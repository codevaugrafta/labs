import AppKit
import SwiftData
import SwiftUI

/// Cover-first library grid when no book is selected (picker-first launch).
struct LibraryBookPickerView: View {
    let books: [Book]
    let continueBook: Book?
    let themeBackground: Color
    let onSelectBook: (Book) -> Void
    let onImport: () -> Void
    let onReview: () -> Void
    let onVocabulary: () -> Void
    let dueCardCount: Int
    let totalVocabCount: Int

    @State private var continueHovered = false

    private let gridColumns = [
        GridItem(.adaptive(minimum: 140, maximum: 200), spacing: 16),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 10) {
                    Text("Library")
                        .font(.title2.weight(.semibold))
                    Spacer()
                    Button(action: onVocabulary) {
                        HStack(spacing: 4) {
                            Image(systemName: "character.book.closed")
                                .font(.system(size: 14))
                            if totalVocabCount > 0 {
                                Text("\(totalVocabCount)")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .help("Vocabulary")
                    Button(action: onReview) {
                        HStack(spacing: 5) {
                            Image(systemName: "rectangle.stack")
                                .font(.system(size: 14))
                            if dueCardCount > 0 {
                                Text("\(dueCardCount)")
                                    .font(.caption2.monospacedDigit().bold())
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Color.red, in: Capsule())
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .help("Review due cards")
                    Button("Import", action: onImport)
                        .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal, 4)

                if let continueBook {
                    Button {
                        onSelectBook(continueBook)
                    } label: {
                        HStack(spacing: 16) {
                            BookCoverThumbnail(book: continueBook, width: 56, height: 80)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Continue reading")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Text(continueBook.title)
                                    .font(.headline.weight(.medium))
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                if !continueBook.author.isEmpty {
                                    Text(continueBook.author)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                if let fraction = continueBook.locator?.fraction, fraction > 0.01 {
                                    Text("\(Int(fraction * 100))% complete")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.tertiary)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .scaleEffect(continueHovered ? 1.02 : 1.0)
                    .animation(.spring(duration: 0.25, bounce: 0.2), value: continueHovered)
                    .onHover { continueHovered = $0 }
                    .accessibilityIdentifier("leo.library.picker.continue")
                }

                LazyVGrid(columns: gridColumns, spacing: 20) {
                    ForEach(books) { book in
                        HoverableBookButton(book: book, onSelect: { onSelectBook(book) })
                    }
                }
            }
            .padding(24)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(themeBackground)
        .accessibilityIdentifier("leo.library.picker.root")
    }
}

private struct HoverableBookButton: View {
    @Bindable var book: Book
    let onSelect: () -> Void

    @State private var isHovered = false
    @State private var isOpening = false

    var body: some View {
        Button {
            withAnimation(.spring(duration: 0.25, bounce: 0.1)) { isOpening = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { onSelect() }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                BookCoverThumbnail(book: book, width: 120, height: 170)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .shadow(
                        color: .black.opacity(isHovered ? 0.22 : 0.12),
                        radius: isHovered ? 12 : 6,
                        y: isHovered ? 5 : 3
                    )
                Text(book.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(book.format == .pdf ? "PDF" : "EPUB")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.primary.opacity(isHovered ? 0.07 : 0.04))
            )
        }
        .buttonStyle(.plain)
        .scaleEffect(isOpening ? 0.96 : (isHovered ? 1.03 : 1.0), anchor: .center)
        .animation(.spring(duration: 0.25, bounce: 0.2), value: isHovered)
        .onHover { isHovered = $0 }
        .accessibilityIdentifier("leo.library.picker.book.\(book.id.uuidString)")
    }
}

private struct BookCoverThumbnail: View {
    @Bindable var book: Book
    let width: CGFloat
    let height: CGFloat

    private var cover: NSImage? {
        guard let path = book.coverImagePath,
              FileManager.default.fileExists(atPath: path) else { return nil }
        return NSImage(contentsOfFile: path)
    }

    var body: some View {
        Group {
            if let cover {
                Image(nsImage: cover)
                    .resizable()
                    .scaledToFill()
            } else {
                BookCoverPlaceholder(title: book.title, width: width, height: height)
            }
        }
        .frame(width: width, height: height)
        .clipped()
        .overlay(alignment: .bottom) {
            if let fraction = book.locator?.fraction, fraction > 0.01 {
                GeometryReader { geo in
                    Rectangle()
                        .fill(Color.accentColor.opacity(0.85))
                        .frame(width: max(4, geo.size.width * fraction), height: 3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 3)
            }
        }
    }
}

/// Gradient placeholder shown when no cover image is available.
/// Uses a deterministic color derived from the title's first character,
/// and displays the first two characters of the title in large white serif text —
/// matching the Apple Books missing-cover pattern.
private struct BookCoverPlaceholder: View {
    let title: String
    let width: CGFloat
    let height: CGFloat

    /// Eight muted, book-spine-inspired colors. Index is chosen deterministically from the title.
    private static let placeholderColors: [Color] = [
        Color(red: 0.36, green: 0.44, blue: 0.56), // slate blue
        Color(red: 0.49, green: 0.36, blue: 0.56), // dusty violet
        Color(red: 0.36, green: 0.52, blue: 0.44), // muted sage
        Color(red: 0.56, green: 0.40, blue: 0.36), // terracotta
        Color(red: 0.36, green: 0.48, blue: 0.56), // steel blue
        Color(red: 0.52, green: 0.44, blue: 0.36), // warm caramel
        Color(red: 0.40, green: 0.36, blue: 0.52), // deep mauve
        Color(red: 0.36, green: 0.50, blue: 0.50), // teal grey
    ]

    private var baseColor: Color {
        guard !title.isEmpty,
              let first = title.unicodeScalars.first else {
            return Self.placeholderColors[0]
        }
        let index = Int(first.value) % Self.placeholderColors.count
        return Self.placeholderColors[index]
    }

    /// Up to 2 characters shown large — the first two non-whitespace scalars of the title.
    private var displayChars: String {
        let chars = title.unicodeScalars.filter { !CharacterSet.whitespaces.contains($0) }
        return String(String.UnicodeScalarView(chars.prefix(2)))
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [baseColor.opacity(0.75), baseColor],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: 4) {
                Text(displayChars)
                    .font(.system(size: width * 0.30, weight: .semibold, design: .serif))
                    .foregroundStyle(.white.opacity(0.92))

                if width >= 80 {
                    Text(title)
                        .font(.system(size: max(9, width * 0.085), weight: .regular, design: .serif))
                        .foregroundStyle(.white.opacity(0.60))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, width * 0.10)
                }
            }
        }
        .frame(width: width, height: height)
    }
}
