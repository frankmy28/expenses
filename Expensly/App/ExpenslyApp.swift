import SwiftUI
import TipKit

@main
struct ExpenslyApp: App {
    @State private var persistence: PersistenceController
    @State private var store: ExpenseStore

    init() {
        let persistence = PersistenceController()
        _persistence = State(initialValue: persistence)
        _store = State(initialValue: ExpenseStore(context: persistence.viewContext))
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
        .alert(item: $store.failure) { failure in
            Alert(title: Text(failure.title), message: Text(failure.message))
        }
    }
}
