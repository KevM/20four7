# Resume Session State & Background Pause — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remember the user's session (channel + auto-surf mode + whether it was playing), pause on background, and on relaunch/return auto-play only when `Resume playing` is ON and a video was actively playing when the app left the foreground.

**Architecture:** Persist `{ lastWatchedChannelID, lastSessionAutoSurf, lastSessionWasPlaying }` in the single `AppSettingsRecord`. The `PlaybackController` reports each channel start with an `isAutoSurf` flag; `AppEnvironment` always records the channel+mode but only counts user-initiated plays. `RootView` centralizes scene-phase handling: it pauses on `.background`, and resumes (warm or cold) under the unified gate.

**Tech Stack:** Swift, SwiftUI, SwiftData, Combine, XCTest. Build/test on iOS Simulator (iPhone 17 per `CLAUDE.md`).

**Reference spec:** `docs/superpowers/specs/2026-06-04-resume-session-state-design.md`

**Conventions:**
- Run the full suite with:
  `xcodebuild test -scheme 20Four7 -destination 'platform=iOS Simulator,name=iPhone 17'`
- Run one test class/method by appending e.g.
  `-only-testing:TwentyFourSevenTests/LocalStoreTests/test_resumeStateRoundTrips`
- Build only:
  `xcodebuild build -scheme 20Four7 -destination 'platform=iOS Simulator,name=iPhone 17'`
- All new tests go in **existing** test files (Tests are glob-included, so no
  `./generate.sh` is needed unless you add a new file).
- `iPhone 16` simulator is not installed — always target `iPhone 17`.

---

## File Structure

- `Sources/Persistence/PersistenceModels.swift` — add two persisted fields to `AppSettingsRecord`.
- `Sources/Persistence/LocalStore.swift` — `ResumeState` value type + resume accessors; remove the superseded `setLastWatched`/`lastWatchedChannelID()` once unused.
- `Sources/Playback/PlaybackController.swift` — extend `onChannelChanged` with an `isAutoSurf` flag; add `pauseForBackground()`.
- `Sources/App/AppEnvironment.swift` — rework the `onChannelChanged` closure (always record channel+mode; gate play count on `userInitiated`).
- `Sources/UI/RootView.swift` — unified `startPlaying(_:autoSurf:startTime:)`, scene-phase handling, reworked `maybeAutoResume()`.
- `Sources/UI/PlayerView.swift` — remove its local `scenePhase` handler.
- `Tests/LocalStoreTests.swift` — resume round-trip test.
- `Tests/PlaybackControllerTests.swift` — update flag test, add `pauseForBackground` test.

---

## Task 1: Persist resume session state

**Files:**
- Modify: `Sources/Persistence/PersistenceModels.swift` (AppSettingsRecord, ~lines 67-96)
- Modify: `Sources/Persistence/LocalStore.swift` (struct near line 5; methods in the Settings section ~lines 184-218)
- Test: `Tests/LocalStoreTests.swift`

- [ ] **Step 1: Write the failing test**

Add this method inside `final class LocalStoreTests` in `Tests/LocalStoreTests.swift` (e.g. after `test_lastWatchedRoundTrips`):

```swift
    func test_resumeStateRoundTrips() throws {
        let store = try makeStore()

        // Defaults before anything is written.
        XCTAssertEqual(store.resumeState(),
                       ResumeState(channelID: nil, isAutoSurf: false, wasPlaying: false))

        store.saveResumeChannel(channelID: "ch1", isAutoSurf: true)
        store.setResumeWasPlaying(true)
        XCTAssertEqual(store.resumeState(),
                       ResumeState(channelID: "ch1", isAutoSurf: true, wasPlaying: true))

        // Fields update independently.
        store.saveResumeChannel(channelID: "ch2", isAutoSurf: false)
        store.setResumeWasPlaying(false)
        XCTAssertEqual(store.resumeState(),
                       ResumeState(channelID: "ch2", isAutoSurf: false, wasPlaying: false))
    }
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `xcodebuild test -scheme 20Four7 -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TwentyFourSevenTests/LocalStoreTests/test_resumeStateRoundTrips`
Expected: FAIL — compile error, `ResumeState` / `saveResumeChannel` / `setResumeWasPlaying` / `resumeState` are undefined.

- [ ] **Step 3: Add the persisted fields to the model**

In `Sources/Persistence/PersistenceModels.swift`, inside `AppSettingsRecord`, add two stored properties with defaults right after `var selectedTagIDs: [String] = []`:

```swift
    // Resume bookkeeping: the exact last channel (including auto-surf drift),
    // whether the last session was auto-surfing, and whether a video was
    // actively playing when the app last left the foreground.
    var lastSessionAutoSurf: Bool = false
    var lastSessionWasPlaying: Bool = false
```

Leave the initializer unchanged — both properties have defaults, so the existing
`init` still compiles and SwiftData performs an automatic lightweight migration
(existing installs keep their data).

- [ ] **Step 4: Add `ResumeState` and the accessors to `LocalStore`**

In `Sources/Persistence/LocalStore.swift`, add the value type just below the existing `AppSettings` struct (after its closing `}` near line 12):

```swift
/// A snapshot of what the user was last doing, used to restore a session.
struct ResumeState: Equatable {
    var channelID: String?
    var isAutoSurf: Bool
    var wasPlaying: Bool
}
```

Then, in the `// MARK: Settings (single row)` section (after `lastWatchedChannelID()` near line 218), add:

```swift
    /// Records the exact channel now playing and whether the session is
    /// auto-surfing. Called on every channel start so an auto-surf session can
    /// later resume from where it drifted to.
    func saveResumeChannel(channelID: String, isAutoSurf: Bool) {
        let r = settingsRecord()
        r.lastWatchedChannelID = channelID
        r.lastSessionAutoSurf = isAutoSurf
        try? context.save()
    }

    /// Records whether a video was actively playing when the app left the
    /// foreground. Read on relaunch to decide whether to auto-play.
    func setResumeWasPlaying(_ wasPlaying: Bool) {
        settingsRecord().lastSessionWasPlaying = wasPlaying
        try? context.save()
    }

    func resumeState() -> ResumeState {
        let r = settingsRecord()
        return ResumeState(channelID: r.lastWatchedChannelID,
                           isAutoSurf: r.lastSessionAutoSurf,
                           wasPlaying: r.lastSessionWasPlaying)
    }
```

(Do **not** remove `setLastWatched`/`lastWatchedChannelID()` yet — they still have
callers until Task 3.)

- [ ] **Step 5: Run the test to verify it passes**

Run: `xcodebuild test -scheme 20Four7 -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TwentyFourSevenTests/LocalStoreTests/test_resumeStateRoundTrips`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/Persistence/PersistenceModels.swift Sources/Persistence/LocalStore.swift Tests/LocalStoreTests.swift
git commit -m "feat: persist resume session state (channel + mode + wasPlaying)"
```

---

## Task 2: Controller reports auto-surf mode; add background pause; rework recording

This task changes the `onChannelChanged` signature, so its three consumers (the
`start()` call site, the `AppEnvironment` closure, and the controller test) must
change together to compile.

**Files:**
- Modify: `Sources/Playback/PlaybackController.swift` (`onChannelChanged` decl ~line 28; `start()` ~line 140; add `pauseForBackground()` near `pauseFromUI` ~line 132)
- Modify: `Sources/App/AppEnvironment.swift` (closure ~lines 30-39)
- Test: `Tests/PlaybackControllerTests.swift`

- [ ] **Step 1: Update the flag test and add the background-pause test (failing)**

In `Tests/PlaybackControllerTests.swift`, **replace** the existing
`test_onChannelChangedUserInitiatedFlag` with this 3-argument version:

```swift
    func test_onChannelChangedUserInitiatedFlag() {
        let player = MockPlayerService()
        let clock = ManualClock()
        let c = PlaybackController(player: player, clock: clock)
        c.setLineup(makeChannels())

        var changes: [(id: String, userInitiated: Bool, isAutoSurf: Bool)] = []
        c.onChannelChanged = { channel, userInitiated, isAutoSurf in
            changes.append((channel.id, userInitiated, isAutoSurf))
        }

        // Tapping a channel: user-initiated, not auto-surf.
        c.play(channelID: "a")
        XCTAssertEqual(changes.last?.id, "a")
        XCTAssertEqual(changes.last?.userInitiated, true)
        XCTAssertEqual(changes.last?.isAutoSurf, false)

        // Swiping to the next channel: user-initiated, not auto-surf.
        c.surf(.next)
        XCTAssertEqual(changes.last?.id, "b")
        XCTAssertEqual(changes.last?.userInitiated, true)
        XCTAssertEqual(changes.last?.isAutoSurf, false)

        // Auto-surf timer advance: NOT user-initiated, IS auto-surf.
        c.startAutoSurf(interval: 10)
        clock.advance(by: 10)
        XCTAssertEqual(changes.last?.id, "c")
        XCTAssertEqual(changes.last?.userInitiated, false)
        XCTAssertEqual(changes.last?.isAutoSurf, true)
    }
```

Then add a new test (e.g. right after `test_stopPausesPlayerAndTearsDownTimers`):

```swift
    func test_pauseForBackgroundKeepsIntentAndSurfMode() {
        let player = MockPlayerService()
        let clock = ManualClock()
        let c = PlaybackController(player: player, clock: clock)
        c.setLineup(makeChannels())
        c.play(channelID: "a")
        c.startAutoSurf(interval: 10)
        XCTAssertTrue(c.isAutoSurfActive)
        XCTAssertFalse(c.isManuallyPaused)

        c.pauseForBackground()

        XCTAssertEqual(player.lastCommand, .pause)
        XCTAssertFalse(c.isManuallyPaused)   // not recorded as a manual pause
        XCTAssertTrue(c.isAutoSurfActive)    // surf mode preserved across background

        // The auto-surf countdown is suspended while backgrounded.
        let remainingBefore = c.autoSurfTimeRemaining
        clock.advance(by: 5)
        XCTAssertEqual(c.autoSurfTimeRemaining, remainingBefore)
    }
```

- [ ] **Step 2: Run the controller tests to verify they fail**

Run: `xcodebuild test -scheme 20Four7 -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TwentyFourSevenTests/PlaybackControllerTests`
Expected: FAIL — compile errors (`onChannelChanged` is 2-arg; `pauseForBackground` undefined).

- [ ] **Step 3: Extend `onChannelChanged` and pass the surf flag**

In `Sources/Playback/PlaybackController.swift`, change the declaration (near line 28) from:

```swift
    var onChannelChanged: ((Channel, _ userInitiated: Bool) -> Void)?
```

to:

```swift
    var onChannelChanged: ((Channel, _ userInitiated: Bool, _ isAutoSurf: Bool) -> Void)?
```

In `start(...)` (near line 140), change:

```swift
        onChannelChanged?(channel, userInitiated)
```

to:

```swift
        onChannelChanged?(channel, userInitiated, isAutoSurfActive)
```

- [ ] **Step 4: Add `pauseForBackground()`**

In `Sources/Playback/PlaybackController.swift`, add this method directly after
`pauseFromUI()` (after the closing `}` near line 132):

```swift
    /// Pause because the app is backgrounding. Unlike `pauseFromUI`, this does
    /// NOT set `isManuallyPaused` and does NOT clear `isAutoSurfActive`, so the
    /// user's intent and the surf mode survive a return to the foreground.
    func pauseForBackground() {
        player.pause()
        autoSurfToken?.cancel()
        autoSurfToken = nil
    }
```

- [ ] **Step 5: Rework the `AppEnvironment` recording closure**

In `Sources/App/AppEnvironment.swift`, replace the entire `playback.onChannelChanged = { ... }` assignment (lines ~30-39) with:

```swift
        playback.onChannelChanged = { [weak local, weak store] channel, userInitiated, isAutoSurf in
            // Always remember the exact channel + mode so an auto-surf session can
            // resume from where it drifted to. Only user-initiated plays count
            // toward popularity, so auto-surf hops don't inflate play counts.
            local?.saveResumeChannel(channelID: channel.id, isAutoSurf: isAutoSurf)
            guard userInitiated else { return }
            if let stats = local?.incrementPlayCount(channelID: channel.id) {
                Task { @MainActor in
                    store?.bumpPlayCount(channelID: channel.id, playCount: stats.playCount, lastPlayedDate: stats.lastPlayedDate)
                }
            }
        }
```

- [ ] **Step 6: Run the controller tests to verify they pass**

Run: `xcodebuild test -scheme 20Four7 -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TwentyFourSevenTests/PlaybackControllerTests`
Expected: PASS (all controller tests, including the two changed/added).

- [ ] **Step 7: Commit**

```bash
git add Sources/Playback/PlaybackController.swift Sources/App/AppEnvironment.swift Tests/PlaybackControllerTests.swift
git commit -m "feat: report auto-surf mode on channel change; add pauseForBackground"
```

---

## Task 3: RootView — unified play helper, scene handling, resume gate

**Files:**
- Modify: `Sources/UI/RootView.swift`
- Modify: `Sources/Persistence/LocalStore.swift` (remove now-dead `setLastWatched`/`lastWatchedChannelID()`)
- Modify: `Tests/LocalStoreTests.swift` (remove the now-dead `test_lastWatchedRoundTrips`)

No unit test is added here (this is SwiftUI scene/glue code, which the suite does
not unit-test). Verification is a clean build, the full existing suite passing,
and the manual smoke test in Step 8.

- [ ] **Step 1: Add scene-phase state to `RootView`**

In `Sources/UI/RootView.swift`, add to the property block (after line 8,
`@State private var showingTagPicker = false`):

```swift
    @Environment(\.scenePhase) private var scenePhase
    @State private var pausedForBackground = false
    @State private var wasPlayingAtBackground = false
```

- [ ] **Step 2: Point the auto-surf toolbar button at the unified helper**

In the toolbar (the Auto-Surf `Button`, near lines 40-43), change:

```swift
                            if let firstChannel = store.filteredChannels.first {
                                startAutoSurfing(firstChannel)
                            }
```

to:

```swift
                            if let firstChannel = store.filteredChannels.first {
                                startPlaying(firstChannel, autoSurf: true)
                            }
```

- [ ] **Step 3: Add the scene-phase handler**

In `Sources/UI/RootView.swift`, add this modifier immediately after
`.task { await maybeAutoResume() }` (line 87):

```swift
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .background:
                // Only a real background pauses; transient .inactive overlays
                // (Control Center, Notification Center, app-switcher peek) do not.
                let wasPlaying = playing != nil && !env.controller.isManuallyPaused
                wasPlayingAtBackground = wasPlaying
                env.localStore.setResumeWasPlaying(wasPlaying)
                env.controller.pauseForBackground()
                pausedForBackground = true
            case .active:
                guard pausedForBackground else { return }
                pausedForBackground = false
                if env.localStore.settings().autoResume && wasPlayingAtBackground {
                    env.controller.playFromUI()
                }
            default:
                break
            }
        }
```

- [ ] **Step 4: Replace the three play helpers with one unified helper**

In `Sources/UI/RootView.swift`, replace both existing methods
`startPlaying(_:startTime:)` (lines ~90-99) and `startAutoSurfing(_:)`
(lines ~101-107) with this single method:

```swift
    @MainActor
    private func startPlaying(_ channel: Channel, autoSurf: Bool = false, startTime: Double = 0) {
        var lineup = store.filteredChannels
        if !lineup.contains(where: { $0.id == channel.id }) {
            lineup.append(channel)
        }
        env.controller.setLineup(lineup)
        if autoSurf {
            env.controller.startAutoSurf(interval: Double(env.localStore.settings().defaultAutoSurfMinutes) * 60)
        }
        env.controller.play(channelID: channel.id, startTime: startTime)
        playing = channel
    }
```

The existing callers `startPlaying(channel)` (onSelect) and
`startPlaying(channel, startTime: startTime)` (onWatchNow) keep working via the
defaulted `autoSurf` parameter.

- [ ] **Step 5: Rework `maybeAutoResume()`**

Replace the body of `maybeAutoResume()` (lines ~109-117) with:

```swift
    @MainActor
    private func maybeAutoResume() async {
        try? await Task.sleep(nanoseconds: 500_000_000)
        await store.refresh()
        let resume = env.localStore.resumeState()
        guard env.localStore.settings().autoResume,
              resume.wasPlaying,
              let lastID = resume.channelID,
              let channel = store.channels.first(where: { $0.id == lastID }) else { return }
        startPlaying(channel, autoSurf: resume.isAutoSurf)
    }
```

- [ ] **Step 6: Remove the now-dead `LocalStore` helpers and their test**

The only callers of `setLastWatched`/`lastWatchedChannelID()` were the
`AppEnvironment` closure (changed in Task 2) and `maybeAutoResume` (changed in
Step 5), so both are now unused.

In `Sources/Persistence/LocalStore.swift`, delete:

```swift
    func setLastWatched(channelID: String) {
        settingsRecord().lastWatchedChannelID = channelID
        try? context.save()
    }
    func lastWatchedChannelID() -> String? { settingsRecord().lastWatchedChannelID }
```

In `Tests/LocalStoreTests.swift`, delete the now-obsolete test (resume coverage
replaces it):

```swift
    func test_lastWatchedRoundTrips() throws {
        let store = try makeStore()
        store.setLastWatched(channelID: "c9")
        XCTAssertEqual(store.lastWatchedChannelID(), "c9")
    }
```

- [ ] **Step 7: Build and run the full suite**

Run: `xcodebuild test -scheme 20Four7 -destination 'platform=iOS Simulator,name=iPhone 17'`
Expected: BUILD SUCCEEDS and all tests PASS. (If the build fails with "Tests can't be run because … isn't a member of the scheme", the target name is `TwentyFourSevenTests` — the scheme is `20Four7`.)

- [ ] **Step 8: Manual smoke test (simulator)**

Boot the app on the iPhone 17 simulator and verify:

1. In **Settings**, turn **Auto-resume last channel** ON.
2. Tap a tag, then tap **Auto-Surf**. Let it surf once (channel changes on the timer).
3. Press Cmd+Shift+H (Home) to background, then relaunch the app:
   - Expected: it reopens playing, **auto-surfing the same tag**, and continues to surf.
4. Open Control Center (swipe down from top-right) over the playing video:
   - Expected: video keeps playing (no pause).
5. From a playing video, tap the close (chevron) to return to the Guide, then
   Home + relaunch:
   - Expected: lands on the **Guide**, nothing plays (wasPlaying was false).
6. Turn **Auto-resume** OFF, play a channel, Home + relaunch:
   - Expected: lands on the **Guide**, nothing plays.

- [ ] **Step 9: Commit**

```bash
git add Sources/UI/RootView.swift Sources/Persistence/LocalStore.swift Tests/LocalStoreTests.swift
git commit -m "feat: centralize scene handling and gate resume on wasPlaying"
```

---

## Task 4: Remove PlayerView's local scene handler

`RootView` now owns scene-phase behavior, so `PlayerView`'s own resume-on-active
handler is redundant and would double-resume.

**Files:**
- Modify: `Sources/UI/PlayerView.swift`

- [ ] **Step 1: Delete the `scenePhase` property**

In `Sources/UI/PlayerView.swift`, remove line 10:

```swift
    @Environment(\.scenePhase) private var scenePhase
```

- [ ] **Step 2: Delete the `onChange(of: scenePhase)` block**

Remove this modifier (lines ~92-98):

```swift
        .onChange(of: scenePhase) { _, newValue in
            if newValue == .active {
                if !controller.isManuallyPaused {
                    controller.playFromUI()
                }
            }
        }
```

Leave the surrounding modifiers (`.onAppear`, `.onDisappear`, `.onChange(of: fillScreen)`) intact.

- [ ] **Step 3: Build to verify no references remain**

Run: `xcodebuild build -scheme 20Four7 -destination 'platform=iOS Simulator,name=iPhone 17'`
Expected: BUILD SUCCEEDS (no "unused variable `scenePhase`" or "cannot find" errors).

- [ ] **Step 4: Commit**

```bash
git add Sources/UI/PlayerView.swift
git commit -m "refactor: remove PlayerView scene handler (centralized in RootView)"
```

---

## Task 5: Full verification

**Files:** none (verification only).

- [ ] **Step 1: Run the entire suite**

Run: `xcodebuild test -scheme 20Four7 -destination 'platform=iOS Simulator,name=iPhone 17'`
Expected: BUILD SUCCEEDS, all tests PASS (LocalStore resume round-trip, controller
flag + pauseForBackground, plus all pre-existing tests).

- [ ] **Step 2: Re-run the manual smoke checklist**

Repeat Task 3 / Step 8 scenarios 1-6 and confirm each matches its expected
outcome. Additionally:

7. Play a video, switch to **another app**, then come back:
   - Expected (Auto-resume ON): playback resumes on return.
   - Expected (Auto-resume OFF): stays paused; tap to resume.
8. Manually pause a video (tap, then pause), background, relaunch with
   Auto-resume ON:
   - Expected: lands on the Guide, nothing plays (`wasPlaying` was false because
     it was user-paused).

- [ ] **Step 3: Confirm both original bug reports are resolved**

- Returning to the Guide from a video no longer leaks audio (close → `stop()`
  plus background → `pauseForBackground()`).
- Launch no longer starts a "random" video: it only auto-plays when Auto-resume
  is ON and the user was actively playing when they left; an auto-surf session
  resumes *as auto-surf of its tag*, which is coherent rather than random.

---

## Self-Review Notes (for the implementer)

- **Spec coverage:** persistence fields (Task 1) ↔ spec §1/§2; `onChannelChanged`
  + `pauseForBackground` (Task 2) ↔ §3/§4; scene handling + unified
  `startPlaying` + `maybeAutoResume` (Task 3) ↔ §5; `PlayerView` cleanup (Task 4)
  ↔ §6; tests (Tasks 1,2,5) ↔ spec Tests section.
- **Type consistency:** `onChannelChanged` is `(Channel, Bool, Bool)` everywhere
  (controller decl, `start()` call, `AppEnvironment` closure, test). `ResumeState`
  field names `channelID`/`isAutoSurf`/`wasPlaying` match between `LocalStore`,
  the test, and `maybeAutoResume`. `startPlaying(_:autoSurf:startTime:)` is the
  single helper; `startAutoSurfing` no longer exists.
- **Migration:** the two new `Bool` fields have defaults, so SwiftData migrates
  on-disk stores automatically; existing data is preserved.
