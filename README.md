# Remder: Intelligent Reminders

Remder is an iPhone reminders app built entirely in SwiftUI and SwiftData. It aims to make sure a reminder actually reaches you: on time, in your own words, on every screen you look at. It combines notifications, real alarms, a Dynamic Island countdown, widgets, location triggers and Siri, with optional account sync across devices.

## Features

### Never miss a reminder
- **Notifications** with Complete and Snooze actions on the notification itself; snooze lengths are 5, 10, 15, 30 or 60 minutes, and the default is configurable.
- **Alarms** (AlarmKit): a Clock-style full-screen alarm that rings through Silent mode and Focus. Daily, weekly and "these weekdays" reminders use a repeating alarm.
- **Live Activities**: a Dynamic Island and Lock Screen countdown that starts a chosen number of minutes before the due time, even if the app isn't running. It can be completed or snoozed from there.
- **Nag mode**: follow-up notifications every 5 to 30 minutes after the due time until you mark the reminder done.
- **Location reminders**: go off when you arrive at or leave a place, once or every time. iOS watches the region itself, so Remder never tracks where you are. Home and Work are saved places you set in Settings.
- **Daily brief**: an optional morning summary and evening check-in, listing today's reminders and what is still open. They are rebuilt for the coming week whenever your reminders change.
- **Custom sounds**: Chime, Bell, Gentle, Pulse and Alert, plus the system default or silent.

### Add reminders in seconds
- **Quick add**: type it like you'd say it, for example `Call mom tomorrow 5pm #Work !high`. An offline parser handles dates and times, repeats, `#category`, `!high` / `!med` / `!low`, "alarm", "10 min before", and "when I get home". On devices that support it, Apple Intelligence (Foundation Models) refines the result and understands looser phrasing like "after work on Friday". Explicit syntax always wins.
- **Siri & Shortcuts** (App Intents): "Add a reminder in Remder", "What's next in Remder", and "Mark ... as done in Remder".
- **Flexible repeats** built on `Calendar.RecurrenceRule`: daily, weekly, monthly, every N days/weeks/months/years, specific weekdays, weekdays or weekends, "last Friday of the month", the 31st-of-the-month case, and an optional end date.

### Stay organized
- Color-coded **categories** with a sidebar and filter chips, and three priority levels.
- **Notes** you can attach to reminders for extra detail.
- **Insights**: current and best streaks for repeating reminders, 30-day completion rate and a completion heatmap, derived from a per-occurrence completion history.
- **Widgets** for the Home Screen (small, medium, large) and Lock Screen (circular, rectangular, inline). You can tick reminders off from the widget.

### Yours, everywhere
- **Accounts** with Sign in with Apple, Google or email and password (Supabase Auth).
- **Cloud sync** of reminders, notes, categories and completions between devices.
- **App Lock** with Face ID, Touch ID or passcode, with a configurable delay. It locks the app's screens only, so notifications and their actions keep working.

## Tech stack

- SwiftUI, SwiftData, App Intents, AlarmKit, ActivityKit / WidgetKit, UserNotifications, CoreLocation, LocalAuthentication, FoundationModels
- [supabase-swift](https://github.com/supabase/supabase-swift) for authentication and sync
- Swift Testing for unit tests and XCTest for UI tests
- Deployment target: iOS 27

## Architecture

| Area | What it does |
| --- | --- |
| `Shared/` | Code compiled into both the app and the widget extension: the SwiftData models (`Reminder`, `ReminderCategory`, `Note`, `Completion`), `RepeatRule`, Live Activity attributes and the complete-reminder intent. |
| `SharedStore` | Builds the single SwiftData container in an App Group, so the app and widgets read the same database. It migrates the older pre-widget store on first launch. |
| `Remder/Services/` | Delivery and logic: `NotificationManager`, `AlarmScheduler`, `LiveActivityManager`, `BriefScheduler`, `QuickAddParser` / `QuickAdd`, `StreakCalculator`, `AppLock`, and the Siri intents in `RemderShortcuts`. |
| `Remder/Services/Account/` | `AuthManager` (Supabase sign-in) and `SyncEngine`, which stores each record as one row in a `sync_records` table. Each sync pulls first (the server's copy wins), then pushes new, changed and deleted records, detected with a per-record hash. It runs after sign-in, when the app comes forward, and shortly after local saves. |
| `Remder/Views/` | `AppGate` (splash, welcome or sign-in, then the app), `RootView` with a sidebar, and the reminders, notes, insights, settings and about screens. |
| `RemderWidgets/` | The Upcoming Reminders widget, the countdown Live Activity and the alarm Live Activity. |

## Getting started

1. Open `Remder.xcodeproj` in Xcode with the iOS 27 SDK. Swift packages resolve automatically.
2. Select the `Remder` scheme, choose an iOS 27 simulator or device, and run.

Notes for running it yourself:
- Widgets and the shared database use the App Group `group.com.ineshsandivpersonalteam.Remder`. On a device, set your own signing team and App Group under Signing & Capabilities. Without the App Group the app falls back to its own container.
- Sign-in and sync talk to the Supabase project configured in `Remder/Services/Account/AuthManager.swift`. To use your own, replace the URL and publishable key there, create a `sync_records` table, and enable the Apple and Google providers and the `remder://` redirect URL in your Supabase dashboard.
- Alarms (AlarmKit), Live Activities and Apple Intelligence need a supported OS and device. The app degrades gracefully where they aren't available.

## Tests

```bash
xcodebuild -project Remder.xcodeproj -scheme Remder \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

- `RemderTests` covers repeat rules (including sync round trips), the quick add parser, the daily brief text, notification action IDs and streaks.
- `RemderUITests` drives sign-in, quick add, categories, completing and deleting reminders, the custom repeat editor, places, the daily brief settings and sidebar navigation. It launches the app with `-uiTesting` (a local test user, an in-memory database, no splash, no permission prompts and no sync); add `-signedOut` to start on the welcome screen.

## Project layout

```
Remder/            App: views, services, settings, sounds, assets
Shared/            Models and intents shared with the widget extension
RemderWidgets/     Widget and Live Activity extension
RemderTests/       Unit tests
RemderUITests/     UI tests
```
