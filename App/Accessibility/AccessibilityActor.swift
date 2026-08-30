// macOS only. Build on the host with Xcode (see App/README.md).
#if canImport(ApplicationServices) && os(macOS)
import ApplicationServices
import Foundation

/// Every call into the Accessibility API is serialized onto this global actor.
/// The AX API is not thread-safe (CLAUDE.md sections 4.2 and 12).
@globalActor
public actor AccessibilityActor {
    public static let shared = AccessibilityActor()
}

public enum AccessibilityPermission {
    /// Whether this process is currently trusted for Accessibility.
    public static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Prompts the user (once) and opens System Settings to the Accessibility
    /// pane if not yet granted.
    @discardableResult
    public static func requestIfNeeded() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
}
#endif
