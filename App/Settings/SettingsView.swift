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
    @State private var lastTest: DetectionEngine.Result?

    var body: some View {
        VStack(alignment: .leading) {
            Text("Add a target, pick a running Xcode window, then \"Test Detection\".")
                .foregroundStyle(.secondary)
            List(model.targets) { target in
                Text(target.displayName)
            }
            HStack {
                Button("Add Target…") {
                    // TODO(host): XcodeWindowEnumerator().currentWindows(),
                    // capture display name + resume prompt, then run Test
                    // Detection before saving.
                }
                Button("Test Detection") {
                    // TODO(host): AXTreeReader -> snapshot for the selected
                    // window, then:
                    //   lastTest = DetectionEngine(patterns: model.patternSet,
                    //                               clock: SystemClock())
                    //       .classify(snapshot)
                }
            }
            if let lastTest {
                TestDetectionResult(result: lastTest)
            }
        }
    }
}

/// Shows what "Test Detection" found: the resolved state, whether the panel was
/// located, and any rules that nearly matched (CLAUDE.md section 5.3 — this
/// screen is mandatory).
private struct TestDetectionResult: View {
    let result: DetectionEngine.Result

    var body: some View {
        GroupBox("Result") {
            VStack(alignment: .leading, spacing: 4) {
                Text("State: \(result.state.kind)")
                Text("Panel located: \(result.panelLocated ? "yes" : "no (scanned whole window)")")
                Text("Text fragments scanned: \(result.scannedTextCount)")
                if let id = result.matchedPatternID {
                    Text("Matched rule: \(id)")
                }
                if let reset = result.resetParse {
                    Text("Reset time: \(reset.matchedText) → \(reset.date.formatted())")
                }
                if !result.nearMisses.isEmpty {
                    Divider()
                    Text("Nearly matched:").font(.caption).foregroundStyle(.secondary)
                    ForEach(result.nearMisses, id: \.patternID) { miss in
                        Text("• \(miss.patternID): \(String(describing: miss.reason))")
                            .font(.caption)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
#endif
