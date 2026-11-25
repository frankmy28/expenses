import CoreData
import Foundation
@testable import Expensly

/// A store on an in-memory Core Data stack with its own UserDefaults and a fixed calendar.
@MainActor
struct TestEnvironment {
    let persistence: PersistenceController
    let settings: AppSettings
    let store: ExpenseStore
    let calendar: Calendar
    var context: NSManagedObjectContext { persistence.viewContext }

    init(appCurrency: String = "EUR",
         now: Date = TestEnvironment.date("2026-11-25T12:00:00Z"),
         fetch: ExchangeRateService.Fetcher? = { _ in throw URLError(.notConnectedToInternet) }) {
        persistence = PersistenceController(inMemory: true)
        let defaults = UserDefaults(suiteName: "ExpenslyTests-\(UUID().uuidString)")!
        defaults.set(appCurrency, forKey: "CurrencyCode")
        settings = AppSettings(defaults: defaults)
        calendar = TestEnvironment.calendar
        let rates = ExchangeRateService(context: persistence.viewContext, calendar: calendar, fetch: fetch)
        store = ExpenseStore(context: persistence.viewContext, settings: settings, rates: rates,
                             calendar: calendar, now: now)
    }

    nonisolated static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2 // Monday
        calendar.minimumDaysInFirstWeek = 4
        calendar.locale = Locale(identifier: "de_DE")
        return calendar
    }

    nonisolated static func date(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso)!
    }

    @discardableResult
    func makeAccount(_ name: String = "Household") -> Account {
        let account = Account(context: context)
        account.accountName = name
        account.currencyCode = "EUR"
        account.currencySymbol = "€"
        return account
    }

    @discardableResult
    func makeExpense(_ amount: Double, at iso: String, category: String = "Foods",
                     currency: String? = "EUR", rate: Double = 1, account: Account? = nil) -> Expense {
        let expense = Expense(context: context)
        expense.amount = amount
        expense.date = TestEnvironment.date(iso)
        expense.category = category
        expense.project = "-"
        expense.currency = currency
        expense.exchangeRate = rate
        expense.account = account ?? makeAccount()
        return expense
    }
}
