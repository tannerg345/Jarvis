import Foundation

/// Everything JARVIS remembers, in one SQLite file on the Mac.
///
/// Stage 0 stores settings, reminders and the command history. Later stages
/// add tables through new entries in `migrations`; existing entries must never
/// be edited once released, only appended to.
public final class JarvisStore {
    public let database: Database

    /// Each entry is one schema version; each version is a list of statements.
    static let migrations: [[String]] = [
        // Version 1 (Stage 0)
        [
            """
            CREATE TABLE settings (
                key TEXT PRIMARY KEY NOT NULL,
                value TEXT NOT NULL
            )
            """,
            """
            CREATE TABLE command_log (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                created_at REAL NOT NULL,
                input TEXT NOT NULL,
                response TEXT NOT NULL
            )
            """,
            """
            CREATE TABLE reminders (
                id TEXT PRIMARY KEY NOT NULL,
                text TEXT NOT NULL,
                fire_at REAL NOT NULL,
                created_at REAL NOT NULL,
                cancelled INTEGER NOT NULL DEFAULT 0
            )
            """,
            "CREATE INDEX reminders_fire_at ON reminders (fire_at)",
        ],
    ]

    public static var schemaVersion: Int { migrations.count }

    public init(database: Database) throws {
        self.database = database
        try migrate()
    }

    public convenience init(path: String) throws {
        try self.init(database: Database(path: path))
    }

    /// A throwaway store for tests and previews.
    public static func inMemory() throws -> JarvisStore {
        try JarvisStore(database: Database(path: ":memory:"))
    }

    private func migrate() throws {
        let current = try database.userVersion()
        guard current < Self.migrations.count else { return }
        for version in current..<Self.migrations.count {
            try database.transaction {
                for statement in Self.migrations[version] {
                    try database.execute(statement)
                }
                try database.setUserVersion(version + 1)
            }
        }
    }

    // MARK: - Settings

    public enum SettingKey: String {
        case addressAs = "address_as"
        case briefingOnFirstOpen = "briefing_on_first_open"
        case lastBriefingDay = "last_briefing_day"
        case loginItemConfigured = "login_item_configured"
    }

    public func setting(_ key: SettingKey) throws -> String? {
        let rows = try database.query("SELECT value FROM settings WHERE key = ?", [.text(key.rawValue)])
        return rows.first?["value"]?.stringValue
    }

    public func setSetting(_ key: SettingKey, _ value: String) throws {
        try database.execute(
            """
            INSERT INTO settings (key, value) VALUES (?, ?)
            ON CONFLICT(key) DO UPDATE SET value = excluded.value
            """,
            [.text(key.rawValue), .text(value)]
        )
    }

    /// How JARVIS addresses you. Defaults to "sir".
    public var addressAs: String {
        (try? setting(.addressAs)) ?? "sir"
    }

    public func setAddressAs(_ value: String) throws {
        try setSetting(.addressAs, value.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Whether the briefing opens the first time JARVIS is used each day.
    public var briefingOnFirstOpen: Bool {
        (try? setting(.briefingOnFirstOpen)) != "false"
    }

    public func setBriefingOnFirstOpen(_ value: Bool) throws {
        try setSetting(.briefingOnFirstOpen, value ? "true" : "false")
    }

    /// The day (yyyy-MM-dd) the briefing was last shown.
    public var lastBriefingDay: String? {
        try? setting(.lastBriefingDay)
    }

    public func setLastBriefingDay(_ day: String) throws {
        try setSetting(.lastBriefingDay, day)
    }

    /// Whether "start at login" has been set up once already.
    public var loginItemConfigured: Bool {
        (try? setting(.loginItemConfigured)) == "true"
    }

    public func setLoginItemConfigured(_ value: Bool) throws {
        try setSetting(.loginItemConfigured, value ? "true" : "false")
    }

    // MARK: - Command history

    public func logCommand(input: String, response: String, at date: Date = Date()) throws {
        try database.execute(
            "INSERT INTO command_log (created_at, input, response) VALUES (?, ?, ?)",
            [.real(date.timeIntervalSince1970), .text(input), .text(response)]
        )
        // Keep the history from growing forever.
        try database.execute(
            """
            DELETE FROM command_log
            WHERE id NOT IN (SELECT id FROM command_log ORDER BY id DESC LIMIT 500)
            """
        )
    }

    /// Most recent first.
    public func recentCommands(limit: Int = 10) throws -> [CommandLogEntry] {
        let rows = try database.query(
            "SELECT id, created_at, input, response FROM command_log ORDER BY id DESC LIMIT ?",
            [.integer(Int64(limit))]
        )
        return rows.compactMap { row in
            guard let id = row["id"]?.intValue,
                  let created = row["created_at"]?.doubleValue,
                  let input = row["input"]?.stringValue,
                  let response = row["response"]?.stringValue else { return nil }
            return CommandLogEntry(
                id: id,
                createdAt: Date(timeIntervalSince1970: created),
                input: input,
                response: response
            )
        }
    }

    // MARK: - Reminders

    public func addReminder(_ reminder: Reminder) throws {
        try database.execute(
            "INSERT INTO reminders (id, text, fire_at, created_at) VALUES (?, ?, ?, ?)",
            [
                .text(reminder.id),
                .text(reminder.text),
                .real(reminder.fireAt.timeIntervalSince1970),
                .real(reminder.createdAt.timeIntervalSince1970),
            ]
        )
    }

    public func cancelReminder(id: String) throws {
        try database.execute("UPDATE reminders SET cancelled = 1 WHERE id = ?", [.text(id)])
    }

    /// Reminders that have not fired yet, soonest first.
    public func upcomingReminders(after date: Date) throws -> [Reminder] {
        try reminders(
            where: "cancelled = 0 AND fire_at > ?",
            [.real(date.timeIntervalSince1970)]
        )
    }

    /// All reminders (fired or not) falling on the same calendar day as `date`.
    public func reminders(onDayOf date: Date, calendar: Calendar) throws -> [Reminder] {
        let start = calendar.startOfDay(for: date)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        return try reminders(
            where: "cancelled = 0 AND fire_at >= ? AND fire_at < ?",
            [.real(start.timeIntervalSince1970), .real(end.timeIntervalSince1970)]
        )
    }

    private func reminders(where condition: String, _ parameters: [SQLValue]) throws -> [Reminder] {
        let rows = try database.query(
            "SELECT id, text, fire_at, created_at FROM reminders WHERE \(condition) ORDER BY fire_at ASC",
            parameters
        )
        return rows.compactMap { row in
            guard let id = row["id"]?.stringValue,
                  let text = row["text"]?.stringValue,
                  let fireAt = row["fire_at"]?.doubleValue,
                  let createdAt = row["created_at"]?.doubleValue else { return nil }
            return Reminder(
                id: id,
                text: text,
                fireAt: Date(timeIntervalSince1970: fireAt),
                createdAt: Date(timeIntervalSince1970: createdAt)
            )
        }
    }
}
