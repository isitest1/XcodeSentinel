// macOS only. Build on the host with Xcode (see App/README.md).
#if canImport(ApplicationServices) && os(macOS)
import AppKit
import ApplicationServices
import SentinelCore

/// Lists the currently-open Xcode windows as `WindowDescriptor`s so
/// `TargetResolver` (pure logic) can bind a persisted target to a live window.
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
            var windowsValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(
                appElement, kAXWindowsAttribute as CFString, &windowsValue
            ) == .success, let windows = windowsValue as? [AXUIElement] else { continue }

            for window in windows {
                out.append(
                    WindowDescriptor(
                        pid: app.processIdentifier,
                        windowNumber: nil,
                        axDocumentPath: Self.documentPath(of: window),
                        axTitle: Self.string(window, kAXTitleAttribute)
                    )
                )
            }
        }
        return out
    }

    private static func documentPath(of window: AXUIElement) -> String? {
        guard let doc = string(window, kAXDocumentAttribute) else { return nil }
        return URL(string: doc)?.path ?? doc
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success
        else { return nil }
        return value as? String
    }
}
#endif
