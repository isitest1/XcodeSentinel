// macOS only. Build on the host with Xcode (see App/README.md).
#if canImport(SwiftUI) && os(macOS)
import SwiftUI
import SentinelCore

/// The dropdown shown from the menu-bar item: one row per monitored target with
/// its state and next action.
struct MenuBarContentView: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.targets.isEmpty {
                Text("No targets yet. Add one in Settings.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.targets) { target in
                    TargetRow(
                        target: target,
                        state: model.statesByTarget[target.id] ?? .unknown
                    )
                }
            }
            Divider()
            SettingsLink { Text("Settings…") }
            Button("Quit XcodeSentinel") { NSApplication.shared.terminate(nil) }
        }
        .padding(12)
        .frame(width: 320)
    }
}

private struct TargetRow: View {
    let target: MonitorTarget
    let state: SessionState

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(target.displayName).font(.headline)
                Text(state.kind).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}
#endif
