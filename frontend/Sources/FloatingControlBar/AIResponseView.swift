import SwiftUI

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

    // All colours are light so they read on the dark glass background
    private let textPrimary   = Color.white
    private let textSecondary = Color.white.opacity(0.75)
    private let textDim       = Color.white.opacity(0.45)
    private let chipBg        = Color.white.opacity(0.10)
    private let chipBorder    = Color.white.opacity(0.15)

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
                                        responseText(text)
                                    case .discoveryCard(_, let title, let subtitle, let body):
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(title).scaledFont(size: 13, weight: .semibold).foregroundColor(textPrimary)
                                            Text(subtitle).scaledFont(size: 12).foregroundColor(textSecondary)
                                            Text(body).scaledFont(size: 12).foregroundColor(textSecondary)
                                        }
                                    }
                                }
                                if !msg.text.isEmpty {
                                    responseText(msg.text)
                                }
                            }
                        } else if isLoading {
                            HStack(spacing: 8) {
                                ProgressView().scaleEffect(0.7).tint(textDim)
                                Text("Thinking…")
                                    .scaledFont(size: 13)
                                    .foregroundColor(textDim)
                            }
                        } else if let msg = currentMessage, !msg.text.isEmpty {
                            responseText(msg.text)
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

    // MARK: - Sub-views

    private var headerView: some View {
        HStack(spacing: 12) {
            if isLoading {
                ProgressView().scaleEffect(0.6).frame(width: 16, height: 16).tint(textDim)
                Text("thinking").scaledFont(size: 14).foregroundColor(textDim)
            } else {
                Text("umi says").scaledFont(size: 14).foregroundColor(textDim)
            }
            Spacer()
            if canClearVisibleConversation {
                HStack(spacing: 4) {
                    Text("esc")
                        .scaledFont(size: 11).foregroundColor(textDim)
                        .frame(width: 30, height: 16)
                        .background(chipBg)
                        .cornerRadius(4)
                    Text("to clear").scaledFont(size: 11).foregroundColor(textDim)
                }
            }
        }
    }

    private var questionBar: some View {
        Text(userInput)
            .scaledFont(size: 13)
            .foregroundColor(textSecondary)
            .lineLimit(2)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(chipBg)
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(chipBorder, lineWidth: 0.5))
    }

    private func responseText(_ text: String) -> some View {
        Text(text)
            .scaledFont(size: 14)
            .foregroundColor(textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
    }

    private var voiceFollowUpView: some View {
        HStack(spacing: 8) {
            Circle().fill(Color.red).frame(width: 8, height: 8)
                .scaleEffect(isVoiceFollowUp ? 1.2 : 1.0)
                .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: isVoiceFollowUp)
            Text(voiceFollowUpTranscript.isEmpty ? "Listening…" : voiceFollowUpTranscript)
                .scaledFont(size: 13).foregroundColor(textSecondary)
                .lineLimit(1)
        }
        .id("voiceFollowUp")
    }

    private var followUpInputView: some View {
        HStack(spacing: 8) {
            TextField("Follow-up…", text: $followUpText)
                .textFieldStyle(.plain)
                .scaledFont(size: 13)
                .foregroundColor(textPrimary)
                .focused($isFollowUpFocused)
                .onSubmit { submitFollowUp() }

            if !followUpText.isEmpty {
                Button(action: submitFollowUp) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(chipBg)
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(chipBorder, lineWidth: 0.5))
    }

    private func historyExchangeView(_ exchange: FloatingChatExchange) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let q = exchange.question, !q.isEmpty {
                Text(q)
                    .scaledFont(size: 13).foregroundColor(textSecondary)
                    .lineLimit(2)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(chipBg)
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(chipBorder, lineWidth: 0.5))
            }
            responseText(exchange.aiMessage.text)
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
