import Foundation

// TTS voice playback stub — actual implementation deferred to Umi v1.1.
// All methods are no-ops; the interface is preserved so callers compile.
@MainActor
final class FloatingBarVoicePlaybackService: NSObject {
    static let shared = FloatingBarVoicePlaybackService()

    var isSpeaking: Bool { false }

    private override init() {}

    func playResponseIfEnabled(_ message: ChatMessage?) {}
    func updateStreamingResponseIfEnabled(_ message: ChatMessage?, isFinal: Bool) {}
    func stop() {}
    func interruptCurrentResponse() {}
    func playFillerIfEnabled() {}
    func playVoiceSample(voiceID: String) {}
}
