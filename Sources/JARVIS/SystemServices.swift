import AppKit
import Carbon
import ServiceManagement
import SwiftUI
import UserNotifications
import JARVISCore

// MARK: - Notifications

/// Schedules reminder notifications. macOS keeps scheduled notifications even
/// if JARVIS quits, so reminders still arrive.
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    private var center: UNUserNotificationCenter { .current() }

    func configure() {
        center.delegate = self
    }

    @discardableResult
    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    func statusDescription() async -> String {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized: return "Allowed"
        case .provisional: return "Allowed quietly"
        case .denied: return "Turned off in System Settings"
        case .notDetermined: return "Not asked yet"
        case .ephemeral: return "Allowed for now"
        @unknown default: return "Unknown"
        }
    }

    func schedule(_ reminder: Reminder, body: String) {
        let content = UNMutableNotificationContent()
        content.title = "JARVIS"
        content.body = body
        content.sound = .default

        let seconds = max(1, reminder.fireAt.timeIntervalSinceNow)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        let request = UNNotificationRequest(identifier: reminder.id, content: content, trigger: trigger)
        center.add(request) { error in
            if let error {
                NSLog("JARVIS: could not schedule reminder: \(error.localizedDescription)")
            }
        }
    }

    func cancel(reminderID: String) {
        center.removePendingNotificationRequests(withIdentifiers: [reminderID])
    }

    /// Show reminders as banners even while JARVIS is the front app.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    static func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Start at login

enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static var needsApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

// MARK: - Global shortcut (Option + Space)

/// Listens for Option + Space anywhere on the Mac. Uses Carbon's hot key API,
/// which needs no Accessibility permission.
final class HotKeyManager {
    static let shared = HotKeyManager()

    var onPress: (@MainActor () -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    func register() {
        guard hotKeyRef == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let userData = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, _, userData in
                guard let userData else { return noErr }
                let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                Task { @MainActor in manager.onPress?() }
                return noErr
            },
            1,
            &eventType,
            userData,
            &handlerRef
        )

        // 'JRVS' as a four-character code.
        let hotKeyID = EventHotKeyID(signature: OSType(0x4A52_5653), id: 1)
        let status = RegisterEventHotKey(
            UInt32(kVK_Space),
            UInt32(optionKey),
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )
        if status != noErr {
            NSLog("JARVIS: could not register Option+Space (status \(status))")
        }
    }
}

// MARK: - Command bar window

/// A floating panel that can take keyboard input without bringing the whole
/// app forward, like Spotlight.
final class CommandBarPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class CommandBarController {
    static let shared = CommandBarController()

    private var panel: CommandBarPanel?
    private var resignObserver: NSObjectProtocol?

    var isVisible: Bool { panel?.isVisible ?? false }

    func toggle() {
        isVisible ? hide() : show()
    }

    func show() {
        let panel = self.panel ?? makePanel()
        self.panel = panel

        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            let size = panel.frame.size
            panel.setFrameOrigin(NSPoint(
                x: frame.midX - size.width / 2,
                y: frame.maxY - size.height - frame.height * 0.2
            ))
        }
        panel.makeKeyAndOrderFront(nil)
        AppModel.shared.commandBarDidOpen()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> CommandBarPanel {
        let panel = CommandBarPanel(
            contentRect: NSRect(x: 0, y: 0, width: CommandBarView.width, height: CommandBarView.height),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.contentView = NSHostingView(
            rootView: CommandBarView().environmentObject(AppModel.shared)
        )

        // Clicking anywhere else closes it.
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: panel,
            queue: .main
        ) { _ in
            Task { @MainActor in CommandBarController.shared.hide() }
        }
        return panel
    }
}
