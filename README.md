# Expensly - iOS Expense Tracking App

Expensly is an iOS app for tracking your daily cash expenses. It is meant for the money you spend in
shops, cafés and on the go, not as financial software for your bank accounts.

Goals:
- Simple user interface built from standard iOS controls
- Quick entry of an expense, including foreign currencies with automatic conversion
- Simple reports per week, month or year and per category
- Export and import as a tab-separated text file
- Sharing budgets with family members through a shared iCloud Drive folder

Data is stored on the device with Core Data. Sharing works without CloudKit: each device writes
its own sync file into a folder everyone can access (for example an iCloud Drive folder shared in
the Files app) and merges the others' files.

## Building

The app is written in SwiftUI (Swift 6, iOS 17 or later). The Xcode project is generated from
`project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen). The generated
`Expensly.xcodeproj` is checked in, so you only need XcodeGen when you change `project.yml`:

```sh
xcodegen generate
open Expensly.xcodeproj
```

Run the unit tests:

```sh
xcodebuild test -project Expensly.xcodeproj -scheme Expensly \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

Release notes are in `doc/version.txt`.
