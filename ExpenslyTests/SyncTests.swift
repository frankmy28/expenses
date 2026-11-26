import CoreData
import Foundation
import Testing
@testable import Expensly

/// Two family members, each with their own store, exchanging snapshots.
@MainActor
struct SyncTests {
    let anna = TestEnvironment()
    let ben = TestEnvironment()

    init() {
        setClock(anna, "2026-11-25T12:00:00Z")
        setClock(ben, "2026-11-25T12:00:00Z")
    }

    private func setClock(_ env: TestEnvironment, _ iso: String) {
        let date = TestEnvironment.date(iso)
        env.store.now = { date }
    }

    @discardableResult
    private func add(_ env: TestEnvironment, _ amount: Double, budget: String = "Household",
                     category: String = "Foods", at iso: String = "2026-11-25T10:00:00Z") -> Expense {
        var draft = env.store.newDraft(now: TestEnvironment.date(iso))
        draft.amount = amount
        draft.category = category
        draft.account = env.store.fetchAccounts().first { $0.accountName == budget } ?? env.store.addAccount(named: budget)
        return env.store.save(draft)!
    }

    private func snapshot(_ env: TestEnvironment, _ name: String) -> SyncSnapshot {
        env.store.syncSnapshot(deviceID: name, ownerName: name)
    }

    private func allExpenses(_ env: TestEnvironment) throws -> [Expense] {
        try env.context.fetch(Expense.fetchRequest()).sorted { $0.amount < $1.amount }
    }

    @Test func newExpensesArriveWithSameIDsBudgetsAndCategories() throws {
        let expense = add(anna, 12.5, budget: "Holiday", category: "Ice cream")

        let stats = ben.store.merge(snapshot(anna, "Anna"))

        #expect(stats == SyncMergeStats(added: 1, updated: 0, deleted: 0))
        let received = try #require(try allExpenses(ben).first)
        #expect(received.uuid == expense.uuid)
        #expect(received.account?.accountName == "Holiday")
        #expect(ben.store.items(.categories).contains { $0.itemName == "Ice cream" })
    }

    @Test func mergingTheSameSnapshotTwiceChangesNothing() throws {
        add(anna, 1)
        add(anna, 2)
        let share = snapshot(anna, "Anna")
        ben.store.merge(share)

        #expect(ben.store.merge(share) == SyncMergeStats())
        #expect(try allExpenses(ben).count == 2)
    }

    @Test func newerChangeWins() throws {
        let expense = add(anna, 10)
        ben.store.merge(snapshot(anna, "Anna"))

        // Ben edits later.
        setClock(ben, "2026-11-25T13:00:00Z")
        let bensCopy = try #require(try allExpenses(ben).first)
        var draft = ben.store.draft(for: bensCopy)
        draft.amount = 11
        ben.store.save(draft, to: bensCopy)

        #expect(anna.store.merge(snapshot(ben, "Ben")).updated == 1)
        #expect(expense.amount == 11)

        // Ben's file is now older than Anna's state: merging it again changes nothing,
        // and Anna's older copy does not overwrite Ben's newer one.
        #expect(anna.store.merge(snapshot(ben, "Ben")) == SyncMergeStats())
        #expect(ben.store.merge(snapshot(anna, "Anna")) == SyncMergeStats())
        #expect(bensCopy.amount == 11)
    }

    @Test func deletionsSpreadAndStaleCopiesDoNotComeBack() throws {
        let expense = add(anna, 10)
        ben.store.merge(snapshot(anna, "Anna"))
        let bensOldShare = snapshot(ben, "Ben")

        setClock(anna, "2026-11-25T14:00:00Z")
        anna.store.delete(expense)

        #expect(ben.store.merge(snapshot(anna, "Anna")).deleted == 1)
        #expect(try allExpenses(ben).isEmpty)
        // Ben's file from before the deletion still lists the expense.
        #expect(anna.store.merge(bensOldShare) == SyncMergeStats())
        #expect(try allExpenses(anna).isEmpty)
    }

    @Test func changeAfterDeletionBringsExpenseBack() throws {
        let expense = add(anna, 10)
        ben.store.merge(snapshot(anna, "Anna"))
        anna.store.delete(expense) // at 12:00

        setClock(ben, "2026-11-25T15:00:00Z")
        let bensCopy = try #require(try allExpenses(ben).first)
        var draft = ben.store.draft(for: bensCopy)
        draft.amount = 20
        ben.store.save(draft, to: bensCopy)

        #expect(anna.store.merge(snapshot(ben, "Ben")).added == 1)
        #expect(try allExpenses(anna).map(\.amount) == [20])
    }

    @Test func onlySharedBudgetsAreSentAndReceived() throws {
        add(anna, 1, budget: "Household")
        add(anna, 2, budget: "Private")
        let everything = snapshot(anna, "Anna")
        #expect(Set(everything.expenses.map(\.budget)) == ["Household", "Private"])

        // Sending: Anna shares only "Household".
        anna.settings.sharedBudgetNames = ["Household"]
        #expect(snapshot(anna, "Anna").expenses.map(\.budget) == ["Household"])

        // Receiving: Ben shares only "Household" and ignores the rest.
        ben.settings.sharedBudgetNames = ["Household"]
        ben.store.merge(everything)
        #expect(try allExpenses(ben).compactMap { $0.account?.accountName } == ["Household"])
    }

    @Test func sameImportOnBothSidesIsNotDuplicated() throws {
        let file = "2026-11-24T08:00:00Z\t3.2\tHousehold\tBaker\t-\t\t\t\t\t\tEUR\t1.0\n"
        try anna.store.importText(file)
        try ben.store.importText(file)

        let stats = ben.store.merge(snapshot(anna, "Anna"))

        #expect(stats.added == 0)
        let annas = try #require(try allExpenses(anna).first)
        let bens = try #require(try allExpenses(ben).first)
        #expect(try allExpenses(ben).count == 1)
        #expect(bens.uuid == annas.uuid)
    }

    @Test func renamedBudgetSpreads() throws {
        add(anna, 10, budget: "Household")
        ben.store.merge(snapshot(anna, "Anna"))

        setClock(anna, "2026-11-25T16:00:00Z")
        let household = try #require(anna.store.fetchAccounts().first { $0.accountName == "Household" })
        anna.store.rename(household, to: "Home")
        ben.store.merge(snapshot(anna, "Anna"))

        #expect(try allExpenses(ben).first?.account?.accountName == "Home")
    }

    @Test func expensesFromBeforeSyncGetIdentities() throws {
        let legacy = anna.makeExpense(5, at: "2026-11-20T10:00:00Z")
        legacy.uuid = nil
        legacy.modifiedAt = nil
        try anna.context.save()

        let share = snapshot(anna, "Anna")

        #expect(legacy.uuid != nil)
        #expect(legacy.modifiedAt == TestEnvironment.date("2026-11-20T10:00:00Z"))
        #expect(share.expenses.map(\.id) == [legacy.uuid])
    }

    @Test func folderWritesOwnFileAndReadsOthers() throws {
        let directory = URL.temporaryDirectory.appending(path: "SyncFolder-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let folder = SyncFolder(url: directory)
        add(anna, 7)

        try folder.write(snapshot(anna, "anna-phone"))
        try folder.write(snapshot(ben, "ben-phone"))
        // A file iCloud has not downloaded yet, and an unrelated file.
        try Data().write(to: directory.appending(path: ".Expensly-carla-phone.json.icloud"))
        try Data("hello".utf8).write(to: directory.appending(path: "notes.txt"))

        let (snapshots, pending) = try folder.readSnapshots(excluding: "ben-phone")

        #expect(snapshots.map(\.deviceID) == ["anna-phone"])
        #expect(snapshots.first?.expenses.count == 1)
        #expect(pending == 1)
    }
}
