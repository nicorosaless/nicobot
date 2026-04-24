import SwiftUI

struct ToolCallView: View {
    let block: ContentBlock

    private var label: String {
        if case .toolCall(_, let label, _) = block { return label }
        return ""
    }

    private var isCompleted: Bool {
        if case .toolCall(_, _, let status) = block { return status == "completed" }
        return false
    }

    var body: some View {
        HStack(spacing: 6) {
            Group {
                if isCompleted {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(OmiColors.success)
                        .font(.system(size: 11, weight: .semibold))
                        .transition(.scale.combined(with: .opacity))
                } else {
                    ProgressView()
                        .controlSize(.mini)
                        .frame(width: 11, height: 11)
                        .transition(.opacity)
                }
            }
            .animation(.spring(duration: 0.3), value: isCompleted)

            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isCompleted ? OmiColors.textQuaternary : OmiColors.purplePrimary)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: OmiChrome.chipRadius, style: .continuous)
                .fill(OmiColors.backgroundTertiary)
                .overlay(
                    RoundedRectangle(cornerRadius: OmiChrome.chipRadius, style: .continuous)
                        .stroke(
                            isCompleted ? OmiColors.border.opacity(0.2) : OmiColors.purplePrimary.opacity(0.3),
                            lineWidth: 0.5
                        )
                )
        )
    }
}

struct ToolCallGroupView: View {
    let blocks: [ContentBlock]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                ToolCallView(block: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
