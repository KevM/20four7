# Dwell-Boost Channel Ranking Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rank channels by how long the user actually watches them (dwell time), so a channel left running for days reliably tops its tag, and refresh a channel's recency when the user edits it.

**Architecture:** Today the popularity score is `playCount + recencyBoost` ([ChannelStore.swift:162](../../../Sources/Stores/ChannelStore.swift)), with a single +1 per channel open and a 7-day linear recency decay anchored to a `lastPlayedDate` that is stamped once at session start and never refreshed. This plan (1) accumulates real watch seconds per channel via segment tracking + a periodic heartbeat in `PlaybackController`, persisting them to `ChannelUserState`; (2) replaces the scoring formula with a pure, testable `ChannelRanker` that adds a **log-compressed (bounded/fair)** dwell term and keeps recency anchored to the heartbeat-refreshed `lastPlayedDate`; and (3) refreshes `lastPlayedDate` (recency only, no score bump) when a channel is edited.

**Tech Stack:** Swift 5 / SwiftUI, SwiftData persistence, XCTest, Combine. Test module name is `TwentyFourSeven`. Tests use `ManualClock` + `MockPlayerService` + `Persistence.makeContainer(inMemory: true)`.

---

## Design decisions (locked from brainstorming)

- **Dwell weight: bounded / fair.** Use `dwellBoost = dwellWeight * log2(1 + watchHours)`. Log compression means a marathon lean-back channel (nest cam) reliably reaches the top of its tag but hits diminishing returns, so it can't permanently bury everything else. Chosen constant `dwellWeight = 4.0`:
  - 1 h watched → `4 * log2(2)` = **4.0**
  - 10 h → `4 * log2(11)` ≈ **13.8**
  - 48 h (the eagle-cam case) → `4 * log2(49)` ≈ **22.4**
  - 192 h (8 days) → `4 * log2(193)` ≈ **30.4** (4× the watch time past 2 days adds only ~8 pts — the "fair" cap)
  These dominate plausible `playCount` values (single/low-double digits), so a 2-day session tops its tag, while the log curve keeps it bounded. Constants live in one place (`ChannelRanker`) for easy tuning.
- **Recency window unchanged:** up to 10 pts decaying linearly over 7 days (604,800 s), now anchored to a `lastPlayedDate` that the heartbeat keeps fresh during long sessions (fixing the latent bug where a 2-day session *decayed* its own recency).
- **Edit = recency refresh only.** Editing a channel re-stamps `lastPlayedDate = now` (resurfaces via the recency term) but adds **no** lasting score. Favoriting already covers explicit lasting interest.
- **Heartbeat interval: 60 s.** Bounds data loss on crash/termination to ≤60 s of a long session and keeps `lastPlayedDate` fresh.

---

## File Structure

| File | Responsibility | Change |
| --- | --- | --- |
| `Sources/Core/ChannelRanker.swift` | Pure scoring function + tunable constants. Single source of truth for ranking. | **Create** |
| `Sources/Persistence/PersistenceModels.swift` | `ChannelUserState` gains `watchSeconds: Double?`. | Modify |
| `Sources/Models/Channel.swift` | In-memory `Channel` gains `watchSeconds: Double`. | Modify |
| `Sources/Core/ChannelMerger.swift` | Map persisted `watchSeconds` onto merged `Channel`. | Modify |
| `Sources/Persistence/LocalStore.swift` | `recordWatch(channelID:seconds:date:)` accumulator. | Modify |
| `Sources/Playback/PlaybackController.swift` | Watch-segment tracking + 60 s heartbeat + `onWatchAccrued` callback. | Modify |
| `Sources/App/AppEnvironment.swift` | Wire `onWatchAccrued` → `recordWatch` → store. | Modify |
| `Sources/Stores/ChannelStore.swift` | Use `ChannelRanker`; add `bumpWatchSeconds`; refresh recency in `editChannel`. | Modify |
| `Tests/ChannelRankerTests.swift` | Unit tests for the pure score. | **Create** |
| `Tests/LocalStoreTests.swift` | `recordWatch` accumulation test. | Modify |
| `Tests/PlaybackControllerTests.swift` | Segment + heartbeat watch-accrual tests. | Modify |
| `Tests/ChannelMergerTests.swift` | `watchSeconds` mapping test. | Modify |
| `Tests/ChannelStoreTests.swift` | Edit-refreshes-recency test. | Modify |

After editing `project.yml` is **not** required (no new build settings); new `.swift` files under `Sources/`/`Tests/` are picked up by the existing globs, but the Xcode project must be regenerated so the new files are compiled. Regenerate with `./generate.sh` (Task 9), never `xcodegen generate` directly (per CLAUDE.md).

---

## Task 1: Pure `ChannelRanker` scoring type

Extract scoring into a pure function so it is testable without `RemoteConfig`/network, and make it the single source of truth for ranking constants.

**Files:**
- Create: `Sources/Core/ChannelRanker.swift`
- Test: `Tests/ChannelRankerTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/ChannelRankerTests.swift`:

```swift
import XCTest
@testable import TwentyFourSeven

final class ChannelRankerTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    func test_playCountOnlyWhenNoWatchAndStaleRecency() {
        // lastPlayed 8 days ago -> recency 0, no watch -> score == playCount
        let lastPlayed = now.addingTimeInterval(-8 * 24 * 3600)
        let score = ChannelRanker.score(
            playCount: 5, watchSeconds: 0,
            lastPlayedDate: lastPlayed, dateAdded: lastPlayed, now: now)
        XCTAssertEqual(score, 5, accuracy: 0.0001)
    }

    func test_freshRecencyAddsFullBoost() {
        // lastPlayed == now -> full 10 recency, no watch
        let score = ChannelRanker.score(
            playCount: 0, watchSeconds: 0,
            lastPlayedDate: now, dateAdded: now, now: now)
        XCTAssertEqual(score, 10, accuracy: 0.0001)
    }

    func test_dwellBoostIsLogCompressed() {
        // 48h watched, stale recency (8 days) so only dwell shows.
        let stale = now.addingTimeInterval(-8 * 24 * 3600)
        let score = ChannelRanker.score(
            playCount: 0, watchSeconds: 48 * 3600,
            lastPlayedDate: stale, dateAdded: stale, now: now)
        // 4 * log2(1 + 48) ~= 22.46
        XCTAssertEqual(score, 4.0 * log2(49), accuracy: 0.0001)
    }

    func test_twoDayDwellBeatsManyTaps() {
        let stale = now.addingTimeInterval(-8 * 24 * 3600)
        let eagleCam = ChannelRanker.score(
            playCount: 1, watchSeconds: 48 * 3600,
            lastPlayedDate: stale, dateAdded: stale, now: now)
        let tappy = ChannelRanker.score(
            playCount: 9, watchSeconds: 0,
            lastPlayedDate: stale, dateAdded: stale, now: now)
        XCTAssertGreaterThan(eagleCam, tappy)
    }

    func test_dwellHasDiminishingReturns() {
        let stale = now.addingTimeInterval(-8 * 24 * 3600)
        let twoDays = ChannelRanker.score(
            playCount: 0, watchSeconds: 48 * 3600,
            lastPlayedDate: stale, dateAdded: stale, now: now)
        let eightDays = ChannelRanker.score(
            playCount: 0, watchSeconds: 192 * 3600,
            lastPlayedDate: stale, dateAdded: stale, now: now)
        // 4x the watch time past 2 days adds < 10 extra points.
        XCTAssertLessThan(eightDays - twoDays, 10)
    }

    func test_nilLastPlayedFallsBackToDateAdded() {
        let added = now.addingTimeInterval(-3.5 * 24 * 3600) // half the window
        let score = ChannelRanker.score(
            playCount: 0, watchSeconds: 0,
            lastPlayedDate: nil, dateAdded: added, now: now)
        XCTAssertEqual(score, 5, accuracy: 0.0001) // 10 * (1 - 0.5)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme 20Four7 -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TwentyFourSevenTests/ChannelRankerTests`
Expected: FAIL — compile error, `ChannelRanker` is undefined.

- [ ] **Step 3: Write minimal implementation**

Create `Sources/Core/ChannelRanker.swift`:

```swift
import Foundation

/// Single source of truth for channel popularity ranking. Pure and deterministic
/// so it can be unit-tested without persistence or network.
///
/// score = playCount
///       + dwellWeight * log2(1 + watchHours)   // bounded/fair dwell term
///       + recencyMax * (1 - age/recencyWindow) // linear 7-day recency decay
enum ChannelRanker {
    /// Recency decays linearly to 0 over this window (7 days).
    static let recencyWindow: TimeInterval = 604_800
    /// Maximum recency contribution at age 0.
    static let recencyMax: Double = 10
    /// Multiplier on the log-compressed watch-hours term. Tuned so a ~2-day
    /// continuous session (~22 pts) tops a tag while staying bounded.
    static let dwellWeight: Double = 4.0

    static func score(playCount: Int,
                      watchSeconds: Double,
                      lastPlayedDate: Date?,
                      dateAdded: Date,
                      now: Date) -> Double {
        let watchHours = max(0, watchSeconds) / 3600.0
        let dwellBoost = dwellWeight * log2(1 + watchHours)

        let reference = lastPlayedDate ?? dateAdded
        let age = now.timeIntervalSince(reference)
        let recencyBoost: Double
        if age >= 0 && age < recencyWindow {
            recencyBoost = recencyMax * (1 - age / recencyWindow)
        } else {
            recencyBoost = 0
        }

        return Double(playCount) + dwellBoost + recencyBoost
    }
}
```

- [ ] **Step 4: Regenerate project so the new file compiles, then run tests**

Run: `./generate.sh && xcodebuild test -scheme 20Four7 -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TwentyFourSevenTests/ChannelRankerTests`
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/ChannelRanker.swift Tests/ChannelRankerTests.swift project.yml 20Four7.xcodeproj
git commit -m "feat: add pure ChannelRanker with bounded dwell term"
```

---

## Task 2: Persist `watchSeconds` on `ChannelUserState`

**Files:**
- Modify: `Sources/Persistence/PersistenceModels.swift:30-64`

- [ ] **Step 1: Add the stored property and init parameter**

In `Sources/Persistence/PersistenceModels.swift`, add the property after `lastPlayedDate` (line 40):

```swift
    var playCount: Int?
    var lastPlayedDate: Date?
    var watchSeconds: Double?
```

Add the init parameter (after `lastPlayedDate: Date? = nil` at line 52):

```swift
        playCount: Int? = 0,
        lastPlayedDate: Date? = nil,
        watchSeconds: Double? = 0
```

Add the assignment (after `self.lastPlayedDate = lastPlayedDate` at line 63):

```swift
        self.lastPlayedDate = lastPlayedDate
        self.watchSeconds = watchSeconds
```

> **SwiftData note:** Adding a new optional property is a lightweight, automatic migration — existing rows read back `nil` (treated as 0 by readers). No schema version bump or manual migration is required.

- [ ] **Step 2: Build to verify it compiles**

Run: `xcodebuild build -scheme 20Four7 -destination 'platform=iOS Simulator,name=iPhone 17'`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add Sources/Persistence/PersistenceModels.swift
git commit -m "feat: add watchSeconds to ChannelUserState"
```

---

## Task 3: Carry `watchSeconds` onto the in-memory `Channel` via the merger

**Files:**
- Modify: `Sources/Models/Channel.swift:10-44`
- Modify: `Sources/Core/ChannelMerger.swift:29-30`
- Test: `Tests/ChannelMergerTests.swift`

- [ ] **Step 1: Write the failing test**

Add to `Tests/ChannelMergerTests.swift`:

```swift
    func test_appliesWatchSecondsFromState() {
        let channel = chan("a", video: "v1", source: .curated)
        let state = ChannelUserState(channelID: "a", watchSeconds: 7200)
        let merged = ChannelMerger.merge(curated: [channel], user: [], userStates: [state])
        XCTAssertEqual(merged.first?.watchSeconds, 7200)
    }

    func test_defaultsWatchSecondsToZeroWhenNoState() {
        let channel = chan("a", video: "v1", source: .curated)
        let merged = ChannelMerger.merge(curated: [channel], user: [], userStates: [])
        XCTAssertEqual(merged.first?.watchSeconds, 0)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme 20Four7 -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TwentyFourSevenTests/ChannelMergerTests`
Expected: FAIL — compile error, `Channel` has no member `watchSeconds`.

- [ ] **Step 3: Add `watchSeconds` to `Channel`**

In `Sources/Models/Channel.swift`, add the property after `lastPlayedDate` (line 20):

```swift
    var playCount: Int
    var lastPlayedDate: Date?
    var watchSeconds: Double
```

Add the init parameter (after `lastPlayedDate: Date? = nil` at line 32):

```swift
        playCount: Int = 0,
        lastPlayedDate: Date? = nil,
        watchSeconds: Double = 0
```

Add the assignment (after `self.lastPlayedDate = lastPlayedDate` at line 43):

```swift
        self.lastPlayedDate = lastPlayedDate
        self.watchSeconds = watchSeconds
```

- [ ] **Step 4: Map it in the merger**

In `Sources/Core/ChannelMerger.swift`, after the `modified.lastPlayedDate = state.lastPlayedDate` line (line 30), add:

```swift
                modified.playCount = state.playCount ?? 0
                modified.lastPlayedDate = state.lastPlayedDate
                modified.watchSeconds = state.watchSeconds ?? 0
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `xcodebuild test -scheme 20Four7 -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TwentyFourSevenTests/ChannelMergerTests`
Expected: PASS (existing tests + 2 new).

- [ ] **Step 6: Commit**

```bash
git add Sources/Models/Channel.swift Sources/Core/ChannelMerger.swift Tests/ChannelMergerTests.swift
git commit -m "feat: surface watchSeconds on Channel via merger"
```

---

## Task 4: `LocalStore.recordWatch` accumulator

**Files:**
- Modify: `Sources/Persistence/LocalStore.swift` (add after `setLastPlayedDate`, ~line 91)
- Test: `Tests/LocalStoreTests.swift`

- [ ] **Step 1: Write the failing test**

Add to `Tests/LocalStoreTests.swift`:

```swift
    func test_recordWatchAccumulatesAndStampsDate() throws {
        let store = try makeStore()
        let d1 = Date(timeIntervalSince1970: 1000)
        let r1 = store.recordWatch(channelID: "c1", seconds: 30, date: d1)
        XCTAssertEqual(r1.watchSeconds, 30, accuracy: 0.0001)
        XCTAssertEqual(r1.lastPlayedDate, d1)

        let d2 = Date(timeIntervalSince1970: 2000)
        let r2 = store.recordWatch(channelID: "c1", seconds: 45, date: d2)
        XCTAssertEqual(r2.watchSeconds, 75, accuracy: 0.0001)
        XCTAssertEqual(r2.lastPlayedDate, d2)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme 20Four7 -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TwentyFourSevenTests/LocalStoreTests/test_recordWatchAccumulatesAndStampsDate`
Expected: FAIL — compile error, `LocalStore` has no member `recordWatch`.

- [ ] **Step 3: Implement `recordWatch`**

In `Sources/Persistence/LocalStore.swift`, add after `setLastPlayedDate(channelID:date:)` (after line 91):

```swift
    /// Accumulate watch time for a channel and refresh its lastPlayedDate so the
    /// recency term stays fresh during long sessions. Returns the new running total.
    @discardableResult
    func recordWatch(channelID: String, seconds: TimeInterval, date: Date = Date()) -> (watchSeconds: Double, lastPlayedDate: Date) {
        let total: Double
        if let existing = userState(for: channelID) {
            let next = (existing.watchSeconds ?? 0) + seconds
            existing.watchSeconds = next
            existing.lastPlayedDate = date
            total = next
        } else {
            let state = ChannelUserState(channelID: channelID, watchSeconds: seconds, lastPlayedDate: date)
            context.insert(state)
            total = seconds
        }
        try? context.save()
        return (total, date)
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme 20Four7 -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TwentyFourSevenTests/LocalStoreTests/test_recordWatchAccumulatesAndStampsDate`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/Persistence/LocalStore.swift Tests/LocalStoreTests.swift
git commit -m "feat: add LocalStore.recordWatch accumulator"
```

---

## Task 5: Watch-segment tracking + heartbeat in `PlaybackController`

Accumulate watch time only while a channel is the current channel **and** the player state is `.playing`. Flush on every transition that ends a segment (channel change, pause, background, stop) and on a 60 s heartbeat (so long continuous sessions still persist + refresh recency). Emit accrued seconds via `onWatchAccrued`.

**Files:**
- Modify: `Sources/Playback/PlaybackController.swift`
- Test: `Tests/PlaybackControllerTests.swift`

- [ ] **Step 1: Write the failing tests**

Add to `Tests/PlaybackControllerTests.swift`:

```swift
    func test_watchAccruesOnPause() {
        let player = MockPlayerService()
        let clock = ManualClock()
        let c = PlaybackController(player: player, clock: clock)
        var accrued: [(String, TimeInterval)] = []
        c.onWatchAccrued = { id, secs in accrued.append((id, secs)) }
        c.setLineup(makeChannels())
        c.play(channelID: "a")          // -> .playing, segment starts at t=0
        clock.advance(by: 30)
        c.pauseFromUI()                 // -> .paused, flush 30s for "a"
        XCTAssertEqual(accrued.count, 1)
        XCTAssertEqual(accrued.first?.0, "a")
        XCTAssertEqual(accrued.first?.1 ?? 0, 30, accuracy: 0.0001)
    }

    func test_watchAccruesToOldChannelOnSurf() {
        let player = MockPlayerService()
        let clock = ManualClock()
        let c = PlaybackController(player: player, clock: clock)
        var accrued: [(String, TimeInterval)] = []
        c.onWatchAccrued = { id, secs in accrued.append((id, secs)) }
        c.setLineup(makeChannels())
        c.play(channelID: "a")
        clock.advance(by: 20)
        c.surf(.next)                   // flush 20s to "a" before switching to "b"
        XCTAssertEqual(accrued.first?.0, "a")
        XCTAssertEqual(accrued.first?.1 ?? 0, 20, accuracy: 0.0001)
    }

    func test_watchHeartbeatFlushesDuringLongSession() {
        let player = MockPlayerService()
        let clock = ManualClock()
        let c = PlaybackController(player: player, clock: clock)
        var accrued: [(String, TimeInterval)] = []
        c.onWatchAccrued = { id, secs in accrued.append((id, secs)) }
        c.setLineup(makeChannels())
        c.play(channelID: "a")          // segment + heartbeat scheduled at t=60
        clock.advance(by: 60)           // heartbeat #1 -> flush 60s, reschedule
        clock.advance(by: 60)           // heartbeat #2 -> flush 60s
        XCTAssertEqual(accrued.count, 2)
        XCTAssertEqual(accrued.allSatisfy { $0.0 == "a" }, true)
        XCTAssertEqual(accrued.reduce(0) { $0 + $1.1 }, 120, accuracy: 0.0001)
    }

    func test_noWatchAccruesWhilePaused() {
        let player = MockPlayerService()
        let clock = ManualClock()
        let c = PlaybackController(player: player, clock: clock)
        var total: TimeInterval = 0
        c.onWatchAccrued = { _, secs in total += secs }
        c.setLineup(makeChannels())
        c.play(channelID: "a")
        clock.advance(by: 10)
        c.pauseFromUI()                 // flush 10s
        clock.advance(by: 100)          // paused: nothing accrues
        XCTAssertEqual(total, 10, accuracy: 0.0001)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme 20Four7 -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TwentyFourSevenTests/PlaybackControllerTests`
Expected: FAIL — compile error, `PlaybackController` has no member `onWatchAccrued`.

- [ ] **Step 3: Add state, callback, and segment helpers**

In `Sources/Playback/PlaybackController.swift`, add stored properties after `lastTickTime` (line 24):

```swift
    private var lastTickTime = Date(timeIntervalSince1970: 0)
    private var watchSegmentStart: Date?
    private var watchHeartbeatToken: ClockToken?
    private let watchHeartbeatInterval: TimeInterval = 60
```

Add the callback after `onChannelChanged` (line 28):

```swift
    var onChannelChanged: ((Channel, _ userInitiated: Bool, _ isAutoSurf: Bool) -> Void)?

    /// Called when watch time accrues for a channel (on pause, channel change,
    /// stop, background, or the 60s heartbeat). Caller persists it.
    var onWatchAccrued: ((_ channelID: String, _ seconds: TimeInterval) -> Void)?
```

Add the segment helpers at the end of the type, before the closing brace (after `handleAutoSurfTick()` ends at line 215):

```swift
    // MARK: Watch-time tracking

    /// Begin a watch segment if a channel is actively playing. Idempotent.
    private func beginWatchSegment() {
        guard currentChannel != nil, state == .playing, watchSegmentStart == nil else { return }
        watchSegmentStart = clock.now()
        scheduleWatchHeartbeat()
    }

    /// Flush the current segment's elapsed time to `onWatchAccrued` and end it.
    /// Idempotent: a no-op when no segment is open.
    private func flushWatchSegment() {
        watchHeartbeatToken?.cancel()
        watchHeartbeatToken = nil
        guard let start = watchSegmentStart, let channel = currentChannel else {
            watchSegmentStart = nil
            return
        }
        watchSegmentStart = nil
        let elapsed = clock.now().timeIntervalSince(start)
        if elapsed > 0 {
            onWatchAccrued?(channel.id, elapsed)
        }
    }

    private func scheduleWatchHeartbeat() {
        watchHeartbeatToken?.cancel()
        watchHeartbeatToken = clock.schedule(after: watchHeartbeatInterval) { [weak self] in
            self?.handleWatchHeartbeat()
        }
    }

    private func handleWatchHeartbeat() {
        // Flush accrued time, then reopen a fresh segment if still playing.
        flushWatchSegment()
        beginWatchSegment()
    }
```

- [ ] **Step 4: Wire begin/flush into the lifecycle**

In `bind()`, replace the `statePublisher` sink (lines 38-42) so state transitions drive segments:

```swift
        player.statePublisher
            .sink { [weak self] state in
                guard let self else { return }
                let wasPlaying = self.state == .playing
                self.state = state
                if state == .playing {
                    self.beginWatchSegment()
                } else if wasPlaying {
                    self.flushWatchSegment()
                }
            }
            .store(in: &cancellables)
```

In `start(_:startTime:userInitiated:)`, flush the **previous** channel's segment before `currentChannel` is reassigned. Change the first line of `start` (line 144) from:

```swift
    private func start(_ channel: Channel, startTime: TimeInterval = 0, userInitiated: Bool) {
        currentChannel = channel
```

to:

```swift
    private func start(_ channel: Channel, startTime: TimeInterval = 0, userInitiated: Bool) {
        flushWatchSegment()
        currentChannel = channel
```

In `stop()` (line 111), flush before pausing so the final segment is attributed:

```swift
    func stop() {
        isManuallyPaused = false
        flushWatchSegment()
        player.pause()
        cancelSleepTimer()
        stopAutoSurf()
    }
```

In `pauseForBackground()` (line 137), flush explicitly (the real web player may not deliver a synchronous `.paused` while backgrounding):

```swift
    func pauseForBackground() {
        flushWatchSegment()
        player.pause()
        autoSurfToken?.cancel()
        autoSurfToken = nil
    }
```

> **Why both the state sink and explicit flushes?** `flushWatchSegment()` is idempotent, so the belt-and-suspenders calls in `start`/`stop`/`pauseForBackground` are safe even when the state publisher also fires `.paused`. The `MockPlayerService` sends `.paused` synchronously (so `pauseFromUI` is covered by the sink), but background teardown on the real player is not guaranteed synchronous, hence the explicit flush there.

- [ ] **Step 5: Run tests to verify they pass**

Run: `xcodebuild test -scheme 20Four7 -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TwentyFourSevenTests/PlaybackControllerTests`
Expected: PASS (existing tests + 4 new).

- [ ] **Step 6: Commit**

```bash
git add Sources/Playback/PlaybackController.swift Tests/PlaybackControllerTests.swift
git commit -m "feat: track watch time with segments and 60s heartbeat"
```

---

## Task 6: Wire watch accrual through `AppEnvironment` to the store

**Files:**
- Modify: `Sources/App/AppEnvironment.swift:30-41`

- [ ] **Step 1: Add the `onWatchAccrued` wiring**

In `Sources/App/AppEnvironment.swift`, after the `onChannelChanged` closure assignment (after line 41), add:

```swift
        playback.onWatchAccrued = { [weak local, weak store] channelID, seconds in
            guard let stats = local?.recordWatch(channelID: channelID, seconds: seconds) else { return }
            Task { @MainActor in
                store?.bumpWatchSeconds(channelID: channelID,
                                        watchSeconds: stats.watchSeconds,
                                        lastPlayedDate: stats.lastPlayedDate)
            }
        }
```

> `store?.bumpWatchSeconds` is added in Task 7; this file will not compile until Task 7 lands. Both tasks are committed together via Task 7's build/commit step — or implement Task 7 first if working strictly file-by-file.

- [ ] **Step 2: Do not build yet (depends on Task 7)**

Proceed to Task 7, which adds `bumpWatchSeconds` and the scoring switch, then build both together.

- [ ] **Step 3: Stage (commit happens in Task 7)**

```bash
git add Sources/App/AppEnvironment.swift
```

---

## Task 7: Switch `ChannelStore` to `ChannelRanker`, add `bumpWatchSeconds`, refresh recency on edit

**Files:**
- Modify: `Sources/Stores/ChannelStore.swift:162-177` (scoring), `:271-293` (edit), `:306-312` (bump)
- Test: `Tests/ChannelStoreTests.swift`

- [ ] **Step 1: Write the failing test**

Add to `Tests/ChannelStoreTests.swift`. This drives a real user channel through `editChannel` and asserts the merged in-memory channel's `lastPlayedDate` is refreshed to ~now (recency-only signal):

```swift
    func test_editChannelRefreshesRecency() throws {
        let localStore = try makeStore()
        let remoteConfig = makeRemoteConfig()

        // Seed a user channel with a stale lastPlayedDate.
        let userChannel = Channel(
            id: "user-vid", title: "Old Title", youTubeVideoID: "abcdefghijk",
            source: .user, isLiveExpected: true, tagIDs: ["mine"])
        localStore.addUserChannel(userChannel)
        let stale = Date(timeIntervalSince1970: 0)
        _ = localStore.recordWatch(channelID: "user-vid", seconds: 5, date: stale)

        let store = ChannelStore(remoteConfig: remoteConfig, localStore: localStore)
        let original = try XCTUnwrap(store.channels.first { $0.id == "user-vid" })
        XCTAssertEqual(original.lastPlayedDate, stale)
        let watchBefore = original.watchSeconds

        let before = Date()
        store.editChannel(original, title: "New Title", tagIDs: ["mine"],
                          isLiveExpected: true, isFavorite: false)

        let edited = try XCTUnwrap(store.channels.first { $0.id == "user-vid" })
        // Recency refreshed (lastPlayedDate ~ now)...
        let lp = try XCTUnwrap(edited.lastPlayedDate)
        XCTAssertGreaterThanOrEqual(lp, before)
        // ...but no lasting score added: watchSeconds unchanged.
        XCTAssertEqual(edited.watchSeconds, watchBefore, accuracy: 0.0001)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme 20Four7 -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TwentyFourSevenTests/ChannelStoreTests/test_editChannelRefreshesRecency`
Expected: FAIL — `editChannel` does not refresh `lastPlayedDate`, so the assertion `lp >= before` fails.

- [ ] **Step 3: Replace `popularityScore` body to delegate to `ChannelRanker`**

In `Sources/Stores/ChannelStore.swift`, replace the whole `popularityScore` method (lines 162-177) with:

```swift
    private func popularityScore(for channel: Channel, now: Date) -> Double {
        ChannelRanker.score(playCount: channel.playCount,
                            watchSeconds: channel.watchSeconds,
                            lastPlayedDate: channel.lastPlayedDate,
                            dateAdded: channel.dateAdded,
                            now: now)
    }
```

- [ ] **Step 4: Add `bumpWatchSeconds`**

In `Sources/Stores/ChannelStore.swift`, add after `bumpPlayCount` (after line 312):

```swift
    func bumpWatchSeconds(channelID: String, watchSeconds: Double, lastPlayedDate: Date) {
        if let idx = channels.firstIndex(where: { $0.id == channelID }) {
            channels[idx].watchSeconds = watchSeconds
            channels[idx].lastPlayedDate = lastPlayedDate
            recomputeFilteredChannels()
        }
    }
```

- [ ] **Step 5: Refresh recency in `editChannel`**

In `editChannel` (lines 271-293), capture the authoritative id in each branch and re-stamp `lastPlayedDate` before `reloadLineup()`. Replace the `switch` + trailing `reloadLineup()` (lines 277-292) with:

```swift
        let authoritativeID: String
        switch original.source {
        case .user:
            localStore.updateUserChannel(id: original.id, title: finalTitle,
                                         youTubeVideoID: original.youTubeVideoID,
                                         isLiveExpected: isLiveExpected, tagIDs: cleanTags)
            localStore.setFavorite(channelID: original.id, isFavorite: isFavorite)
            authoritativeID = original.id
        case .curated:
            let adopted = Channel(
                id: "user-\(original.youTubeVideoID)", title: finalTitle,
                youTubeVideoID: original.youTubeVideoID, thumbnailURL: original.thumbnailURL,
                source: .user, isLiveExpected: isLiveExpected,
                dateAdded: original.dateAdded, tagIDs: cleanTags)
            localStore.adoptCuratedChannel(adopted, fromCuratedID: original.id)
            localStore.setFavorite(channelID: adopted.id, isFavorite: isFavorite)
            authoritativeID = adopted.id
        }
        // Editing is an interest signal: refresh recency only (no lasting score bump).
        // setFavorite above guarantees a ChannelUserState row exists for this id.
        localStore.setLastPlayedDate(channelID: authoritativeID, date: Date())
        reloadLineup()
```

- [ ] **Step 6: Run the full suite**

Run: `xcodebuild test -scheme 20Four7 -destination 'platform=iOS Simulator,name=iPhone 17'`
Expected: PASS — all tests, including `test_editChannelRefreshesRecency` and the new ranker/playback/merger/localstore tests.

- [ ] **Step 7: Commit (includes Task 6's staged change)**

```bash
git add Sources/Stores/ChannelStore.swift Sources/App/AppEnvironment.swift Tests/ChannelStoreTests.swift
git commit -m "feat: rank channels by dwell time and refresh recency on edit"
```

---

## Task 8: Manual smoke verification

**Files:** none (manual run).

- [ ] **Step 1: Launch the app and confirm ranking behavior**

Run the app (via the `/run` skill or Xcode on iPhone 17 sim). Verify:
- Opening a channel and leaving it playing for a couple of minutes moves it up within its tag (heartbeat persists watch time).
- Pausing stops further movement.
- Editing a channel's title/tags surfaces it near the top of its tag (recency refresh) without otherwise changing its long-term standing.

- [ ] **Step 2: Confirm no regressions in existing flows**

Verify favorites, auto-surf, sleep timer, and resume-on-foreground still work (these share `PlaybackController`; the watch-segment changes must not disturb them).

---

## Task 9: Final regeneration + full green run

**Files:** none.

- [ ] **Step 1: Regenerate the project (picks up new source files)**

Run: `./generate.sh`
Expected: project regenerates without error. (Never run `xcodegen generate` directly — see CLAUDE.md.)

- [ ] **Step 2: Full test run**

Run: `xcodebuild test -scheme 20Four7 -destination 'platform=iOS Simulator,name=iPhone 17'`
Expected: ** TEST SUCCEEDED ** with all suites passing.

- [ ] **Step 3: Commit any regeneration diff**

```bash
git add -A
git commit -m "chore: regenerate project for dwell-boost ranking" || echo "nothing to regenerate"
```

---

## Self-Review

**Spec coverage:**
- "Dwell time should boost ranking (bounded/fair)" → Tasks 1 (`ChannelRanker` log term), 5 (watch tracking), 7 (store uses ranker). ✓
- "A 2-day session should top its tag" → `ChannelRanker` constants + `test_twoDayDwellBeatsManyTaps`. ✓
- "Boost on edit (recency only)" → Task 7 Step 5 + `test_editChannelRefreshesRecency`. ✓
- Latent bug (recency decays during long session) → fixed by heartbeat refreshing `lastPlayedDate` (Task 5) anchoring recency in `ChannelRanker`. ✓
- Persistence + crash-resilience of long sessions → 60 s heartbeat (Task 5) + `recordWatch` (Task 4). ✓

**Placeholder scan:** No TBD/TODO/"handle edge cases"; every code step shows full code. ✓

**Type consistency:**
- `ChannelRanker.score(playCount:watchSeconds:lastPlayedDate:dateAdded:now:)` — same signature in Task 1 def, Task 1 tests, and Task 7 caller. ✓
- `recordWatch(channelID:seconds:date:)` returns `(watchSeconds: Double, lastPlayedDate: Date)` — consistent in Tasks 4, 6. ✓
- `onWatchAccrued: (String, TimeInterval) -> Void` — consistent in Tasks 5 (def), 6 (wiring). ✓
- `bumpWatchSeconds(channelID:watchSeconds:lastPlayedDate:)` — Task 6 caller matches Task 7 def. ✓
- `watchSeconds` is `Double?` on `ChannelUserState` (Task 2) and `Double` on `Channel` (Task 3); merger coalesces `?? 0` (Task 3). ✓

**Cross-task ordering note:** Task 6 (`AppEnvironment`) references `bumpWatchSeconds` defined in Task 7; the plan commits them together (Task 7 Step 7). A worker doing strict file-by-file builds should implement Task 7 before building Task 6.
