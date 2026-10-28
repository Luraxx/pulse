# Pulse setup and methodology

Full setup guide, scoring methodology and Google Health data-type mapping.
For the short version see [`README.md`](README.md).

> **Not affiliated with WHOOP, Google or Fitbit.** "Whoop-style" describes the *kind*
> of metrics (recovery / strain / sleep readiness), not a connection. Not a medical
> device, see [Disclaimer](#disclaimer). Licensed under **Apache-2.0**
> ([`LICENSE`](LICENSE), [`NOTICE`](NOTICE)).

---

## Why the Google Health API (and not the Fitbit Web API)?

The classic **Fitbit Web API shuts down in September 2026**. Google replaces it with
the **Google Health API** (`https://health.googleapis.com/v4`) using Google OAuth 2.0.
The Fitbit Air syncs into the **Google Health app** anyway, so Pulse is built directly
against the new API. Sources:

- https://developers.google.com/health/about (overview, sunset date)
- https://developers.google.com/health/setup (cloud setup)
- https://developers.google.com/health/scopes (scopes)
- https://developers.google.com/health/endpoints (endpoints)
- https://blog.google/products-and-platforms/devices/fitbit/fitbit-air/ (Fitbit Air)

Because the API is new (v4, launched May 2026) and not every field name is finalized,
Pulse decodes **tolerantly** (candidate keys, read-variant fallback) and logs every
metric individually in the in-app **sync log** (under "More"). A single missing data
type never blocks the rest.

---

## Requirements

- iPhone on iOS 17+ with the Google Health app, Fitbit Air paired
- Mac with **Xcode 16+**, or no Mac at all: sideload the ready-made IPA, see
  [`SIDELOADING.md`](SIDELOADING.md)
- `xcodegen` (`brew install xcodegen`), only needed if you change `project.yml`
- A Google account, the same one used in the Google Health app

---

## Part 1: Google Cloud setup (one-time, ~10 minutes)

Every user runs their own Google Cloud project. There is no shared backend or API key
in this repository.

1. **Create a project:** [console.cloud.google.com](https://console.cloud.google.com),
   new project, for example `pulse-personal`.
2. **Enable the API:** [API library](https://console.developers.google.com/apis/library/health.googleapis.com),
   pick **Google Health API**, then *Enable*.
3. **OAuth consent screen** (Google Auth Platform, Branding/Audience):
   - User type **External**, publishing status **Testing**
   - Under **Audience → Test users** add your own Google address.
4. **Grant scopes** (Google Auth Platform → **Data Access** → "Add or remove scopes",
   search for "Google Health API"). These four read scopes:
   - `…/auth/googlehealth.health_metrics_and_measurements.readonly`
   - `…/auth/googlehealth.sleep.readonly`
   - `…/auth/googlehealth.activity_and_fitness.readonly`
   - `…/auth/googlehealth.profile.readonly`
5. **Create an iOS client ID:** APIs & Services → **Credentials** →
   *Create Credentials* → *OAuth client ID* → application type **iOS** → bundle ID
   matching the one in `project.yml` (default `net.dehlwes.pulse`, change it to your
   own reverse-domain id when you fork). Sideloaded the IPA? Then use the bundle ID
   that Pulse shows on its *Connect Google Health* screen, the sideloading tool
   changes it. Copy the generated client ID, it looks like
   `1234567890-abc….apps.googleusercontent.com`. No client secret is needed (PKCE).

> **Testing mode note:** while the project sits in "Testing", refresh tokens expire
> after **7 days**. Pulse surfaces this as a "Reconnect" hint, one tap and you are set.
> Publishing the project would require Google verification for the restricted health
> scopes, which is not worth it for personal use.

---

## Part 2: Build and run on your iPhone

```bash
open Pulse.xcodeproj
```

> Important: open **`Pulse.xcodeproj`**, not the folder and not `Package.swift`.
> Opening the folder makes Xcode show only the SwiftPM schemes (`PulseCore`,
> `pulse-selftest`), which are macOS test targets and cannot be installed on an
> iPhone. Make sure the **Pulse** scheme is selected in the toolbar. The project file
> is committed; you only need `xcodegen generate` after changing `project.yml`.

In Xcode: target **Pulse** → *Signing & Capabilities* → pick your personal team (a
free Apple ID works) → connect the iPhone → ▶︎ Run.

**In the app:** tap "Connect Google Health", paste the client ID, sign in through the
system browser, done. The first sync pulls 60 days of history (configurable), after
that pull-to-refresh is enough. No Google setup? Start **Demo mode** for 120 days of
realistic sample data.

> With a free Apple ID the build expires after 7 days and has to be re-installed from
> Xcode. A paid Apple Developer account extends this to a year.

---

## Project structure

```
pulse/
├── Pulse.xcodeproj      # generated project, open this to build
├── project.yml          # xcodegen definition (regenerate only after changes)
├── App/                 # iOS-specific: SwiftUI, OAuth browser flow, assets
│   ├── PulseApp.swift / AppModel.swift (central @Observable model)
│   ├── Auth/WebAuthenticator.swift    (ASWebAuthenticationSession)
│   └── UI/              # dashboard, detail pages, trends, health, settings,
│                        # onboarding, charts, theme
├── Core/                # platform-neutral, no UIKit/SwiftUI
│   ├── Models/          # DayRecord, SleepSession, Workout, MetricsStore, Journal
│   ├── Metrics/         # RecoveryEngine, StrainEngine, SleepEngine, AgeEngine,
│   │                    # HealthMonitor
│   ├── API/             # GoogleAuth (PKCE, Keychain), HealthAPIClient, JSONExtract
│   ├── Sync/SyncEngine.swift
│   ├── Demo/DemoData.swift
│   └── Package.swift    # exposes Core as a library for the self-tests
├── PulseWidget/         # home-screen widgets (App Group)
└── SelfTest/            # standalone SwiftPM package
    └── Sources/pulse-selftest/main.swift
```

**Run the self-tests without Xcode** (PKCE against the RFC-7636 vector, DTO decoding
with Google Health fixtures, every metric engine end-to-end on demo data, store
roundtrip):

```bash
cd SelfTest && swift run pulse-selftest
```

> The self-tests live in a **separate sub-package** on purpose. That way the project
> root has no `Package.swift`, so Xcode cannot accidentally open the folder as a Swift
> package and the play button always builds the app instead of the test runner.

---

## How the scores are built

### Recovery (1–99 %)

| Component | Weight | Method |
| --- | --- | --- |
| HRV (nightly RMSSD) | 40 % | ln-transformed, z-score vs. 30-day baseline, logistic curve |
| Resting HR | 25 % | z-score inverted, logistic curve |
| Sleep | 25 % | sleep performance of the previous night |
| Respiration | 10 % | penalty only when elevated above baseline |

Penalties: SpO₂ minimum below 90 % (−7), temperature above +1.8 SD (−5).
Zones follow Whoop: **≥ 67 green**, 34–66 yellow, below 34 red. Missing components are
re-weighted; with fewer than 5 nights of baseline the app shows "calibrating".

### Strain (0–21)

Time in **heart-rate-reserve** zones (Karvonen; max HR from Tanaka `208 − 0.7 × age`
or set manually) is summed with weights (zones from 20 % HRR, weights 0.5 to 11) and
mapped logarithmically: `strain = 21 × (1 − e^(−load/450))`.
Calibration: easy day ≈ 2–4, solid training ≈ 10, hard day ≈ 18.
Without intraday HR a fallback uses workout average HR plus steps.

The **daily strain target** (the white tick on the ring) comes from your recovery:
`target = 0.2 × recovery`, capped at 3 to 18.5. This mirrors the published Whoop
ranges (training days roughly 14–18, easy days 10–14, red recovery clearly below).

### Sleep

`need = base (default 7:36 h, configurable) + 30 % of sleep debt + up to 45 min strain
bonus (from strain 8 the previous day)`.
Debt accumulates when you undersleep (capped at 5 h), oversleeping pays it back.
Consistency is the deviation of bed and wake times vs. the last 4 nights.
The bedtime recommendation projects tonight's need onto your habitual wake time.

### Pulse Age (biological age)

The score estimates how "old" your body looks physiologically, so it can land below or
above your real age. Implementation: [AgeEngine.swift](Core/Metrics/AgeEngine.swift).

1. **Backbone: VO₂max → fitness age.** VO₂max is the strongest single predictor of
   all-cause mortality (Mandsager, *JAMA Netw Open* 2018, 122,007 people; each 1-MET
   increase means roughly 13–15 % lower mortality risk). Pulse prefers the VO₂max
   **measured** by Google Health (`daily-vo2-max`). If it is missing, it is estimated
   through the **heart-rate ratio method** (Uth et al. 2004:
   `VO₂max ≈ 15.3 × HRmax / HRrest`, HRmax from an observed max or Nes/HUNT
   `211 − 0.64 × age`). The value is translated into an age through the **FRIEND**
   reference norms (50th percentile, sex-specific; Kaminsky, *Mayo Clin Proc* 2015).
2. **HRV → HRV age.** Nightly RMSSD against age-typical reference values.
3. Both equivalent ages are averaged with weights (**VO₂max 0.7 / HRV 0.3**).
4. **Capped corrections** from resting HR (+10 bpm ≈ hazard ratio 1.09 for mortality,
   Zhang *CMAJ* 2016), sleep performance and activity (max ± 5 years combined).

Against double counting: the resting-HR correction is skipped when VO₂max was
**estimated**, because the resting HR already sits inside that estimate. The score
appears after roughly **30 days** of measurements (provisional from 14), before that
it shows "calibrating". Age and sex (settings under "More") select the reference
curves. **Orientation, not a medical finding.**

Sources: [Mandsager 2018](https://jamanetwork.com/journals/jamanetworkopen/fullarticle/2707428) ·
[FRIEND/Kaminsky 2015](https://pmc.ncbi.nlm.nih.gov/articles/PMC4919021/) ·
[Uth 2004](https://pubmed.ncbi.nlm.nih.gov/14624296/) ·
[Zhang 2016](https://www.cmaj.ca/content/188/3/E53)

### Journal correlations

Behaviour factors (alcohol, late caffeine, stress, and so on) are compared against the
**next day's** recovery. Following Whoop's Monthly Performance Assessment rules, a
factor needs at least **5 days checked and 5 days unchecked** before a correlation is
shown, and the monthly view unlocks at **28 recovery days**. Each result is labelled
"solid" (difference larger than twice its standard error) or "trend". Correlation, not
proof.

---

## Data-type mapping (Google Health API v4)

| Metric | dataType (URL) | Payload key | Note |
| --- | --- | --- | --- |
| Heart rate intraday | `heart-rate` | `heartRate` | ~5 s resolution, reduced to 1 min |
| HRV | `heart-rate-variability` | `heartRateVariability` | nightly mean; fallback `daily-heart-rate-variability` |
| Sleep | `sleep` | `sleep` | sessions with `stages[]` + `summary`, time in `interval` |
| Respiration | `daily-respiratory-rate` | `dailyRespiratoryRate` | daily value (`date` filter), `breathsPerMinute` |
| SpO₂ | `oxygen-saturation` | `oxygenSaturation` | average + minimum per night |
| Temperature | `daily-sleep-temperature-derivations` | `dailySleepTemperatureDerivations` | nightly skin temperature (`nightlyTemperatureCelsius`) |
| Resting HR | `daily-resting-heart-rate` | `dailyRestingHeartRate` | daily value; fallback: 5th percentile of night HR |
| VO₂max | `daily-vo2-max` | `dailyVo2Max` | cardio fitness (ml/kg/min); fallback: HR-ratio estimate |
| Steps | `steps` | `steps` | interval samples summed per day |
| Workouts | `exercise` | `exercise` | filtered via `interval.civil_start_time` (civil time, no Z) |

Per type the client tries `…:reconcile` → `list` (range filter) → `list` (start filter
only) and remembers the variant that worked. If Google renames a type you will see it
in the **sync log** and only need to adjust the strings in
[SyncEngine.swift](Core/Sync/SyncEngine.swift).

Syncing runs in two phases: all daily metrics first (fast, saved and displayed
immediately), then intraday heart rate, which is the expensive part (~17k samples per
day, paginated). Completed days are skipped on later syncs, and all requests are
throttled to stay under Google's limit of 300 requests per minute per user.

---

## Troubleshooting

- **"Sign-in expired, please reconnect"**: normal in testing mode (7 days), just
  reconnect.
- **HTTP 403 during sync**: the Google Health API is not enabled in your cloud project,
  or the scope was not added on the Data Access page.
- **`access_denied` at login**: your address is missing under *Audience → Test users*.
- **Individual metrics empty**: check the sync log. The data type may not be populated
  for the Fitbit Air yet, or it is named differently (adjust the mapping table above).
  Sleep-derived values (HRV, respiration, SpO₂, temperature) only appear after you have
  actually slept wearing the band.
- **HTTP 429 during sync**: rate limit. The client backs off automatically and retries,
  the sync just takes a bit longer.
- **Widget does not build / signing error**: the widget (`PulseWidget`) uses an
  **App Group** to share the score with the app. Xcode handles this with automatic
  signing, but with a **free Apple ID** you may have to select your team once for
  **both** targets (Pulse and PulseWidget) and confirm the App Group. If it keeps
  failing you can remove the widget with `git revert` of the widget commit, the rest of
  the app is unaffected.
- **Background sync is not punctual**: expected. iOS runs `BGAppRefreshTask`
  opportunistically (usually at night or in the morning), not on demand.

---

## Contributing

This is a personal hobby project, shared as-is. Issues and pull requests are welcome
but may be answered slowly. Found a bug or a wrong number? Open an issue with the
relevant part of the sync log and what you expected.

By contributing you agree that your changes are licensed under Apache-2.0. There is
intentionally no analytics, telemetry or server component, please keep it that way.
Core logic changes should come with a matching check in `SelfTest`.

---

## Disclaimer

- **Not a medical device.** Pulse is for personal, informational use only. All scores
  (recovery, strain, sleep, Pulse Age, health monitor) are orientations, not diagnoses.
  They are not clinically validated and must not be used for medical decisions. If you
  feel unwell, talk to a doctor, not an app.
- **No affiliation.** WHOOP is a trademark of WHOOP, Inc.; Google, Fitbit and Google
  Health are trademarks of Google LLC. This project is independent and neither
  affiliated with nor endorsed by any of them. Product names are used purely
  descriptively. The metric methodology comes from publicly published research (cited
  above), not from any company's proprietary algorithms.
- **Your own Google Cloud project.** There is no shared backend access or API key in
  this repository (PKCE, no secret). Everyone creates their own Google Cloud project
  and remains subject to Google's API terms.
- **No warranty.** Provided "AS IS", without warranty of any kind (see the License).

## License

**Apache-2.0**, see [`LICENSE`](LICENSE) and [`NOTICE`](NOTICE). Permissive (free to
use, modify and redistribute, including commercially) with an explicit patent grant and
a trademark clause.
