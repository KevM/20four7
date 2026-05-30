# Televista — Ambient YouTube Channels (iOS/iPadOS Client) — Design

**Date:** 2026-05-30
**Status:** Approved design, ready for implementation planning
**Scope of this document:** Sub-project #1 — the iOS/iPadOS client app.

---

## 1. Summary

Televista is a lean-back, TV-like app for watching always-on **ambient YouTube
livestreams** (fireplaces, rain, lofi radio, aquariums, nature, cityscapes,
space). Content is a **curated, remotely-updatable catalog** plus **user-added
channels**. The experience is a hybrid of browsing a **Channel Guide** and
**channel-surfing** in fullscreen.

This document covers **Sub-project #1**: the iOS/iPadOS client with local
persistence. Accounts/sync and a native tvOS target are explicitly deferred to
later sub-projects but the design is shaped so they slot in without a rewrite.

## 2. Goals & Non-Goals

**Goals**
- Compliant, reliable playback of ambient YouTube livestreams on iPhone/iPad.
- Hybrid navigation: browse a tag-filtered Guide, then surf up/down while watching.
- Ambient features: sleep timer, clock/dim overlay, best-effort audio-only,
  auto-resume of last channel.
- Curated catalog updatable without an app release; users can add their own channels.
- Tag-native data model (editorial + user tags now; derived tags later).
- Architecture that quarantines YouTube fragility and is ready for CloudKit sync
  and a tvOS target.

**Non-Goals (this sub-project)**
- Accounts, Sign in with Apple, CloudKit sync (Sub-project #2).
- Derived/"Popular" tags and leaderboard (Sub-project #2).
- Native tvOS app (Sub-project #3).
- Live YouTube search, comments/social features, Android/web.

## 3. Platform & Compliance Context (the constraint that drives everything)

The **only ToS-compliant way** to play YouTube content in a third-party app is
YouTube's official **IFrame Player API** — a web component, not a raw stream.

- **iOS/iPadOS:** `WKWebView` exists, so the iframe player works. ✅ This is the target.
- **tvOS:** `WKWebView` does **not** exist; `AVPlayer` cannot play YouTube URLs;
  extracting stream URLs violates ToS and is fragile. A native tvOS player has no
  sanctioned path today, so tvOS is deferred. ❌
- **Living-room path now:** **AirPlay** from the iOS app to an Apple TV (the iframe
  player's video routes through AVPlayer, so the system AirPlay picker works).
- **Audio-only/background** is what YouTube Premium gates; via the iframe player it
  is ToS-gray and iOS may suspend it. Shipped **best-effort, not guaranteed.**

Decision: **iOS/iPadOS first, architected so a tvOS target can be added later.**
Distribution: **App Store**, with accounts/sync planned via **CloudKit + Sign in
with Apple** in Sub-project #2.

## 4. Architecture

Native **SwiftUI** app (chosen over UIKit/React Native for cross-Apple-platform UI
reuse, first-class CloudKit support, and clean App Store review).

Independently-testable units, communicating through well-defined interfaces:

- **`PlayerService` (protocol)** — the swappable playback abstraction and the most
  important boundary in the app. iOS implementation wraps the YouTube iframe player
  in a `WKWebView`. A future tvOS implementation conforms to the same protocol.
  *Everything else talks to the protocol, never to the web view.*
- **`ChannelStore`** — merges the remote curated catalog with user-added channels;
  exposes the current lineup; owns dedupe and ordering. Persists user data locally.
- **`PlaybackController`** — app-level "what's playing now" state: surf
  next/previous, sleep timer, audio-only, auto-resume. Drives `PlayerService`.
- **`RemoteConfig`** — fetches/caches the curated catalog (see §6) with a bundled
  fallback so the app is never empty.
- **UI layer** — `GuideView`, `PlayerView` (fullscreen + overlays), `AddChannelView`,
  `SettingsView`.

**Data flow (one-way):** stores/controllers hold state → SwiftUI views render →
user actions call controllers → `PlayerService` executes playback.

## 5. Player Core

**`PlayerService` protocol (minimal, platform-agnostic):**
- Commands: `load(channel)`, `play()`, `pause()`, `setVolume()`, `mute()/unmute()`.
- State publisher: `.loading / .playing / .paused / .ended / .error(reason)`.
- Events: `playbackStarted`, `ended`, `embeddingDisallowed`, `streamOffline`.

**iOS implementation — `WebViewPlayerService`:**
- Hosts a `WKWebView` loading a small local HTML page embedding YouTube's
  **IFrame Player API** (`YT.Player`) — the sanctioned, compliant method.
- **JS ⇄ Swift bridge** via `WKScriptMessageHandler`: Swift controls playback with
  `evaluateJavaScript`; JS posts player state/errors back to Swift.
- Player configured `playsinline`, controls hidden, `modestbranding`; a custom
  SwiftUI overlay sits on top so it reads as an ambient screen, not a YouTube page.
- **AirPlay** comes nearly free via the system route picker (iframe video routes
  through AVPlayer).

**Realities baked into the design (not bugs):**
- Some videos have embedding disabled (error 101/150) → surfaced as
  `embeddingDisallowed`; validated at add-time for user channels and in catalog
  validation for curated ones.
- Livestreams can go offline → `streamOffline` + graceful "offline" card with
  one-tap surf to the next channel.
- Unavoidable bits of YouTube player chrome can't be fully removed — accepted.
- Audio-only/background is best-effort with explicit caveats (see §3).

**Why this boundary matters:** the entire app is testable against a **mock
`PlayerService`** (no network/YouTube), and a tvOS player is a drop-in. The
fragile code is quarantined behind one interface.

## 6. Curated Catalog Delivery (remote, versioned, URL + naming convention)

Two files at a configurable **base URL** (any static host/CDN). The base URL is a
**build-time constant per environment** (e.g. staging vs prod).

```
https://<base>/televista/channels-manifest.json   ← stable entry point, fetched first
https://<base>/televista/catalog-v{N}.json         ← versioned catalog payload
```

**`channels-manifest.json`:**
```json
{
  "schemaVersion": 1,
  "catalogVersion": 7,
  "catalogUrl": "https://<base>/televista/catalog-v7.json",
  "minAppVersion": "1.0.0",
  "publishedAt": "2026-05-30T00:00:00Z"
}
```

**Behavior**
- App fetches the manifest on launch and on pull-to-refresh; it is the only
  hardcoded URL (everything else is indirection).
- If `catalogVersion` > cached → download `catalogUrl`, validate, swap in, cache.
  Catalog files are **content-addressed by version** (`catalog-v{N}.json`): publish
  a new file, bump the manifest. No overwriting live files → no corruption from a
  half-upload; **rollback = point the manifest back at the previous version.**
- `schemaVersion` lets the app reject catalogs it's too old to parse; `minAppVersion`
  nudges upgrades; unknown future fields are ignored (forward-compatible).
- **HTTP caching:** honor `ETag`/`Last-Modified` with `If-None-Match` (cheap 304s);
  short TTL to avoid hammering on every launch.
- **Resilience ladder:** live manifest → last good cached catalog → bundled catalog.
  App is never empty, even offline on first launch.

**Update workflow:** upload `catalog-v{N+1}.json`, edit manifest to reference it.

**Catalog JSON shape (sketch):**
```json
{
  "schemaVersion": 1,
  "tags": {
    "fireplace": { "name": "Fireplace", "symbol": "flame", "sortOrder": 10 },
    "rain":      { "name": "Rain", "symbol": "cloud.rain", "sortOrder": 20 }
  },
  "channels": [
    {
      "id": "uuid-stable",
      "title": "Cozy Fireplace 4K",
      "youTubeVideoID": "abc123",
      "thumbnailURL": null,
      "isLiveExpected": true,
      "tagIds": ["fireplace"]
    }
  ]
}
```
Tags are defined once in a top-level dictionary and referenced by `tagIds` on each
channel (small file, rename-safe).

## 7. Data Model (local now, CloudKit-ready)

**`Channel`** — `id` (stable UUID), `title`, `youTubeVideoID` (or live/channel id),
`thumbnailURL?`, `source: .curated | .user`, `isLiveExpected: Bool`, `dateAdded`,
`tags: [Tag]`.

**`Tag`** — `id`, `name`, `symbol?`, `kind`:
- **`.editorial`** — defined in the curated catalog; the navigation backbone
  (e.g. Fireplace, Rain, 4K, No Music). Add/rename via catalog publish, no app update.
- **`.user`** — created by the user on their added/favorited channels; private;
  CloudKit-synced later.
- **`.derived`** — *not stored on channels*; computed (e.g. "Popular", "Trending").
  Absent in #1; produced by CloudKit aggregation in #2. The **leaderboard is a
  ranked view of a derived tag.**

**Per-channel user state** — `isFavorite`, `customOrder`, user tag assignments,
keyed by `channelID`, kept **separate** from channel definitions. This separation
is what makes sync clean: only user channels + user state sync; curated channels
come from remote config.

**Settings** — auto-resume, audio-only, default sleep timer, clock overlay on/off,
dim level. **Last-watched channel** persisted for auto-resume.

**Persistence — SwiftData** (chosen over Core Data: less boilerplate, official
CloudKit mirroring path). Stored locally: user channels, per-channel user state,
settings, last-watched. **Not** in SwiftData: the curated catalog (owned by
`RemoteConfig`). **Identity:** `userID` field present but nil in #1; populated by
Sign in with Apple in #2 so existing local data adopts cleanly.

## 8. Screens

1. **Guide (home)** — tag chips across the top (editorial tags + a "★ My Tags"
   bucket; multi-select filtering), grid of channels with live badges and favorite
   stars, tap to watch. (If auto-resume is on, the app boots into the Player instead.)
2. **Player (fullscreen)** — iframe player under an auto-hiding SwiftUI overlay:
   live/channel badge (top), **surf ▲/▼** (right edge), bottom control bar
   (play/pause, volume, favorite, sleep timer, dim, audio-only). Large **clock**
   appears when the clock overlay is enabled.
3. **Add Channel** — paste URL or `@handle` → **validate at add-time** (embeddable?
   live?) → assign tags (including new user tags) → save as `.user`. Validation
   keeps dead/non-embeddable links out of the player.
4. **Settings** — ambient prefs (auto-resume, audio-only [best-effort], default
   sleep timer, clock overlay, dim level). Account / "Sign in with Apple" row
   present but stubbed as "Later" for Sub-project #2.

URL parsing supports `watch?v=`, `youtu.be`, `@handle`, and live URLs.

## 9. Error Handling & Edge Cases

YouTube is the fragile surface; failure is treated as normal:
- **Embedding disabled (101/150)** — rejected at add-time (user) / catalog
  validation (curated); if hit live, "can't play here" card + one-tap surf.
- **Stream offline/ended** — graceful card + auto-surf. Live badges are best-effort
  (mark `isLiveExpected`, verify lazily; no constant polling of YouTube).
- **Network loss** — Guide renders from cache + local user channels; player shows
  retry. App is fully browsable offline; only playback needs network.
- **Catalog fetch failure / malformed / bad schema** — resilience ladder keeps the
  last good catalog; invalid catalogs rejected.
- **WKWebView/iframe failure** — surfaced via `PlayerService.state = .error(reason)`;
  never a blank screen.
- **Invalid Add-Channel input** — inline error for unrecognized URLs.

## 10. Testing

- **Unit (against a mock `PlayerService`, no YouTube):** `ChannelStore`
  (curated+user merge, dedupe), `RemoteConfig` (version compare, ETag/304, fallback
  ladder, schema rejection), tag filtering, URL parsing, sleep-timer & auto-resume
  logic.
- **Snapshot/UI tests:** Guide and overlay states (live/offline/error, empty, dimmed).
- **Manual/integration smoke:** real `WebViewPlayerService` against known-good live
  streams (the part that can't be reliably automated).
- TDD applied to data/config/parsing logic; the web view is not unit-tested.

## 11. Sub-project Roadmap

- **#1 (this spec):** iOS/iPadOS client, local persistence, iframe player behind
  `PlayerService`, Guide + surf, ambient features, versioned curated catalog,
  user-added channels + add-time validation, editorial + user tags, AirPlay.
- **#2:** Sign in with Apple + CloudKit sync; anonymous play-count aggregation →
  derived "Popular"/"Trending" tags → leaderboard.
- **#3:** Native tvOS target (revisit a viable playback path; reuse `PlayerService`
  boundary and SwiftUI views).
