# Remder

A reminders app for iPhone built with SwiftUI and SwiftData.

## Features

- Reminders with priorities, categories, locations and flexible repeat rules
- Natural-language quick add
- Notifications with actions, alarms and Live Activities
- Home Screen widgets and Siri/Shortcuts support
- Notes, plus insights and streaks
- Optional app lock
- Optional account with cloud sync across devices (Supabase)

## Requirements

- Xcode with the iOS 27 SDK
- An iOS 27 simulator or device

## Getting started

1. Open `Remder.xcodeproj` in Xcode. Swift packages resolve automatically.
2. Select the `Remder` scheme and run.

Widgets and the shared database use an App Group, so building to a device requires your own signing team and App Group set under Signing & Capabilities. Without the App Group the app falls back to its own container.

## Tests

```bash
xcodebuild -project Remder.xcodeproj -scheme Remder \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

UI tests launch the app with `-uiTesting` (local test user, in-memory database, no sync).

## Project layout

- `Remder/`: app code (views, services, settings)
- `Shared/`: models and intents shared by the app and widgets
- `RemderWidgets/`: widget and Live Activity extension
- `RemderTests/`, `RemderUITests/`: unit and UI tests
