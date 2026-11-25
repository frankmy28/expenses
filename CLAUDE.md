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

## Upgrade compatibility (App Store users)

Existing installs must keep their data. Do not change:
- the bundle id `de.frankmathy.ios.Expenses`,
- the Core Data container/model name `Expenses` (`Expensly/Persistence/Expenses.xcdatamodeld`, store `Application Support/Expenses.sqlite`),
- the UserDefaults keys in `AppSettings` (`CurrencyCode`, `LastCategory`, ...),
- the tab-separated export format in `ExpenseTextFormat` (old exports must still import).

Schema changes need a new model version (current: `Expenses 1.1`) that lightweight migration can handle; `MigrationTests` opens a store written with the original model. Data fixups run in code (`ExpenseStore.backfillCurrencies`).

## Architecture

- `ExpenseStore` (`@Observable`, `@MainActor`) is the single model, injected with `.environment`. It holds the selected `ExpensePeriod` (week/month/year/all, half-open date range), the loaded expenses and their groupings (`ExpenseGrouping.byDay` / `.byCategory`), and performs every write. After a change it calls `reload()`; views observe its properties. Errors go to `store.failure`, shown as an alert by `RootView`.
- All Core Data work runs on the main-queue view context. Entities use Xcode's class codegen; add behavior in extensions (`Expense+Conversion.swift`).
- Editing: `ExpenseDetailView` edits an `ExpenseDraft` value and calls `store.save(draft, to:)`. Nothing touches Core Data until Save.
- Naming quirks: an "Account" entity is shown as a "Budget". Categories and projects are both `NamedItem` rows told apart by `listName` (`NamedItemList`). Defaults are seeded on first use from the localized `DefaultValues.plist`.
- Currency: totals are in the app currency (`AppSettings.appCurrencyCode`, fixed once from the locale). `Expense.exchangeRate` converts one unit of the expense currency into the app currency. `ExchangeRateService` looks up rates in memory → newest active `ExchangeRate` row → floatrates.com (which sends rates as strings or numbers) and calls its update closure up to twice (stored, then fresh). An existing expense keeps its saved rate unless its currency changes.
- Locations come from MapKit points of interest (`LocationPickerView`), stored as venue id/name/lat/lng on the expense.
- First-run hints use TipKit (`Views/Tips.swift`).

## Localization

English is the source language; German translations are in `Expensly/Resources/Localizable.xcstrings`. Keys are the English text. When adding user-facing text, add the German translation to the catalog (plural forms as variations). `InfoPlist.strings` and `DefaultValues.plist` are localized in `en.lproj`/`de.lproj`.
