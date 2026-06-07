# Live catch-up on resume — design

**Date:** 2026-06-07
**Status:** Implemented

> **Revision (2026-06-07, post-implementation):** The 2× catch-up *ramp* was
> dropped — on a real device it looked janky and YouTube clamps the rate on live
> streams (exactly the risk this spec flagged). Go Live now simply **jumps to the
> live tip** (instant seek). The Go Live control also moved from the bottom
> control capsule **into the header** (the `● LIVE` badge becomes the tappable
> control). Sections below reflect the shipped design; struck-through ramp details
> are kept only as rationale.

## Problem

The app's focus is live content, but pausing a live stream and resuming it
leaves playback wherever it stopped — now behind the live edge. There is no way
to catch back up to the live tip of the feed. Resuming should offer a path back
to live.

## Behavior summary

A live stream becomes **behind** when it is paused manually or auto-resumed after
the app was backgrounded. While behind, the top-left `● LIVE` badge becomes a
**gray, tappable "▶ GO LIVE" control** in the header. Tapping it **jumps straight
to the live tip** (instant seek) and plays; the badge returns to a static red
`● LIVE` at the edge.

That's the whole interaction — no fast-forward ramp, no second state to remember.

## Design decisions (and why)

- **Trigger model: explicit "Go Live", not silent auto-jump.** Resuming plays
  from where you paused; catching up is a deliberate user action. Preserves the
  ability to stay behind live if you paused to look at something.
- **Detection: intent-based, not drift-polling.** The controller knows it paused
  a live stream, so it marks "behind" directly — no steady-state polling loop and
  no dependence on YouTube's finicky live-duration semantics.
- **Triggers: manual pause AND background return.** Both leave you behind the
  edge; the background gap is often the larger offender. Treated identically.
- **Action placement: the header badge itself is the control.** The `● LIVE`
  badge doubles as status and action — red/static at the edge, gray/tappable when
  behind. One element, the platform-standard convention.
- **Jump, don't ramp.** A 2× catch-up ramp was prototyped but cut: it looked
  janky and YouTube clamps `setPlaybackRate()` on live streams. The instant seek
  is simpler, reliable, and always reaches live. ~~*(Original ramp rationale: at
  rate r the gap closes at (r−1) s/s, so drift d catches up in d/(r−1) s; a
  one-shot drift query chose ramp-vs-seek. Removed.)*~~

## Architecture

`PlaybackController` owns the behind-state and the trivial Go Live action;
WebKit/YouTube specifics stay behind the `PlayerService` boundary.

### 1. `PlayerService` boundary

One new method:

- `func seekToLive()` — seek to the live edge and play.

`MockPlayerService` records `seekToLiveCount` for unit tests.

~~*(The ramp also added `liveDriftSeconds() async`, `setPlaybackRate(_:)`, and a
rate read-back. All removed when the ramp was cut.)*~~

### 2. `player.html`

One matching JS function:

- `seekToLive()` → `player.seekTo(player.getDuration(), true); player.playVideo();`
  (guarded so a non-finite duration just plays without seeking). Invoked from
  Swift via the fire-and-forget `evaluate` path.

### 3. `WebViewPlayerService`

`func seekToLive() { evaluate("seekToLive()") }`.

### 4. `PlaybackController`

- New `@Published private(set) var isBehindLive`.

**Set behind** in `pauseFromUI()` and `pauseForBackground()` when
`isCurrentlyLive`.

**Clear behind** in:
- `start()` — a fresh load is at the edge.
- `goLive()`.
- the `liveStatusDetected(isLive: false)` event — a non-live stream has no
  "behind" concept.

**`goLive()`** (synchronous; no-op unless `isBehindLive`): clear `isBehindLive`,
clear `isManuallyPaused`, set `userIntendsPlayback`, then `player.seekToLive()`
(the JS seek also resumes playback).

### 5. UI — `PlayerOverlay`

- `● LIVE` header badge:
  - `isCurrentlyLive && !isBehindLive` → static red `● LIVE` (status only).
  - `isCurrentlyLive && isBehindLive` → a gray `Button` labelled
    `▶ GO LIVE` (`forward.end.fill` + text). Tapping it calls a new `onGoLive`
    closure → `controller.goLive()`, and fires `onInteraction()` to reset the
    overlay auto-hide.
- `onGoLive` is wired through `PlayerView` like the existing overlay closures.

## Testing

Controller tests against `MockPlayerService`:

- Pausing a live channel sets `isBehindLive`; pausing a non-live channel does not.
- `pauseForBackground` on a live channel sets `isBehindLive`.
- `start` / `surf` / `liveStatusDetected(false)` clear `isBehindLive`.
- `goLive` while behind calls `seekToLive`, clears `isBehindLive`, and clears
  `isManuallyPaused`.
- `goLive` is a no-op when not behind.

## Out of scope (YAGNI)

- A fast-forward / 2× catch-up ramp (prototyped and removed — see decisions).
- Continuous drift display / a "−0:42 behind" readout.
- Self-correcting gray state from buffering or stalls (detection is intent-based).
- Catch-up for non-live (VOD-as-live) content.
