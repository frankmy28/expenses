import Foundation

/// User preferences in UserDefaults. Uses the same keys as the old `SystemConfig`, so the
/// app currency and the last-used category, project and budget survive the upgrade.
struct AppSettings {
    private enum Key {
        static let currencyCode = "CurrencyCode"
        static let currencySymbol = "CurrencySymbol"
        static let lastCategory = "LastCategory"
        static let lastProject = "LastProject"
        static let lastAccount = "LastAccount"
    }

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The currency totals are shown in. Defaults to the locale's currency and is then kept,
    /// so changing the device region does not silently change the meaning of stored amounts.
    var appCurrencyCode: String {
        if let code = defaults.string(forKey: Key.currencyCode) { return code }
        let code = Locale.current.currency?.identifier ?? "EUR"
        defaults.set(code, forKey: Key.currencyCode)
        return code
    }

    var appCurrencySymbol: String {
        if let symbol = defaults.string(forKey: Key.currencySymbol) { return symbol }
        let symbol = Currencies.symbol(for: appCurrencyCode)
        defaults.set(symbol, forKey: Key.currencySymbol)
        return symbol
    }

    var lastCategory: String? {
        get { defaults.string(forKey: Key.lastCategory) }
        nonmutating set { defaults.set(newValue, forKey: Key.lastCategory) }
    }

    var lastProject: String? {
        get { defaults.string(forKey: Key.lastProject) }
        nonmutating set { defaults.set(newValue, forKey: Key.lastProject) }
    }

    var lastAccount: String? {
        get { defaults.string(forKey: Key.lastAccount) }
        nonmutating set { defaults.set(newValue, forKey: Key.lastAccount) }
    }

    // MARK: - Sharing through a shared folder

    private enum SyncKey {
        static let folderBookmark = "SyncFolderBookmark"
        static let sharedBudgets = "SyncSharedBudgets"
        static let deviceID = "SyncDeviceID"
        static let ownerName = "SyncOwnerName"
        static let lastSync = "SyncLastDate"
    }

    /// Security-scoped bookmark of the folder chosen for sharing.
    var syncFolderBookmark: Data? {
        get { defaults.data(forKey: SyncKey.folderBookmark) }
        nonmutating set { defaults.set(newValue, forKey: SyncKey.folderBookmark) }
    }

    /// Budget names that are shared. `nil` means all budgets.
    var sharedBudgetNames: Set<String>? {
        get { (defaults.stringArray(forKey: SyncKey.sharedBudgets)).map(Set.init) }
        nonmutating set { defaults.set(newValue.map { Array($0).sorted() }, forKey: SyncKey.sharedBudgets) }
    }

    func isShared(budget name: String?) -> Bool {
        guard let name else { return false }
        return sharedBudgetNames?.contains(name) ?? true
    }

    /// Identifies this installation; its sync file is named after it.
    var syncDeviceID: String {
        if let id = defaults.string(forKey: SyncKey.deviceID) { return id }
        let id = UUID().uuidString
        defaults.set(id, forKey: SyncKey.deviceID)
        return id
    }

    /// The name others see for changes from this device.
    var syncOwnerName: String {
        get { defaults.string(forKey: SyncKey.ownerName) ?? "" }
        nonmutating set { defaults.set(newValue, forKey: SyncKey.ownerName) }
    }

    var lastSyncDate: Date? {
        get { defaults.object(forKey: SyncKey.lastSync) as? Date }
        nonmutating set { defaults.set(newValue, forKey: SyncKey.lastSync) }
    }
}

enum Currencies {
    /// Currencies offered for expenses. HRK was dropped: Croatia moved to the euro in 2023 and
    /// floatrates.com no longer publishes it.
    static let available = ["EUR", "USD", "GBP", "JPY", "CHF", "AUD", "BGN", "BRL", "CAD", "CNY", "CZK",
                            "DKK", "HKD", "HUF", "IDR", "ILS", "INR", "KRW", "MXN", "MYR", "NOK", "NZD",
                            "PHP", "PLN", "RON", "RUB", "SEK", "SGD", "THB", "TRY", "ZAR"]

    static func symbol(for code: String, locale: Locale = .current) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        return formatter.currencySymbol ?? code
    }

    static func name(for code: String, locale: Locale = .current) -> String {
        locale.localizedString(forCurrencyCode: code) ?? code
    }
}

extension Double {
    func formattedCurrency(_ code: String) -> String {
        formatted(.currency(code: code))
    }
}
