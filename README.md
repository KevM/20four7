# 20Four7

A lean-back, TV-like iOS/iPadOS app for watching always-on **ambient YouTube
livestreams** — fireplaces, rain, lofi radio, aquariums, nature, cityscapes,
space. Content is a **curated, remotely-updatable catalog** plus your own
**user-added channels**. The experience blends browsing a **Channel Guide** with
**channel-surfing** in fullscreen.

## Features

- **Ambient playback** of YouTube livestreams via YouTube's official IFrame
  Player API (the only ToS-compliant embedding path).
- **Hybrid navigation** — browse a tag-filtered Guide, then surf ▲/▼ while watching.
- **Ambient extras** — sleep timer, clock/dim overlay, auto-resume of the last
  channel, best-effort audio-only.
- **Curated catalog** updatable without an App Store release, with a bundled
  fallback so the app is never empty (live → cached → bundled resilience ladder).
- **User channels** — paste a URL or `@handle`, validated at add-time, tagged,
  and stored locally.
- **Tag-native data model** — editorial tags (from the catalog) and private user
  tags.
- **AirPlay** to an Apple TV comes nearly free via the system route picker.

## Architecture

Native **SwiftUI**, built around independently-testable units that communicate
through well-defined interfaces:

- **`PlayerService`** (protocol) — the swappable playback abstraction and the
  most important boundary in the app. The iOS implementation
  (`WebViewPlayerService`) wraps the YouTube IFrame player in a `WKWebView`;
  everything else talks to the protocol, never the web view. This quarantines
  YouTube's fragility behind one interface and makes the whole app testable
  against a `MockPlayerService`.
- **`ChannelStore`** — merges the remote curated catalog with user-added
  channels; owns dedupe and ordering; persists user data locally.
- **`PlaybackController`** — app-level "what's playing now" state: surf
  next/previous, sleep timer, audio-only, auto-resume.
- **`RemoteConfig`** — fetches/caches the versioned curated catalog with a
  bundled fallback.
- **UI** — `GuideView`, `PlayerView` (fullscreen + overlays), `AddChannelView`,
  `SettingsView`.

Persistence uses **SwiftData** (local-only today; structured so CloudKit sync
and a tvOS target can be added later without a rewrite).

See [`docs/superpowers/specs/`](docs/superpowers/specs/) for the full design.

## Requirements

- Xcode 16+ (Swift 6)
- iOS / iPadOS 17.0+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

## Getting started

The Xcode project is generated from [`project.yml`](project.yml) and is not
checked in. Generate it, then open and run:

```sh
xcodegen generate
open 20Four7.xcodeproj
```

Set your own signing team in Xcode (Signing & Capabilities) before building to a
device.

### Catalog configuration

The curated catalog base URL is a build-time constant in
[`Sources/App/Config.swift`](Sources/App/Config.swift) and defaults to a
placeholder (`cdn.example.com`). Point it at your own static host that serves:

```
<base>/channels-manifest.json   ← stable entry point, fetched first
<base>/catalog-v{N}.json         ← versioned catalog payload
```

A bundled [`catalog-fallback.json`](Sources/Resources/catalog-fallback.json)
ships with the app so it works offline on first launch.

## Tests

```sh
xcodebuild test -scheme 20Four7 -destination 'platform=iOS Simulator,name=iPhone 16'
```

Data, config, and parsing logic are covered by unit tests against a mock player
(no network or YouTube required). The web view is exercised by manual smoke
tests, not unit tests.

## License

[MIT](LICENSE)
