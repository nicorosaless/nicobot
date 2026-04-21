import Foundation

// MARK: - BYOK providers

enum BYOKProvider: String, CaseIterable {
    case openai
    case anthropic
    case gemini
    case deepgram

    var storageKey: String {
        switch self {
        case .openai: return "dev_openai_api_key"
        case .anthropic: return "dev_anthropic_api_key"
        case .gemini: return "dev_gemini_api_key"
        case .deepgram: return "dev_deepgram_api_key"
        }
    }

    var headerName: String {
        switch self {
        case .openai: return "X-BYOK-OpenAI"
        case .anthropic: return "X-BYOK-Anthropic"
        case .gemini: return "X-BYOK-Gemini"
        case .deepgram: return "X-BYOK-Deepgram"
        }
    }

    var displayName: String {
        switch self {
        case .openai: return "OpenAI"
        case .anthropic: return "Anthropic"
        case .gemini: return "Gemini"
        case .deepgram: return "Deepgram"
        }
    }

    var key: String { UserDefaults.standard.string(forKey: storageKey) ?? "" }
    var hasKey: Bool { !key.isEmpty }
}

// MARK: - APIKeyService

// Reads BYOK keys from UserDefaults (set via Settings > API Keys).
// Keys are forwarded as headers to the local backend.
@MainActor
final class APIKeyService: ObservableObject {
    static let shared = APIKeyService()

    @Published var openaiApiKey: String = ""
    @Published var anthropicApiKey: String = ""
    @Published var geminiApiKey: String = ""

    private init() {
        refresh()
    }

    func refresh() {
        openaiApiKey = UserDefaults.standard.string(forKey: BYOKProvider.openai.storageKey) ?? ""
        anthropicApiKey = UserDefaults.standard.string(forKey: BYOKProvider.anthropic.storageKey) ?? ""
        geminiApiKey = UserDefaults.standard.string(forKey: BYOKProvider.gemini.storageKey) ?? ""
    }

    var byokHeaders: [String: String] {
        var headers: [String: String] = [:]
        for provider in BYOKProvider.allCases {
            if provider.hasKey {
                headers[provider.headerName] = provider.key
            }
        }
        return headers
    }
}
