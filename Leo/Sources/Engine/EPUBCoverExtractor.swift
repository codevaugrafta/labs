import Foundation

/// Extracts a cover image from an EPUB (ZIP) into `coversDirectory` for library thumbnails.
/// Uses `/usr/bin/unzip` (Leo is not sandboxed) to read entries without a ZIP dependency.
enum EPUBCoverExtractor {

    private static let logPrefix = "[Leo EPUBCover]"

    /// Writes cover bytes to `coversDirectory/{bookID}.{ext}` and returns the absolute path, or `nil` if none.
    static func extractCover(
        epubPath: String,
        bookID: UUID,
        coversDirectory: URL,
        fileManager: FileManager = .default
    ) -> String? {
        guard fileManager.fileExists(atPath: epubPath) else {
            NSLog("\(logPrefix) EPUB missing at \(epubPath)")
            return nil
        }
        guard let opfRelative = readOPFPathFromContainer(epubPath: epubPath) else {
            NSLog("\(logPrefix) Could not read OPF path from container.xml")
            return nil
        }
        guard let opfData = unzipPayload(epubPath: epubPath, innerPath: opfRelative),
              !opfData.isEmpty else {
            NSLog("\(logPrefix) Could not read OPF at \(opfRelative)")
            return nil
        }
        guard let coverInner = resolveCoverInnerPath(opfData: opfData, opfZipPath: opfRelative) else {
            NSLog("\(logPrefix) No cover reference in OPF \(opfRelative)")
            return nil
        }
        guard let imageData = unzipPayload(epubPath: epubPath, innerPath: coverInner),
              !imageData.isEmpty else {
            NSLog("\(logPrefix) Could not read cover at \(coverInner)")
            return nil
        }

        let rawExt = (coverInner as NSString).pathExtension.lowercased()
        let ext = allowedImageExtension(rawExt) ? rawExt : "jpg"

        do {
            try fileManager.createDirectory(at: coversDirectory, withIntermediateDirectories: true)
            let dest = coversDirectory.appendingPathComponent("\(bookID.uuidString).\(ext)")
            try imageData.write(to: dest, options: .atomic)
            return dest.path
        } catch {
            NSLog("\(logPrefix) Failed to write cover: \(error.localizedDescription)")
            return nil
        }
    }

    static func removeCachedCoverFile(at path: String?, fileManager: FileManager = .default) {
        guard let path, fileManager.fileExists(atPath: path) else { return }
        do {
            try fileManager.removeItem(atPath: path)
        } catch {
            NSLog("\(logPrefix) Could not remove cached cover at \(path): \(error.localizedDescription)")
        }
    }

    // MARK: - ZIP (unzip -p)

    private static func unzipPayload(epubPath: String, innerPath: String) -> Data? {
        let normalized = innerPath.replacingOccurrences(of: "\\", with: "/")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-p", epubPath, normalized]
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            NSLog("\(logPrefix) unzip spawn failed: \(error.localizedDescription)")
            return nil
        }

        guard process.terminationStatus == 0 else {
            if let alt = tryAlternateZipPath(epubPath: epubPath, innerPath: normalized) {
                return alt
            }
            return nil
        }

        return try? out.fileHandleForReading.readToEnd()
    }

    /// Some archives store paths with different casing; try a case-insensitive match via fresh unzip listing not worth doing — try leading `./` stripped already.
    private static func tryAlternateZipPath(epubPath: String, innerPath: String) -> Data? {
        let variants = [
            innerPath.lowercased(),
            innerPath.uppercased(),
        ].uniqued()
        for v in variants where v != innerPath {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            process.arguments = ["-p", epubPath, v]
            let out = Pipe()
            process.standardOutput = out
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
                process.waitUntilExit()
                if process.terminationStatus == 0, let data = try out.fileHandleForReading.readToEnd(), !data.isEmpty {
                    return data
                }
            } catch { continue }
        }
        return nil
    }

    // MARK: - container.xml

    private static func readOPFPathFromContainer(epubPath: String) -> String? {
        guard let data = unzipPayload(epubPath: epubPath, innerPath: "META-INF/container.xml") ??
                unzipPayload(epubPath: epubPath, innerPath: "meta-inf/container.xml"),
              let doc = try? XMLDocument(data: data, options: [.nodePreserveAll, .nodeCompactEmptyElement]),
              let root = doc.rootElement(),
              let rootfile = firstChildElement(localName: "rootfile", under: root, depth: 8),
              let path = rootfile.attribute(forName: "full-path")?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty else {
            return nil
        }
        return path
    }

    /// Breadth-first search for first element matching local name (handles default OPF/DC namespaces).
    private static func firstChildElement(localName: String, under parent: XMLElement, depth: Int) -> XMLElement? {
        guard depth > 0 else { return nil }
        var queue: [XMLElement] = [parent]
        var remaining = depth * 50
        while !queue.isEmpty, remaining > 0 {
            remaining -= 1
            let el = queue.removeFirst()
            for child in el.children ?? [] {
                guard let xe = child as? XMLElement else { continue }
                if xe.localName == localName { return xe }
                queue.append(xe)
            }
        }
        return nil
    }

    // MARK: - OPF → cover path

    private static func resolveCoverInnerPath(opfData: Data, opfZipPath: String) -> String? {
        guard let doc = try? XMLDocument(data: opfData, options: [.nodePreserveAll, .nodeCompactEmptyElement]),
              let root = doc.rootElement() else { return nil }

        guard let manifest = childElements(localName: "manifest", under: root).first else { return nil }
        let manifestItems = childElements(localName: "item", under: manifest)

        for item in manifestItems {
            guard let props = item.attribute(forName: "properties")?.stringValue else { continue }
            if propertyTokens(props).contains("cover-image"),
               let href = item.attribute(forName: "href")?.stringValue {
                return normalizedZipEntryPath(opfPath: opfZipPath, href: href)
            }
        }

        if let metadata = childElements(localName: "metadata", under: root).first {
            for meta in childElements(localName: "meta", under: metadata) {
                guard meta.attribute(forName: "name")?.stringValue == "cover" else { continue }
                guard let coverId = meta.attribute(forName: "content")?.stringValue else { continue }
                for item in manifestItems where item.attribute(forName: "id")?.stringValue == coverId {
                    if let href = item.attribute(forName: "href")?.stringValue {
                        return normalizedZipEntryPath(opfPath: opfZipPath, href: href)
                    }
                }
            }
        }

        if let guide = childElements(localName: "guide", under: root).first {
            for ref in childElements(localName: "reference", under: guide) {
                guard ref.attribute(forName: "type")?.stringValue == "cover" else { continue }
                if let href = ref.attribute(forName: "href")?.stringValue {
                    return normalizedZipEntryPath(opfPath: opfZipPath, href: href)
                }
            }
        }

        return nil
    }

    private static func childElements(localName: String, under parent: XMLElement) -> [XMLElement] {
        (parent.children ?? []).compactMap { $0 as? XMLElement }.filter { $0.localName == localName }
    }

    private static func propertyTokens(_ raw: String) -> Set<String> {
        Set(raw.split(whereSeparator: { $0.isWhitespace || $0 == "," }).map { String($0) })
    }

    /// Join `href` to the OPF’s ZIP directory using **string-only** normalization (no `file://` resolution — CWD would break EPUB paths during tests/CLI).
    private static func normalizedZipEntryPath(opfPath: String, href: String) -> String {
        let trimmed = href.trimmingCharacters(in: .whitespacesAndNewlines)
        let opfDir = (opfPath as NSString).deletingLastPathComponent
        let raw = (opfDir as NSString).appendingPathComponent(trimmed)
        return normalizeZipRelativePath(raw)
    }

    private static func normalizeZipRelativePath(_ raw: String) -> String {
        let parts = raw.split(separator: "/").map(String.init)
        var stack: [String] = []
        for p in parts {
            if p == ".." {
                if !stack.isEmpty { stack.removeLast() }
            } else if p != "." && !p.isEmpty {
                stack.append(p)
            }
        }
        return stack.joined(separator: "/")
    }

    private static func allowedImageExtension(_ ext: String) -> Bool {
        ["jpg", "jpeg", "png", "webp", "gif", "bmp", "tif", "tiff"].contains(ext)
    }
}

// MARK: - uniqued helper

private extension Sequence where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
