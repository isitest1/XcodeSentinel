// This model has no macOS dependency, but it lives with the app because target
// registration/persistence is an app concern. If detection logic ever needs it,
// move it into SentinelCore instead of importing AppKit here.
import Foundation

/// A monitored Xcode window. Persisted by `workspacePath` + `displayName` and
/// re-resolved to a live window on each launch (CLAUDE.md section 5).
public struct MonitorTarget: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    /// User-facing label, e.g. "SampleApp - main".
    public var displayName: String
    /// Resolved back to a window on relaunch (PID is not stable).
    public var workspacePath: String
    public var isEnabled: Bool
    /// Lower runs first in the resume queue.
    public var priority: Int
    /// Default: "Please continue from where you stopped."
    public var resumePrompt: String
    /// Safety cap, default 12.
    public var maxAutoResumesPerDay: Int
    /// Default 120s.
    public var minIntervalBetweenResumes: TimeInterval
    public var notifyOnStall: Bool
    public var requiresManualApprovalForDestructiveStops: Bool

    public init(
        id: UUID = UUID(),
        displayName: String,
        workspacePath: String,
        isEnabled: Bool = true,
        priority: Int = 0,
        resumePrompt: String = "Please continue from where you stopped.",
        maxAutoResumesPerDay: Int = 12,
        minIntervalBetweenResumes: TimeInterval = 120,
        notifyOnStall: Bool = true,
        requiresManualApprovalForDestructiveStops: Bool = true
    ) {
        self.id = id
        self.displayName = displayName
        self.workspacePath = workspacePath
        self.isEnabled = isEnabled
        self.priority = priority
        self.resumePrompt = resumePrompt
        self.maxAutoResumesPerDay = maxAutoResumesPerDay
        self.minIntervalBetweenResumes = minIntervalBetweenResumes
        self.notifyOnStall = notifyOnStall
        self.requiresManualApprovalForDestructiveStops = requiresManualApprovalForDestructiveStops
    }
}
