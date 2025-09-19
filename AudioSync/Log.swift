import os
enum LogLevel: Int {
    case debug = 0
    case info = 1
    case warning = 2
    case error = 3
}
enum Log {
    static let subsystem = "com.solo.AudioSync"

    static let general = AppLogger(subsystem: subsystem, category: "general")
    static let backend = AppLogger(subsystem: subsystem, category: "backend")
    static let ui = AppLogger(subsystem: subsystem, category: "ui")
}
/// 封装 Logger，支持全局等级控制
struct AppLogger {
    let logger: Logger
    let category: String
    
    static var globalLevel: LogLevel = .debug // 可动态修改
    
    init(subsystem: String, category: String) {
        self.logger = Logger(subsystem: subsystem, category: category)
        self.category = category
    }
    
    func debug(_ message: String) {
        guard AppLogger.globalLevel.rawValue <= LogLevel.debug.rawValue else { return }
        logger.debug("\(message, privacy: .public)")
    }
    
    func info(_ message: String) {
        guard AppLogger.globalLevel.rawValue <= LogLevel.info.rawValue else { return }
        logger.info("\(message, privacy: .public)")
    }
    
    func warning(_ message: String) {
        guard AppLogger.globalLevel.rawValue <= LogLevel.warning.rawValue else { return }
        logger.warning("\(message, privacy: .public)")
    }
    
    func error(_ message: String) {
        guard AppLogger.globalLevel.rawValue <= LogLevel.error.rawValue else { return }
        logger.error("\(message, privacy: .public)")
    }
}
