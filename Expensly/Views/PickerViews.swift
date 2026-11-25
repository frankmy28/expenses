import SwiftUI

/// Picks a category or project. Items can be added with + and removed by swiping.
struct NamedItemPickerView: View {
    @Environment(ExpenseStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let list: NamedItemList
    @Binding var selection: String?

    @State private var isAdding = false
    @State private var newName = ""

    var body: some View {
        let items = store.items(list)
        let _ = store.listsVersion
        List {
            ForEach(items, id: \.objectID) { item in
                Button {
                    selection = item.itemName
                    dismiss()
                } label: {
                    HStack {
                        Text(item.itemName ?? "").foregroundStyle(.primary)
                        Spacer()
                        if item.itemName == selection {
                            Image(systemName: "checkmark").foregroundStyle(.tint)
                        }
                    }
                }
            }
            .onDelete { offsets in
                for index in offsets { store.delete(items[index]) }
            }
        }
        .navigationTitle(Text(list.title))
        .toolbar {
            Button("Add New Item", systemImage: "plus") {
                newName = ""
                isAdding = true
            }
        }
        .alert("Add New Item", isPresented: $isAdding) {
            TextField("Name", text: $newName)
            Button("Cancel", role: .cancel) {}
            Button("Add") {
                if let item = store.addItem(named: newName, to: list) {
                    selection = item.itemName
                }
            }
        } message: {
            Text("Enter Item Name.")
        }
    }
}

/// Picks a budget. Budgets can be added, renamed and deleted.
struct AccountPickerView: View {
    @Environment(ExpenseStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: Account?

    @State private var editing: Account?
    @State private var isAdding = false
    @State private var name = ""
    @State private var deleting: Account?

    var body: some View {
        let accounts = store.accounts()
        let _ = store.listsVersion
        List(accounts, id: \.objectID) { account in
            Button {
                selection = account
                dismiss()
            } label: {
                HStack {
                    Text(account.accountName ?? "").foregroundStyle(.primary)
                    Spacer()
                    if account == selection {
                        Image(systemName: "checkmark").foregroundStyle(.tint)
                    }
                }
            }
            .swipeActions {
                Button("Delete", role: .destructive) { deleting = account }
                Button("Edit") {
                    name = account.accountName ?? ""
                    editing = account
                }
                .tint(.blue)
            }
        }
        .navigationTitle("Budget")
        .toolbar {
            Button("Add New Budget", systemImage: "plus") {
                name = ""
                isAdding = true
            }
        }
        .alert("Add New Budget", isPresented: $isAdding) {
            TextField("Name", text: $name)
            Button("Cancel", role: .cancel) {}
            Button("Add") {
                if let account = store.addAccount(named: name) { selection = account }
            }
        } message: {
            Text("Enter Budget Name.")
        }
        .alert("Edit Budget", isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })) {
            TextField("Name", text: $name)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                if let editing { store.rename(editing, to: name) }
            }
        } message: {
            Text("Enter new budget name.")
        }
        .confirmationDialog("Delete Budget \(deleting?.accountName ?? "")?",
                            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let deleting {
                    if selection == deleting { selection = nil }
                    store.delete(deleting)
                }
            }
        }
    }
}
