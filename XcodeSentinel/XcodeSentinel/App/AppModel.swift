import ApplicationServices
import Foundation
import Observation
import SwiftUI
import UserNotifications
import SentinelCore

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

// MARK: - AppModel

@Observable
@MainActor
final class AppModel {

    // MARK: - State

    var schedules: [Schedule] = []
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

    var menuBarSymbolName: String {
        schedules.contains { $0.isEnabled && $0.sendAt > Date() }
            ? "clock.badge.checkmark" : "clock"
    }

    // MARK: - Private

    private let scheduleStore: ScheduleStore?
    private let webhookStore: WebhookStore?
    private var notifier: Notifier = Notifier()
    private var timerTask: Task<Void, Never>?

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

        Task { [weak self] in await self?.startTimer() }
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

    // MARK: - Fire

    /// Checks every 30 s; fires any enabled schedule whose sendAt has passed.
    private func checkAndFire() async {
        let now = Date()
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
        if changed { saveSchedules() }
    }

    private func fire(_ schedule: Schedule) async {
        let identity = TargetIdentity(
            workspacePath: schedule.workspacePath,
            displayName: schedule.displayName
        )

        let window: AXUIElement? = await AccessibilityActor.run {
            let windows = XcodeWindowEnumerator().currentWindows()
            guard case .matched(let desc, _) = TargetResolver.resolve(identity, among: windows),
                  let element = XcodeWindowEnumerator().liveElement(for: desc) else { return nil }
            return element
        }

        guard let window else {
            await notifier.notify(
                targetName: schedule.displayName,
                line: "Scheduled send failed: Xcode window not found."
            )
            return
        }

        let outcome = await ResumeController().resume(
            window: window, prompt: schedule.message, dryRun: false
        )
        switch outcome {
        case .sent:
            await notifier.notify(targetName: schedule.displayName, line: "Scheduled message sent.")
        case .couldNotFindInput:
            await notifier.notify(
                targetName: schedule.displayName,
                line: "Scheduled send failed: Claude input field not found."
            )
        case .couldNotConfirmProgress:
            await notifier.notify(
                targetName: schedule.displayName,
                line: "Message sent but Claude didn't start responding within 15 s."
            )
        case .dryRun:
            break
        }
    }

    // MARK: - Schedule management

    func addSchedule(_ schedule: Schedule) {
        schedules.append(schedule)
        saveSchedules()
    }

    func removeSchedules(at offsets: IndexSet) {
        schedules.remove(atOffsets: offsets)
        saveSchedules()
    }

    func updateSchedule(_ schedule: Schedule) {
        guard let i = schedules.firstIndex(where: { $0.id == schedule.id }) else { return }
        schedules[i] = schedule
        saveSchedules()
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
