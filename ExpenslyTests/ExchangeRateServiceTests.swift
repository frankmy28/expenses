import CoreData
import Foundation
import Testing
@testable import Expensly

/// Counts calls to the fake floatrates.com fetcher.
final class FetchCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    var count: Int { lock.withLock { value } }
    func increment() { lock.withLock { value += 1 } }
}

@MainActor
struct ExchangeRateServiceTests {
    /// Shaped like https://www.floatrates.com/daily/eur.json, which now sends rates as strings.
    nonisolated static let eurRates = Data("""
    {"usd":{"code":"USD","alphaCode":"USD","rate":"1.25","inverseRate":"0.8"},
     "gbp":{"code":"GBP","rate":0.8,"inverseRate":1.25}}
    """.utf8)

    @Test func parsesStringAndNumberRatesAndInvertsThem() throws {
        let rates = try ExchangeRateService.parseFloatRates(Self.eurRates)
        #expect(rates == ["USD": 0.8, "GBP": 1.25])
    }

    @Test func downloadsStoresAndThenReusesTodaysRate() async throws {
        let counter = FetchCounter()
        let env = TestEnvironment { url in
            #expect(url.absoluteString == "https://www.floatrates.com/daily/eur.json")
            counter.increment()
            return Self.eurRates
        }
        var updates: [Double] = []

        try await env.store.rates.lookup(from: "USD", to: "EUR") { updates.append($0) }
        try await env.store.rates.lookup(from: "GBP", to: "EUR") { updates.append($0) }

        #expect(updates == [0.8, 1.25])
        #expect(counter.count == 1)
        #expect(try env.context.count(for: ExchangeRate.fetchRequest()) == 2)
    }

    @Test func staleRateIsShownFirstThenReplaced() async throws {
        let env = TestEnvironment { _ in Self.eurRates }
        let old = ExchangeRate(context: env.context)
        old.baseCcy = "USD"
        old.termsCcy = "EUR"
        old.rate = 0.7
        old.active = true
        old.recordDate = TestEnvironment.date("2020-01-01T00:00:00Z")
        try env.context.save()
        var updates: [Double] = []

        try await env.store.rates.lookup(from: "USD", to: "EUR") { updates.append($0) }

        #expect(updates == [0.7, 0.8])
        #expect(!old.active)
        #expect(env.store.rates.storedRate(from: "USD", to: "EUR")?.rate == 0.8)
    }

    @Test func offlineFallsBackToStoredRate() async throws {
        let env = TestEnvironment() // fetcher fails
        let old = ExchangeRate(context: env.context)
        old.baseCcy = "USD"
        old.termsCcy = "EUR"
        old.rate = 0.7
        old.active = true
        old.recordDate = TestEnvironment.date("2020-01-01T00:00:00Z")
        try env.context.save()
        var updates: [Double] = []

        try await env.store.rates.lookup(from: "USD", to: "EUR") { updates.append($0) }

        #expect(updates == [0.7])
    }

    @Test func throwsWhenNoRateExists() async {
        let env = TestEnvironment { _ in Self.eurRates }
        await #expect(throws: ExchangeRateError.self) {
            try await env.store.rates.lookup(from: "JPY", to: "EUR") { _ in }
        }
    }

    @Test func clearAllRemovesRates() async throws {
        let env = TestEnvironment { _ in Self.eurRates }
        try await env.store.rates.refreshRates(to: "EUR")
        try env.store.rates.clearAll()
        #expect(try env.context.count(for: ExchangeRate.fetchRequest()) == 0)
        #expect(env.store.rates.storedRate(from: "USD", to: "EUR") == nil)
    }
}
