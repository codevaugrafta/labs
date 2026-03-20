import Foundation

/// Distinguishes packaged `Adhan.app` from `swift run` / Xcode debug (different `Bundle.main` paths).
enum AdhanBuildInfo {
    static var marketingVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    static var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }

    static var versionSummary: String { "\(marketingVersion) (\(buildNumber))" }

    static var bundlePath: String { Bundle.main.bundlePath }

    /// True when running from SPM / Xcode build products (not `build/Adhan.app` or `/Applications`).
    static var isLikelySwiftPMOrDebugRun: Bool {
        let p = bundlePath
        if p.contains(".build/") { return true }
        if p.contains("DerivedData") { return true }
        if p.contains("/Build/Products/") { return true }
        return false
    }

    /// Short label for the menu bar.
    static var runKindMenuLabel: String {
        isLikelySwiftPMOrDebugRun ? "debug / swift run" : "Adhan.app"
    }

    /// Shown in Settings (About) so users know whether they are on a packaged app vs debug run.
    static var userFacingInstallHint: String {
        if isLikelySwiftPMOrDebugRun {
            """
            This copy is running from a build/debug path (e.g. swift run or Xcode), not the packaged app.

            Quit this instance, then open:
            • /Applications/Adhan.app, or
            • Adhan/build/Adhan.app after ./build-app.sh
            """
        } else {
            "This copy is running from an .app bundle (expected for daily use)."
        }
    }
}
