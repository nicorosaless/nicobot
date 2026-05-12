import Combine
import SwiftUI

/// Visual mode for the animated floating bar.
enum ActiveBarMode: Hashable {
    case idle
    case listening    // PTT recording mic input
    case processing   // waiting for AI (isAILoading)
    case responding   // AI streaming text (TTS not yet playing)
    case speaking     // TTS audio actively playing
    case done         // AI response complete, conversation still open
}

/// A single question/answer exchange in the floating bar chat history.
struct FloatingChatExchange: Identifiable {
    let id = UUID()
    let question: String?
    let questionMessageId: String?
    let aiMessage: ChatMessage
}

/// Hidden provenance carried with a floating-bar notification so follow-up
/// questions can explain where the notification came from without guessing.
struct FloatingBarNotificationContext: Equatable {
    let sourceTitle: String
    let assistantId: String
    let sourceApp: String?
    let windowTitle: String?
    let contextSummary: String?
    let currentActivity: String?
    let reasoning: String?
    let detail: String?
}

/// A custom in-app notification rendered directly below the floating bar.
struct FloatingBarNotification: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let message: String
    let assistantId: String
    let context: FloatingBarNotificationContext?
    /// Screenshot JPEG data from the moment the notification was generated (not shown in UI)
    let screenshotData: Data?

    init(
        title: String,
        message: String,
        assistantId: String,
        context: FloatingBarNotificationContext? = nil,
        screenshotData: Data? = nil
    ) {
        self.title = title
        self.message = message
        self.assistantId = assistantId
        self.context = context
        self.screenshotData = screenshotData
    }

    static func == (lhs: FloatingBarNotification, rhs: FloatingBarNotification) -> Bool {
        lhs.id == rhs.id
    }
}

/// Observable object holding the state for the floating control bar.
@MainActor
class FloatingControlBarState: NSObject, ObservableObject {
    static let visibleConversationReuseInterval: TimeInterval = 10 * 60

    @Published var isRecording: Bool = false
    @Published var duration: Int = 0
    @Published var isInitialising: Bool = false
    @Published var isDragging: Bool = false
    @Published var isHoveringBar: Bool = false
    @Published var requiresHoverReset: Bool = false
    @Published var currentNotification: FloatingBarNotification? = nil

    // AI conversation state
    @Published var showingAIConversation: Bool = false
    @Published var showingAIResponse: Bool = false
    @Published var isAILoading: Bool = true
    @Published var aiInputText: String = ""
    @Published var currentAIMessage: ChatMessage? = nil
    @Published var displayedQuery: String = ""
    @Published var currentQuestionMessageId: String? = nil
    @Published var inputViewHeight: CGFloat = 120
    @Published var responseContentHeight: CGFloat = 0
    @Published var chatHistory: [FloatingChatExchange] = []
    @Published var lastConversationActivityAt: Date? = nil

    var aiResponseText: String {
        get { currentAIMessage?.text ?? "" }
        set {
            if currentAIMessage != nil {
                currentAIMessage?.text = newValue
            } else {
                currentAIMessage = ChatMessage(text: newValue, sender: .ai)
            }
        }
    }

    // Push-to-talk state
    @Published var isVoiceListening: Bool = false
    @Published var isVoiceLocked: Bool = false
    @Published var voiceTranscript: String = ""
    @Published var micLevel: Float = 0.0  // 0.0–1.0 for waveform animation
    @Published var isSpeaking: Bool = false
    @Published var speakingLevel: Float = 0.0  // 0.0–1.0 from TTS playback metering

    // Voice follow-up state (PTT while AI conversation is active)
    @Published var isVoiceFollowUp: Bool = false
    @Published var voiceFollowUpTranscript: String = ""

    /// Whether the current query originated from voice (PTT). Used to decide
    /// whether voice responses should play for this particular query.
    @Published var currentQueryFromVoice: Bool = false

    @Published var selectedModel: String = ModelQoS.Claude.defaultSelection
    static var availableModels: [(id: String, label: String)] { ModelQoS.Claude.availableModels }

    /// Whether the expandable transcript panel is visible below the bar.
    @Published var isTranscriptExpanded: Bool = false

    var activeBarMode: ActiveBarMode {
        if isVoiceListening { return .listening }
        if isAILoading { return .processing }
        if isSpeaking { return .speaking }
        if let msg = currentAIMessage, msg.isStreaming { return .responding }
        if showingAIConversation && currentAIMessage != nil { return .done }
        return .idle
    }

    var isShowingNotification: Bool {
        currentNotification != nil
    }

    var hasVisibleConversation: Bool {
        !chatHistory.isEmpty || currentAIMessage != nil || !displayedQuery.isEmpty
    }

    var canRestoreVisibleConversation: Bool {
        guard hasVisibleConversation, let lastConversationActivityAt else { return false }
        return Date().timeIntervalSince(lastConversationActivityAt) <= Self.visibleConversationReuseInterval
    }

    func markConversationActivity(at date: Date = Date()) {
        lastConversationActivityAt = date
    }

    func clearVisibleConversation() {
        isTranscriptExpanded = false
        aiInputText = ""
        displayedQuery = ""
        currentAIMessage = nil
        currentQuestionMessageId = nil
        chatHistory = []
        showingAIResponse = false
        isAILoading = false
        isVoiceFollowUp = false
        voiceFollowUpTranscript = ""
        currentQueryFromVoice = false
        isSpeaking = false
        speakingLevel = 0.0
        lastConversationActivityAt = nil
    }
}
