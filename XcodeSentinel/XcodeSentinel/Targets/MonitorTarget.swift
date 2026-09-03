import Foundation

/// A monitored Xcode window. Persisted by workspacePath + displayName and
/// re-resolved to a live window on each launch (CLAUDE.md section 5).
public struct MonitorTarget: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public var displayName: String
    public var workspacePath: String
    public var isEnabled: Bool
    public var priority: Int
    public var resumePrompt: String
    public var maxAutoResumesPerDay: Int
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
