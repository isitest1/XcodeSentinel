// macOS only in practice (uses Application Support), kept with the app layer.
#if os(macOS)
import Foundation

/// Persists `MonitorTarget`s as JSON in Application Support. Only the workspace
/// path and display name matter across launches; the live window is re-resolved
/// on startup (CLAUDE.md section 5.1).
public struct TargetStore {
    private let url: URL

    public init(fileManager: FileManager = .default) throws {
        let dir = try fileManager.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        ).appendingPathComponent("XcodeSentinel", isDirectory: true)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        self.url = dir.appendingPathComponent("targets.json")
    }

    public func load() throws -> [MonitorTarget] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try JSONDecoder().decode([MonitorTarget].self, from: Data(contentsOf: url))
    }

    public func save(_ targets: [MonitorTarget]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(targets).write(to: url, options: .atomic)
    }
}
#endif
