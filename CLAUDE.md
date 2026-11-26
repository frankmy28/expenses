# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

"Expensly": an iOS app for tracking daily cash expenses. It was first released to the App Store in 2018 (UIKit, CocoaPods) and was rewritten in SwiftUI for version 2.0 (Swift 6 language mode, iOS 17+, built with Xcode 27). There are no third-party dependencies. Release notes are in `doc/version.txt`; each 1.x release lists the GitHub issues it closed, and commit messages follow `<issue title> #<number>`.

## Build and test

The Xcode project is generated from `project.yml` with XcodeGen. `Expensly.xcodeproj` is checked in; regenerate it after changing `project.yml` or adding/removing files:

```sh
xcodegen generate
xcodebuild -project Expensly.xcodeproj -scheme Expensly -destination 'platform=iOS Simulator,name=iPhone 17' build
xcodebuild test -project Expensly.xcodeproj -scheme Expensly -destination 'platform=iOS Simulator,name=iPhone 17'
# single test (Swift Testing):
xcodebuild test ... -only-testing:ExpenslyTests/ExpenseStoreTests/backfillsCurrencyOfOldExpenses
```

Tests use Swift Testing (`ExpenslyTests/`). `TestEnvironment` gives each test an in-memory Core Data stack, its own UserDefaults suite, a fixed UTC calendar and a fake exchange-rate fetcher (offline by default). Tests never hit the network.

## Signing and data compatibility

The app is no longer on the App Store and is built with a free personal team (`Y2NF3B2C3V`), so it uses the bundle id `de.frankmathy.apps.Expenses` (the old App Store id `de.frankmathy.ios.Expenses` belongs to the former paid team). Free provisioning means no iCloud/CloudKit entitlement and 7-day app expiry on devices. Change signing in `project.yml`, not in Xcode's Signing tab, or the next `xcodegen generate` reverts it.

Stored data must stay readable. Do not change:
- the Core Data container/model name `Expenses` (`Expensly/Persistence/Expenses.xcdatamodeld`, store `Application Support/Expenses.sqlite`),
- the UserDefaults keys in `AppSettings` (`CurrencyCode`, `LastCategory`, ...),
- the tab-separated export format in `ExpenseTextFormat` (old exports must still import),
- the sync file format (`SyncSnapshot`, `format` 1) — other family members may run an older build.

Schema changes need a new model version (current: `Expenses 1.2`) that lightweight migration can handle; `MigrationTests` opens a store written with the original model. Data fixups run in code (`ExpenseStore.backfillCurrencies`).

## Architecture

- `ExpenseStore` (`@Observable`, `@MainActor`) is the single model, injected with `.environment`. It holds the selected `ExpensePeriod` (week/month/year/all, half-open date range), the loaded expenses and their groupings (`ExpenseGrouping.byDay` / `.byCategory`), and performs every write. After a change it calls `reload()`; views observe its properties. Errors go to `store.failure`, shown as an alert by `RootView`.
- All Core Data work runs on the main-queue view context. Entities use Xcode's class codegen; add behavior in extensions (`Expense+Conversion.swift`).
- Editing: `ExpenseDetailView` edits an `ExpenseDraft` value and calls `store.save(draft, to:)`. Nothing touches Core Data until Save.
- Naming quirks: an "Account" entity is shown as a "Budget". Categories and projects are both `NamedItem` rows told apart by `listName` (`NamedItemList`). Defaults are seeded on first use from the localized `DefaultValues.plist`.
- Currency: totals are in the app currency (`AppSettings.appCurrencyCode`, fixed once from the locale). `Expense.exchangeRate` converts one unit of the expense currency into the app currency. `ExchangeRateService` looks up rates in memory → newest active `ExchangeRate` row → floatrates.com (which sends rates as strings or numbers) and calls its update closure up to twice (stored, then fresh). An existing expense keeps its saved rate unless its currency changes.
- Locations come from MapKit points of interest (`LocationPickerView`), stored as venue id/name/lat/lng on the expense.
- First-run hints use TipKit (`Views/Tips.swift`).
- Sharing budgets (no CloudKit): the user picks a folder (typically an iCloud Drive folder shared with the family in the Files app); a security-scoped bookmark is kept in `AppSettings`. `SyncService` runs on app open/background and on "Sync Now": it reads every other device's `Expensly-<device id>.json` (`SyncFolder`, coordinated file access off the main thread), merges each into the store (`ExpenseStore.merge`), then writes this device's own file (`ExpenseStore.syncSnapshot`). Each device only ever writes its own file. Expenses carry a `uuid` and `modifiedAt` (model 1.2); deletions are kept as `DeletedExpense` rows. Merge rules: newest `modifiedAt` wins, a deletion wins over older changes, budgets are matched by name, only budgets in `AppSettings.sharedBudgetNames` (nil = all) are sent or received, and an unknown remote expense matching a local one by date/amount/currency/category/budget is treated as the same (avoids duplicates after both sides imported the same export). Any code that creates, edits or deletes expenses must set `modifiedAt` / record a deletion, or the change won't spread.

## Localization

English is the source language; German translations are in `Expensly/Resources/Localizable.xcstrings`. Keys are the English text. When adding user-facing text, add the German translation to the catalog (plural forms as variations). `InfoPlist.strings` and `DefaultValues.plist` are localized in `en.lproj`/`de.lproj`.
