// macOS only. Build on the host with Xcode (see App/README.md).
#if canImport(ApplicationServices) && os(macOS)
import ApplicationServices
import Foundation
import SentinelCore

/// Re-binds persisted `MonitorTarget`s to live Xcode windows on launch and
/// whenever the set of windows changes. The matching itself is pure
/// (`TargetResolver` in SentinelCore); this type only supplies the live window
/// list and holds the resulting `AXUIElement` handles.
@AccessibilityActor
public final class TargetBinder {
    private let enumerator = XcodeWindowEnumerator()
    public private(set) var bindings: [UUID: WindowDescriptor] = [:]
    public private(set) var unresolved: [UUID] = []
    public private(set) var ambiguous: [UUID: [WindowDescriptor]] = [:]

    public init() {}

    public func rebind(_ targets: [MonitorTarget]) {
        let windows = enumerator.currentWindows()
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
}
#endif
