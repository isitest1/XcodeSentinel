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
        }
        .frame(width: 520, height: 400)
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
