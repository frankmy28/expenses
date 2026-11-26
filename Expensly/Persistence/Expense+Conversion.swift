import CoreData

extension Expense {
    /// The amount converted to the app currency.
    ///
    /// `exchangeRate` converts one unit of `currency` into the app currency. Expenses without a
    /// currency (from before version 1.1) or in the app currency are returned unconverted, and so
    /// is an expense whose rate is missing (0).
    func amount(inAppCurrency appCurrency: String) -> Double {
        guard let currency, currency != appCurrency, exchangeRate != 0, !exchangeRate.isNaN else {
            return amount
        }
        return amount * exchangeRate
    }

    /// True when the expense was entered in a currency other than the app currency.
    func isForeignCurrency(appCurrency: String) -> Bool {
        guard let currency, currency.count == 3 else { return false }
        return currency != appCurrency
    }

    var venue: Venue? {
        guard let venueId, let venueName else { return nil }
        return Venue(id: venueId, name: venueName, latitude: venueLat, longitude: venueLng)
    }
}

/// A place assigned to an expense.
struct Venue: Hashable, Identifiable, Codable, Sendable {
    var id: String
    var name: String
    var latitude: Double
    var longitude: Double
}
