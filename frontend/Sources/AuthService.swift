import Foundation
import SwiftUI

@MainActor
class AuthState: ObservableObject {
    static let shared = AuthState()
    @Published var isSignedIn: Bool = true
    @Published var isLoading: Bool = false
    @Published var isRestoringAuth: Bool = false
    @Published var error: String?
    @Published var userEmail: String? = "local@umi.app"
    private init() {}
}

@MainActor
class AuthService {
    static let shared = AuthService()
    var isSignedIn: Bool { true }
    var currentUserId: String { "local" }
    var currentUserEmail: String? { "local@umi.app" }

    func getAuthToken() async throws -> String { "local-token" }
    func signOut() {}
    func restoreSession() async {}
}
