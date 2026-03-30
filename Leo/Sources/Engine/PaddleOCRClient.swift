import Foundation
import AppKit

/// Batch OCR engine backed by PaddleOCR-VL-1.5 (Python subprocess).
/// Loads the model once per call, processes all pages in a single Python process.
/// Falls back gracefully when Python/paddleocr unavailable.
actor PaddleOCRClient {
    static let shared = PaddleOCRClient()

    private var _isAvailable: Bool?

    /// True if python3 + paddleocr are installed. Cached after first check.
    var isAvailable: Bool {
        get async {
            if let cached = _isAvailable { return cached }
            let result = await checkInstalled()
            _isAvailable = result
            return result
        }
    }

    // MARK: - Public

    /// Batch-OCR a set of page images. Key = original page index, value = extracted text.
    /// Runs PaddleOCR once (one model load) for all pages.
    func recognizePages(_ images: [(index: Int, cgImage: CGImage)]) async throws -> [Int: String] {
        guard await isAvailable else { throw PaddleOCRError.notAvailable }

        let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("leo-paddle-\(UUID().uuidString)")

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
                    defer { try? FileManager.default.removeItem(at: tmpDir) }

                    // Write PNG files
                    for (index, cgImage) in images {
                        let imgURL = tmpDir.appendingPathComponent("page-\(index).png")
                        let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
                        guard let tiff = nsImage.tiffRepresentation,
                              let bitmap = NSBitmapImageRep(data: tiff),
                              let png = bitmap.representation(using: .png, properties: [:]) else { continue }
                        try png.write(to: imgURL)
                    }

                    // Write worker script with paths embedded
                    let outputURL = tmpDir.appendingPathComponent("results.json")
                    let scriptURL = tmpDir.appendingPathComponent("worker.py")
                    let script = Self.workerScript(inputDir: tmpDir.path, outputPath: outputURL.path)
                    try script.write(to: scriptURL, atomically: true, encoding: .utf8)

                    // Run Python worker (blocking — off cooperative thread pool)
                    let proc = Process()
                    proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                    proc.arguments = ["python3", scriptURL.path]
                    proc.standardOutput = Pipe()
                    proc.standardError = Pipe()
                    try proc.run()
                    proc.waitUntilExit()

                    guard proc.terminationStatus == 0 else {
                        continuation.resume(throwing: PaddleOCRError.workerFailed)
                        return
                    }

                    let data = try Data(contentsOf: outputURL)
                    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: String] else {
                        continuation.resume(throwing: PaddleOCRError.parseError)
                        return
                    }

                    let results = Dictionary(uniqueKeysWithValues: json.compactMap { k, v -> (Int, String)? in
                        guard let idx = Int(k) else { return nil }
                        return (idx, v)
                    })
                    continuation.resume(returning: results)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Private

    private func checkInstalled() async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                proc.arguments = ["python3", "-c", "import paddleocr; print('ok')"]
                let out = Pipe()
                proc.standardOutput = out
                proc.standardError = Pipe()
                guard (try? proc.run()) != nil else {
                    continuation.resume(returning: false)
                    return
                }
                proc.waitUntilExit()
                let s = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                continuation.resume(returning: s.contains("ok"))
            }
        }
    }

    private static func workerScript(inputDir: String, outputPath: String) -> String {
        // Paths are plain macOS temp paths — no special characters to escape.
        return """
import sys, json
from pathlib import Path

INPUT_DIR = "\(inputDir)"
OUTPUT_PATH = "\(outputPath)"

def load_ocr():
    from paddleocr import PaddleOCR
    # lang='ch' works for both PaddleOCR 2.x and 3.x
    return PaddleOCR(lang='ch', show_log=False)

def extract_text(ocr, img_path):
    # PaddleOCR 3.x uses predict(); 2.x uses ocr()
    if hasattr(ocr, 'predict'):
        result = ocr.predict(img_path)
        lines = []
        if result:
            for res in result:
                if isinstance(res, list):
                    for item in res:
                        if isinstance(item, dict):
                            t = item.get('rec_text', '')
                            if t:
                                lines.append(t)
                        elif isinstance(item, (list, tuple)) and len(item) >= 2:
                            t = item[1]
                            lines.append(t[0] if isinstance(t, (list, tuple)) else str(t))
        return '\\n'.join(lines)
    else:
        result = ocr.ocr(img_path, cls=True)
        lines = []
        if result:
            for page in result:
                if page:
                    for item in page:
                        if item and len(item) >= 2 and isinstance(item[1], (list, tuple)):
                            lines.append(str(item[1][0]))
        return '\\n'.join(lines)

ocr = load_ocr()
results = {}

for f in sorted(Path(INPUT_DIR).glob('page-*.png')):
    idx = int(f.stem.replace('page-', ''))
    try:
        results[str(idx)] = extract_text(ocr, str(f))
    except Exception:
        results[str(idx)] = ''

with open(OUTPUT_PATH, 'w', encoding='utf-8') as fh:
    json.dump(results, fh, ensure_ascii=False)
"""
    }
}

enum PaddleOCRError: LocalizedError {
    case notAvailable
    case workerFailed
    case parseError

    var errorDescription: String? {
        switch self {
        case .notAvailable: "PaddleOCR is not installed. Install with: pip3 install paddleocr"
        case .workerFailed: "PaddleOCR worker exited with an error"
        case .parseError: "Failed to parse PaddleOCR results"
        }
    }
}
