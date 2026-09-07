import ApplicationServices
import Foundation
import IOKit.pwr_mgt
import OSLog
import Observation
import ServiceManagement
import SwiftUI
import UserNotifications
import SentinelCore

private let fireLog = os.Logger(subsystem: "com.kohei.XcodeSentinel", category: "fire")

// MARK: - Schedule model

/// A single scheduled message send.
/// The app fires `message` into `workspacePath`'s Xcode window at `sendAt`.
/// No automatic detection is involved — only what the user explicitly sets.
struct Schedule: Codable, Identifiable, Sendable {
    let id: UUID
    var displayName: String
    var workspacePath: String
    var sendAt: Date
    var message: String
    var isEnabled: Bool
    var repeatPolicy: RepeatPolicy

    init(
        id: UUID = UUID(),
        displayName: String,
        workspacePath: String,
        sendAt: Date,
        message: String = "Please continue from where you stopped.",
        isEnabled: Bool = true,
        repeatPolicy: RepeatPolicy = .once
    ) {
        self.id = id
        self.displayName = displayName
        self.workspacePath = workspacePath
        self.sendAt = sendAt
        self.message = message
        self.isEnabled = isEnabled
        self.repeatPolicy = repeatPolicy
    }
}

enum RepeatPolicy: String, Codable, CaseIterable, Sendable {
    case once     = "Once"
    case daily    = "Daily"
    case weekdays = "Weekdays only"

    func nextSendAt(after date: Date) -> Date? {
        let cal = Calendar.current
        switch self {
        case .once:
            return nil
        case .daily:
            return cal.date(byAdding: .day, value: 1, to: date)
        case .weekdays:
            guard var next = cal.date(byAdding: .day, value: 1, to: date) else { return nil }
            while cal.isDateInWeekend(next) {
                guard let n = cal.date(byAdding: .day, value: 1, to: next) else { break }
                next = n
            }
            return next
        }
    }
}

// MARK: - LogEntry

struct LogEntry: Codable, Identifiable {
    let id: UUID
    let date: Date
    let targetName: String
    let message: String
    let outcome: Outcome

    enum Outcome: String, Codable {
        case success, failure, deferred, warning
    }

    init(targetName: String, message: String, outcome: Outcome) {
        self.id = UUID()
        self.date = Date()
        self.targetName = targetName
        self.message = message
        self.outcome = outcome
    }
}

// MARK: - AppModel

@Observable
@MainActor
final class AppModel {

    // MARK: - State

    var schedules: [Schedule] = []
    var executionLog: [LogEntry] = []
    var isAccessibilityTrusted: Bool = false
    /// Set this to the schedule's ID before calling openWindow(id: "schedule-form").
    /// nil = new schedule, non-nil = edit existing.
    var scheduleBeingEdited: UUID? = nil
    var webhookConfig: WebhookConfig = WebhookConfig() {
        didSet {
            saveWebhookConfig()
            notifier = Notifier(webhook: webhookConfig.sender)
        }
    }
    /// When true, acquires an IOPMAssertion to prevent idle display sleep (and thus screen lock)
    /// while there are active future schedules. Persisted in UserDefaults.
    var preventScreenLock: Bool = false {
        didSet {
            UserDefaults.standard.set(preventScreenLock, forKey: "preventScreenLock")
            updateDisplayAssertion()
        }
    }

    /// Whether the app is registered to launch automatically at login via SMAppService.
    /// Setting this calls register() or unregister(); the stored value reflects the
    /// desired intent (optimistic). If the OS call fails the value is reverted.
    var launchAtLogin: Bool = false {
        didSet {
            guard oldValue != launchAtLogin else { return }
            do {
                if launchAtLogin {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
                launchAtLoginStatus = SMAppService.mainApp.status
            } catch {
                launchAtLogin = oldValue  // revert
                launchAtLoginStatus = SMAppService.mainApp.status
            }
        }
    }

    /// Live status from SMAppService — used to show "needs approval" hint in UI.
    private(set) var launchAtLoginStatus: SMAppService.Status = .notRegistered

    var menuBarSymbolName: String {
        schedules.contains { $0.isEnabled && $0.sendAt > Date() }
            ? "clock.badge.checkmark" : "clock"
    }

    // MARK: - Private

    private let scheduleStore: ScheduleStore?
    private let webhookStore: WebhookStore?
    private var notifier: Notifier = Notifier()
    private var timerTask: Task<Void, Never>?
    /// True while the display is locked. CGEvent delivery is blocked by the OS
    /// when locked, so we defer sends until after unlock.
    private var isScreenLocked = false
    /// Set when checkAndFire finds a due schedule during lock; cleared on unlock.
    private var pendingFireAfterUnlock = false
    /// IOPMAssertion ID for preventing idle display sleep. 0 = not held.
    private var displayAssertionID: IOPMAssertionID = 0

    // MARK: - Init

    init() {
        let sStore = try? ScheduleStore()
        let wStore = try? WebhookStore()
        let webhook = (try? wStore?.load()) ?? WebhookConfig()
        self.scheduleStore = sStore
        self.webhookStore = wStore
        self.webhookConfig = webhook
        self.schedules = (try? sStore?.load()) ?? []
        self.isAccessibilityTrusted = AccessibilityPermission.isTrusted
        self.notifier = Notifier(webhook: webhook.sender)
        self.preventScreenLock = UserDefaults.standard.bool(forKey: "preventScreenLock")
        let svcStatus = SMAppService.mainApp.status
        self.launchAtLogin = svcStatus == .enabled
        self.launchAtLoginStatus = svcStatus
        loadLog()

        setupScreenLockObservers()
        updateDisplayAssertion()
        Task { [weak self] in await self?.startTimer() }
    }

    private func setupScreenLockObservers() {
        let center = DistributedNotificationCenter.default()
        center.addObserver(
            forName: NSNotification.Name("com.apple.screenIsLocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.isScreenLocked = true }
        }
        center.addObserver(
            forName: NSNotification.Name("com.apple.screenIsUnlocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.isScreenLocked = false
                if self.pendingFireAfterUnlock {
                    self.pendingFireAfterUnlock = false
                    Task { await self.checkAndFire() }
                }
            }
        }
    }

    private func startTimer() async {
        try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound])
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.checkAndFire()
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    // MARK: - Display sleep assertion

    private func updateDisplayAssertion() {
        guard preventScreenLock else {
            releaseDisplayAssertion()
            return
        }
        let hasFutureSchedules = schedules.contains { $0.isEnabled && $0.sendAt > Date() }
        if hasFutureSchedules {
            acquireDisplayAssertion()
        } else {
            releaseDisplayAssertion()
        }
    }

    private func acquireDisplayAssertion() {
        guard displayAssertionID == 0 else { return }
        IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "XcodeSentinel: scheduled sends pending" as CFString,
            &displayAssertionID
        )
    }

    private func releaseDisplayAssertion() {
        guard displayAssertionID != 0 else { return }
        IOPMAssertionRelease(displayAssertionID)
        displayAssertionID = 0
    }

    // MARK: - Fire

    /// Checks every 30 s; fires any enabled schedule whose sendAt has passed.
    /// If the screen is locked, defers until unlock (CGEvent is blocked by the OS).
    private func checkAndFire() async {
        let now = Date()
        let hasDue = schedules.contains { $0.isEnabled && $0.sendAt <= now }
        guard hasDue else { return }

        if isScreenLocked {
            pendingFireAfterUnlock = true
            for s in schedules where s.isEnabled && s.sendAt <= now {
                appendLog(LogEntry(
                    targetName: s.displayName,
                    message: "Deferred — screen is locked. Will retry on unlock.",
                    outcome: .deferred
                ))
            }
            return
        }

        var changed = false
        for i in schedules.indices {
            guard schedules[i].isEnabled, schedules[i].sendAt <= now else { continue }
            let s = schedules[i]
            await fire(s)
            if let next = s.repeatPolicy.nextSendAt(after: s.sendAt) {
                schedules[i].sendAt = next
            } else {
                schedules[i].isEnabled = false
            }
            changed = true
        }
        if changed {
            saveSchedules()
            updateDisplayAssertion()
        }
    }

    private func fire(_ schedule: Schedule) async {
        fireLog.info("fire: starting for '\(schedule.displayName, privacy: .public)' path='\(schedule.workspacePath, privacy: .public)'")
        let identity = TargetIdentity(
            workspacePath: schedule.workspacePath,
            displayName: schedule.displayName
        )

        let window: AXUIElement? = await AccessibilityActor.run {
            let windows = XcodeWindowEnumerator().currentWindows()
            fireLog.info("fire: found \(windows.count, privacy: .public) Xcode windows")
            for w in windows {
                fireLog.info("fire: window '\(w.axTitle ?? "nil", privacy: .public)' path='\(w.axDocumentPath ?? "nil", privacy: .public)'")
            }
            guard case .matched(let desc, _) = TargetResolver.resolve(identity, among: windows),
                  let element = XcodeWindowEnumerator().liveElement(for: desc) else {
                fireLog.error("fire: could not resolve target window")
                return nil
            }
            fireLog.info("fire: resolved window '\(desc.axTitle ?? "nil", privacy: .public)'")
            return element
        }

        guard let window else {
            let msg = "Failed: Xcode window not found."
            fireLog.error("fire: \(msg, privacy: .public)")
            await notifier.notify(targetName: schedule.displayName, line: "Scheduled send failed: Xcode window not found.")
            appendLog(LogEntry(targetName: schedule.displayName, message: msg, outcome: .failure))
            return
        }

        fireLog.info("fire: calling ResumeController for '\(schedule.displayName, privacy: .public)'")
        let outcome = await ResumeController().resume(
            window: window, prompt: schedule.message, dryRun: false, confirmProgress: false
        )
        fireLog.info("fire: outcome=\(String(describing: outcome), privacy: .public)")
        switch outcome {
        case .sent:
            await notifier.notify(targetName: schedule.displayName, line: "Scheduled message sent.")
            appendLog(LogEntry(
                targetName: schedule.displayName,
                message: "Sent: \"\(schedule.message.prefix(60))\(schedule.message.count > 60 ? "…" : "")\"",
                outcome: .success
            ))
        case .couldNotFindInput:
            let msg = "Failed: Claude input field not found."
            await notifier.notify(targetName: schedule.displayName, line: "Scheduled send failed: Claude input field not found.")
            appendLog(LogEntry(targetName: schedule.displayName, message: msg, outcome: .failure))
        case .couldNotConfirmProgress:
            let msg = "Sent, but Claude didn't start responding within 15 s."
            await notifier.notify(targetName: schedule.displayName, line: msg)
            appendLog(LogEntry(targetName: schedule.displayName, message: msg, outcome: .warning))
        case .dryRun:
            appendLog(LogEntry(
                targetName: schedule.displayName,
                message: "Dry run: would send \"\(schedule.message.prefix(60))\(schedule.message.count > 60 ? "…" : "")\"",
                outcome: .success
            ))
        }
    }

    // MARK: - Log

    private func appendLog(_ entry: LogEntry) {
        executionLog.insert(entry, at: 0)
        if executionLog.count > 50 { executionLog.removeLast() }
        saveLog()
    }

    private func saveLog() {
        guard let data = try? JSONEncoder().encode(executionLog) else { return }
        UserDefaults.standard.set(data, forKey: "executionLog")
    }

    private func loadLog() {
        guard let data = UserDefaults.standard.data(forKey: "executionLog"),
              let entries = try? JSONDecoder().decode([LogEntry].self, from: data) else { return }
        executionLog = entries
    }

    func clearLog() {
        executionLog = []
        saveLog()
    }

    // MARK: - Schedule management

    func addSchedule(_ schedule: Schedule) {
        schedules.append(schedule)
        saveSchedules()
        updateDisplayAssertion()
    }

    func removeSchedules(at offsets: IndexSet) {
        schedules.remove(atOffsets: offsets)
        saveSchedules()
        updateDisplayAssertion()
    }

    func updateSchedule(_ schedule: Schedule) {
        guard let i = schedules.firstIndex(where: { $0.id == schedule.id }) else { return }
        schedules[i] = schedule
        saveSchedules()
        updateDisplayAssertion()
    }

    private func saveSchedules() {
        try? scheduleStore?.save(schedules)
    }

    private func saveWebhookConfig() {
        try? webhookStore?.save(webhookConfig)
    }

    // MARK: - Accessibility

    func recheckPermission() {
        isAccessibilityTrusted = AccessibilityPermission.isTrusted
    }

    func requestPermission() {
        AccessibilityPermission.requestIfNeeded()
        isAccessibilityTrusted = AccessibilityPermission.isTrusted
    }

    func xcodeWindows() async -> [WindowDescriptor] {
        await AccessibilityActor.run {
            XcodeWindowEnumerator().currentWindows()
        }
    }
}
