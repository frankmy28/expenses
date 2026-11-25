import SwiftUI
import TipKit

// First-run hints. They replace the coach marks of the `Instructions` pod.

struct AddExpenseTip: Tip {
    var title: Text { Text("Add an expense") }
    var message: Text? { Text("Tap + to record a new expense. Tap an expense to edit it, swipe it to delete it.") }
    var image: Image? { Image(systemName: "plus.circle") }
}

struct PeriodTip: Tip {
    var title: Text { Text("Choose the period") }
    var message: Text? { Text("Tap the date to show a week, month, year or all expenses. Use the arrows or swipe the bar to move back and forward in time.") }
    var image: Image? { Image(systemName: "calendar") }
}

struct ShareTip: Tip {
    var title: Text { Text("Export") }
    var message: Text? { Text("Share the expenses of the shown period as a tab-separated text file.") }
    var image: Image? { Image(systemName: "square.and.arrow.up") }
}

struct CurrencyTip: Tip {
    var title: Text { Text("Foreign currency") }
    var message: Text? { Text("Paid in another currency? Pick it here and the amount is converted with today's exchange rate.") }
    var image: Image? { Image(systemName: "dollarsign.arrow.circlepath") }
}

struct ImportTip: Tip {
    var title: Text { Text("Import") }
    var message: Text? { Text("Import a file exported from Expensly, for example from another device.") }
    var image: Image? { Image(systemName: "square.and.arrow.down") }
}
