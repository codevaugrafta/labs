import AppKit
import SwiftUI

// MARK: - NSPanel subclass

/// A floating, non-activating NSPanel for word lookups.
/// Designed to feel like macOS Dictionary.app — clean, solid, native.
///
/// - `.nonactivatingPanel` — clicking a word in the reader does not steal key focus
/// - `.fullScreenAuxiliary` — stays visible when the main window enters full screen
/// - No `.titled`/`.closable` — removes the traffic-light dots and titlebar chrome
/// - Dismiss via click-outside, Escape, or next word tap (handled by Controller)
final class FloatingDictionaryPanel: NSPanel {

    init(contentRect: NSRect) {
        let style: NSWindow.StyleMask = [
            .nonactivatingPanel,
            .fullSizeContentView,
        ]

        super.init(
            contentRect: contentRect,
            styleMask: style,
            backing: .buffered,
            defer: false
        )

        // Behaviour — stays above Leo's windows but hides when app loses focus
        level = .floating
        isMovableByWindowBackground = true
        hidesOnDeactivate = true
        collectionBehavior = [.fullScreenAuxiliary]
        isReleasedWhenClosed = false

        // Appearance — clear window background so SwiftUI content provides the visual surface.
        // On macOS 26 the SwiftUI content uses GlassEffectContainer; on older versions it uses
        // ultraThinMaterial. Both need the NSPanel to be transparent underneath.
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
