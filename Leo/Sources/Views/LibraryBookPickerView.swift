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

    private let gridColumns = [
        GridItem(.adaptive(minimum: 140, maximum: 200), spacing: 16),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    Text("Library")
                        .font(.title2.weight(.semibold))
                    Spacer()
                    Button("Import Book", action: onImport)
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
                    .accessibilityIdentifier("leo.library.picker.continue")
                }

                LazyVGrid(columns: gridColumns, spacing: 20) {
                    ForEach(books) { book in
                        Button {
                            onSelectBook(book)
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                BookCoverThumbnail(book: book, width: 120, height: 170)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
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
                                    .fill(Color.primary.opacity(0.04))
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("leo.library.picker.book.\(book.id.uuidString)")
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

private struct BookCoverThumbnail: View {
    let book: Book
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
                Image(systemName: book.format == .epub ? "book.fill" : "doc.fill")
                    .font(.system(size: width * 0.28))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.primary.opacity(0.06))
            }
        }
        .frame(width: width, height: height)
        .clipped()
    }
}
