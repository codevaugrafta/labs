import AppKit
import SwiftUI

// MARK: - NSPanel subclass

/// A floating, non-activating NSPanel for word lookups.
///
/// Style design:
/// - `.nonactivatingPanel` — clicking a word in the reader does not steal key focus
/// - `.fullScreenAuxiliary` — stays visible when the main window enters full screen
/// - `.titled + .closable` — provides the standard close button chrome
/// - `.windowFloat` level — sits above normal windows without blocking system UI
/// - `hidesOnDeactivate = false` — panel stays open when the app loses focus
/// - `isMovableByWindowBackground = true` — drag anywhere in the panel to reposition
final class FloatingDictionaryPanel: NSPanel {

    init(contentRect: NSRect) {
        let style: NSWindow.StyleMask = [
            .nonactivatingPanel,
            .fullSizeContentView,
            .titled,
            .closable,
        ]

        super.init(
            contentRect: contentRect,
            styleMask: style,
            backing: .buffered,
            defer: false
        )

        // Behaviour
        level = .floating
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isReleasedWhenClosed = false

        // Chrome
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
    }

    /// NSPanel override — allows the panel to become the first responder
    /// so SwiftUI buttons inside it receive keyboard/mouse events without
    /// requiring the user to click the main window first.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
