import Darwin
import Foundation

/// Copies SwiftData store from pre-rename `FocusPath` Application Support into `Love` when the new store does not exist yet.
enum LoveDataMigration {
    private static let legacyDirName = "FocusPath"
    private static let legacyStoreName = "FocusPath.store"
    private static let newDirName = "Love"
    private static let newStoreName = "Love.store"

    static func migrateLegacyApplicationSupportIfNeeded() {
        let fm = FileManager.default
        guard let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }

        let legacyDir = appSupport.appendingPathComponent(legacyDirName, isDirectory: true)
        let legacyStore = legacyDir.appendingPathComponent(legacyStoreName)
        let newDir = appSupport.appendingPathComponent(newDirName, isDirectory: true)
        let newStore = newDir.appendingPathComponent(newStoreName)

        guard !fm.fileExists(atPath: newStore.path) else { return }

        try? fm.createDirectory(at: newDir, withIntermediateDirectories: true)

        guard fm.fileExists(atPath: legacyStore.path) else { return }

        do {
            try fm.copyItem(at: legacyStore, to: newStore)
        } catch {
            return
        }

        applyStoreFilePermissions(newStore.path)

        for suffix in ["-wal", "-shm"] {
            let legacySidecar = URL(fileURLWithPath: legacyStore.path + suffix)
            let newSidecar = URL(fileURLWithPath: newStore.path + suffix)
            guard fm.fileExists(atPath: legacySidecar.path) else { continue }
            try? fm.removeItem(at: newSidecar)
            try? fm.copyItem(at: legacySidecar, to: newSidecar)
            applyStoreFilePermissions(newSidecar.path)
        }
    }

    private static func applyStoreFilePermissions(_ path: String) {
        chmod(path, 0o600)
    }
}
