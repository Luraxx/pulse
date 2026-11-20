import Foundation
import PulseCore

// Self-test runner: verifies the Core logic without Xcode/iOS SDK.

var failures: [String] = []

func check(_ condition: Bool, _ message: String) {
    if condition {
        print("  ✓ \(message)")
    } else {
        print("  ✗ FAILED: \(message)")
        failures.append(message)
    }
}

func section(_ name: String) {
    print("\n— \(name)")
}

func jsonDict(_ raw: String) -> [String: Any] {
    guard let data = raw.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data),
          let dict = object as? [String: Any] else {
        failures.append("Fixture not parseable")
        return [:]
    }
    return dict
}

// MARK: PKCE (RFC 7636 test vector)

section("PKCE")
let pkce = PKCE(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
check(pkce.challenge == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM", "SHA256 challenge matches RFC 7636 vector")
let freshPKCE = PKCE()
check(freshPKCE.verifier.count >= 43, "Random verifier has sufficient length")
check(freshPKCE.verifier != PKCE().verifier, "Verifiers are random")

// MARK: OAuth configuration

section("OAuth configuration")
let config = GoogleOAuthConfig(clientID: "407408718192-abc123.apps.googleusercontent.com")
check(config.reversedClientScheme == "com.googleusercontent.apps.407408718192-abc123", "Reversed client scheme correct")
check(config.redirectURI == "com.googleusercontent.apps.407408718192-abc123:/oauth2redirect", "Redirect URI correct")
check(!GoogleOAuthConfig(clientID: "kaputt").isValid, "Invalid client ID is detected")

let auth = GoogleAuth(usesKeychain: false)
if let url = auth.authorizationURL(config: config, pkce: pkce, state: "test-state") {
    let absolute = url.absoluteString
    check(absolute.hasPrefix("https://accounts.google.com/o/oauth2/v2/auth"), "Auth URL points to Google")
    check(absolute.contains("code_challenge=E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"), "Auth URL contains PKCE challenge")
    check(absolute.contains("googlehealth.sleep.readonly"), "Auth URL contains Health scopes")
    check(!absolute.contains("prompt="), "No prompt=consent (Google Health recommendation)")
} else {
    check(false, "Auth URL could not be built")
}
let callback = URL(string: "com.googleusercontent.apps.x:/oauth2redirect?state=test-state&code=4/abc")!
check(GoogleAuth.extractCode(from: callback, expectedState: "test-state") == "4/abc", "Code extraction from callback")
check(GoogleAuth.extractCode(from: callback, expectedState: "falsch") == nil, "State mismatch is rejected")
check(GoogleAuth.formEncode(["a": "b c", "x": "y+z"]) == "a=b%20c&x=y%2Bz", "Form encoding percent-encodes correctly")

// MARK: JSON extraction (Google Health formats)

section("JSON extraction")
check(JSONExtract.snakeCase("heartRateVariability") == "heart_rate_variability", "camelCase → snake_case")

let hrPoint = jsonDict(#"""
{
  "dataSource": { "device": { "displayName": "Fitbit Air" }, "platform": "FITBIT", "recordingMethod": "DERIVED" },
  "heartRate": { "sampleTime": { "physicalTime": "2026-05-12T15:59:07Z" }, "beatsPerMinute": 72 }
}
"""#)
let hrPayload = (hrPoint["heartRate"] as? [String: Any]) ?? [:]
check(JSONExtract.firstDouble(in: hrPayload, keys: ["beatsPerMinute", "bpm"]) == 72, "Heart rate value extracted")
check(JSONExtract.firstDate(in: hrPayload, keys: ["physicalTime"]) != nil, "Sample time extracted (nested)")

let civil = JSONExtract.civilDateString(from: ["year": 2026, "month": 7, "day": 5])
check(civil == "2026-07-05", "CivilDate object → yyyy-MM-dd")

let sleepPoint = jsonDict(#"""
{
  "name": "users/me/dataTypes/sleep/dataPoints/abc",
  "sleep": {
    "type": "STAGES",
    "interval": { "startTime": "2026-07-16T22:45:00Z", "endTime": "2026-07-17T06:30:00Z" },
    "stages": [
      { "type": "LIGHT", "startTime": "2026-07-16T22:45:00Z", "endTime": "2026-07-17T00:10:00Z" },
      { "type": "DEEP", "startTime": "2026-07-17T00:10:00Z", "endTime": "2026-07-17T01:20:00Z" },
      { "type": "REM", "startTime": "2026-07-17T01:20:00Z", "endTime": "2026-07-17T02:00:00Z" },
      { "type": "AWAKE", "startTime": "2026-07-17T02:00:00Z", "endTime": "2026-07-17T02:08:00Z" },
      { "type": "LIGHT", "startTime": "2026-07-17T02:08:00Z", "endTime": "2026-07-17T06:30:00Z" }
    ],
    "summary": { "minutesAsleep": 457, "minutesAwake": 8, "stagesSummary": [ { "type": "DEEP", "minutes": 70 } ] }
  }
}
"""#)
if let session = HealthAPIClient.parseSleep(sleepPoint) {
    check(session.stages.count == 5, "5 sleep stages decoded")
    check(session.minutesAsleep == 457, "minutesAsleep taken from summary")
    check(session.stages[1].stage == .deep, "DEEP → .deep gemappt")
    check(abs(session.minutesInBed - 465) < 0.01, "Time in bed = 465 min")
} else {
    check(false, "Sleep fixture could not be decoded")
}
check(HealthAPIClient.parseSleep(["sleep": ["interval": [:]]]) == nil, "Incomplete sleep data → nil instead of crash")

// Exercise: Google calls the time interval "interval" (filter interval.civil_start_time).
let exercisePoint = jsonDict(#"""
{
  "name": "users/me/dataTypes/exercise/dataPoints/xyz",
  "exercise": {
    "exerciseType": "RUNNING",
    "activityName": "Laufen",
    "interval": { "startTime": "2026-07-17T17:30:00Z", "endTime": "2026-07-17T18:15:00Z" },
    "averageHeartRate": 148,
    "calories": 430
  }
}
"""#)
if let workout = HealthAPIClient.parseExercise(exercisePoint) {
    check(workout.name == "Laufen", "Workout name from activityName")
    check(abs(workout.durationMinutes - 45) < 0.01, "Workout duration from interval = 45 min")
    check(workout.averageHR == 148, "Workout average HR decoded")
} else {
    check(false, "Exercise fixture with interval could not be decoded")
}
// Older/alternative structure "sessionTimeInterval" stays readable as a fallback.
let exerciseAlt = jsonDict(#"""
{ "exercise": { "activityName": "Rad", "sessionTimeInterval": { "startTime": "2026-07-17T08:00:00Z", "endTime": "2026-07-17T08:30:00Z" } } }
"""#)
check(HealthAPIClient.parseExercise(exerciseAlt)?.name == "Rad", "Fallback sessionTimeInterval stays readable")
check(HealthAPIClient.parseExercise(["exercise": ["interval": [:]]]) == nil, "Incomplete workout → nil instead of crash")

// MARK: DayKey

section("DayKey")
check(DayKey.addDays("2026-07-18", -1) == "2026-07-17", "addDays across day boundary")
check(DayKey.keys(from: "2026-02-27", to: "2026-03-02").count == 4, "Leap-year range (2026 not a leap year): Feb 27–Mar 2 = 4 days")
check(DayKey.distance(from: "2026-07-01", to: "2026-07-18") == 17, "Distance between keys")
if let lateEvening = DayKey.date(from: "2026-07-17")?.addingTimeInterval(23 * 3600) {
    check(DayKey.nightKey(for: lateEvening) == "2026-07-18", "11 pm sample counts toward the next day's night")
}
if let earlyMorning = DayKey.date(from: "2026-07-18")?.addingTimeInterval(5 * 3600) {
    check(DayKey.nightKey(for: earlyMorning) == "2026-07-18", "5 am sample counts toward the same day")
}

// MARK: Statistics

section("Statistics")
check(Stats.percentile([1, 2, 3, 4, 5], 0.5) == 3, "Median")
check(Stats.percentile([10], 0.05) == 10, "Percentile with a single value")
check(abs(Stats.logistic(0) - 0.5) < 1e-9, "Logistic(0) = 0.5")
if let baseline = Stats.baseline([60, 62, 64, 66, 68]) {
    check(abs(baseline.mean - 64) < 1e-9, "Baseline-Mittelwert")
    check(baseline.isReliable, "5 values count as solid")
    check(abs(baseline.z(64)) < 1e-9, "z-score at the mean = 0")
} else {
    check(false, "Baseline nil despite 5 values")
}
check(Stats.baseline([1, 2]) == nil, "Baseline needs at least 3 values")

// MARK: Languages

section("Languages (DE/EN)")
check(JournalFactor.alcohol.label(.de) == "Alkohol" && JournalFactor.alcohol.label(.en) == "Alcohol", "JournalFactor bilingual")
check(BiologicalSex.male.label(.en) == "Male", "BiologicalSex English")
check(HealthMetricKind.restingHR.label(.en) == "Resting HR" && HealthMetricKind.restingHR.unit(.en) == "bpm", "HealthMetricKind English incl. unit")
check(StrainEngine.zoneLabels(.en).count == StrainEngine.zoneLabels.count, "Zone labels: EN list complete")
// Own local inputs — fitInputs/healthRecord are not initialized yet at this point
// (main.swift top level runs sequentially; a forward access would segfault).
let langInputs = AgeInputs(
    chronoAge: 30, sex: .male,
    vo2maxValues: [52, 51, 53, 52, 54],
    rmssdValues: Array(repeating: 57, count: 10),
    restingHRValues: Array(repeating: 51, count: 10),
    sleepPerformances: [88, 90, 87, 91],
    stepsValues: [12000, 11500, 12500],
    validDayCount: 30
)
let deAge = AgeEngine.compute(dateKey: "2026-07-18", inputs: langInputs, language: .de)
let enAge = AgeEngine.compute(dateKey: "2026-07-18", inputs: langInputs, language: .en)
check(enAge.components.contains { $0.label == "Resting HR" || $0.label == "Sleep" || $0.label == "Activity" }, "AgeEngine components in English")
check(enAge.pulseAge == deAge.pulseAge, "Language only changes texts, never values")
func langHealthRecord(_ key: String, rhr: Double, resp: Double) -> DayRecord {
    var r = DayRecord(date: key)
    r.restingHR = rhr; r.respiratoryRate = resp; r.hrvRmssd = 60; r.spo2Avg = 97; r.bodyTemp = 34
    return r
}
var langAlertRecords = (0..<8).map { langHealthRecord(DayKey.addDays("2026-06-01", $0), rhr: 55, resp: 14) }
langAlertRecords.append(langHealthRecord(DayKey.addDays("2026-06-01", 8), rhr: 70, resp: 18))
if let enAlert = HealthMonitor.alert(records: langAlertRecords, language: .en) {
    check(enAlert.message.contains("outside your baseline"), "Health alert phrased in English")
} else {
    check(false, "EN health alert missing")
}

// MARK: Trend aggregation

section("Trend aggregation")
let maPairs: [(key: String, value: Double)] = (0..<10).map { (DayKey.addDays("2026-06-01", $0), Double($0)) }
let ma3 = TrendMath.movingAverage(maPairs, window: 3)
check(ma3.count == 10, "Moving average keeps the point count")
check(abs(ma3[0].value - 0) < 1e-9, "First point: mean of itself")
check(abs(ma3[2].value - 1) < 1e-9, "Window 3 over 0,1,2 → 1")
check(abs(ma3[9].value - 8) < 1e-9, "Window 3 over 7,8,9 → 8")
// Gaps: missing days are skipped, not counted as 0.
let gapPairs: [(key: String, value: Double)] = [("2026-06-01", 10), ("2026-06-03", 30)]
let maGap = TrendMath.movingAverage(gapPairs, window: 3)
check(abs(maGap[1].value - 20) < 1e-9, "Gap in window → mean only over existing values")

// 2026-07-19 was a Sunday, 2026-07-20 a Monday.
let weekPairs: [(key: String, value: Double)] = [
    ("2026-07-17", 60), ("2026-07-18", 70), ("2026-07-19", 80), // Week starting Mon 13.07.
    ("2026-07-20", 40), ("2026-07-21", 60),                     // Week starting Mon 20.07.
]
let weekly = TrendMath.weeklyMean(weekPairs)
check(weekly.count == 2, "Two calendar weeks → two points")
check(weekly[0].key == "2026-07-13" && abs(weekly[0].value - 70) < 1e-9, "Week 1: Monday key + mean 70")
check(weekly[1].key == "2026-07-20" && abs(weekly[1].value - 50) < 1e-9, "Week 2: Monday key + mean 50")

// MARK: Strain engine

section("Strain engine")
check(StrainEngine.strain(fromRaw: 0) == 0, "No load → strain 0")
let s60 = StrainEngine.strain(fromRaw: 60)
let s300 = StrainEngine.strain(fromRaw: 300)
let s900 = StrainEngine.strain(fromRaw: 900)
let s5000 = StrainEngine.strain(fromRaw: 5000)
check(s60 > 2 && s60 < 4, "Easy day ≈ 2–4 (is \(String(format: "%.1f", s60)))")
check(s300 > 9 && s300 < 12, "Solid training ≈ 9–12 (is \(String(format: "%.1f", s300)))")
check(s900 > 16 && s900 < 19, "Hard day ≈ 16–19 (is \(String(format: "%.1f", s900)))")
check(s5000 < 21, "Scale stays below 21 (is \(String(format: "%.2f", s5000)))")
check(s60 < s300 && s300 < s900 && s900 < s5000, "Strain grows monotonically with load")
// Strain target from recovery (Whoop ranges: training 14–18, easy 10–14).
let t90 = StrainEngine.targetStrain(forRecovery: 90)
let t67 = StrainEngine.targetStrain(forRecovery: 67)
let t34 = StrainEngine.targetStrain(forRecovery: 34)
check(t90 >= 17 && t90 <= 18.5, "Recovery 90 → training target (\(String(format: "%.1f", t90)))")
check(t67 >= 13 && t67 <= 14, "Recovery 67 → moderate target (\(String(format: "%.1f", t67)))")
check(t34 >= 6 && t34 <= 8, "Recovery 34 → recovery target (\(String(format: "%.1f", t34)))")
check(StrainEngine.targetStrain(forRecovery: 5) >= 3, "Target lower bound 3")
check(StrainEngine.targetStrain(forRecovery: 99) <= 18.5, "Target upper bound 18.5 (never all-out)")
check(t90 > t67 && t67 > t34, "Target grows monotonically with recovery")

check(StrainEngine.zoneIndex(for: 0.1) == nil, "Below zone 0 → no load")
check(StrainEngine.zoneIndex(for: 0.5) == 2, "50 % HRR → zone 3 (index 2)")
check(StrainEngine.zoneIndex(for: 0.99) == 5, "99 % HRR → max zone")

// Rest time: samples near resting HR produce no active zone time, but restMin.
let strainBase = DayKey.date(from: "2026-07-17")!
let restSamples = (0..<10).map { HRSample(t: strainBase.addingTimeInterval(Double($0) * 60), bpm: 60) }
let restAcc = StrainEngine.accumulate(samples: restSamples, restingHR: 58, maxHR: 190)
check(restAcc.zones.reduce(0, +) == 0, "Samples near resting HR → no active zone time")
check(restAcc.restMin >= 9, "Rest time is recorded (\(Int(restAcc.restMin)) min)")
let restResult = StrainEngine.dayStrain(
    record: { var r = DayRecord(date: "2026-07-17"); r.hrSamples = restSamples; return r }(),
    restingHR: 58,
    config: StrainConfig(age: 30)
)
check(restResult.strain < 1, "Pure rest day → strain near 0")
check(restResult.trackedMinutes >= 9, "Recorded time (rest+active) visible")

// MARK: Demo data + engines end-to-end

section("Demo data & engines")
let demoDays = DemoData.generate(daysBack: 120, seed: 42)
check(demoDays.count == 120, "120 demo days generated")
let sortedKeys = demoDays.keys.sorted()

let strainConfig = StrainConfig(age: 30)
var strainByDay: [String: Double] = [:]
for (key, record) in demoDays {
    let result = StrainEngine.dayStrain(record: record, restingHR: record.restingHR, config: strainConfig)
    strainByDay[key] = result.strain
    if result.strain < 0 || result.strain > 21 {
        check(false, "Strain outside 0–21 on \(key): \(result.strain)")
    }
}
check(strainByDay.values.allSatisfy { $0 >= 0 && $0 <= 21 }, "All daily strains in 0–21")
let maxStrain = strainByDay.values.max() ?? 0
let avgStrain = strainByDay.values.reduce(0, +) / Double(strainByDay.count)
check(maxStrain > 10, "Hard days reach strain > 10 (max \(String(format: "%.1f", maxStrain)))")
check(avgStrain > 3 && avgStrain < 16, "Average strain plausible (\(String(format: "%.1f", avgStrain)))")

let sleepConfig = SleepEngineConfig()
let sleepAnalyses = SleepEngine.analyze(days: demoDays, config: sleepConfig, strainByDay: strainByDay)
check(sleepAnalyses.count == 120, "Sleep analysis for all days")
for (key, analysis) in sleepAnalyses {
    if analysis.needMinutes < 300 || analysis.needMinutes > 620 {
        check(false, "Sleep need outside plausibility on \(key): \(analysis.needMinutes)")
    }
    if analysis.debtAfterMinutes < 0 || analysis.debtAfterMinutes > sleepConfig.maxDebtMinutes {
        check(false, "Sleep debt outside limits on \(key)")
    }
    if let consistency = analysis.consistency, consistency < 0 || consistency > 100 {
        check(false, "Consistency outside 0–100 on \(key)")
    }
    if analysis.performance < 0 || analysis.performance > 100 {
        check(false, "Sleep performance outside 0–100 on \(key)")
    }
}
check(true, "Need/debt/consistency/performance in valid ranges")
let withStages = sleepAnalyses.values.filter { !$0.stageMinutes.isEmpty }
check(withStages.count == 120, "All nights have stage minutes")

var recoveryScores: [Int] = []
for key in sortedKeys.suffix(60) {
    guard let record = demoDays[key] else { continue }
    let history = sortedKeys.filter { $0 < key }.compactMap { demoDays[$0] }
    let result = RecoveryEngine.compute(
        dateKey: key,
        today: record,
        history: history,
        sleepPerformance: sleepAnalyses[key]?.performance
    )
    if let result {
        recoveryScores.append(result.score)
        if result.score < 1 || result.score > 99 {
            check(false, "Recovery outside 1–99 on \(key): \(result.score)")
        }
        let expectedZone: RecoveryZone = result.score >= 67 ? .green : (result.score >= 34 ? .yellow : .red)
        if result.zone != expectedZone {
            check(false, "Zone mapping wrong on \(key)")
        }
        let weightSum = result.components.reduce(0) { $0 + $1.weight }
        if abs(weightSum - 1) > 0.001 {
            check(false, "Component weights don't sum to 1 on \(key)")
        }
    } else {
        check(false, "Recovery nil despite data on \(key)")
    }
}
check(recoveryScores.count == 60, "Recovery computed for the last 60 days")
let recoveryRange = (recoveryScores.min() ?? 0)...(recoveryScores.max() ?? 0)
check(recoveryRange.upperBound - recoveryRange.lowerBound >= 20, "Recovery varies realistically (\(recoveryRange))")

if let lastKey = sortedKeys.last, let lastRecord = demoDays[lastKey] {
    let history = sortedKeys.dropLast().compactMap { demoDays[$0] }
    let statuses = HealthMonitor.evaluate(today: lastRecord, history: Array(history))
    check(statuses.count == HealthMetricKind.allCases.count, "Health Monitor returns all metrics")
    check(statuses.allSatisfy { $0.state != .noData }, "Demo data: no metric without data")
    let rhrStatus = statuses.first { $0.kind == .restingHR }
    check(rhrStatus?.lowerBound != nil && rhrStatus?.upperBound != nil, "Resting HR has a baseline band")
}

// MARK: Workout strain

section("Workout strain")
var workoutStrainChecked = false
for key in sortedKeys.suffix(28) {
    guard let record = demoDays[key], let workout = record.workouts.first else { continue }
    if let strain = StrainEngine.workoutStrain(workout: workout, daySamples: record.hrSamples, restingHR: record.restingHR, config: strainConfig) {
        check(strain > 0 && strain <= 21, "Workout-Strain (\(workout.name), \(key)) in 0–21: \(String(format: "%.1f", strain))")
        workoutStrainChecked = true
        break
    }
}
check(workoutStrainChecked, "At least one workout strain computed")

// MARK: Age engine (Pulse Age)

section("Age norms")
// Inversion hits the anchor points again.
check(abs(AgeNorms.fitnessAge(vo2max: 48.0, sex: .male) - 25) < 1.0, "VO₂max 48 (m) → fitness age ≈ 25")
check(abs(AgeNorms.fitnessAge(vo2max: 40.3, sex: .male) - 45) < 1.0, "VO₂max 40.3 (m) → fitness age ≈ 45")
check(abs(AgeNorms.fitnessAge(vo2max: 30.9, sex: .female) - 45) < 1.0, "VO₂max 30.9 (f) → fitness age ≈ 45")
// Monotonicity: fitter ⇒ younger.
check(AgeNorms.fitnessAge(vo2max: 55, sex: .male) < AgeNorms.fitnessAge(vo2max: 35, sex: .male), "Higher VO₂max ⇒ younger fitness age")
let fitVeryHigh = AgeNorms.fitnessAge(vo2max: 65, sex: .male)
check(fitVeryHigh >= 20 && fitVeryHigh <= 25, "Very high VO₂max is clamped to ≥20 (\(String(format: "%.0f", fitVeryHigh)))")
check(abs(AgeNorms.hrvAge(rmssd: 46) - 35) < 1.5, "RMSSD 46 → HRV age ≈ 35")
check(AgeNorms.hrvAge(rmssd: 60) < AgeNorms.hrvAge(rmssd: 25), "Higher HRV ⇒ younger HRV age")
// Sex shifts the curve.
check(AgeNorms.vo2max(age: 40, sex: .male) > AgeNorms.vo2max(age: 40, sex: .female), "VO₂max norm: men > women at the same age")

section("Age engine")
let fitInputs = AgeInputs(
    chronoAge: 30, sex: .male,
    vo2maxValues: [52, 51, 53, 52, 54],
    rmssdValues: Array(repeating: 57, count: 10),
    restingHRValues: Array(repeating: 51, count: 10),
    sleepPerformances: [88, 90, 87, 91],
    stepsValues: [12000, 11500, 12500],
    validDayCount: 30
)
let fitResult = AgeEngine.compute(dateKey: "2026-07-18", inputs: fitInputs)
if let pulseAge = fitResult.pulseAge, let delta = fitResult.deltaYears {
    check(pulseAge >= 15 && pulseAge <= 95, "Fit 30-year-old: Pulse Age within limits (\(String(format: "%.0f", pulseAge)))")
    check(delta < 0, "Fit person is biologically younger (Δ \(String(format: "%.0f", delta)))")
    check(!fitResult.vo2maxEstimated, "Measured VO₂max is preferred (not estimated)")
} else {
    check(false, "Pulse Age nil despite full data")
}

let unfitInputs = AgeInputs(
    chronoAge: 30, sex: .male,
    vo2maxValues: Array(repeating: 30, count: 5),
    rmssdValues: Array(repeating: 25, count: 10),
    restingHRValues: Array(repeating: 72, count: 10),
    sleepPerformances: [60, 63, 58],
    stepsValues: [3000, 2800, 3200],
    validDayCount: 30
)
let unfitResult = AgeEngine.compute(dateKey: "2026-07-18", inputs: unfitInputs)
check((unfitResult.deltaYears ?? 0) > 0, "Unfit person is biologically older (Δ \(String(format: "%.0f", unfitResult.deltaYears ?? 0)))")
check((fitResult.pulseAge ?? 0) < (unfitResult.pulseAge ?? 0), "Fit < unfit in Pulse Age")

// Calibration gate: too few days ⇒ no value.
let earlyInputs = AgeInputs(
    chronoAge: 30, sex: .male,
    vo2maxValues: [50, 51, 52],
    rmssdValues: Array(repeating: 55, count: 8),
    restingHRValues: Array(repeating: 52, count: 8),
    validDayCount: 10
)
let earlyResult = AgeEngine.compute(dateKey: "2026-07-18", inputs: earlyInputs)
check(earlyResult.pulseAge == nil, "Under 14 valid days: no Pulse Age yet")
check(earlyResult.calibrating, "Early phase is marked as calibrating")
check(earlyResult.calibrationHave == 10, "Calibration progress counts valid days")

// Double-counting guard: without a measured VO₂max it is estimated AND
// resting HR is then NOT added again as a correction.
let estimatedInputs = AgeInputs(
    chronoAge: 40, sex: .male,
    vo2maxValues: [],
    rmssdValues: Array(repeating: 40, count: 10),
    restingHRValues: Array(repeating: 58, count: 12),
    observedMaxHR: 185,
    sleepPerformances: [80, 82],
    stepsValues: [9000, 8500],
    validDayCount: 30
)
let estimatedResult = AgeEngine.compute(dateKey: "2026-07-18", inputs: estimatedInputs)
check(estimatedResult.vo2maxEstimated, "Without a measurement: VO₂max is estimated via HR ratio")
check(estimatedResult.vo2max != nil, "Estimated VO₂max is present")
check(!estimatedResult.components.contains { $0.key == "rhr" }, "With estimated VO₂max no separate resting HR correction (no double counting)")
check(estimatedResult.components.contains { $0.key == "fitness" }, "Fitness component also present in the estimate path")

// End-to-end on demo data (measured VO₂max ~50).
let ageWindow = sortedKeys.suffix(30).compactMap { demoDays[$0] }
let ageSleepPerf = sortedKeys.suffix(30).compactMap { key -> Double? in
    guard let a = sleepAnalyses[key], a.hasData else { return nil }
    return a.performance
}
let demoAgeInputs = AgeInputs(
    chronoAge: 30, sex: .male,
    vo2maxValues: ageWindow.compactMap { $0.vo2max },
    rmssdValues: ageWindow.compactMap { $0.hrvRmssd },
    restingHRValues: ageWindow.compactMap { $0.restingHR },
    sleepPerformances: ageSleepPerf,
    stepsValues: ageWindow.compactMap { $0.steps.map(Double.init) },
    validDayCount: ageWindow.filter { $0.hrvRmssd != nil || $0.restingHR != nil }.count
)
let demoAgeResult = AgeEngine.compute(dateKey: sortedKeys.last!, inputs: demoAgeInputs)
check(demoAgeResult.vo2max != nil, "Demo: VO₂max present")
if let demoPulseAge = demoAgeResult.pulseAge {
    check(demoPulseAge >= 15 && demoPulseAge <= 45, "Demo: Pulse Age plausible (\(String(format: "%.0f", demoPulseAge)))")
} else {
    check(false, "Demo: Pulse Age nil despite 30 days")
}

// MARK: Journal & correlation

section("Journal & correlation")
var journalEntries: [String: JournalEntry] = [:]
var journalRecovery: [String: Int] = [:]
for i in 0..<12 {
    let day = DayKey.addDays("2026-06-01", i)
    let alcohol = i % 2 == 0
    let factors: Set<JournalFactor> = alcohol ? [.alcohol] : []
    journalEntries[day] = JournalEntry(date: day, factors: factors)
    journalRecovery[DayKey.addDays("2026-06-01", i + 1)] = alcohol ? 45 : 75
}
let insights = JournalEngine.insights(entries: journalEntries, recoveryByDay: journalRecovery)
if let alc = insights.first(where: { $0.factor == .alcohol }) {
    check(alc.delta < -15, "Alcohol clearly lowers next-day recovery (Δ \(Int(alc.delta)))")
    check(alc.daysWith >= 5 && alc.daysWithout >= 5, "Both groups above Whoop minimum sample size (5/5)")
    check(alc.confidence == .solid, "Clear, consistent effect → solid")
} else {
    check(false, "Alcohol insight missing despite data")
}
check(!insights.contains { $0.factor == .sick }, "Factor without entries yields no insight")
check(JournalFactor.allCases.contains(.sex), "Sex is present as a journal factor")

// Noisy tiny effect → only a trend, not solid.
var noisyEntries: [String: JournalEntry] = [:]
var noisyRecovery: [String: Int] = [:]
// Group means almost equal (~68), but high spread → no real effect.
let noisyScores = [55, 58, 80, 77, 60, 63, 75, 74, 65, 70, 72, 68]
for i in 0..<12 {
    let day = DayKey.addDays("2026-05-01", i)
    noisyEntries[day] = JournalEntry(date: day, factors: i % 2 == 0 ? [.lateMeal] : [])
    noisyRecovery[DayKey.addDays("2026-05-01", i + 1)] = noisyScores[i]
}
if let noisy = JournalEngine.insights(entries: noisyEntries, recoveryByDay: noisyRecovery).first(where: { $0.factor == .lateMeal }) {
    check(noisy.confidence == .emerging, "Small effect in strong noise → only a trend (Δ \(String(format: "%.1f", noisy.delta)), SE \(String(format: "%.1f", noisy.standardError)))")
} else {
    check(false, "Noise insight missing despite 6/6 days")
}

check(!JournalEngine.assessmentReady(recoveryByDay: journalRecovery), "Under 28 recovery days: monthly assessment not ready yet")
var manyRecoveries: [String: Int] = [:]
for i in 0..<30 { manyRecoveries[DayKey.addDays("2026-05-01", i)] = 70 }
check(JournalEngine.assessmentReady(recoveryByDay: manyRecoveries), "From 28 recovery days: monthly assessment ready")

let tmpJournal = FileManager.default.temporaryDirectory.appendingPathComponent("pulse-journal-\(UUID().uuidString)")
let jStore = JournalStore(directory: tmpJournal)
jStore.toggle(.alcohol, on: "2026-07-18")
check(jStore.isSet(.alcohol, on: "2026-07-18"), "Toggle sets factor")
check(jStore.save(), "Journal save successful")
let jReload = JournalStore(directory: tmpJournal)
check(jReload.isSet(.alcohol, on: "2026-07-18"), "Journal survives roundtrip")
try? FileManager.default.removeItem(at: tmpJournal)

// MARK: Sleep debt (no compounding, cap per night)

section("Sleep debt")
func debtNight(_ key: String, minutes: Double) -> DayRecord {
    var r = DayRecord(date: key)
    guard let dayStart = DayKey.date(from: key) else { return r }
    let wake = dayStart.addingTimeInterval(7 * 3600)
    let bed = wake.addingTimeInterval(-minutes * 60)
    r.sleepSessions = [SleepSession(id: "debt-\(key)", start: bed, end: wake, minutesAsleep: minutes, minutesAwake: 0)]
    return r
}
// Base 456, no strain: night 1 disaster (60 min), then exactly base, then base+60.
let debtDays: [String: DayRecord] = [
    "2026-06-01": debtNight("2026-06-01", minutes: 60),
    "2026-06-02": debtNight("2026-06-02", minutes: 456),
    "2026-06-03": debtNight("2026-06-03", minutes: 516),
]
let debtAnalyses = SleepEngine.analyze(days: debtDays, config: SleepEngineConfig())
check(abs((debtAnalyses["2026-06-01"]?.debtAfterMinutes ?? -1) - 180) < 0.01, "Disaster night: increase per night capped at 180 min (not immediately max)")
check(abs((debtAnalyses["2026-06-02"]?.debtAfterMinutes ?? -1) - 180) < 0.01, "Slept exactly base → debt stays constant (no compounding)")
check(abs((debtAnalyses["2026-06-03"]?.debtAfterMinutes ?? -1) - 120) < 0.01, "60 min oversleep → debt drops by 60")
check((debtAnalyses["2026-06-02"]?.needMinutes ?? 0) > 456, "Displayed need still includes debt repayment")

// MARK: Recovery calibration without HRV

section("Recovery calibration")
func rhrOnly(_ key: String, rhr: Double) -> DayRecord {
    var r = DayRecord(date: key)
    r.restingHR = rhr
    return r
}
let rhrHistory = (0..<10).map { rhrOnly(DayKey.addDays("2026-06-01", $0), rhr: 54 + Double($0 % 3)) }
let noHrvResult = RecoveryEngine.compute(
    dateKey: "2026-06-11",
    today: rhrOnly("2026-06-11", rhr: 55),
    history: rhrHistory,
    sleepPerformance: 85
)
check(noHrvResult != nil, "Recovery computable without HRV")
check(noHrvResult?.calibrating == false, "Missing HRV does not block calibration (10 RHR nights suffice)")
let shortHistory = Array(rhrHistory.prefix(3))
let earlyNoHrv = RecoveryEngine.compute(
    dateKey: "2026-06-05",
    today: rhrOnly("2026-06-05", rhr: 55),
    history: shortHistory,
    sleepPerformance: 85
)
check(earlyNoHrv?.calibrating == true, "Under 5 RHR nights still calibrating")

// MARK: Bedtime recommendation

section("Bedtime recommendation")
var wakeComps = DateComponents()
wakeComps.year = 2026; wakeComps.month = 6; wakeComps.day = 10; wakeComps.hour = 6; wakeComps.minute = 45
let wake645 = Calendar.current.date(from: wakeComps)!
let bedRec = SleepEngine.bedtimeRecommendation(
    currentDebtMinutes: 0, strainToday: 3, recentWakeTimes: [wake645, wake645, wake645]
)
check(abs(bedRec.projectedNeedMinutes - 456) < 5, "Without debt/strain ≈ base need (\(Int(bedRec.projectedNeedMinutes)))")
if let bed = bedRec.recommendedBedtimeMinutes {
    check(abs(bed - 1389) < 3, "Bedtime = wake time − need (\(Int(bed)/60):\(String(format: "%02d", Int(bed)%60)))")
} else {
    check(false, "No bedtime despite wake times")
}
let bedRecHard = SleepEngine.bedtimeRecommendation(currentDebtMinutes: 120, strainToday: 16, recentWakeTimes: [wake645])
check(bedRecHard.projectedNeedMinutes > bedRec.projectedNeedMinutes, "Debt + hard day raise the need")

// MARK: Health warning

section("Health warning")
func healthRecord(_ key: String, rhr: Double, resp: Double) -> DayRecord {
    var r = DayRecord(date: key)
    r.restingHR = rhr; r.respiratoryRate = resp; r.hrvRmssd = 60; r.spo2Avg = 97; r.bodyTemp = 34
    return r
}
var stableRecords = (0..<8).map { healthRecord(DayKey.addDays("2026-06-01", $0), rhr: 55, resp: 14) }
check(HealthMonitor.alert(records: stableRecords) == nil, "Stable values → no warning")
stableRecords.append(healthRecord(DayKey.addDays("2026-06-01", 8), rhr: 70, resp: 18))
if let multi = HealthMonitor.alert(records: stableRecords) {
    check(multi.kinds.count >= 2, "Several abnormal values → warning with ≥2 metrics")
} else {
    check(false, "Warning missing despite two abnormal values")
}
var streakRecords = (0..<7).map { healthRecord(DayKey.addDays("2026-07-01", $0), rhr: 55, resp: 14) }
streakRecords.append(healthRecord(DayKey.addDays("2026-07-01", 7), rhr: 68, resp: 14))
streakRecords.append(healthRecord(DayKey.addDays("2026-07-01", 8), rhr: 69, resp: 14))
if let streak = HealthMonitor.alert(records: streakRecords) {
    check(streak.kinds == [.restingHR], "Single metric over 2 days → streak warning")
} else {
    check(false, "Streak warning missing")
}

// MARK: Sync helpers

section("Sync helpers")
let base = DayKey.date(from: "2026-07-17")!
let rawSamples = (0..<120).map { i in
    SamplePoint(time: base.addingTimeInterval(Double(i) * 5), value: 60 + Double(i % 10))
}
let downsampled = SyncEngine.downsampleToMinutes(rawSamples)
check(downsampled.count == 10, "600 s at 5 s resolution → 10 minute buckets")
check(downsampled.allSatisfy { $0.bpm >= 60 && $0.bpm <= 70 }, "Downsampling averages correctly")

let nightSamples = [
    SamplePoint(time: DayKey.date(from: "2026-07-16")!.addingTimeInterval(23.5 * 3600), value: 55),
    SamplePoint(time: DayKey.date(from: "2026-07-17")!.addingTimeInterval(3 * 3600), value: 65),
]
let grouped = SyncEngine.groupByNight(nightSamples)
check(grouped["2026-07-17"]?.count == 2, "Night grouping combines evening + morning")

// Rate-limit backoff (Google: 300 requests/min/user).
check(HealthAPIClient.retryDelay(attempt: 0, retryAfterHeader: "7") == 7, "Retry-After header is respected")
check(HealthAPIClient.retryDelay(attempt: 0, retryAfterHeader: nil) == 2, "Without header: exponential from 2 s")
check(HealthAPIClient.retryDelay(attempt: 2, retryAfterHeader: nil) == 8, "Exponential increase (attempt 3 → 8 s)")
check(HealthAPIClient.retryDelay(attempt: 9, retryAfterHeader: nil) == 60, "Backoff capped at 60 s")
check(HealthAPIClient.retryDelay(attempt: 0, retryAfterHeader: "120") == 60, "Retry-After capped at 60 s")

// Incremental HR sync: checked past days are skipped.
let oldKey = DayKey.addDays(DayKey.today(), -3)
var oldFull = DayRecord(date: oldKey)
oldFull.hrSamples = [HRSample(t: DayKey.date(from: oldKey)!, bpm: 60)]
oldFull.hrSyncedAt = Date() // checked after end of day
check(SyncEngine.isIntradayComplete(oldFull, dayKey: oldKey), "Old day with data, checked after end of day → skipped")
var oldEmpty = DayRecord(date: oldKey)
oldEmpty.hrSyncedAt = Date() // empty, but checked
check(SyncEngine.isIntradayComplete(oldEmpty, dayKey: oldKey), "Old EMPTY day, checked once → NOT loaded again")
let yesterdayKey = DayKey.addDays(DayKey.today(), -1)
var yest = DayRecord(date: yesterdayKey)
yest.hrSamples = [HRSample(t: DayKey.date(from: yesterdayKey)!, bpm: 60)]
yest.hrSyncedAt = Date()
check(!SyncEngine.isIntradayComplete(yest, dayKey: yesterdayKey), "Yesterday is always reloaded (delayed watch data)")
var todayDay = DayRecord(date: DayKey.today())
todayDay.hrSamples = [HRSample(t: Date(), bpm: 60)]
todayDay.hrSyncedAt = Date()
check(!SyncEngine.isIntradayComplete(todayDay, dayKey: DayKey.today()), "Today never counts as complete")
var oldUnstamped = DayRecord(date: oldKey)
oldUnstamped.hrSamples = [HRSample(t: DayKey.date(from: oldKey)!, bpm: 60)]
check(!SyncEngine.isIntradayComplete(oldUnstamped, dayKey: oldKey), "Without hrSyncedAt stamp it is loaded")
check(!SyncEngine.isIntradayComplete(nil, dayKey: oldKey), "Missing day is loaded")

// Spike filter: isolated artifact spike is smoothed, ramp stays.
let spikeSamples = [60.0, 62, 175, 61, 63].enumerated().map {
    HRSample(t: base.addingTimeInterval(Double($0.offset) * 60), bpm: $0.element)
}
let deSpiked = SyncEngine.removeSpikes(spikeSamples)
check(deSpiked[2].bpm < 100, "Isolated HR spike (175) is smoothed → \(Int(deSpiked[2].bpm))")
let rampSamples = [60.0, 105, 150, 175].enumerated().map {
    HRSample(t: base.addingTimeInterval(Double($0.offset) * 60), bpm: $0.element)
}
check(SyncEngine.removeSpikes(rampSamples).map(\.bpm) == rampSamples.map(\.bpm), "Monotonic increase stays untouched")

// MARK: Store roundtrip

section("MetricsStore")
let tempDir = FileManager.default.temporaryDirectory
    .appendingPathComponent("pulse-selftest-\(UUID().uuidString)")
let store = MetricsStore(directory: tempDir)
store.merge(Array(demoDays.values))
check(store.days.count == 120, "Store contains 120 days")
check(store.save(), "Save successful")

let reloaded = MetricsStore(directory: tempDir)
check(reloaded.days.count == 120, "Reload returns 120 days")
if let lastKey = sortedKeys.last {
    let original = store.days[lastKey]
    let restored = reloaded.days[lastKey]
    check(original?.hrvRmssd == restored?.hrvRmssd, "HRV survives roundtrip")
    // ISO-8601 encoding rounds dates to whole seconds → compare tolerantly.
    let hrStampDelta = abs((original?.hrSyncedAt?.timeIntervalSince1970 ?? -1) - (restored?.hrSyncedAt?.timeIntervalSince1970 ?? -2))
    check(hrStampDelta < 1, "hrSyncedAt survives roundtrip (second precision)")
    check(original?.sleepSessions.count == restored?.sleepSessions.count, "Sleep sessions survive roundtrip")
    check((restored?.hrSamples.count ?? 0) > 0, "HR samples of the last day preserved")
}
let historyCheck = reloaded.history(before: sortedKeys.last!, days: 30)
check(historyCheck.count == 30, "history(before:) returns 30 days")
try? FileManager.default.removeItem(at: tempDir)

// MARK: Result

print("")
if failures.isEmpty {
    print("ALL TESTS PASSED ✅")
    exit(0)
} else {
    print("\(failures.count) TEST(S) FAILED ❌")
    for failure in failures {
        print("  – \(failure)")
    }
    exit(1)
}
