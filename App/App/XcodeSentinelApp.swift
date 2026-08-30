// macOS only. Build on the host with Xcode (see App/README.md).
#if canImport(SwiftUI) && os(macOS)
import SwiftUI
import SentinelCore

/// Menu-bar-resident entry point. The app has no Dock icon (`LSUIElement`).
@main
struct XcodeSentinelApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(model: model)
        } label: {
            Image(systemName: model.menuBarSymbolName)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(model: model)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // TODO(host): register login item via SMAppService.mainApp, kick off
        // AccessibilityActor permission check, then start the monitor loop.
    }
}
#endif
