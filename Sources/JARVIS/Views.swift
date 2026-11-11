import AppKit
import SwiftUI
import JARVISCore

// MARK: - Main window

struct MainView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow

    private var selection: Binding<AppSection?> {
        Binding(
            get: { model.selectedSection },
            set: { if let section = $0 { model.selectedSection = section } }
        )
    }

    var body: some View {
        NavigationSplitView {
            List(selection: selection) {
                ForEach(AppSection.allCases) { section in
                    Label(section.title, systemImage: section.systemImage)
                        .tag(section)
                }
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190)
        } detail: {
            switch model.selectedSection {
            case .today:
                TodayView()
            default:
                ComingSoonView(section: model.selectedSection)
            }
        }
        .frame(minWidth: 760, minHeight: 520)
        .onAppear { model.openWindowAction = openWindow }
    }
}

struct TodayView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if model.showBriefing {
                    BriefingCard(briefing: model.briefing) { model.dismissBriefing() }
                } else {
                    HStack(alignment: .firstTextBaseline) {
                        Text(model.briefing.greeting)
                            .font(.largeTitle.weight(.semibold))
                        Spacer()
                        Button("Show briefing") { model.presentBriefing() }
                    }
                }

                CommandInputView()

                if let error = model.storeError {
                    Label("Your data couldn't be opened: \(error)", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }

                GroupBox("Upcoming reminders") {
                    VStack(alignment: .leading, spacing: 8) {
                        if model.upcomingReminders.isEmpty {
                            Text("None scheduled. Try \"remind me to stretch in 20 minutes\".")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(model.upcomingReminders) { reminder in
                            HStack {
                                Image(systemName: "bell")
                                    .foregroundStyle(.secondary)
                                Text(reminder.text)
                                Spacer()
                                Text(model.butler.when(reminder.fireAt, now: Date()))
                                    .foregroundStyle(.secondary)
                                Button {
                                    model.cancelReminder(reminder)
                                } label: {
                                    Image(systemName: "xmark.circle")
                                }
                                .buttonStyle(.borderless)
                                .help("Cancel this reminder")
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                }

                GroupBox("Recent commands") {
                    VStack(alignment: .leading, spacing: 10) {
                        if model.recentCommands.isEmpty {
                            Text("Nothing yet.")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(model.recentCommands) { entry in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.input)
                                Text(entry.response)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                }
            }
            .padding(28)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }
}

struct BriefingCard: View {
    let briefing: Briefing
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(briefing.greeting)
                .font(.largeTitle.weight(.semibold))
            Text(briefing.dateLine)
                .font(.title3)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(briefing.lines, id: \.self) { line in
                    Text(line)
                }
            }
            .font(.body)
            HStack {
                Spacer()
                Button("Thank you, JARVIS", action: onDismiss)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.accentColor.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.accentColor.opacity(0.25))
        )
    }
}

struct ComingSoonView: View {
    let section: AppSection

    private var details: [String] {
        switch section {
        case .today:
            return []
        case .calendar:
            return [
                "Your Google Calendar, today and this week",
                "Add, move and cancel events in plain English",
                "Find free time for workouts",
            ]
        case .fitness:
            return [
                "Goals for lifting (5+ days a week), running and basketball",
                "Workouts scheduled into your free time",
                "Set-by-set logging and progress charts",
            ]
        case .nutrition:
            return [
                "Plain-English meal logging",
                "Maintenance calories and a protein target",
                "Weight log with a 7-day trend",
            ]
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: section.systemImage)
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text(section.title)
                .font(.largeTitle.weight(.semibold))
            Text("Arrives in \(section.arrivesIn ?? "a later stage").")
                .font(.title3)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(details, id: \.self) { item in
                    Label(item, systemImage: "checkmark.circle")
                }
            }
            .padding(.top, 8)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Command input (main window and command bar)

struct CommandInputView: View {
    @EnvironmentObject private var model: AppModel
    @State private var input = ""
    @FocusState private var focused: Bool
    var focusToken: Int = 0

    private var placeholder: String {
        model.addressAs.isEmpty ? "How may I help?" : "How may I help, \(model.addressAs)?"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .foregroundStyle(Color.accentColor)
                TextField(placeholder, text: $input)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($focused)
                    .onSubmit(submit)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(nsColor: .textBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.secondary.opacity(0.3))
            )

            if let exchange = model.lastExchange {
                Text(exchange.reply)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onChange(of: focusToken) { _ in focused = true }
        .onAppear { if focusToken > 0 { focused = true } }
    }

    private func submit() {
        let text = input
        input = ""
        model.handle(text)
    }
}

struct CommandBarView: View {
    static let width: CGFloat = 640
    static let height: CGFloat = 190

    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CommandInputView(focusToken: model.commandBarFocusToken)
            Spacer(minLength: 0)
            Text("Esc to close · say \"help\" to see what I can do")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .frame(width: Self.width, height: Self.height, alignment: .topLeading)
        .background(.regularMaterial)
        .onExitCommand { CommandBarController.shared.hide() }
    }
}

// MARK: - Menu bar

struct MenuBarLabel: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(systemName: "sparkles")
            .onAppear { AppModel.shared.openWindowAction = openWindow }
    }
}

struct MenuBarView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(model.butler.greeting(now: Date()))
                .font(.headline)

            if let next = model.upcomingReminders.first {
                Label("\(next.text) — \(model.butler.when(next.fireAt, now: Date()))", systemImage: "bell")
            } else {
                Text("No reminders scheduled.")
                    .foregroundStyle(.secondary)
            }

            Divider()

            Button {
                model.showMainWindow()
            } label: {
                Label("Open JARVIS", systemImage: "macwindow")
            }
            Button {
                CommandBarController.shared.show()
            } label: {
                Label("Command bar   ⌥Space", systemImage: "command")
            }
            Button {
                model.openSettings()
            } label: {
                Label("Settings…", systemImage: "gearshape")
            }

            Divider()

            Button("Quit JARVIS") {
                NSApp.terminate(nil)
            }
        }
        .buttonStyle(.plain)
        .padding(14)
        .frame(width: 290, alignment: .leading)
    }
}

// MARK: - Settings

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var loginEnabled = LoginItem.isEnabled
    @State private var loginNeedsApproval = LoginItem.needsApproval
    @State private var loginError: String?
    @State private var notificationStatus = "Checking…"

    var body: some View {
        Form {
            Section("How JARVIS addresses you") {
                TextField("Address", text: $model.addressAs)
                Text("Used in every reply, e.g. \"Very good, sir.\" Leave empty for none.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Daily briefing") {
                Toggle("Show the briefing the first time I open JARVIS each day", isOn: $model.briefingOnFirstOpen)
                Button("Show today's briefing now") { model.presentBriefing() }
            }

            Section("Startup") {
                Toggle("Start JARVIS when I log in", isOn: Binding(
                    get: { loginEnabled },
                    set: { setLogin($0) }
                ))
                if loginNeedsApproval {
                    HStack {
                        Text("macOS needs your approval in Login Items.")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Open Login Items") { LoginItem.openSystemSettings() }
                    }
                }
                if let loginError {
                    Text(loginError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section("Notifications") {
                LabeledContent("Status", value: notificationStatus)
                HStack {
                    Button("Ask for permission") {
                        Task {
                            await NotificationManager.shared.requestAuthorization()
                            notificationStatus = await NotificationManager.shared.statusDescription()
                        }
                    }
                    Button("Open Notification Settings") { NotificationManager.openSystemSettings() }
                }
            }

            Section("Command bar") {
                LabeledContent("Shortcut", value: "Option + Space")
            }

            Section("Your data") {
                LabeledContent("Stored at") {
                    Text(model.databasePath)
                        .textSelection(.enabled)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([model.dataDirectory])
                }
                if let error = model.storeError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 540, height: 620)
        .task {
            notificationStatus = await NotificationManager.shared.statusDescription()
        }
    }

    private func setLogin(_ enabled: Bool) {
        do {
            try LoginItem.setEnabled(enabled)
            loginError = nil
        } catch {
            loginError = "Couldn't change this: \(error.localizedDescription)"
        }
        loginEnabled = LoginItem.isEnabled
        loginNeedsApproval = LoginItem.needsApproval
    }
}
