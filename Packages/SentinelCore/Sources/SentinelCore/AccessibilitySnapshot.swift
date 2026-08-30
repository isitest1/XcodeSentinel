import Foundation

/// A plain, `Codable` copy of an Accessibility element. The macOS app walks the
/// real `AXUIElement` tree (on its serial `AccessibilityActor`) and converts
/// each element into one of these before handing it to `SentinelCore`. The
/// detection logic therefore never touches the AX API (CLAUDE.md section 4.2),
/// and the AX Inspector can dump the same structure to JSON for test fixtures
/// (CLAUDE.md section 10).
public struct AXNode: Codable, Equatable, Sendable {
    /// The AX role, e.g. `AXButton`, `AXTextArea`, `AXStaticText`.
    public var role: String
    /// `AXTitle` if present.
    public var title: String?
    /// `AXValue` rendered as text if present.
    public var value: String?
    /// `AXDescription` / help text if present.
    public var descriptionText: String?
    /// `AXIdentifier` if the element exposes one.
    public var identifier: String?
    /// Whether the element is enabled (`AXEnabled`). Defaults to `true`.
    public var isEnabled: Bool
    /// Whether the element currently has keyboard focus (`AXFocused`).
    public var isFocused: Bool
    /// Child elements, in tree order.
    public var children: [AXNode]

    public init(
        role: String,
        title: String? = nil,
        value: String? = nil,
        descriptionText: String? = nil,
        identifier: String? = nil,
        isEnabled: Bool = true,
        isFocused: Bool = false,
        children: [AXNode] = []
    ) {
        self.role = role
        self.title = title
        self.value = value
        self.descriptionText = descriptionText
        self.identifier = identifier
        self.isEnabled = isEnabled
        self.isFocused = isFocused
        self.children = children
    }

    private enum CodingKeys: String, CodingKey {
        case role, title, value, descriptionText, identifier, isEnabled, isFocused, children
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        role = try c.decode(String.self, forKey: .role)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        value = try c.decodeIfPresent(String.self, forKey: .value)
        descriptionText = try c.decodeIfPresent(String.self, forKey: .descriptionText)
        identifier = try c.decodeIfPresent(String.self, forKey: .identifier)
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        isFocused = try c.decodeIfPresent(Bool.self, forKey: .isFocused) ?? false
        children = try c.decodeIfPresent([AXNode].self, forKey: .children) ?? []
    }
}

extension AXNode {
    /// Depth-first iteration over this node and every descendant.
    public func flattened() -> [AXNode] {
        var out: [AXNode] = [self]
        for child in children {
            out.append(contentsOf: child.flattened())
        }
        return out
    }

    /// All non-empty human-readable text carried directly by this node
    /// (`title`, `value`, `descriptionText`).
    public var texts: [String] {
        [title, value, descriptionText].compactMap { text in
            guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            return text
        }
    }

    /// First descendant (self included) matching `predicate`, depth-first.
    public func firstNode(where predicate: (AXNode) -> Bool) -> AXNode? {
        if predicate(self) { return self }
        for child in children {
            if let hit = child.firstNode(where: predicate) { return hit }
        }
        return nil
    }
}

/// A single detection observation: the AX tree of one Xcode window plus the
/// metadata needed to make sense of it. This is the unit passed to
/// `DetectionEngine` and the unit stored as a test fixture.
public struct AXSnapshot: Codable, Equatable, Sendable {
    /// Schema version, so old exported fixtures remain readable.
    public var schemaVersion: Int
    /// Display name of the monitored target (never a real path — the exporter
    /// scrubs this, CLAUDE.md section 14.4).
    public var targetName: String?
    /// When the snapshot was captured, if known.
    public var capturedAt: Date?
    /// The Xcode version string the snapshot came from, for triage.
    public var xcodeVersion: String?
    /// Root of the captured subtree (typically the Claude panel container).
    public var root: AXNode

    public init(
        schemaVersion: Int = 1,
        targetName: String? = nil,
        capturedAt: Date? = nil,
        xcodeVersion: String? = nil,
        root: AXNode
    ) {
        self.schemaVersion = schemaVersion
        self.targetName = targetName
        self.capturedAt = capturedAt
        self.xcodeVersion = xcodeVersion
        self.root = root
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, targetName, capturedAt, xcodeVersion, root
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        targetName = try c.decodeIfPresent(String.self, forKey: .targetName)
        capturedAt = try c.decodeIfPresent(Date.self, forKey: .capturedAt)
        xcodeVersion = try c.decodeIfPresent(String.self, forKey: .xcodeVersion)
        root = try c.decode(AXNode.self, forKey: .root)
    }

    /// Every text fragment anywhere in the tree, in depth-first order.
    public var allTexts: [String] {
        root.flattened().flatMap(\.texts)
    }

    /// Decode a snapshot from exported JSON.
    public static func decode(from data: Data) throws -> AXSnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(AXSnapshot.self, from: data)
    }

    /// Encode to pretty JSON for the AX Inspector export.
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
}
