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

    /// A pattern that almost fired — shown by the Settings "Test Detection"
    /// screen so a user can see why a rule did not match.
    public struct NearMiss: Sendable, Equatable {
        public var patternID: String
        public var reason: DetectionPattern.Evaluation
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
        /// Whether panel location narrowed the tree (vs. scanning everything).
        public var panelLocated: Bool
        /// Rules that nearly matched.
        public var nearMisses: [NearMiss]
    }

    public func classify(_ snapshot: AXSnapshot) -> Result {
        let panel = locatePanel(in: snapshot)
        let marker = patterns.panelHints.completedTurnMarker

        // Step 1: Active-spinner check — most reliable "working" signal.
        // An AXProgressIndicator with no identifier/description/title/value is
        // an in-progress spinner; one with identifier "checkmark" is completed.
        // Scan from the end of the panel's children and stop at the last
        // completed-turn boundary so stale spinners from history don't fire.
        if hasActiveSpinnerInTail(panel.node, marker: marker) {
            return Result(
                state: .working,
                matchedPatternID: "active-spinner",
                resetParse: nil,
                scannedTextCount: 0,
                panelLocated: panel.located,
                nearMisses: []
            )
        }

        // Step 2: Idle check — if the last child is the completed-turn marker,
        // the most recent response is finished and Claude is waiting for input.
        if marker != nil && lastChildIsMarker(panel.node, marker: marker!) {
            return Result(
                state: .idle,
                matchedPatternID: "completed-boundary",
                resetParse: nil,
                scannedTextCount: 0,
                panelLocated: panel.located,
                nearMisses: []
            )
        }

        // Step 3: Text-pattern scan on the current turn only.
        // currentTurnNode() returns the children after the last completed-turn
        // marker, preventing stale limit messages or "Thinking" text from a
        // previous session from falsely triggering patterns.
        let scanNode = currentTurnNode(from: panel.node, marker: marker)
        let fragments = collectFragments(from: scanNode)

        guard !fragments.isEmpty else {
            return Result(
                state: .unknown, matchedPatternID: nil, resetParse: nil,
                scannedTextCount: 0, panelLocated: panel.located, nearMisses: []
            )
        }

        var nearMisses: [NearMiss] = []
        for pattern in patterns.patterns {
            switch pattern.evaluate(fragments: fragments) {
            case .matched:
                let (state, parse) = resolve(outcome: pattern.outcome, pattern: pattern, fragments: fragments)
                return Result(
                    state: state,
                    matchedPatternID: pattern.id,
                    resetParse: parse,
                    scannedTextCount: fragments.count,
                    panelLocated: panel.located,
                    nearMisses: nearMisses
                )
            case .noMatch:
                continue
            case let reason:
                nearMisses.append(NearMiss(patternID: pattern.id, reason: reason))
            }
        }

        return Result(
            state: .unknown,
            matchedPatternID: nil,
            resetParse: nil,
            scannedTextCount: fragments.count,
            panelLocated: panel.located,
            nearMisses: nearMisses
        )
    }

    // MARK: - Panel location

    /// Narrow a whole-window snapshot to the Claude-panel subtree using
    /// `patterns.panelHints`. Falls back to the whole root when hints are empty
    /// or nothing matches — detection then just scans more text, it never fails
    /// for lack of a panel.
    public func locatePanel(in snapshot: AXSnapshot) -> (node: AXNode, located: Bool) {
        let hints = patterns.panelHints
        guard !hints.isEmpty else { return (snapshot.root, false) }

        let all = snapshot.root.flattened()

        // 1. Exact AXIdentifier match, most specific hint first.
        for identifier in hints.identifiers {
            if let hit = all.first(where: { $0.identifier == identifier }) {
                return (hit, true)
            }
        }

        // 2. Smallest subtree that contains an anchor text and has an allowed
        //    container role (or any role if none configured).
        if !hints.anchorTexts.isEmpty {
            let anchors = hints.anchorTexts.map { $0.lowercased() }
            let candidates = all.filter { node in
                let roleOK = hints.containerRoles.isEmpty || hints.containerRoles.contains(node.role)
                guard roleOK else { return false }
                let text = node.flattened().flatMap(\.texts).joined(separator: "\n").lowercased()
                return anchors.contains { text.contains($0) }
            }
            if let smallest = candidates.min(by: { $0.flattened().count < $1.flattened().count }) {
                return (smallest, true)
            }
        }

        // 3. Role-only match: when anchorTexts is empty but containerRoles is set,
        //    find the first node whose role is in the list. This is used when the
        //    panel container has a unique role (e.g. AXOpaqueProviderGroup).
        if !hints.containerRoles.isEmpty {
            if let hit = all.first(where: { hints.containerRoles.contains($0.role) }) {
                return (hit, true)
            }
        }

        return (snapshot.root, false)
    }

    // MARK: - Tail helpers

    /// Returns true when an "active" AXProgressIndicator (no identifier, no
    /// descriptionText, no title, no value) appears after the last completed-turn
    /// marker in the panel's direct children. Scans backwards so it stops at the
    /// marker without inspecting stale history.
    private func hasActiveSpinnerInTail(_ panel: AXNode, marker: CompletedTurnMarker?) -> Bool {
        for child in panel.children.reversed() {
            if let m = marker,
               child.role == m.role &&
               child.descriptionText == m.descriptionText {
                return false  // Boundary reached without finding an active spinner.
            }
            if child.role == "AXProgressIndicator" &&
               (child.identifier == nil || child.identifier!.isEmpty) &&
               (child.descriptionText == nil || child.descriptionText!.isEmpty) &&
               (child.title == nil || child.title!.isEmpty) &&
               (child.value == nil || child.value!.isEmpty) {
                return true
            }
        }
        return false
    }

    /// Returns true when the last direct child of the panel is the completed-turn
    /// marker, meaning the most recent response just finished.
    private func lastChildIsMarker(_ panel: AXNode, marker: CompletedTurnMarker) -> Bool {
        guard let last = panel.children.last else { return false }
        return last.role == marker.role && last.descriptionText == marker.descriptionText
    }

    /// Returns an AXNode whose children are only the elements AFTER the last
    /// completed-turn marker. Falls back to the whole panel when no marker is
    /// configured or none is found (first-ever task).
    private func currentTurnNode(from panel: AXNode, marker: CompletedTurnMarker?) -> AXNode {
        guard let marker else { return panel }
        var lastBoundary: Int? = nil
        for (i, child) in panel.children.enumerated() {
            if child.role == marker.role && child.descriptionText == marker.descriptionText {
                lastBoundary = i
            }
        }
        guard let idx = lastBoundary else { return panel }
        let tail = idx + 1 < panel.children.count
            ? Array(panel.children[(idx + 1)...])
            : []
        return AXNode(role: panel.role, children: tail)
    }

    /// Collects TextFragments from a node. For nodes that carry no text (e.g. a
    /// plain AXProgressIndicator), emits a synthetic "role:<role>" fragment so
    /// that role-based patterns in Patterns.json can still match.
    private func collectFragments(from node: AXNode) -> [TextFragment] {
        node.flattened().flatMap { n -> [TextFragment] in
            let texts = n.texts
            guard !texts.isEmpty else {
                return [TextFragment(text: "role:\(n.role)", role: n.role)]
            }
            return texts.map { TextFragment(text: $0, role: n.role) }
        }
    }

    // MARK: - Outcome resolution

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
