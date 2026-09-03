import SwiftUI
import SentinelCore
import ServiceManagement

@main
struct XcodeSentinelApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(model: model)
        } label: {
            Label("XcodeSentinel", systemImage: model.menuBarSymbolName)
                .labelStyle(.iconOnly)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(model: model)
        }

        Window("Schedule", id: "schedule-form") {
            ScheduleFormView(model: model)
                .onDisappear { model.scheduleBeingEdited = nil }
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 480, height: 480)

        Window("AX Inspector", id: "ax-inspector") {
            AXInspectorView(model: model)
        }
        .defaultSize(width: 800, height: 600)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, @unchecked Sendable {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AccessibilityPermission.requestIfNeeded()
        Task { @MainActor in
            try? SMAppService.mainApp.register()
        }
    }
}
