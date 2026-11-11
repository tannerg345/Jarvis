import XCTest
@testable import JARVISCore

final class ButlerTests: XCTestCase {
    private var calendar: Calendar!
    private var butler: Butler!

    override func setUp() {
        super.setUp()
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        calendar = cal
        butler = Butler(address: "sir", calendar: cal, locale: Locale(identifier: "en_US"))
    }

    private func date(_ d: Int, _ h: Int, _ mi: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: d, hour: h, minute: mi))!
    }

    func testGreetingByTimeOfDay() {
        XCTAssertEqual(butler.greeting(now: date(11, 8, 0)), "Good morning, sir.")
        XCTAssertEqual(butler.greeting(now: date(11, 13, 0)), "Good afternoon, sir.")
        XCTAssertEqual(butler.greeting(now: date(11, 20, 0)), "Good evening, sir.")
    }

    func testNoAddress() {
        let plain = Butler(address: "  ", calendar: calendar, locale: Locale(identifier: "en_US"))
        XCTAssertEqual(plain.greeting(now: date(11, 8, 0)), "Good morning.")
        XCTAssertEqual(plain.thanks(), "Always a pleasure.")
    }

    func testConfirmReminderToday() {
        let reply = butler.confirmReminder("stretch", at: date(11, 17, 0), now: date(11, 14, 30))
        XCTAssertTrue(reply.hasPrefix("Very good, sir. I'll remind you to stretch at "), reply)
        XCTAssertTrue(reply.contains("5:00"), reply)
    }

    func testConfirmReminderTomorrow() {
        let reply = butler.confirmReminder("stretch", at: date(12, 9, 0), now: date(11, 14, 30))
        XCTAssertTrue(reply.contains("tomorrow at"), reply)
    }

    func testConfirmReminderLaterDate() {
        let reply = butler.confirmReminder("stretch", at: date(14, 9, 0), now: date(11, 14, 30))
        XCTAssertTrue(reply.contains("I'll remind you to stretch on "), reply)
    }

    func testAboutPhrasing() {
        XCTAssertTrue(butler.confirmReminder("about the meeting", at: date(11, 16, 0), now: date(11, 14, 0))
            .contains("remind you about the meeting"))
        XCTAssertEqual(butler.reminderNotificationBody("about the meeting"),
                       "Pardon the interruption, sir — a reminder about the meeting.")
        XCTAssertEqual(butler.reminderNotificationBody("stretch"),
                       "Pardon the interruption, sir — it's time to stretch.")
    }

    func testBriefingWithoutReminders() {
        let briefing = butler.briefing(now: date(11, 8, 0), remindersToday: [])
        XCTAssertEqual(briefing.greeting, "Good morning, sir.")
        XCTAssertTrue(briefing.dateLine.contains("November"), briefing.dateLine)
        XCTAssertTrue(briefing.lines[0].contains("No reminders"))
    }

    func testBriefingCountsOnlyUpcomingReminders() {
        let now = date(11, 12, 0)
        let reminders = [
            Reminder(text: "past", fireAt: date(11, 9, 0)),
            Reminder(text: "stretch", fireAt: date(11, 15, 0)),
            Reminder(text: "cook", fireAt: date(11, 18, 0)),
        ]
        let briefing = butler.briefing(now: now, remindersToday: reminders)
        XCTAssertTrue(briefing.lines[0].hasPrefix("2 reminders still to come, the first being stretch"), briefing.lines[0])
    }

    func testBriefingGate() {
        let now = date(11, 8, 0)
        XCTAssertTrue(BriefingGate.shouldShow(lastShownDay: nil, now: now, calendar: calendar, enabled: true))
        XCTAssertTrue(BriefingGate.shouldShow(lastShownDay: "2026-11-10", now: now, calendar: calendar, enabled: true))
        XCTAssertFalse(BriefingGate.shouldShow(lastShownDay: "2026-11-11", now: now, calendar: calendar, enabled: true))
        XCTAssertFalse(BriefingGate.shouldShow(lastShownDay: nil, now: now, calendar: calendar, enabled: false))
    }

    func testDayKey() {
        XCTAssertEqual(DayKey.string(for: date(5, 23, 59), calendar: calendar), "2026-11-05")
    }
}
