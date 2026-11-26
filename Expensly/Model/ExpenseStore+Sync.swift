import CoreData
import Foundation

extension ExpenseStore {
    /// Gives every expense a sync id and change time. Expenses from before model version 1.2
    /// have neither; their change time becomes their date, so any real edit is newer.
    @discardableResult
    func ensureSyncIdentities() -> Bool {
        let request = Expense.fetchRequest()
        request.predicate = NSPredicate(format: "uuid == nil OR modifiedAt == nil")
        guard let missing = try? context.fetch(request), !missing.isEmpty else { return false }
        for expense in missing {
            if expense.uuid == nil { expense.uuid = UUID() }
            if expense.modifiedAt == nil { expense.modifiedAt = expense.date ?? .distantPast }
        }
        return save(String(localized: "Error saving expense record"))
    }

    /// Remembers that an expense was deleted so the deletion reaches the other devices.
    func recordDeletion(of expense: Expense) {
        guard let id = expense.uuid else { return }
        let deletion = DeletedExpense(context: context)
        deletion.uuid = id
        deletion.deletedAt = now()
    }

    /// This device's share: all expenses in shared budgets plus all recorded deletions.
    func syncSnapshot(deviceID: String, ownerName: String) -> SyncSnapshot {
        ensureSyncIdentities()
        let expenses = ((try? context.fetch(Expense.fetchRequest())) ?? [])
            .filter { settings.isShared(budget: $0.account?.accountName) }
            .compactMap(SyncExpense.init(expense:))
            .sorted { $0.date < $1.date }
        let deletions = fetchDeletions().values
            .map { SyncDeletion(id: $0.uuid!, deletedAt: $0.deletedAt!) }
            .sorted { $0.deletedAt < $1.deletedAt }
        return SyncSnapshot(deviceID: deviceID, ownerName: ownerName, writtenAt: now(),
                            expenses: expenses, deletions: deletions)
    }

    /// Merges another device's share into this store.
    ///
    /// - Expenses in budgets this device does not share are ignored.
    /// - The newer change wins; a deletion wins over changes made before it.
    /// - An unknown expense that matches a local one without a counterpart on the other side
    ///   (same date, amount, currency, category and budget) is taken as the same expense. This
    ///   avoids duplicates when both sides imported the same export file before sharing.
    @discardableResult
    func merge(_ snapshot: SyncSnapshot) -> SyncMergeStats {
        ensureSyncIdentities()
        var stats = SyncMergeStats()
        let all = (try? context.fetch(Expense.fetchRequest())) ?? []
        var byID = Dictionary(all.compactMap { e in e.uuid.map { ($0, e) } }, uniquingKeysWith: { a, _ in a })
        var deletions = fetchDeletions()

        for remote in snapshot.deletions {
            if let local = byID[remote.id], (local.modifiedAt ?? .distantPast) <= remote.deletedAt {
                context.delete(local)
                byID[remote.id] = nil
                stats.deleted += 1
            }
            if let known = deletions[remote.id] {
                if let date = known.deletedAt, date < remote.deletedAt { known.deletedAt = remote.deletedAt }
            } else {
                let deletion = DeletedExpense(context: context)
                deletion.uuid = remote.id
                deletion.deletedAt = remote.deletedAt
                deletions[remote.id] = deletion
            }
        }

        let remoteIDs = Set(snapshot.expenses.map(\.id))
        var unmatched = all.filter { e in !e.isDeleted && e.uuid.map { !remoteIDs.contains($0) } ?? true }
        var budgets = Dictionary(fetchAccounts().compactMap { a in a.accountName.map { ($0, a) } },
                                 uniquingKeysWith: { a, _ in a })
        var categories = Set(items(.categories).compactMap(\.itemName))
        var projects = Set(items(.projects).compactMap(\.itemName))

        for remote in snapshot.expenses where settings.isShared(budget: remote.budget) {
            if let deletion = deletions[remote.id], let deletedAt = deletion.deletedAt {
                guard remote.modifiedAt > deletedAt else { continue }
                // Changed again after it was deleted somewhere: it comes back.
                context.delete(deletion)
                deletions[remote.id] = nil
            }
            let local: Expense
            if let existing = byID[remote.id] {
                guard (existing.modifiedAt ?? .distantPast) < remote.modifiedAt else { continue }
                local = existing
                stats.updated += 1
            } else if let index = unmatched.firstIndex(where: { remote.matches($0) }) {
                local = unmatched.remove(at: index)
                local.uuid = remote.id
                byID[remote.id] = local
                guard (local.modifiedAt ?? .distantPast) < remote.modifiedAt else { continue }
                stats.updated += 1
            } else {
                local = Expense(context: context)
                byID[remote.id] = local
                stats.added += 1
            }
            let account = budgets[remote.budget] ?? {
                let account = makeAccount(named: remote.budget)
                budgets[remote.budget] = account
                return account
            }()
            remote.apply(to: local, account: account)
            if categories.insert(remote.category).inserted { makeItem(remote.category, in: .categories) }
            if projects.insert(remote.project).inserted { makeItem(remote.project, in: .projects) }
        }

        save(String(localized: "Error saving expense record"))
        if stats != SyncMergeStats() {
            listsVersion += 1
            reload()
        }
        return stats
    }

    private func fetchDeletions() -> [UUID: DeletedExpense] {
        let all = (try? context.fetch(DeletedExpense.fetchRequest())) ?? []
        return Dictionary(all.compactMap { d in d.uuid.map { ($0, d) } }, uniquingKeysWith: { a, _ in a })
    }
}

extension SyncExpense {
    init?(expense: Expense) {
        guard let id = expense.uuid, let date = expense.date, let budget = expense.account?.accountName else {
            return nil
        }
        self.init(id: id,
                  modifiedAt: expense.modifiedAt ?? date,
                  date: date,
                  amount: expense.amount,
                  currency: expense.currency ?? "",
                  exchangeRate: expense.exchangeRate,
                  budget: budget,
                  category: expense.category ?? "",
                  project: expense.project ?? "",
                  comment: expense.comment,
                  venue: expense.venue)
    }

    func apply(to expense: Expense, account: Account) {
        expense.uuid = id
        expense.modifiedAt = modifiedAt
        expense.date = date
        expense.amount = amount
        expense.currency = currency
        expense.exchangeRate = exchangeRate
        expense.account = account
        expense.category = category
        expense.project = project
        expense.comment = comment
        expense.venueId = venue?.id
        expense.venueName = venue?.name
        expense.venueLat = venue?.latitude ?? 0
        expense.venueLng = venue?.longitude ?? 0
    }

    /// Same expense entered or imported separately on two devices. Dates are compared to the
    /// second because the export format drops fractions of a second.
    func matches(_ expense: Expense) -> Bool {
        guard let localDate = expense.date else { return false }
        return abs(localDate.timeIntervalSince(date)) < 1
            && expense.amount == amount
            && (expense.currency ?? "") == currency
            && (expense.category ?? "") == category
            && expense.account?.accountName == budget
    }
}
