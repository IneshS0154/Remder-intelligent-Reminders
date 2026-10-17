# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Remder is an iOS-only (deployment target iOS 27) SwiftUI reminders app with widgets, Live Activities, alarms, notes and optional cloud sync. There is no README, linter or package manifest of its own; dependencies (Supabase via SPM) are resolved by the Xcode project.

## Commands

Targets: `Remder` (app), `RemderWidgetsExtension`, `RemderTests` (unit), `RemderUITests`. Shared scheme: `Remder`.

```bash
xcodebuild -project Remder.xcodeproj -scheme Remder -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
xcodebuild -project Remder.xcodeproj -scheme Remder -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test -only-testing:RemderTests
xcodebuild -project Remder.xcodeproj -scheme Remder -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test -only-testing:RemderTests/RepeatRuleTests/<testName>
```

Adjust the simulator name to one installed locally (`xcrun simctl list devices`).

## Architecture

- **`Shared/`** is compiled into both the app and the widget extension: SwiftData models (`Reminder`, `ReminderCategory`, `Note`, `Completion`), `RepeatRule`, Live Activity attributes, and App Intents (`CompleteReminderIntent`). Code needed by widgets must live here, not in `Remder/`.
- **`SharedStore`** builds the single SwiftData `ModelContainer` in the App Group container so the app and widgets see the same data. It falls back to the app's own container when the App Group entitlement is missing, and migrates the pre-widget store on first launch. Adding a model means adding it to `SharedStore.schema`.
- **`RemderApp.sharedContainer`** is a static container so code outside the view tree (notification actions in `NotificationDelegate`, intents, `SyncEngine`) can read and write the same data.
- **Reminders delivery** is layered: `NotificationManager` (local notifications + actions), `AlarmScheduler` (AlarmKit-style alarms), `LiveActivityManager`, `BriefScheduler` (daily brief), `RemderShortcuts`/`ReminderIntentHandler` (Siri/Shortcuts). Quick add goes through `QuickAddParser` (natural-language parsing) and `QuickAdd`.
- **Account/sync** (`Remder/Services/Account/`): `AuthManager` handles Supabase auth; `SyncEngine` does two-way sync against a single `sync_records` table (one row per record keyed by kind + key; pull first with server-wins, then push diffs by per-record hash). It listens to `ModelContext.didSave` and uses `isApplyingRemote` to ignore its own writes. `AppGate` (views/Account) decides between splash, welcome/sign-in and the main `RootView`.
- **UI**: `RootView` + `SidebarView` host `RemindersView`, `NotesView`, `InsightsView`, `SettingsView`; `AppSettings` (`Remder/Settings/`) holds preferences.

## Testing notes

- Unit tests use in-memory containers via `makeContext()` and the `date(...)`/`reminder(...)` helpers in `RemderTests/TestHelpers.swift`.
- UI tests launch the app with `-uiTesting` (signed in as a local test user, in-memory DB, no splash/permission prompts/sync); add `-signedOut` to start on the welcome screen. See `UITestMode`.
