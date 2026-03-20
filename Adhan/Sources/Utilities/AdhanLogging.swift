import OSLog

/// Unified subsystem logging for Console.app (`com.adhan.prayer-times`).
enum AdhanLog {
    private static let subsystem = "com.adhan.prayer-times"

    static let player = Logger(subsystem: subsystem, category: "Player")
    static let scheduler = Logger(subsystem: subsystem, category: "PrayerScheduler")
    static let notifications = Logger(subsystem: subsystem, category: "Notifications")
    static let data = Logger(subsystem: subsystem, category: "SwiftData")
}
