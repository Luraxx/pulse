import Foundation

/// JSON-based storage for all daily records.
/// Used by the app on the MainActor; the sync engine delivers
/// finished DayRecords that are merged here.
public final class MetricsStore {
    public private(set) var days: [String: DayRecord] = [:]
    public let fileURL: URL

    /// Intraday HR is kept only for the last N days to keep the file small.
    public var hrRetentionDays: Int = 28

    public init(directory: URL, filename: String = "days.json") {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.fileURL = directory.appendingPathComponent(filename)
        load()
    }

    public func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let decoded = try? decoder.decode([String: DayRecord].self, from: data) {
            days = decoded
        }
    }

    @discardableResult
    public func save() -> Bool {
        pruneHeartRateSamples()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(days) else { return false }
        do {
            try data.write(to: fileURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    public func wipe() {
        days = [:]
        try? FileManager.default.removeItem(at: fileURL)
    }

    // MARK: - Access

    public func record(for key: String) -> DayRecord {
        days[key] ?? DayRecord(date: key)
    }

    public func upsert(_ record: DayRecord) {
        days[record.date] = record
    }

    public func update(_ key: String, _ mutate: (inout DayRecord) -> Void) {
        var record = record(for: key)
        mutate(&record)
        days[key] = record
    }

    public func merge(_ records: [DayRecord]) {
        for record in records {
            days[record.date] = record
        }
    }

    public func replaceAll(_ newDays: [String: DayRecord]) {
        days = newDays
    }

    public var sortedKeys: [String] {
        days.keys.sorted()
    }

    /// Chronological records of the last `count` calendar days up to `key` (inclusive).
    /// Missing days are skipped.
    public func chronological(upTo key: String, count: Int) -> [DayRecord] {
        let start = DayKey.addDays(key, -(count - 1))
        return DayKey.keys(from: start, to: key).compactMap { days[$0] }
    }

    /// Records of the `count` days BEFORE `key` (exclusive), chronological.
    public func history(before key: String, days count: Int) -> [DayRecord] {
        let end = DayKey.addDays(key, -1)
        let start = DayKey.addDays(key, -count)
        return DayKey.keys(from: start, to: end).compactMap { days[$0] }
    }

    // MARK: - Maintenance

    private func pruneHeartRateSamples() {
        let cutoff = DayKey.addDays(DayKey.today(), -hrRetentionDays)
        for (key, var record) in days where key < cutoff && !record.hrSamples.isEmpty {
            record.hrSamples = []
            days[key] = record
        }
    }
}
