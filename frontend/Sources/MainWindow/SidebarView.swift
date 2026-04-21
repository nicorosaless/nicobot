import SwiftUI

enum SidebarNavItem: Int, CaseIterable {
    case chat = 0
    case settings = 1

    var title: String {
        switch self {
        case .chat: return "Chat"
        case .settings: return "Settings"
        }
    }

    var icon: String {
        switch self {
        case .chat: return "bubble.left.and.bubble.right.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

extension Notification.Name {
    static let navigateToSidebarItem = Notification.Name("navigateToSidebarItem")
    static let navigateToRewind = Notification.Name("navigateToRewind")
    static let refreshAllData = Notification.Name("refreshAllData")
    static let toggleTranscriptionRequested = Notification.Name("toggleTranscriptionRequested")
}

struct SidebarView: View {
    @Binding var selectedIndex: Int
    @Binding var isCollapsed: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if !isCollapsed {
                    Text("Umi")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.leading, 16)
                }
                Spacer()
                Button(action: { withAnimation { isCollapsed.toggle() } }) {
                    Image(systemName: "sidebar.left")
                        .foregroundColor(.gray)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 12)
            }
            .frame(height: 52)

            Divider()

            VStack(spacing: 4) {
                ForEach(SidebarNavItem.allCases, id: \.rawValue) { item in
                    SidebarRow(item: item, selected: selectedIndex == item.rawValue, collapsed: isCollapsed) {
                        selectedIndex = item.rawValue
                    }
                }
            }
            .padding(.top, 8)

            Spacer()
        }
        .frame(width: isCollapsed ? 52 : 200)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.3))
        .onReceive(NotificationCenter.default.publisher(for: .navigateToSidebarItem)) { note in
            if let rawValue = note.userInfo?["rawValue"] as? Int {
                selectedIndex = rawValue
            }
        }
    }
}

private struct SidebarRow: View {
    let item: SidebarNavItem
    let selected: Bool
    let collapsed: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: item.icon)
                    .frame(width: 20)
                    .foregroundColor(selected ? .white : .gray)
                if !collapsed {
                    Text(item.title)
                        .foregroundColor(selected ? .white : .gray)
                        .font(.system(size: 14))
                }
                Spacer()
            }
            .padding(.horizontal, collapsed ? 14 : 12)
            .padding(.vertical, 8)
            .background(selected ? Color.accentColor.opacity(0.3) : Color.clear)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
    }
}
