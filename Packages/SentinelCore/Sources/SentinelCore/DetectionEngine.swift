import Foundation

/// Turns an `AXSnapshot` into a `SessionState` using a `PatternSet`.
///
/// Design rules (CLAUDE.md sections 6.2, 6.3, 17):
///  - No screen coordinates, ever. Only AX text and roles.
///  - If nothing matches, the result is `.unknown`, never `.working`.
///  - Reset times come from `ResetTimeParser`, run over the text of the nodes
///    that triggered a limit outcome.
public struct DetectionEngine: Sendable {
    public let patterns: PatternSet
    private let clock: any SentinelClock

    public init(patterns: PatternSet, clock: any SentinelClock = SystemClock()) {
        self.patterns = patterns
        self.clock = clock
    }

    /// A classification plus the diagnostic detail the UI and logs need.
    public struct Result: Sendable, Equatable {
        public var state: SessionState
        /// The `id` of the pattern that fired, if any.
        public var matchedPatternID: String?
        /// The reset-time parse result, when the state is a limit.
        public var resetParse: ResetTimeParseResult?
        /// Text fragments considered, for the AX Inspector highlight.
        public var scannedTextCount: Int
    }

    public func classify(_ snapshot: AXSnapshot) -> Result {
        let fragments: [TextFragment] = snapshot.root.flattened().flatMap { node -> [TextFragment] in
            node.texts.map { TextFragment(text: $0, role: node.role) }
        }

        guard !fragments.isEmpty else {
            return Result(state: .unknown, matchedPatternID: nil, resetParse: nil, scannedTextCount: 0)
        }

        for pattern in patterns.patterns where pattern.matches(fragments: fragments) {
            let state = resolve(outcome: pattern.outcome, pattern: pattern, fragments: fragments)
            return Result(
                state: state.0,
                matchedPatternID: pattern.id,
                resetParse: state.1,
                scannedTextCount: fragments.count
            )
        }

        return Result(
            state: .unknown,
            matchedPatternID: nil,
            resetParse: nil,
            scannedTextCount: fragments.count
        )
    }

    private func resolve(
        outcome: DetectionOutcome,
        pattern: DetectionPattern,
        fragments: [TextFragment]
    ) -> (SessionState, ResetTimeParseResult?) {
        switch outcome {
        case .idle:
            return (.idle, nil)
        case .working:
            return (.working, nil)
        case .awaitingContinue:
            return (.awaitingContinue, nil)
        case .awaitingApproval:
            return (.awaitingApproval, nil)
        case .awaitingUserAnswer:
            return (.awaitingUserAnswer, nil)
        case .completed:
            return (.completed, nil)
        case .errored:
            let message = firstFragment(containingAnyOf: pattern.anyOf + pattern.allOf, in: fragments)
                ?? "Session ended with an error."
            return (.errored(message: message), nil)
        case .sessionLimited:
            let parse = parseReset(from: pattern, fragments: fragments)
            return (.sessionLimited(resetAt: parse?.date), parse)
        case .weeklyLimited:
            let parse = parseReset(from: pattern, fragments: fragments)
            return (.weeklyLimited(resetAt: parse?.date), parse)
        }
    }

    private func parseReset(
        from pattern: DetectionPattern,
        fragments: [TextFragment]
    ) -> ResetTimeParseResult? {
        // Try the fragments that actually contain the limit wording first, then
        // fall back to scanning every fragment.
        let triggerNeedles = (pattern.anyOf + pattern.allOf).map { $0.lowercased() }
        let carriesTrigger: (TextFragment) -> Bool = { fragment in
            let lowered = fragment.text.lowercased()
            return triggerNeedles.contains { lowered.contains($0) }
        }
        let ordered = fragments.filter(carriesTrigger) + fragments.filter { !carriesTrigger($0) }
        for fragment in ordered {
            if let parsed = ResetTimeParser.parse(
                fragment.text, now: clock.now, calendar: clock.calendar
            ) {
                return parsed
            }
        }
        return nil
    }

    private func firstFragment(containingAnyOf needles: [String], in fragments: [TextFragment]) -> String? {
        let lowered = needles.map { $0.lowercased() }
        return fragments.first { fragment in
            lowered.contains { fragment.text.lowercased().contains($0) }
        }?.text
    }
}
