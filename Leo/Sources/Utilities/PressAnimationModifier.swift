import SwiftUI

/// A ButtonStyle that scales down to 0.94 on press and springs back.
/// Apply to any plain-style button for satisfying press feedback.
struct LeoPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0, anchor: .center)
            .animation(.spring(duration: 0.2, bounce: 0.3), value: configuration.isPressed)
    }
}
