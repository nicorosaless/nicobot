import MarkdownUI
import SwiftUI

/// Simplified AI response view for the floating control bar.
struct AIResponseView: View {
    @EnvironmentObject var state: FloatingControlBarState
    @Binding var isLoading: Bool
    let currentMessage: ChatMessage?
    @State private var followUpText: String = ""
    @FocusState private var isFollowUpFocused: Bool

    let userInput: String
    let chatHistory: [FloatingChatExchange]
    @Binding var isVoiceFollowUp: Bool
    @Binding var voiceFollowUpTranscript: String
    var canClearVisibleConversation: Bool = false

    var onClearVisibleConversation: (() -> Void)?
    var onEscape: (() -> Void)?
    var onSendFollowUp: ((String) -> Void)?
    var onRate: ((String, Int?) -> Void)?
    var onShareLink: (() async -> String?)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerView.fixedSize(horizontal: false, vertical: true)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(chatHistory) { exchange in
                            historyExchangeView(exchange)
                        }

                        if !userInput.isEmpty {
                            questionBar
                        }

                        if let msg = currentMessage, !msg.contentBlocks.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(ContentBlockGroup.group(msg.contentBlocks)) { group in
                                    switch group {
                                    case .toolCalls(_, let blocks):
                                        ToolCallGroupView(blocks: blocks)
                                    case .text(_, let text), .thinking(_, let text):
                                        Text(text)
                                            .scaledFont(size: 13)
                                            .foregroundColor(.secondary)
                                    case .discoveryCard(_, let title, let subtitle, let body):
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(title).scaledFont(size: 13, weight: .semibold)
                                            Text(subtitle).scaledFont(size: 12).foregroundColor(.secondary)
                                            Text(body).scaledFont(size: 12).foregroundColor(.secondary)
                                        }
                                    }
                                }

                                if !msg.text.isEmpty {
                                    Markdown(msg.text)
                                        .markdownTheme(.gitHub)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        } else if isLoading {
                            HStack(spacing: 8) {
                                ProgressView().scaleEffect(0.7)
                                Text("Thinking…")
                                    .scaledFont(size: 13)
                                    .foregroundColor(.secondary)
                            }
                        } else if let msg = currentMessage, !msg.text.isEmpty {
                            Markdown(msg.text)
                                .markdownTheme(.gitHub)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        if isVoiceFollowUp {
                            voiceFollowUpView
                        }

                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .background(
                        GeometryReader { geo -> Color in
                            let h = geo.size.height
                            DispatchQueue.main.async { state.responseContentHeight = h }
                            return Color.clear
                        }
                    )
                }
                .onChange(of: currentMessage?.text) {
                    withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo("bottom", anchor: .bottom) }
                }
                .onChange(of: currentMessage?.contentBlocks.count) {
                    withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo("bottom", anchor: .bottom) }
                }
                .onChange(of: chatHistory.count) {
                    withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo("bottom", anchor: .bottom) }
                }
                .onChange(of: isVoiceFollowUp) {
                    if isVoiceFollowUp {
                        withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo("voiceFollowUp", anchor: .bottom) }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if !isLoading && !isVoiceFollowUp {
                followUpInputView
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onExitCommand { onEscape?() }
        .onAppear {
            if !isLoading {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { isFollowUpFocused = true }
            }
        }
        .onChange(of: isLoading) {
            if !isLoading {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { isFollowUpFocused = true }
            }
        }
    }

    private var headerView: some View {
        HStack(spacing: 12) {
            if isLoading {
                ProgressView().scaleEffect(0.6).frame(width: 16, height: 16)
                Text("thinking").scaledFont(size: 14).foregroundColor(.secondary)
            } else {
                Text("umi says").scaledFont(size: 14).foregroundColor(.secondary)
            }
            Spacer()
            if canClearVisibleConversation {
                HStack(spacing: 4) {
                    Text("esc")
                        .scaledFont(size: 11).foregroundColor(.secondary)
                        .frame(width: 30, height: 16)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(4)
                    Text("to clear").scaledFont(size: 11).foregroundColor(.secondary)
                }
            }
        }
    }

    private var questionBar: some View {
        Text(userInput)
            .scaledFont(size: 13)
            .foregroundColor(.white)
            .lineLimit(2)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.1))
            .cornerRadius(8)
    }

    private var voiceFollowUpView: some View {
        HStack(spacing: 8) {
            Circle().fill(Color.red).frame(width: 8, height: 8)
                .scaleEffect(isVoiceFollowUp ? 1.2 : 1.0)
                .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: isVoiceFollowUp)
            Text(voiceFollowUpTranscript.isEmpty ? "Listening…" : voiceFollowUpTranscript)
                .scaledFont(size: 13).foregroundColor(.white.opacity(0.8))
                .lineLimit(1)
        }
        .id("voiceFollowUp")
    }

    private var followUpInputView: some View {
        HStack(spacing: 8) {
            TextField("Follow-up…", text: $followUpText)
                .textFieldStyle(.plain)
                .scaledFont(size: 13)
                .foregroundColor(.white)
                .focused($isFollowUpFocused)
                .onSubmit { submitFollowUp() }

            if !followUpText.isEmpty {
                Button(action: submitFollowUp) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.08))
        .cornerRadius(8)
    }

    private func historyExchangeView(_ exchange: FloatingChatExchange) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let q = exchange.question, !q.isEmpty {
                Text(q)
                    .scaledFont(size: 13).foregroundColor(.white)
                    .lineLimit(2)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(8)
            }
            Markdown(exchange.aiMessage.text)
                .markdownTheme(.gitHub)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
        }
    }

    private func submitFollowUp() {
        let text = followUpText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        followUpText = ""
        onSendFollowUp?(text)
    }
}
