# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and this project follows
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **Ready-made `Pulse.ipa`** on every GitHub release, built by GitHub Actions, for
  installing with SideStore, AltStore or iloader without a Mac. Guide in
  [`SIDELOADING.md`](SIDELOADING.md) ([#1](https://github.com/Luraxx/pulse/issues/1)).
- The *Connect Google Health* screen shows the app's bundle ID, which the Google iOS
  client has to match.

### Fixed

- The home-screen widget keeps working after sideloading: the App Group is taken from
  what the signing tool registered instead of a fixed name.
- The app version follows the release tag instead of a fixed 1.0.

## [0.1.0] - 2026-07-22

First public release. Everything runs on device, no server and no subscription.

### Metrics

- **Recovery score (1–99 %)** from HRV, resting heart rate, sleep performance and
  respiration, each scored against a personal 30-day baseline.
- **Strain (0–21)** from heart-rate-reserve zones on a logarithmic scale, including
  strain per workout and a daily strain target derived from recovery.
- **Sleep** with need, debt, performance, consistency, efficiency, a flowing stage
  hypnogram and a bedtime recommendation for tonight.
- **Pulse Age**, a biological age estimate anchored on VO₂max (measured by Google
  Health, or estimated through the heart-rate ratio method) mapped against
  sex- and age-specific reference norms, blended with an HRV-based age and capped
  corrections from resting HR, sleep and activity.
- **Health monitor** for resting HR, HRV, respiration, SpO₂ and skin temperature inside
  a personal baseline band, with a proactive warning when several values drift or one
  value stays off for days.
- **Journal** with behaviour factors and correlations against the next day's recovery,
  following Whoop's assessment thresholds (5 days on and 5 days off per factor,
  monthly view from 28 recovery days) and labelled solid or trend.
- **Trends** over 7, 30 and 90 days, with resolution adapting to the range: daily
  values, 7-day averages, and weekly means for the long view.

### App

- Two home-screen widgets: recovery ring (small) and a daily overview with three rings
  (medium).
- Background sync with a morning recovery notification, a bedtime reminder, health
  warnings and a heads-up before the Google connection expires.
- Customizable Today page: modules can be reordered and hidden.
- English and German, switchable in the app without a restart.
- Demo mode with 120 days of realistic sample data, no Fitbit required.

### Under the hood

- Built against the Google Health API v4, which replaces the Fitbit Web API being shut
  down in September 2026. Tolerant decoding with candidate keys and read-variant
  fallback, plus a per-metric sync log.
- Two-phase sync: daily metrics first (saved and displayed immediately), then intraday
  heart rate. Completed days are skipped on later syncs and requests are throttled to
  stay under Google's per-user rate limit.
- OAuth with PKCE, no client secret. Tokens in the keychain, all data as JSON in
  Application Support.
- Self-test suite covering the metric core, runnable without Xcode.

### Known limitations

- The Google Cloud project stays in testing mode for personal use, so the sign-in
  expires every 7 days and has to be renewed with one tap.
- Not distributed through the App Store. Build it yourself with Xcode; a free Apple ID
  works but the build expires after 7 days.
- Sleep-derived values only appear after a night wearing the band, and Pulse Age needs
  roughly 30 days before it leaves the calibrating state.
- The in-app sync log is still German only.

[Unreleased]: https://github.com/Luraxx/pulse/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/Luraxx/pulse/releases/tag/v0.1.0
