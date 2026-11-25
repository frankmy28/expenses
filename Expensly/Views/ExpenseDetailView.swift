import SwiftUI
import TipKit

/// Adds a new expense (`expense == nil`, shown in a sheet) or edits an existing one (pushed).
/// Changes are kept in an `ExpenseDraft` and only written on Save.
struct ExpenseDetailView: View {
    @Environment(ExpenseStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let expense: Expense?

    @State private var draft: ExpenseDraft?
    @State private var amountText = ""
    @State private var rateError: String?
    @State private var rateDate: Date?
    @FocusState private var amountFocused: Bool
    private let currencyTip = CurrencyTip()

    var body: some View {
        Group {
            if let draft = Binding($draft) {
                form(draft)
            } else {
                ProgressView()
            }
        }
        .navigationTitle(expense == nil ? "Add Expense" : "Edit Expense")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    if let draft { store.save(draft, to: expense) }
                    dismiss()
                }
                .disabled(!(draft?.isValid(appCurrency: store.appCurrency) ?? false))
            }
        }
        .onAppear {
            guard draft == nil else { return }
            let initial = expense.map(store.draft(for:)) ?? store.newDraft()
            draft = initial
            amountText = AmountInput.format(initial.amount)
            if expense == nil { amountFocused = true }
        }
    }

    private func form(_ draft: Binding<ExpenseDraft>) -> some View {
        let appCurrency = store.appCurrency
        let isForeign = draft.wrappedValue.currency != appCurrency
        return Form {
            Section {
                HStack {
                    TextField("Amount", text: $amountText)
                        .keyboardType(.numberPad)
                        .font(.largeTitle.weight(.semibold))
                        .monospacedDigit()
                        .focused($amountFocused)
                        .onChange(of: amountText) { _, newValue in
                            let amount = AmountInput.parse(newValue)
                            draft.wrappedValue.amount = amount
                            let formatted = AmountInput.format(amount)
                            if formatted != newValue { amountText = formatted }
                        }
                    Menu {
                        Picker("Currency", selection: draft.currency) {
                            ForEach(Currencies.available, id: \.self) { code in
                                Text("\(code) – \(Currencies.name(for: code))").tag(code)
                            }
                        }
                    } label: {
                        Text(Currencies.symbol(for: draft.wrappedValue.currency))
                            .font(.title2.weight(.semibold))
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .popoverTip(currencyTip)
                }
                if isForeign {
                    conversionInfo(draft.wrappedValue, appCurrency: appCurrency)
                }
            }

            Section {
                DatePicker("Date", selection: draft.date)
                NavigationLink {
                    NamedItemPickerView(list: .categories, selection: draft.category)
                } label: {
                    LabeledContent("Category", value: draft.wrappedValue.category ?? "–")
                }
                NavigationLink {
                    AccountPickerView(selection: draft.account)
                } label: {
                    LabeledContent("Budget", value: draft.wrappedValue.account?.accountName ?? "–")
                }
                NavigationLink {
                    NamedItemPickerView(list: .projects, selection: draft.project)
                } label: {
                    LabeledContent("Project", value: draft.wrappedValue.project ?? "–")
                }
            }

            Section {
                NavigationLink {
                    LocationPickerView(venue: draft.venue)
                } label: {
                    LabeledContent("Location", value: draft.wrappedValue.venue?.name ?? "–")
                }
                TextField("Comment", text: draft.comment, axis: .vertical)
            }
        }
        .task(id: draft.wrappedValue.currency) {
            await updateRate(draft)
        }
    }

    @ViewBuilder
    private func conversionInfo(_ draft: ExpenseDraft, appCurrency: String) -> some View {
        if let rateError {
            Label(rateError, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        } else if draft.exchangeRate > 0 {
            LabeledContent {
                Text(draft.amountInAppCurrency(appCurrency).formattedCurrency(appCurrency))
                    .monospacedDigit()
            } label: {
                Text("\(draft.currency)/\(appCurrency) = \(draft.exchangeRate.formatted(.number.precision(.fractionLength(2...4))))")
                if let rateDate, !Calendar.current.isDateInToday(rateDate) {
                    Text("Rate from \(rateDate.formatted(date: .abbreviated, time: .omitted))")
                }
            }
            .foregroundStyle(.secondary)
        } else {
            HStack {
                ProgressView()
                Text("Loading exchange rate…").foregroundStyle(.secondary)
            }
        }
    }

    /// Fetches a rate when the currency changes. An existing expense keeps the rate it was
    /// saved with as long as its currency is unchanged (the old app replaced it with today's
    /// rate whenever the expense was opened).
    private func updateRate(_ draft: Binding<ExpenseDraft>) async {
        let currency = draft.wrappedValue.currency
        let appCurrency = store.appCurrency
        rateError = nil
        rateDate = nil
        guard currency != appCurrency else {
            draft.wrappedValue.exchangeRate = 1
            return
        }
        if let expense, expense.currency == currency, expense.exchangeRate > 0 {
            draft.wrappedValue.exchangeRate = expense.exchangeRate
            return
        }
        draft.wrappedValue.exchangeRate = 0
        do {
            try await store.rates.lookup(from: currency, to: appCurrency) { rate in
                guard draft.wrappedValue.currency == currency else { return }
                draft.wrappedValue.exchangeRate = rate
                rateDate = store.rates.storedRate(from: currency, to: appCurrency)?.recordDate
            }
        } catch {
            guard !Task.isCancelled else { return }
            rateError = error.localizedDescription
        }
    }
}

/// Cash-register style amount entry: digits fill in from the right ("1", "12" → 0,12, "1250" → 12,50).
enum AmountInput {
    static func parse(_ text: String) -> Double {
        let digits = text.filter(\.isWholeNumber).prefix(12)
        return (Double(String(digits)) ?? 0) / 100
    }

    static func format(_ amount: Double, locale: Locale = .current) -> String {
        guard amount != 0 else { return "" }
        return amount.formatted(.number.precision(.fractionLength(2)).locale(locale))
    }
}
