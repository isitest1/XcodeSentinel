import Foundation
import SentinelCore

/// User-persisted webhook settings (CLAUDE.md section 8.2).
/// Stored as webhook.json in Application Support alongside targets.json.
struct WebhookConfig: Codable, Equatable, Sendable {
    var isEnabled: Bool = false
    var endpoint: String = ""
    var preset: WebhookPreset = .ntfy
    var customTemplate: String = ""

    /// Returns a ready-to-use sender, or nil when disabled or the URL is invalid.
    var sender: WebhookSender? {
        guard isEnabled, !endpoint.isEmpty, let url = URL(string: endpoint) else { return nil }
        return WebhookSender(
            endpoint: url,
            preset: preset,
            customTemplate: customTemplate.isEmpty ? nil : customTemplate
        )
    }
}

/// Reads and writes WebhookConfig as JSON in Application Support/XcodeSentinel/.
struct WebhookStore: Sendable {
    private let url: URL

    init(fileManager: FileManager = .default) throws {
        let dir = try fileManager.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        ).appendingPathComponent("XcodeSentinel", isDirectory: true)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        self.url = dir.appendingPathComponent("webhook.json")
    }

    func load() throws -> WebhookConfig {
        guard FileManager.default.fileExists(atPath: url.path) else { return WebhookConfig() }
        return try JSONDecoder().decode(WebhookConfig.self, from: Data(contentsOf: url))
    }

    func save(_ config: WebhookConfig) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(config).write(to: url, options: .atomic)
    }
}
