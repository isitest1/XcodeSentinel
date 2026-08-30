import Foundation

/// Severity of a log record.
public enum LogLevel: Int, Sendable, Comparable, CaseIterable {
    case debug = 0
    case info = 1
    case notice = 2
    case warning = 3
    case error = 4

    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var label: String {
        switch self {
        case .debug: return "DEBUG"
        case .info: return "INFO"
        case .notice: return "NOTICE"
        case .warning: return "WARNING"
        case .error: return "ERROR"
        }
    }
}

/// A single structured log record.
///
/// `metadata` values are plain strings so a record is trivially `Sendable` and
/// encodable. Chat text and source code must never be placed here (CLAUDE.md
/// sections 8.2 and 12): keep it to target names, states and timestamps.
public struct LogRecord: Sendable, Equatable {
    public let level: LogLevel
    public let message: String
    public let metadata: [String: String]
    public let timestamp: Date

    public init(level: LogLevel, message: String, metadata: [String: String], timestamp: Date) {
        self.level = level
        self.message = message
        self.metadata = metadata
        self.timestamp = timestamp
    }
}

/// Sink for log records. The macOS app supplies an implementation that forwards
/// to the platform logger; tests use ``CollectingLogSink``.
public protocol LogSink: Sendable {
    func write(_ record: LogRecord)
}

/// Structured logger. Construct one per subsystem with a stable `subsystem`
/// label and pass it down. There is no global logger and no `print`.
public struct Logger: Sendable {
    public let subsystem: String
    public let minimumLevel: LogLevel
    private let sink: any LogSink
    private let clock: any SentinelClock

    public init(
        subsystem: String,
        sink: any LogSink,
        clock: any SentinelClock = SystemClock(),
        minimumLevel: LogLevel = .info
    ) {
        self.subsystem = subsystem
        self.sink = sink
        self.clock = clock
        self.minimumLevel = minimumLevel
    }

    public func log(_ level: LogLevel, _ message: String, _ metadata: [String: String] = [:]) {
        guard level >= minimumLevel else { return }
        var enriched = metadata
        enriched["subsystem"] = subsystem
        sink.write(LogRecord(level: level, message: message, metadata: enriched, timestamp: clock.now))
    }

    public func debug(_ message: String, _ metadata: [String: String] = [:]) { log(.debug, message, metadata) }
    public func info(_ message: String, _ metadata: [String: String] = [:]) { log(.info, message, metadata) }
    public func notice(_ message: String, _ metadata: [String: String] = [:]) { log(.notice, message, metadata) }
    public func warning(_ message: String, _ metadata: [String: String] = [:]) { log(.warning, message, metadata) }
    public func error(_ message: String, _ metadata: [String: String] = [:]) { log(.error, message, metadata) }
}

/// A `LogSink` that keeps records in memory for assertions in tests.
public final class CollectingLogSink: LogSink, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [LogRecord] = []

    public init() {}

    public func write(_ record: LogRecord) {
        lock.lock()
        storage.append(record)
        lock.unlock()
    }

    public var records: [LogRecord] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}
