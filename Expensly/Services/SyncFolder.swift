import Foundation

enum SyncFolderError: LocalizedError {
    case noAccess(String)

    var errorDescription: String? {
        switch self {
        case let .noAccess(name):
            String(localized: "Expensly has no access to the folder \(name). Choose it again.")
        }
    }
}

/// Reads and writes sync files in the shared folder (for example a folder in iCloud Drive that
/// is shared with the family in the Files app). Runs off the main thread: reading a file that
/// iCloud has not downloaded yet can take a while.
struct SyncFolder: Sendable {
    static let filePrefix = "Expensly-"
    static let fileExtension = "json"

    let url: URL

    var name: String { url.lastPathComponent }

    func fileName(for deviceID: String) -> String {
        "\(Self.filePrefix)\(deviceID).\(Self.fileExtension)"
    }

    /// Everyone else's snapshots, and how many files iCloud is still downloading.
    func readSnapshots(excluding deviceID: String) throws -> (snapshots: [SyncSnapshot], pending: Int) {
        try withAccess {
            let ownFile = fileName(for: deviceID)
            let manager = FileManager.default
            let names = try manager.contentsOfDirectory(atPath: url.path(percentEncoded: false))
            var snapshots: [SyncSnapshot] = []
            var pending = 0
            for name in names {
                // iCloud keeps files that are not downloaded as ".<name>.icloud" placeholders.
                if name.hasPrefix(".\(Self.filePrefix)"), name.hasSuffix(".\(Self.fileExtension).icloud") {
                    let realName = String(name.dropFirst().dropLast(".icloud".count))
                    guard realName != ownFile else { continue }
                    try? manager.startDownloadingUbiquitousItem(at: url.appending(path: realName))
                    pending += 1
                    continue
                }
                guard name.hasPrefix(Self.filePrefix), name.hasSuffix(".\(Self.fileExtension)"), name != ownFile else {
                    continue
                }
                let data = try coordinatedRead(url.appending(path: name))
                if let snapshot = try? JSONDecoder().decode(SyncSnapshot.self, from: data),
                   snapshot.format <= SyncSnapshot.currentFormat {
                    snapshots.append(snapshot)
                }
            }
            return (snapshots, pending)
        }
    }

    func write(_ snapshot: SyncSnapshot) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(snapshot)
        try withAccess {
            try coordinatedWrite(data, to: url.appending(path: fileName(for: snapshot.deviceID)))
        }
    }

    private func withAccess<T>(_ body: () throws -> T) throws -> T {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            throw SyncFolderError.noAccess(name)
        }
        return try body()
    }

    private func coordinatedRead(_ file: URL) throws -> Data {
        var coordinationError: NSError?
        var result: Result<Data, Error> = .failure(CocoaError(.fileReadUnknown))
        NSFileCoordinator().coordinate(readingItemAt: file, options: [], error: &coordinationError) { readURL in
            result = Result { try Data(contentsOf: readURL) }
        }
        if let coordinationError { throw coordinationError }
        return try result.get()
    }

    private func coordinatedWrite(_ data: Data, to file: URL) throws {
        var coordinationError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: file, options: .forReplacing, error: &coordinationError) { writeURL in
            do { try data.write(to: writeURL, options: .atomic) } catch { writeError = error }
        }
        if let coordinationError { throw coordinationError }
        if let writeError { throw writeError }
    }
}
