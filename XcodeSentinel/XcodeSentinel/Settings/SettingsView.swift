import SwiftUI
import SentinelCore

struct SettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        TabView {
            SchedulesPane(model: model)
                .tabItem { Label("Schedules", systemImage: "clock") }
            NotificationsPane(model: model)
                .tabItem { Label("Notifications", systemImage: "bell") }
            LogPane(model: model)
                .tabItem { Label("Log", systemImage: "list.bullet.rectangle") }
        }
        .frame(width: 520, height: 480)
    }
}

// MARK: - Schedules pane

private struct SchedulesPane: View {
    @Bindable var model: AppModel
    @State private var selectedID: UUID?
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            List(selection: $selectedID) {
                ForEach(model.schedules) { schedule in
                    ScheduleListRow(schedule: schedule, model: model)
                        .tag(schedule.id)
                }
                .onDelete { model.removeSchedules(at: $0) }
            }
            .listStyle(.bordered)
            .frame(minHeight: 180)

            HStack {
                Button("Add…") {
                    model.scheduleBeingEdited = nil
                    openWindow(id: "schedule-form")
                }
                Button("Edit…") {
                    model.scheduleBeingEdited = selectedID
                    openWindow(id: "schedule-form")
                }
                .disabled(selectedID == nil)
                Button("Remove") {
                    if let id = selectedID,
                       let i = model.schedules.firstIndex(where: { $0.id == id }) {
                        model.removeSchedules(at: IndexSet([i]))
                        selectedID = nil
                    }
                }
                .disabled(selectedID == nil)
            }

            Text("The app checks every 30 seconds and sends the message at the scheduled time.")
                .font(.caption).foregroundStyle(.secondary)

            Divider()

            Toggle(isOn: $model.preventScreenLock) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Prevent idle screen lock while schedules are active")
                        .font(.callout)
                    Text("Acquires an IOPMAssertion to keep the display awake until all scheduled sends complete. Required for unattended overnight operation.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding()
    }
}

private struct ScheduleListRow: View {
    let schedule: Schedule
    let model: AppModel

    var body: some View {
        HStack {
            Toggle("", isOn: Binding(
                get: { schedule.isEnabled },
                set: { on in var s = schedule; s.isEnabled = on; model.updateSchedule(s) }
            ))
            .labelsHidden()

            VStack(alignment: .leading, spacing: 2) {
                Text(schedule.displayName).font(.headline)
                HStack(spacing: 6) {
                    Text(schedule.sendAt.formatted(date: .abbreviated, time: .shortened))
                    if schedule.repeatPolicy != .once {
                        Text("· \(schedule.repeatPolicy.rawValue)")
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
                Text(schedule.message).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
            }
        }
    }
}

// MARK: - Notifications pane

private struct NotificationsPane: View {
    @Bindable var model: AppModel
    @State private var testSending = false
    @State private var testResult: String?

    var body: some View {
        Form {
            Section("Local Notifications") {
                Text("macOS notifications are sent when a scheduled message is sent or fails.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Toggle("Enable webhook (away-from-Mac notifications)", isOn: $model.webhookConfig.isEnabled)

                if model.webhookConfig.isEnabled {
                    TextField("URL", text: $model.webhookConfig.endpoint)
                        .textFieldStyle(.roundedBorder)

                    Picker("Preset", selection: $model.webhookConfig.preset) {
                        ForEach(WebhookPreset.allCases, id: \.self) { p in
                            Text(p.rawValue.capitalized).tag(p)
                        }
                    }
                    .pickerStyle(.segmented)

                    if model.webhookConfig.preset == .custom {
                        TextField(
                            "Template ({{title}}, {{message}}, {{timestamp}})",
                            text: $model.webhookConfig.customTemplate,
                            axis: .vertical
                        )
                        .lineLimit(3)
                        .font(.caption.monospaced())
                    }

                    HStack {
                        Button("Send test notification") { Task { await sendTest() } }
                            .disabled(testSending || model.webhookConfig.endpoint.isEmpty)
                        if testSending { ProgressView().controlSize(.small) }
                        if let r = testResult {
                            Text(r).font(.caption)
                                .foregroundStyle(r.hasPrefix("✓") ? .green : .red)
                        }
                    }
                }
            } header: {
                Text("Webhook (ntfy / Pushover / Discord / Slack)")
            } footer: {
                Text("Payloads contain only the schedule name, status, and timestamp — never chat text or source code.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding()
    }

    private func sendTest() async {
        testSending = true
        testResult = nil
        defer { testSending = false }
        guard let sender = model.webhookConfig.sender else {
            testResult = "✗ Invalid URL"
            return
        }
        do {
            try await sender.send(targetName: "XcodeSentinel", line: "Test notification.")
            testResult = "✓ Sent"
        } catch {
            testResult = "✗ \(error.localizedDescription)"
        }
        try? await Task.sleep(for: .seconds(4))
        testResult = nil
    }
}

// MARK: - Log pane

private struct LogPane: View {
    @Bindable var model: AppModel
    @State private var selectedID: LogEntry.ID?

    private var selectedEntry: LogEntry? {
        model.executionLog.first { $0.id == selectedID }
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .medium
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(model.executionLog.count) entries (newest first)")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Clear") {
                    model.clearLog()
                    selectedID = nil
                }
                .font(.caption)
                .disabled(model.executionLog.isEmpty)
            }

            if model.executionLog.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "list.bullet.rectangle")
                        .font(.largeTitle).foregroundStyle(.tertiary)
                    Text("No activity yet.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(model.executionLog, selection: $selectedID) {
                    TableColumn("Time") { entry in
                        Text(Self.timeFormatter.string(from: entry.date))
                            .font(.caption.monospaced())
                    }
                    .width(min: 120, ideal: 130, max: 140)

                    TableColumn("Target") { entry in
                        Text(entry.targetName)
                            .font(.caption)
                            .lineLimit(1)
                    }
                    .width(min: 80, ideal: 100)

                    TableColumn("Result") { entry in
                        HStack(spacing: 4) {
                            Image(systemName: entry.outcome.iconName)
                                .foregroundStyle(entry.outcome.color)
                                .font(.caption2)
                            Text(entry.message)
                                .font(.caption)
                                .lineLimit(1)
                        }
                    }
                }

                // Detail panel — expands full message for the selected row
                LogDetailPanel(entry: selectedEntry, timeFormatter: Self.timeFormatter)
            }
        }
        .padding()
    }
}

private struct LogDetailPanel: View {
    let entry: LogEntry?
    let timeFormatter: DateFormatter

    var body: some View {
        Group {
            if let entry {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: entry.outcome.iconName)
                            .foregroundStyle(entry.outcome.color)
                            .font(.caption)
                        Text(entry.targetName).font(.caption.bold())
                        Text("·").foregroundStyle(.tertiary)
                        Text(timeFormatter.string(from: entry.date))
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                    }
                    Text(entry.message)
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(NSColor.textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )
            } else {
                Text("Click a row to see the full message.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 10)
            }
        }
        .frame(minHeight: 56)
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

// MARK: - WindowDescriptor helpers for UI

extension WindowDescriptor {
    var displayLabel: String {
        if let title = axTitle, !title.isEmpty { return title }
        if let path = axDocumentPath { return URL(fileURLWithPath: path).lastPathComponent }
        return "PID \(pid.map(String.init) ?? "?")"
    }

    var workspaceName: String {
        if let path = axDocumentPath { return WorkspacePath.name(from: path) }
        if let title = axTitle { return title }
        return ""
    }
}
