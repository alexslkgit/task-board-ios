import Foundation
import os

nonisolated extension Logger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "TaskBoard"

    static let network = Logger(subsystem: subsystem, category: "network")
    static let repository = Logger(subsystem: subsystem, category: "repository")
    static let tasks = Logger(subsystem: subsystem, category: "tasks")
    static let ui = Logger(subsystem: subsystem, category: "ui")
}
