import CoreData
import Foundation
import Observation

/// The app's model: the selected period, the expenses in it, and all changes to the store.
/// Replaces the old `Model` singleton, its delegate list and the `CD*DAO` classes.
@MainActor
@Observable
final class ExpenseStore {
    struct Failure: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    @ObservationIgnored let context: NSManagedObjectContext
    @ObservationIgnored let settings: AppSettings
    @ObservationIgnored let rates: ExchangeRateService
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored let bundle: Bundle
    /// The clock for change and deletion times used by sync. Tests replace it.
    @ObservationIgnored var now: () -> Date = { .now }

    private(set) var period: ExpensePeriod
    private(set) var expenses: [Expense] = []
    private(set) var byDay: [ExpenseGroup<Date>] = []
    private(set) var byCategory: [ExpenseGroup<String>] = []
    private(set) var total: Double = 0
    /// Bumped on every change to budgets, categories or projects so pickers refresh.
    var listsVersion = 0
    var failure: Failure?

    var appCurrency: String { settings.appCurrencyCode }

    init(context: NSManagedObjectContext,
         settings: AppSettings = AppSettings(),
         rates: ExchangeRateService? = nil,
         calendar: Calendar = .current,
         bundle: Bundle = .main,
         now: Date = .now) {
        self.context = context
        self.settings = settings
        self.rates = rates ?? ExchangeRateService(context: context, calendar: calendar)
        self.calendar = calendar
        self.bundle = bundle
        self.period = .containing(now, type: .week, calendar: calendar)
    }

    // MARK: - Period

    func setPeriodType(_ type: PeriodType) {
        guard type != period.type else { return }
        // Like the old app: a new period type starts at the current week/month/year.
        period = .containing(.now, type: type, calendar: calendar)
        reload()
    }

    func showCurrentPeriod() {
        period = .containing(.now, type: period.type == .all ? .week : period.type, calendar: calendar)
        reload()
    }

    func showNextPeriod() {
        period = period.next(calendar: calendar)
        reload()
    }

    func showPreviousPeriod() {
        period = period.previous(calendar: calendar)
        reload()
    }

    // MARK: - Loading

    func reload() {
        let request = Expense.fetchRequest()
        if let range = period.range {
            request.predicate = NSPredicate(format: "date >= %@ AND date < %@",
                                            range.lowerBound as NSDate, range.upperBound as NSDate)
        }
        do {
            let loaded = try context.fetch(request)
            backfillCurrencies(loaded)
            expenses = loaded
        } catch {
            report(String(localized: "Error loading expenses"), error)
            expenses = []
        }
        let currency = appCurrency
        byDay = ExpenseGrouping.byDay(expenses, appCurrency: currency, calendar: calendar)
        byCategory = ExpenseGrouping.byCategory(expenses, appCurrency: currency)
        total = ExpenseGrouping.total(expenses, appCurrency: currency)
    }

    /// Expenses from before model version 1.1 have no currency (or the model default "I").
    /// They were entered in their budget's currency at a rate of 1.
    private func backfillCurrencies(_ expenses: [Expense]) {
        var changed = false
        for expense in expenses where expense.currency?.count != 3 {
            expense.currency = expense.account?.currencyCode ?? appCurrency
            expense.exchangeRate = 1
            changed = true
        }
        if changed { save(String(localized: "Error saving expense record")) }
    }

    // MARK: - Expenses

    func newDraft(now: Date = .now) -> ExpenseDraft {
        let categories = items(.categories).compactMap(\.itemName)
        let projects = items(.projects).compactMap(\.itemName)
        let budgets = accounts()
        let account = settings.lastAccount.flatMap { name in budgets.first { $0.accountName == name } } ?? budgets.first
        return ExpenseDraft(date: now,
                            amount: 0,
                            currency: appCurrency,
                            exchangeRate: 1,
                            category: settings.lastCategory ?? categories.first,
                            project: settings.lastProject ?? projects.first,
                            account: account,
                            comment: "",
                            venue: nil)
    }

    func draft(for expense: Expense) -> ExpenseDraft {
        let hasCurrency = expense.currency?.count == 3
        return ExpenseDraft(date: expense.date ?? .now,
                            amount: expense.amount,
                            currency: hasCurrency ? expense.currency! : appCurrency,
                            exchangeRate: hasCurrency ? expense.exchangeRate : 1,
                            category: expense.category,
                            project: expense.project,
                            account: expense.account,
                            comment: expense.comment ?? "",
                            venue: expense.venue)
    }

    /// Writes the draft to `expense`, or to a new expense when `expense` is nil, and saves.
    @discardableResult
    func save(_ draft: ExpenseDraft, to expense: Expense? = nil) -> Expense? {
        let target = expense ?? Expense(context: context)
        target.date = draft.date
        target.amount = draft.amount
        target.currency = draft.currency
        target.exchangeRate = draft.currency == appCurrency ? 1 : draft.exchangeRate
        target.category = draft.category
        target.project = draft.project
        target.account = draft.account
        target.comment = draft.comment
        target.venueId = draft.venue?.id
        target.venueName = draft.venue?.name
        target.venueLat = draft.venue?.latitude ?? 0
        target.venueLng = draft.venue?.longitude ?? 0
        if target.uuid == nil { target.uuid = UUID() }
        target.modifiedAt = now()
        guard save(String(localized: "Error saving expense record")) else { return nil }
        settings.lastCategory = draft.category
        settings.lastProject = draft.project
        settings.lastAccount = draft.account?.accountName
        reload()
        return target
    }

    func delete(_ expense: Expense) {
        recordDeletion(of: expense)
        context.delete(expense)
        save(String(localized: "Error deleting expense record"))
        reload()
    }

    func deleteAllExpenses() {
        do {
            for expense in try context.fetch(Expense.fetchRequest()) {
                recordDeletion(of: expense)
                context.delete(expense)
            }
        } catch {
            report(String(localized: "Error deleting expense record"), error)
        }
        save(String(localized: "Error deleting expense record"))
        reload()
    }

    // MARK: - Import / export

    /// The expenses of the current period in the export format, newest first.
    func exportText() -> String {
        ExpenseTextFormat.text(for: byDay.flatMap(\.expenses))
    }

    /// Imports an export file and returns the number of imported expenses. Budgets that do
    /// not exist yet are created.
    @discardableResult
    func importText(_ text: String) throws -> Int {
        let rows = ExpenseTextFormat.parse(text, defaultCurrency: appCurrency)
        var budgets = Dictionary(fetchAccounts().compactMap { a in a.accountName.map { ($0, a) } },
                                 uniquingKeysWith: { first, _ in first })
        for row in rows {
            let account = budgets[row.accountName] ?? {
                let account = makeAccount(named: row.accountName)
                budgets[row.accountName] = account
                return account
            }()
            let expense = Expense(context: context)
            expense.date = row.date
            expense.amount = row.amount
            expense.account = account
            expense.category = row.category
            expense.project = row.project
            expense.comment = row.comment
            expense.venueId = row.venue?.id
            expense.venueName = row.venue?.name
            expense.venueLat = row.venue?.latitude ?? 0
            expense.venueLng = row.venue?.longitude ?? 0
            expense.currency = row.currency
            expense.exchangeRate = row.exchangeRate
            expense.uuid = UUID()
            expense.modifiedAt = now()
        }
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
        listsVersion += 1
        reload()
        return rows.count
    }

    // MARK: - Budgets ("Account" in the data model)

    /// All budgets sorted by name. Seeds the defaults on first use.
    func accounts() -> [Account] {
        let found = fetchAccounts()
        guard found.isEmpty else { return found }
        let seeded = DefaultValues.load("accounts", bundle: bundle).map(makeAccount(named:))
        guard !seeded.isEmpty else { return [] }
        save(String(localized: "Error saving budget"))
        return seeded
    }

    @discardableResult
    func addAccount(named name: String) -> Account? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        let account = makeAccount(named: name)
        guard save(String(localized: "Error saving budget")) else { return nil }
        listsVersion += 1
        return account
    }

    func rename(_ account: Account, to name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        if settings.lastAccount == account.accountName { settings.lastAccount = name }
        if let oldName = account.accountName, var shared = settings.sharedBudgetNames, shared.contains(oldName) {
            shared.remove(oldName)
            shared.insert(name)
            settings.sharedBudgetNames = shared
        }
        account.accountName = name
        // Sync matches budgets by name: mark the expenses as changed so the new name spreads.
        let changedAt = now()
        for case let expense as Expense in account.expenses ?? [] {
            expense.modifiedAt = changedAt
        }
        save(String(localized: "Error saving budget"))
        listsVersion += 1
        reload()
    }

    /// Deletes a budget. A budget that expenses still use cannot be deleted (every expense
    /// needs one); the old app tried anyway and failed silently.
    func delete(_ account: Account) {
        let count = account.expenses?.count ?? 0
        guard count == 0 else {
            failure = Failure(title: String(localized: "Budget in use"),
                              message: String(localized: "\(count) expenses use the budget \(account.accountName ?? ""). Move or delete them first."))
            return
        }
        context.delete(account)
        save(String(localized: "Error saving budget"))
        listsVersion += 1
    }

    /// Budgets as stored, without seeding (an import brings its own budgets).
    func fetchAccounts() -> [Account] {
        let request = Account.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "accountName", ascending: true,
                                                    selector: #selector(NSString.localizedStandardCompare(_:)))]
        return (try? context.fetch(request)) ?? []
    }

    func makeAccount(named name: String) -> Account {
        let account = Account(context: context)
        account.accountName = name
        account.currencyCode = appCurrency
        account.currencySymbol = settings.appCurrencySymbol
        return account
    }

    // MARK: - Categories and projects

    /// Items of one list sorted by name. Seeds the defaults on first use.
    func items(_ list: NamedItemList) -> [NamedItem] {
        let request = NamedItem.fetchRequest()
        request.predicate = NSPredicate(format: "listName == %@", list.rawValue)
        request.sortDescriptors = [NSSortDescriptor(key: "itemName", ascending: true,
                                                    selector: #selector(NSString.localizedStandardCompare(_:)))]
        let found = (try? context.fetch(request)) ?? []
        guard found.isEmpty else { return found }
        let seeded = DefaultValues.load(list.rawValue, bundle: bundle).map { makeItem($0, in: list) }
        guard !seeded.isEmpty else { return [] }
        save(String(localized: "Error saving item"))
        return seeded
    }

    @discardableResult
    func addItem(named name: String, to list: NamedItemList) -> NamedItem? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        let item = makeItem(name, in: list)
        guard save(String(localized: "Error saving item")) else { return nil }
        listsVersion += 1
        return item
    }

    /// Removes an item from the picker. Expenses store the name as text, so they keep it.
    func delete(_ item: NamedItem) {
        context.delete(item)
        save(String(localized: "Error saving item"))
        listsVersion += 1
    }

    @discardableResult
    func makeItem(_ name: String, in list: NamedItemList) -> NamedItem {
        let item = NamedItem(context: context)
        item.itemName = name
        item.listName = list.rawValue
        return item
    }

    // MARK: - Errors

    @discardableResult
    func save(_ errorTitle: String) -> Bool {
        guard context.hasChanges else { return true }
        do {
            try context.save()
            return true
        } catch {
            context.rollback()
            report(errorTitle, error)
            return false
        }
    }

    func report(_ title: String, _ error: Error) {
        failure = Failure(title: title, message: error.localizedDescription)
    }
}
