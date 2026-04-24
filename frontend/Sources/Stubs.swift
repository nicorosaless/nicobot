import Foundation
import Combine
import SwiftUI

// MARK: - Message sender

enum MessageSender { case user, ai }

// MARK: - Content block (stub — no streaming content blocks in Umi v1)

enum ContentBlock {
    case text(UUID = UUID(), String)
    case toolCall(UUID = UUID(), String, String)
    case thinking(UUID = UUID(), String)
    case discoveryCard(UUID = UUID(), String, String, String)
}

// MARK: - Content block grouping

enum ContentBlockGroup: Identifiable {
    case text(UUID, String)
    case toolCalls(UUID, [ContentBlock])
    case thinking(UUID, String)
    case discoveryCard(UUID, String, String, String)

    var id: UUID {
        switch self {
        case .text(let id, _), .toolCalls(let id, _), .thinking(let id, _), .discoveryCard(let id, _, _, _):
            return id
        }
    }

    static func group(_ blocks: [ContentBlock]) -> [ContentBlockGroup] {
        var groups: [ContentBlockGroup] = []
        var pendingToolCalls: [ContentBlock] = []

        func flushToolCalls() {
            guard !pendingToolCalls.isEmpty else { return }
            // Use first toolCall's UUID for stable ForEach identity across re-renders
            var groupId = UUID()
            if case .toolCall(let id, _, _) = pendingToolCalls[0] { groupId = id }
            groups.append(.toolCalls(groupId, pendingToolCalls))
            pendingToolCalls.removeAll()
        }

        for block in blocks {
            switch block {
            case .toolCall:
                pendingToolCalls.append(block)
            case .text(let id, let text):
                flushToolCalls()
                groups.append(.text(id, text))
            case .thinking(let id, let text):
                flushToolCalls()
                groups.append(.thinking(id, text))
            case .discoveryCard(let id, let title, let subtitle, let body):
                flushToolCalls()
                groups.append(.discoveryCard(id, title, subtitle, body))
            }
        }

        flushToolCalls()
        return groups
    }
}

// MARK: - Recording timer stub

@MainActor
final class RecordingTimer {
    static let shared = RecordingTimer()
    @Published var duration: Double = 0
    private init() {}
}

// MARK: - Notification sound stub

enum NotificationSound: String {
    case `default` = "default"
    case focusLost = "focusLost"
    case focusRegained = "focusRegained"
    case none = "none"

    func playCustomSound() {}
}

// MARK: - Model QoS stub (Umi uses whatever LLM is configured in .env)

enum ModelQoS {
    enum Claude {
        static let defaultSelection = "gpt-4o-mini"
        static let availableModels: [(id: String, label: String)] = [
            ("gpt-4o-mini", "GPT-4o Mini"),
            ("gpt-4o", "GPT-4o"),
        ]
        static func sanitizedSelection(_ value: String?) -> String {
            guard let value, availableModels.contains(where: { $0.id == value }) else {
                return defaultSelection
            }
            return value
        }
    }
}

// MARK: - Subscription stubs (Umi has no subscriptions — always unlimited)

enum SubscriptionPlanType: String { case basic, pro }
enum SubscriptionStatusType: String { case active, inactive }

// MARK: - Notification.Name extensions

extension Notification.Name {
    static let showUsageLimitPopup = Notification.Name("showUsageLimitPopup")
    static let navigateToFloatingBarSettings = Notification.Name("navigateToFloatingBarSettings")
    static let modelTierDidChange = Notification.Name("modelTierDidChange")
}
