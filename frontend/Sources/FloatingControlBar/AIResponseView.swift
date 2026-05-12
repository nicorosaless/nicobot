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
                                            .foregroundColor(textMid)
                                    case .discoveryCard(_, let title, let subtitle, let body):
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(title).scaledFont(size: 13, weight: .semibold).foregroundColor(textDark)
                                            Text(subtitle).scaledFont(size: 12).foregroundColor(textLight)
                                            Text(body).scaledFont(size: 12).foregroundColor(textMid)
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
                                ProgressView().scaleEffect(0.7).tint(textLight)
                                Text("Thinking…")
                                    .scaledFont(size: 13)
                                    .foregroundColor(textLight)
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

    private let textDark = Color(hex: 0x1F2937)
    private let textMid = Color(hex: 0x374151)
    private let textLight = Color(hex: 0x6B7280)

    private var headerView: some View {
        HStack(spacing: 12) {
            if isLoading {
                ProgressView().scaleEffect(0.6).frame(width: 16, height: 16).tint(textLight)
                Text("thinking").scaledFont(size: 14).foregroundColor(textLight)
            } else {
                Text("umi says").scaledFont(size: 14).foregroundColor(textLight)
            }
            Spacer()
            if canClearVisibleConversation {
                HStack(spacing: 4) {
                    Text("esc")
                        .scaledFont(size: 11).foregroundColor(textLight)
                        .frame(width: 30, height: 16)
                        .background(Color.black.opacity(0.06))
                        .cornerRadius(4)
                    Text("to clear").scaledFont(size: 11).foregroundColor(textLight)
                }
            }
        }
    }

    private var questionBar: some View {
        Text(userInput)
            .scaledFont(size: 13)
            .foregroundColor(textDark)
            .lineLimit(2)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.black.opacity(0.04))
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.black.opacity(0.1), lineWidth: 0.5))
    }

    private var voiceFollowUpView: some View {
        HStack(spacing: 8) {
            Circle().fill(Color.red).frame(width: 8, height: 8)
                .scaleEffect(isVoiceFollowUp ? 1.2 : 1.0)
                .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: isVoiceFollowUp)
            Text(voiceFollowUpTranscript.isEmpty ? "Listening…" : voiceFollowUpTranscript)
                .scaledFont(size: 13).foregroundColor(textMid)
                .lineLimit(1)
        }
        .id("voiceFollowUp")
    }

    private var followUpInputView: some View {
        HStack(spacing: 8) {
            TextField("Follow-up…", text: $followUpText)
                .textFieldStyle(.plain)
                .scaledFont(size: 13)
                .foregroundColor(textDark)
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
        .background(Color.black.opacity(0.04))
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5))
    }

    private func historyExchangeView(_ exchange: FloatingChatExchange) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let q = exchange.question, !q.isEmpty {
                Text(q)
                    .scaledFont(size: 13).foregroundColor(textDark)
                    .lineLimit(2)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.black.opacity(0.04))
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.black.opacity(0.1), lineWidth: 0.5))
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
