# Harden the remote-catalog → player trust boundary

**Date:** 2026-06-03
**Status:** Approved — ready for implementation plan

## Problem

The curated catalog is, by design, remotely updatable without an App Store
release (`RemoteConfig` fetches it from `Config.catalogBaseURL`). That makes
every catalog field untrusted input that can change *after* App Review. Today
two gaps let a malicious or merely broken catalog reach code:

1. **JS injection (HIGH).** `CatalogValidator` never checks `youTubeVideoID`
   format, and `WebViewPlayerService` interpolates that string straight into a
   JavaScript call:

   ```swift
   evaluate("loadVideo('\(channel.youTubeVideoID)', \(channel.isLiveExpected), false, false, \(startTime))")
   ```

   A catalog entry like `youTubeVideoID = "x'); <arbitrary js> //"` executes in
   the `https://20four7.fm.rodeo` origin the player page runs as. The user-add
   path is already safe (it validates via `YouTubeURLParser.isValidVideoID`); the
   remote path skips that check.

2. **Unbounded catalog host (MEDIUM).** `RemoteConfig.fetchFromNetwork` follows
   `manifest.catalogUrl` to any HTTPS host with no allowlist, so a tampered
   manifest can redirect catalog fetching off the trusted origin.

## Goals

- Make it structurally impossible for a catalog value to execute as JavaScript.
- Reject malformed catalogs at runtime (fail-closed → cache → bundled).
- Confine catalog fetching to the trusted host.
- Catch bad catalogs in CI before they ship (fail-fast), with a single source of
  validation truth in `CatalogValidator`.

## Scope

In scope: the HIGH and MEDIUM findings above.

Out of scope (tracked separately): `SECURITY.md` placeholder text, the README's
reference to a `BackgroundLineupScanner` that doesn't exist, silent
`try? context.save()` handling in `LocalStore`, and `ChannelMerger` ordering.

## Design

### Change 1 — Shared video-ID rule + catalog validation

- Promote `YouTubeURLParser.isValidVideoID` from `private` to an internal
  `static` method so it is the single definition of a valid ID (11 characters of
  `[A-Za-z0-9_-]`). The user-add path and the catalog path then validate
  identically.
- `CatalogValidator.validate` gains a per-channel check: any channel whose
  `youTubeVideoID` fails `isValidVideoID` throws a new
  `CatalogValidationError.invalidVideoID(channelID:videoID:)`. This is
  whole-catalog rejection, consistent with the existing `unsupportedSchema` /
  `noChannels` / `unknownTag` behavior, so `RemoteConfig` falls back to the
  last-good cache and then the bundled catalog.

### Change 2 — JS boundary hardening (callAsyncJavaScript)

- In `WebViewPlayerService`, the two `loadVideo(...)` call sites (the immediate
  `load(channel:startTime:)` path and the deferred `apiReady` path) switch from
  string interpolation to:

  ```swift
  webView.callAsyncJavaScript(
      "loadVideo(videoId, isLiveExpected, false, false, startSeconds)",
      arguments: ["videoId": id,
                  "isLiveExpected": isLiveExpected,
                  "startSeconds": startTime],
      in: nil,
      contentWorld: .page)
  ```

  WebKit binds the arguments as real JavaScript values, so no string assembly
  occurs and a value can never break out of a literal. The call is async, so it
  is wrapped in a `Task` (the current `load()` is synchronous fire-and-forget).
  `contentWorld: .page` matches the world where `player.html`'s `loadVideo` is
  defined.
- The other `evaluate()` calls (`play`, `pause`, `setVolume`, `setMuted`,
  `setAspectCover`) are unchanged — they carry no untrusted strings (volume is
  clamped to an `Int`, the rest are `Bool`s).
- `player.html`'s `loadVideo` signature is unchanged.

This is defense in depth: Change 1 keeps a bad ID out of the system, and Change 2
makes the call injection-proof even if an unvalidated value ever reaches it.

### Change 3 — Manifest catalogUrl host restriction

- `RemoteConfig.fetchFromNetwork` validates that `manifest.catalogUrl.host`
  equals `baseURL.host` before fetching the catalog; a mismatch throws and the
  fallback ladder takes over.
- Implemented as a small pure helper on `CatalogValidator` (keeping all
  validation in one place) so it is unit-testable in isolation, e.g.
  `validateManifest(_:expectedHost:)`. The expected host derives from the
  `baseURL` already injected into `RemoteConfig`.

### Change 4 — Tests (single source of validation truth)

- **Unit tests** (`CatalogValidatorTests`): reject a malformed video ID; accept a
  valid one; reject a manifest whose `catalogUrl` host differs from the base
  host; accept a matching host.
- **Real-file gate** (new test file): using the test source file's `#filePath`
  to locate the repo root, load and validate the actual deploy/ship artifacts
  through `CatalogValidator`:
  - `Sources/Resources/catalog-fallback.json`
  - `web/channels-catalog.json`
  - `web/channels-manifest.json`

  This validates the real files in place (not bundle copies), so a bad catalog in
  a pull request fails CI before merge. The repo-relative-path approach is chosen
  deliberately over packaging the files as hermetic bundle resources: the point of
  the test is to gate the exact file that gets deployed, and the test always runs
  inside a repo checkout (local and CI).
- **Fixture update** (`RemoteConfigTests`): the manifest fixtures currently use
  `catalogUrl` host `cdn.example.com` while `baseURL` is `20four7.fm.rodeo`. They
  change to a matching `20four7.fm.rodeo` host so they satisfy the new host check.
  `CatalogModelsTests`' decode-only manifest test is unaffected (it does not run
  the host validation).

## Files touched

- `Sources/Core/YouTubeURLParser.swift` — expose `isValidVideoID`.
- `Sources/Catalog/CatalogValidator.swift` — video-ID check, new error case,
  manifest host helper.
- `Sources/Catalog/RemoteConfig.swift` — enforce manifest host before fetch.
- `Sources/Player/WebViewPlayerService.swift` — `callAsyncJavaScript` for
  `loadVideo`.
- `Tests/CatalogValidatorTests.swift` — new cases.
- `Tests/RemoteConfigTests.swift` — fixture host update.
- New test file (e.g. `Tests/CatalogFilesTests.swift`) — real-file validation
  gate.

## Verification

- `xcodebuild test -scheme 20Four7 -destination 'platform=iOS Simulator,name=iPhone 17'`
  passes, including the new cases and the real-file gate.
- Manual: confirm a channel still loads and plays in the player WebView after the
  `callAsyncJavaScript` switch (the web view is not covered by unit tests).
