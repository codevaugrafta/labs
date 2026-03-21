import Foundation

/// Primary list scope for must-dos (not a calendar view).
enum MainListFilter: String, CaseIterable, Identifiable, Hashable, Sendable {
    case all = "All"
    case today = "Today"
    case thisWeek = "This week"
    case backlog = "Backlog"

    var id: String { rawValue }
}
