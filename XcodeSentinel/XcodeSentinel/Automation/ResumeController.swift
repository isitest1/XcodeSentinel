import AppKit
import ApplicationServices
import Foundation
import SentinelCore

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

    public func resume(
        window: AXUIElement,
        prompt: String,
        dryRun: Bool
    ) async -> Outcome {
        guard !dryRun else { return .dryRun }

        // 1. Find the chat input field inside the window.
        guard let inputElement = Self.findChatInput(in: window) else {
            return .couldNotFindInput
        }

        // 2. Write the prompt into the field.
        // AXValue write works for AXTextArea/AXTextField. For AXUnknown (Xcode's
        // Claude input, verified 2026-08-31), fall back to clipboard paste.
        let writeResult = AXUIElementSetAttributeValue(
            inputElement, kAXValueAttribute as CFString, prompt as CFString
        )
        if writeResult != .success {
            guard Self.pasteViaClipboard(prompt, into: inputElement, window: window)
            else { return .couldNotFindInput }
        }

        // 3. Send. Xcode's Claude panel has no AXButton with "send"/"submit"
        // (verified 2026-08-31). Focus the input then press Return.
        if let sendButton = Self.findSendButton(in: window) {
            AXUIElementPerformAction(sendButton, kAXPressAction as CFString)
        } else {
            AXUIElementSetAttributeValue(inputElement, kAXFocusedAttribute as CFString, kCFBooleanTrue)
            // Small delay to let focus settle before sending.
            try? await Task.sleep(nanoseconds: 150_000_000)
            Self.pressReturn(toPid: Self.pid(of: window))
        }

        // 4. Poll for .working for up to 15 s to confirm the send took.
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
        // Strategy 1: Locate the AXGroup containing AXOpaqueProviderGroup (the
        // Claude chat container), then return its AXUnknown sibling — the actual
        // chat input field in Xcode's Claude panel.
        if let chatGroup = findChatGroup(in: window),
           let input = findInputInChatGroup(chatGroup) {
            return input
        }
        // Strategy 2: Fallback for future Xcode versions that may expose a typed field.
        return findFirst(in: window, matching: { element in
            guard let role = Self.string(element, kAXRoleAttribute) else { return false }
            return role == "AXTextArea" || role == "AXTextField"
        })
    }

    /// Returns the AXGroup whose DIRECT children include an AXScrollArea that
    /// contains an AXOpaqueProviderGroup (the Claude chat scroll area).
    private static func findChatGroup(in window: AXUIElement) -> AXUIElement? {
        findFirst(in: window, depth: 0, maxDepth: 15, matching: { element in
            guard Self.string(element, kAXRoleAttribute) == "AXGroup" else { return false }
            var ref: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &ref) == .success,
                  let children = ref as? [AXUIElement] else { return false }
            return children.contains { child in
                guard Self.string(child, kAXRoleAttribute) == "AXScrollArea" else { return false }
                var childRef: CFTypeRef?
                guard AXUIElementCopyAttributeValue(child, kAXChildrenAttribute as CFString, &childRef) == .success,
                      let grandchildren = childRef as? [AXUIElement] else { return false }
                return grandchildren.contains {
                    Self.string($0, kAXRoleAttribute) == "AXOpaqueProviderGroup"
                }
            }
        })
    }

    /// Among the direct children of the chat group, returns the first AXUnknown
    /// (the Claude text input) or any AXTextArea/AXTextField as a fallback.
    private static func findInputInChatGroup(_ group: AXUIElement) -> AXUIElement? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(group, kAXChildrenAttribute as CFString, &ref) == .success,
              let children = ref as? [AXUIElement] else { return nil }
        var fallback: AXUIElement? = nil
        for child in children {
            let role = Self.string(child, kAXRoleAttribute) ?? ""
            if role == "AXUnknown" { return child }
            if role == "AXTextArea" || role == "AXTextField" { fallback = child }
        }
        return fallback
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

