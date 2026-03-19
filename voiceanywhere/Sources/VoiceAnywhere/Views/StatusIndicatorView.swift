import SwiftUI

/// Animated three-bar waveform shown in the floating panel while speech is active.
struct StatusIndicatorView: View {
    @State private var animating = false

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.accentColor)
                    .frame(width: 3, height: barHeight(for: index))
                    .animation(
                        .easeInOut(duration: 0.4)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.15),
                        value: animating
                    )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
        )
        .onAppear {
            animating = true
        }
    }

    // MARK: - Helpers

    /// Returns a deterministic height so the bars animate to distinct heights.
    private func barHeight(for index: Int) -> CGFloat {
        // Stagger the target heights across the three bars.
        let heights: [CGFloat] = [18, 22, 14]
        return animating ? heights[index % heights.count] : 6
    }
}

#if DEBUG
#Preview {
    StatusIndicatorView()
        .frame(width: 60, height: 32)
        .padding()
}
#endif
