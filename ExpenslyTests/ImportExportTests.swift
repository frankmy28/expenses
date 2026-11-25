import CoreData
import Foundation
import Testing
@testable import Expensly

@MainActor
struct ImportExportTests {
    @Test func exportLineHasTheTwelveColumnsOfTheOldFormat() {
        let env = TestEnvironment()
        let expense = env.makeExpense(12.5, at: "2026-11-25T10:30:00Z", category: "Restaurant", currency: "USD", rate: 0.9)
        expense.comment = "Lunch\twith\nteam"
        expense.venueId = "v1"
        expense.venueName = "Café"
        expense.venueLat = 52.5
        expense.venueLng = 13.25

        let line = ExpenseTextFormat.line(for: expense)

        #expect(line == "2026-11-25T10:30:00Z\t12.5\tHousehold\tRestaurant\t-\tLunch with team\tv1\tCafé\t52.5\t13.25\tUSD\t0.9")
    }

    @Test func venueCoordinatesAreEmptyWithoutVenue() {
        let env = TestEnvironment()
        let columns = ExpenseTextFormat.line(for: env.makeExpense(1, at: "2026-11-25T10:30:00Z")).components(separatedBy: "\t")
        #expect(columns.count == 12)
        #expect(columns[6...9].allSatisfy { $0.isEmpty })
    }

    @Test func parsesOldTenColumnFilesWithDefaultCurrency() {
        let text = "2018-05-01T08:00:00Z\t3.2\tHaushalt\tBäcker\t-\t\t\t\t\t\r\n"
        let rows = ExpenseTextFormat.parse(text, defaultCurrency: "EUR")
        #expect(rows.count == 1)
        #expect(rows[0].amount == 3.2)
        #expect(rows[0].accountName == "Haushalt")
        #expect(rows[0].currency == "EUR")
        #expect(rows[0].exchangeRate == 1)
        #expect(rows[0].venue == nil)
    }

    @Test func skipsShortRowsAndBadDates() {
        let text = """
        not a date\t1\tA\tB\tC\t\t\t\t\t
        2018-05-01T08:00:00Z\t1\tA
        2018-05-01T08:00:00Z\t1\tA\tB\tC\tD\tv\tVenue\t1.5\t2.5\tGBP\t1.1
        """
        let rows = ExpenseTextFormat.parse(text, defaultCurrency: "EUR")
        #expect(rows.count == 1)
        #expect(rows[0].venue == Venue(id: "v", name: "Venue", latitude: 1.5, longitude: 2.5))
        #expect(rows[0].currency == "GBP")
        #expect(rows[0].exchangeRate == 1.1)
    }

    @Test func roundTripsThroughExportAndImport() throws {
        let source = TestEnvironment()
        source.makeExpense(10, at: "2026-11-24T10:00:00Z", category: "Foods")
        source.makeExpense(20, at: "2026-11-25T10:00:00Z", category: "Car", currency: "USD", rate: 0.8,
                           account: source.makeAccount("Travel"))
        try source.context.save()
        source.store.reload()
        let text = source.store.exportText()

        let target = TestEnvironment()
        let count = try target.store.importText(text)

        #expect(count == 2)
        #expect(target.store.total == 26)
        #expect(Set(target.store.accounts().compactMap(\.accountName)) == ["Household", "Travel"])
        #expect(target.store.exportText() == text)
    }
}
