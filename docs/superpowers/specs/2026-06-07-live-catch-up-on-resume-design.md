# Live catch-up on resume — design

**Date:** 2026-06-07
**Status:** Approved (pending implementation plan)

## Problem

The app's focus is live content, but pausing a live stream and resuming it
leaves playback wherever it stopped — now behind the live edge. There is no way
to catch back up to the live tip of the feed. Resuming should offer a path back
to live.

## Behavior summary

A live stream becomes **behind** when it is paused manually or auto-resumed
after the app was backgrounded. While behind:

- The top-left `● LIVE` badge turns **gray** (passive status only — not tappable).
- A **Go Live button** (`forward.end.fill`) appears in the bottom control
  capsule, right after play/pause. It is present only while behind.

Tapping Go Live catches up to the live edge:

- **Drift ≤ 30s** → smooth **2× playback ramp** that coasts to the edge, then
  snaps back to 1×.
- **Drift > 30s** (or unknown) → **instant seek** to the edge.
- If YouTube/WebKit **clamps the playback rate** (live streams often hide/clamp
  speed control), the ramp silently **falls back to the instant seek**, so the
  user always reaches live.

The badge goes **red immediately** on tap (you have committed to live); the 2×
ramp is just the animation of getting there.

### Interrupted catch-up

If the user is **mid-ramp** (fast-forwarding toward live) and gets
**involuntarily yanked away** — backgrounding the app via the home screen or app
switcher — the catch-up intent is remembered. The **next resume jumps straight
to live immediately** (instant seek, no second ramp), honoring the "I wanted to
be at live" intent they had when they tapped.

This applies only to the *involuntary* interruption (backgrounding). Deliberately
pausing, dismissing the player, or surfing to another channel mid-ramp cancels
the catch-up outright — no remembered live-jump (a surf reloads at the edge
anyway; a manual pause leaves the normal gray badge + Go Live button).

## Design decisions (and why)

- **Trigger model: explicit "Go Live", not silent auto-jump.** Resuming plays
  from where you paused; catching up is a deliberate user action. Preserves the
  ability to stay behind live if you paused to look at something.
- **Detection: intent-based, not drift-polling.** The controller knows it paused
  a live stream, so it marks "behind" directly — no steady-state polling loop and
  no dependence on YouTube's finicky live-duration semantics for *detection*.
- **Triggers: manual pause AND background return.** Both leave you behind the
  edge; the background gap is often the larger offender. Treated identically.
- **Action placement: the control capsule, not the badge.** The badge stays a
  read-only status indicator; the tap target lives where every other action
  lives. Keeps the top-left corner read-only and uncluttered.
- **Catch-up: 2× ramp within 30s, else instant seek.** At rate *r* the gap
  closes at *(r − 1)* s per real second, so a measured drift *d* catches up in
  *d / (r − 1)* seconds (= *d* real seconds at 2×). A one-shot drift query at tap
  time is enough to choose ramp vs seek and to compute the ramp duration — no
  continuous polling.

## Architecture

Policy (threshold, rate, ramp timing) lives in the testable `PlaybackController`;
mechanism (WebKit/YouTube specifics) stays behind the `PlayerService` boundary.

### 1. `PlayerService` boundary

Three new methods:

- `func seekToLive()` — hard-seek to the live edge and play.
- `func liveDriftSeconds() async -> TimeInterval?` — one-shot
  `getDuration() − getCurrentTime()`; `nil` when not live / unknown. `async`
  because it is a JS round-trip (like the existing `loadVideo`).
- `func setPlaybackRate(_ rate: Double) async -> Double` — sets the rate and
  **reads back** `getPlaybackRate()` so the caller can detect clamping.

`MockPlayerService` implements all three: canned drift, canned applied-rate, and
recorded call history, so the orchestration is fully unit-testable.

### 2. `player.html`

Three matching JS functions, no polling loop:

- `seekToLive()` → `player.seekTo(player.getDuration(), true); player.playVideo();`
- `liveDrift()` → returns `getDuration() − getCurrentTime()` when the video is
  live, else `null`.
- a rate setter → `player.setPlaybackRate(rate)` then returns
  `player.getPlaybackRate()` (the applied value).

`liveDrift()` and the rate setter are invoked from Swift via
`callAsyncJavaScript` (arguments bound, never string-interpolated, matching the
existing `loadVideo` call). `seekToLive()` can use the fire-and-forget
`evaluate` path.

### 3. `WebViewPlayerService`

Implements the three new protocol methods over the JS functions above.

### 4. `PlaybackController` (orchestration)

- New `@Published private(set) var isBehindLive`.
- Constants: `catchUpThresholdSeconds = 30`, `catchUpRate = 2.0`.
- A `rampToken: ClockToken?` for the scheduled restore-to-1×.
- A private `wantsLiveOnResume: Bool` — "was fast-forwarding when involuntarily
  interrupted." Set **only when the 2× ramp actually begins**. In-memory only (a
  cold relaunch does a fresh at-live load regardless).

**Set behind** in `pauseFromUI()` and `pauseForBackground()` when
`isCurrentlyLive`.

**Clear behind** in:
- `start()` — a fresh load is at the edge.
- `goLive()`.
- the `liveStatusDetected(isLive: false)` event — a non-live stream has no
  "behind" concept.

**`goLive()`** (no-op unless `isBehindLive`):
1. Clear `isBehindLive`, clear `isManuallyPaused`, set `userIntendsPlayback`,
   ensure playing (`player.play()`).
2. `Task { @MainActor }`: `let drift = await player.liveDriftSeconds()`.
   - If `drift` exists, `> 0`, and `≤ catchUpThresholdSeconds`:
     `let applied = await player.setPlaybackRate(catchUpRate)`.
     - `applied > 1.0` → set `wantsLiveOnResume = true` and schedule `rampToken`
       to restore 1× **and clear `wantsLiveOnResume`** after
       `drift / (applied − 1)` seconds via the injected `clock`.
     - else (clamped) → `player.seekToLive()`.
   - else (too far / unknown) → `player.seekToLive()`.

**`playFromUI()`** resume hook: after `player.play()`, if `wantsLiveOnResume` is
set → `player.seekToLive()`, then clear `wantsLiveOnResume` and `isBehindLive`.
`enterForeground(autoResume:)` already resumes via `playFromUI()`, so this single
hook covers both auto-resume-on-return and a later manual play (when auto-resume
is off).

**Ramp cancellation:** all of `pauseFromUI()`, `pauseForBackground()`, `stop()`,
`surf()`, and `start()` cancel any live `rampToken` and restore the rate to 1×
(so a half-finished ramp never leaks into the next action). They differ only in
the live-intent flag:

- `pauseForBackground()` **preserves** `wantsLiveOnResume` — the involuntary
  interruption we want the next resume to honor.
- `pauseFromUI()`, `stop()`, and `start()` (the latter covers `surf()`)
  **clear** `wantsLiveOnResume` — deliberate exits from the catch-up.

### 5. UI — `PlayerOverlay`

- `● LIVE` badge: state-driven **color only** — red when
  `isCurrentlyLive && !isBehindLive`, gray when `isCurrentlyLive && isBehindLive`.
  Not interactive.
- Control capsule: a Go Live button (`forward.end.fill`) shown only when
  `isCurrentlyLive && isBehindLive`, placed right after play/pause. Tapping it
  calls a new `onGoLive` closure → `controller.goLive()`, and fires
  `onInteraction()` to reset the overlay auto-hide. Absent (not dimmed) when at
  the edge; its appearance reflows the centered capsule and doubles as a state
  cue.
- `onGoLive` is wired through `PlayerView` like the existing overlay closures.
- Any new fixed sizes go on `LayoutMetrics`, not inline ternaries.

## Testing

Controller tests against `MockPlayerService`:

- Pausing a live channel sets `isBehindLive`; pausing a non-live channel does not.
- `pauseForBackground` on a live channel sets `isBehindLive`; `enterForeground`
  auto-resume keeps it set.
- `start` / `surf` / `liveStatusDetected(false)` clear `isBehindLive`.
- `goLive` with small drift (mock returns e.g. 10s, applied rate 2.0) calls
  `setPlaybackRate(2.0)`, then restores 1× after the test clock advances
  `10 / (2 − 1) = 10s`.
- `goLive` with large drift (> 30s) calls `seekToLive` and never changes rate.
- `goLive` with clamped rate (mock returns applied 1.0) falls back to
  `seekToLive`.
- Pausing / surfing mid-ramp cancels the ramp and restores 1×.
- `goLive` is a no-op when not behind.
- **Interrupted catch-up:** start a ramp, then `pauseForBackground()` →
  `wantsLiveOnResume` stays set; a subsequent `playFromUI()` calls `seekToLive`
  and clears the flag (no `setPlaybackRate` ramp). With auto-resume off, the same
  holds when the user later taps play manually.
- **Deliberate exit clears intent:** start a ramp, then `pauseFromUI()` (or
  `stop()` / `surf()`) → a later `playFromUI()` does **not** seek to live.

## Risk

The 2× ramp depends on YouTube honoring `setPlaybackRate()` on a **live** IFrame
player, which it often hides/clamps. The read-back + seek fallback guarantees
correctness (you always reach live); the ramp is a best-effort enhancement to be
confirmed with a quick spike during implementation. If the spike shows live rate
changes are reliably refused, the ramp path can be dropped with no other design
changes — Go Live degrades to the instant seek that already works.

## Out of scope (YAGNI)

- Continuous drift display / a "−0:42 behind" readout.
- Self-correcting gray state from buffering or stalls (detection is intent-based).
- Configurable threshold/rate in settings (constants for now).
- Catch-up for non-live (VOD-as-live) content.
