import AVFoundation
import Foundation

@MainActor
final class FloatingBarVoicePlaybackService: NSObject, AVAudioPlayerDelegate {
    static let shared = FloatingBarVoicePlaybackService()

    private(set) var isSpeaking: Bool = false

    private weak var barState: FloatingControlBarState?
    private var sentenceQueue: [String] = []
    private var audioQueue: [Data] = []
    private var currentPlayer: AVAudioPlayer?
    private var synthesisTask: Task<Void, Never>?
    private var meterTimer: Timer?
    private var processedTextLength: Int = 0
    private var responseId = UUID()

    private override init() { super.init() }

    func configure(barState: FloatingControlBarState) {
        self.barState = barState
    }

    // MARK: - Public interface

    func playResponseIfEnabled(_ message: ChatMessage?) {
        guard let message, !message.text.isEmpty else { return }
        guard ShortcutSettings.shared.hasAnyFloatingBarVoiceAnswersEnabled else { return }
        processedTextLength = 0
        let result = extractCompleteSentences(from: message.text, isFinal: true)
        for s in result.complete { sentenceQueue.append(s) }
        startSynthesisLoopIfNeeded()
    }

    func updateStreamingResponseIfEnabled(_ message: ChatMessage?, isFinal: Bool) {
        guard ShortcutSettings.shared.hasAnyFloatingBarVoiceAnswersEnabled else { return }
        guard let message else { return }

        let text = message.text
        guard text.count > processedTextLength else { return }

        let newText = String(text.dropFirst(processedTextLength))
        let result = extractCompleteSentences(from: newText, isFinal: isFinal)
        processedTextLength = text.count - result.remainder.count

        for s in result.complete { sentenceQueue.append(s) }
        if !sentenceQueue.isEmpty {
            startSynthesisLoopIfNeeded()
        }
    }

    func stop() { interruptCurrentResponse() }

    func interruptCurrentResponse() {
        responseId = UUID()
        synthesisTask?.cancel()
        synthesisTask = nil
        currentPlayer?.stop()
        currentPlayer = nil
        sentenceQueue.removeAll()
        audioQueue.removeAll()
        processedTextLength = 0
        stopMeterTimer()
        isSpeaking = false
        barState?.isSpeaking = false
        barState?.speakingLevel = 0
    }

    func playFillerIfEnabled() {
        processedTextLength = 0
        responseId = UUID()
    }

    func playVoiceSample(voiceID: String) {
        interruptCurrentResponse()
        let sampleText = "Hello, I'm your AI assistant. How can I help you today?"
        sentenceQueue.append(sampleText)
        startSynthesisLoopIfNeeded()
    }

    // MARK: - Synthesis loop

    private func startSynthesisLoopIfNeeded() {
        guard synthesisTask == nil else { return }
        let currentResponseId = responseId

        synthesisTask = Task { [weak self] in
            while let self, !Task.isCancelled, self.responseId == currentResponseId {
                guard let sentence = self.sentenceQueue.first else {
                    break
                }
                self.sentenceQueue.removeFirst()

                do {
                    let request = APIClient.TtsSynthesizeRequest(
                        text: sentence,
                        voiceId: ShortcutSettings.shared.selectedVoiceID,
                        modelId: "eleven_multilingual_v2",
                        outputFormat: "mp3_44100_128",
                        voiceSettings: .init(
                            stability: 0.5,
                            similarityBoost: 0.75,
                            style: 0.0,
                            useSpeakerBoost: true
                        )
                    )
                    let audioData = try await APIClient.shared.synthesizeSpeech(request: request)
                    guard self.responseId == currentResponseId, !Task.isCancelled else { break }

                    if !audioData.isEmpty {
                        self.audioQueue.append(audioData)
                        if self.currentPlayer == nil || !self.currentPlayer!.isPlaying {
                            self.playNextChunk()
                        }
                    }
                } catch {
                    break
                }
            }

            if let self, self.responseId == currentResponseId {
                self.synthesisTask = nil
            }
        }
    }

    // MARK: - Playback

    private func playNextChunk() {
        guard let data = audioQueue.first else {
            isSpeaking = false
            barState?.isSpeaking = false
            barState?.speakingLevel = 0
            stopMeterTimer()
            return
        }
        audioQueue.removeFirst()

        do {
            let player = try AVAudioPlayer(data: data)
            player.delegate = self
            player.isMeteringEnabled = true
            player.enableRate = true
            player.rate = ShortcutSettings.shared.voicePlaybackSpeed
            player.prepareToPlay()
            player.play()
            currentPlayer = player
            isSpeaking = true
            barState?.isSpeaking = true
            startMeterTimer()
        } catch {
            playNextChunk()
        }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.currentPlayer = nil
            self.playNextChunk()
        }
    }

    // MARK: - Metering

    private func startMeterTimer() {
        meterTimer?.invalidate()
        meterTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let player = self.currentPlayer, player.isPlaying else { return }
                player.updateMeters()
                let power = player.averagePower(forChannel: 0)
                let linear = max(0, min(1, (power + 50) / 50))
                self.barState?.speakingLevel = linear
            }
        }
    }

    private func stopMeterTimer() {
        meterTimer?.invalidate()
        meterTimer = nil
    }

    // MARK: - Sentence extraction

    private struct SentenceResult {
        let complete: [String]
        let remainder: String
    }

    private func extractCompleteSentences(from text: String, isFinal: Bool) -> SentenceResult {
        var complete: [String] = []
        var remaining = text

        while let range = remaining.rangeOfCharacter(from: CharacterSet(charactersIn: ".!?\n")) {
            let sentence = String(remaining[remaining.startIndex...range.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if sentence.count > 1 {
                complete.append(sentence)
            }
            remaining = String(remaining[remaining.index(after: range.lowerBound)...])
        }

        if isFinal {
            let finalSentence = remaining.trimmingCharacters(in: .whitespacesAndNewlines)
            if finalSentence.count > 1 {
                complete.append(finalSentence)
            }
            return SentenceResult(complete: complete, remainder: "")
        }

        return SentenceResult(complete: complete, remainder: remaining)
    }

}
