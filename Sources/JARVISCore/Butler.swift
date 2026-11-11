import Foundation

/// JARVIS's voice: every reply and the daily briefing are worded here, in a
/// polite, formal and brief butler style.
public struct Butler {
    /// How JARVIS addresses you ("sir" by default). Empty means no address.
    public var address: String
    public var calendar: Calendar
    public var locale: Locale

    public init(address: String = "sir", calendar: Calendar = .current, locale: Locale = .current) {
        self.address = address.trimmingCharacters(in: .whitespacesAndNewlines)
        self.calendar = calendar
        self.locale = locale
    }

    /// ", sir" — or nothing if no address is set.
    private var comma: String {
        address.isEmpty ? "" : ", \(address)"
    }

    // MARK: - Replies

    public func greeting(now: Date) -> String {
        "\(partOfDay(now))\(comma)."
    }

    public func help() -> String {
        """
        At your service\(comma). For now I can:
        • Set reminders — "remind me to stretch in 20 minutes" or "remind me at 5pm to go to the gym"
        • Open a section — "open fitness", "show calendar"
        • Show your briefing — "briefing"
        • Open settings — "settings"
        Calendar, training and nutrition arrive in the coming stages.
        """
    }

    public func unknown() -> String {
        "I'm afraid that's beyond me for the moment\(comma). Say \"help\" to see what I can do."
    }

    public func needTime() -> String {
        "Certainly\(comma) — when shall I remind you? For example: \"remind me to stretch in 20 minutes\" or \"remind me at 5pm to stretch\"."
    }

    public func thanks() -> String {
        "Always a pleasure\(comma)."
    }

    public func opening(_ section: AppSection) -> String {
        "Right away\(comma). Opening \(section.title)."
    }

    public func openingSettings() -> String {
        "Right away\(comma). Opening settings."
    }

    public func presentingBriefing() -> String {
        "Your briefing\(comma)."
    }

    public func confirmReminder(_ text: String, at date: Date, now: Date) -> String {
        "Very good\(comma). I'll \(remindPhrase(text)) \(when(date, now: now))."
    }

    public func reminderCancelled(_ text: String) -> String {
        "As you wish\(comma). I won't \(remindPhrase(text))."
    }

    public func reminderNotificationBody(_ text: String) -> String {
        if text.lowercased().hasPrefix("about ") {
            return "Pardon the interruption\(comma) — a reminder \(text)."
        }
        return "Pardon the interruption\(comma) — it's time to \(text)."
    }

    public func saveFailed() -> String {
        "My apologies\(comma) — I couldn't save that. Please try again."
    }

    // MARK: - Briefing

    public func briefing(now: Date, remindersToday: [Reminder]) -> Briefing {
        var lines: [String] = []

        let pending = remindersToday.filter { $0.fireAt > now }
        switch pending.count {
        case 0:
            lines.append("No reminders on the books for the rest of today.")
        case 1:
            lines.append("One reminder still to come: \(pending[0].text) at \(timeString(pending[0].fireAt)).")
        default:
            let first = pending[0]
            lines.append("\(pending.count) reminders still to come, the first being \(first.text) at \(timeString(first.fireAt)).")
        }

        lines.append("Your calendar, training and nutrition will join this briefing as I'm built out\(comma).")

        return Briefing(
            greeting: greeting(now: now),
            dateLine: format(now, template: "EEEEMMMMd"),
            lines: lines
        )
    }

    // MARK: - Dates and times

    public func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = calendar.timeZone
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    /// "at 5:00 PM", "tomorrow at 9:00 AM" or "on Thu, Nov 13 at 9:00 AM".
    public func when(_ date: Date, now: Date) -> String {
        let time = timeString(date)
        if calendar.isDate(date, inSameDayAs: now) {
            return "at \(time)"
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
           calendar.isDate(date, inSameDayAs: tomorrow) {
            return "tomorrow at \(time)"
        }
        return "on \(format(date, template: "EEEMMMd")) at \(time)"
    }

    private func partOfDay(_ date: Date) -> String {
        let hour = calendar.component(.hour, from: date)
        if hour < 12 { return "Good morning" }
        if hour < 17 { return "Good afternoon" }
        return "Good evening"
    }

    private func remindPhrase(_ text: String) -> String {
        text.lowercased().hasPrefix("about ") ? "remind you \(text)" : "remind you to \(text)"
    }

    private func format(_ date: Date, template: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }
}

/// Decides whether today's briefing still needs to be shown.
public enum BriefingGate {
    public static func shouldShow(lastShownDay: String?, now: Date, calendar: Calendar, enabled: Bool) -> Bool {
        enabled && lastShownDay != DayKey.string(for: now, calendar: calendar)
    }
}

/// A calendar day written as yyyy-MM-dd, in the given calendar's time zone.
public enum DayKey {
    public static func string(for date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
