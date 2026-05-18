import Foundation

public enum AppLogLevel: Int, CaseIterable, Identifiable {
    case debug = 0
    case info = 1
    case warning = 2
    case error = 3

    public var id: String { rawValueString }

    public var rawValueString: String {
        switch self {
        case .debug: return "debug"
        case .info: return "info"
        case .warning: return "warning"
        case .error: return "error"
        }
    }

    public var title: String {
        switch self {
        case .debug: return "Debug"
        case .info: return "Info"
        case .warning: return "Warning"
        case .error: return "Error"
        }
    }

    public var label: String {
        switch self {
        case .debug: return "DEBUG"
        case .info: return "INFO"
        case .warning: return "WARNING"
        case .error: return "ERROR"
        }
    }

    public var shouldSynchronizeImmediately: Bool {
        self == .warning || self == .error
    }

    public init?(storedValue: String) {
        switch storedValue {
        case "debug": self = .debug
        case "info": self = .info
        case "warning": self = .warning
        case "error": self = .error
        default: return nil
        }
    }
}

public struct AppFileLogger {
    private let category: String

    public init(category: String) {
        self.category = category
    }

    public func debug(_ message: @autoclosure () -> String, file: StaticString = #fileID, function: StaticString = #function, line: UInt = #line) {
        PersistentLogStore.shared.write(level: .debug, category: category, message: message(), file: file, function: function, line: line)
    }

    public func info(_ message: @autoclosure () -> String, file: StaticString = #fileID, function: StaticString = #function, line: UInt = #line) {
        PersistentLogStore.shared.write(level: .info, category: category, message: message(), file: file, function: function, line: line)
    }

    public func warning(_ message: @autoclosure () -> String, file: StaticString = #fileID, function: StaticString = #function, line: UInt = #line) {
        PersistentLogStore.shared.write(level: .warning, category: category, message: message(), file: file, function: function, line: line)
    }

    public func error(_ message: @autoclosure () -> String, file: StaticString = #fileID, function: StaticString = #function, line: UInt = #line) {
        PersistentLogStore.shared.write(level: .error, category: category, message: message(), file: file, function: function, line: line)
    }
}

public enum AppLog {
    public static let lifecycle = AppFileLogger(category: "lifecycle")
    public static let network = AppFileLogger(category: "network")
    public static let refresh = AppFileLogger(category: "refresh")
    public static let decode = AppFileLogger(category: "decode")
    public static let settings = AppFileLogger(category: "settings")

    public static var logDirectoryURL: URL {
        PersistentLogStore.shared.logDirectoryURL
    }

    public static var currentLogFileURL: URL {
        PersistentLogStore.shared.currentLogFileURL
    }

    public static func start(minimumLevel: AppLogLevel = .info) {
        PersistentLogStore.shared.start(minimumLevel: minimumLevel)
    }

    public static func setMinimumLevel(_ level: AppLogLevel) {
        PersistentLogStore.shared.setMinimumLevel(level)
    }

    public static func flush() {
        PersistentLogStore.shared.flush()
    }

    public static func shutdown(reason: String) {
        PersistentLogStore.shared.shutdown(reason: reason)
    }

    public static func clearArchivedLogs() {
        PersistentLogStore.shared.clearArchivedLogs()
    }
}
