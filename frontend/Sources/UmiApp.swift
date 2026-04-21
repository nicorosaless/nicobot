import SwiftUI

@main
struct UmiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var authState = AuthState.shared

    var body: some Scene {
        Window("Umi", id: "main") {
            DesktopHomeView()
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1200, height: 800)
        .commands {
            CommandGroup(after: .sidebar) {
                Button("Chat") {
                    NotificationCenter.default.post(
                        name: .navigateToSidebarItem, object: nil,
                        userInfo: ["rawValue": SidebarNavItem.chat.rawValue])
                }
                .keyboardShortcut("1", modifiers: .command)

                Button("Settings") {
                    NotificationCenter.default.post(
                        name: .navigateToSidebarItem, object: nil,
                        userInfo: ["rawValue": SidebarNavItem.settings.rawValue])
                }
                .keyboardShortcut(",", modifiers: .command)
            }

            CommandGroup(after: .toolbar) {
                Button("Refresh") {
                    NotificationCenter.default.post(name: .refreshAllData, object: nil)
                }
                .keyboardShortcut("r", modifiers: .command)
            }
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    static var openMainWindow: (() -> Void)?

    private var statusBarItem: NSStatusItem?
    private var globalHotkeyMonitor: Any?
    private var localHotkeyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        signal(SIGPIPE, SIG_IGN)

        // Register Ask Umi hotkey via Carbon (works without Accessibility permission)
        GlobalShortcutManager.shared.registerShortcuts()

        setupMenuBar()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            NSApp.activate()
            for window in NSApp.windows where window.title.hasPrefix("Umi") {
                window.makeKeyAndOrderFront(nil)
                window.appearance = NSAppearance(named: .darkAqua)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        GlobalShortcutManager.shared.unregisterShortcuts()
        PushToTalkManager.shared.cleanup()
        if let monitor = globalHotkeyMonitor { NSEvent.removeMonitor(monitor) }
        if let monitor = localHotkeyMonitor { NSEvent.removeMonitor(monitor) }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        for window in sender.windows where window.title.hasPrefix("Umi") {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
            sender.activate(ignoringOtherApps: true)
            return false
        }
        return true
    }

    private func setupMenuBar() {
        if let old = statusBarItem {
            NSStatusBar.system.removeStatusItem(old)
        }
        statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusBarItem?.button {
            if let icon = NSImage(systemSymbolName: "bubble.left.and.bubble.right.fill",
                                  accessibilityDescription: "Umi") {
                icon.isTemplate = true
                button.image = icon
            }
            button.toolTip = "Umi"
        }

        let menu = NSMenu()

        let openItem = NSMenuItem(title: "Open Umi", action: #selector(openUmiFromMenu), keyEquivalent: "o")
        openItem.target = self
        menu.addItem(openItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit Umi", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusBarItem?.menu = menu
    }

    @objc private func openUmiFromMenu() {
        NSApp.activate()
        for window in NSApp.windows where window.title.hasPrefix("Umi") {
            window.makeKeyAndOrderFront(nil)
            return
        }
        Self.openMainWindow?()
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
