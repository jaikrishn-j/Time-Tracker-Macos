import Foundation
import OSLog

enum AppLogger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.jk.TimeTracker"

    static let persistence = Logger(subsystem: subsystem, category: "Persistence")
    static let timers = Logger(subsystem: subsystem, category: "Timers")
    static let calendar = Logger(subsystem: subsystem, category: "Calendar")
    static let sync = Logger(subsystem: subsystem, category: "Sync")
    static let settings = Logger(subsystem: subsystem, category: "Settings")
}
