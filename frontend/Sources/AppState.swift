import SwiftUI

@MainActor
class AppState: ObservableObject {
    static weak var current: AppState?

    @AppStorage("hasCompletedOnboarding") var hasCompletedOnboarding = false

    // Legacy floating bar state (unused in Umi v1, kept for compatibility)
    @Published var isSavingConversation: Bool = false
    @Published var isTranscribing: Bool = false

    init() {
        AppState.current = self
    }

    func resetOnboardingAndRestart() {
        hasCompletedOnboarding = false
    }

    func toggleTranscription() {
        isTranscribing.toggle()
    }
}
