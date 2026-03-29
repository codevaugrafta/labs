import Foundation
import SwiftUI

enum ReaderServerState: Equatable {
    case idle
    case running(port: UInt16, readerURL: URL)
    case failed(String)

    var failureMessage: String? {
        if case .failed(let message) = self {
            return message
        }
        return nil
    }
}

struct LeoRuntimePaths: Equatable {
    let rootDirectory: URL
    let booksDirectory: URL
    let storeURL: URL
    let usesUITestIsolation: Bool

    static func resolve(
        environment: [String: String],
        applicationSupportDirectory: URL
    ) -> LeoRuntimePaths {
        if let rawRoot = environment["LEO_UI_TEST_DATA_DIR"], !rawRoot.isEmpty {
            let root = URL(fileURLWithPath: (rawRoot as NSString).standardizingPath, isDirectory: true)
            return LeoRuntimePaths(
                rootDirectory: root,
                booksDirectory: root.appendingPathComponent("Books", isDirectory: true),
                storeURL: root.appendingPathComponent("Leo.store"),
                usesUITestIsolation: true
            )
        }

        let root = applicationSupportDirectory.appendingPathComponent("Leo", isDirectory: true)
        return LeoRuntimePaths(
            rootDirectory: root,
            booksDirectory: root.appendingPathComponent("Books", isDirectory: true),
            storeURL: root.appendingPathComponent("Leo.store"),
            usesUITestIsolation: false
        )
    }
}

@MainActor
final class LeoRuntime: ObservableObject {
    @Published private(set) var readerServerState: ReaderServerState = .idle

    let paths: LeoRuntimePaths

    private let fileManager: FileManager
    private let webResourceSearchPaths: [String]

    init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager

        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.paths = LeoRuntimePaths.resolve(
            environment: environment,
            applicationSupportDirectory: appSupport
        )

        self.webResourceSearchPaths = [
            Bundle.main.resourceURL?.appendingPathComponent("web").path,
            Bundle.main.resourceURL?.appendingPathComponent("Leo_Leo.bundle/web").path,
            Bundle.main.bundlePath + "/Contents/Resources/web",
            Bundle.main.bundlePath + "/Contents/Resources/Leo_Leo.bundle/web",
            (Bundle.main.bundlePath + "/../../Sources/Resources/web" as NSString).standardizingPath,
            "Sources/Resources/web",
        ].compactMap { $0 }

        prepareDirectories()
    }

    var booksDirectory: URL {
        paths.booksDirectory
    }

    var storeURL: URL {
        paths.storeURL
    }

    var readerURL: URL? {
        if case .running(_, let readerURL) = readerServerState {
            return readerURL
        }
        return nil
    }

    func startEmbeddedReader(forceRestart: Bool = false) {
        if forceRestart {
            LocalServer.shared.stop()
            readerServerState = .idle
        }

        if case .running = readerServerState, !forceRestart {
            return
        }

        guard let webRoot = findWebResourcesPath() else {
            readerServerState = .failed("Leo couldn’t find its embedded reader files. Rebuild the app bundle and try again.")
            return
        }

        do {
            let result = try LocalServer.shared.start(webResourcesPath: webRoot, forceRestart: forceRestart)
            readerServerState = .running(port: result.port, readerURL: result.readerURL)
            NSLog("[Leo] Embedded reader ready on \(result.readerURL.absoluteString)")
        } catch {
            readerServerState = .failed(error.localizedDescription)
            NSLog("[Leo] Embedded reader failed: \(error.localizedDescription)")
        }
    }

    func markReaderFailure(_ message: String) {
        guard !message.isEmpty else { return }
        readerServerState = .failed(message)
    }

    func clearReaderFailureIfPossible() {
        guard case .failed = readerServerState,
              let readerURL = LocalServer.shared.readerURL else { return }
        readerServerState = .running(port: LocalServer.shared.port, readerURL: readerURL)
    }

    private func prepareDirectories() {
        try? fileManager.createDirectory(at: paths.rootDirectory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: paths.booksDirectory, withIntermediateDirectories: true)
    }

    private func findWebResourcesPath() -> String? {
        for path in webResourceSearchPaths {
            if fileManager.fileExists(atPath: (path as NSString).appendingPathComponent("reader.html")) {
                return path
            }
        }
        return nil
    }
}
