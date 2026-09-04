import SwiftUI
import SentinelCore

struct MenuBarContentView: View {
    let model: AppModel
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !model.isAccessibilityTrusted {
                permissionBanner
                Divider()
            }

            if model.schedules.isEmpty {
                emptyState
            } else {
                scheduleList
            }

            if !model.executionLog.isEmpty {
                Divider()
                recentActivitySection
            }

            Divider()
            menuActions
        }
        .frame(width: 320)
        .task { model.recheckPermission() }
    }

    // MARK: - Permission banner

    private var permissionBanner: some View {
        Button { model.requestPermission() } label: {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Accessibility access required").font(.caption.bold())
                    Text("Tap to open System Settings").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.badge.plus").font(.largeTitle).foregroundStyle(.tertiary)
            Text("No schedules").font(.headline)
            Text("Set a time and a message to send to an Xcode Claude window.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Add schedule…") {
                model.scheduleBeingEdited = nil
                openWindow(id: "schedule-form")
            }.buttonStyle(.borderedProminent)
        }
        .padding(24).frame(maxWidth: .infinity)
    }

    // MARK: - Schedule list

    private var scheduleList: some View {
        VStack(spacing: 0) {
            ForEach(model.schedules) { schedule in
                ScheduleRow(model: model, schedule: schedule)
                if schedule.id != model.schedules.last?.id {
                    Divider().padding(.horizontal, 12)
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Recent activity

    private var recentActivitySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Recent Activity")
                    .font(.caption2.uppercaseSmallCaps())
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
                Spacer()
            }
            ForEach(model.executionLog.prefix(3)) { entry in
                LogEntryRow(entry: entry)
            }
            if model.executionLog.count > 3 {
                Button("View all \(model.executionLog.count) entries…") { openSettings() }
                    .font(.caption2)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
            }
        }
    }

    // MARK: - Menu actions

    private var menuActions: some View {
        VStack(spacing: 0) {
            menuButton("Add schedule…", icon: "plus.circle") {
                model.scheduleBeingEdited = nil
                openWindow(id: "schedule-form")
            }
            menuButton("Settings…", icon: "gear") { openSettings() }
            menuButton("AX Inspector", icon: "square.and.pencil") { openWindow(id: "ax-inspector") }
            Divider().padding(.vertical, 2)
            menuButton("Quit XcodeSentinel", icon: "power") { NSApplication.shared.terminate(nil) }
        }
        .padding(.vertical, 4)
    }

    private func menuButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon).frame(width: 16).foregroundStyle(.secondary)
                Text(title)
                Spacer()
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Schedule row

private struct ScheduleRow: View {
    let model: AppModel
    let schedule: Schedule
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(schedule.isEnabled ? Color.blue : Color.gray.opacity(0.4))
                .frame(width: 9, height: 9)
                .padding(.leading, 12)

            VStack(alignment: .leading, spacing: 2) {
                Text(schedule.displayName).font(.callout.bold()).lineLimit(1)
                Text(schedule.sendAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption).foregroundStyle(.secondary)
                if schedule.repeatPolicy != .once {
                    Text(schedule.repeatPolicy.rawValue)
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                Text(schedule.message)
                    .font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
            }

            Spacer()

            // Enabled toggle
            Toggle("", isOn: Binding(
                get: { schedule.isEnabled },
                set: { on in var s = schedule; s.isEnabled = on; model.updateSchedule(s) }
            ))
            .labelsHidden()
            .padding(.trailing, 4)

            // Edit button — opens the standalone schedule-form window
            Button {
                model.scheduleBeingEdited = schedule.id
                openWindow(id: "schedule-form")
            } label: {
                Image(systemName: "pencil").font(.caption).foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.trailing, 10)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Schedule form (standalone window — add + edit)

/// Opened as a standalone Window scene to avoid MenuBarExtra focus issues.
/// Reads model.scheduleBeingEdited on appear: nil = new, non-nil = edit.
struct ScheduleFormView: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var editingScheduleID: UUID? = nil
    @State private var windows: [WindowDescriptor] = []
    @State private var selectedIndex = 0
    @State private var displayName = ""
    @State private var sendAt = Date().addingTimeInterval(5 * 3600)
    @State private var message = "Please continue from where you stopped."
    @State private var repeatPolicy = RepeatPolicy.once
    @State private var isLoading = true

    private var isEditing: Bool { editingScheduleID != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isEditing ? "Edit Schedule" : "New Schedule").font(.headline)

            if isLoading {
                HStack { ProgressView(); Text("Looking for Xcode windows…") }
            } else if windows.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Label("No Xcode windows found.", systemImage: "xmark.circle")
                        .foregroundStyle(.secondary)
                    Text("Open Xcode with a Claude session, then click Refresh.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Refresh") { Task { await loadWindows() } }.buttonStyle(.bordered)
                }
            } else {
                // Tap-selectable list avoids dropdown focus/dismiss issues.
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Xcode window:").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Refresh") { Task { await loadWindows() } }
                            .font(.caption).buttonStyle(.borderless)
                    }
                    VStack(spacing: 0) {
                        ForEach(windows.indices, id: \.self) { i in
                            WindowPickerRow(
                                label: windows[i].displayLabel,
                                isSelected: selectedIndex == i
                            ) {
                                let old = selectedIndex
                                selectedIndex = i
                                let oldName = windows.indices.contains(old)
                                    ? windows[old].workspaceName : ""
                                if displayName.isEmpty || displayName == oldName {
                                    displayName = windows[i].workspaceName
                                }
                            }
                            if i < windows.count - 1 { Divider() }
                        }
                    }
                    .background(Color(NSColor.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.3)))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Name (shown in notifications):").font(.caption).foregroundStyle(.secondary)
                    TextField("e.g. FishingLog – main", text: $displayName)
                }
            }

            DatePicker("Send at:", selection: $sendAt, in: Date()...,
                       displayedComponents: [.date, .hourAndMinute])

            VStack(alignment: .leading, spacing: 4) {
                Text("Repeat:").font(.caption).foregroundStyle(.secondary)
                Picker("", selection: $repeatPolicy) {
                    ForEach(RepeatPolicy.allCases, id: \.self) { p in Text(p.rawValue).tag(p) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Message to send:").font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $message)
                    .frame(minHeight: 72, maxHeight: 72)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .background(Color(NSColor.textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.secondary.opacity(0.3)))
                Text("This text is typed into the Claude input field and sent.")
                    .font(.caption2).foregroundStyle(.tertiary)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button(isEditing ? "Save" : "Add") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled((windows.isEmpty && !isEditing) || displayName.isEmpty || message.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 460)
        .onAppear {
            editingScheduleID = model.scheduleBeingEdited
            prefill()
            Task { await loadWindows() }
            // Ensure the app becomes active so text fields and controls are focusable.
            NSApp.activate(ignoringOtherApps: true)
        }
        // If window is reused (brought to front), reset form for new context.
        .onChange(of: model.scheduleBeingEdited) { _, newID in
            editingScheduleID = newID
            resetFields()
            prefill()
            Task { await loadWindows() }
        }
    }

    private func resetFields() {
        selectedIndex = 0
        displayName = ""
        sendAt = Date().addingTimeInterval(5 * 3600)
        message = "Please continue from where you stopped."
        repeatPolicy = .once
        isLoading = true
    }

    private func prefill() {
        guard let id = editingScheduleID,
              let s = model.schedules.first(where: { $0.id == id }) else { return }
        displayName = s.displayName
        sendAt = s.sendAt
        message = s.message
        repeatPolicy = s.repeatPolicy
    }

    private func loadWindows() async {
        isLoading = true
        windows = await model.xcodeWindows()
        isLoading = false
        if !windows.isEmpty && displayName.isEmpty {
            displayName = windows[0].workspaceName
        }
        if let id = editingScheduleID,
           let s = model.schedules.first(where: { $0.id == id }),
           let i = windows.firstIndex(where: {
               $0.axDocumentPath == s.workspacePath || $0.axTitle == s.workspacePath
           }) {
            selectedIndex = i
        }
    }

    private func save() {
        let workspacePath: String
        if !windows.isEmpty {
            let win = windows[selectedIndex]
            workspacePath = win.axDocumentPath ?? win.axTitle ?? displayName
        } else if let id = editingScheduleID,
                  let s = model.schedules.first(where: { $0.id == id }) {
            workspacePath = s.workspacePath
        } else {
            return
        }

        if let id = editingScheduleID,
           let existing = model.schedules.first(where: { $0.id == id }) {
            var updated = existing
            updated.displayName = displayName
            updated.workspacePath = workspacePath
            updated.sendAt = sendAt
            updated.message = message
            updated.repeatPolicy = repeatPolicy
            model.updateSchedule(updated)
        } else {
            model.addSchedule(Schedule(
                displayName: displayName,
                workspacePath: workspacePath,
                sendAt: sendAt,
                message: message,
                repeatPolicy: repeatPolicy
            ))
        }
        dismiss()
    }
}

// MARK: - Log entry row

private struct LogEntryRow: View {
    let entry: LogEntry

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: entry.outcome.iconName)
                .foregroundStyle(entry.outcome.color)
                .font(.caption2)
                .frame(width: 12)

            VStack(alignment: .leading, spacing: 1) {
                Text(entry.targetName)
                    .font(.caption2.bold())
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(entry.message)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Text(entry.date, style: .time)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 3)
    }
}

private extension LogEntry.Outcome {
    var iconName: String {
        switch self {
        case .success:  "checkmark.circle.fill"
        case .failure:  "xmark.circle.fill"
        case .deferred: "clock.arrow.2.circlepath"
        case .warning:  "exclamationmark.triangle.fill"
        }
    }

    var color: Color {
        switch self {
        case .success:  .green
        case .failure:  .red
        case .deferred: .orange
        case .warning:  .yellow
        }
    }
}

// MARK: - Window picker row (extracted to help the Swift type-checker)

private struct WindowPickerRow: View {
    let label: String
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        HStack {
            Text(label)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)
            if isSelected {
                Image(systemName: "checkmark")
                    .foregroundStyle(Color.accentColor)
                    .font(.caption.bold())
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(isSelected ? Color.blue.opacity(0.12) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }
}
