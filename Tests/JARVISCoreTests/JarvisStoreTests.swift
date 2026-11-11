import XCTest
@testable import JARVISCore

final class JarvisStoreTests: XCTestCase {
    func testDefaultSettings() throws {
        let store = try JarvisStore.inMemory()
        XCTAssertEqual(store.addressAs, "sir")
        XCTAssertTrue(store.briefingOnFirstOpen)
        XCTAssertNil(store.lastBriefingDay)
        XCTAssertFalse(store.loginItemConfigured)
    }

    func testSettingsRoundTrip() throws {
        let store = try JarvisStore.inMemory()
        try store.setAddressAs("  Tanner ")
        try store.setBriefingOnFirstOpen(false)
        try store.setLastBriefingDay("2026-11-11")
        try store.setLoginItemConfigured(true)
        XCTAssertEqual(store.addressAs, "Tanner")
        XCTAssertFalse(store.briefingOnFirstOpen)
        XCTAssertEqual(store.lastBriefingDay, "2026-11-11")
        XCTAssertTrue(store.loginItemConfigured)

        // Overwriting an existing key updates it.
        try store.setAddressAs("sir")
        XCTAssertEqual(store.addressAs, "sir")
    }

    func testRemindersUpcomingAndCancel() throws {
        let store = try JarvisStore.inMemory()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let past = Reminder(text: "past", fireAt: now.addingTimeInterval(-60))
        let soon = Reminder(text: "soon", fireAt: now.addingTimeInterval(60))
        let later = Reminder(text: "later", fireAt: now.addingTimeInterval(3600))
        for reminder in [later, past, soon] {
            try store.addReminder(reminder)
        }

        XCTAssertEqual(try store.upcomingReminders(after: now).map(\.text), ["soon", "later"])

        try store.cancelReminder(id: soon.id)
        XCTAssertEqual(try store.upcomingReminders(after: now).map(\.text), ["later"])
    }

    func testRemindersOnDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let store = try JarvisStore.inMemory()
        let day = calendar.date(from: DateComponents(year: 2026, month: 11, day: 11, hour: 12))!
        try store.addReminder(Reminder(text: "today", fireAt: day.addingTimeInterval(3600)))
        try store.addReminder(Reminder(text: "tomorrow", fireAt: day.addingTimeInterval(24 * 3600)))
        XCTAssertEqual(try store.reminders(onDayOf: day, calendar: calendar).map(\.text), ["today"])
    }

    func testCommandLogNewestFirstAndTextIsPreserved() throws {
        let store = try JarvisStore.inMemory()
        try store.logCommand(input: "help", response: "At your service")
        try store.logCommand(input: "it's \"quoted\" — ok", response: "Very good, sir.")
        let entries = try store.recentCommands(limit: 5)
        XCTAssertEqual(entries.map(\.input), ["it's \"quoted\" — ok", "help"])
    }

    func testMigrationsRunOnceOnAFile() throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("jarvis-test-\(UUID().uuidString).sqlite").path
        defer { try? FileManager.default.removeItem(atPath: path) }

        do {
            let store = try JarvisStore(path: path)
            try store.setAddressAs("sir")
            XCTAssertEqual(try store.database.userVersion(), JarvisStore.schemaVersion)
        }
        // Reopening must not try to recreate tables, and must keep the data.
        let reopened = try JarvisStore(path: path)
        XCTAssertEqual(reopened.addressAs, "sir")
        XCTAssertEqual(try reopened.database.userVersion(), JarvisStore.schemaVersion)
    }
}
