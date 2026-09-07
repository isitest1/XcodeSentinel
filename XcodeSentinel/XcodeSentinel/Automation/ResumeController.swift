import AppKit
import ApplicationServices
import Foundation
import OSLog
import SentinelCore

private let log = os.Logger(subsystem: "com.kohei.XcodeSentinel", category: "resume")

/// Performs a single resume against one Xcode window: writes the resume prompt
/// into the chat input, presses Send, then confirms the session moved to
/// .working within 15 s (CLAUDE.md section 7.1).
/// Only called via ResumeScheduler dispatch, never by the monitor loop directly.
@AccessibilityActor
public struct ResumeController {
    public enum Outcome: Sendable, Equatable {
        case sent
        case couldNotFindInput
        case couldNotConfirmProgress
        case dryRun
    }

    public nonisolated init() {}

    /// - Parameters:
    ///   - confirmProgress: When false, return `.sent` immediately after pressing Return
    ///     without the 15-second polling check. Use `false` for scheduler-driven sends
    ///     where we don't need to verify Claude started responding.
    public func resume(
        window: AXUIElement,
        prompt: String,
        dryRun: Bool,
        confirmProgress: Bool = true
    ) async -> Outcome {
        guard !dryRun else { return .dryRun }

        // 1. Find the chat input field inside the window.
        guard let inputElement = Self.findChatInput(in: window) else {
            log.error("resume: chat input not found in window")
            return .couldNotFindInput
        }
        let role = Self.string(inputElement, kAXRoleAttribute) ?? "?"
        log.info("resume: found input role=\(role, privacy: .public)")

        // 2. Bring the Xcode window to the foreground so CGEvents land correctly.
        //    kAXFocusedAttribute writes alone are unreliable for WKWebView-based
        //    inputs (Xcode's Claude panel), so we activate the app first.
        Self.activateWindow(window)
        try? await Task.sleep(nanoseconds: 500_000_000) // Allow Space switch to complete

        // Verify Xcode is actually frontmost before proceeding.
        if let pid = Self.pid(of: window) {
            let isFront = NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
            log.info("resume: xcode is frontmost after activate: \(isFront, privacy: .public)")
        }

        // Recalculate center after Space switch — position may have changed.
        let center = Self.elementCenter(inputElement)
        let desc = Self.string(inputElement, kAXDescriptionAttribute) ?? ""
        log.info("resume: element center=\(String(describing: center), privacy: .public) desc='\(desc, privacy: .public)'")

        // If the element has no screen position the Claude panel is collapsed/hidden.
        guard let center else {
            log.error("resume: element has no screen position — Claude panel may be collapsed/hidden")
            return .couldNotFindInput
        }

        // 3. ALWAYS click the element to ensure OS-level / DOM focus before any
        //    text delivery or Return press.  AX value writes do NOT move keyboard
        //    focus, so without this click Return lands in whatever Xcode element
        //    was last focused by the user (e.g. the TARGETS list).
        log.info("resume: clicking at \(center.x, privacy: .public),\(center.y, privacy: .public) to focus input")
        Self.clickAt(center)
        try? await Task.sleep(nanoseconds: 500_000_000) // Let WebKit/Xcode process the click

        // 4. Deliver the prompt text.
        //
        //    WKWebView inputs (role == AXUnknown): kAXValueAttribute writes update
        //    the accessibility tree but do NOT fire browser input/paste events.
        //    React/Vue state never updates, so the submit button stays disabled and
        //    Return does nothing.  Use clipboard paste (Cmd+V) instead — it fires
        //    a real paste event that JavaScript handles correctly.
        //
        //    Native inputs (AXTextField / AXTextArea): direct AX write is fine.
        let useClipboard = role == "AXUnknown"
        if useClipboard {
            // Clipboard paste path for WKWebView-based inputs.
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(prompt, forType: .string)
            log.info("resume: clipboard paste path (WKWebView), prompt length=\(prompt.count, privacy: .public)")

            let pid = Self.pid(of: window)
            log.info("resume: Cmd+V to pid=\(String(describing: pid), privacy: .public)")
            let src = CGEventSource(stateID: .hidSystemState)
            let vDown = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true)
            let vUp   = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false)
            vDown?.flags = .maskCommand
            vUp?.flags   = .maskCommand
            if let pid {
                vDown?.postToPid(pid)
                vUp?.postToPid(pid)
            } else {
                vDown?.post(tap: .cghidEventTap)
                vUp?.post(tap: .cghidEventTap)
            }
            try? await Task.sleep(nanoseconds: 400_000_000) // Let WebKit process the paste event

            // Read back the AX value as a best-effort confirmation.
            var valRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(inputElement, kAXValueAttribute as CFString, &valRef) == .success,
               let val = valRef as? String, !val.isEmpty {
                log.info("resume: post-paste AX value confirmed (length=\(val.count, privacy: .public))")
            } else {
                log.info("resume: post-paste AX value not readable — proceeding anyway (normal for WKWebView)")
            }
        } else {
            // Direct AX write path for native text fields.
            let wrote = AXUIElementSetAttributeValue(
                inputElement, kAXValueAttribute as CFString, prompt as CFString
            ) == .success
            log.info("resume: AX value write (native field): \(wrote, privacy: .public)")
            if !wrote {
                // Fallback to clipboard even for native fields if write failed.
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(prompt, forType: .string)
                let pid = Self.pid(of: window)
                let src = CGEventSource(stateID: .hidSystemState)
                let vDown = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true)
                let vUp   = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false)
                vDown?.flags = .maskCommand
                vUp?.flags   = .maskCommand
                if let pid { vDown?.postToPid(pid); vUp?.postToPid(pid) }
                else { vDown?.post(tap: .cghidEventTap); vUp?.post(tap: .cghidEventTap) }
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
        }

        // 6. Send. Prefer AXButton; fall back to Return key.
        if let sendButton = Self.findSendButton(in: window) {
            log.info("resume: pressing send button via AXPress")
            AXUIElementPerformAction(sendButton, kAXPressAction as CFString)
        } else {
            log.info("resume: no send button found, pressing Return to pid=\(String(describing: Self.pid(of: window)), privacy: .public)")
            try? await Task.sleep(nanoseconds: 150_000_000)
            Self.pressReturn(toPid: Self.pid(of: window))
        }

        // 6. For scheduler-driven sends, return immediately without waiting for
        //    Claude to start responding (the user is away; the 15-second check
        //    always timed out with the empty PatternSet used here).
        guard confirmProgress else {
            log.info("resume: confirmProgress=false, returning .sent")
            return .sent
        }

        // 7. Poll for .working for up to 15 s to confirm the send took.
        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            let snap = AXTreeReader().snapshot(ofWindow: window)
            let engine = DetectionEngine(patterns: PatternSet(version: 1, patterns: []))
            if engine.classify(snap).state.isProgressing { return .sent }
        }
        return .couldNotConfirmProgress
    }

    // MARK: - AX element location (verified against real Xcode AX dump 2026-08-31)

    private static func findChatInput(in window: AXUIElement) -> AXUIElement? {
        // Locate the AXGroup that is the Claude chat container:
        // - has an AXScrollArea child containing AXOpaqueProviderGroup (message history)
        // - AND has at least one AXUnknown direct child (the text input)
        // The second requirement distinguishes Claude's panel from other AXGroups
        // (e.g. the Project Navigator list) that also contain AXOpaqueProviderGroup.
        if let chatGroup = findChatGroup(in: window),
           let input = findInputInChatGroup(chatGroup) {
            log.info("findChatInput: chat group strategy succeeded")
            return input
        }
        // Do NOT fall back to searching for any AXTextArea/AXTextField in the window.
        // That risks matching Xcode's own filter/search fields (e.g. the TARGETS list
        // filter box) and sending keystrokes or clicks to them, which can corrupt the
        // Xcode UI or cause a crash. If we can't positively identify the Claude panel,
        // fail safely and return nil.
        log.warning("findChatInput: Claude chat group not found — returning nil (Claude panel may not be open)")
        return nil
    }

    /// Returns the AXGroup that is the Claude chat container. It must satisfy
    /// BOTH conditions:
    ///   1. A direct AXScrollArea child whose children include AXOpaqueProviderGroup
    ///      (the WebKit-rendered chat message history).
    ///   2. At least one direct AXUnknown child (the chat text-input field).
    /// Requiring both avoids false matches on Project Navigator groups that also
    /// contain AXOpaqueProviderGroup but have no editable AXUnknown sibling.
    private static func findChatGroup(in window: AXUIElement) -> AXUIElement? {
        findFirst(in: window, depth: 0, maxDepth: 15, matching: { element in
            guard Self.string(element, kAXRoleAttribute) == "AXGroup" else { return false }
            var ref: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &ref) == .success,
                  let children = ref as? [AXUIElement] else { return false }

            // Condition 1: scroll area with opaque provider group (chat history)
            let hasHistory = children.contains { child in
                guard Self.string(child, kAXRoleAttribute) == "AXScrollArea" else { return false }
                var childRef: CFTypeRef?
                guard AXUIElementCopyAttributeValue(child, kAXChildrenAttribute as CFString, &childRef) == .success,
                      let grandchildren = childRef as? [AXUIElement] else { return false }
                return grandchildren.contains {
                    Self.string($0, kAXRoleAttribute) == "AXOpaqueProviderGroup"
                }
            }
            guard hasHistory else { return false }

            // Condition 2: at least one AXUnknown direct child (the text input)
            return children.contains { Self.string($0, kAXRoleAttribute) == "AXUnknown" }
        })
    }

    /// Returns the chat text-input element from the Claude group's direct children.
    /// Claude's text input is typically the LAST AXUnknown child (bottom of the panel).
    /// Skips AXUnknown elements whose description suggests a filter/search field.
    private static func findInputInChatGroup(_ group: AXUIElement) -> AXUIElement? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(group, kAXChildrenAttribute as CFString, &ref) == .success,
              let children = ref as? [AXUIElement] else { return nil }
        var lastUnknown: AXUIElement? = nil
        var fallback: AXUIElement? = nil
        for child in children {
            let role = Self.string(child, kAXRoleAttribute) ?? ""
            if role == "AXUnknown" {
                let childDesc = (Self.string(child, kAXDescriptionAttribute) ?? "").lowercased()
                // Skip filter/search fields that are not the chat input
                let isFilter = childDesc.contains("filter") || childDesc.contains("search")
                if !isFilter { lastUnknown = child }
            }
            if role == "AXTextArea" || role == "AXTextField" { fallback = child }
        }
        return lastUnknown ?? fallback
    }

    private static func findSendButton(in window: AXUIElement) -> AXUIElement? {
        Self.findFirst(in: window, matching: { element in
            guard let role = Self.string(element, kAXRoleAttribute),
                  role == "AXButton" else { return false }
            let title = Self.string(element, kAXTitleAttribute) ?? ""
            let desc  = Self.string(element, kAXDescriptionAttribute) ?? ""
            let text  = (title + desc).lowercased()
            return text.contains("send") || text.contains("submit")
        })
    }

    private static func findFirst(
        in element: AXUIElement,
        depth: Int = 0,
        maxDepth: Int = 30,
        matching predicate: (AXUIElement) -> Bool
    ) -> AXUIElement? {
        if predicate(element) { return element }
        guard depth < maxDepth else { return nil }
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &ref) == .success,
              let children = ref as? [AXUIElement] else { return nil }
        for child in children {
            if let hit = findFirst(in: child, depth: depth + 1, maxDepth: maxDepth, matching: predicate) {
                return hit
            }
        }
        return nil
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success,
              let str = ref as? String else { return nil }
        return str
    }

    private static func pid(of element: AXUIElement) -> pid_t? {
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success else { return nil }
        return pid
    }

    /// Posts a Return keypress to the target process rather than the global HID
    /// tap, reducing the risk of the key landing in the wrong window.
    private static func pressReturn(toPid pid: pid_t?) {
        let src = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: 0x24, keyDown: true)
        let up   = CGEvent(keyboardEventSource: src, virtualKey: 0x24, keyDown: false)
        if let pid {
            down?.postToPid(pid)
            up?.postToPid(pid)
        } else {
            down?.post(tap: .cghidEventTap)
            up?.post(tap: .cghidEventTap)
        }
    }

    /// Activates the Xcode app and raises the target window to the foreground.
    private static func activateWindow(_ window: AXUIElement) {
        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(window, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        if let pid = Self.pid(of: window) {
            NSRunningApplication(processIdentifier: pid)?.activate()
        }
    }

    /// Returns the screen-space center of an AX element, or nil if unreachable.
    private static func elementCenter(_ element: AXUIElement) -> CGPoint? {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let posRef, let sizeRef else { return nil }
        var pt = CGPoint.zero
        var sz = CGSize.zero
        // AXValue is a CFType; the force-cast is safe because
        // kAXPositionAttribute/kAXSizeAttribute always return AXValue.
        AXValueGetValue(posRef as! AXValue, .cgPoint, &pt)
        AXValueGetValue(sizeRef as! AXValue, .cgSize, &sz)
        guard sz.width > 0, sz.height > 0 else { return nil }
        return CGPoint(x: pt.x + sz.width / 2, y: pt.y + sz.height / 2)
    }

    /// Posts a left mouse click at the given screen point via the global HID tap.
    /// This gives OS-level focus to whatever UI element is at that point —
    /// required for WKWebView inputs that ignore kAXFocusedAttribute writes.
    private static func clickAt(_ point: CGPoint) {
        let src = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(mouseEventSource: src, mouseType: .leftMouseDown,
                           mouseCursorPosition: point, mouseButton: .left)
        let up   = CGEvent(mouseEventSource: src, mouseType: .leftMouseUp,
                           mouseCursorPosition: point, mouseButton: .left)
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    /// Writes `text` to the clipboard then sends Cmd+V to `element`.
    /// Used when AXValue write is not supported (e.g. AXUnknown input fields).
    @discardableResult
    private static func pasteViaClipboard(
        _ text: String, into element: AXUIElement, window: AXUIElement
    ) -> Bool {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        // Focus the target element first.
        AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        guard let pid = Self.pid(of: window) else { return false }
        let src = CGEventSource(stateID: .hidSystemState)
        let vDown = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true)
        let vUp   = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false)
        vDown?.flags = .maskCommand
        vUp?.flags   = .maskCommand
        vDown?.postToPid(pid)
        vUp?.postToPid(pid)
        return true
    }
}

