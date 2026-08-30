import Foundation

/// The persisted identity of a monitored target. PIDs are not stable across
/// Xcode restarts, so only the workspace path and the user's display name are
/// stored; the live window is re-resolved on each launch (CLAUDE.md section 5.1).
public struct TargetIdentity: Sendable, Equatable, Codable {
    /// Absolute path to the `.xcodeproj` / `.xcworkspace` (or its containing
    /// folder for a Swift package opened directly).
    public var workspacePath: String
    /// User-assigned label, e.g. "SampleApp - main".
    public var displayName: String

    public init(workspacePath: String, displayName: String) {
        self.workspacePath = workspacePath
        self.displayName = displayName
    }

    /// The workspace file name without extension, e.g. `/a/b/SampleApp.xcodeproj`
    /// → `SampleApp`. Used for title matching.
    public var workspaceName: String {
        WorkspacePath.name(from: workspacePath)
    }
}

/// A lightweight, macOS-independent description of one candidate Xcode window.
/// The app fills this in from the AX/CG APIs; the resolver never touches those.
public struct WindowDescriptor: Sendable, Equatable, Codable, Identifiable {
    public var id: Int { windowNumber ?? pid.map(Int.init) ?? axTitle.hashValue }

    /// Owning process id, if known.
    public var pid: Int32?
    /// CoreGraphics window number, if known.
    public var windowNumber: Int?
    /// `AXDocument` rendered as a filesystem path (the workspace URL), if the
    /// window exposes one.
    public var axDocumentPath: String?
    /// `AXTitle` of the window.
    public var axTitle: String?

    public init(
        pid: Int32? = nil,
        windowNumber: Int? = nil,
        axDocumentPath: String? = nil,
        axTitle: String? = nil
    ) {
        self.pid = pid
        self.windowNumber = windowNumber
        self.axDocumentPath = axDocumentPath
        self.axTitle = axTitle
    }
}

/// How confident a resolution is. Callers may choose to require `.high` before
/// performing any automated action.
public enum MatchConfidence: Int, Sendable, Equatable, Comparable, Codable {
    case low = 0
    case medium = 1
    case high = 2

    public static func < (lhs: MatchConfidence, rhs: MatchConfidence) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// The result of trying to bind a persisted `TargetIdentity` to a live window.
public enum TargetResolution: Sendable, Equatable {
    case matched(WindowDescriptor, confidence: MatchConfidence)
    /// More than one window matched equally well — the app should ask the user.
    case ambiguous([WindowDescriptor])
    case notFound
}

/// Binds a persisted target to one of the currently-open Xcode windows.
///
/// Priority (CLAUDE.md section 5.1):
///  1. `AXDocument` path equals the workspace path            → `.high`
///  2. `AXTitle` contains the workspace file name             → `.medium`
///  3. `AXTitle` contains the user's display name             → `.low`
public enum TargetResolver {
    public static func resolve(
        _ identity: TargetIdentity,
        among windows: [WindowDescriptor]
    ) -> TargetResolution {
        guard !windows.isEmpty else { return .notFound }

        let wantedPath = WorkspacePath.normalize(identity.workspacePath)
        let wantedName = identity.workspaceName.lowercased()
        let wantedDisplay = identity.displayName.lowercased()

        func score(_ window: WindowDescriptor) -> MatchConfidence? {
            if let doc = window.axDocumentPath,
               WorkspacePath.normalize(doc) == wantedPath {
                return .high
            }
            let title = (window.axTitle ?? "").lowercased()
            if !wantedName.isEmpty, title.contains(wantedName) {
                return .medium
            }
            if !wantedDisplay.isEmpty, title.contains(wantedDisplay) {
                return .low
            }
            return nil
        }

        let scored = windows.compactMap { window -> (WindowDescriptor, MatchConfidence)? in
            score(window).map { (window, $0) }
        }
        guard let best = scored.map(\.1).max() else { return .notFound }

        let winners = scored.filter { $0.1 == best }.map(\.0)
        if winners.count == 1 {
            return .matched(winners[0], confidence: best)
        }
        return .ambiguous(winners)
    }
}

/// Path helpers for workspace identification. Pure string work so it runs on
/// Linux in tests.
public enum WorkspacePath {
    /// File name without extension: `/a/b/SampleApp.xcworkspace` → `SampleApp`.
    /// A trailing slash is tolerated. An empty path yields "".
    public static func name(from path: String) -> String {
        let trimmed = path.hasSuffix("/") ? String(path.dropLast()) : path
        let last = trimmed.split(separator: "/").last.map(String.init) ?? trimmed
        guard let dot = last.lastIndex(of: "."), dot != last.startIndex else {
            return last
        }
        return String(last[last.startIndex..<dot])
    }

    /// Normalizes a path for comparison: strips a `file://` scheme, percent
    /// decoding, a single trailing slash, and collapses `//`.
    public static func normalize(_ path: String) -> String {
        var value = path
        if value.hasPrefix("file://") {
            value = String(value.dropFirst("file://".count))
        }
        value = value.removingPercentEncoding ?? value
        while value.contains("//") {
            value = value.replacingOccurrences(of: "//", with: "/")
        }
        if value.count > 1, value.hasSuffix("/") {
            value = String(value.dropLast())
        }
        return value
    }
}
