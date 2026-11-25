import Foundation

/// Which kind of period the expense list shows.
enum PeriodType: String, CaseIterable, Identifiable, Sendable {
    case week, month, year, all

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .week: "Week"
        case .month: "Month"
        case .year: "Year"
        case .all: "All"
        }
    }

    fileprivate var component: Calendar.Component? {
        switch self {
        case .week: .weekOfYear
        case .month: .month
        case .year: .year
        case .all: nil
        }
    }
}

/// The time range the expense list and the category report show.
///
/// Replaces the old `DateIntervalSelection` class. The range is half-open: `start` is
/// included and `end` (the start of the next period) is not.
struct ExpensePeriod: Equatable, Sendable {
    let type: PeriodType
    /// `nil` for `.all`.
    let range: Range<Date>?

    static func containing(_ date: Date, type: PeriodType, calendar: Calendar = .current) -> ExpensePeriod {
        guard let component = type.component,
              let interval = calendar.dateInterval(of: component, for: date) else {
            return ExpensePeriod(type: .all, range: nil)
        }
        return ExpensePeriod(type: type, range: interval.start..<interval.end)
    }

    func next(calendar: Calendar = .current) -> ExpensePeriod { moved(by: 1, calendar: calendar) }
    func previous(calendar: Calendar = .current) -> ExpensePeriod { moved(by: -1, calendar: calendar) }

    /// The same kind of period, containing `date`.
    func with(type newType: PeriodType, around date: Date, calendar: Calendar = .current) -> ExpensePeriod {
        .containing(date, type: newType, calendar: calendar)
    }

    func contains(_ date: Date) -> Bool {
        range?.contains(date) ?? true
    }

    private func moved(by value: Int, calendar: Calendar) -> ExpensePeriod {
        guard let component = type.component, let range,
              let date = calendar.date(byAdding: component, value: value, to: range.lowerBound) else {
            return self
        }
        return .containing(date, type: type, calendar: calendar)
    }

    /// Text for the period selector, e.g. "24.11.–30.11.26", "November 2026", "2026", "All".
    func title(calendar: Calendar = .current, locale: Locale = .current) -> String {
        guard let range else { return String(localized: "All", locale: locale) }
        let start = range.lowerBound
        switch type {
        case .week:
            let lastDay = calendar.date(byAdding: .day, value: -1, to: range.upperBound) ?? start
            let short = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
                .day(.twoDigits).month(.twoDigits)
            let long = short.year(.twoDigits)
            return "\(start.formatted(short))–\(lastDay.formatted(long))"
        case .month:
            return start.formatted(Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
                .month(.wide).year())
        case .year:
            return start.formatted(Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
                .year())
        case .all:
            return String(localized: "All", locale: locale)
        }
    }
}
