import Foundation
import Observation

/// Shares budgets through a folder: reads the other devices' files, merges them into the
/// store, then writes this device's file. Runs when the app opens or goes to the background,
/// and when the user taps Sync Now.
@MainActor
@Observable
final class SyncService {
    struct Report: Equatable {
        var date: Date
        var stats: SyncMergeStats
        var sources: [String]
        var pending: Int
    }

    @ObservationIgnored let store: ExpenseStore
    private(set) var folderName: String?
    private(set) var isSyncing = false
    private(set) var lastReport: Report?
    var lastError: String?

    private var settings: AppSettings { store.settings }

    init(store: ExpenseStore) {
        self.store = store
        folderName = resolveFolder()?.name
    }

    var isConfigured: Bool { settings.syncFolderBookmark != nil }

    var ownerName: String {
        get { settings.syncOwnerName }
        set { settings.syncOwnerName = newValue }
    }

    var lastSyncDate: Date? { settings.lastSyncDate }

    /// Remembers a folder picked by the user. The URL from the file picker is only usable while
    /// the app runs, so a bookmark is stored instead.
    func useFolder(_ url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            settings.syncFolderBookmark = try url.bookmarkData()
            folderName = url.lastPathComponent
            lastError = nil
            lastReport = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func stopSharing() {
        settings.syncFolderBookmark = nil
        settings.lastSyncDate = nil
        folderName = nil
        lastReport = nil
        lastError = nil
    }

    func syncIfConfigured() async {
        guard isConfigured, !isSyncing else { return }
        await sync()
    }

    func sync() async {
        guard let folder = resolveFolder() else {
            lastError = isConfigured ? SyncFolderError.noAccess(folderName ?? "").localizedDescription : nil
            return
        }
        isSyncing = true
        defer { isSyncing = false }
        let deviceID = settings.syncDeviceID
        do {
            let (snapshots, pending) = try await Task.detached {
                try folder.readSnapshots(excluding: deviceID)
            }.value
            var stats = SyncMergeStats()
            for snapshot in snapshots {
                stats += store.merge(snapshot)
            }
            let own = store.syncSnapshot(deviceID: deviceID, ownerName: settings.syncOwnerName)
            try await Task.detached { try folder.write(own) }.value
            let names = snapshots.map { $0.ownerName.isEmpty ? String(localized: "Unnamed device") : $0.ownerName }
            lastReport = Report(date: .now, stats: stats, sources: names, pending: pending)
            settings.lastSyncDate = .now
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func resolveFolder() -> SyncFolder? {
        guard let bookmark = settings.syncFolderBookmark else { return nil }
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, bookmarkDataIsStale: &isStale) else {
            return nil
        }
        if isStale {
            let accessing = url.startAccessingSecurityScopedResource()
            if let fresh = try? url.bookmarkData() { settings.syncFolderBookmark = fresh }
            if accessing { url.stopAccessingSecurityScopedResource() }
        }
        return SyncFolder(url: url)
    }
}
