import Foundation

@MainActor
class AnalyticsManager {
    static let shared = AnalyticsManager()
    private init() {}

    func initialize() {}
    func identify(userId: String? = nil) {}
    func reset() {}
    func track(_ event: String, properties: [String: Any]? = nil) {}
    func trackScreen(_ name: String) {}

    // Floating bar events (all no-ops)
    func floatingBarToggled(visible: Bool, source: String) {}
    func floatingBarAskOmiOpened(source: String) {}
    func floatingBarAskOmiClosed() {}
    func floatingBarQuerySent(messageLength: Int, hasScreenshot: Bool) {}
    func floatingBarPTTStarted(mode: String) {}
    func floatingBarPTTFinalized(transcript: String) {}
    func floatingBarPTTEnded(mode: String, hadTranscript: Bool, transcriptLength: Int) {}
    func notificationSent(notificationId: String, title: String, assistantId: String, surface: String) {}
    func notificationClicked(notificationId: String, title: String, assistantId: String, surface: String) {}
    func notificationDismissed(notificationId: String, title: String, assistantId: String, surface: String) {}
}
