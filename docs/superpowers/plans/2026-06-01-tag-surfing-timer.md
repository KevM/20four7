# Tag Surfing Timed Auto-Switching Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a timed auto-switching (Tag Surfing) feature that rotates through channels matching the active tag chip at a configurable interval.

**Architecture:** Extend `AppSettings` and `AppSettingsRecord` with an auto-surf interval setting. Update `PlaybackController` with an auto-surf countdown timer using the `Clock` protocol (allowing mockable tests) that automatically triggers `surf(.next)`. Update the UI views (`GuideView`, `SettingsView`, `PlayerView`, `PlayerOverlay`) to trigger and display this behavior.

**Tech Stack:** Swift, SwiftUI, SwiftData, Combine

---

### Task 1: Extend Persistence with Auto-Surf Settings

**Files:**
* Modify: [PersistenceModels.swift](file:///Users/kevm/github/televista/Sources/Persistence/PersistenceModels.swift)
* Modify: [LocalStore.swift](file:///Users/kevm/github/televista/Sources/Persistence/LocalStore.swift)
* Test: [LocalStoreTests.swift](file:///Users/kevm/github/televista/Tests/LocalStoreTests.swift)

- [ ] **Step 1: Write a test verifying defaultAutoSurfMinutes in AppSettings**
  
  Add to `Tests/LocalStoreTests.swift`:
  ```swift
  func test_settingsDefaultAutoSurfMinutes() throws {
      let container = try Persistence.makeContainer(inMemory: true)
      let store = LocalStore(context: container.mainContext)
      let settings = store.settings()
      XCTAssertEqual(settings.defaultAutoSurfMinutes, 5)
  }
  ```

- [ ] **Step 2: Run tests to verify the compile error / test failure**
  
  Run:
  ```sh
  xcodebuild test -scheme 20Four7 -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing TwentyFourSevenTests/LocalStoreTests/test_settingsDefaultAutoSurfMinutes
  ```
  Expected: Compile error due to missing `defaultAutoSurfMinutes` in `AppSettings`.

- [ ] **Step 3: Implement settings changes in persistence files**
  
  Modify [PersistenceModels.swift](file:///Users/kevm/github/televista/Sources/Persistence/PersistenceModels.swift#L62-L86) to add `defaultAutoSurfMinutes` to `AppSettingsRecord`:
  ```swift
  @Model
  final class AppSettingsRecord {
      // ... existing properties
      var defaultAutoSurfMinutes: Int?

      init(id: String = "default", autoResume: Bool = false,
           defaultSleepMinutes: Int = 30, showClockOverlay: Bool = false,
           dimLevelRaw: Int = 0, showOffline: Bool = false, scanOnCellular: Bool = false,
           lastWatchedChannelID: String? = nil, defaultAutoSurfMinutes: Int = 5) {
          // ... existing inits
          self.defaultAutoSurfMinutes = defaultAutoSurfMinutes
      }
  }
  ```

  Modify [LocalStore.swift](file:///Users/kevm/github/televista/Sources/Persistence/LocalStore.swift#L4-L12) to add `defaultAutoSurfMinutes` to `AppSettings` struct:
  ```swift
  struct AppSettings: Equatable {
      var autoResume: Bool
      var defaultSleepMinutes: Int
      var showClockOverlay: Bool
      var dimLevelRaw: Int
      var showOffline: Bool
      var scanOnCellular: Bool
      var defaultAutoSurfMinutes: Int
  }
  ```

  Modify [LocalStore.swift](file:///Users/kevm/github/televista/Sources/Persistence/LocalStore.swift#L152-L169) `settings()` and `saveSettings(_:)`:
  ```swift
      func settings() -> AppSettings {
          let r = settingsRecord()
          return AppSettings(autoResume: r.autoResume,
                             defaultSleepMinutes: r.defaultSleepMinutes,
                             showClockOverlay: r.showClockOverlay, dimLevelRaw: r.dimLevelRaw,
                             showOffline: r.showOffline, scanOnCellular: r.scanOnCellular,
                             defaultAutoSurfMinutes: r.defaultAutoSurfMinutes ?? 5)
      }

      func saveSettings(_ s: AppSettings) {
          let r = settingsRecord()
          r.autoResume = s.autoResume
          r.defaultSleepMinutes = s.defaultSleepMinutes
          r.showClockOverlay = s.showClockOverlay
          r.dimLevelRaw = s.dimLevelRaw
          r.showOffline = s.showOffline
          r.scanOnCellular = s.scanOnCellular
          r.defaultAutoSurfMinutes = s.defaultAutoSurfMinutes
          try? context.save()
      }
  ```

- [ ] **Step 4: Run the test to verify it passes**
  
  Run:
  ```sh
  xcodebuild test -scheme 20Four7 -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing TwentyFourSevenTests/LocalStoreTests/test_settingsDefaultAutoSurfMinutes
  ```
  Expected: PASS

- [ ] **Step 5: Commit changes**
  
  Run:
  ```sh
  git add Sources/Persistence/PersistenceModels.swift Sources/Persistence/LocalStore.swift Tests/LocalStoreTests.swift
  git commit -m "feat: add defaultAutoSurfMinutes setting to persistence layer"
  ```

---

### Task 2: Implement Auto-Surf Timer Logic in PlaybackController

**Files:**
* Modify: [PlaybackController.swift](file:///Users/kevm/github/televista/Sources/Playback/PlaybackController.swift)
* Test: [PlaybackControllerTests.swift](file:///Users/kevm/github/televista/Tests/PlaybackControllerTests.swift)

- [ ] **Step 1: Write unit tests verifying Auto-Surf countdown, pause/resume, and surf resets**
  
  Add to `Tests/PlaybackControllerTests.swift`:
  ```swift
  func test_autoSurfTimerTriggersSurf() {
      let player = MockPlayerService()
      let clock = ManualClock()
      let c = PlaybackController(player: player, clock: clock)
      let channels = makeChannels()
      c.setLineup(channels)
      c.play(channelID: "a")
      
      c.startAutoSurf(interval: 10)
      XCTAssertTrue(c.isAutoSurfActive)
      XCTAssertEqual(c.autoSurfTimeRemaining, 10)
      
      clock.advance(by: 5)
      XCTAssertEqual(c.autoSurfTimeRemaining, 5)
      XCTAssertEqual(c.currentChannel?.id, "a")
      
      clock.advance(by: 5)
      XCTAssertEqual(c.currentChannel?.id, "b")
      XCTAssertEqual(c.autoSurfTimeRemaining, 10) // resets to interval
  }

  func test_autoSurfTimerPausesOnPlayerPause() {
      let player = MockPlayerService()
      let clock = ManualClock()
      let c = PlaybackController(player: player, clock: clock)
      c.setLineup(makeChannels())
      c.play(channelID: "a")
      
      c.startAutoSurf(interval: 10)
      clock.advance(by: 3)
      XCTAssertEqual(c.autoSurfTimeRemaining, 7)
      
      c.pauseFromUI()
      clock.advance(by: 5)
      XCTAssertEqual(c.autoSurfTimeRemaining, 7) // paused, doesn't decrement
      
      c.playFromUI()
      clock.advance(by: 2)
      XCTAssertEqual(c.autoSurfTimeRemaining, 5) // resumed, decrements again
  }

  func test_autoSurfTimerResetsOnManualSurf() {
      let player = MockPlayerService()
      let clock = ManualClock()
      let c = PlaybackController(player: player, clock: clock)
      c.setLineup(makeChannels())
      c.play(channelID: "a")
      
      c.startAutoSurf(interval: 10)
      clock.advance(by: 4)
      XCTAssertEqual(c.autoSurfTimeRemaining, 6)
      
      c.surf(.next)
      XCTAssertEqual(c.autoSurfTimeRemaining, 10) // manual surf resets timer
  }
  ```

- [ ] **Step 2: Run tests to verify they fail**
  
  Run:
  ```sh
  xcodebuild test -scheme 20Four7 -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing TwentyFourSevenTests/PlaybackControllerTests
  ```
  Expected: Compile errors due to missing methods and published properties in `PlaybackController`.

- [ ] **Step 3: Implement Auto-Surf properties and methods in PlaybackController**
  
  Add to `PlaybackController.swift`:
  ```swift
      @Published private(set) var isAutoSurfActive = false
      @Published private(set) var autoSurfTimeRemaining: TimeInterval? = nil
      
      private var autoSurfInterval: TimeInterval = 300
      private var autoSurfToken: ClockToken?
  ```

  Implement the methods in `PlaybackController.swift`:
  ```swift
      func startAutoSurf(interval: TimeInterval) {
          stopAutoSurf()
          isAutoSurfActive = true
          autoSurfInterval = interval
          autoSurfTimeRemaining = interval
          scheduleAutoSurfTick()
      }

      func stopAutoSurf() {
          autoSurfToken?.cancel()
          autoSurfToken = nil
          isAutoSurfActive = false
          autoSurfTimeRemaining = nil
      }

      private func scheduleAutoSurfTick() {
          autoSurfToken?.cancel()
          autoSurfToken = clock.schedule(after: 1) { [weak self] in
              self?.handleAutoSurfTick()
          }
      }

      private func handleAutoSurfTick() {
          guard isAutoSurfActive, let remaining = autoSurfTimeRemaining else { return }
          let nextRemaining = remaining - 1
          if nextRemaining <= 0 {
              surf(.next)
              // Note: surf(.next) resets the timer back to the full interval via our modified surf method
          } else {
              autoSurfTimeRemaining = nextRemaining
              scheduleAutoSurfTick()
          }
      }
  ```

  Modify `surf(_ direction: SurfDirection)`:
  ```swift
      func surf(_ direction: SurfDirection) {
          guard let current = currentChannel,
                let next = Surfer.channel(after: current.id, in: lineup, direction: direction) else { return }
          isManuallyPaused = false
          start(next)
          if isAutoSurfActive {
              autoSurfTimeRemaining = autoSurfInterval
              scheduleAutoSurfTick()
          }
      }
  ```

  Modify `play(channelID: String)`:
  ```swift
      func play(channelID: String) {
          guard let channel = lineup.first(where: { $0.id == channelID }) else { return }
          isManuallyPaused = false
          start(channel)
          if isAutoSurfActive {
              autoSurfTimeRemaining = autoSurfInterval
              scheduleAutoSurfTick()
          }
      }
  ```

  Modify `playFromUI()` and `pauseFromUI()`:
  ```swift
      func playFromUI() {
          isManuallyPaused = false
          player.play()
          if isAutoSurfActive {
              scheduleAutoSurfTick()
          }
      }

      func pauseFromUI() {
          isManuallyPaused = true
          player.pause()
          autoSurfToken?.cancel()
          autoSurfToken = nil
      }
  ```

  Modify `start(_ channel: Channel)` to make sure we clean up auto surf timer if we start playback normally without auto-surf active:
  ```swift
      private func start(_ channel: Channel) {
          channelStore?.stopBackgroundScan()
          currentChannel = channel
          showsOfflineState = channelStore?.offlineChannelIDs.contains(channel.id) ?? false
          isCurrentlyLive = channel.isLiveExpected
          player.load(channel: channel)
          player.play()
          onChannelChanged?(channel)
      }
  ```

- [ ] **Step 4: Run the test to verify it passes**
  
  Run:
  ```sh
  xcodebuild test -scheme 20Four7 -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing TwentyFourSevenTests/PlaybackControllerTests
  ```
  Expected: PASS

- [ ] **Step 5: Commit changes**
  
  Run:
  ```sh
  git add Sources/Playback/PlaybackController.swift Tests/PlaybackControllerTests.swift
  git commit -m "feat: implement timed auto-switching logic in PlaybackController"
  ```

---

### Task 3: Add Auto-Surf Trigger and Layout to GuideView

**Files:**
* Modify: [GuideView.swift](file:///Users/kevm/github/televista/Sources/UI/GuideView.swift)
* Modify: [RootView.swift](file:///Users/kevm/github/televista/Sources/UI/RootView.swift)

- [ ] **Step 1: Implement the Action Banner layout in GuideView**
  
  Update [GuideView.swift](file:///Users/kevm/github/televista/Sources/UI/GuideView.swift#L13-L20) to display the Auto-Surf banner above the channel grid:
  ```swift
      // Add a property closure to handle auto-surf trigger:
      let onAutoSurf: () -> Void
  ```

  Insert the banner in `body` of `GuideView.swift` between the `TagChipBar` and the `LazyVGrid`:
  ```swift
                  TagChipBar(tags: store.chipTags, selected: store.selectedTagIDs) { id in
                      if id == "__all__" { store.selectedTagIDs.removeAll() } else { store.toggleTag(id) }
                      store.startBackgroundScan()
                  }
                  
                  if !store.selectedTagIDs.isEmpty && !store.filteredChannels.isEmpty {
                      let tagNames = store.selectedTagIDs.compactMap { store.tagsByID[$0]?.name }.sorted().joined(separator: ", ")
                      HStack(spacing: 12) {
                          VStack(alignment: .leading, spacing: 2) {
                              Text("\(tagNames) Active")
                                  .font(.subheadline.bold())
                                  .foregroundColor(.white)
                              Text("\(store.filteredChannels.count) Ambient channels")
                                  .font(.caption)
                                  .foregroundColor(.gray)
                          }
                          Spacer()
                          Button(action: onAutoSurf) {
                              HStack(spacing: 6) {
                                  Image(systemName: "play.circle.fill")
                                      .font(.body)
                                  Text("Auto-Surf")
                                      .font(.subheadline.bold())
                              }
                              .foregroundColor(.white)
                              .padding(.vertical, 8)
                              .padding(.horizontal, 16)
                              .background(Color.red)
                              .cornerRadius(8)
                          }
                          .buttonStyle(.plain)
                      }
                      .padding(.horizontal, 16)
                      .padding(.vertical, 10)
                      .background(Color.white.opacity(0.06))
                      .cornerRadius(12)
                      .padding(.horizontal, 12)
                      .transition(.opacity.combined(with: .move(edge: .top)))
                  }
  ```

- [ ] **Step 2: Update RootView to wire up the Guide auto-surf trigger**
  
  Modify [RootView.swift](file:///Users/kevm/github/televista/Sources/UI/RootView.swift#L18-L20):
  ```swift
              GuideView(store: store, onSelect: { channel in
                  startPlaying(channel)
              }, onAutoSurf: {
                  if let firstChannel = store.filteredChannels.first {
                      startAutoSurfing(firstChannel)
                  }
              })
  ```

  Add the helper method `startAutoSurfing(_:)` to `RootView`:
  ```swift
      @MainActor
      private func startAutoSurfing(_ channel: Channel) {
          env.controller.setLineup(store.filteredChannels)
          env.controller.startAutoSurf(interval: Double(env.localStore.settings().defaultAutoSurfMinutes) * 60)
          env.controller.play(channelID: channel.id)
          playing = channel
      }
  ```

  Ensure `stopAutoSurf()` is called in the `onClose` handler of `PlayerView` inside `RootView`:
  ```swift
          .fullScreenCover(item: $playing) { _ in
              PlayerView(
                  controller: env.controller, store: store, webView: env.player,
                  settings: env.localStore.settings(),
                  onClose: {
                      playing = nil
                      env.controller.stopAutoSurf()
                      store.startBackgroundScan()
                  }
              )
          }
  ```

- [ ] **Step 3: Run project tests to ensure existing functions are not broken**
  
  Run:
  ```sh
  xcodebuild test -scheme 20Four7 -destination 'platform=iOS Simulator,name=iPhone 17'
  ```
  Expected: PASS

- [ ] **Step 4: Commit changes**
  
  Run:
  ```sh
  git add Sources/UI/GuideView.swift Sources/UI/RootView.swift
  git commit -m "feat: integrate Auto-Surf action banner trigger in GuideView"
  ```

---

### Task 4: Add Auto-Surf Countdown Banner to PlayerView and SettingsView

**Files:**
* Modify: [SettingsView.swift](file:///Users/kevm/github/televista/Sources/UI/SettingsView.swift)
* Modify: [PlayerOverlay.swift](file:///Users/kevm/github/televista/Sources/UI/PlayerOverlay.swift)
* Modify: [PlayerView.swift](file:///Users/kevm/github/televista/Sources/UI/PlayerView.swift)

- [ ] **Step 1: Add Auto-Surf interval Stepper in SettingsView**
  
  Update [SettingsView.swift](file:///Users/kevm/github/televista/Sources/UI/SettingsView.swift#L16-L20) to add the Auto-Surf setting:
  ```swift
              Section("Playback") {
                  Toggle("Auto-resume last channel", isOn: $settings.autoResume)
                  Stepper("Default sleep timer: \(settings.defaultSleepMinutes) min",
                          value: $settings.defaultSleepMinutes, in: 5...120, step: 5)
                  Stepper("Auto-surf interval: \(settings.defaultAutoSurfMinutes) min",
                          value: $settings.defaultAutoSurfMinutes, in: 1...30, step: 1)
              }
  ```

- [ ] **Step 2: Add formatTime helper and countdown layout in PlayerOverlay**
  
  Modify [PlayerOverlay.swift](file:///Users/kevm/github/televista/Sources/UI/PlayerOverlay.swift) to show the countdown banner:
  
  Add to the top of `PlayerOverlay.swift` (inside the `body` or as an overlay):
  ```swift
      private func formatTime(_ time: TimeInterval) -> String {
          let mins = Int(time) / 60
          let secs = Int(time) % 60
          return String(format: "%02d:%02d", mins, secs)
      }
  ```

  Position the countdown banner at the top-right of the player interface (next to the close button or nested inside the Top Header HStack):
  ```swift
                  HStack {
                      VStack(alignment: .leading) {
                          if let c = controller.currentChannel {
                              if controller.isCurrentlyLive { Text("● LIVE").font(.caption.bold()).foregroundStyle(.red) }
                              HStack(alignment: .center, spacing: 10) {
                                  Text(c.title).font(.headline)
                                  Button(action: onClose) {
                                      Image(systemName: "chevron.down")
                                          .font(.system(size: 12, weight: .bold))
                                          .foregroundStyle(.white)
                                          .frame(width: 28, height: 28)
                                          .background(Color.black.opacity(0.35))
                                          .clipShape(Circle())
                                  }
                                  .buttonStyle(.plain)
                              }
                          }
                      }
                      Spacer()
                      
                      if controller.isAutoSurfActive, let remaining = controller.autoSurfTimeRemaining {
                          HStack(spacing: 6) {
                              Image(systemName: "timer")
                                  .font(.caption)
                              Text("Surfing in \(formatTime(remaining))")
                                  .font(.caption.bold())
                          }
                          .padding(.vertical, 6)
                          .padding(.horizontal, 10)
                          .background(Color.black.opacity(0.6))
                          .cornerRadius(12)
                          .overlay(
                              RoundedRectangle(cornerRadius: 12)
                                  .stroke(Color.white.opacity(0.15), lineWidth: 1)
                          )
                      }
                  }
                  .padding()
  ```

- [ ] **Step 3: Run the project tests to verify complete compilation and pass**
  
  Run:
  ```sh
  xcodebuild test -scheme 20Four7 -destination 'platform=iOS Simulator,name=iPhone 17'
  ```
  Expected: PASS

- [ ] **Step 4: Commit changes**
  
  Run:
  ```sh
  git add Sources/UI/SettingsView.swift Sources/UI/PlayerOverlay.swift
  git commit -m "feat: add Auto-Surf interval settings and countdown display to player"
  ```
