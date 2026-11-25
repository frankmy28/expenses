import Foundation

/// The values being edited on the expense screen.
///
/// The old app edited the managed object in place and called `context.reset()` on cancel,
/// which also threw away any other unsaved change. A draft keeps edits out of Core Data
/// until the user taps Save.
struct ExpenseDraft: Equatable {
    var date: Date
    /// In `currency`.
    var amount: Double
    var currency: String
    /// One unit of `currency` in the app currency. 0 while a foreign rate is still unknown.
    var exchangeRate: Double
    var category: String?
    var project: String?
    var account: Account?
    var comment: String
    var venue: Venue?

    func amountInAppCurrency(_ appCurrency: String) -> Double {
        currency == appCurrency ? amount : amount * exchangeRate
    }

    func isValid(appCurrency: String) -> Bool {
        amount != 0 && category != nil && project != nil && account != nil
            && (currency == appCurrency || exchangeRate > 0)
    }
}

/// Seed values for budgets, categories and projects, from the localized `DefaultValues.plist`.
enum DefaultValues {
    static func load(_ key: String, bundle: Bundle = .main) -> [String] {
        guard let url = bundle.url(forResource: "DefaultValues", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: [String]] else {
            return []
        }
        return plist[key] ?? []
    }
}

/// Categories and projects are both `NamedItem` rows, told apart by `listName`.
enum NamedItemList: String, Sendable {
    case categories
    case projects

    var title: LocalizedStringResource {
        switch self {
        case .categories: "Category"
        case .projects: "Project"
        }
    }
}
