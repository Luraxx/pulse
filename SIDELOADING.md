# Installing Pulse without a Mac (sideloading)

Every [release](https://github.com/Luraxx/pulse/releases) ships a ready-made
`Pulse.ipa`. With a sideloading tool you can install it using only your own Apple ID,
from Windows, Linux or macOS, without Xcode. It is the same app as the Xcode build,
built by GitHub Actions straight from the tagged source
([`ipa.yml`](.github/workflows/ipa.yml)). Nothing about the app changes: still on
device, still your own Google Cloud project, no server.

> **Community-supported, best effort.** Pulse is developed and tested with Xcode.
> Sideloading goes through third-party tools that re-sign the app with your Apple ID,
> so problems with signing, refreshing or app-ID limits belong to those tools (see
> their docs). Bugs in Pulse itself are welcome as [issues](../../issues/new/choose)
> as usual; please mention which tool you installed with.

---

## What you need

- iPhone on iOS 17+ with the Google Health app, Fitbit Air paired
- A sideloading tool, for example
  - [SideStore](https://sidestore.io), set up from a computer with
    [iloader](https://github.com/nab138/iloader) (Windows, macOS, Linux)
  - [AltStore](https://altstore.io) with AltServer
  - [iloader](https://github.com/nab138/iloader) on its own, which can install any IPA
    directly
- An Apple ID (a free one works)
- A Google account and your own Google Cloud project ([`SETUP.md`](SETUP.md), Part 1)

## 1. Install the IPA

1. Download `Pulse.ipa` from the
   [latest release](https://github.com/Luraxx/pulse/releases/latest/download/Pulse.ipa).
2. Install it:
   - **SideStore / AltStore:** open the app on your iPhone → *My Apps* → **+** → pick
     `Pulse.ipa`.
   - **iloader:** connect the iPhone, sign in with your Apple ID and install the IPA
     from your computer.
3. If the tool asks whether to keep the app extension, keep it if you want the
   home-screen widget. It uses one extra app ID.

## 2. Create the Google client with *your* bundle ID

The sideloading tool gives the app a bundle ID unique to your Apple ID, usually
`net.dehlwes.pulse.<TEAMID>`. Create the Google iOS client with exactly that one:

1. Open Pulse and tap **Connect Google Health**. The screen shows **Bundle ID of this
   app**, long-press to copy it.
2. Follow [`SETUP.md`](SETUP.md), Part 1. In step 5 (iOS client ID) enter the bundle
   ID from Pulse instead of `net.dehlwes.pulse`.
3. Paste the client ID into Pulse and sign in.

Nothing else differs from the Xcode build. No Google setup yet? **Demo mode** on the
welcome screen works right away.

## Limits worth knowing

- **7-day signing (free Apple ID).** The app stops launching after 7 days unless it is
  refreshed. SideStore refreshes on the iPhone, AltStore through AltServer, with iloader
  you install again. Your data stays as long as you don't delete the app. A paid Apple
  Developer account extends this to a year.
- **App limits (free Apple ID).** At most 3 sideloaded apps can be active at once (the
  sideloading app itself counts) and 10 new app IDs can be registered per 7 days.
  Pulse uses 2 app IDs: the app and the widget.
- **Google testing mode.** Sign-in expires after 7 days, one tap on *Reconnect*. Same as
  the Xcode build, see [`SETUP.md`](SETUP.md).
- **Widget.** Supported. The tools register their own App Group for your team and Pulse
  picks it up. If the widget stays empty, open Pulse once and pull to refresh; if it is
  still empty, open an issue with the tool and its version.
- **Background sync.** Works as in the Xcode build: iOS decides when, usually overnight
  or in the morning.
- **Updates.** Install the new `Pulse.ipa` over the existing app with the same tool and
  Apple ID; data and Google connection are kept. Installing with a different Apple ID
  gives a new bundle ID, so it becomes a separate app that needs its own Google client.
