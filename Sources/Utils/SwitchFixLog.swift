import Foundation
import os

public enum SwitchFixLog {
    public static let subsystem = "com.switchfix"

    public static let app = SwitchFixLogger(category: "app")
    public static let monitor = SwitchFixLogger(category: "monitor")
    public static let engine = SwitchFixLogger(category: "engine")
    public static let state = SwitchFixLogger(category: "state")
    public static let detector = SwitchFixLogger(category: "detector")
    public static let corrector = SwitchFixLogger(category: "corrector")
    public static let source = SwitchFixLogger(category: "source")
    public static let permissions = SwitchFixLogger(category: "permissions")
    public static let dictionary = SwitchFixLogger(category: "dictionary")
    public static let preferences = SwitchFixLogger(category: "preferences")
}

/// Every message is prefixed "[SwitchFix]" so it survives filtering with
/// `eventMessage CONTAINS "[SwitchFix]"`, and all dynamic values are logged
/// public so they are readable in Console.app and `log stream`.
public struct SwitchFixLogger {
    private let logger: Logger

    init(category: String) {
        self.logger = Logger(subsystem: SwitchFixLog.subsystem, category: category)
    }

    /// Visible only with `log stream --level debug`.
    public func debug(_ message: String) {
        logger.debug("[SwitchFix] \(message, privacy: .public)")
    }

    /// Visible only with `--level info` or higher verbosity.
    public func info(_ message: String) {
        logger.info("[SwitchFix] \(message, privacy: .public)")
    }

    /// Default level: visible in plain `log stream` with no --level flag.
    public func notice(_ message: String) {
        logger.notice("[SwitchFix] \(message, privacy: .public)")
    }

    public func error(_ message: String) {
        logger.error("[SwitchFix] \(message, privacy: .public)")
    }
}
