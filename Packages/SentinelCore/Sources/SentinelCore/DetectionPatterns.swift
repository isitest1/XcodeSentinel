import Foundation

/// The classification a pattern produces. These mirror `SessionState.kind` but
/// carry no associated values: a JSON pattern cannot know the parsed reset
/// `Date`, which `ResetTimeParser` supplies separately (CLAUDE.md section 6.3).
public enum DetectionOutcome: String, Codable, Sendable, CaseIterable {
    case idle
    case working
    case awaitingContinue
    case sessionLimited
    case weeklyLimited
    case awaitingApproval
    case awaitingUserAnswer
    case errored
    case completed
}

/// One rule mapping visible Accessibility text to a `DetectionOutcome`.
///
/// Rules live in `Resources/Patterns.json` (not in code) so the app can follow
/// wording changes in Xcode's Claude panel without a rebuild, and users can add
/// their own from Settings (CLAUDE.md section 6.2).
public struct DetectionPattern: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    /// State to report when this rule matches.
    public var outcome: DetectionOutcome
    /// Rule matches if ANY of these substrings appears in the scanned text.
    /// An empty list means "no positive requirement" (see `allOf`).
    public var anyOf: [String]
    /// Rule matches only if ALL of these substrings appear.
    public var allOf: [String]
    /// Rule is rejected if ANY of these substrings appears.
    public var noneOf: [String]
    /// If set, only text carried by nodes whose `role` equals this value is
    /// considered for this rule.
    public var role: String?
    /// Substring comparison is case-insensitive unless this is `true`.
    public var caseSensitive: Bool
    /// Disabled rules are kept in the file but skipped during evaluation.
    public var enabled: Bool
    /// Optional human note shown in the Settings editor.
    public var note: String?

    public init(
        id: String,
        outcome: DetectionOutcome,
        anyOf: [String] = [],
        allOf: [String] = [],
        noneOf: [String] = [],
        role: String? = nil,
        caseSensitive: Bool = false,
        enabled: Bool = true,
        note: String? = nil
    ) {
        self.id = id
        self.outcome = outcome
        self.anyOf = anyOf
        self.allOf = allOf
        self.noneOf = noneOf
        self.role = role
        self.caseSensitive = caseSensitive
        self.enabled = enabled
        self.note = note
    }

    private enum CodingKeys: String, CodingKey {
        case id, outcome, anyOf, allOf, noneOf, role, caseSensitive, enabled, note
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        outcome = try c.decode(DetectionOutcome.self, forKey: .outcome)
        anyOf = try c.decodeIfPresent([String].self, forKey: .anyOf) ?? []
        allOf = try c.decodeIfPresent([String].self, forKey: .allOf) ?? []
        noneOf = try c.decodeIfPresent([String].self, forKey: .noneOf) ?? []
        role = try c.decodeIfPresent(String.self, forKey: .role)
        caseSensitive = try c.decodeIfPresent(Bool.self, forKey: .caseSensitive) ?? false
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        note = try c.decodeIfPresent(String.self, forKey: .note)
    }

    /// Whether this rule matches the given text fragments. `nil` roles in the
    /// fragment list are treated as "role unknown" and always pass a role
    /// constraint check only when the rule has no `role` set.
    func matches(fragments: [TextFragment]) -> Bool {
        guard enabled else { return false }
        guard !(anyOf.isEmpty && allOf.isEmpty) else { return false }

        let scoped: [String]
        if let role {
            scoped = fragments.filter { $0.role == role }.map(\.text)
        } else {
            scoped = fragments.map(\.text)
        }
        guard !scoped.isEmpty else { return false }

        let haystack = scoped
            .map { caseSensitive ? $0 : $0.lowercased() }

        func present(_ needle: String) -> Bool {
            let n = caseSensitive ? needle : needle.lowercased()
            return haystack.contains { $0.contains(n) }
        }

        if !noneOf.isEmpty, noneOf.contains(where: present) { return false }
        if !allOf.isEmpty, !allOf.allSatisfy(present) { return false }
        if !anyOf.isEmpty, !anyOf.contains(where: present) { return false }
        return true
    }
}

/// A piece of visible text plus the role of the node that carried it.
struct TextFragment: Equatable, Sendable {
    var text: String
    var role: String?
}

/// An ordered collection of `DetectionPattern`s plus a schema version.
///
/// Evaluation order matters: `DetectionEngine` walks `patterns` top to bottom
/// and the first rule that matches wins, so more specific rules (e.g. weekly
/// limit) must precede more general ones (e.g. session limit).
public struct PatternSet: Codable, Equatable, Sendable {
    public var version: Int
    public var patterns: [DetectionPattern]

    public init(version: Int, patterns: [DetectionPattern]) {
        self.version = version
        self.patterns = patterns
    }

    /// Decode a pattern set from JSON (the on-disk and bundled format).
    public static func decode(from data: Data) throws -> PatternSet {
        try JSONDecoder().decode(PatternSet.self, from: data)
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    /// The default rules shipped with the app, loaded from the module bundle.
    public static func bundled() throws -> PatternSet {
        guard let url = Bundle.module.url(forResource: "Patterns", withExtension: "json") else {
            throw PatternSetError.bundledResourceMissing
        }
        return try decode(from: Data(contentsOf: url))
    }

    /// IDs that appear more than once — a set is invalid if this is non-empty.
    public var duplicateIDs: [String] {
        var seen = Set<String>()
        var dupes: [String] = []
        for pattern in patterns {
            if !seen.insert(pattern.id).inserted { dupes.append(pattern.id) }
        }
        return dupes
    }
}

public enum PatternSetError: Error, Equatable {
    case bundledResourceMissing
}
