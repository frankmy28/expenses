import Foundation

/// A section of expenses with its total in the app currency.
struct ExpenseGroup<Key: Hashable>: Identifiable {
    let key: Key
    let expenses: [Expense]
    let total: Double

    var id: Key { key }
}

/// Builds the sections for the expense list and the category report.
/// Replaces the old `GroupedExpenseModel`.
enum ExpenseGrouping {
    /// One group per day, newest day first. Expenses within a day are newest first.
    static func byDay(_ expenses: [Expense], appCurrency: String, calendar: Calendar = .current) -> [ExpenseGroup<Date>] {
        group(expenses, appCurrency: appCurrency) { expense in
            calendar.startOfDay(for: expense.date ?? .distantPast)
        }
        .sorted { $0.key > $1.key }
    }

    /// One group per category, sorted by name.
    static func byCategory(_ expenses: [Expense], appCurrency: String) -> [ExpenseGroup<String>] {
        group(expenses, appCurrency: appCurrency) { $0.category ?? "" }
            .sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
    }

    static func total(_ expenses: [Expense], appCurrency: String) -> Double {
        expenses.reduce(0) { $0 + $1.amount(inAppCurrency: appCurrency) }
    }

    private static func group<Key: Hashable>(_ expenses: [Expense], appCurrency: String, key: (Expense) -> Key) -> [ExpenseGroup<Key>] {
        Dictionary(grouping: expenses, by: key).map { key, members in
            let sorted = members.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
            return ExpenseGroup(key: key, expenses: sorted, total: total(sorted, appCurrency: appCurrency))
        }
    }
}
