import XCTest
@testable import JARVISCore

final class CommandParserTests: XCTestCase {
    private var calendar: Calendar!
    private var parser: CommandParser!
    /// Wednesday 11 November 2026, 14:30 UTC.
    private var now: Date!

    override func setUp() {
        super.setUp()
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        calendar = cal
        parser = CommandParser(calendar: cal)
        now = date(2026, 11, 11, 14, 30)
    }

    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
    }

    // MARK: - Simple commands

    func testEmptyInput() {
        XCTAssertEqual(parser.parse("   ", now: now), .empty)
        XCTAssertEqual(parser.parse("?!", now: now), .empty)
    }

    func testHelp() {
        XCTAssertEqual(parser.parse("help", now: now), .help)
        XCTAssertEqual(parser.parse("Jarvis, what can you do?", now: now), .help)
        XCTAssertEqual(parser.parse("Help please", now: now), .help)
    }

    func testBriefing() {
        XCTAssertEqual(parser.parse("Good morning", now: now), .briefing)
        XCTAssertEqual(parser.parse("show me my briefing", now: now), .briefing)
        XCTAssertEqual(parser.parse("Briefing.", now: now), .briefing)
    }

    func testGreetingAndThanks() {
        XCTAssertEqual(parser.parse("hello", now: now), .greeting)
        XCTAssertEqual(parser.parse("Hey Jarvis", now: now), .greeting)
        XCTAssertEqual(parser.parse("thank you", now: now), .thanks)
        XCTAssertEqual(parser.parse("Thanks Jarvis!", now: now), .thanks)
    }

    func testSettings() {
        XCTAssertEqual(parser.parse("settings", now: now), .settings)
        XCTAssertEqual(parser.parse("open preferences", now: now), .settings)
    }

    func testOpenSections() {
        XCTAssertEqual(parser.parse("open fitness", now: now), .open(.fitness))
        XCTAssertEqual(parser.parse("Show me the nutrition tab", now: now), .open(.nutrition))
        XCTAssertEqual(parser.parse("go to my calendar", now: now), .open(.calendar))
        XCTAssertEqual(parser.parse("switch to today", now: now), .open(.today))
    }

    func testUnknown() {
        XCTAssertEqual(parser.parse("make me a sandwich", now: now), .unknown("make me a sandwich"))
    }

    // MARK: - Relative reminders

    func testReminderInMinutesAtEnd() {
        XCTAssertEqual(
            parser.parse("remind me to stretch in 20 minutes", now: now),
            .remind(text: "stretch", at: now.addingTimeInterval(20 * 60))
        )
    }

    func testReminderInHoursAtStart() {
        XCTAssertEqual(
            parser.parse("Remind me in 2 hours to call Mom.", now: now),
            .remind(text: "call Mom", at: now.addingTimeInterval(2 * 3600))
        )
    }

    func testReminderShortUnits() {
        XCTAssertEqual(
            parser.parse("remind me in 5 min to drink water", now: now),
            .remind(text: "drink water", at: now.addingTimeInterval(5 * 60))
        )
        XCTAssertEqual(
            parser.parse("remind me to eat in 1 hr", now: now),
            .remind(text: "eat", at: now.addingTimeInterval(3600))
        )
    }

    func testReminderOutOfRange() {
        XCTAssertEqual(parser.parse("remind me in 0 minutes to x", now: now), .remindMissingTime)
        XCTAssertEqual(parser.parse("remind me in 20000 hours to x", now: now), .remindMissingTime)
    }

    // MARK: - Clock-time reminders

    func testReminderAtTimeFirst() {
        XCTAssertEqual(
            parser.parse("remind me at 5pm to go to the gym", now: now),
            .remind(text: "go to the gym", at: date(2026, 11, 11, 17, 0))
        )
    }

    func testReminderAtTimeLast() {
        XCTAssertEqual(
            parser.parse("remind me to look at the stars at 9:15 pm", now: now),
            .remind(text: "look at the stars", at: date(2026, 11, 11, 21, 15))
        )
    }

    func testAmbiguousHourPicksNextOccurrence() {
        // 14:30 now: "at 3" means 15:00 today.
        XCTAssertEqual(
            parser.parse("remind me to drink water at 3", now: now),
            .remind(text: "drink water", at: date(2026, 11, 11, 15, 0))
        )
        // "at 1" (13:00 and 01:00 both passed) means 01:00 tomorrow.
        XCTAssertEqual(
            parser.parse("remind me to sleep at 1", now: now),
            .remind(text: "sleep", at: date(2026, 11, 12, 1, 0))
        )
    }

    func testPastTimeRollsToTomorrow() {
        XCTAssertEqual(
            parser.parse("remind me at 9am to stretch", now: now),
            .remind(text: "stretch", at: date(2026, 11, 12, 9, 0))
        )
    }

    func testTomorrow() {
        XCTAssertEqual(
            parser.parse("remind me to call mom tomorrow at 9am", now: now),
            .remind(text: "call mom", at: date(2026, 11, 12, 9, 0))
        )
        XCTAssertEqual(
            parser.parse("remind me tomorrow at 9:15 to stretch", now: now),
            .remind(text: "stretch", at: date(2026, 11, 12, 9, 15))
        )
    }

    func testTwentyFourHourClock() {
        XCTAssertEqual(
            parser.parse("remind me at 18:45 to cook", now: now),
            .remind(text: "cook", at: date(2026, 11, 11, 18, 45))
        )
    }

    func testNoonAndMidnight() {
        XCTAssertEqual(
            parser.parse("remind me at 12pm to eat", now: now),
            .remind(text: "eat", at: date(2026, 11, 12, 12, 0))
        )
        XCTAssertEqual(
            parser.parse("remind me at 12am to sleep", now: now),
            .remind(text: "sleep", at: date(2026, 11, 12, 0, 0))
        )
    }

    func testInvalidTimes() {
        XCTAssertEqual(parser.parse("remind me at 25 to x", now: now), .remindMissingTime)
        XCTAssertEqual(parser.parse("remind me at 13pm to x", now: now), .remindMissingTime)
        XCTAssertEqual(parser.parse("remind me at 5:75 to x", now: now), .remindMissingTime)
    }

    func testReminderWithoutTime() {
        XCTAssertEqual(parser.parse("remind me to stretch", now: now), .remindMissingTime)
    }

    func testAboutPhrasing() {
        XCTAssertEqual(
            parser.parse("remind me about the meeting at 4pm", now: now),
            .remind(text: "about the meeting", at: date(2026, 11, 11, 16, 0))
        )
    }
}
