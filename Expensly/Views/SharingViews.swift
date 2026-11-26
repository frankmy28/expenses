import SwiftUI
import UniformTypeIdentifiers

/// Info screen section for sharing budgets through a shared folder.
struct SharingSection: View {
    @Environment(SyncService.self) private var sync
    @Environment(ExpenseStore.self) private var store
    @State private var isChoosingFolder = false
    @State private var isConfirmingStop = false

    var body: some View {
        @Bindable var sync = sync
        Section {
            TextField("Your name", text: $sync.ownerName)
                .textContentType(.name)
            LabeledContent("Shared folder", value: sync.folderName ?? String(localized: "None"))
            Button(sync.isConfigured ? "Choose Another Folder" : "Choose Shared Folder", systemImage: "folder") {
                isChoosingFolder = true
            }
            if sync.isConfigured {
                NavigationLink {
                    SharedBudgetsView()
                } label: {
                    LabeledContent("Shared budgets", value: sharedBudgetsSummary)
                }
                Button {
                    Task { await sync.sync() }
                } label: {
                    HStack {
                        Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                        Spacer()
                        if sync.isSyncing { ProgressView() }
                    }
                }
                .disabled(sync.isSyncing)
                statusText
                Button("Stop Sharing", role: .destructive) { isConfirmingStop = true }
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Sharing")
        } footer: {
            Text("Share a folder in iCloud Drive with your family in the Files app, then choose that folder here on each iPhone. Expensly syncs when it opens and when you tap Sync Now. Budgets are matched by name.")
        }
        .fileImporter(isPresented: $isChoosingFolder, allowedContentTypes: [.folder]) { result in
            if case let .success(url) = result {
                sync.useFolder(url)
                Task { await sync.sync() }
            }
        }
        .confirmationDialog("Stop sharing?", isPresented: $isConfirmingStop, titleVisibility: .visible) {
            Button("Stop Sharing", role: .destructive) { sync.stopSharing() }
        } message: {
            Text("Your expenses stay on this iPhone. Your file in the shared folder is no longer updated.")
        }
    }

    private var sharedBudgetsSummary: String {
        let _ = store.listsVersion
        guard let names = store.settings.sharedBudgetNames else { return String(localized: "All") }
        return String(localized: "\(names.count) of \(store.accounts().count)")
    }

    @ViewBuilder
    private var statusText: some View {
        if let error = sync.lastError {
            Label(error, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
                .font(.footnote)
        } else if let report = sync.lastReport {
            VStack(alignment: .leading, spacing: 2) {
                if report.sources.isEmpty {
                    Text("No files from others yet.")
                } else {
                    Text("Shared with \(report.sources.formatted(.list(type: .and)))")
                }
                Text("\(report.stats.received) received, \(report.stats.deleted) deleted · \(report.date.formatted(date: .omitted, time: .shortened))")
                if report.pending > 0 {
                    Text("\(report.pending) files are still downloading from iCloud. Sync again in a moment.")
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        } else if let date = sync.lastSyncDate {
            Text("Last sync \(date.formatted(.relative(presentation: .named)))")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

/// Picks which budgets are shared. Expenses in other budgets are neither sent nor received.
struct SharedBudgetsView: View {
    @Environment(ExpenseStore.self) private var store
    @Environment(SyncService.self) private var sync

    var body: some View {
        let accounts = store.accounts()
        let _ = store.listsVersion
        List {
            Section {
                ForEach(accounts, id: \.objectID) { account in
                    let name = account.accountName ?? ""
                    Toggle(name, isOn: Binding(
                        get: { store.settings.isShared(budget: name) },
                        set: { setShared(name, $0, all: accounts) }
                    ))
                }
            } footer: {
                Text("Only expenses in shared budgets are sent to and received from the others. New budgets are shared while all budgets are selected.")
            }
        }
        .navigationTitle("Shared budgets")
        .onDisappear { Task { await sync.syncIfConfigured() } }
    }

    private func setShared(_ name: String, _ shared: Bool, all accounts: [Account]) {
        let allNames = Set(accounts.compactMap(\.accountName))
        var names = store.settings.sharedBudgetNames ?? allNames
        if shared { names.insert(name) } else { names.remove(name) }
        store.settings.sharedBudgetNames = names.isSuperset(of: allNames) ? nil : names
        store.listsVersion += 1
    }
}
