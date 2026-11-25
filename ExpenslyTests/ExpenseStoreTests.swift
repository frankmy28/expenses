import CoreData
import Foundation
import Testing
@testable import Expensly

@MainActor
struct ExpenseStoreTests {
    @Test func conversionUsesRateOnlyForForeignCurrencies() {
        let env = TestEnvironment()
        #expect(env.makeExpense(10, at: "2026-11-25T10:00:00Z").amount(inAppCurrency: "EUR") == 10)
        #expect(env.makeExpense(10, at: "2026-11-25T10:00:00Z", currency: "USD", rate: 0.9).amount(inAppCurrency: "EUR") == 9)
        #expect(env.makeExpense(10, at: "2026-11-25T10:00:00Z", currency: nil).amount(inAppCurrency: "EUR") == 10)
        #expect(env.makeExpense(10, at: "2026-11-25T10:00:00Z", currency: "USD", rate: 0).amount(inAppCurrency: "EUR") == 10)
    }

    @Test func reloadShowsOnlyTheCurrentWeekGroupedAndTotalled() throws {
        let env = TestEnvironment()
        env.makeExpense(5, at: "2026-11-23T08:00:00Z", category: "Baker")
        env.makeExpense(20, at: "2026-11-25T09:00:00Z", category: "Foods")
        env.makeExpense(10, at: "2026-11-25T18:00:00Z", category: "Baker", currency: "USD", rate: 0.5)
        env.makeExpense(99, at: "2026-11-30T00:00:00Z") // next week
        env.makeExpense(99, at: "2026-11-22T23:59:59Z") // previous week
        try env.context.save()

        env.store.reload()

        #expect(env.store.expenses.count == 3)
        #expect(env.store.total == 30)
        #expect(env.store.byDay.map(\.key) == [TestEnvironment.date("2026-11-25T00:00:00Z"),
                                               TestEnvironment.date("2026-11-23T00:00:00Z")])
        #expect(env.store.byDay[0].total == 25)
        #expect(env.store.byDay[0].expenses.map(\.amount) == [10, 20]) // newest first
        #expect(env.store.byCategory.map(\.key) == ["Baker", "Foods"])
        #expect(env.store.byCategory.map(\.total) == [10, 20])
    }

    @Test func movingThePeriodReloads() throws {
        let env = TestEnvironment()
        env.makeExpense(99, at: "2026-11-30T10:00:00Z")
        try env.context.save()
        env.store.reload()
        #expect(env.store.expenses.isEmpty)

        env.store.showNextPeriod()
        #expect(env.store.total == 99)

        env.store.setPeriodType(.all)
        #expect(env.store.period.range == nil)
        #expect(env.store.expenses.count == 1)
    }

    @Test func backfillsCurrencyOfOldExpenses() throws {
        let env = TestEnvironment()
        let legacy = env.makeExpense(7, at: "2026-11-24T10:00:00Z", currency: nil, rate: 0)
        let defaulted = env.makeExpense(8, at: "2026-11-24T11:00:00Z", currency: "I", rate: 0)
        try env.context.save()

        env.store.reload()

        #expect(legacy.currency == "EUR")
        #expect(legacy.exchangeRate == 1)
        #expect(defaulted.currency == "EUR")
        #expect(!env.context.hasChanges)
    }

    @Test func seedsDefaultBudgetsCategoriesAndProjects() {
        let env = TestEnvironment()
        let accounts = env.store.accounts()
        let categories = env.store.items(.categories)
        #expect(accounts.count == 1)
        #expect(accounts.first?.currencyCode == "EUR")
        #expect(categories.count == 11)
        #expect(env.store.items(.projects).map(\.itemName) == ["-"])
        // Seeding happens only once.
        #expect(env.store.items(.categories).count == 11)
    }

    @Test func newDraftUsesLastUsedValues() {
        let env = TestEnvironment()
        let groceries = env.store.addAccount(named: "Groceries")!
        env.settings.lastCategory = "Car"
        env.settings.lastAccount = "Groceries"

        let draft = env.store.newDraft()

        #expect(draft.category == "Car")
        #expect(draft.account == groceries)
        #expect(draft.project == "-")
        #expect(draft.currency == "EUR")
        #expect(!draft.isValid(appCurrency: "EUR")) // amount is still 0
    }

    @Test func savingADraftCreatesThenUpdatesAnExpense() throws {
        let env = TestEnvironment()
        var draft = env.store.newDraft(now: TestEnvironment.date("2026-11-25T10:00:00Z"))
        draft.amount = 12.5
        draft.category = "Restaurant"
        draft.comment = "Lunch"
        draft.venue = Venue(id: "v1", name: "Café", latitude: 52.5, longitude: 13.4)

        let expense = try #require(env.store.save(draft))
        #expect(env.store.expenses == [expense])
        #expect(expense.venueName == "Café")
        #expect(env.settings.lastCategory == "Restaurant")

        var edit = env.store.draft(for: expense)
        edit.amount = 15
        edit.venue = nil
        env.store.save(edit, to: expense)

        #expect(try env.context.count(for: Expense.fetchRequest()) == 1)
        #expect(expense.amount == 15)
        #expect(expense.venueId == nil)
        #expect(env.store.total == 15)
    }

    @Test func foreignDraftNeedsARate() {
        let env = TestEnvironment()
        var draft = env.store.newDraft()
        draft.amount = 10
        draft.currency = "USD"
        draft.exchangeRate = 0
        #expect(!draft.isValid(appCurrency: "EUR"))
        draft.exchangeRate = 0.9
        #expect(draft.isValid(appCurrency: "EUR"))
        #expect(draft.amountInAppCurrency("EUR") == 9)
    }

    @Test func budgetInUseIsNotDeleted() throws {
        let env = TestEnvironment()
        let account = env.makeAccount("Travel")
        env.makeExpense(1, at: "2026-11-25T10:00:00Z", account: account)
        try env.context.save()

        env.store.delete(account)

        #expect(env.store.failure != nil)
        #expect(!account.isDeleted)
        #expect(try env.context.count(for: Account.fetchRequest()) == 1)

        let unused = env.store.addAccount(named: "Unused")!
        env.store.delete(unused)
        #expect(try env.context.count(for: Account.fetchRequest()) == 1)
    }

    @Test func renamingABudgetUpdatesLastUsed() {
        let env = TestEnvironment()
        let account = env.store.addAccount(named: "Old")!
        env.settings.lastAccount = "Old"
        env.store.rename(account, to: "New")
        #expect(account.accountName == "New")
        #expect(env.settings.lastAccount == "New")
    }

    @Test func deleteAllExpensesKeepsBudgets() throws {
        let env = TestEnvironment()
        env.makeExpense(1, at: "2026-11-25T10:00:00Z")
        env.makeExpense(2, at: "2020-01-01T10:00:00Z")
        try env.context.save()

        env.store.deleteAllExpenses()

        #expect(try env.context.count(for: Expense.fetchRequest()) == 0)
        #expect(try env.context.count(for: Account.fetchRequest()) == 2)
    }
}
