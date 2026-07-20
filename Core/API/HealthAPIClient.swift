import Foundation

public struct SamplePoint: Sendable {
    public let time: Date
    public let value: Double

    public init(time: Date, value: Double) {
        self.time = time
        self.value = value
    }
}

public enum APIError: Error, LocalizedError, Sendable {
    case http(Int, String)
    case badResponse(String)
    case allVariantsFailed(String)

    public var errorDescription: String? {
        switch self {
        case .http(let code, let body):
            return "HTTP \(code): \(body)"
        case .badResponse(let message):
            return "Unerwartete Antwort: \(message)"
        case .allVariantsFailed(let message):
            return "Kein Lesepfad funktionierte: \(message)"
        }
    }
}

/// Client für die Google Health API (v4).
/// Basis: https://health.googleapis.com/v4 — Datentypen als kebab-case in der URL,
/// Filter nach AIP-160 (snake_case-Feldpfade). Da die API neu ist, probiert der
/// Client je Datentyp mehrere Lesevarianten (reconcile → list → list nur mit
/// Startfilter) und merkt sich die funktionierende.
public final class HealthAPIClient: @unchecked Sendable {
    public static let baseURL = URL(string: "https://health.googleapis.com/v4")!

    private let auth: GoogleAuth
    private let config: GoogleOAuthConfig
    private let session: URLSession
    private let lock = NSLock()
    private var workingVariant: [String: ReadVariant] = [:]

    // Globale Drossel: Google erlaubt 300 Requests/min pro Nutzer (~5/s).
    // Alle Requests – auch parallele – halten einen Mindestabstand ein; ein
    // 429 verschiebt das Zeitfenster für ALLE Tasks nach hinten (Cooldown).
    private var nextAllowedRequest = Date.distantPast
    private let minRequestInterval: TimeInterval = 0.25

    public init(auth: GoogleAuth, config: GoogleOAuthConfig, session: URLSession = .shared) {
        self.auth = auth
        self.config = config
        self.session = session
    }

    enum ReadVariant: CaseIterable {
        case reconcileRange
        case listRange
        case listFrom
    }

    /// Zeitformat des Filterwerts — je Datentyp unterschiedlich.
    public enum TimeFilterFormat {
        case physical      // RFC-3339 mit Z (Sample-/Session-Zeiten, z.B. Schlaf)
        case civilDate     // "yyyy-MM-dd" (Tagesdatentypen, `date`)
        case civilDateTime // lokale Zivilzeit ohne Z (z.B. exercise.interval.civil_start_time)
    }

    private static let filterFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let civilDateTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f
    }()

    // MARK: - Roh-Datenpunkte

    /// Lädt alle Datenpunkte eines Typs im Zeitfenster (mit Pagination).
    /// - Parameters:
    ///   - type: kebab-case-Datentyp der URL, z.B. "heart-rate"
    ///   - payloadKey: camelCase-Key des Payloads im Datenpunkt, z.B. "heartRate"
    ///   - filterField: Feldpfad hinter dem Payload-Key, z.B. "sample_time.physical_time"
    ///   - timeFormat: Zeitformat des Filterwerts (physisch / Zivildatum / Zivilzeit)
    public func fetchRawDataPoints(
        type: String,
        payloadKey: String,
        filterField: String,
        start: Date,
        end: Date,
        timeFormat: TimeFilterFormat = .physical
    ) async throws -> [[String: Any]] {
        let fieldPath = "\(JSONExtract.snakeCase(payloadKey)).\(filterField)"
        let startValue: String
        let endValue: String
        switch timeFormat {
        case .physical:
            startValue = Self.filterFormatter.string(from: start)
            endValue = Self.filterFormatter.string(from: end)
        case .civilDate:
            startValue = DayKey.string(from: start)
            endValue = DayKey.string(from: end)
        case .civilDateTime:
            startValue = Self.civilDateTimeFormatter.string(from: start)
            endValue = Self.civilDateTimeFormatter.string(from: end)
        }
        let rangeFilter = "\(fieldPath) >= \"\(startValue)\" AND \(fieldPath) <= \"\(endValue)\""
        let fromFilter = "\(fieldPath) >= \"\(startValue)\""

        let variants: [ReadVariant]
        if let known = knownVariant(for: type) {
            variants = [known]
        } else {
            variants = ReadVariant.allCases
        }

        var lastError: Error?
        for variant in variants {
            let filter = variant == .listFrom ? fromFilter : rangeFilter
            let reconcile = variant == .reconcileRange
            do {
                let points = try await fetchPaginated(type: type, filter: filter, reconcile: reconcile)
                setKnownVariant(variant, for: type)
                return points
            } catch let error as APIError {
                if case .http(let code, _) = error, code == 400 || code == 404 {
                    lastError = error
                    continue
                }
                throw error
            }
        }
        throw APIError.allVariantsFailed(lastError.map { "\($0.localizedDescription)" } ?? "unbekannt")
    }

    private func fetchPaginated(type: String, filter: String, reconcile: Bool) async throws -> [[String: Any]] {
        var results: [[String: Any]] = []
        var pageToken: String?
        var pages = 0

        repeat {
            var query: [URLQueryItem] = [
                URLQueryItem(name: "filter", value: filter),
                URLQueryItem(name: "pageSize", value: "1000"),
            ]
            if let pageToken {
                query.append(URLQueryItem(name: "pageToken", value: pageToken))
            }
            let suffix = reconcile ? ":reconcile" : ""
            let json = try await getJSON(path: "/users/me/dataTypes/\(type)/dataPoints\(suffix)", query: query)
            let points = (json["dataPoints"] as? [[String: Any]])
                ?? (json["data_points"] as? [[String: Any]])
                ?? []
            results.append(contentsOf: points)
            pageToken = json["nextPageToken"] as? String
            pages += 1
        } while pageToken != nil && pages < 60

        return results
    }

    private func knownVariant(for type: String) -> ReadVariant? {
        lock.lock()
        defer { lock.unlock() }
        return workingVariant[type]
    }

    private func setKnownVariant(_ variant: ReadVariant, for type: String) {
        lock.lock()
        workingVariant[type] = variant
        lock.unlock()
    }

    // MARK: - Typisierte Abfragen

    /// Sample-Datentypen (Herzfrequenz, HRV, SpO2, Atemfrequenz, Temperatur …).
    public func fetchSamples(
        type: String,
        payloadKey: String,
        valueKeys: [String],
        start: Date,
        end: Date,
        filterField: String = "sample_time.physical_time",
        timeKeys: [String] = ["physicalTime", "startTime", "time", "endTime", "date"]
    ) async throws -> [SamplePoint] {
        let points = try await fetchRawDataPoints(
            type: type,
            payloadKey: payloadKey,
            filterField: filterField,
            start: start,
            end: end
        )
        return points.compactMap { point -> SamplePoint? in
            let payload = (point[payloadKey] as? [String: Any]) ?? point
            guard let value = JSONExtract.firstDouble(in: payload, keys: valueKeys),
                  let time = JSONExtract.firstDate(in: payload, keys: timeKeys),
                  time >= start, time < end else {
                return nil
            }
            return SamplePoint(time: time, value: value)
        }
        .sorted { $0.time < $1.time }
    }

    /// Tagesdatentypen (z.B. resting-heart-rate) → Werte je "yyyy-MM-dd".
    public func fetchDailyValues(
        type: String,
        payloadKey: String,
        valueKeys: [String],
        start: Date,
        end: Date
    ) async throws -> [String: Double] {
        let points = try await fetchRawDataPoints(
            type: type,
            payloadKey: payloadKey,
            filterField: "date",
            start: start,
            end: end,
            timeFormat: .civilDate
        )
        var result: [String: Double] = [:]
        for point in points {
            let payload = (point[payloadKey] as? [String: Any]) ?? point
            guard let value = JSONExtract.firstDouble(in: payload, keys: valueKeys) else { continue }
            var dateKey = JSONExtract.firstString(in: payload, keys: ["date"])
            if dateKey == nil, let time = JSONExtract.firstDate(in: payload, keys: ["physicalTime", "startTime"]) {
                dateKey = DayKey.string(from: time)
            }
            if let dateKey {
                result[String(dateKey.prefix(10))] = value
            }
        }
        return result
    }

    /// Schlaf-Sessions inkl. Phasen.
    public func fetchSleepSessions(start: Date, end: Date) async throws -> [SleepSession] {
        let points = try await fetchRawDataPoints(
            type: "sleep",
            payloadKey: "sleep",
            filterField: "interval.end_time",
            start: start,
            end: end
        )
        return points.compactMap { Self.parseSleep($0) }
    }

    public static func parseSleep(_ point: [String: Any]) -> SleepSession? {
        let payload = (point["sleep"] as? [String: Any]) ?? point
        let interval = (payload["interval"] as? [String: Any]) ?? [:]
        guard let start = JSONExtract.date(from: interval["startTime"]) ?? JSONExtract.firstDate(in: payload, keys: ["startTime"]),
              let end = JSONExtract.date(from: interval["endTime"]) ?? JSONExtract.firstDate(in: payload, keys: ["endTime"]),
              end > start else {
            return nil
        }

        var stages: [StageSpan] = []
        if let stageArray = payload["stages"] as? [[String: Any]] {
            for stage in stageArray {
                guard let s = JSONExtract.date(from: stage["startTime"]),
                      let e = JSONExtract.date(from: stage["endTime"]),
                      e > s else {
                    continue
                }
                let type = (stage["type"] as? String) ?? "UNKNOWN"
                stages.append(StageSpan(stage: SleepStage(apiValue: type), start: s, end: e))
            }
            stages.sort { $0.start < $1.start }
        }

        let summary = (payload["summary"] as? [String: Any]) ?? [:]
        var minutesAsleep = JSONExtract.firstDouble(in: summary, keys: ["minutesAsleep", "totalMinutesAsleep"])
        if minutesAsleep == nil {
            let fromStages = stages.filter { $0.stage.isAsleep }.reduce(0) { $0 + $1.minutes }
            minutesAsleep = fromStages > 0 ? fromStages : end.timeIntervalSince(start) / 60 * 0.92
        }
        var minutesAwake = JSONExtract.firstDouble(in: summary, keys: ["minutesAwake"])
        if minutesAwake == nil {
            let fromStages = stages.filter { $0.stage == .awake }.reduce(0) { $0 + $1.minutes }
            minutesAwake = fromStages
        }

        let id = (point["name"] as? String) ?? "sleep-\(Int(start.timeIntervalSince1970))"
        let isMain = (payload["isMainSleep"] as? Bool) ?? false

        return SleepSession(
            id: id,
            start: start,
            end: end,
            minutesAsleep: minutesAsleep ?? 0,
            minutesAwake: minutesAwake ?? 0,
            stages: stages,
            isMainSleep: isMain
        )
    }

    /// Workout-/Exercise-Sessions.
    public func fetchExerciseSessions(start: Date, end: Date) async throws -> [Workout] {
        // Exercise ist filterbar nur über interval.civil_start_time (Zivilzeit,
        // ISO ohne Z, nur >=/<). Der listFrom-Lesepfad nutzt genau dieses `>=`.
        let points = try await fetchRawDataPoints(
            type: "exercise",
            payloadKey: "exercise",
            filterField: "interval.civil_start_time",
            start: start,
            end: end,
            timeFormat: .civilDateTime
        )
        return points.compactMap { Self.parseExercise($0) }
    }

    public static func parseExercise(_ point: [String: Any]) -> Workout? {
        let payload = (point["exercise"] as? [String: Any]) ?? point
        // Zeitintervall: Google nennt es "interval"; ältere Fixtures "sessionTimeInterval".
        let interval = (payload["interval"] as? [String: Any])
            ?? (payload["sessionTimeInterval"] as? [String: Any]) ?? [:]
        guard let start = JSONExtract.date(from: interval["startTime"]) ?? JSONExtract.firstDate(in: payload, keys: ["startTime"]),
              let end = JSONExtract.date(from: interval["endTime"]) ?? JSONExtract.firstDate(in: payload, keys: ["endTime"]) else {
            return nil
        }
        let name = (payload["activityName"] as? String)
            ?? (payload["activityType"] as? String)
            ?? (payload["name"] as? String)
            ?? "Workout"
        let avgHR = JSONExtract.firstDouble(in: payload, keys: ["averageHeartRate", "avgHeartRate", "averageHeartRateBpm"])
        let calories = JSONExtract.firstDouble(in: payload, keys: ["calories", "caloriesBurned", "activeCalories"])
        let id = (point["name"] as? String) ?? "\(start.timeIntervalSince1970)-\(name)"
        return Workout(id: id, name: name, start: start, end: end, averageHR: avgHR, calories: calories)
    }

    /// Nutzerprofil (Name, Geburtstag falls freigegeben).
    public func fetchProfile() async throws -> UserProfile {
        let json = try await getJSON(path: "/users/me/profile", query: [])
        let payload = (json["profile"] as? [String: Any]) ?? json
        let name = (payload["displayName"] as? String) ?? (payload["fullName"] as? String)
        let birthday = JSONExtract.firstString(in: payload, keys: ["birthday", "dateOfBirth"])
        let genderString = JSONExtract.firstString(in: payload, keys: ["gender", "sex", "biologicalSex"])
        return UserProfile(displayName: name, birthday: birthday, sex: BiologicalSex(apiValue: genderString))
    }

    // MARK: - HTTP

    private func getJSON(path: String, query: [URLQueryItem]) async throws -> [String: Any] {
        guard var components = URLComponents(url: Self.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false) else {
            throw APIError.badResponse("Ungültiger Pfad")
        }
        // ":reconcile" darf nicht als Pfadsegment encodiert werden
        components.path = components.path.replacingOccurrences(of: "%3A", with: ":")
        if !query.isEmpty {
            components.queryItems = query
        }
        guard let url = components.url else {
            throw APIError.badResponse("Ungültige URL")
        }

        var attempt = 0
        var didRefresh = false
        while true {
            await throttle()
            let token = try await auth.validAccessToken(config: config)
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")

            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await session.data(for: request)
            } catch {
                throw APIError.badResponse(error.localizedDescription)
            }
            guard let http = response as? HTTPURLResponse else {
                throw APIError.badResponse("Keine HTTP-Antwort")
            }

            switch http.statusCode {
            case 200..<300:
                guard let object = try? JSONSerialization.jsonObject(with: data),
                      let dict = object as? [String: Any] else {
                    throw APIError.badResponse("Kein JSON-Objekt")
                }
                return dict
            case 401 where !didRefresh:
                didRefresh = true
                _ = try await auth.refresh(config: config)
                continue
            case 429:
                // Minuten-Quota erreicht: ALLE Tasks global ausbremsen und
                // großzügiger erneut versuchen — der Sync soll sich aufs
                // erlaubte Tempo einpendeln, nicht scheitern.
                guard attempt < 5 else {
                    throw APIError.http(http.statusCode, Self.bodyExcerpt(data))
                }
                let delay = Self.retryDelay(
                    attempt: attempt,
                    retryAfterHeader: http.value(forHTTPHeaderField: "Retry-After")
                )
                imposeCooldown(delay)
                attempt += 1
                continue
            case 500, 502, 503, 504:
                guard attempt < 3 else {
                    throw APIError.http(http.statusCode, Self.bodyExcerpt(data))
                }
                let delay = Self.retryDelay(
                    attempt: attempt,
                    retryAfterHeader: http.value(forHTTPHeaderField: "Retry-After")
                )
                try await Task.sleep(nanoseconds: UInt64(min(delay, 30) * 1_000_000_000))
                attempt += 1
                continue
            default:
                throw APIError.http(http.statusCode, Self.bodyExcerpt(data))
            }
        }
    }

    private static func bodyExcerpt(_ data: Data) -> String {
        String(String(data: data, encoding: .utf8)?.prefix(300) ?? "")
    }

    // MARK: - Drossel & Backoff

    /// Reserviert den nächsten Request-Slot und wartet, bis er frei ist.
    private func throttle() async {
        let wait: TimeInterval = {
            lock.lock()
            defer { lock.unlock() }
            let now = Date()
            let slot = max(nextAllowedRequest, now)
            nextAllowedRequest = slot.addingTimeInterval(minRequestInterval)
            return slot.timeIntervalSince(now)
        }()
        if wait > 0 {
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
        }
    }

    /// Nach einem 429: alle weiteren Requests global um `delay` verschieben.
    private func imposeCooldown(_ delay: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        let until = Date().addingTimeInterval(delay)
        if until > nextAllowedRequest {
            nextAllowedRequest = until
        }
    }

    /// Wartezeit für einen Retry: Retry-After-Header, sonst exponentiell (2,4,8…), Kappung 60 s.
    public static func retryDelay(attempt: Int, retryAfterHeader: String?) -> TimeInterval {
        if let header = retryAfterHeader, let seconds = Double(header), seconds > 0 {
            return min(seconds, 60)
        }
        return min(pow(2, Double(attempt + 1)), 60)
    }
}
