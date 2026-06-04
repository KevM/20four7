# Resume Session State & Background Pause — Design

**Date:** 2026-06-04
**Status:** Approved

## Goal

Make the app remember and restore **what the user was doing**, and stop audio
from leaking when the app leaves the foreground.

Concretely:

1. When the app is backgrounded (swipe to springboard, switch apps, lock),
   **pause playback** and remember the session. Transient `.inactive` overlays
   (Control Center, Notification Center, app-switcher peek, call banners) do
   **not** pause — only a real `.background` transition does.
2. On **cold relaunch**, restore the session state but **do not auto-play** — land
   on the Guide — *unless* `Resume playing` is ON **and** a video was actively
   playing when the app last left the foreground.
3. The same gate governs **warm foreground return**: resume only if
   `Resume playing` is ON and it was playing when they left.
4. Auto-surf is a first-class session mode: if the user was auto-surfing a tag,
   resuming restores auto-surf of that tag, starting on the exact channel they
   left on, then continuing to surf.

This supersedes the prior one-line "gate `lastWatched` on `userInitiated`" fix.

## Unified Rule

> A video auto-plays — on warm foreground return *or* cold relaunch — **if and
> only if** `Resume playing` (`autoResume`) is ON **and** a video was actively
> playing when the app last left the foreground. Otherwise it stays paused
> (warm) or lands on the Guide (cold).

`wasPlaying` is **intent-based**: `playing != nil && !controller.isManuallyPaused`.
So a user-paused or sleep-timer-paused video does not auto-resume; a buffering
one does.

## Current State

- **`autoResume`** defaults to `false`
  (`Sources/Persistence/PersistenceModels.swift`), toggled by
  "Auto-resume last channel" in `SettingsView`.
- **`maybeAutoResume()`** (`Sources/UI/RootView.swift`) sleeps 500ms, refreshes,
  then unconditionally replays `lastWatchedChannelID` as a single channel if
  `autoResume` is on. It has no concept of session mode (single vs auto-surf)
  and no `wasPlaying` gate.
- **Tag filter** (`selectedTagIDs`) is already persisted and restored at store
  init (`ChannelStore.setupInitialLineup`), so after launch
  `store.filteredChannels` already reflects the surfed tag.
- **Interval** comes from `settings.defaultAutoSurfMinutes` (already persisted).
- **`onChannelChanged`** (`Sources/App/AppEnvironment.swift`) currently persists
  `lastWatched` and increments play count. (A prior fix in this branch gated both
  on `userInitiated`; this design reworks that closure.)
- **Scene phase** is observed only in `PlayerView`, which resumes on `.active`
  when `!isManuallyPaused` and does **not** pause on background.
- **No background-audio mode** is configured (no `UIBackgroundModes` /
  `AVAudioSession`), so we pause proactively on the scene-phase transition rather
  than managing an audio session.
- `RootView.onClose` already calls `controller.stop()` (landed earlier this
  branch) to halt audio when the player is dismissed to the Guide.

## Decisions

- **One gate, two entry points:** the same `autoResume && wasPlaying` rule drives
  both warm return and cold relaunch.
- **No-play relaunch lands on the Guide** (filter restored, no player shown); the
  channel/mode stay remembered for when the rule later applies.
- **Auto-surf resumes from the exact channel** the user left on (including
  auto-surf drift), then continues surfing the restored filtered lineup.
- **Reuse `lastWatchedChannelID`** to mean "exact last channel, including
  auto-surf drift" — its only consumer is auto-resume.
- **Play count stays `userInitiated`-only** so auto-surf hops don't inflate it.
- **Centralize scene handling in `RootView`** (it owns `playing` + the controller
  and stays in the hierarchy behind the full-screen cover); remove `PlayerView`'s
  own scene-phase handler.
- **`pauseForBackground()` is distinct from manual pause** so user intent
  (`isManuallyPaused`) and surf mode (`isAutoSurfActive`) survive the round trip.

## Changes

### 1. `Sources/Persistence/PersistenceModels.swift` — persist session mode

Add two defaulted properties to `AppSettingsRecord` (additive, lightweight
automatic SwiftData migration — existing installs keep their data):

- `var lastSessionAutoSurf: Bool = false`
- `var lastSessionWasPlaying: Bool = false`

`lastWatchedChannelID` is retained, now meaning the exact last channel.

### 2. `Sources/Persistence/LocalStore.swift` — resume-state accessors

- `struct ResumeState { let channelID: String?; let isAutoSurf: Bool; let wasPlaying: Bool }`
- `func saveResumeChannel(channelID: String, isAutoSurf: Bool)` — writes the
  channel + mode; called on each channel start.
- `func setResumeWasPlaying(_ wasPlaying: Bool)` — called when leaving the
  foreground.
- `func resumeState() -> ResumeState` — reader for relaunch.

### 3. `Sources/Playback/PlaybackController.swift` — background pause

- `func pauseForBackground()`: `player.pause()` and cancel the auto-surf tick
  token, **without** touching `isManuallyPaused` or `isAutoSurfActive`.
- Foreground resume reuses the existing `playFromUI()`.
- Extend `onChannelChanged` to carry the surf flag:
  `var onChannelChanged: ((Channel, _ userInitiated: Bool, _ isAutoSurf: Bool) -> Void)?`
  and pass `isAutoSurfActive` from `start(...)`.

### 4. `Sources/App/AppEnvironment.swift` — recording

Rework the `onChannelChanged` closure:

- *Always* `local.saveResumeChannel(channelID: channel.id, isAutoSurf: isAutoSurf)`
  (makes auto-surf drift resumable).
- *Only when `userInitiated`* increment play count and bump the store.

### 5. `Sources/UI/RootView.swift` — scene handling + resume

- Add `@Environment(\.scenePhase)`, two `@State` flags
  (`pausedForBackground: Bool`, `wasPlayingAtBackground: Bool`), and a single
  `onChange(of: scenePhase)`. Only the `.background` transition pauses; transient
  `.inactive` overlays (Control Center, Notification Center, app-switcher peek,
  call banners) are ignored.
  - `→ .background` → compute
    `wasPlayingAtBackground = playing != nil && !controller.isManuallyPaused`,
    persist `localStore.setResumeWasPlaying(wasPlayingAtBackground)`, call
    `controller.pauseForBackground()`, set `pausedForBackground = true`.
  - `→ .active` → guard `pausedForBackground` (so transient `.inactive → .active`
    cycles that never hit `.background` are ignored); clear it to `false`; then if
    `settings.autoResume && wasPlayingAtBackground`, `controller.playFromUI()`.
- Unify lineup building into:
  `private func startPlaying(_ channel: Channel, autoSurf: Bool, startTime: Double = 0)`
  — set lineup from `filteredChannels` (append `channel` if missing), optionally
  `startAutoSurf(interval:)`, then `play(channelID:startTime:)`, then
  `playing = channel`. Existing `startPlaying`/`startAutoSurfing` become thin
  callers of this.
- Rework `maybeAutoResume()`:
  - `let s = localStore.resumeState()`
  - guard `settings.autoResume && s.wasPlaying`, `s.channelID`, and the channel
    still exists in `store.channels`; otherwise return (land on Guide).
  - `startPlaying(channel, autoSurf: s.isAutoSurf)`.

### 6. `Sources/UI/PlayerView.swift` — remove local scene handling

Delete the `@Environment(\.scenePhase)` property and the
`onChange(of: scenePhase)` resume block; scene handling now lives in `RootView`.

## Lifecycle Walkthroughs

- **Playing → home button → relaunch, `autoResume` ON:** background captures
  `wasPlaying=true`, persists `{channel, mode, true}`, pauses. Relaunch:
  `maybeAutoResume` opens the player and plays (auto-surf if that was the mode).
- **Playing → home → quick return (warm), `autoResume` ON:** background pauses;
  `.active` sees `resumeOnForeground=true` → resumes.
- **Auto-surfing tag X → lock → relaunch, ON:** resumes auto-surf of X from the
  exact channel, continues surfing.
- **On Guide (not playing) → background → relaunch:** `wasPlaying=false` → lands
  on Guide, filter restored.
- **User-paused → background → relaunch, ON:** `isManuallyPaused` ⇒
  `wasPlaying=false` → lands on Guide.
- **`autoResume` OFF:** never auto-plays; background pauses, warm return stays
  paused (tap to play), relaunch lands on Guide.

## Edge Cases

- Resume channel no longer exists in the catalog → don't resume (guard).
- Auto-surf mode but the exact channel isn't in the restored filtered lineup →
  the unified `startPlaying` appends it so it still plays; surf continues through
  the lineup.
- Cold launch starts at `.active`; `onChange(of:)` does not fire for the initial
  value and `playing == nil`, so the warm-return branch never double-fires
  against `maybeAutoResume`.

## Tests

- **`LocalStore`** round-trip: `saveResumeChannel` + `setResumeWasPlaying` →
  `resumeState()` returns the written values; defaults are
  `{ nil, false, false }`.
- **`PlaybackController`**: `pauseForBackground()` pauses the player but leaves
  `isManuallyPaused == false` and `isAutoSurfActive == true`; `onChannelChanged`
  fires with the correct `userInitiated` and `isAutoSurf` flags for play, manual
  surf, and auto-surf tick.
- Resume-branch behavior is exercised through the unified controller helper
  (lineup + auto-surf + play) under the `MockPlayerService`.

## Out of Scope

- Persisting a playback offset (meaningless for live streams).
- Enabling true background audio (`UIBackgroundModes`).
- Persisting the per-session interval separately from `defaultAutoSurfMinutes`.
