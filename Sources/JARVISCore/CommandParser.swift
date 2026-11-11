import Foundation

/// What the user asked for, worked out from what they typed or said.
public enum Command: Equatable {
    case empty
    case help
    case briefing
    case greeting
    case thanks
    case settings
    case open(AppSection)
    case remind(text: String, at: Date)
    /// "remind me to stretch" with no time, or a time that makes no sense.
    case remindMissingTime
    case unknown(String)
}

/// Turns plain English into a `Command` using fixed rules.
///
/// This is the "rules first" layer from the plan: common commands are handled
/// here instantly and exactly. The local AI model (Stage 1) only sees what
/// these rules cannot handle.
public struct CommandParser {
    public var calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    public func parse(_ raw: String, now: Date) -> Command {
        let text = clean(raw)
        if text.isEmpty { return .empty }

        if matches(#"^(?:help|what can you do|what can i say|commands)$"#, text) {
            return .help
        }
        if matches(#"^(?:briefing|daily briefing|my briefing|morning briefing|brief me|good morning|show (?:me )?(?:my |the )?briefing)$"#, text) {
            return .briefing
        }
        if matches(#"^(?:hi|hello|hey|hey jarvis|hello jarvis|good afternoon|good evening)$"#, text) {
            return .greeting
        }
        if matches(#"^(?:thanks|thank you|cheers)(?: jarvis)?$"#, text) {
            return .thanks
        }
        if matches(#"^(?:open |show )?(?:settings|preferences)$"#, text) {
            return .settings
        }
        if let groups = capture(#"^(?:open|show(?: me)?|go to|switch to)\s+(?:the\s+|my\s+)?(today|calendar|fitness|nutrition)(?:\s+(?:tab|page|view))?$"#, text),
           let name = groups[0]?.lowercased(),
           let section = AppSection(rawValue: name) {
            return .open(section)
        }
        if text.lowercased().hasPrefix("remind me") {
            return parseReminder(text, now: now) ?? .remindMissingTime
        }
        return .unknown(text)
    }

    // MARK: - Reminders

    private static let unitPattern = #"(minutes?|mins?|m|hours?|hrs?|h)"#
    private static let timePattern = #"(\d{1,2})(?::(\d{2}))?\s*(am|pm|a\.m\.|p\.m\.)?"#

    private func parseReminder(_ text: String, now: Date) -> Command? {
        let unit = Self.unitPattern
        let time = Self.timePattern

        // "remind me in 20 minutes to stretch"
        if let g = capture(#"^remind me in (\d+)\s*"# + unit + #"\s+(?:to\s+)?(.+)$"#, text) {
            return relative(amount: g[0], unit: g[1], text: g[2], now: now)
        }
        // "remind me to stretch in 20 minutes"
        if let g = capture(#"^remind me\s+(?:to\s+)?(.+?)\s+in\s+(\d+)\s*"# + unit + "$", text) {
            return relative(amount: g[1], unit: g[2], text: g[0], now: now)
        }
        // "remind me (tomorrow) at 5pm to go to the gym"
        if let g = capture(#"^remind me\s+(tomorrow\s+)?at\s+"# + time + #"\s+(?:to\s+)?(.+)$"#, text) {
            return absolute(hour: g[1], minute: g[2], meridiem: g[3], tomorrow: g[0] != nil, text: g[4], now: now)
        }
        // "remind me to go to the gym (tomorrow) at 5pm"
        if let g = capture(#"^remind me\s+(?:to\s+)?(.+?)\s+at\s+"# + time + "$", text) {
            var task = g[0] ?? ""
            var tomorrow = false
            if let range = task.range(of: #"\s+tomorrow$"#, options: [.regularExpression, .caseInsensitive]) {
                task.removeSubrange(range)
                tomorrow = true
            }
            return absolute(hour: g[1], minute: g[2], meridiem: g[3], tomorrow: tomorrow, text: task, now: now)
        }
        return nil
    }

    private func relative(amount: String?, unit: String?, text: String?, now: Date) -> Command? {
        guard let amount = amount.flatMap({ Int($0) }),
              let unit = unit?.lowercased(),
              let task = tidy(text) else { return nil }
        let minutes = unit.hasPrefix("h") ? amount * 60 : amount
        // Between 1 minute and 7 days.
        guard minutes >= 1, minutes <= 7 * 24 * 60 else { return nil }
        return .remind(text: task, at: now.addingTimeInterval(TimeInterval(minutes * 60)))
    }

    private func absolute(hour: String?, minute: String?, meridiem: String?, tomorrow: Bool, text: String?, now: Date) -> Command? {
        guard let hour = hour.flatMap({ Int($0) }),
              let task = tidy(text) else { return nil }
        let minuteValue = minute.flatMap { Int($0) } ?? 0
        guard let date = resolveTime(hour: hour, minute: minuteValue, meridiem: meridiem, dayOffset: tomorrow ? 1 : 0, now: now) else {
            return nil
        }
        return .remind(text: task, at: date)
    }

    /// The next moment matching the clock time. Without am/pm, "at 7" means
    /// whichever of 7:00 or 19:00 comes next.
    func resolveTime(hour: Int, minute: Int, meridiem: String?, dayOffset: Int, now: Date) -> Date? {
        guard (0...59).contains(minute) else { return nil }

        let hours: [Int]
        if let meridiem = meridiem?.replacingOccurrences(of: ".", with: "").lowercased() {
            guard (1...12).contains(hour) else { return nil }
            let base = hour % 12
            hours = [meridiem == "pm" ? base + 12 : base]
        } else {
            guard (0...23).contains(hour) else { return nil }
            hours = (1...11).contains(hour) ? [hour, hour + 12] : [hour]
        }

        let today = calendar.startOfDay(for: now)
        guard let day = calendar.date(byAdding: .day, value: dayOffset, to: today) else { return nil }
        let options = hours
            .compactMap { calendar.date(bySettingHour: $0, minute: minute, second: 0, of: day) }
            .sorted()
        if let next = options.first(where: { $0 > now }) {
            return next
        }
        // Already passed today: the earliest matching time tomorrow.
        if dayOffset == 0, let first = options.first {
            return calendar.date(byAdding: .day, value: 1, to: first)
        }
        return nil
    }

    // MARK: - Text helpers

    /// Trims whitespace and trailing punctuation, and drops a leading
    /// "Jarvis," or "please" and a trailing "please".
    private func clean(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while let last = text.last, ".!?".contains(last) {
            text.removeLast()
        }
        for pattern in [#"^(?:hey\s+)?jarvis[,:]?\s+(?=\S)"#, #"^please\s+"#, #",?\s+please$"#] {
            if let range = text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
                text.removeSubrange(range)
            }
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func tidy(_ text: String?) -> String? {
        guard var task = text?.trimmingCharacters(in: .whitespacesAndNewlines), !task.isEmpty else { return nil }
        while let last = task.last, ".,;:".contains(last) {
            task.removeLast()
        }
        return task.isEmpty ? nil : task
    }

    private func matches(_ pattern: String, _ text: String) -> Bool {
        capture(pattern, text) != nil
    }

    /// Returns the capture groups (nil where a group did not take part), or
    /// nil if the whole pattern does not match.
    private func capture(_ pattern: String, _ text: String) -> [String?]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range) else { return nil }
        guard match.numberOfRanges > 1 else { return [] }
        return (1..<match.numberOfRanges).map { index in
            let groupRange = match.range(at: index)
            guard groupRange.location != NSNotFound, let swiftRange = Range(groupRange, in: text) else {
                return nil
            }
            return String(text[swiftRange])
        }
    }
}
