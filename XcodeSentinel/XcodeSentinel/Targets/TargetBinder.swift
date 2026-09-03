import ApplicationServices
import Foundation
import SentinelCore

/// Re-binds persisted MonitorTargets to live Xcode windows on launch and
/// whenever the window set changes. The AX work is done on AccessibilityActor;
/// only WindowDescriptors (plain data) cross the actor boundary.
///
/// @unchecked Sendable: all mutable state (bindings, unresolved, ambiguous) is
/// guarded by @AccessibilityActor, making cross-actor references safe.
@AccessibilityActor
public final class TargetBinder: @unchecked Sendable {
    // Plain value-type properties so nonisolated init() can set them to empty defaults.
    public private(set) var bindings: [UUID: WindowDescriptor] = [:]
    public private(set) var unresolved: [UUID] = []
    public private(set) var ambiguous: [UUID: [WindowDescriptor]] = [:]

    public nonisolated init() {}

    public func rebind(_ targets: [MonitorTarget]) {
        let windows = XcodeWindowEnumerator().currentWindows()
        bindings.removeAll()
        unresolved.removeAll()
        ambiguous.removeAll()

        for target in targets where target.isEnabled {
            let identity = TargetIdentity(
                workspacePath: target.workspacePath,
                displayName: target.displayName
            )
            switch TargetResolver.resolve(identity, among: windows) {
            case let .matched(window, _):
                bindings[target.id] = window
            case let .ambiguous(windows):
                ambiguous[target.id] = windows
            case .notFound:
                unresolved.append(target.id)
            }
        }
    }

    /// The live AXUIElement for a bound target, resolved on demand.
    public func liveElement(for targetID: UUID) -> AXUIElement? {
        guard let descriptor = bindings[targetID] else { return nil }
        return XcodeWindowEnumerator().liveElement(for: descriptor)
    }
}
