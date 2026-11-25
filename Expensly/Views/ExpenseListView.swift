import CoreTransferable
import SwiftUI
import TipKit
import UniformTypeIdentifiers

struct ExpenseListView: View {
    @Environment(ExpenseStore.self) private var store
    @State private var isAdding = false
    private let addTip = AddExpenseTip()
    private let shareTip = ShareTip()

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.byDay) { group in
                    Section {
                        ForEach(group.expenses, id: \.objectID) { expense in
                            NavigationLink(value: expense) {
                                ExpenseRow(expense: expense, appCurrency: store.appCurrency)
                            }
                        }
                        .onDelete { offsets in
                            for index in offsets { store.delete(group.expenses[index]) }
                        }
                    } header: {
                        HStack {
                            Text(group.key.formatted(.dateTime.weekday(.abbreviated).day().month().year()))
                            Spacer()
                            Text(group.total.formattedCurrency(store.appCurrency)).monospacedDigit()
                        }
                    }
                }
            }
            .overlay {
                if store.byDay.isEmpty {
                    ContentUnavailableView {
                        Label("No Expenses", systemImage: "cart")
                    } description: {
                        Text("There are no expenses in this period.")
                    } actions: {
                        Button("Add Expense") { isAdding = true }
                    }
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                PeriodBar()
            }
            .refreshable { store.reload() }
            .navigationTitle("Expensly")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Expense.self) { expense in
                ExpenseDetailView(expense: expense)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: ExpenseExport(text: store.exportText()),
                              preview: SharePreview(ExpenseExport.fileName()))
                        .disabled(store.expenses.isEmpty)
                        .popoverTip(shareTip)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add Expense", systemImage: "plus") {
                        addTip.invalidate(reason: .actionPerformed)
                        isAdding = true
                    }
                    .popoverTip(addTip)
                }
            }
            .sheet(isPresented: $isAdding) {
                NavigationStack {
                    ExpenseDetailView(expense: nil)
                }
            }
        }
    }
}

struct ExpenseRow: View {
    @ObservedObject var expense: Expense
    let appCurrency: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(expense.category ?? "")
                    .font(.headline)
                if !detail.isEmpty {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(expense.amount(inAppCurrency: appCurrency).formattedCurrency(appCurrency))
                    .font(.headline)
                    .monospacedDigit()
                Text(expense.account?.accountName ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Venue or comment, plus the original amount for foreign-currency expenses.
    private var detail: String {
        var parts: [String] = []
        if let name = expense.venueName, !name.isEmpty {
            parts.append(name)
        } else if let comment = expense.comment, !comment.isEmpty {
            parts.append(comment)
        }
        if expense.isForeignCurrency(appCurrency: appCurrency), let currency = expense.currency {
            parts.append(expense.amount.formattedCurrency(currency))
        }
        return parts.joined(separator: " · ")
    }
}

/// The export file for the share sheet. Its contents are produced when the user shares.
struct ExpenseExport: Transferable {
    let text: String

    static func fileName(date: Date = .now) -> String {
        let stamp = date.formatted(.verbatim("\(year: .defaultDigits)\(month: .twoDigits)\(day: .twoDigits) \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased))\(minute: .twoDigits)\(second: .twoDigits)",
                                             timeZone: .current, calendar: .current))
        return "Expenses \(stamp).txt"
    }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .plainText) { export in
            let url = URL.temporaryDirectory.appending(path: fileName())
            try export.text.write(to: url, atomically: true, encoding: .utf8)
            return SentTransferredFile(url)
        }
    }
}
