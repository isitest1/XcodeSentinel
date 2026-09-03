import ApplicationServices
import Foundation

/// Every call into the Accessibility API is serialized onto this global actor.
/// The AX API is not thread-safe (CLAUDE.md sections 4.2 and 12).
@globalActor
public actor AccessibilityActor {
    public static let shared = AccessibilityActor()
}

// AXUIElement handles are reference-counted opaque pointers. The actual AX API
// calls are serialized on AccessibilityActor; passing the handle itself between
// actors is safe, so we opt into Swift 6's Sendable system here.
extension AXUIElement: @retroactive @unchecked Sendable {}

extension AccessibilityActor {
    /// Runs a synchronous closure on AccessibilityActor, analogous to MainActor.run.
    /// GlobalActor does not synthesise run() automatically, so we add it here.
    @AccessibilityActor
    static func run<T: Sendable>(_ body: @AccessibilityActor @Sendable () throws -> T) rethrows -> T {
        try body()
    }
}

@MainActor
public enum AccessibilityPermission {
    public static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    @discardableResult
    public static func requestIfNeeded() -> Bool {
        // Use the string literal directly to avoid referencing the C global var,
        // which Swift 6 strict concurrency flags as shared mutable state.
        let options = ["AXTrustedCheckOptionPrompt": true]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
}
