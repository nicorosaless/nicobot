import Foundation

actor APIClient {
    static let shared = APIClient()

    let baseURL = "http://localhost:10201"

    func get<T: Decodable>(_ path: String) async throws -> T {
        let url = URL(string: "\(baseURL)\(path)")!
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(T.self, from: data)
    }

    func post<B: Encodable, T: Decodable>(_ path: String, body: B) async throws -> T {
        var req = URLRequest(url: URL(string: "\(baseURL)\(path)")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(body)
        let (data, _) = try await URLSession.shared.data(for: req)
        return try JSONDecoder().decode(T.self, from: data)
    }

    // MARK: - TTS (stub — returns empty data, TTS not yet implemented in Umi v1)

    struct TtsSynthesizeRequest {
        let text: String
        let voiceId: String
        let modelId: String
        let outputFormat: String
        struct VoiceSettings {
            let stability: Float
            let similarityBoost: Float
            let style: Float
            let useSpeakerBoost: Bool
        }
        let voiceSettings: VoiceSettings?
    }

    func synthesizeSpeech(request: TtsSynthesizeRequest) async throws -> Data {
        return Data()
    }

    // MARK: - Share (stub)

    struct ShareResponse { let url: String }
    func shareChatMessages(messageIds: [String]) async throws -> ShareResponse {
        return ShareResponse(url: "")
    }

    // MARK: - Subscription stubs (Umi has no subscriptions)

    struct SubscriptionResponse: Decodable {
        struct Subscription: Decodable {
            let plan: String
            let status: String
        }
        let subscription: Subscription
    }

    func getUserSubscription() async throws -> SubscriptionResponse {
        return SubscriptionResponse(
            subscription: .init(plan: "pro", status: "active")
        )
    }

    struct ChatUsageQuota: Decodable {
        let used: Double
        let limit: Double?
        let unit: String
        let plan: String
        let allowed: Bool
    }

    func fetchChatUsageQuota() async -> ChatUsageQuota? {
        return ChatUsageQuota(used: 0, limit: nil, unit: "questions", plan: "pro", allowed: true)
    }
}
