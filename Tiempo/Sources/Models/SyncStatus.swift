import Foundation

enum SyncStatus: Int, Codable, Sendable {
    case synced = 0
    case pendingCreate = 1
    case pendingUpdate = 2
    case pendingDelete = 3
}
