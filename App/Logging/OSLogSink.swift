// macOS only. Build on the host with Xcode (see App/README.md).
#if os(macOS)
import Foundation
import OSLog
import SentinelCore

/// Forwards `SentinelCore` log records to the unified logging system.
/// Chat text and source code must never reach here (CLAUDE.md sections 8.2, 12).
public struct OSLogSink: LogSink {
    private let base: os.Logger

    public init(subsystem: String = "app.xcodesentinel") {
        self.base = os.Logger(subsystem: subsystem, category: "core")
    }

    public func write(_ record: LogRecord) {
        let meta = record.metadata
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
        let line = "\(record.message) \(meta)"
        switch record.level {
        case .debug: base.debug("\(line, privacy: .public)")
        case .info: base.info("\(line, privacy: .public)")
        case .notice: base.notice("\(line, privacy: .public)")
        case .warning: base.warning("\(line, privacy: .public)")
        case .error: base.error("\(line, privacy: .public)")
        }
    }
}
#endif
