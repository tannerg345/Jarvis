import AppKit
import SwiftUI
import JARVISCore

/// One command and JARVIS's reply, shown under the command field.
struct Exchange: Equatable {
    let input: String
    let reply: String
}

/// The app's shared state, used by every window and the menu bar.
@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()
    static let mainWindowID = "main"

    @Published var selectedSection: AppSection = .today
    @Published var showBriefing = false
    @Published private(set) var briefing: Briefing
    @Published private(set) var lastExchange: Exchange?
    @Published private(set) var recentCommands: [CommandLogEntry] = []
    @Published private(set) var upcomingReminders: [Reminder] = []
    @Published private(set) var storeError: String?
    /// Bumped each time the command bar opens, so the text field can refocus.
    @Published private(set) var commandBarFocusToken = 0

    @Published var addressAs: String {
        didSet {
            try? store?.setAddressAs(addressAs)
            reload()
        }
    }

    @Published var briefingOnFirstOpen: Bool {
        didSet { try? store?.setBriefingOnFirstOpen(briefingOnFirstOpen) }
    }

    /// Captured from SwiftUI so non-view code can reopen the main window.
    var openWindowAction: OpenWindowAction?

    let store: JarvisStore?
    let dataDirectory: URL
    /// Used if the database could not be opened, so the briefing still shows
    /// only once per day while the app is running.
    private var sessionBriefingDay: String?

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = support.appendingPathComponent("JARVIS", isDirectory: true)
        dataDirectory = directory

        var opened: JarvisStore?
        var openError: String?
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            opened = try JarvisStore(path: directory.appendingPathComponent("jarvis.sqlite").path)
        } catch {
            openError = String(describing: error)
        }
        store = opened
        storeError = openError

        let address = opened?.addressAs ?? "sir"
        addressAs = address
        briefingOnFirstOpen = opened?.briefingOnFirstOpen ?? true
        briefing = Butler(address: address).briefing(now: Date(), remindersToday: [])

        reload()
    }

    var butler: Butler {
        Butler(address: addressAs)
    }

    var databasePath: String {
        dataDirectory.appendingPathComponent("jarvis.sqlite").path
    }

    // MARK: - Commands

    /// Handles one typed (later also spoken) command and returns the reply.
    @discardableResult
    func handle(_ input: String) -> String {
        let now = Date()
        let command = CommandParser().parse(input, now: now)
        let reply: String

        switch command {
        case .empty:
            return ""
        case .help:
            reply = butler.help()
        case .briefing:
            presentBriefing()
            reply = butler.presentingBriefing()
        case .greeting:
            reply = butler.greeting(now: now)
        case .thanks:
            reply = butler.thanks()
        case .settings:
            openSettings()
            reply = butler.openingSettings()
        case .open(let section):
            selectedSection = section
            showMainWindow()
            reply = butler.opening(section)
        case .remind(let text, let date):
            reply = addReminder(text: text, at: date, now: now)
        case .remindMissingTime:
            reply = butler.needTime()
        case .unknown:
            reply = butler.unknown()
        }

        try? store?.logCommand(input: input, response: reply, at: now)
        lastExchange = Exchange(input: input, reply: reply)
        reload()
        return reply
    }

    private func addReminder(text: String, at date: Date, now: Date) -> String {
        let reminder = Reminder(text: text, fireAt: date, createdAt: now)
        do {
            guard let store else { throw DatabaseError(message: storeError ?? "No database") }
            try store.addReminder(reminder)
        } catch {
            return butler.saveFailed()
        }
        NotificationManager.shared.schedule(reminder, body: butler.reminderNotificationBody(text))
        return butler.confirmReminder(text, at: date, now: now)
    }

    func cancelReminder(_ reminder: Reminder) {
        try? store?.cancelReminder(id: reminder.id)
        NotificationManager.shared.cancel(reminderID: reminder.id)
        lastExchange = Exchange(input: "Cancel: \(reminder.text)", reply: butler.reminderCancelled(reminder.text))
        reload()
    }

    // MARK: - Briefing

    /// Shows the briefing if it has not been shown yet today.
    func checkDailyBriefing() {
        let now = Date()
        let lastShown = store?.lastBriefingDay ?? sessionBriefingDay
        guard BriefingGate.shouldShow(lastShownDay: lastShown, now: now, calendar: .current, enabled: briefingOnFirstOpen) else {
            return
        }
        let today = DayKey.string(for: now, calendar: .current)
        sessionBriefingDay = today
        try? store?.setLastBriefingDay(today)
        presentBriefing()
    }

    func presentBriefing() {
        reload()
        selectedSection = .today
        showBriefing = true
        showMainWindow()
    }

    func dismissBriefing() {
        showBriefing = false
    }

    // MARK: - Data

    func reload() {
        let now = Date()
        guard let store else {
            briefing = butler.briefing(now: now, remindersToday: [])
            return
        }
        upcomingReminders = (try? store.upcomingReminders(after: now)) ?? []
        recentCommands = (try? store.recentCommands(limit: 8)) ?? []
        let todays = (try? store.reminders(onDayOf: now, calendar: .current)) ?? []
        briefing = butler.briefing(now: now, remindersToday: todays)
    }

    // MARK: - Windows

    func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        let existing = NSApp.windows.first { window in
            !(window is NSPanel) && (window.identifier?.rawValue.hasPrefix(Self.mainWindowID) ?? false)
        }
        if let existing {
            existing.makeKeyAndOrderFront(nil)
        } else {
            openWindowAction?(id: Self.mainWindowID)
        }
    }

    func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    func commandBarDidOpen() {
        commandBarFocusToken += 1
    }
}
