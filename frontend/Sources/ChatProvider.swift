import Foundation
import SwiftUI

struct ChatMessage: Identifiable {
    let id: String = UUID().uuidString
    let role: String  // "user" | "assistant"
    var content: String
    let createdAt = Date()

    // Legacy floating bar interface
    var text: String {
        get { content }
        set { content = newValue }
    }
    var sender: MessageSender { role == "user" ? .user : .ai }
    var contentBlocks: [ContentBlock] { [] }
    var isStreaming: Bool = false
    var isSynced: Bool { true }

    init(role: String, content: String) {
        self.role = role
        self.content = content
    }

    init(text: String, sender: MessageSender) {
        self.role = sender == .user ? "user" : "assistant"
        self.content = text
    }
}

struct ChatStreamRequest: Encodable {
    let text: String
    let sessionId: String?

    enum CodingKeys: String, CodingKey {
        case text
        case sessionId = "session_id"
    }

    func encodedData() throws -> Data {
        try JSONEncoder().encode(self)
    }
}

private struct ChatMessageResponse: Decodable {
    let sessionId: String
    let messageId: String
    let response: String

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case messageId = "message_id"
        case response
    }
}

@MainActor
class ChatProvider: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var isLoading = false
    @Published var sessionId: String?
    @Published var errorMessage: String?
    @Published var backendHealthy = false
    @Published var hermesHealthy = false
    @Published var connectionMessage = "Comprobando servicios..."

    // Legacy floating bar properties
    var isSending: Bool { isLoading }
    var modelOverride: String? = nil
    var workingDirectory: String? = nil
    static var floatingBarSystemPromptPrefix: String { "" }

    private let baseURL = "http://127.0.0.1:10201"

    func initialize() {
        Task {
            await refreshConnectionStatus()
            await createSession()
        }
    }

    func refreshConnectionStatus() async {
        async let backend = checkJSONEndpoint("/health")
        async let hermes = checkJSONEndpoint("/v1/hermes/health")

        let backendOK = await backend
        let hermesOK = await hermes
        backendHealthy = backendOK
        hermesHealthy = hermesOK

        if backendOK && hermesOK {
            connectionMessage = "Backend y Hermes conectados"
        } else if backendOK {
            connectionMessage = "Backend conectado, Hermes no responde"
        } else {
            connectionMessage = "Backend local no responde"
        }
    }

    func createSession() async {
        guard let url = URL(string: "\(baseURL)/v1/chat/sessions") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: [:])
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let id = json["session_id"] as? String {
                sessionId = id
            }
        } catch {
            logError("ChatProvider: failed to create session", error: error)
        }
    }

    func sendMessage(
        _ text: String,
        model: String? = nil,
        systemPromptSuffix: String? = nil,
        systemPromptPrefix: String? = nil,
        sessionKey: String? = nil,
        imageData: Data? = nil
    ) async {
        await sendMessageStreaming(text)
    }

    private func sendMessageStreaming(_ text: String) async {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        await refreshConnectionStatus()
        guard backendHealthy else {
            errorMessage = "No se pudo conectar al backend local en 127.0.0.1:10201. Vuelve a ejecutar ./run.sh."
            return
        }

        log("ChatProvider: sending stream request")
        messages.append(ChatMessage(role: "user", content: text))
        isLoading = true
        errorMessage = nil

        guard let url = URL(string: "\(baseURL)/v1/chat/stream") else {
            isLoading = false; return
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            req.httpBody = try ChatStreamRequest(text: text, sessionId: sessionId).encodedData()
        } catch {
            errorMessage = "No se pudo preparar el mensaje para enviar."
            isLoading = false
            return
        }

        var assistantMsg = ChatMessage(role: "assistant", content: "")
        assistantMsg.isStreaming = true
        messages.append(assistantMsg)
        let idx = messages.count - 1

        do {
            let (bytes, response) = try await URLSession.shared.bytes(for: req)
            guard let http = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }
            log("ChatProvider: stream HTTP \(http.statusCode)")
            guard (200..<300).contains(http.statusCode) else {
                let body = try await readErrorBody(from: bytes)
                messages[idx].isStreaming = false
                errorMessage = body.isEmpty
                    ? "El backend respondió con HTTP \(http.statusCode)."
                    : "El backend respondió con HTTP \(http.statusCode): \(body)"
                isLoading = false
                return
            }

            var currentEvent = ""
            var currentData = ""
            var tokenCount = 0

            for try await line in bytes.lines {
                if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    // Blank line = end of SSE event
                    if currentEvent == "tok" {
                        await appendAssistantToken(currentData, at: idx)
                        tokenCount += 1
                    } else if currentEvent == "done" {
                        if let d = currentData.data(using: .utf8),
                           let json = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                           let sid = json["session_id"] as? String {
                            sessionId = sid
                        }
                        messages[idx].isStreaming = false
                        isLoading = false
                        log("ChatProvider: stream done tokens=\(tokenCount) chars=\(messages[idx].content.count)")
                        return
                    }
                    currentEvent = ""
                    currentData = ""
                } else if line.hasPrefix("event:") {
                    currentEvent = line.dropFirst(6).trimmingCharacters(in: .whitespaces)
                } else if line.hasPrefix("data:") {
                    if !currentData.isEmpty {
                        currentData += "\n"
                    }
                    currentData += String(line.dropFirst(5).trimmingCharacters(in: .init(charactersIn: " ")))
                }
            }
            // Stream ended without explicit done
            if currentEvent == "tok" {
                await appendAssistantToken(currentData, at: idx)
                tokenCount += 1
            }
            messages[idx].isStreaming = false
            if messages[idx].content.isEmpty {
                log("ChatProvider: empty stream, requesting non-streaming fallback")
                await fillAssistantFromMessageFallback(text: text, at: idx)
            } else {
                isLoading = false
            }
            log("ChatProvider: stream ended without done tokens=\(tokenCount) chars=\(messages[idx].content.count)")
        } catch {
            messages[idx].isStreaming = false
            if messages[idx].content.isEmpty {
                errorMessage = "No se pudo conectar al backend. ¿Está corriendo run.sh?"
            }
            isLoading = false
            logError("ChatProvider: stream failed", error: error)
        }
    }

    private func fillAssistantFromMessageFallback(text: String, at index: Int) async {
        guard let url = URL(string: "\(baseURL)/v1/chat/message") else {
            errorMessage = "No se pudo construir la URL de fallback."
            isLoading = false
            return
        }

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = 60
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try ChatStreamRequest(text: text, sessionId: sessionId).encodedData()

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }
            guard (200..<300).contains(http.statusCode) else {
                let body = String(data: data, encoding: .utf8) ?? ""
                throw NSError(
                    domain: "ChatProvider",
                    code: http.statusCode,
                    userInfo: [NSLocalizedDescriptionKey: body.isEmpty ? "HTTP \(http.statusCode)" : body]
                )
            }

            let decoded = try JSONDecoder().decode(ChatMessageResponse.self, from: data)
            sessionId = decoded.sessionId
            if messages.indices.contains(index), !decoded.response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                var updated = messages[index]
                updated.content = ""
                updated.isStreaming = false
                messages[index] = updated
                errorMessage = nil
                await revealAssistantText(decoded.response, at: index)
                log("ChatProvider: fallback message filled chars=\(decoded.response.count)")
            } else {
                errorMessage = "Hermes respondió sin texto."
            }
        } catch {
            if messages.indices.contains(index), messages[index].content.isEmpty {
                errorMessage = "El backend cerró el stream sin devolver texto."
            }
            logError("ChatProvider: fallback message failed", error: error)
        }
        isLoading = false
    }

    private func appendAssistantToken(_ token: String, at index: Int) async {
        guard messages.indices.contains(index), !token.isEmpty else { return }
        var updated = messages[index]
        updated.content += token
        messages[index] = updated
        await pauseForVisibleStreaming()
    }

    private func revealAssistantText(_ text: String, at index: Int) async {
        for chunk in displayChunks(for: text) {
            await appendAssistantToken(chunk, at: index)
        }
    }

    private func displayChunks(for text: String) -> [String] {
        var chunks: [String] = []
        var buffer = ""
        let boundaries = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)

        for scalar in text.unicodeScalars {
            buffer.unicodeScalars.append(scalar)
            if buffer.count >= 4 || boundaries.contains(scalar) {
                chunks.append(buffer)
                buffer = ""
            }
        }

        if !buffer.isEmpty {
            chunks.append(buffer)
        }
        return chunks
    }

    private func pauseForVisibleStreaming() async {
        try? await Task.sleep(nanoseconds: 18_000_000)
    }

    private func checkJSONEndpoint(_ path: String) async -> Bool {
        guard let url = URL(string: "\(baseURL)\(path)") else { return false }
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 2
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            return (200..<300).contains(http.statusCode)
        } catch {
            return false
        }
    }

    private func readErrorBody(from bytes: URLSession.AsyncBytes) async throws -> String {
        var lines: [String] = []
        for try await line in bytes.lines {
            lines.append(line)
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func reset() {
        messages = []
        sessionId = nil
        errorMessage = nil
        Task {
            await refreshConnectionStatus()
            await createSession()
        }
    }

    // MARK: - Legacy floating bar stubs

    func stopAgent() {}

    @discardableResult
    func appendAssistantMessage(_ text: String) -> ChatMessage? {
        let msg = ChatMessage(role: "assistant", content: text)
        messages.append(msg)
        return msg
    }

    func invalidateAgentSession(sessionKey: String) async {}

    func rateMessage(_ id: String, rating: Int?) async {}
}
