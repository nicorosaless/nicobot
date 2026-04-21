import SwiftUI

struct DesktopHomeView: View {
    @StateObject private var appState = AppState()
    @StateObject private var viewModelContainer = ViewModelContainer.shared
    @State private var selectedIndex = SidebarNavItem.chat.rawValue
    @State private var isSidebarCollapsed = false
    @State private var selectedSettingsSection: SettingsContentView.SettingsSection = .general
    @State private var highlightedSettingId: String? = nil

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(selectedIndex: $selectedIndex, isCollapsed: $isSidebarCollapsed)

            Divider()

            Group {
                switch SidebarNavItem(rawValue: selectedIndex) ?? .chat {
                case .chat:
                    ChatPage(chatProvider: viewModelContainer.chatProvider)
                case .settings:
                    SettingsPage(
                        appState: appState,
                        selectedSection: $selectedSettingsSection,
                        highlightedSettingId: $highlightedSettingId,
                        chatProvider: viewModelContainer.chatProvider
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .preferredColorScheme(.dark)
        .onAppear {
            viewModelContainer.setup()
        }
    }
}
