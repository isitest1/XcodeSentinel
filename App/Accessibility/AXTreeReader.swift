// macOS only. Build on the host with Xcode (see App/README.md).
#if canImport(ApplicationServices) && os(macOS)
import ApplicationServices
import Foundation
import SentinelCore

/// Walks a live `AXUIElement` subtree and converts it into a `SentinelCore`
/// `AXSnapshot`. This is the ONLY place that touches the AX API for reading; the
/// detection logic downstream never sees an `AXUIElement`.
///
/// Skeleton: the concrete traversal (which attributes, depth limits, how the
/// Claude panel is located within an Xcode window) is implemented on the host
/// after inspecting a real tree — see docs/accessibility-tree.md.
@AccessibilityActor
public struct AXTreeReader {
    public init() {}

    /// Capture the Claude-panel subtree of the given Xcode window element.
    public func snapshot(
        ofWindow window: AXUIElement,
        targetName: String?,
        xcodeVersion: String?
    ) -> AXSnapshot {
        let root = Self.node(from: window, depth: 0, maxDepth: 40)
        return AXSnapshot(
            targetName: targetName,
            capturedAt: Date(),
            xcodeVersion: xcodeVersion,
            root: root
        )
    }

    private static func node(from element: AXUIElement, depth: Int, maxDepth: Int) -> AXNode {
        // TODO(host): read AXRole/AXTitle/AXValue/AXDescription/AXIdentifier,
        // AXEnabled, AXFocused; recurse over AXChildren up to maxDepth.
        AXNode(role: string(element, kAXRoleAttribute) ?? "AXUnknown")
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success
        else { return nil }
        return value as? String
    }
}
#endif
