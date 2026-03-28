import Foundation
import Zip

/// Bidirectional Anki integration.
/// Import: .apkg → extract cards → map states to FamiliarityTracker
/// Export: vocabulary entries → .apkg with context sentences + audio
///
/// .apkg format: ZIP containing collection.anki2 (SQLite DB) + media files
struct AnkiExporter: Sendable {

    // MARK: - Import

    struct ImportResult: Sendable {
        let totalCards: Int
        let wordStates: [(word: String, state: FamiliarityState)]
    }

    /// Import an Anki .apkg file and extract word → familiarity state mappings.
    /// Anki card types map to familiarity states:
    /// - type 0 (new) → .unknown
    /// - type 1 (learning) → .learning
    /// - type 2 (review, ivl < 21) → .familiar
    /// - type 2 (review, ivl >= 21) → .known (mature)
    func importDeck(from fileURL: URL) throws -> ImportResult {
        let extractDir = try extractAPKG(fileURL: fileURL)
        let dbPath = extractDir.appendingPathComponent("collection.anki2")

        guard FileManager.default.fileExists(atPath: dbPath.path) else {
            throw AnkiError.invalidFormat("collection.anki2 not found in .apkg")
        }

        // Use sqlite3 command-line to query the database
        // (avoids adding SQLite SPM dependency — can upgrade later)
        let query = """
        SELECT n.flds, c.type, c.ivl
        FROM cards c
        JOIN notes n ON c.nid = n.id;
        """

        let result = try runSQLite(dbPath: dbPath.path, query: query)
        var wordStates: [(word: String, state: FamiliarityState)] = []

        for line in result.split(separator: "\n") {
            let parts = line.split(separator: "|", maxSplits: 2)
            guard parts.count >= 3 else { continue }

            // Extract the first field (front of card) — this is typically the word
            let fields = String(parts[0])
            let word = extractWordFromFields(fields)
            guard !word.isEmpty else { continue }

            let cardType = Int(parts[1]) ?? 0
            let interval = Int(parts[2]) ?? 0

            let state: FamiliarityState = switch cardType {
            case 0: .unknown     // New card
            case 1: .learning    // Learning
            case 2 where interval >= 21: .known  // Mature review card
            case 2: .familiar    // Young review card
            default: .seen
            }

            wordStates.append((word: word, state: state))
        }

        // Clean up
        try? FileManager.default.removeItem(at: extractDir)

        return ImportResult(totalCards: wordStates.count, wordStates: wordStates)
    }

    // MARK: - Export

    struct ExportCard: Sendable {
        let word: String
        let pinyin: String
        let definition: String
        let contextSentence: String
    }

    /// Export vocabulary entries to an Anki-compatible format.
    /// Generates a tab-separated text file that Anki can import directly.
    /// (Full .apkg generation requires SQLite writes — using TSV for v1)
    func exportCards(_ cards: [ExportCard], to outputURL: URL) throws {
        var lines: [String] = []
        // Header comment for Anki import
        lines.append("#separator:tab")
        lines.append("#html:false")
        lines.append("#columns:Front\tPinyin\tDefinition\tContext")

        for card in cards {
            let front = card.word
            let pinyin = card.pinyin
            let definition = card.definition.replacingOccurrences(of: "\t", with: " ")
            let context = card.contextSentence.replacingOccurrences(of: "\t", with: " ")
            lines.append("\(front)\t\(pinyin)\t\(definition)\t\(context)")
        }

        let content = lines.joined(separator: "\n")
        try content.write(to: outputURL, atomically: true, encoding: .utf8)
    }

    // MARK: - Private

    private func extractAPKG(fileURL: URL) throws -> URL {
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let extractDir = cacheDir.appendingPathComponent("Leo/AnkiImport/\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)

        // .apkg is a ZIP file
        try Zip.unzipFile(fileURL, destination: extractDir, overwrite: true, password: nil)
        return extractDir
    }

    private func runSQLite(dbPath: String, query: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [dbPath, query]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// Extract the Chinese word from an Anki field string.
    /// Fields are separated by \x1f (unit separator). Takes the first field
    /// and strips HTML tags.
    private func extractWordFromFields(_ fields: String) -> String {
        let firstField = fields.split(separator: "\u{1f}").first.map(String.init) ?? fields
        // Strip HTML tags
        let stripped = firstField
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // Take only the Chinese portion if mixed
        let chinese = stripped.filter { $0.isChineseCharacter }
        return chinese.isEmpty ? stripped : String(chinese)
    }
}

enum AnkiError: LocalizedError {
    case invalidFormat(String)
    case exportFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidFormat(let msg): "Invalid Anki format: \(msg)"
        case .exportFailed(let msg): "Export failed: \(msg)"
        }
    }
}

// Uses Character.isChineseCharacter from ChineseParser.swift
