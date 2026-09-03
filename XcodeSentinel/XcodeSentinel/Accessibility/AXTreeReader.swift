import ApplicationServices
import Foundation
import SentinelCore

/// Walks a live AXUIElement tree and converts it to an AXSnapshot.
/// This is the ONLY place in the app that reads the AX API; detection logic
/// downstream never sees an AXUIElement (CLAUDE.md section 4.2).
@AccessibilityActor
public struct AXTreeReader {
    public init() {}

    public func snapshot(
        ofWindow window: AXUIElement,
        targetName: String? = nil,
        xcodeVersion: String? = nil
    ) -> AXSnapshot {
        let root = Self.node(from: window, depth: 0, maxDepth: 40)
        return AXSnapshot(
            targetName: targetName,
            capturedAt: Date(),
            xcodeVersion: xcodeVersion,
            root: root
        )
    }

    // MARK: - Internal

    private static func node(from element: AXUIElement, depth: Int, maxDepth: Int) -> AXNode {
        let role        = string(element, kAXRoleAttribute) ?? "AXUnknown"
        let title       = string(element, kAXTitleAttribute)
        let value       = stringValue(element)
        let description = string(element, kAXDescriptionAttribute)
        let identifier  = string(element, kAXIdentifierAttribute)
        let isEnabled   = bool(element, kAXEnabledAttribute) ?? true
        let isFocused   = bool(element, kAXFocusedAttribute) ?? false

        var children: [AXNode] = []
        if depth < maxDepth {
            var ref: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &ref) == .success,
               let axChildren = ref as? [AXUIElement] {
                children = axChildren.map { Self.node(from: $0, depth: depth + 1, maxDepth: maxDepth) }
            }
        }

        return AXNode(
            role: role,
            title: title,
            value: value,
            descriptionText: description,
            identifier: identifier,
            isEnabled: isEnabled,
            isFocused: isFocused,
            children: children
        )
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success,
              let str = ref as? String, !str.isEmpty else { return nil }
        return str
    }

    /// AXValue can be a non-string type (e.g. a number for a slider). Try String
    /// first; for other types return nil rather than a noisy description.
    private static func stringValue(_ element: AXUIElement) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &ref) == .success
        else { return nil }
        if let str = ref as? String { return str.isEmpty ? nil : str }
        return nil
    }

    private static func bool(_ element: AXUIElement, _ attribute: String) -> Bool? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success
        else { return nil }
        // AX boolean attributes come back as CFBoolean.
        if CFGetTypeID(ref) == CFBooleanGetTypeID() {
            return CFBooleanGetValue((ref as! CFBoolean))
        }
        return nil
    }
}
