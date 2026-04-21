import Foundation

/// Stub — all features unlocked for local Umi install.
@MainActor
class TierManager {
    static let shared = TierManager()
    private init() {}

    var currentTier: Int { 0 }
    func checkAndUpdateTier() async {}
    func isFeatureUnlocked(_: String) -> Bool { true }
}
