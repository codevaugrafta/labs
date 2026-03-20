import Foundation

extension Notification.Name {
    /// Posted when menu bar content toggles change so `MenuBarManager` can rebuild.
    static let adhanMenuBarNeedsRebuild = Notification.Name("adhanMenuBarNeedsRebuild")
}
