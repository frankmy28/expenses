import Foundation
import Testing
@testable import Expensly

struct ExpensePeriodTests {
    let calendar = TestEnvironment.calendar
    let wednesday = TestEnvironment.date("2026-11-25T12:00:00Z")

    @Test func weekStartsOnMondayAndLastsSevenDays() {
        let period = ExpensePeriod.containing(wednesday, type: .week, calendar: calendar)
        #expect(period.range?.lowerBound == TestEnvironment.date("2026-11-23T00:00:00Z"))
        #expect(period.range?.upperBound == TestEnvironment.date("2026-11-30T00:00:00Z"))
    }

    @Test func monthAndYearCoverWholeUnits() {
        let month = ExpensePeriod.containing(wednesday, type: .month, calendar: calendar)
        #expect(month.range == TestEnvironment.date("2026-11-01T00:00:00Z")..<TestEnvironment.date("2026-12-01T00:00:00Z"))
        let year = ExpensePeriod.containing(wednesday, type: .year, calendar: calendar)
        #expect(year.range == TestEnvironment.date("2026-01-01T00:00:00Z")..<TestEnvironment.date("2027-01-01T00:00:00Z"))
    }

    @Test func allHasNoRangeAndContainsEverything() {
        let all = ExpensePeriod.containing(wednesday, type: .all, calendar: calendar)
        #expect(all.range == nil)
        #expect(all.contains(.distantPast))
        #expect(all.next(calendar: calendar) == all)
    }

    @Test func nextAndPreviousMoveByOneUnit() {
        let month = ExpensePeriod.containing(TestEnvironment.date("2026-01-31T10:00:00Z"), type: .month, calendar: calendar)
        let february = month.next(calendar: calendar)
        #expect(february.range == TestEnvironment.date("2026-02-01T00:00:00Z")..<TestEnvironment.date("2026-03-01T00:00:00Z"))
        #expect(february.previous(calendar: calendar) == month)

        let week = ExpensePeriod.containing(wednesday, type: .week, calendar: calendar)
        #expect(week.next(calendar: calendar).range?.lowerBound == TestEnvironment.date("2026-11-30T00:00:00Z"))
    }

    @Test func rangeIsHalfOpen() {
        let week = ExpensePeriod.containing(wednesday, type: .week, calendar: calendar)
        #expect(week.contains(TestEnvironment.date("2026-11-23T00:00:00Z")))
        #expect(week.contains(TestEnvironment.date("2026-11-29T23:59:59Z")))
        #expect(!week.contains(TestEnvironment.date("2026-11-30T00:00:00Z")))
    }

    @Test func titles() {
        let locale = Locale(identifier: "de_DE")
        #expect(ExpensePeriod.containing(wednesday, type: .week, calendar: calendar).title(calendar: calendar, locale: locale) == "23.11.–29.11.26")
        #expect(ExpensePeriod.containing(wednesday, type: .year, calendar: calendar).title(calendar: calendar, locale: locale) == "2026")
    }
}
