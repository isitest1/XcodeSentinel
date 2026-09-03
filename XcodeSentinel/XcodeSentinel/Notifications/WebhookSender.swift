import Foundation
import SentinelCore

/// Sends the away-from-Mac webhook. Formatting is handled by
/// SentinelCore.WebhookPayloadBuilder (unit-tested on Linux).
public struct WebhookSender: Sendable {
    public var endpoint: URL
    public var preset: WebhookPreset
    public var customTemplate: String?

    public init(endpoint: URL, preset: WebhookPreset, customTemplate: String? = nil) {
        self.endpoint = endpoint
        self.preset = preset
        self.customTemplate = customTemplate
    }

    public func send(targetName: String, line: String, now: Date = Date()) async throws {
        let payload = WebhookPayloadBuilder.build(
            preset: preset,
            endpoint: endpoint,
            targetName: targetName,
            line: line,
            now: now,
            template: customTemplate
        )
        var request = URLRequest(url: payload.url)
        request.httpMethod = payload.method
        for (key, value) in payload.headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.httpBody = payload.body
        _ = try await URLSession.shared.data(for: request)
    }
}
