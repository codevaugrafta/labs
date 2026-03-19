import KeyboardShortcuts

/// Thin wrapper around KeyboardShortcuts to keep hotkey wiring out of AppDelegate.
/// Registration itself is done in AppDelegate; this file documents the contract.
enum HotkeyManager {
    /// Registers a handler for the speak-selection hotkey.
    static func onSpeakSelection(_ handler: @escaping () -> Void) {
        KeyboardShortcuts.onKeyUp(for: .speakSelection, action: handler)
    }

    /// Registers a handler for the repeat-last hotkey.
    static func onRepeatLast(_ handler: @escaping () -> Void) {
        KeyboardShortcuts.onKeyUp(for: .repeatLast, action: handler)
    }

    /// Removes all registered handlers (useful for testing or re-registration).
    static func removeAll() {
        KeyboardShortcuts.removeAllHandlers()
    }
}
