# JARVIS

A free, private personal assistant for the Mac that helps plan your days, train and eat well. It runs entirely on your laptop, and you can type to it or (from Stage 2) talk to it. It speaks like a butler.

Built in stages. Each stage is a working app.

| Stage | What it adds | Status |
| --- | --- | --- |
| 0 — Foundation | Menu bar icon, main window, Option+Space command bar, reminders, daily briefing, starts at login | **Done** |
| 1 — Calendar + brain | Google Calendar, plain-English events with previews, free-time finder, local AI model | Next |
| 2 — Talk | Hold-to-talk, spoken replies and briefing, Siri shortcuts | Planned |
| 3 — Fitness | Lifting, running and basketball goals, scheduling, logging, progress | Planned |
| 4 — Nutrition | Meal logging, maintenance calories, protein target, weight trend | Planned |

Requirements: a Mac with Apple silicon (M1 or later) running macOS 13 Ventura or later.

## Install (no Terminal)

1. Open the [Releases page](https://github.com/Tannerg345/jarvis/releases) and download `JARVIS.zip` from the newest release.
2. Double-click the zip, then drag **JARVIS** into your **Applications** folder.
3. **First open only:** right-click JARVIS → **Open** → **Open**. macOS warns because the app isn't signed with a paid Apple developer account. If it doesn't offer Open, go to System Settings → Privacy & Security and click **Open Anyway**.
4. Allow notifications when asked.
5. If macOS asks, approve JARVIS in System Settings → General → **Login Items**, so it starts when you log in.

To update, quit JARVIS (menu bar icon → Quit), replace the app in Applications with the new one, and open it again. Your data is kept.

## Using Stage 0

- **Command bar:** press **Option + Space** anywhere and type. Press Esc or click elsewhere to close it.
- **Menu bar:** the ✨ icon shows your next reminder and opens JARVIS, the command bar and Settings.
- **Daily briefing:** the first time you open JARVIS each day, it opens on your briefing.

Things to try:

- `help`
- `remind me to stretch in 1 minute`
- `remind me at 5pm to go to the gym`
- `remind me to call mom tomorrow at 9am`
- `open fitness`, `show calendar`, `settings`
- `briefing`

Your data lives in `~/Library/Application Support/JARVIS/jarvis.sqlite`. Nothing leaves your Mac.

## Build it yourself (optional, uses Terminal)

Needs Apple's free Command Line Tools (or Xcode). On macOS 13, update to the latest 13.x first.

```bash
xcode-select --install
```

```bash
git clone https://github.com/Tannerg345/jarvis.git
```

```bash
cd jarvis && ./scripts/build-app.sh && open build/JARVIS.app
```

## For developers

- `Sources/JARVISCore` — storage (SQLite), the command parser and the butler's phrasing. No UI code; covered by `swift test`.
- `Sources/JARVIS` — the SwiftUI/AppKit app: windows, menu bar, command bar, notifications, login item.
- `scripts/build-app.sh` — builds, ad-hoc signs and zips `JARVIS.app`.
- `.github/workflows/build.yml` — runs the tests and builds the app on every push; a `v*` tag publishes a release.

JARVIS is a personal project and is not affiliated with Marvel.
