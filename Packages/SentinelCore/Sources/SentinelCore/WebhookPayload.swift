import Foundation

/// Away-from-Mac notification transports with a built-in body format
/// (CLAUDE.md section 8.2).
public enum WebhookPreset: String, Sendable, Equatable, Codable, CaseIterable {
    case ntfy
    case pushover
    case discord
    case slack
    case custom
}

/// A ready-to-send HTTP request. The app layer only has to hand this to
/// `URLSession`; all formatting is done here and is unit-tested on Linux.
public struct WebhookRequest: Sendable, Equatable {
    public var method: String
    public var url: URL
    public var headers: [String: String]
    public var body: Data

    public init(method: String = "POST", url: URL, headers: [String: String], body: Data) {
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
    }

    /// The body decoded as UTF-8, for assertions and logging.
    public var bodyString: String { String(decoding: body, as: UTF8.self) }
}

/// Builds a `WebhookRequest` from a preset. The payload carries only the
/// target's display name, a one-line status and a timestamp — never chat text
/// or source code (CLAUDE.md sections 8.2 and 17).
public enum WebhookPayloadBuilder {
    /// - Parameters:
    ///   - template: required for `.custom`; `{{title}}`, `{{message}}` and
    ///     `{{timestamp}}` are substituted. Ignored for other presets.
    public static func build(
        preset: WebhookPreset,
        endpoint: URL,
        targetName: String,
        line: String,
        now: Date,
        template: String? = nil
    ) -> WebhookRequest {
        let title = "XcodeSentinel — \(targetName)"
        let timestamp = ISO8601DateFormatter().string(from: now)

        switch preset {
        case .ntfy:
            return WebhookRequest(
                url: endpoint,
                headers: ["Title": title, "Content-Type": "text/plain; charset=utf-8"],
                body: Data(line.utf8)
            )

        case .slack, .discord:
            let text = "*\(title)*\n\(line)"
            return WebhookRequest(
                url: endpoint,
                headers: ["Content-Type": "application/json"],
                body: json(["text": text])
            )

        case .pushover:
            return WebhookRequest(
                url: endpoint,
                headers: ["Content-Type": "application/json"],
                body: json(["title": title, "message": line, "timestamp": timestamp])
            )

        case .custom:
            let filled = (template ?? #"{"title":"{{title}}","message":"{{message}}","timestamp":"{{timestamp}}"}"#)
                .replacingOccurrences(of: "{{title}}", with: escapeForJSON(title))
                .replacingOccurrences(of: "{{message}}", with: escapeForJSON(line))
                .replacingOccurrences(of: "{{timestamp}}", with: escapeForJSON(timestamp))
            return WebhookRequest(
                url: endpoint,
                headers: ["Content-Type": "application/json"],
                body: Data(filled.utf8)
            )
        }
    }

    private static func json(_ object: [String: String]) -> Data {
        (try? JSONSerialization.data(
            withJSONObject: object, options: [.sortedKeys]
        )) ?? Data("{}".utf8)
    }

    /// Minimal JSON string escaping for values interpolated into a custom
    /// template (which is otherwise raw text).
    private static func escapeForJSON(_ s: String) -> String {
        var out = ""
        for scalar in s.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default: out.unicodeScalars.append(scalar)
            }
        }
        return out
    }
}
