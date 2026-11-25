import CoreData
import Foundation
import Testing
@testable import Expensly

/// Checks that a store written by the first App Store version (model "Expenses", no currency
/// attributes) opens in the new app and its expenses get a currency.
@MainActor
struct MigrationTests {
    @Test func opensAVersion1StoreAndBackfillsCurrency() throws {
        let directory = URL.temporaryDirectory.appending(path: "MigrationTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appending(path: "Expenses.sqlite")

        // Write a store with the original model version.
        let momd = try #require(Bundle(for: PersistenceController.self).url(forResource: "Expenses", withExtension: "momd"))
        let oldModel = try #require(NSManagedObjectModel(contentsOf: momd.appending(path: "Expenses.mom")))
        #expect(oldModel.entitiesByName["ExchangeRate"] == nil)
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: oldModel)
        let store = try coordinator.addPersistentStore(type: .sqlite, at: storeURL)
        let oldContext = NSManagedObjectContext(.mainQueue)
        oldContext.persistentStoreCoordinator = coordinator
        let account = NSEntityDescription.insertNewObject(forEntityName: "Account", into: oldContext)
        account.setValue("Haushalt", forKey: "accountName")
        account.setValue("EUR", forKey: "currencyCode")
        let expense = NSEntityDescription.insertNewObject(forEntityName: "Expense", into: oldContext)
        expense.setValue(4.2, forKey: "amount")
        expense.setValue("Bäcker", forKey: "category")
        expense.setValue("-", forKey: "project")
        expense.setValue(TestEnvironment.date("2018-05-01T08:00:00Z"), forKey: "date")
        expense.setValue(account, forKey: "account")
        try oldContext.save()
        try coordinator.remove(store)

        // Open it the way the new app does.
        let persistence = PersistenceController(storeURL: storeURL)
        #expect(persistence.loadError == nil)
        let defaults = UserDefaults(suiteName: "MigrationTests-\(UUID().uuidString)")!
        defaults.set("EUR", forKey: "CurrencyCode")
        let expenseStore = ExpenseStore(context: persistence.viewContext, settings: AppSettings(defaults: defaults),
                                        calendar: TestEnvironment.calendar)
        expenseStore.setPeriodType(.all)

        let migrated = try #require(expenseStore.expenses.first)
        #expect(expenseStore.expenses.count == 1)
        #expect(migrated.amount == 4.2)
        #expect(migrated.account?.accountName == "Haushalt")
        #expect(migrated.currency == "EUR")
        #expect(migrated.exchangeRate == 1)
    }
}
