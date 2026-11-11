import Foundation
import SQLite3

/// A value stored in or read from SQLite.
public enum SQLValue: Equatable {
    case null
    case integer(Int64)
    case real(Double)
    case text(String)

    public var stringValue: String? {
        if case .text(let value) = self { return value }
        return nil
    }

    public var doubleValue: Double? {
        switch self {
        case .real(let value): return value
        case .integer(let value): return Double(value)
        default: return nil
        }
    }

    public var intValue: Int64? {
        switch self {
        case .integer(let value): return value
        case .real(let value): return Int64(value)
        default: return nil
        }
    }
}

public struct DatabaseError: Error, CustomStringConvertible {
    public let message: String
    public var description: String { message }

    public init(message: String) {
        self.message = message
    }
}

public typealias Row = [String: SQLValue]

/// SQLite asks for this marker to copy bound strings before the call returns.
private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// A small, thread-safe wrapper around one SQLite connection.
public final class Database {
    private var handle: OpaquePointer?
    private let lock = NSRecursiveLock()

    /// Opens (or creates) the database at `path`. Use ":memory:" for tests.
    public init(path: String) throws {
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let result = sqlite3_open_v2(path, &handle, flags, nil)
        guard result == SQLITE_OK else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "code \(result)"
            sqlite3_close(handle)
            handle = nil
            throw DatabaseError(message: "Could not open the database: \(message)")
        }
        try execute("PRAGMA journal_mode = WAL")
        try execute("PRAGMA foreign_keys = ON")
    }

    deinit {
        sqlite3_close(handle)
    }

    /// Runs a statement and ignores any rows it returns.
    public func execute(_ sql: String, _ parameters: [SQLValue] = []) throws {
        _ = try query(sql, parameters)
    }

    /// Runs a statement and returns every row as a column-name dictionary.
    @discardableResult
    public func query(_ sql: String, _ parameters: [SQLValue] = []) throws -> [Row] {
        lock.lock()
        defer { lock.unlock() }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw makeError("prepare", sql: sql)
        }
        defer { sqlite3_finalize(statement) }

        for (offset, parameter) in parameters.enumerated() {
            let index = Int32(offset + 1)
            let result: Int32
            switch parameter {
            case .null:
                result = sqlite3_bind_null(statement, index)
            case .integer(let value):
                result = sqlite3_bind_int64(statement, index, value)
            case .real(let value):
                result = sqlite3_bind_double(statement, index, value)
            case .text(let value):
                result = sqlite3_bind_text(statement, index, value, -1, sqliteTransient)
            }
            guard result == SQLITE_OK else { throw makeError("bind", sql: sql) }
        }

        var rows: [Row] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW else { throw makeError("step", sql: sql) }

            var row: Row = [:]
            let columnCount = sqlite3_column_count(statement)
            for column in 0..<columnCount {
                guard let namePointer = sqlite3_column_name(statement, column) else { continue }
                let name = String(cString: namePointer)
                switch sqlite3_column_type(statement, column) {
                case SQLITE_INTEGER:
                    row[name] = .integer(sqlite3_column_int64(statement, column))
                case SQLITE_FLOAT:
                    row[name] = .real(sqlite3_column_double(statement, column))
                case SQLITE_TEXT:
                    if let text = sqlite3_column_text(statement, column) {
                        row[name] = .text(String(cString: text))
                    } else {
                        row[name] = .null
                    }
                default:
                    row[name] = .null
                }
            }
            rows.append(row)
        }
        return rows
    }

    /// Runs `body` inside a transaction, rolling back if it throws.
    public func transaction(_ body: () throws -> Void) throws {
        lock.lock()
        defer { lock.unlock() }
        try execute("BEGIN IMMEDIATE")
        do {
            try body()
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    /// SQLite's built-in schema version number, used for migrations.
    public func userVersion() throws -> Int {
        let rows = try query("PRAGMA user_version")
        return Int(rows.first?["user_version"]?.intValue ?? 0)
    }

    public func setUserVersion(_ version: Int) throws {
        try execute("PRAGMA user_version = \(version)")
    }

    private func makeError(_ stage: String, sql: String) -> DatabaseError {
        let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "no connection"
        return DatabaseError(message: "SQLite \(stage) failed: \(message) [\(sql)]")
    }
}
