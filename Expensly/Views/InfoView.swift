import SwiftUI
import TipKit
import UniformTypeIdentifiers

struct InfoView: View {
    @Environment(ExpenseStore.self) private var store
    @Environment(SyncService.self) private var sync
    @State private var isImporting = false
    @State private var isConfirmingDelete = false
    @State private var message: (title: String, text: String)?
    private let importTip = ImportTip()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 16) {
                        Image(systemName: "cart.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.white)
                            .frame(width: 64, height: 64)
                            .background(.tint, in: RoundedRectangle(cornerRadius: 14))
                        VStack(alignment: .leading) {
                            Text("Expensly").font(.title2.weight(.bold))
                            Text("Version \(Self.version) (\(Self.build))")
                                .foregroundStyle(.secondary)
                        }
                    }
                    LabeledContent("Currency", value: "\(store.appCurrency) – \(Currencies.name(for: store.appCurrency))")
                }

                SharingSection()

                Section("Data") {
                    Button("Import Expenses", systemImage: "square.and.arrow.down") {
                        importTip.invalidate(reason: .actionPerformed)
                        isImporting = true
                    }
                    .popoverTip(importTip)
                    Button("Reset Exchange Rates", systemImage: "arrow.triangle.2.circlepath") {
                        do {
                            try store.rates.clearAll()
                            message = (String(localized: "Exchange rates reset"),
                                       String(localized: "Rates are downloaded again the next time they are needed."))
                        } catch {
                            message = (String(localized: "Error"), error.localizedDescription)
                        }
                    }
                    Button("Delete All Expenses", systemImage: "trash", role: .destructive) {
                        isConfirmingDelete = true
                    }
                    .foregroundStyle(.red)
                }

                Section {
                    Link(destination: Self.homepage) {
                        Label("Help and Homepage", systemImage: "questionmark.circle")
                    }
                }
            }
            .navigationTitle("Info")
            .fileImporter(isPresented: $isImporting,
                          allowedContentTypes: [.plainText, .tabSeparatedText, .text]) { result in
                handleImport(result)
            }
            .confirmationDialog("Delete all Expenses?", isPresented: $isConfirmingDelete,
                                titleVisibility: .visible) {
                Button("Delete All Expenses", role: .destructive) { store.deleteAllExpenses() }
            } message: {
                if sync.isConfigured {
                    Text("This cannot be undone. Expenses in shared budgets are also deleted for the others at the next sync.")
                } else {
                    Text("This cannot be undone.")
                }
            }
            .alert(message?.title ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK") {}
            } message: {
                Text(message?.text ?? "")
            }
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case let .success(url):
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            do {
                let text = try String(contentsOf: url, encoding: .utf8)
                let count = try store.importText(text)
                message = (String(localized: "Import succesful"),
                           String(localized: "Imported \(count) expenses from \(url.lastPathComponent)"))
            } catch {
                message = (String(localized: "Error importing Expenses"),
                           String(localized: "Importing from \(url.lastPathComponent) failed."))
            }
        case let .failure(error):
            message = (String(localized: "Error importing Expenses"), error.localizedDescription)
        }
    }

    private static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    private static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
    }

    private static var homepage: URL {
        URL(string: String(localized: "HomepageUrl"))!
    }
}
