import OSLog
import CocoaLumberjackSwift
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
    // 静态初始化 DDLog，只执行一次
        private static let ddLogSetup: Void = {
            // 初始化日志系统
            let fileLogger = DDFileLogger() // 输出到文件
            fileLogger.rollingFrequency = 60*60*24  // 每天生成一个新日志
            fileLogger.logFileManager.maximumNumberOfLogFiles = 3
            DDLog.add(fileLogger)
        }()
    
    init(subsystem: String, category: String) {
        _ = AppLogger.ddLogSetup
        self.logger = Logger(subsystem: subsystem, category: category)
        self.category = category
    }
    
    private func logToFile(_ level: LogLevel, _ message: String) {

            switch level {
            case .debug: DDLogDebug("[\(category)] \(message)")
            case .info: DDLogInfo("[\(category)] \(message)")
            case .warning: DDLogWarn("[\(category)] \(message)")
            case .error: DDLogError("[\(category)] \(message)")
            }
        }
    
    
    func debug(_ message: String) {
        guard AppLogger.globalLevel.rawValue <= LogLevel.debug.rawValue else { return }
        logger.debug("\(message, privacy: .public)")
        logToFile(.debug, message)
    }
    
    func info(_ message: String) {
        guard AppLogger.globalLevel.rawValue <= LogLevel.info.rawValue else { return }
        logger.info("\(message, privacy: .public)")
        logToFile(.info, message)
    }
    
    func warning(_ message: String) {
        guard AppLogger.globalLevel.rawValue <= LogLevel.warning.rawValue else { return }
        logger.warning("\(message, privacy: .public)")
        logToFile(.warning, message)
    }
    
    func error(_ message: String) {
        guard AppLogger.globalLevel.rawValue <= LogLevel.error.rawValue else { return }
        logger.error("\(message, privacy: .public)")
        logToFile(.error, message)
    }
}
