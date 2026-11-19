import Foundation
import Observation
import AuthenticationServices
import BackgroundTasks
import UIKit

/// Central app model: holds the store, auth, settings and the computed
/// Whoop metrics (recovery, strain, sleep) for all views.
@MainActor
@Observable
final class AppModel {
    // MARK: - Settings (persisted in UserDefaults)

    private enum Keys {
        static let clientID = "google.clientID"
        static let onboarded = "app.onboarded"
        static let demoMode = "app.demoMode"
        static let daysBack = "sync.daysBack"
        static let hrDaysBack = "sync.hrDaysBack"
        static let sleepNeed = "calc.sleepNeedMinutes"
        static let age = "calc.age"
        static let sex = "calc.sex"
        static let heightCm = "profile.heightCm"
        static let weightKg = "profile.weightKg"
        static let maxHR = "calc.maxHROverride"
        static let lastSync = "sync.lastSyncAt"
        static let notifications = "notify.enabled"
        static let connectedAt = "auth.connectedAt"
        static let moduleOrder = "dashboard.moduleOrder"
        static let hiddenModules = "dashboard.hiddenModules"
        static let language = "app.language"
    }

    /// Identifier of the background sync task (must be listed in Info.plist under
    /// BGTaskSchedulerPermittedIdentifiers).
    static let refreshTaskID = "net.dehlwes.pulse.refresh"

    /// App language; applies immediately to all texts (no restart needed).
    var language: PulseLanguage {
        didSet {
            defaults.set(language.rawValue, forKey: Keys.language)
            Fmt.language = language
            recomputeAll() // AgeEngine components carry localized texts
        }
    }

    /// Shorthand for bilingual texts right where they are used.
    func loc(_ de: String, _ en: String) -> String {
        language == .de ? de : en
    }

    var clientID: String {
        didSet { defaults.set(clientID, forKey: Keys.clientID) }
    }
    var onboarded: Bool {
        didSet { defaults.set(onboarded, forKey: Keys.onboarded) }
    }
    var demoMode: Bool {
        didSet { defaults.set(demoMode, forKey: Keys.demoMode) }
    }
    var daysBack: Int {
        didSet { defaults.set(daysBack, forKey: Keys.daysBack) }
    }
    var hrDaysBack: Int {
        didSet { defaults.set(hrDaysBack, forKey: Keys.hrDaysBack) }
    }
    var baseSleepNeedMinutes: Double {
        didSet {
            defaults.set(baseSleepNeedMinutes, forKey: Keys.sleepNeed)
            recomputeAll()
        }
    }
    var age: Int {
        didSet {
            defaults.set(age, forKey: Keys.age)
            recomputeAll()
        }
    }
    var sex: BiologicalSex {
        didSet {
            defaults.set(sex.rawValue, forKey: Keys.sex)
            recomputeAll()
        }
    }
    /// Height in cm (profile; currently not used in any score calculation).
    var heightCm: Double {
        didSet { defaults.set(heightCm, forKey: Keys.heightCm) }
    }
    /// Weight in kg (profile; VO₂max is already normalized per kg).
    var weightKg: Double {
        didSet { defaults.set(weightKg, forKey: Keys.weightKg) }
    }
    /// 0 = automatic (Tanaka formula)
    var maxHROverride: Double {
        didSet {
            defaults.set(maxHROverride, forKey: Keys.maxHR)
            recomputeAll()
        }
    }
    var lastSyncAt: Date? {
        didSet {
            if let lastSyncAt {
                defaults.set(lastSyncAt.timeIntervalSince1970, forKey: Keys.lastSync)
            } else {
                defaults.removeObject(forKey: Keys.lastSync)
            }
        }
    }
    /// Opt-in for the morning recovery notification + background sync.
    private(set) var notificationsEnabled: Bool {
        didSet { defaults.set(notificationsEnabled, forKey: Keys.notifications) }
    }
    /// Time of the last connection (for the 7-day expiry warning).
    private(set) var connectedAt: Date? {
        didSet {
            if let connectedAt {
                defaults.set(connectedAt.timeIntervalSince1970, forKey: Keys.connectedAt)
            } else {
                defaults.removeObject(forKey: Keys.connectedAt)
            }
        }
    }

    // MARK: - Runtime state

    private(set) var syncing = false
    private(set) var syncMessage = ""
    private(set) var syncFraction: Double = 0
    var lastError: String?
    private(set) var syncLog: [SyncLogEntry] = []
    var selectedDayKey: String
    private(set) var profileName: String?
    /// Day for which the morning journal popup should be shown (usually yesterday).
    var journalPromptDay: String?

    // MARK: - Dashboard customization

    /// Order of ALL modules (including hidden ones).
    private(set) var moduleOrder: [DashboardModule] = DashboardModule.allCases {
        didSet { defaults.set(moduleOrder.map(\.rawValue), forKey: Keys.moduleOrder) }
    }
    /// Hidden modules.
    private(set) var hiddenModules: Set<DashboardModule> = [] {
        didSet { defaults.set(hiddenModules.map(\.rawValue), forKey: Keys.hiddenModules) }
    }

    var visibleModules: [DashboardModule] {
        moduleOrder.filter { !hiddenModules.contains($0) }
    }

    func moveModules(from source: IndexSet, to destination: Int) {
        moduleOrder.move(fromOffsets: source, toOffset: destination)
    }

    func setModule(_ module: DashboardModule, visible: Bool) {
        if visible {
            hiddenModules.remove(module)
        } else {
            hiddenModules.insert(module)
        }
    }

    // MARK: - Data & derived metrics

    let store: MetricsStore
    let journal: JournalStore
    let auth = GoogleAuth()
    private(set) var strainResults: [String: StrainResult] = [:]
    private(set) var sleepAnalyses: [String: SleepAnalysis] = [:]
    private(set) var recoveryResults: [String: RecoveryResult] = [:]
    private(set) var ageResults: [String: AgeResult] = [:]
    private(set) var journalInsights: [FactorInsight] = []
    /// Observable mirror of the journal entries. JournalStore is a plain
    /// class (not @Observable) — without this mirror, toggles in the
    /// UI would not show up because SwiftUI doesn't notice any change.
    private(set) var journalEntries: [String: JournalEntry] = [:]

    private let defaults = UserDefaults.standard

    init() {
        let directory = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Pulse", isDirectory: true)
        store = MetricsStore(directory: directory)
        journal = JournalStore(directory: directory)

        // Local constant so self.language (observable getter) is not
        // read below before all stored properties are initialized.
        let initialLanguage = defaults.string(forKey: Keys.language).flatMap(PulseLanguage.init(rawValue:))
            ?? .systemDefault
        language = initialLanguage
        Fmt.language = initialLanguage

        clientID = defaults.string(forKey: Keys.clientID) ?? ""
        onboarded = defaults.bool(forKey: Keys.onboarded)
        demoMode = defaults.bool(forKey: Keys.demoMode)
        daysBack = (defaults.object(forKey: Keys.daysBack) as? Int) ?? 60
        hrDaysBack = (defaults.object(forKey: Keys.hrDaysBack) as? Int) ?? 14
        baseSleepNeedMinutes = (defaults.object(forKey: Keys.sleepNeed) as? Double) ?? 456
        age = (defaults.object(forKey: Keys.age) as? Int) ?? 30
        sex = (defaults.string(forKey: Keys.sex)).flatMap(BiologicalSex.init(rawValue:)) ?? .unspecified
        heightCm = (defaults.object(forKey: Keys.heightCm) as? Double) ?? 175
        weightKg = (defaults.object(forKey: Keys.weightKg) as? Double) ?? 75
        maxHROverride = (defaults.object(forKey: Keys.maxHR) as? Double) ?? 0
        lastSyncAt = (defaults.object(forKey: Keys.lastSync) as? Double).map(Date.init(timeIntervalSince1970:))
        notificationsEnabled = defaults.bool(forKey: Keys.notifications)
        connectedAt = (defaults.object(forKey: Keys.connectedAt) as? Double).map(Date.init(timeIntervalSince1970:))
        selectedDayKey = DayKey.today()

        // Load module order; append new modules (from future versions) at the end.
        var order = (defaults.stringArray(forKey: Keys.moduleOrder) ?? [])
            .compactMap(DashboardModule.init(rawValue:))
        for module in DashboardModule.allCases where !order.contains(module) {
            order.append(module)
        }
        moduleOrder = order
        hiddenModules = Set(
            (defaults.stringArray(forKey: Keys.hiddenModules) ?? [])
                .compactMap(DashboardModule.init(rawValue:))
        )

        recomputeAll()
    }

    // MARK: - Derived configuration

    var oauthConfig: GoogleOAuthConfig {
        GoogleOAuthConfig(clientID: clientID)
    }

    var isConnected: Bool {
        auth.isConnected
    }

    var strainConfig: StrainConfig {
        StrainConfig(age: age, maxHROverride: maxHROverride > 0 ? maxHROverride : nil)
    }

    var sleepConfig: SleepEngineConfig {
        var config = SleepEngineConfig()
        config.baselineNeedMinutes = baseSleepNeedMinutes
        return config
    }

    var hasData: Bool {
        !store.days.isEmpty
    }

    var availableKeys: [String] {
        store.sortedKeys
    }

    // MARK: - Access for views

    func record(for key: String) -> DayRecord? {
        store.days[key]
    }

    func recovery(for key: String) -> RecoveryResult? {
        recoveryResults[key]
    }

    func sleep(for key: String) -> SleepAnalysis? {
        sleepAnalyses[key]
    }

    func strain(for key: String) -> StrainResult? {
        strainResults[key]
    }

    func ageResult(for key: String) -> AgeResult? {
        ageResults[key]
    }

    // MARK: - Journal

    func journalEntry(for key: String) -> JournalEntry {
        // Read from the observable mirror, not from the store — otherwise
        // SwiftUI does not notice the change after a toggle.
        journalEntries[key] ?? JournalEntry(date: key)
    }

    func toggleJournal(_ factor: JournalFactor, on key: String) {
        journal.toggle(factor, on: key)
        journal.save()
        recomputeJournalInsights()
    }

    private func recomputeJournalInsights() {
        journalEntries = journal.entries
        let recoveryByDay = recoveryResults.mapValues { $0.score }
        journalInsights = JournalEngine.insights(entries: journal.entries, recoveryByDay: recoveryByDay)
    }

    /// Number of days with recovery — basis for the monthly assessment (from 28).
    var recoveryDayCount: Int {
        recoveryResults.count
    }

    /// Shows the journal popup for yesterday — at most once per day, only if
    /// yesterday has data and nothing has been entered yet.
    func maybeShowJournalPrompt() {
        guard hasData, journalPromptDay == nil else { return }
        let yesterday = DayKey.addDays(DayKey.today(), -1)
        guard journal.entry(for: yesterday).factors.isEmpty,
              let record = store.days[yesterday],
              record.restingHR != nil || !record.sleepSessions.isEmpty || record.steps != nil else { return }
        let promptedKey = "journal.promptedFor"
        guard defaults.string(forKey: promptedKey) != yesterday else { return }
        defaults.set(yesterday, forKey: promptedKey)
        journalPromptDay = yesterday
    }

    /// Reschedules the routine notifications (after every sync):
    /// morning alarm for tomorrow 7:30 (replaces today's) and the
    /// bedtime reminder for tonight.
    func rescheduleRoutineNotifications() {
        guard notificationsEnabled else { return }
        PulseNotifications.scheduleMorningReminder(language: language)
        if let bed = bedtimeTonight?.recommendedBedtimeMinutes {
            PulseNotifications.scheduleBedtimeReminder(bedtimeMinutes: bed, language: language)
        } else {
            PulseNotifications.cancelBedtimeReminder()
        }
    }

    // MARK: - Health warning & bedtime recommendation

    /// Proactive health warning for the selected day (nil = all within range).
    var healthAlert: HealthAlert? {
        let records = store.chronological(upTo: selectedDayKey, count: 10)
        return HealthMonitor.alert(records: records, language: language)
    }

    /// Recommendation for the coming night (from sleep debt, today's strain,
    /// usual wake time). nil without enough history.
    var bedtimeTonight: BedtimeRecommendation? {
        guard hasData else { return nil }
        let today = DayKey.today()
        let debt = sleepAnalyses[today]?.debtAfterMinutes
            ?? store.sortedKeys.last.flatMap { sleepAnalyses[$0]?.debtAfterMinutes }
            ?? 0
        let strainToday = strainResults[today]?.strain ?? 0
        let recentWakes = store.chronological(upTo: today, count: 7)
            .compactMap { sleepAnalyses[$0.date]?.wakeTime }
        guard !recentWakes.isEmpty else { return nil }
        return SleepEngine.bedtimeRecommendation(
            currentDebtMinutes: debt,
            strainToday: strainToday,
            recentWakeTimes: recentWakes,
            config: sleepConfig
        )
    }

    var selectedRecord: DayRecord? {
        record(for: selectedDayKey)
    }

    /// Health Monitor status for the selected day.
    var healthStatuses: [HealthMetricStatus] {
        guard let record = selectedRecord else { return [] }
        let history = store.history(before: selectedDayKey, days: 45)
        return HealthMonitor.evaluate(today: record, history: history)
    }

    /// Values of a metric for the last `count` days up to the selected day.
    func trend(_ count: Int, endingAt key: String? = nil, _ value: (DayRecord) -> Double?) -> [(key: String, value: Double)] {
        let end = key ?? selectedDayKey
        let start = DayKey.addDays(end, -(count - 1))
        return DayKey.keys(from: start, to: end).compactMap { dayKey in
            guard let record = store.days[dayKey], let v = value(record) else { return nil }
            return (dayKey, v)
        }
    }

    // MARK: - Recalculation

    func recomputeAll() {
        var strains: [String: StrainResult] = [:]
        var strainScalar: [String: Double] = [:]
        for (key, record) in store.days {
            let result = StrainEngine.dayStrain(record: record, restingHR: record.restingHR, config: strainConfig)
            strains[key] = result
            strainScalar[key] = result.strain
        }
        strainResults = strains

        sleepAnalyses = SleepEngine.analyze(days: store.days, config: sleepConfig, strainByDay: strainScalar)

        // Write workout strains into the records
        for (_, record) in store.days where !record.workouts.isEmpty {
            var updated = record
            for index in updated.workouts.indices {
                updated.workouts[index].strain = StrainEngine.workoutStrain(
                    workout: updated.workouts[index],
                    daySamples: record.hrSamples,
                    restingHR: record.restingHR,
                    config: strainConfig
                )
            }
            store.upsert(updated)
        }

        // Recovery chronologically with growing history
        var recoveries: [String: RecoveryResult] = [:]
        var history: [DayRecord] = []
        let keys = store.sortedKeys
        history.reserveCapacity(keys.count)
        for key in keys {
            guard let record = store.days[key] else { continue }
            recoveries[key] = RecoveryEngine.compute(
                dateKey: key,
                today: record,
                history: history,
                sleepPerformance: sleepAnalyses[key]?.performance
            )
            history.append(record)
        }
        recoveryResults = recoveries
        recomputeJournalInsights()

        // Biological "Pulse Age" per day from the 30-day window.
        var ages: [String: AgeResult] = [:]
        for key in keys {
            let window = store.chronological(upTo: key, count: AgeEngine.calibrationNeed)
            guard !window.isEmpty else { continue }
            let sleepPerf = window.compactMap { record -> Double? in
                guard let analysis = sleepAnalyses[record.date], analysis.hasData else { return nil }
                return analysis.performance
            }
            let inputs = AgeInputs(
                chronoAge: age,
                sex: sex,
                vo2maxValues: window.compactMap { $0.vo2max },
                rmssdValues: window.compactMap { $0.hrvRmssd },
                restingHRValues: window.compactMap { $0.restingHR },
                observedMaxHR: Self.robustMaxHR(window),
                maxHROverride: maxHROverride > 0 ? maxHROverride : nil,
                sleepPerformances: sleepPerf,
                stepsValues: window.compactMap { $0.steps.map(Double.init) },
                validDayCount: window.filter { $0.hrvRmssd != nil || $0.restingHR != nil }.count
            )
            ages[key] = AgeEngine.compute(dateKey: key, inputs: inputs, language: language)
        }
        ageResults = ages

        if store.days[selectedDayKey] == nil, let last = keys.last {
            selectedDayKey = last
        }

        // Update the daily snapshot for the widgets.
        let today = DayKey.today()
        let todayRecovery = recoveryResults[today]
        let todaySleep = sleepAnalyses[today]
        WidgetBridge.publish(
            recovery: todayRecovery,
            sleepPerformance: (todaySleep?.hasData == true) ? todaySleep?.performance : nil,
            strain: strainResults[today]?.strain,
            strainTarget: todayRecovery.map { StrainEngine.targetStrain(forRecovery: $0.score) },
            language: language
        )
    }

    /// Robust observed max HR (97.5th percentile) over the window's intraday HR;
    /// nil with too few samples (prevents artifact outliers).
    private static func robustMaxHR(_ window: [DayRecord]) -> Double? {
        let bpms = window.flatMap { $0.hrSamples.map(\.bpm) }
        guard bpms.count >= 300 else { return nil }
        return Stats.percentile(bpms, 0.975)
    }

    // MARK: - Actions

    func startDemo() {
        store.replaceAll(DemoData.generate(daysBack: 120, seed: 42))
        store.save()
        demoMode = true
        onboarded = true
        selectedDayKey = DayKey.today()
        lastError = nil
        recomputeAll()
    }

    func connect() async {
        lastError = nil
        let config = oauthConfig
        guard config.isValid, let scheme = config.reversedClientScheme else {
            lastError = AuthError.invalidClientID.errorDescription
            return
        }
        let pkce = PKCE()
        let state = UUID().uuidString
        guard let url = auth.authorizationURL(config: config, pkce: pkce, state: state) else {
            lastError = "Could not create the authorization URL."
            return
        }
        do {
            let callback = try await WebAuthenticator.shared.authenticate(url: url, callbackScheme: scheme)
            guard let code = GoogleAuth.extractCode(from: callback, expectedState: state) else {
                lastError = "No valid authorization code received."
                return
            }
            _ = try await auth.exchange(code: code, pkce: pkce, config: config)
            connectedAt = Date()
            if notificationsEnabled, let connectedAt {
                PulseNotifications.scheduleTokenExpiry(connectedAt: connectedAt, language: language)
                scheduleBackgroundRefresh()
            }
            if demoMode {
                store.wipe()
                demoMode = false
            }
            onboarded = true
            recomputeAll()
            await syncNow()
        } catch let error as AuthError {
            lastError = error.errorDescription
        } catch {
            let nsError = error as NSError
            let cancelled = nsError.domain == ASWebAuthenticationSessionError.errorDomain
                && nsError.code == ASWebAuthenticationSessionError.canceledLogin.rawValue
            if !cancelled {
                lastError = error.localizedDescription
            }
        }
    }

    func syncNow(daysBackOverride: Int? = nil, hrDaysBackOverride: Int? = nil) async {
        guard !syncing else { return }
        guard isConnected else {
            lastError = AuthError.notConnected.errorDescription
            return
        }
        syncing = true
        syncMessage = "Starte…"
        syncFraction = 0

        // Protect the sync against the screen lock and keep it running ~30 s
        // in the background when switching apps (partial results are
        // saved after each phase anyway).
        UIApplication.shared.isIdleTimerDisabled = true
        var bgTask: UIBackgroundTaskIdentifier = .invalid
        bgTask = UIApplication.shared.beginBackgroundTask(withName: "pulse.sync") {
            UIApplication.shared.endBackgroundTask(bgTask)
            bgTask = .invalid
        }
        defer {
            syncing = false
            UIApplication.shared.isIdleTimerDisabled = false
            if bgTask != .invalid {
                UIApplication.shared.endBackgroundTask(bgTask)
            }
        }

        let client = HealthAPIClient(auth: auth, config: oauthConfig)
        let engine = SyncEngine(client: client)

        // Phase 1: all daily metrics — then save and display immediately.
        let daily = await engine.syncDailyMetrics(
            existingDays: store.days,
            daysBack: daysBackOverride ?? daysBack
        ) { [weak self] progress in
            Task { @MainActor in
                self?.syncMessage = progress.message
                self?.syncFraction = progress.fraction * 0.55
            }
        }
        store.replaceAll(daily.updatedDays)
        store.save()
        syncLog = daily.log
        profileName = daily.profile?.displayName ?? profileName
        if sex == .unspecified, let profileSex = daily.profile?.sex, profileSex != .unspecified {
            sex = profileSex // triggers recomputeAll()
        } else {
            recomputeAll()
        }

        // Phase 2: intraday heart rate — only missing days, in parallel.
        let hr = await engine.syncIntradayHeartRate(
            existingDays: store.days,
            hrDaysBack: hrDaysBackOverride ?? hrDaysBack
        ) { [weak self] progress in
            Task { @MainActor in
                self?.syncMessage = progress.message
                self?.syncFraction = 0.55 + progress.fraction * 0.45
            }
        }
        store.replaceAll(hr.updatedDays)
        store.save()
        syncLog = daily.log + hr.log
        lastSyncAt = Date()
        recomputeAll()

        if daily.hadErrors || hr.hadErrors {
            lastError = "Sync finished with warnings – see the sync log for details."
        }

        rescheduleRoutineNotifications()
        maybeShowJournalPrompt()
    }

    func disconnect() {
        auth.disconnect()
        connectedAt = nil
        PulseNotifications.cancelTokenExpiry()
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.refreshTaskID)
    }

    func resetAll() {
        store.wipe()
        journal.wipe()
        syncLog = []
        lastSyncAt = nil
        connectedAt = nil
        demoMode = false
        onboarded = false
        profileName = nil
        lastError = nil
        PulseNotifications.cancelAll()
        recomputeAll()
    }

    // MARK: - Notifications & background sync

    func setNotifications(enabled: Bool) async {
        if enabled {
            let granted = await PulseNotifications.requestAuthorization()
            notificationsEnabled = granted
            if granted {
                if let connectedAt { PulseNotifications.scheduleTokenExpiry(connectedAt: connectedAt, language: language) }
                scheduleBackgroundRefresh()
            }
        } else {
            notificationsEnabled = false
            PulseNotifications.cancelAll()
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.refreshTaskID)
        }
    }

    /// Schedules the next background sync. iOS decides the actual
    /// time – "from early morning" is only a wish, not a guarantee.
    func scheduleBackgroundRefresh() {
        guard notificationsEnabled, isConnected else { return }
        let request = BGAppRefreshTaskRequest(identifier: Self.refreshTaskID)
        request.earliestBeginDate = Self.nextEarlyMorning()
        try? BGTaskScheduler.shared.submit(request)
    }

    /// Called by the `.backgroundTask` handler: light sync + morning notification.
    func performBackgroundRefresh() async {
        scheduleBackgroundRefresh() // schedule the next run immediately
        guard isConnected else { return }
        await syncNow(daysBackOverride: 3, hrDaysBackOverride: 1)
        guard notificationsEnabled, await PulseNotifications.isAuthorized() else { return }
        let today = DayKey.today()
        if let rec = recovery(for: today) {
            let sleepText = sleep(for: today).flatMap { $0.hasData ? "\(Fmt.hm($0.sleptMinutes)) h" : nil }
            let yesterday = DayKey.addDays(today, -1)
            let journalPending = journal.entry(for: yesterday).factors.isEmpty && store.days[yesterday] != nil
            let alertMessage = HealthMonitor.alert(records: store.chronological(upTo: today, count: 10), language: language)?.message
            PulseNotifications.postRecoverySummary(
                recovery: rec.score,
                sleep: sleepText,
                journalPending: journalPending,
                alertMessage: alertMessage,
                language: language
            )
        }
    }

    private static func nextEarlyMorning(hour: Int = 6, minute: Int = 30) -> Date {
        let cal = Calendar.current
        let now = Date()
        var comps = cal.dateComponents([.year, .month, .day], from: now)
        comps.hour = hour
        comps.minute = minute
        let target = cal.date(from: comps) ?? now.addingTimeInterval(6 * 3600)
        return target > now ? target : (cal.date(byAdding: .day, value: 1, to: target) ?? now.addingTimeInterval(6 * 3600))
    }
}
