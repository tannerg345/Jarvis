import SwiftUI
import JARVISCore

@main
struct JARVISApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        // The main window: Today, Calendar, Fitness, Nutrition.
        Window("JARVIS", id: AppModel.mainWindowID) {
            MainView()
                .environmentObject(model)
        }
        .defaultSize(width: 920, height: 640)

        // Always-there menu bar icon with a quick Today panel.
        MenuBarExtra {
            MenuBarView()
                .environmentObject(model)
        } label: {
            MenuBarLabel()
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(model)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var activationObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NotificationManager.shared.configure()
        Task { _ = await NotificationManager.shared.requestAuthorization() }

        HotKeyManager.shared.onPress = {
            CommandBarController.shared.toggle()
        }
        HotKeyManager.shared.register()

        configureLoginItemOnFirstLaunch()

        // The briefing is the first thing shown each day, whenever JARVIS is
        // opened or brought to the front.
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in AppModel.shared.checkDailyBriefing() }
        }
        AppModel.shared.checkDailyBriefing()
    }

    /// JARVIS keeps running in the menu bar when its window is closed.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// "Start at login" is on by default; after the first launch it is left to
    /// the setting in Settings.
    private func configureLoginItemOnFirstLaunch() {
        guard let store = AppModel.shared.store, !store.loginItemConfigured else { return }
        try? LoginItem.setEnabled(true)
        try? store.setLoginItemConfigured(true)
    }
}
