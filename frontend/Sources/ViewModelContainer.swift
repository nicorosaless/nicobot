import SwiftUI

/// Minimal container for v1 — chat only.
@MainActor
class ViewModelContainer: ObservableObject {
    static let shared = ViewModelContainer()

    @Published var chatProvider = ChatProvider()

    private init() {}

    func setup() {
        chatProvider.initialize()
    }
}
