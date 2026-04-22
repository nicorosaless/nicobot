import SwiftUI
struct ChatPage: View {
    @ObservedObject var chatProvider: ChatProvider
    @State private var inputText = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Chat con Hermes")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                    Text(chatProvider.connectionMessage)
                        .font(.system(size: 12))
                        .foregroundColor(statusColor)
                }
                Spacer()
                HStack(spacing: 8) {
                    StatusDot(isHealthy: chatProvider.backendHealthy, label: "Backend")
                    StatusDot(isHealthy: chatProvider.hermesHealthy, label: "Hermes")
                }
                Button(action: { chatProvider.reset() }) {
                    Image(systemName: "arrow.counterclockwise")
                        .foregroundColor(.gray)
                }
                .buttonStyle(.plain)
                .help("Nueva sesión")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if chatProvider.messages.isEmpty && !chatProvider.isLoading {
                            Text("Escribe un mensaje para empezar.")
                                .foregroundColor(.gray)
                                .font(.system(size: 14))
                                .padding(.top, 40)
                        }
                        ForEach(chatProvider.messages) { msg in
                            MessageBubble(message: msg).id(msg.id)
                        }
                        if chatProvider.isLoading && (chatProvider.messages.last?.content.isEmpty ?? true) {
                            HStack {
                                ProgressView().scaleEffect(0.7)
                                Text("Conectando con Hermes...").foregroundColor(.gray).font(.system(size: 13))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 20)
                        }
                        if let err = chatProvider.errorMessage {
                            Text(err).foregroundColor(.red).font(.system(size: 13)).padding(.horizontal, 20)
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.vertical, 16)
                }
                .onChange(of: chatProvider.messages.count) {
                    withAnimation { proxy.scrollTo("bottom") }
                }
                .onChange(of: chatProvider.messages.last?.content) {
                    proxy.scrollTo("bottom")
                }
                .onChange(of: chatProvider.messages.last?.contentBlocks.count) {
                    proxy.scrollTo("bottom")
                }
            }

            Divider()

            HStack(spacing: 10) {
                TextField("Escribe un mensaje…", text: $inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                    .focused($inputFocused)
                    .lineLimit(1...6)
                    .onSubmit { sendIfNotEmpty() }

                Button(action: sendIfNotEmpty) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(inputText.isEmpty ? .gray : .accentColor)
                }
                .buttonStyle(.plain)
                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || chatProvider.isLoading)
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.8))
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var statusColor: Color {
        chatProvider.backendHealthy && chatProvider.hermesHealthy ? .green : .orange
    }

    private func sendIfNotEmpty() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""
        Task { await chatProvider.sendMessage(text) }
    }
}

private struct StatusDot: View {
    let isHealthy: Bool
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(isHealthy ? Color.green : Color.orange)
                .frame(width: 7, height: 7)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.gray)
        }
        .help("\(label): \(isHealthy ? "conectado" : "sin respuesta")")
    }
}

private struct MessageBubble: View {
    let message: ChatMessage
    private var isUser: Bool { message.role == "user" }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if isUser { Spacer(minLength: 60) }
            if !isUser {
                Circle()
                    .fill(Color.accentColor.opacity(0.3))
                    .frame(width: 28, height: 28)
                    .overlay(Text("H").font(.system(size: 12, weight: .bold)).foregroundColor(.accentColor))
            }
            messageContent
            if isUser {
                Circle()
                    .fill(Color.blue.opacity(0.3))
                    .frame(width: 28, height: 28)
                    .overlay(Image(systemName: "person.fill").font(.system(size: 12)).foregroundColor(.blue))
            }
            if !isUser { Spacer(minLength: 60) }
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private var messageContent: some View {
        if isUser {
            Text(message.content)
                .font(.system(size: 14))
                .foregroundColor(.white)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.accentColor.opacity(0.2))
                .cornerRadius(12)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(ContentBlockGroup.group(message.contentBlocks)) { group in
                    switch group {
                    case .toolCalls(_, let blocks):
                        ToolCallGroupView(blocks: blocks)
                    case .text(_, let text), .thinking(_, let text):
                        Text(text)
                            .font(.system(size: 13))
                            .foregroundColor(.gray)
                    case .discoveryCard(_, let title, let subtitle, let body):
                        VStack(alignment: .leading, spacing: 2) {
                            Text(title).font(.system(size: 13, weight: .semibold))
                            Text(subtitle).font(.system(size: 12)).foregroundColor(.gray)
                            Text(body).font(.system(size: 12)).foregroundColor(.gray)
                        }
                    }
                }

                if !message.content.isEmpty || (message.isStreaming && message.contentBlocks.isEmpty) {
                    Text(message.content.isEmpty ? "..." : message.content)
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.07))
            .cornerRadius(12)
        }
    }
}
