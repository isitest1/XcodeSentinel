import AppKit
import ApplicationServices
import SentinelCore

/// Lists all currently-open Xcode windows as WindowDescriptors.
/// Pure enumeration — no modification to the UI.
@AccessibilityActor
public struct XcodeWindowEnumerator {
    public init() {}

    public func currentWindows() -> [WindowDescriptor] {
        let xcodes = NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.apple.dt.Xcode"
        )
        var out: [WindowDescriptor] = []
        for app in xcodes {
            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            var windowsRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(
                appElement, kAXWindowsAttribute as CFString, &windowsRef
            ) == .success, let windows = windowsRef as? [AXUIElement] else { continue }

            for window in windows {
                out.append(WindowDescriptor(
                    pid: app.processIdentifier,
                    axDocumentPath: Self.documentPath(of: window),
                    axTitle: Self.string(window, kAXTitleAttribute)
                ))
            }
        }
        return out
    }

    /// Returns the live AXUIElement for a window matching the given descriptor,
    /// identified by PID + title (or document path when available).
    public func liveElement(for descriptor: WindowDescriptor) -> AXUIElement? {
        guard let pid = descriptor.pid else { return nil }
        let appElement = AXUIElementCreateApplication(pid)
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            appElement, kAXWindowsAttribute as CFString, &windowsRef
        ) == .success, let windows = windowsRef as? [AXUIElement] else { return nil }

        for window in windows {
            let docPath = Self.documentPath(of: window)
            let title = Self.string(window, kAXTitleAttribute)
            if let want = descriptor.axDocumentPath, docPath == want { return window }
            if let want = descriptor.axTitle, title == want { return window }
        }
        return nil
    }

    // MARK: - Helpers

    private static func documentPath(of window: AXUIElement) -> String? {
        guard let doc = string(window, kAXDocumentAttribute) else { return nil }
        return URL(string: doc)?.path ?? doc
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success,
              let str = ref as? String, !str.isEmpty else { return nil }
        return str
    }
}
