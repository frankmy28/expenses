import CoreData
import Foundation

enum ExchangeRateError: LocalizedError {
    case unavailable(String, String)

    var errorDescription: String? {
        switch self {
        case let .unavailable(base, terms):
            String(localized: "No exchange rate available for \(base)/\(terms).")
        }
    }
}

/// Looks up exchange rates in three tiers: an in-memory cache, the newest active
/// `ExchangeRate` row in Core Data, then floatrates.com. A rate counts as current when it
/// was recorded today.
@MainActor
final class ExchangeRateService {
    typealias Fetcher = @Sendable (URL) async throws -> Data

    private let context: NSManagedObjectContext
    private let fetch: Fetcher
    private var cache: [String: ExchangeRate] = [:]
    private let calendar: Calendar

    init(context: NSManagedObjectContext, calendar: Calendar = .current, fetch: Fetcher? = nil) {
        self.context = context
        self.calendar = calendar
        self.fetch = fetch ?? { url in
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                throw URLError(.badServerResponse)
            }
            return data
        }
    }

    /// Calls `update` with a stored rate right away (if there is one), and again with a
    /// fresh rate when the stored one is not from today. Throws only when no rate at all
    /// could be found.
    func lookup(from base: String, to terms: String, update: (Double) -> Void) async throws {
        let stored = storedRate(from: base, to: terms)
        if let stored {
            update(stored.rate)
            if let date = stored.recordDate, calendar.isDateInToday(date) { return }
        }
        do {
            let rates = try await refreshRates(to: terms)
            if let rate = rates[base] {
                update(rate)
            } else if stored == nil {
                throw ExchangeRateError.unavailable(base, terms)
            }
        } catch {
            // Offline or the service failed: a stored rate, even an old one, is good enough.
            if stored == nil { throw error }
        }
    }

    func storedRate(from base: String, to terms: String) -> ExchangeRate? {
        if let cached = cache[base + terms] { return cached }
        let request = ExchangeRate.fetchRequest()
        request.predicate = NSPredicate(format: "baseCcy == %@ AND termsCcy == %@ AND active == YES", base, terms)
        request.sortDescriptors = [NSSortDescriptor(key: "recordDate", ascending: false)]
        request.fetchLimit = 1
        let rate = try? context.fetch(request).first
        if let rate { cache[base + terms] = rate }
        return rate
    }

    /// Downloads today's rates into `terms` and stores them, replacing the active rows.
    /// Returns rates keyed by base currency: one unit of the key in `terms`.
    @discardableResult
    func refreshRates(to terms: String) async throws -> [String: Double] {
        let url = URL(string: "https://www.floatrates.com/daily/\(terms.lowercased()).json")!
        let rates = try Self.parseFloatRates(try await fetch(url))

        let request = ExchangeRate.fetchRequest()
        request.predicate = NSPredicate(format: "termsCcy == %@ AND active == YES", terms)
        for old in try context.fetch(request) { old.active = false }

        let today = calendar.startOfDay(for: .now)
        for (base, value) in rates {
            let rate = ExchangeRate(context: context)
            rate.baseCcy = base
            rate.termsCcy = terms
            rate.rate = value
            rate.active = true
            rate.recordDate = today
            cache[base + terms] = rate
        }
        try context.save()
        return rates
    }

    func clearAll() throws {
        cache.removeAll()
        for rate in try context.fetch(ExchangeRate.fetchRequest()) {
            context.delete(rate)
        }
        try context.save()
    }

    /// floatrates.com publishes, per currency X, how many X one unit of the requested currency
    /// buys (`rate`). We store the inverse: what one X costs in the requested currency.
    /// The service has sent `rate` both as a number and as a string, so both are accepted.
    nonisolated static func parseFloatRates(_ data: Data) throws -> [String: Double] {
        struct Entry: Decodable {
            let code: String
            let rate: Double

            enum CodingKeys: String, CodingKey { case code, rate }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                code = try container.decode(String.self, forKey: .code)
                if let number = try? container.decode(Double.self, forKey: .rate) {
                    rate = number
                } else {
                    let text = try container.decode(String.self, forKey: .rate)
                    guard let number = Double(text) else {
                        throw DecodingError.dataCorruptedError(forKey: .rate, in: container,
                                                               debugDescription: "Not a number: \(text)")
                    }
                    rate = number
                }
            }
        }
        let entries = try JSONDecoder().decode([String: Entry].self, from: data)
        var result: [String: Double] = [:]
        for entry in entries.values where entry.rate > 0 {
            result[entry.code.uppercased()] = 1.0 / entry.rate
        }
        return result
    }
}
