import Darwin
import Foundation
import OSLog

private extension Logger {
    static let loveMigration = Logger(subsystem: "com.franciscodilussor.love", category: "migration")
}

/// Copies SwiftData store from pre-rename `FocusPath` Application Support into `Love` when the new store does not exist yet.
enum LoveDataMigration {
    private static let legacyDirName = "FocusPath"
    private static let legacyStoreName = "FocusPath.store"
    private static let newDirName = "Love"
    private static let newStoreName = "Love.store"

    /// UserDefaults key for a one-shot alert in the UI after a failed migration (consumed on read).
    static let pendingFailureUserDefaultsKey = "Love.pendingMigrationFailure"

    /// Returns and clears a user-facing migration failure message, if any.
    static func consumePendingUserFacingFailure() -> String? {
        let key = pendingFailureUserDefaultsKey
        let message = UserDefaults.standard.string(forKey: key)
        if message != nil {
            UserDefaults.standard.removeObject(forKey: key)
        }
        return message
    }

    static func migrateLegacyApplicationSupportIfNeeded() {
        let fm = FileManager.default
        guard let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            Logger.loveMigration.error("Application Support directory URL unavailable")
            return
        }

        let legacyDir = appSupport.appendingPathComponent(legacyDirName, isDirectory: true)
        let legacyStore = legacyDir.appendingPathComponent(legacyStoreName)
        let newDir = appSupport.appendingPathComponent(newDirName, isDirectory: true)
        let newStore = newDir.appendingPathComponent(newStoreName)

        guard !fm.fileExists(atPath: newStore.path) else { return }

        do {
            try fm.createDirectory(at: newDir, withIntermediateDirectories: true)
        } catch {
            Logger.loveMigration.error("createDirectory Love failed: \(error.localizedDescription)")
            return
        }

        guard fm.fileExists(atPath: legacyStore.path) else { return }

        do {
            try fm.copyItem(at: legacyStore, to: newStore)
        } catch {
            Logger.loveMigration.error("copy legacy FocusPath.store failed: \(error.localizedDescription)")
            UserDefaults.standard.set(
                "Love could not copy your old FocusPath database (\(error.localizedDescription)). A new library will be created when the app opens.",
                forKey: pendingFailureUserDefaultsKey
            )
            return
        }

        applyStoreFilePermissions(newStore.path)

        for suffix in ["-wal", "-shm"] {
            let legacySidecar = URL(fileURLWithPath: legacyStore.path + suffix)
            let newSidecar = URL(fileURLWithPath: newStore.path + suffix)
            guard fm.fileExists(atPath: legacySidecar.path) else { continue }
            do {
                if fm.fileExists(atPath: newSidecar.path) {
                    try fm.removeItem(at: newSidecar)
                }
                try fm.copyItem(at: legacySidecar, to: newSidecar)
                applyStoreFilePermissions(newSidecar.path)
            } catch {
                Logger.loveMigration.warning("copy sidecar \(suffix) failed (main store copied): \(error.localizedDescription)")
            }
        }
    }

    private static func applyStoreFilePermissions(_ path: String) {
        chmod(path, 0o600)
    }
}
