// macOS only. Build on the host with Xcode (see App/README.md).
#if canImport(SwiftUI) && os(macOS)
import Foundation
import Observation
import SentinelCore

/// Top-level app state. Owns the monitor loop and wires the macOS layer to
/// `SentinelCore`. This is a skeleton — the loop body is filled in on the host
/// once the AX structure is known (docs/accessibility-tree.md).
@Observable
@MainActor
final class AppModel {
    private(set) var targets: [MonitorTarget] = []
    private(set) var statesByTarget: [UUID: SessionState] = [:]

    var scheduler = ResumeScheduler()
    var patternSet: PatternSet = (try? PatternSet.bundled()) ?? PatternSet(version: 1, patterns: [])
    var limits: SafetyLimits = .default

    private let clock: any SentinelClock = SystemClock()

    /// Overall status for the menu-bar glyph.
    var menuBarSymbolName: String {
        let states = statesByTarget.values
        if states.contains(where: { if case .errored = $0 { return true } else { return false } }) {
            return "exclamationmark.triangle.fill"
        }
        if states.contains(where: { $0.resetAt != nil }) { return "hourglass" }
        if states.contains(.working) { return "gearshape.2.fill" }
        if states.contains(where: \.isStall) { return "pause.circle.fill" }
        return "checkmark.circle"
    }

    // TODO(host): implement
    //  - loadTargets()/saveTargets() via TargetStore
    //  - the per-target polling loop using PollingInterval.seconds(for:now:)
    //  - AXTreeReader -> AXSnapshot -> DetectionEngine.classify
    //  - on a stall: scheduler.enqueue(...); on dispatch .start -> ResumeController
    //  - Notifier for local + webhook notifications
}
#endif
