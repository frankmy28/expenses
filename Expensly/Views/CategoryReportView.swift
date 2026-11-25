import Charts
import SwiftUI

/// Totals per category for the selected period.
struct CategoryReportView: View {
    @Environment(ExpenseStore.self) private var store

    var body: some View {
        NavigationStack {
            List {
                if !store.byCategory.isEmpty {
                    Section {
                        Chart(store.byCategory) { group in
                            SectorMark(angle: .value("Amount", max(group.total, 0)),
                                       innerRadius: .ratio(0.55),
                                       angularInset: 1.5)
                                .foregroundStyle(by: .value("Category", group.key))
                                .cornerRadius(4)
                        }
                        .chartLegend(position: .bottom, alignment: .center)
                        .frame(height: 260)
                        .padding(.vertical, 8)
                    }
                    Section {
                        ForEach(store.byCategory) { group in
                            LabeledContent {
                                Text(group.total.formattedCurrency(store.appCurrency)).monospacedDigit()
                            } label: {
                                Text(group.key)
                                Text("\(group.expenses.count) expenses")
                            }
                        }
                        LabeledContent {
                            Text(store.total.formattedCurrency(store.appCurrency)).monospacedDigit()
                        } label: {
                            Text("Total")
                        }
                        .font(.headline)
                    }
                }
            }
            .overlay {
                if store.byCategory.isEmpty {
                    ContentUnavailableView("No Expenses", systemImage: "chart.pie",
                                           description: Text("There are no expenses in this period."))
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                PeriodBar()
            }
            .navigationTitle("Expenses by Category")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
