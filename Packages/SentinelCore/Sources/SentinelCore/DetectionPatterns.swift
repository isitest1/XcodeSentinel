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

    /// Why a rule did or did not fire. `blockedByNoneOf` and `disabled` are
    /// surfaced as "near misses" by `DetectionEngine` so the Settings
    /// "Test Detection" screen can explain what almost matched.
    public enum Evaluation: Sendable, Equatable {
        case matched
        /// Positive text was present but a `noneOf` term also appeared.
        case blockedByNoneOf(String)
        /// Positive text exists in the tree, but not on a node with `role`.
        case blockedByRole
        /// The rule is disabled but its positive text is present.
        case wouldMatchIfEnabled
        /// No positive text matched, or the rule has no positive requirement.
        case noMatch
    }

    /// Whether this rule matches the given text fragments.
    func matches(fragments: [TextFragment]) -> Bool {
        evaluate(fragments: fragments) == .matched
    }

    /// Full evaluation, including the reasons a near-match was rejected.
    func evaluate(fragments: [TextFragment]) -> Evaluation {
        guard !(anyOf.isEmpty && allOf.isEmpty) else { return .noMatch }

        func present(_ needles: [String], in texts: [String]) -> Bool {
            let hay = texts.map { caseSensitive ? $0 : $0.lowercased() }
            return needles.contains { needle in
                let n = caseSensitive ? needle : needle.lowercased()
                return hay.contains { $0.contains(n) }
            }
        }
        func firstPresent(_ needles: [String], in texts: [String]) -> String? {
            let hay = texts.map { caseSensitive ? $0 : $0.lowercased() }
            return needles.first { needle in
                let n = caseSensitive ? needle : needle.lowercased()
                return hay.contains { $0.contains(n) }
            }
        }

        let allTexts = fragments.map(\.text)
        let scopedTexts: [String] = {
            guard let role else { return allTexts }
            return fragments.filter { $0.role == role }.map(\.text)
        }()

        // Does the positive requirement hold, ignoring role scoping?
        let anyOfHoldsUnscoped = anyOf.isEmpty || present(anyOf, in: allTexts)
        let allOfHoldsUnscoped = allOf.isEmpty || allOf.allSatisfy { present([$0], in: allTexts) }
        let positiveUnscoped = anyOfHoldsUnscoped && allOfHoldsUnscoped

        guard positiveUnscoped else { return .noMatch }

        // Role scoping.
        if role != nil {
            let anyScoped = anyOf.isEmpty || present(anyOf, in: scopedTexts)
            let allScoped = allOf.isEmpty || allOf.allSatisfy { present([$0], in: scopedTexts) }
            guard anyScoped && allScoped else { return .blockedByRole }
        }

        if let blocker = firstPresent(noneOf, in: scopedTexts.isEmpty ? allTexts : scopedTexts) {
            return .blockedByNoneOf(blocker)
        }

        return enabled ? .matched : .wouldMatchIfEnabled
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
    /// Hints for finding the Claude panel subtree inside a whole-window AX
    /// snapshot, before running the patterns. Optional; when empty the engine
    /// scans the entire tree.
    public var panelHints: PanelHints

    public init(version: Int, patterns: [DetectionPattern], panelHints: PanelHints = .init()) {
        self.version = version
        self.patterns = patterns
        self.panelHints = panelHints
    }

    private enum CodingKeys: String, CodingKey {
        case version, patterns, panelHints
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int.self, forKey: .version)
        patterns = try c.decode([DetectionPattern].self, forKey: .patterns)
        panelHints = try c.decodeIfPresent(PanelHints.self, forKey: .panelHints) ?? .init()
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

/// Heuristics for locating the Claude panel within a full Xcode-window AX tree.
/// Verified against a real Xcode AX dump (2026-08-31) — values now reflect
/// actual Xcode structure.
public struct PanelHints: Codable, Equatable, Sendable {
    /// `AXIdentifier` values that mark the panel container, most specific first.
    public var identifiers: [String]
    /// Substrings that, if present in a subtree's text, strongly suggest it is
    /// the panel (e.g. the composer placeholder).
    public var anchorTexts: [String]
    /// Roles a panel container is likely to have.
    public var containerRoles: [String]
    /// AX node that appears at the end of every completed Claude response.
    /// Used to locate the "current turn" tail within the panel's chat history.
    public var completedTurnMarker: CompletedTurnMarker?

    public init(
        identifiers: [String] = [],
        anchorTexts: [String] = [],
        containerRoles: [String] = [],
        completedTurnMarker: CompletedTurnMarker? = nil
    ) {
        self.identifiers = identifiers
        self.anchorTexts = anchorTexts
        self.containerRoles = containerRoles
        self.completedTurnMarker = completedTurnMarker
    }

    private enum CodingKeys: String, CodingKey {
        case identifiers, anchorTexts, containerRoles, completedTurnMarker
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        identifiers = try c.decodeIfPresent([String].self, forKey: .identifiers) ?? []
        anchorTexts = try c.decodeIfPresent([String].self, forKey: .anchorTexts) ?? []
        containerRoles = try c.decodeIfPresent([String].self, forKey: .containerRoles) ?? []
        completedTurnMarker = try c.decodeIfPresent(CompletedTurnMarker.self, forKey: .completedTurnMarker)
    }

    public var isEmpty: Bool {
        identifiers.isEmpty && anchorTexts.isEmpty && containerRoles.isEmpty
    }
}

/// Identifies the AX node that ends a completed Claude response turn.
/// Verified: Xcode appends an AXButton with descriptionText "Report Concern"
/// after every finished response (2026-08-31 AX dump).
public struct CompletedTurnMarker: Codable, Equatable, Sendable {
    public var role: String
    public var descriptionText: String

    public init(role: String, descriptionText: String) {
        self.role = role
        self.descriptionText = descriptionText
    }
}
