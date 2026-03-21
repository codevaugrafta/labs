import Foundation

/// Where the user intends to act on a must-do (v1 — no calendar time grid).
enum PlanningBucket: Int, Codable, CaseIterable, Hashable, Sendable {
    case backlog = 0
    case today = 1
    case thisWeek = 2

    var displayName: String {
        switch self {
        case .backlog: "Backlog"
        case .today: "Today"
        case .thisWeek: "This week"
        }
    }
}
