import Foundation

/// Persists completed agent sessions to daily JSON files under `baseURL`.
public final class SessionArchiveStore: @unchecked Sendable {

    /// Default singleton backed by `~/.desktoppet/history/`.
    public static let shared: SessionArchiveStore = SessionArchiveStore(
        baseURL: FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".desktoppet/history", isDirectory: true)
    )

    /// Root directory where daily archive files are stored.
    public let baseURL: URL

    private let queue = DispatchQueue(label: "com.desktoppet.SessionArchiveStore")
    private var archivedIds = Set<String>()

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    public init(baseURL: URL) {
        self.baseURL = baseURL
        queue.sync {
            do {
                try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
            } catch {
                fputs("SessionArchiveStore: failed to create directory \(baseURL.path): \(error)\n", stderr)
            }
            self.archivedIds = self._rebuildDedupSet()
        }
    }

    /// Persists a completed session to the daily archive file.
    public func archive(_ session: AgentSession, startedAt: Date, endedAt: Date) {
        queue.sync {
            guard !archivedIds.contains(session.id) else { return }

            let record = SessionArchive(
                sessionId: session.id,
                agentKind: session.agentKind,
                project: session.project,
                title: session.title,
                message: session.message,
                tokenCount: nil,
                startedAt: startedAt,
                endedAt: endedAt,
                duration: endedAt.timeIntervalSince(startedAt)
            )

            let fileURL = self._fileURL(for: startedAt)
            var existing = self._readRecords(from: fileURL)
            existing.append(record)

            do {
                let data = try SessionArchiveStore.encoder.encode(existing)
                try data.write(to: fileURL, options: .atomic)
                archivedIds.insert(session.id)
            } catch {
                fputs("SessionArchiveStore: failed to write archive \(fileURL.path): \(error)\n", stderr)
            }
        }
    }

    /// Returns all archived records for the calendar day containing `date` (UTC).
    public func records(for date: Date) -> [SessionArchive] {
        queue.sync {
            let fetched = self._readRecords(from: self._fileURL(for: date))
            for r in fetched { archivedIds.insert(r.sessionId) }
            return fetched
        }
    }

    /// Returns all records from the calendar day of `date` (UTC) up to today.
    public func allRecords(since date: Date) -> [SessionArchive] {
        queue.sync {
            guard var current = self._startOfDay(date) else { return [] }
            let today = Date()
            var result: [SessionArchive] = []

            while current <= today {
                result.append(contentsOf: self._readRecords(from: self._fileURL(for: current)))
                guard let next = Self.utcCalendar.date(byAdding: .day, value: 1, to: current) else { break }
                current = next
            }
            return result
        }
    }

    /// Deletes daily archive files older than `days` days.
    /// Uses the most recent archive file's date (or today if none) as the reference point.
    public func pruneOlderThan(days: Int) {
        queue.sync {
            guard let contents = try? FileManager.default.contentsOfDirectory(
                at: baseURL, includingPropertiesForKeys: nil
            ) else { return }

            let jsonFiles = contents.filter { $0.pathExtension == "json" }
            let names = jsonFiles.map { $0.deletingPathExtension().lastPathComponent }

            // Find the latest archive date to use as reference; fall back to today
            let referenceString = names.max() ?? SessionArchiveStore.dateFormatter.string(from: Date())
            guard let referenceDate = SessionArchiveStore.dateFormatter.date(from: referenceString) else { return }

            let cutoffDate = referenceDate.addingTimeInterval(-TimeInterval(days) * 86_400)
            let cutoffString = SessionArchiveStore.dateFormatter.string(from: cutoffDate)

            for url in jsonFiles {
                let name = url.deletingPathExtension().lastPathComponent
                if name < cutoffString {
                    try? FileManager.default.removeItem(at: url)
                }
            }
        }
    }

    // MARK: - Private helpers (must be called inside queue)

    private static let utcCalendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    /// Returns midnight UTC on the same day as `date`, or `nil` if the calendar conversion fails.
    private func _startOfDay(_ date: Date) -> Date? {
        var components = Self.utcCalendar.dateComponents([.year, .month, .day], from: date)
        components.hour = 0
        components.minute = 0
        components.second = 0
        components.nanosecond = 0
        return Self.utcCalendar.date(from: components)
    }

    private func _fileURL(for date: Date) -> URL {
        let name = SessionArchiveStore.dateFormatter.string(from: date)
        return baseURL.appendingPathComponent("\(name).json")
    }

    private func _readRecords(from url: URL) -> [SessionArchive] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? SessionArchiveStore.decoder.decode([SessionArchive].self, from: data)) ?? []
    }

    private func _rebuildDedupSet() -> Set<String> {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: baseURL, includingPropertiesForKeys: nil
        ) else { return [] }

        var ids = Set<String>()
        for url in contents where url.pathExtension == "json" {
            let records = _readRecords(from: url)
            for r in records { ids.insert(r.sessionId) }
        }
        return ids
    }
}
