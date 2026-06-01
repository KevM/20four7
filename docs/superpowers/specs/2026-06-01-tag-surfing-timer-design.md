# Tag Surfing (Timed Auto-Switching) Design

This design details the addition of a **Tag Surfing** feature to allow users to automatically transition between ambient streams within a chosen tag chip at a configurable interval.

## Goal Description
Allow users to lean back and watch a slideshow-like rotation of streams within a tag. For example, a user selects the "Lo-Fi" or "Rain" tag, taps "Auto-Surf", and the app automatically switches to the next channel in that tag lineup every X minutes.

## User Review Required

> [!NOTE]
> The auto-surf interval will default to **5 minutes** and is configurable via the main App Settings. Tapping pause in the player pauses the countdown. Manually surfing to the next/previous channel resets the countdown.

## Proposed Changes

---

### Playback & State Layer

#### [MODIFY] [LocalStore.swift](file:///Users/kevm/github/televista/Sources/Persistence/LocalStore.swift)
* Add `autoSurfIntervalMinutes: Int` to `AppSettings` and `AppSettingsRecord` (defaults to 5).
* Handle database migrations/fallback values if necessary (or standard model defaults since SwiftData allows optional/default values).

#### [MODIFY] [PlaybackController.swift](file:///Users/kevm/github/televista/Sources/Playback/PlaybackController.swift)
* Add `@Published private(set) var isAutoSurfActive = false`
* Add `@Published private(set) var autoSurfTimeRemaining: TimeInterval? = nil`
* Add a `ClockToken?` for the auto-surf countdown (reusing the existing `Clock` interface).
* Maintain a regular timer publisher or countdown loop when auto-surf is active to update `autoSurfTimeRemaining` every second (so the UI countdown banner updates).
* Implement `startAutoSurf(interval: TimeInterval)`:
  * Cancels existing auto-surf timer.
  * Sets `isAutoSurfActive = true`.
  * Starts countdown. When countdown reaches 0, it calls `surf(.next)` and schedules the next interval.
* Implement `stopAutoSurf()`:
  * Cleans up timer and resets states.
* Modify `surf(_ direction: SurfDirection)`:
  * If `isAutoSurfActive`, reset the timer countdown to the full duration.
* Modify manual pause/play methods:
  * When paused: suspend countdown (cancel current token, store remaining time).
  * When played: resume countdown (schedule token with remaining time).

---

### UI Layer

#### [MODIFY] [SettingsView.swift](file:///Users/kevm/github/televista/Sources/UI/SettingsView.swift)
* Add a control (Stepper or Picker) under "Playback" settings: `"Auto-Surf interval: X min"` (ranging from 1 to 60 minutes).

#### [MODIFY] [GuideView.swift](file:///Users/kevm/github/televista/Sources/UI/GuideView.swift)
* Directly below `TagChipBar` and above the `LazyVGrid`, if a tag is selected, render the Active Tag Banner:
  * Left: `"Tag: [Tag Name] · [X] channels"`
  * Right: A prominent `"Auto-Surf"` button.
  * Tapping `"Auto-Surf"` triggers the callback to start playing the first channel in the lineup with Auto-Surf activated.

#### [MODIFY] [RootView.swift](file:///Users/kevm/github/televista/Sources/UI/RootView.swift)
* Add support for launching playback in Auto-Surf mode (configuring `PlaybackController` lineup and starting the auto-surf timer).

#### [MODIFY] [PlayerView.swift](file:///Users/kevm/github/televista/Sources/UI/PlayerView.swift) & [PlayerOverlay.swift](file:///Users/kevm/github/televista/Sources/UI/PlayerOverlay.swift)
* If `controller.isAutoSurfActive` and `controller.autoSurfTimeRemaining != nil`, render a green/white countdown badge: `"Auto-surfing next channel in MM:SS"`.
* Position this pill badge so that it displays/hides in lockstep with the overlay controls.
* Add an action to turn off Auto-Surf if the user wants to stay on the current channel permanently (e.g. clicking a small close button next to the timer).

---

## Verification Plan

### Automated Tests
* Create unit tests in `PlaybackTests` testing `PlaybackController` timer transitions:
  * Verify `startAutoSurf` sets correct active flag.
  * Verify timer fires and calls `surf(.next)` via the mock `Clock` injection.
  * Verify pause/resume updates time remaining and pauses/resumes timer correctly.
  * Verify manual surf resets timer.

### Manual Verification
* Run in iOS Simulator:
  * Select tag "Lo-Fi" in Guide.
  * Tap "Auto-Surf" button.
  * Verify full-screen player opens and auto-surf countdown is visible.
  * Verify video changes automatically when timer reaches zero.
  * Verify swiping to next/prev resets countdown.
  * Verify tapping pause pauses the countdown.
  * Change auto-surf interval in settings and verify the new interval is respected.
