# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

"Expensly": an iOS app for tracking daily cash expenses, written in Swift 4.0 (UIKit, storyboards, Core Data). It was released to the App Store in 2018. The project was last upgraded for Xcode 10 (`LastUpgradeVersion = 1000`), the iOS deployment target is 10.0/11.1, and the pods are pinned to their 2018 versions (CocoaPods 1.3.1). Release notes are in `doc/version.txt`, and each release lists the GitHub issue numbers it closed. Commit messages follow the same convention: `<issue title> #<number>`.

## Build and run

Dependencies come from CocoaPods (Firebase/Core, Instructions, ActionSheetPicker-3.0), and `Pods/` is gitignored. Always build the **workspace**, not the `.xcodeproj`:

```sh
pod install
open Expenses.xcworkspace
# command line:
xcodebuild -workspace Expenses.xcworkspace -scheme Expenses \
  -destination 'generic/platform=iOS Simulator' build
```

**Credentials live outside the repo.** `AppCredentials.swift` (Foursquare `clientId`/`clientSecret`, used by `Util/FoursquareClient.swift`) and `GoogleService-Info.plist` (Firebase) are referenced in `project.pbxproj` by the relative path `../../../../Documents/Development/iOS/FrankMathyCredentials/`. The real files are in `~/Documents/Development/iOS/FrankMathyCredentials/`. That relative path only resolves when the checkout sits three directories below `$HOME`. From `~/devlocal/expenses` it does not, so the build fails until the file references are fixed or the files are made reachable. Never commit these files.

## Tests

The test targets are effectively disabled:
- The shared `Expenses` scheme has no Testables, so `xcodebuild test` runs nothing.
- The `ExpensesTests` target's Sources build phase is empty. The files in `ExpensesTests/` are not compiled.
- Those files are stale. `TestData.swift` uses initializers like `Account(accountName:)` and `Expense(date:category:...)` from before the move to Core Data, so they would not compile today. `ExchangeRateServiceTest` also calls the live floatrates.com API.

Before writing or running unit tests, do all of the following:
1. Add the test files to the `ExpensesTests` target.
2. Add the target to the scheme's Testables.
3. Rewrite the fixtures to create `Expense`/`Account` objects in an `NSManagedObjectContext`, ideally an in-memory store.

After that, a single test runs with:

```sh
xcodebuild test -workspace Expenses.xcworkspace -scheme Expenses \
  -destination 'platform=iOS Simulator,name=<device>' \
  -only-testing:ExpensesTests/DateIntervalSelectionTests/<testMethod>
```

## Architecture

**Data flow.** View controllers → `Model.sharedInstance` (`Model/Model.swift`) → Core Data DAOs (`CoreData/CD*DAO.swift`) → `CoreDataUtil.sharedInstance.managedObjectContext`, which is `AppDelegate.persistentContainer.viewContext`. Everything is a `sharedInstance` singleton and runs on the main-thread view context. There are no background contexts.

**Model as observable hub.** `Model` holds the date filter (`DateIntervalSelection`: Week/Month/Year/All) and two `GroupedExpenseModel<Key>` instances that back the table views:
- `expenseByDateModel`: grouped by start of day, newest first.
- `expenseByCategoryModel`: grouped by category name.

`reloadExpenses()` fetches the expenses for the current interval, rebuilds both groupings, then notifies the registered `ModelDelegate`s (`modelUpdated`, `dateIntervalChanged`, `cloudAccessError`). View controllers register with `Model.sharedInstance.addObserver`. Totals are summed from `Expense.amountAccountCcy`, which is the amount converted with `exchangeRate` when `currency` differs from the app currency.

**Edit/save via unwind segues.** `ExpenseDetailsViewController` edits the managed `Expense` object in place. For a new expense it first creates one in the context. The unwind actions in `ExpensesViewController` either save (`saveExpenseDetail` → `Model.updateExpense` → `context.save()`) or discard (`cancelToExpensesViewController` → `CoreDataUtil.rollbackChanges()`, which calls `context.reset()`). Unsaved changes anywhere in the context are discarded on cancel.

**Core Data model.** `Expenses.xcdatamodeld` is versioned, and the current version is `Expenses 1.1`. The entities are `Expense`, `Account`, `NamedItem` and `ExchangeRate`:
- `Expense` uses **manual codegen**. Its classes live in `CoreData/Model/Expense+CoreData{Class,Properties}.swift` and must be updated by hand when its attributes change.
- `Account`, `NamedItem` and `ExchangeRate` use Xcode's automatic class codegen.
- Schema changes need a new model version, which relies on lightweight migration. Data fixups run in code: see `CDExpensesDAO.doMigrationIfRequired`, which backfills `currency`/`exchangeRate` on load.

**Naming quirks:**
- An "Account" in code is shown to users as a "Budget" (renamed in #87).
- Categories and projects are both `NamedItem` rows, distinguished by `listName` (`"categories"`, `"projects"`).
- On first use, accounts, categories and projects are seeded from `DefaultValues.plist` (localized under `Base.lproj`/`de.lproj`) via `PListUtils`.

**Exchange rates.** `Service/ExchangeRateService.swift` looks up rates in three tiers: an in-memory cache, then the newest `active` `ExchangeRate` row in Core Data, then `https://www.floatrates.com/daily/<CCY>.json`. It refetches when the cached rate is not from today. The completion handler can fire twice: once with a stale cached rate, then with the fresh one. The supported currencies are hard-coded in `availableCurrencies`.

**Import/export format.** Export (`Model.CSV()`, shared from `ExpensesViewController`) and import (`InfoViewController.documentPicker`) use a tab-separated text format with ISO-8601 dates. The columns are: date, amount, account, category, project, comment, venueId, venueName, lat, lng, currency, exchangeRate. Import accepts ≥10 columns, and the currency columns are optional for older files. Keep the writer and the parser in sync.

**Location.** `EditLocationViewController` uses MapKit and CoreLocation. Venues come from the Foursquare v2 API (`FoursquareClient`). JSON parsing uses the vendored `Util/SwiftyJSON.swift`, which is third-party code; don't edit it.

**Dead code.** `Expenses/CloudKit/` (CK* DAOs, subscription manager) comes from an earlier CloudKit-backed version and is **not in any build phase**. It is not compiled, and the commented-out code in `Model.swift`/`AppDelegate.swift` refers to it. The README's mention of CloudKit sharing and live updates describes that old design. The app is now local Core Data only.

## UI, localization, analytics

- All screens are in `Base.lproj/Main.storyboard`. Segue identifiers such as `AddExpense` and `EditExpense` are matched as strings in `prepare(for:)`, and an unknown identifier hits `fatalError`.
- Each screen shows first-run coach marks using the `Instructions` pod (`CoachMarksController`). A "help was displayed" flag for each screen is stored in `SystemConfig` (UserDefaults). `SystemConfig` also stores the app currency (defaulting to the locale's) and the last-used category, project and account.
- Localization: English (Base) and German (`de.lproj`). `NSLocalizedString` keys are the English text itself, and format-string keys are mangled, e.g. `"Imported d expenses from s"`. Add new keys to both `Base.lproj/Localizable.strings` and `de.lproj/Localizable.strings`. The top-level `Expenses/Localizable.strings` is an unused stub.
- Firebase Analytics events (`Analytics.logEvent`) are logged from the view controllers.
