import AppKit
import SwiftUI

/// Lets `NavigationSplitView` and the reader extend under the title bar (traffic lights stay usable).
/// When the library column is visible, use a standard title bar so the split doesn’t show a stray strip
/// above the sidebar.
struct MainWindowChromeConfigurator: NSViewRepresentable {
    var librarySidebarRevealed: Bool = false

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.frame = .zero
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            if librarySidebarRevealed {
                window.titlebarAppearsTransparent = false
                window.titleVisibility = .visible
            } else {
                window.titlebarAppearsTransparent = true
                window.titleVisibility = .hidden
            }
            if !window.styleMask.contains(.fullSizeContentView) {
                window.styleMask.insert(.fullSizeContentView)
            }
            // Avoid tint/accent “holes” under rounded split columns when the system briefly shows
            // the window backing during live resize.
            window.backgroundColor = .windowBackgroundColor
        }
    }
}
