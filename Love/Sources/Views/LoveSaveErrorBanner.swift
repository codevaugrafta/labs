import SwiftUI

/// Shown when `LoveEngine.save()` fails (`lastError`); same affordance in main window and Quick capture.
struct LoveSaveErrorBanner: View {
    let message: String
    let onDismiss: () -> Void
    var horizontalPadding: CGFloat = 20

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
            Spacer(minLength: 8)
            Button("Dismiss") {
                onDismiss()
            }
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background {
            RoundedRectangle(cornerRadius: LoveTheme.controlCorner, style: .continuous)
                .fill(.regularMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: LoveTheme.controlCorner, style: .continuous)
                        .fill(Color.orange.opacity(0.12))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: LoveTheme.controlCorner, style: .continuous)
                        .strokeBorder(.orange.opacity(0.4), lineWidth: 1)
                }
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Save failed: \(message)")
    }
}
