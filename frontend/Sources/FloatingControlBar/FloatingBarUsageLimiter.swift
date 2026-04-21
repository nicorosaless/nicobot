import Foundation

// Umi has no usage limits — all queries are always allowed.
@MainActor
final class FloatingBarUsageLimiter: ObservableObject {
    static let shared = FloatingBarUsageLimiter()

    @Published private(set) var hasPaidPlan: Bool = true

    var isLimitReached: Bool { false }
    var remainingQueries: Int { .max }
    var limitDescription: String { "unlimited" }

    func fetchPlan() async {}
    func syncQuota() async {}
    func recordQuery() {}
    func reset() {}
}
