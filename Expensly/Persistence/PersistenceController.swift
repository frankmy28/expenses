import CoreData

/// Owns the Core Data stack.
///
/// The container name ("Expenses") and the model name (`Expenses.xcdatamodeld`) are the
/// same as in the 2018 UIKit app. Together with the unchanged bundle identifier this makes
/// the new app open the existing `Application Support/Expenses.sqlite` store on upgrade.
@MainActor
final class PersistenceController {
    static let modelName = "Expenses"

    /// One model instance for the whole process. Loading the model more than once (for example
    /// one in-memory container per test) makes Core Data warn that several entity descriptions
    /// claim the same class.
    static let model: NSManagedObjectModel = {
        let bundle = Bundle(for: PersistenceController.self)
        guard let url = bundle.url(forResource: modelName, withExtension: "momd"),
              let model = NSManagedObjectModel(contentsOf: url) else {
            fatalError("Core Data model \(modelName).momd is missing from the app bundle")
        }
        return model
    }()

    let container: NSPersistentContainer
    private(set) var loadError: Error?

    var viewContext: NSManagedObjectContext { container.viewContext }

    /// - Parameters:
    ///   - inMemory: Use a throwaway store (tests, previews).
    ///   - storeURL: Open the SQLite store at this URL instead of the default location.
    init(inMemory: Bool = false, storeURL: URL? = nil) {
        container = NSPersistentContainer(name: Self.modelName, managedObjectModel: Self.model)
        if let description = container.persistentStoreDescriptions.first {
            if inMemory {
                description.url = URL(fileURLWithPath: "/dev/null")
            } else if let storeURL {
                description.url = storeURL
            }
            // Older stores (model version "Expenses") migrate to "Expenses 1.1" automatically.
            description.shouldMigrateStoreAutomatically = true
            description.shouldInferMappingModelAutomatically = true
        }
        var error: Error?
        container.loadPersistentStores { _, loadError in
            error = loadError
        }
        loadError = error
        container.viewContext.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
    }

    static func preview() -> PersistenceController {
        PersistenceController(inMemory: true)
    }
}
