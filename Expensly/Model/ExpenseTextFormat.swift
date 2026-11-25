import Foundation

/// The tab-separated export/import format, unchanged from the 2018 app so old exports can
/// still be imported.
///
/// Columns: date (ISO 8601), amount, budget, category, project, comment, venueId, venueName,
/// lat, lng, currency, exchangeRate. Rows with at least 10 columns are accepted; the two
/// currency columns are optional (files from before version 1.1).
enum ExpenseTextFormat {
    struct Row: Equatable {
        var date: Date
        var amount: Double
        var accountName: String
        var category: String
        var project: String
        var comment: String
        var venue: Venue?
        var currency: String
        var exchangeRate: Double
    }

    static func line(for expense: Expense) -> String {
        let venue = expense.venue
        let columns = [
            ISO8601DateFormatter().string(from: expense.date ?? .now),
            String(expense.amount),
            clean(expense.account?.accountName),
            clean(expense.category),
            clean(expense.project),
            clean(expense.comment),
            clean(venue?.id),
            clean(venue?.name),
            venue.map { String($0.latitude) } ?? "",
            venue.map { String($0.longitude) } ?? "",
            clean(expense.currency),
            String(expense.exchangeRate),
        ]
        return columns.joined(separator: "\t")
    }

    static func text(for expenses: [Expense]) -> String {
        expenses.map { line(for: $0) + "\n" }.joined()
    }

    /// Parses an export file. Rows that are too short or have an unreadable date are skipped.
    static func parse(_ text: String, defaultCurrency: String) -> [Row] {
        let dateFormatter = ISO8601DateFormatter()
        return text.components(separatedBy: .newlines).compactMap { line -> Row? in
            let columns = line.components(separatedBy: "\t")
            guard columns.count >= 10, let date = dateFormatter.date(from: columns[0]) else { return nil }
            var venue: Venue?
            if !columns[6].isEmpty {
                venue = Venue(id: columns[6], name: columns[7],
                              latitude: number(columns[8]), longitude: number(columns[9]))
            }
            var currency = defaultCurrency
            var rate = 1.0
            if columns.count >= 12, columns[10].count == 3 {
                currency = columns[10]
                rate = number(columns[11])
            }
            return Row(date: date, amount: number(columns[1]), accountName: columns[2], category: columns[3],
                       project: columns[4], comment: columns[5], venue: venue, currency: currency,
                       exchangeRate: rate)
        }
    }

    private static func number(_ text: String) -> Double {
        (text.trimmingCharacters(in: .whitespaces) as NSString).doubleValue
    }

    /// Tabs and line breaks would break the format, so they become spaces.
    private static func clean(_ text: String?) -> String {
        guard let text else { return "" }
        return text.components(separatedBy: CharacterSet(charactersIn: "\t\r\n")).joined(separator: " ")
    }
}
