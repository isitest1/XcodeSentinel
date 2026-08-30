// macOS only. Build on the host with Xcode (see App/README.md).
#if canImport(SwiftUI) && os(macOS)
import SwiftUI
import SentinelCore

/// Settings window. Tabs: Targets, Detection Patterns, Scheduler, Notifications.
/// Skeleton — the individual panes are built on the host.
struct SettingsView: View {
    let model: AppModel

    var body: some View {
        TabView {
            TargetsPane(model: model)
                .tabItem { Label("Targets", systemImage: "list.bullet") }
            Text("Detection Patterns — edit Patterns.json, add/disable rules, run \"Test Detection\".")
                .tabItem { Label("Detection", systemImage: "text.magnifyingglass") }
            Text("Scheduler — max concurrent (1–3), spacing, Quiet Hours.")
                .tabItem { Label("Scheduler", systemImage: "calendar") }
            Text("Notifications — local + webhook presets (ntfy / Pushover / Discord / Slack).")
                .tabItem { Label("Notifications", systemImage: "bell") }
        }
        .frame(width: 560, height: 420)
        .padding()
    }
}

private struct TargetsPane: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading) {
            Text("Add a target, pick a running Xcode window, then \"Test Detection\".")
                .foregroundStyle(.secondary)
            List(model.targets) { target in
                Text(target.displayName)
            }
            Button("Add Target…") {
                // TODO(host): enumerate running Xcode windows, capture display
                // name + resume prompt, run Test Detection before saving.
            }
        }
    }
}
#endif
