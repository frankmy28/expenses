import SwiftUI
import TipKit

@main
struct ExpenslyApp: App {
    @State private var persistence: PersistenceController
    @State private var store: ExpenseStore
    @State private var sync: SyncService

    init() {
        let persistence = PersistenceController()
        let store = ExpenseStore(context: persistence.viewContext)
        _persistence = State(initialValue: persistence)
        _store = State(initialValue: store)
        _sync = State(initialValue: SyncService(store: store))
        if !Self.isRunningTests {
            try? Tips.configure()
        }
    }

    var body: some Scene {
        WindowGroup {
            if let error = persistence.loadError {
                ContentUnavailableView("Your expenses could not be opened",
                                       systemImage: "exclamationmark.triangle",
                                       description: Text(error.localizedDescription))
            } else {
                RootView()
                    .environment(store)
                    .environment(sync)
                    .environment(\.managedObjectContext, persistence.viewContext)
            }
        }
    }

    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}

struct RootView: View {
    @Environment(ExpenseStore.self) private var store
    @Environment(SyncService.self) private var sync
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var store = store
        TabView {
            ExpenseListView()
                .tabItem { Label("Expenses", systemImage: "cart") }
            CategoryReportView()
                .tabItem { Label("Category Report", systemImage: "chart.pie") }
            InfoView()
                .tabItem { Label("Info", systemImage: "info.circle") }
        }
        .task { store.reload() }
        .onChange(of: scenePhase, initial: true) { _, phase in
            // Pick up the others' changes on open, hand ours over when leaving.
            if phase == .active || phase == .background {
                Task { await sync.syncIfConfigured() }
            }
        }
        .alert(item: $store.failure) { failure in
            Alert(title: Text(failure.title), message: Text(failure.message))
        }
    }
}
