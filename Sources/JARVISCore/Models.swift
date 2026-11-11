import Foundation

/// The four areas of the main window.
public enum AppSection: String, CaseIterable, Identifiable {
    case today
    case calendar
    case fitness
    case nutrition

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .today: return "Today"
        case .calendar: return "Calendar"
        case .fitness: return "Fitness"
        case .nutrition: return "Nutrition"
        }
    }

    /// SF Symbol name for the sidebar (all available on macOS 13).
    public var systemImage: String {
        switch self {
        case .today: return "sun.max"
        case .calendar: return "calendar"
        case .fitness: return "figure.strengthtraining.traditional"
        case .nutrition: return "fork.knife"
        }
    }

    /// The build stage that brings this section to life, if it is not here yet.
    public var arrivesIn: String? {
        switch self {
        case .today: return nil
        case .calendar: return "Stage 1"
        case .fitness: return "Stage 3"
        case .nutrition: return "Stage 4"
        }
    }
}

/// A one-off reminder delivered as a Mac notification.
public struct Reminder: Identifiable, Equatable {
    public let id: String
    public let text: String
    public let fireAt: Date
    public let createdAt: Date

    public init(id: String = UUID().uuidString, text: String, fireAt: Date, createdAt: Date = Date()) {
        self.id = id
        self.text = text
        self.fireAt = fireAt
        self.createdAt = createdAt
    }
}

/// One line of the command history: what was asked and how JARVIS replied.
public struct CommandLogEntry: Identifiable, Equatable {
    public let id: Int64
    public let createdAt: Date
    public let input: String
    public let response: String

    public init(id: Int64, createdAt: Date, input: String, response: String) {
        self.id = id
        self.createdAt = createdAt
        self.input = input
        self.response = response
    }
}

/// The daily briefing shown the first time JARVIS is opened each day.
public struct Briefing: Equatable {
    public let greeting: String
    public let dateLine: String
    public let lines: [String]

    public init(greeting: String, dateLine: String, lines: [String]) {
        self.greeting = greeting
        self.dateLine = dateLine
        self.lines = lines
    }
}
