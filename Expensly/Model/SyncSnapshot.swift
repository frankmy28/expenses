import Foundation

/// What one device shares: its expenses in shared budgets and the expenses it deleted.
///
/// Each device writes its own file (`Expensly-<device id>.json`) into the shared folder and
/// reads everyone else's, so two people never write the same file. Merging uses the newest
/// change per expense ("last writer wins"); a deletion wins over older changes.
struct SyncSnapshot: Codable, Equatable, Sendable {
    static let currentFormat = 1

    var format = SyncSnapshot.currentFormat
    var deviceID: String
    var ownerName: String
    var writtenAt: Date
    var expenses: [SyncExpense]
    var deletions: [SyncDeletion]
}

struct SyncExpense: Codable, Equatable, Sendable {
    var id: UUID
    var modifiedAt: Date
    var date: Date
    var amount: Double
    var currency: String
    var exchangeRate: Double
    /// Budgets are matched by name between devices.
    var budget: String
    var category: String
    var project: String
    var comment: String?
    var venue: Venue?
}

struct SyncDeletion: Codable, Equatable, Sendable {
    var id: UUID
    var deletedAt: Date
}

/// What a merge changed locally.
struct SyncMergeStats: Equatable, Sendable {
    var added = 0
    var updated = 0
    var deleted = 0

    var received: Int { added + updated }

    static func += (lhs: inout SyncMergeStats, rhs: SyncMergeStats) {
        lhs.added += rhs.added
        lhs.updated += rhs.updated
        lhs.deleted += rhs.deleted
    }
}
