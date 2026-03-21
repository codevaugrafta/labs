import Foundation

extension Notification.Name {
    /// Posted to open quick capture UI (menu bar or global shortcut).
    static let loveQuickCapture = Notification.Name("LoveQuickCapture")
    /// Posted to show the main document window.
    static let loveShowMainWindow = Notification.Name("LoveShowMainWindow")
    /// Posted after SwiftData save so the menu bar title stays in sync.
    static let loveDataDidChange = Notification.Name("LoveDataDidChange")
}
