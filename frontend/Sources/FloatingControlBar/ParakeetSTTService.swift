import AVFoundation
import Accelerate
import Foundation
#if canImport(OnnxRuntimeBindings)
import OnnxRuntimeBindings
#elseif canImport(onnxruntime)
import onnxruntime
#endif

// MARK: - Parakeet v3 TDT STT Service
//
// Pipeline:
//   raw PCM 16kHz → nemo128.onnx → mel [1,128,T]
//   mel → parakeet-encoder.int8.onnx → enc [1,1024,T']
//   enc → parakeet-decoder-joint.int8.onnx (greedy TDT) → text
//
// All heavy work (model load + inference) runs on a background queue.
// Only audio capture and UI callbacks run on MainActor.

final class ParakeetSTTService {
    static let shared = ParakeetSTTService()

    // MARK: - State (main thread only)
    private var updateHandler: ((String) -> Void)?
    private var levelCallback: ((Float) -> Void)?
    private var audioEngine: AVAudioEngine?
    private var audioBuffer: [Float] = []
    private let bufferLock = NSLock()

#if canImport(OnnxRuntimeBindings) || canImport(onnxruntime)
    // MARK: - ONNX sessions (accessed only on modelQueue)
    private var ortEnv: ORTEnv?
    private var nemoSession: ORTSession?
    private var encoderSession: ORTSession?
    private var decoderSession: ORTSession?
    private var vocab: [Int: String] = [:]
    private let blankId: Int = 8192

    private let modelQueue = DispatchQueue(label: "parakeet.model", qos: .userInitiated)
    private var isModelReady = false
    private var isLoading = false
    private var hardwareSampleRate: Double = 44100

    private init() {}

    // MARK: - Public API (call from any context)

    /// Pre-warm: load models in background without starting capture. Call at app startup.
    func preload() async {
        guard !isModelReady, !isLoading else { return }
        isLoading = true
        let ok = await loadModelsAsync()
        isLoading = false
        if ok { isModelReady = true }
        log("ParakeetSTT: preload done, ready=\(isModelReady)")
    }

    func start(
        updateHandler: @escaping (String) -> Void,
        levelCallback: ((Float) -> Void)? = nil
    ) async {
        self.updateHandler = updateHandler
        self.levelCallback = levelCallback
        bufferLock.lock(); audioBuffer = []; bufferLock.unlock()

        if !isModelReady {
            // If preload is in progress, wait for it rather than returning early
            if isLoading {
                updateHandler("🔄 Cargando modelo STT...")
                while isLoading {
                    try? await Task.sleep(nanoseconds: 200_000_000)
                }
            }
            if !isModelReady {
                isLoading = true
                updateHandler("🔄 Cargando modelo STT (~3s)...")
                let ok = await loadModelsAsync()
                isLoading = false
                guard ok else { return }
                isModelReady = true
            }
        }

        startCapture()
        updateHandler("🎤 Escuchando...")
    }

    func stop() async -> String {
        let samples = stopCapture()
        log("ParakeetSTT: stop() samples=\(samples.count), modelReady=\(isModelReady)")
        guard isModelReady, !samples.isEmpty else { return "" }
        updateHandler?("🔄 Transcribiendo...")
        let text = await withCheckedContinuation { cont in
            modelQueue.async {
                let result = self.transcribeSync(samples: samples)
                cont.resume(returning: result)
            }
        }
        return text
    }

    // MARK: - Model Loading (background)

    private static func modelDir() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Umi/Models")
    }

    private func loadModelsAsync() async -> Bool {
        let dir = ParakeetSTTService.modelDir()
        return await withCheckedContinuation { cont in
            modelQueue.async {
                let ok = self.loadModelsSync(dir: dir)
                cont.resume(returning: ok)
            }
        }
    }

    private func loadModelsSync(dir: URL) -> Bool {
        let names = [
            ("nemo128.onnx",                   "preprocessor"),
            ("parakeet-encoder.int8.onnx",     "encoder"),
            ("parakeet-decoder-joint.int8.onnx","decoder"),
        ]
        for (name, label) in names {
            if !FileManager.default.fileExists(atPath: dir.appendingPathComponent(name).path) {
                DispatchQueue.main.async {
                    self.updateHandler?("❌ Modelo faltante: \(name)")
                }
                log("ParakeetSTT: missing \(label)")
                return false
            }
        }
        do {
            let env = try ORTEnv(loggingLevel: .warning)
            let opts = try ORTSessionOptions()
            try opts.setIntraOpNumThreads(4)

            let nemo = try ORTSession(env: env, modelPath: dir.appendingPathComponent("nemo128.onnx").path, sessionOptions: opts)
            let encoder = try ORTSession(env: env, modelPath: dir.appendingPathComponent("parakeet-encoder.int8.onnx").path, sessionOptions: opts)
            let decoder = try ORTSession(env: env, modelPath: dir.appendingPathComponent("parakeet-decoder-joint.int8.onnx").path, sessionOptions: opts)
            self.ortEnv = env
            self.nemoSession = nemo
            self.encoderSession = encoder
            self.decoderSession = decoder
            self.vocab = self.loadVocabSync(dir: dir)
            log("ParakeetSTT: models loaded, vocab=\(self.vocab.count)")
            return true
        } catch {
            DispatchQueue.main.async { self.updateHandler?("❌ Error cargando modelo: \(error.localizedDescription)") }
            logError("ParakeetSTT: model load failed", error: error)
            return false
        }
    }

    private func loadVocabSync(dir: URL) -> [Int: String] {
        let path = dir.appendingPathComponent("parakeet-vocab.txt").path
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return [:] }
        var result: [Int: String] = [:]
        for line in content.components(separatedBy: "\n") {
            let parts = line.split(separator: " ", maxSplits: 1)
            if parts.count == 2, let id = Int(parts[1]) {
                result[id] = String(parts[0])
            }
        }
        return result
    }

    // MARK: - Audio Capture (MainActor)

    private func startCapture() {
        // Tear down any existing engine to prevent dual-tap crash
        if let old = audioEngine {
            old.inputNode.removeTap(onBus: 0)
            old.stop()
            audioEngine = nil
        }

        let engine = AVAudioEngine()
        let input = engine.inputNode
        // Always use the hardware's native format — requesting a custom format crashes.
        // We resample to 16kHz later in the inference pipeline.
        let hwFmt = input.outputFormat(forBus: 0)
        hardwareSampleRate = hwFmt.sampleRate

        input.installTap(onBus: 0, bufferSize: 1024, format: hwFmt) { [weak self] buffer, _ in
            guard let self, let channelData = buffer.floatChannelData else { return }
            let count = Int(buffer.frameLength)
            // Take channel 0 (works for both mono and stereo hardware)
            let samples = Array(UnsafeBufferPointer(start: channelData[0], count: count))

            var rms: Float = 0
            vDSP_rmsqv(samples, 1, &rms, vDSP_Length(count))
            let level = min(rms * 10, 1.0)

            self.bufferLock.lock()
            self.audioBuffer.append(contentsOf: samples)
            self.bufferLock.unlock()

            DispatchQueue.main.async { self.levelCallback?(level) }
        }
        do {
            engine.prepare()
            try engine.start()
            audioEngine = engine
        } catch {
            logError("ParakeetSTT: audio engine failed", error: error)
        }
    }

    private func stopCapture() -> [Float] {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        DispatchQueue.main.async { self.levelCallback?(0) }
        bufferLock.lock()
        let s = audioBuffer
        audioBuffer = []
        bufferLock.unlock()
        return s
    }

    // MARK: - Audio Resampling

    private func resampleTo16k(_ samples: [Float], fromRate: Double) -> [Float] {
        guard fromRate != 16000, !samples.isEmpty else { return samples }
        guard let srcFmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: fromRate, channels: 1, interleaved: false),
              let dstFmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: srcFmt, to: dstFmt) else { return samples }
        let inCount = AVAudioFrameCount(samples.count)
        let outCount = AVAudioFrameCount(Double(samples.count) * 16000.0 / fromRate) + 1
        guard let srcBuf = AVAudioPCMBuffer(pcmFormat: srcFmt, frameCapacity: inCount),
              let dstBuf = AVAudioPCMBuffer(pcmFormat: dstFmt, frameCapacity: outCount) else { return samples }
        srcBuf.frameLength = inCount
        _ = samples.withUnsafeBufferPointer { ptr in
            memcpy(srcBuf.floatChannelData![0], ptr.baseAddress!, samples.count * 4)
        }
        var done = false
        var error: NSError?
        converter.convert(to: dstBuf, error: &error) { _, status in
            if done { status.pointee = .endOfStream; return nil }
            done = true; status.pointee = .haveData; return srcBuf
        }
        guard error == nil, dstBuf.frameLength > 0 else { return samples }
        return Array(UnsafeBufferPointer(start: dstBuf.floatChannelData![0], count: Int(dstBuf.frameLength)))
    }

    // MARK: - Inference (modelQueue)

    private func transcribeSync(samples: [Float]) -> String {
        guard let nemo = nemoSession, let enc = encoderSession, let dec = decoderSession else {
            log("ParakeetSTT: sessions nil"); return ""
        }
        do {
            let resampled = resampleTo16k(samples, fromRate: hardwareSampleRate)
            log("ParakeetSTT: raw=\(samples.count) @\(hardwareSampleRate)Hz → resampled=\(resampled.count) @16kHz")

            // 1. nemo128: PCM → mel [1, 128, T]
            let N = resampled.count
            let wavTensor = try resampled.withUnsafeBufferPointer { ptr in
                try ORTValue(
                    tensorData: NSMutableData(bytes: ptr.baseAddress!, length: N * 4),
                    elementType: .float, shape: [1, NSNumber(value: N)]
                )
            }
            var wavLen = Int64(N)
            let wavLenTensor = try ORTValue(
                tensorData: NSMutableData(bytes: &wavLen, length: 8),
                elementType: .int64, shape: [1]
            )
            let nemoOut = try nemo.run(
                withInputs: ["waveforms": wavTensor, "waveforms_lens": wavLenTensor],
                outputNames: Set(["features", "features_lens"]), runOptions: nil
            )
            guard let featVal = nemoOut["features"], let featLenVal = nemoOut["features_lens"] else { return "" }
            let featData = try featVal.tensorData() as Data
            let T = (try featLenVal.tensorData() as Data).withUnsafeBytes { Int($0.load(as: Int64.self)) }
            var mel = featData.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
            log("ParakeetSTT: mel T=\(T), mel.count=\(mel.count) (expect \(128*T))")

            // 2. Encoder: mel → enc_out [1, 1024, T']
            let encInTensor = try ORTValue(
                tensorData: NSMutableData(bytes: &mel, length: mel.count * 4),
                elementType: .float, shape: [1, 128, NSNumber(value: T)]
            )
            var encLen = Int64(T)
            let encLenTensor = try ORTValue(
                tensorData: NSMutableData(bytes: &encLen, length: 8),
                elementType: .int64, shape: [1]
            )
            let encOut = try enc.run(
                withInputs: ["audio_signal": encInTensor, "length": encLenTensor],
                outputNames: Set(["outputs", "encoded_lengths"]), runOptions: nil
            )
            guard let encVal = encOut["outputs"], let encLenVal = encOut["encoded_lengths"] else { return "" }
            let encData = try encVal.tensorData() as Data
            let Tprime = (try encLenVal.tensorData() as Data).withUnsafeBytes { Int($0.load(as: Int64.self)) }
            let encFlat = encData.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
            log("ParakeetSTT: enc Tprime=\(Tprime), encFlat.count=\(encFlat.count)")

            // 3. TDT greedy decode
            let result = try greedyDecodeSync(encFlat: encFlat, Tprime: Tprime, dec: dec)
            log("ParakeetSTT: decoded '\(result)' (\(result.count) chars)")
            return result
        } catch {
            logError("ParakeetSTT: transcription failed", error: error)
            return ""
        }
    }

    private func greedyDecodeSync(encFlat: [Float], Tprime: Int, dec: ORTSession) throws -> String {
        let dim = 1024
        let stateLen = 2 * 1 * 640
        var st1 = [Float](repeating: 0, count: stateLen)
        var st2 = [Float](repeating: 0, count: stateLen)
        var prevToken: Int32 = Int32(blankId)
        var hypothesis: [Int] = []
        let maxPerFrame = 10
        // TDT duration bins: index 0→skip 0, 1→skip 1, …, 4→skip 4
        let durations = [0, 1, 2, 3, 4]

        var t = 0
        while t < Tprime {
            var frame = [Float](repeating: 0, count: dim)
            for k in 0..<dim { frame[k] = encFlat[k * Tprime + t] }

            var advanced = false
            for _ in 0..<maxPerFrame {
                let frameTensor = try ORTValue(
                    tensorData: NSMutableData(bytes: &frame, length: dim * 4),
                    elementType: .float, shape: [1, 1024, 1]
                )
                var tgt = prevToken
                let tgtTensor = try ORTValue(
                    tensorData: NSMutableData(bytes: &tgt, length: 4),
                    elementType: .int32, shape: [1, 1]
                )
                var tgtLen: Int32 = 1
                let tgtLenTensor = try ORTValue(
                    tensorData: NSMutableData(bytes: &tgtLen, length: 4),
                    elementType: .int32, shape: [1]
                )
                let st1Tensor = try ORTValue(
                    tensorData: NSMutableData(bytes: &st1, length: stateLen * 4),
                    elementType: .float, shape: [2, 1, 640]
                )
                let st2Tensor = try ORTValue(
                    tensorData: NSMutableData(bytes: &st2, length: stateLen * 4),
                    elementType: .float, shape: [2, 1, 640]
                )
                let decOut = try dec.run(
                    withInputs: [
                        "encoder_outputs": frameTensor,
                        "targets": tgtTensor,
                        "target_length": tgtLenTensor,
                        "input_states_1": st1Tensor,
                        "input_states_2": st2Tensor,
                    ],
                    outputNames: Set(["outputs", "output_states_1", "output_states_2"]),
                    runOptions: nil
                )
                guard let logitsVal = decOut["outputs"] else { break }
                let logitsData = try logitsVal.tensorData() as Data
                let logits = logitsData.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }

                let vocabLogits = Array(logits.prefix(8193))
                let durLogits = Array(logits.suffix(5))
                let token = vocabLogits.indices.max(by: { vocabLogits[$0] < vocabLogits[$1] }) ?? blankId
                let durIdx = durLogits.indices.max(by: { durLogits[$0] < durLogits[$1] }) ?? 1
                let dur = durations[min(durIdx, durations.count - 1)]

                if token == blankId {
                    // Blank: do NOT update LSTM states or prevToken
                    t += max(dur, 1)
                    advanced = true
                    break
                }

                // Non-blank: update LSTM states only for emitted tokens
                if let sv = decOut["output_states_1"] {
                    st1 = (try sv.tensorData() as Data).withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
                }
                if let sv = decOut["output_states_2"] {
                    st2 = (try sv.tensorData() as Data).withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
                }

                hypothesis.append(token)
                prevToken = Int32(token)

                if dur > 0 {
                    t += dur
                    advanced = true
                    break
                }
            }
            if !advanced { t += 1 }
        }
        log("ParakeetSTT: TDT decode produced \(hypothesis.count) tokens from \(Tprime) frames")
        return decodeTokens(hypothesis)
    }

    private func decodeTokens(_ ids: [Int]) -> String {
        let skip: Set<String> = ["<unk>", "<pad>", "<blk>", "<|nospeech|>",
                                  "<|endoftext|>", "<|startoftranscript|>"]
        return ids.compactMap { id -> String? in
            guard let tok = vocab[id], !skip.contains(tok) else { return nil }
            return tok.replacingOccurrences(of: "▁", with: " ")
        }.joined().trimmingCharacters(in: .whitespaces)
    }

#else
    private init() {}
    func start(updateHandler: @escaping (String) -> Void, levelCallback: ((Float) -> Void)? = nil) async {
        updateHandler("⚠️ ONNX Runtime no disponible")
    }
    func stop() async -> String { return "" }
#endif
}
