import SwiftUI

struct ToolCallView: View {
    let block: ContentBlock

    private var label: String {
        if case .toolCall(_, let label, _) = block {
            return label
        }
        return ""
    }

    private var status: String {
        if case .toolCall(_, _, let status) = block {
            return status
        }
        return "running"
    }

    private var isCompleted: Bool {
        status == "completed"
    }

    var body: some View {
        HStack(spacing: 8) {
            if isCompleted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(OmiColors.success)
                    .font(.system(size: 13, weight: .semibold))
            } else {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.65)
                    .frame(width: 13, height: 13)
            }

            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isCompleted ? OmiColors.textQuaternary : OmiColors.purplePrimary)
                .lineLimit(1)

            Text("tool")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(isCompleted ? OmiColors.textQuaternary : OmiColors.purplePrimary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(OmiColors.backgroundQuaternary.opacity(0.75))
                .clipShape(Capsule())

            Text(isCompleted ? "completado" : "ejecutando")
                .font(.system(size: 11))
                .foregroundStyle(OmiColors.textQuaternary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(OmiColors.backgroundTertiary)
        .clipShape(RoundedRectangle(cornerRadius: OmiChrome.chipRadius, style: .continuous))
    }
}

struct ToolCallGroupView: View {
    let blocks: [ContentBlock]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                ToolCallView(block: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
