# Live Catch-up on Resume Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a viewer who has fallen behind a live stream catch back up — a gray "behind live" indicator plus a Go Live control that either ramps playback to 2× (when close) or seeks straight to the edge (when far or when the rate is refused).

**Architecture:** Catch-up *policy* (threshold, rate, ramp timing, behind-detection) lives in the unit-tested `PlaybackController`; the WebKit/YouTube *mechanism* sits behind the `PlayerService` protocol. Behind-detection is intent-based (pausing a live stream marks it behind); only the Go Live *action* does a single one-shot drift query. An interrupted 2× ramp (backgrounding) is remembered so the next resume jumps straight to live.

**Tech Stack:** Swift / SwiftUI, WKWebView + YouTube IFrame API, XCTest, XcodeGen. Build/test on the iPhone 17 simulator.

**Background spec:** [`docs/superpowers/specs/2026-06-07-live-catch-up-on-resume-design.md`](../specs/2026-06-07-live-catch-up-on-resume-design.md)

**Conventions used by every task below:**
- Full test run: `xcodebuild test -scheme 20Four7 -destination 'platform=iOS Simulator,name=iPhone 17'`
- Single test: append `-only-testing:TwentyFourSevenTests/PlaybackControllerTests/<method>`
- Build only: `xcodebuild build -scheme 20Four7 -destination 'platform=iOS Simulator,name=iPhone 17'`
- No new files are created, so `./generate.sh` is **not** required.
- The test module is imported as `@testable import TwentyFourSeven`.

---

## File Structure

| File | Responsibility | Change |
|------|----------------|--------|
| `Sources/Player/PlayerService.swift` | Playback boundary protocol | Add `seekToLive()`, `setPlaybackRate(_:)`, `liveDriftSeconds() async`, `playbackRate() async` |
| `Sources/Player/MockPlayerService.swift` | Test double | Implement the four new methods + test hooks |
| `Sources/Player/WebViewPlayerService.swift` | iOS YouTube IFrame impl | Implement the four new methods over JS |
| `Sources/Player/Resources/player.html` | In-page YouTube glue | Add `seekToLive`, `liveDrift`, `setPlaybackRate`, `getPlaybackRate` JS |
| `Sources/Playback/PlaybackController.swift` | Catch-up policy + state | `isBehindLive`, `goLive()`, ramp scheduling, `wantsLiveOnResume`, pause/start/stop wiring |
| `Sources/UI/PlayerOverlay.swift` | Player chrome | Gray LIVE badge when behind; Go Live button in the control capsule |
| `Sources/UI/PlayerView.swift` | Hosts the overlay | Wire the `onGoLive` closure |
| `Tests/PlaybackControllerTests.swift` | Controller unit tests | New tests for behind-detection, ramp/seek/clamp, interrupted catch-up |

---

## Task 1: Extend the player boundary

Adds the four new playback primitives across the protocol, the mock, the WebKit
implementation, and the in-page JS. No unit test of its own (the codebase does
not unit-test WebView/JS); the mock is exercised by Tasks 2–4. Verified by a
clean build.

**Files:**
- Modify: `Sources/Player/PlayerService.swift:37-42`
- Modify: `Sources/Player/MockPlayerService.swift:18-31`
- Modify: `Sources/Player/WebViewPlayerService.swift:140-146`
- Modify: `Sources/Player/Resources/player.html:116-119`

- [ ] **Step 1: Add the four methods to the `PlayerService` protocol**

In `Sources/Player/PlayerService.swift`, replace the protocol body (the lines
from `func load(channel:` through `func setMuted(_ muted: Bool)`):

```swift
    func load(channel: Channel, startTime: TimeInterval)
    func play()
    func pause()
    func setVolume(_ volume: Int)   // 0...100
    func setMuted(_ muted: Bool)

    /// Seek to the live edge of a live stream and play.
    func seekToLive()
    /// Set the playback speed multiplier (1.0 == normal).
    func setPlaybackRate(_ rate: Double)
    /// One-shot seconds-behind-live (`getDuration() − getCurrentTime()`).
    /// `nil` when the video is not live or the value is unavailable.
    func liveDriftSeconds() async -> TimeInterval?
    /// The playback rate the player actually applied (used to detect a rate the
    /// platform clamped or refused).
    func playbackRate() async -> Double
```

- [ ] **Step 2: Implement them in `MockPlayerService`**

In `Sources/Player/MockPlayerService.swift`, add these stored properties right
after `private(set) var muted = false` (line 16):

```swift
    private(set) var seekToLiveCount = 0
    private(set) var rateHistory: [Double] = []
    private(set) var currentRate: Double = 1.0
    /// Test inputs: the drift `liveDriftSeconds()` returns, and the rate
    /// `playbackRate()` reports back (set to 1.0 to simulate a clamped rate).
    var driftToReturn: TimeInterval?
    var rateToReturn: Double?
```

Then add the four method implementations right after `setMuted` (line 31):

```swift
    func seekToLive() { seekToLiveCount += 1 }
    func setPlaybackRate(_ rate: Double) { currentRate = rate; rateHistory.append(rate) }
    func liveDriftSeconds() async -> TimeInterval? { driftToReturn }
    func playbackRate() async -> Double { rateToReturn ?? currentRate }
```

- [ ] **Step 3: Implement them in `WebViewPlayerService`**

In `Sources/Player/WebViewPlayerService.swift`, add these methods right after the
`setAspectCover` line (line 144):

```swift
    func seekToLive() { evaluate("seekToLive()") }
    func setPlaybackRate(_ rate: Double) { evaluate("setPlaybackRate(\(rate))") }

    func liveDriftSeconds() async -> TimeInterval? {
        do {
            let result = try await webView.callAsyncJavaScript(
                "return liveDrift()", arguments: [:], in: nil, contentWorld: .page)
            if let n = result as? NSNumber { return n.doubleValue }
            return nil
        } catch {
            return nil
        }
    }

    func playbackRate() async -> Double {
        do {
            let result = try await webView.callAsyncJavaScript(
                "return getPlaybackRate()", arguments: [:], in: nil, contentWorld: .page)
            if let n = result as? NSNumber { return n.doubleValue }
            return 1.0
        } catch {
            return 1.0
        }
    }
```

- [ ] **Step 4: Add the JS functions to `player.html`**

In `Sources/Player/Resources/player.html`, add these functions right after the
`setMuted` function (line 119):

```javascript
    function seekToLive() {
      if (!player) return;
      try {
        var end = player.getDuration();
        if (isFinite(end) && end > 0) { player.seekTo(end, true); }
        player.playVideo();
      } catch (e) {}
    }
    function liveDrift() {
      if (!player) return null;
      try {
        var data = player.getVideoData();
        if (!data || !data.isLive) return null;
        var d = player.getDuration() - player.getCurrentTime();
        return (isFinite(d) && d >= 0) ? d : null;
      } catch (e) { return null; }
    }
    function setPlaybackRate(r) {
      if (!player) return;
      try { player.setPlaybackRate(r); } catch (e) {}
    }
    function getPlaybackRate() {
      if (!player) return 1;
      try { return player.getPlaybackRate(); } catch (e) { return 1; }
    }
```

- [ ] **Step 5: Build to verify everything compiles**

Run: `xcodebuild build -scheme 20Four7 -destination 'platform=iOS Simulator,name=iPhone 17'`
Expected: **BUILD SUCCEEDED**.

- [ ] **Step 6: Commit**

```bash
git add Sources/Player/PlayerService.swift Sources/Player/MockPlayerService.swift Sources/Player/WebViewPlayerService.swift Sources/Player/Resources/player.html
git commit -m "feat: add live-edge seek, playback-rate, and drift primitives to PlayerService"
```

---

## Task 2: Behind-live state in the controller

Adds the published `isBehindLive` flag and the supporting private state
(`rampToken`, `wantsLiveOnResume`, constants) and the `cancelRamp` helper, then
wires behind set/clear into the pause/start/stop/live-status paths. At this point
`rampToken` is always nil and `wantsLiveOnResume` always false (Task 3 makes the
ramp real), so `cancelRamp` is a harmless no-op here — it is introduced now so
the pause paths are fully wired.

**Files:**
- Modify: `Sources/Playback/PlaybackController.swift`
- Test: `Tests/PlaybackControllerTests.swift`

- [ ] **Step 1: Write the failing tests**

Append to `Tests/PlaybackControllerTests.swift`, just before the final closing
brace of `PlaybackControllerTests` (after `test_subSecondWatchIsDiscarded`,
around line 501):

```swift
    // MARK: - Behind-live detection

    func test_pausingLiveStreamMarksBehind() {
        let player = MockPlayerService()
        let c = PlaybackController(player: player, clock: ManualClock())
        c.setLineup(makeChannels())          // makeChannels() are isLiveExpected: true
        c.play(channelID: "a")
        player.simulate(state: .playing)
        XCTAssertFalse(c.isBehindLive)

        c.pauseFromUI()
        XCTAssertTrue(c.isBehindLive)
    }

    func test_pausingNonLiveStreamDoesNotMarkBehind() {
        let player = MockPlayerService()
        let c = PlaybackController(player: player, clock: ManualClock())
        let vod = Channel(id: "vod", title: "VOD", youTubeVideoID: "v", source: .curated, isLiveExpected: false)
        c.setLineup([vod])
        c.play(channelID: "vod")
        player.simulate(state: .playing)

        c.pauseFromUI()
        XCTAssertFalse(c.isBehindLive)
    }

    func test_backgroundPauseMarksLiveStreamBehind() {
        let player = MockPlayerService()
        let c = PlaybackController(player: player, clock: ManualClock())
        c.setLineup(makeChannels())
        c.play(channelID: "a")
        player.simulate(state: .playing)

        c.pauseForBackground()
        XCTAssertTrue(c.isBehindLive)
    }

    func test_surfingToAnotherChannelClearsBehind() {
        let player = MockPlayerService()
        let c = PlaybackController(player: player, clock: ManualClock())
        c.setLineup(makeChannels())
        c.play(channelID: "a")
        player.simulate(state: .playing)
        c.pauseFromUI()
        XCTAssertTrue(c.isBehindLive)

        c.surf(.next)                        // fresh load is at the live edge
        XCTAssertFalse(c.isBehindLive)
    }

    func test_liveStatusFalseClearsBehind() {
        let player = MockPlayerService()
        let c = PlaybackController(player: player, clock: ManualClock())
        c.setLineup(makeChannels())
        c.play(channelID: "a")
        player.simulate(state: .playing)
        c.pauseFromUI()
        XCTAssertTrue(c.isBehindLive)

        player.simulate(event: .liveStatusDetected(isLive: false))
        XCTAssertFalse(c.isBehindLive)
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `xcodebuild test -scheme 20Four7 -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TwentyFourSevenTests/PlaybackControllerTests/test_pausingLiveStreamMarksBehind`
Expected: compile failure — `value of type 'PlaybackController' has no member 'isBehindLive'`.

- [ ] **Step 3: Add the published flag and private state**

In `Sources/Playback/PlaybackController.swift`, add the published flag right
after `@Published private(set) var isAutoSurfActive = false` (line 14):

```swift
    @Published private(set) var isBehindLive = false
```

Add the private state right after `private var currentStartTime: TimeInterval = 0`
(line 36):

```swift
    /// The in-progress 2× catch-up ramp's restore-to-1× timer, if any.
    private var rampToken: ClockToken?
    /// Set only while a 2× catch-up ramp is running. Preserved across a
    /// background pause so the next resume jumps straight to live; cleared by any
    /// deliberate exit (manual pause, stop, new channel) and on ramp completion.
    private var wantsLiveOnResume = false
    private let catchUpThresholdSeconds: TimeInterval = 30
    private let catchUpRate: Double = 2.0
```

- [ ] **Step 4: Add the `cancelRamp` helper**

In `Sources/Playback/PlaybackController.swift`, add this method right after
`handleContentProcessTermination()` (after line 204):

```swift
    /// Cancel any in-progress catch-up ramp and restore normal speed. Pass
    /// `clearLiveIntent: false` only for an involuntary background pause, so the
    /// next resume still jumps to live; deliberate exits pass `true`.
    private func cancelRamp(clearLiveIntent: Bool) {
        if rampToken != nil {
            rampToken?.cancel()
            rampToken = nil
            player.setPlaybackRate(1.0)
        }
        if clearLiveIntent { wantsLiveOnResume = false }
    }
```

- [ ] **Step 5: Wire behind set/clear into the lifecycle methods**

In `pauseFromUI()` (lines 163-169), replace the method body so it reads:

```swift
    func pauseFromUI() {
        isManuallyPaused = true
        userIntendsPlayback = false
        cancelRamp(clearLiveIntent: true)
        if isCurrentlyLive { isBehindLive = true }
        player.pause()
        autoSurfToken?.cancel()
        autoSurfToken = nil
    }
```

In `pauseForBackground()` (lines 174-180), replace the method body so it reads:

```swift
    func pauseForBackground() {
        isForeground = false
        flushWatchSegment()
        cancelRamp(clearLiveIntent: false)
        if isCurrentlyLive { isBehindLive = true }
        player.pause()
        autoSurfToken?.cancel()
        autoSurfToken = nil
    }
```

In `stop()` (lines 144-151), replace the method body so it reads:

```swift
    func stop() {
        isManuallyPaused = false
        userIntendsPlayback = false
        cancelRamp(clearLiveIntent: true)
        isBehindLive = false
        flushWatchSegment()
        player.pause()
        cancelSleepTimer()
        stopAutoSurf()
    }
```

In `start(_:startTime:userInitiated:)` (lines 206-216), add two lines right after
`flushWatchSegment()` (the first line of the method):

```swift
        flushWatchSegment()
        cancelRamp(clearLiveIntent: true)
        isBehindLive = false
```

In the `eventPublisher` sink's `.liveStatusDetected` case (lines 87-91), add the
clear-on-not-live line:

```swift
                case .liveStatusDetected(let isLive):
                    self?.isCurrentlyLive = isLive
                    if !isLive { self?.isBehindLive = false }
                    if let channel = self?.currentChannel {
                        self?.channelStore?.updateLiveStatus(channelID: channel.id, isLive: isLive)
                    }
```

- [ ] **Step 6: Run the new tests to verify they pass**

Run: `xcodebuild test -scheme 20Four7 -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TwentyFourSevenTests/PlaybackControllerTests/test_pausingLiveStreamMarksBehind -only-testing:TwentyFourSevenTests/PlaybackControllerTests/test_pausingNonLiveStreamDoesNotMarkBehind -only-testing:TwentyFourSevenTests/PlaybackControllerTests/test_backgroundPauseMarksLiveStreamBehind -only-testing:TwentyFourSevenTests/PlaybackControllerTests/test_surfingToAnotherChannelClearsBehind -only-testing:TwentyFourSevenTests/PlaybackControllerTests/test_liveStatusFalseClearsBehind`
Expected: all five PASS.

- [ ] **Step 7: Commit**

```bash
git add Sources/Playback/PlaybackController.swift Tests/PlaybackControllerTests.swift
git commit -m "feat: mark a paused/backgrounded live stream as behind live"
```

---

## Task 3: Go Live — ramp, seek, and clamp fallback

Implements `goLive()`: a one-shot drift query, a 2× ramp when within 30s, an
instant seek when far, and a fallback seek when the platform clamps the rate.

**Files:**
- Modify: `Sources/Playback/PlaybackController.swift`
- Test: `Tests/PlaybackControllerTests.swift`

- [ ] **Step 1: Write the failing tests**

Append to `Tests/PlaybackControllerTests.swift`, just before the final closing
brace of `PlaybackControllerTests`:

```swift
    // MARK: - Go Live catch-up

    /// Pauses a freshly-played live channel so `isBehindLive` is true, returning
    /// the wired controller, player, and clock.
    private func behindLiveSetup() -> (PlaybackController, MockPlayerService, ManualClock) {
        let player = MockPlayerService()
        let clock = ManualClock()
        let c = PlaybackController(player: player, clock: clock)
        c.setLineup(makeChannels())
        c.play(channelID: "a")
        player.simulate(state: .playing)
        c.pauseFromUI()
        return (c, player, clock)
    }

    func test_goLiveRampsWhenCloseToLive() async {
        let (c, player, clock) = behindLiveSetup()
        player.driftToReturn = 10            // 10s behind, within the 30s window

        await c.goLive()

        XCTAssertEqual(player.rateHistory.last, 2.0)   // ramped to 2×
        XCTAssertEqual(player.seekToLiveCount, 0)      // ramp, not a hard seek
        XCTAssertFalse(c.isBehindLive)                 // committed to live

        // Catch-up completes after 10 / (2 − 1) = 10s, restoring 1×.
        clock.advance(by: 10)
        XCTAssertEqual(player.rateHistory.last, 1.0)
    }

    func test_goLiveSeeksWhenFarBehind() async {
        let (c, player, _) = behindLiveSetup()
        player.driftToReturn = 120           // beyond the 30s window

        await c.goLive()

        XCTAssertEqual(player.seekToLiveCount, 1)
        XCTAssertTrue(player.rateHistory.isEmpty)      // never touched the rate
        XCTAssertFalse(c.isBehindLive)
    }

    func test_goLiveFallsBackToSeekWhenRateClamped() async {
        let (c, player, clock) = behindLiveSetup()
        player.driftToReturn = 10
        player.rateToReturn = 1.0            // YouTube refuses the rate change

        await c.goLive()

        XCTAssertEqual(player.seekToLiveCount, 1)      // fell back to a hard seek
        XCTAssertEqual(player.rateHistory.last, 1.0)   // attempt was undone to 1×
        XCTAssertFalse(c.isBehindLive)

        clock.advance(by: 60)                          // no ramp was scheduled
        XCTAssertEqual(player.rateHistory.last, 1.0)
    }

    func test_goLiveIsNoOpWhenNotBehind() async {
        let player = MockPlayerService()
        let c = PlaybackController(player: player, clock: ManualClock())
        c.setLineup(makeChannels())
        c.play(channelID: "a")
        player.simulate(state: .playing)     // at the edge, not behind
        player.driftToReturn = 10

        await c.goLive()

        XCTAssertEqual(player.seekToLiveCount, 0)
        XCTAssertTrue(player.rateHistory.isEmpty)
    }

    func test_manualPauseDuringRampRestoresRateAndClearsIntent() async {
        let (c, player, clock) = behindLiveSetup()
        player.driftToReturn = 10
        await c.goLive()
        XCTAssertEqual(player.rateHistory.last, 2.0)

        c.pauseFromUI()                      // deliberate exit
        XCTAssertEqual(player.rateHistory.last, 1.0)   // rate restored immediately

        clock.advance(by: 30)                          // ramp token cancelled
        XCTAssertEqual(player.rateHistory.last, 1.0)

        c.playFromUI()                       // deliberate exit cleared intent
        XCTAssertEqual(player.seekToLiveCount, 0)
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `xcodebuild test -scheme 20Four7 -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TwentyFourSevenTests/PlaybackControllerTests/test_goLiveRampsWhenCloseToLive`
Expected: compile failure — `value of type 'PlaybackController' has no member 'goLive'`.

- [ ] **Step 3: Implement `goLive()`**

In `Sources/Playback/PlaybackController.swift`, add this method right after
`cancelRamp(clearLiveIntent:)` (added in Task 2):

```swift
    /// Catch up to the live edge. Within `catchUpThresholdSeconds` of live, ramp
    /// playback to `catchUpRate` and coast to the edge; otherwise — or if the
    /// platform clamps/refuses the rate — seek straight there. No-op unless
    /// behind live.
    func goLive() async {
        guard isBehindLive else { return }
        isBehindLive = false
        isManuallyPaused = false
        userIntendsPlayback = true
        player.play()

        let drift = await player.liveDriftSeconds()
        guard let drift, drift > 0, drift <= catchUpThresholdSeconds else {
            player.seekToLive()
            return
        }
        player.setPlaybackRate(catchUpRate)
        let applied = await player.playbackRate()
        guard applied > 1.0 else {
            player.setPlaybackRate(1.0)        // rate refused → undo and hard-seek
            player.seekToLive()
            return
        }
        guard isForeground else {              // backgrounded mid-query: don't ramp
            player.setPlaybackRate(1.0)
            return
        }
        wantsLiveOnResume = true
        let rampDuration = drift / (applied - 1.0)
        rampToken = clock.schedule(after: rampDuration) { [weak self] in
            guard let self else { return }
            self.player.setPlaybackRate(1.0)
            self.wantsLiveOnResume = false
            self.rampToken = nil
        }
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `xcodebuild test -scheme 20Four7 -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TwentyFourSevenTests/PlaybackControllerTests/test_goLiveRampsWhenCloseToLive -only-testing:TwentyFourSevenTests/PlaybackControllerTests/test_goLiveSeeksWhenFarBehind -only-testing:TwentyFourSevenTests/PlaybackControllerTests/test_goLiveFallsBackToSeekWhenRateClamped -only-testing:TwentyFourSevenTests/PlaybackControllerTests/test_goLiveIsNoOpWhenNotBehind -only-testing:TwentyFourSevenTests/PlaybackControllerTests/test_manualPauseDuringRampRestoresRateAndClearsIntent`
Expected: all five PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/Playback/PlaybackController.swift Tests/PlaybackControllerTests.swift
git commit -m "feat: Go Live catch-up with 2x ramp, seek, and clamp fallback"
```

---

## Task 4: Remember an interrupted catch-up across backgrounding

Adds the `playFromUI()` resume hook so that a ramp interrupted by backgrounding
jumps straight to live on the next resume, while deliberate exits do not.

**Files:**
- Modify: `Sources/Playback/PlaybackController.swift:153-161`
- Test: `Tests/PlaybackControllerTests.swift`

- [ ] **Step 1: Write the failing tests**

Append to `Tests/PlaybackControllerTests.swift`, just before the final closing
brace of `PlaybackControllerTests` (the `behindLiveSetup` helper from Task 3 is
reused):

```swift
    // MARK: - Interrupted catch-up

    func test_interruptedRampJumpsToLiveOnForegroundResume() async {
        let (c, player, _) = behindLiveSetup()
        player.driftToReturn = 10
        await c.goLive()                     // ramp begins; wantsLiveOnResume set
        XCTAssertEqual(player.seekToLiveCount, 0)

        c.pauseForBackground()               // involuntary: keep the live intent
        XCTAssertEqual(player.rateHistory.last, 1.0)   // ramp cancelled, rate restored

        c.enterForeground(autoResume: true)  // resumes via playFromUI → seek to live
        XCTAssertEqual(player.seekToLiveCount, 1)
        XCTAssertFalse(c.isBehindLive)
    }

    func test_interruptedRampJumpsToLiveOnManualPlayWhenAutoResumeOff() async {
        let (c, player, _) = behindLiveSetup()
        player.driftToReturn = 10
        await c.goLive()

        c.pauseForBackground()
        c.enterForeground(autoResume: false) // stays paused, intent preserved
        XCTAssertEqual(player.seekToLiveCount, 0)

        c.playFromUI()                       // user taps play → seek to live
        XCTAssertEqual(player.seekToLiveCount, 1)
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `xcodebuild test -scheme 20Four7 -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TwentyFourSevenTests/PlaybackControllerTests/test_interruptedRampJumpsToLiveOnForegroundResume`
Expected: FAIL — `seekToLiveCount` is 0 (the resume hook does not exist yet).

- [ ] **Step 3: Add the resume hook to `playFromUI()`**

In `Sources/Playback/PlaybackController.swift`, replace `playFromUI()`
(lines 153-161) so it reads:

```swift
    func playFromUI() {
        isManuallyPaused = false
        userIntendsPlayback = true
        player.play()
        if wantsLiveOnResume {
            wantsLiveOnResume = false
            isBehindLive = false
            player.seekToLive()
        }
        if isAutoSurfActive {
            lastTickTime = clock.now()
            scheduleNextAutoSurfTick()
        }
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `xcodebuild test -scheme 20Four7 -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TwentyFourSevenTests/PlaybackControllerTests/test_interruptedRampJumpsToLiveOnForegroundResume -only-testing:TwentyFourSevenTests/PlaybackControllerTests/test_interruptedRampJumpsToLiveOnManualPlayWhenAutoResumeOff`
Expected: both PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/Playback/PlaybackController.swift Tests/PlaybackControllerTests.swift
git commit -m "feat: jump straight to live when a catch-up ramp is interrupted by backgrounding"
```

---

## Task 5: Go Live UI — gray badge and capsule button

The LIVE badge turns gray (status only) when behind; a `forward.end.fill` Go Live
button appears in the control capsule, wired to `goLive()`. No unit test (the
codebase does not unit-test SwiftUI views); verified by a clean build.

**Files:**
- Modify: `Sources/UI/PlayerOverlay.swift`
- Modify: `Sources/UI/PlayerView.swift:34-46`

- [ ] **Step 1: Make the LIVE badge gray when behind**

In `Sources/UI/PlayerOverlay.swift`, replace the LIVE badge block (lines 38-42)
so it reads:

```swift
                            if controller.isCurrentlyLive {
                                Text("● LIVE")
                                    .font(m.overlayLiveFont)
                                    .foregroundStyle(controller.isBehindLive ? Color.gray : Color.red)
                            }
```

- [ ] **Step 2: Add the `onGoLive` closure property**

In `Sources/UI/PlayerOverlay.swift`, add the property right after
`let onClose: () -> Void` (line 14):

```swift
    let onGoLive: () -> Void
```

- [ ] **Step 3: Add the Go Live button to the control capsule**

In `Sources/UI/PlayerOverlay.swift`, the control capsule's first button is the
play/pause button ending with `.buttonStyle(.plain)` (line 88). Insert the Go
Live button immediately after that line, before the favorite `Button`:

```swift
                    if controller.isCurrentlyLive && controller.isBehindLive {
                        Button {
                            onInteraction()
                            onGoLive()
                        } label: {
                            Image(systemName: "forward.end.fill")
                                .frame(width: m.controlSize, height: m.controlSize)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
```

- [ ] **Step 4: Wire `onGoLive` from `PlayerView`**

In `Sources/UI/PlayerView.swift`, the `PlayerOverlay(...)` initializer passes
`onClose: onClose,` then `activeTag: activeCategoryName` (lines 44-45). Insert the
`onGoLive` argument between them:

```swift
                    onClose: onClose,
                    onGoLive: { Task { await controller.goLive() } },
                    activeTag: activeCategoryName
```

- [ ] **Step 5: Build to verify everything compiles**

Run: `xcodebuild build -scheme 20Four7 -destination 'platform=iOS Simulator,name=iPhone 17'`
Expected: **BUILD SUCCEEDED**.

- [ ] **Step 6: Commit**

```bash
git add Sources/UI/PlayerOverlay.swift Sources/UI/PlayerView.swift
git commit -m "feat: gray LIVE badge and Go Live control when behind the live edge"
```

---

## Task 6: Full verification

**Files:** none (verification only).

- [ ] **Step 1: Run the entire test suite**

Run: `xcodebuild test -scheme 20Four7 -destination 'platform=iOS Simulator,name=iPhone 17'`
Expected: **TEST SUCCEEDED** — all `PlaybackControllerTests` (existing + 12 new)
and every other suite pass.

- [ ] **Step 2: Confirm the working tree is clean**

Run: `git status`
Expected: nothing to commit, working tree clean (all changes were committed in
Tasks 1–5).

---

## Self-Review notes

- **Spec coverage:** behind-detection (Task 2), the three triggers — manual pause
  + background (Task 2), Go Live ramp/seek/clamp fallback (Task 3), interrupted
  catch-up across backgrounding (Task 4), gray badge + capsule button (Task 5),
  and the full test plan (Tasks 2–4, run together in Task 6) are each implemented.
- **Async testability:** `goLive()` is `async` and awaited directly in tests; the
  ramp's restore-to-1× runs inside a synchronous `ManualClock` closure (no nested
  `Task`), so `clock.advance(by:)` deterministically drives completion.
- **Type consistency:** `seekToLive()`, `setPlaybackRate(_:)`,
  `liveDriftSeconds() async -> TimeInterval?`, `playbackRate() async -> Double`,
  `isBehindLive`, `wantsLiveOnResume`, `rampToken`, `cancelRamp(clearLiveIntent:)`,
  and `goLive()` are named identically across protocol, mock, controller, and
  tests.
- **No new files**, so XcodeGen regeneration is intentionally omitted.
