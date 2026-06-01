# Guide Tag Sorting & Badges Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement popularity-based and density-based smart sorting for tag chips in the Channel Guide, along with modern counter badges on each chip.

**Architecture:** We introduce a `TagUsageRecord` SwiftData model to track how many times each tag is selected. The `ChannelStore` computes tag density counts in-memory dynamically, performs a three-tier hybrid sort (Visits DESC -> Content Count DESC -> Name ASC), and increments tap records asynchronously to prevent main-thread blockage.

**Tech Stack:** SwiftUI, SwiftData, XCTest

---

### Task 1: SwiftData Persistence Model

**Files:**
- Modify: `Sources/Persistence/PersistenceModels.swift`
- Modify: `Sources/Persistence/Persistence.swift`

- [ ] **Step 1: Define `TagUsageRecord` model**
  
  Open [PersistenceModels.swift](file:///Users/kevm/github/televista/Sources/Persistence/PersistenceModels.swift) and append the `TagUsageRecord` class definition to the end of the file:
  
  ```swift
  @Model
  final class TagUsageRecord {
      @Attribute(.unique) var tagID: String
      var tapCount: Int

      init(tagID: String, tapCount: Int = 0) {
          self.tagID = tagID
          self.tapCount = tapCount
      }
  }
  ```

- [ ] **Step 2: Add `TagUsageRecord` to schema registry**
  
  Open [Persistence.swift](file:///Users/kevm/github/televista/Sources/Persistence/Persistence.swift) and modify the `Schema` initialization list around line 6 to include `TagUsageRecord.self`:
  
  ```swift
  let schema = Schema([UserChannel.self, ChannelUserState.self, AppSettingsRecord.self, TagUsageRecord.self])
  ```

- [ ] **Step 3: Run the project test suite to verify schema compilation**
  
  Run:
  ```sh
  xcodebuild test -scheme 20Four7 -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing TwentyFourSevenTests/LocalStoreTests
  ```
  Expected: PASS

- [ ] **Step 4: Commit schema changes**
  
  Run:
  ```sh
  git add Sources/Persistence/PersistenceModels.swift Sources/Persistence/Persistence.swift
  git commit -m "feat: add TagUsageRecord database persistence model"
  ```

---

### Task 2: Tag Usage Persistence in `LocalStore`

**Files:**
- Modify: `Sources/Persistence/LocalStore.swift`
- Modify: `Tests/LocalStoreTests.swift`

- [ ] **Step 1: Write the failing unit test for tag usage persistence**
  
  Open [LocalStoreTests.swift](file:///Users/kevm/github/televista/Tests/LocalStoreTests.swift) and add the following test method inside the class:
  
  ```swift
  func test_tagUsageHistoryRoundTripsAndIncrements() throws {
      let store = try makeStore()
      
      // 1. Verify default is empty
      XCTAssertEqual(store.tagTapCounts(), [:])
      
      // 2. Increment and verify count is 1
      store.incrementTagTapCount(tagID: "lofi")
      XCTAssertEqual(store.tagTapCounts()["lofi"], 1)
      
      // 3. Increment again and verify count is 2
      store.incrementTagTapCount(tagID: "lofi")
      XCTAssertEqual(store.tagTapCounts()["lofi"], 2)
      
      // 4. Increment different tag
      store.incrementTagTapCount(tagID: "rain")
      XCTAssertEqual(store.tagTapCounts()["lofi"], 2)
      XCTAssertEqual(store.tagTapCounts()["rain"], 1)
  }
  ```

- [ ] **Step 2: Run test to verify it fails**
  
  Run:
  ```sh
  xcodebuild test -scheme 20Four7 -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing TwentyFourSevenTests/LocalStoreTests/test_tagUsageHistoryRoundTripsAndIncrements
  ```
  Expected: FAIL with compilation errors (methods `tagTapCounts` and `incrementTagTapCount` not found)

- [ ] **Step 3: Implement `LocalStore` methods**
  
  Open [LocalStore.swift](file:///Users/kevm/github/televista/Sources/Persistence/LocalStore.swift) and append these methods under the `// MARK: Settings (single row)` section (around line 173):
  
  ```swift
  // MARK: Tag Usage History
  func incrementTagTapCount(tagID: String) {
      let descriptor = FetchDescriptor<TagUsageRecord>(predicate: #Predicate { $0.tagID == tagID })
      if let record = (try? context.fetch(descriptor))?.first {
          record.tapCount += 1
      } else {
          context.insert(TagUsageRecord(tagID: tagID, tapCount: 1))
      }
      try? context.save()
  }

  func tagTapCounts() -> [String: Int] {
      let descriptor = FetchDescriptor<TagUsageRecord>()
      let records = (try? context.fetch(descriptor)) ?? []
      var dict: [String: Int] = [:]
      for r in records {
          dict[r.tagID] = r.tapCount
      }
      return dict
  }
  ```

- [ ] **Step 4: Run test to verify it passes**
  
  Run:
  ```sh
  xcodebuild test -scheme 20Four7 -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing TwentyFourSevenTests/LocalStoreTests/test_tagUsageHistoryRoundTripsAndIncrements
  ```
  Expected: PASS

- [ ] **Step 5: Commit persistence methods**
  
  Run:
  ```sh
  git add Sources/Persistence/LocalStore.swift Tests/LocalStoreTests.swift
  git commit -m "feat: implement tag usage methods in LocalStore and write unit tests"
  ```

---

### Task 3: Business Logic & Sorting in `ChannelStore`

**Files:**
- Modify: `Sources/Stores/ChannelStore.swift`
- Modify: `Tests/ChannelStoreTests.swift`

- [ ] **Step 1: Write the failing unit test for tag sorting**
  
  Open [ChannelStoreTests.swift](file:///Users/kevm/github/televista/Tests/ChannelStoreTests.swift) and add the following test method to the end of the class:
  
  ```swift
  func test_tagSortingByVisitsAndContentDensity() async throws {
      let localStore = try makeStore()
      let remoteConfig = makeRemoteConfig()
      
      // Setup channels with tags
      let userChannel1 = Channel(id: "u1", title: "C1", youTubeVideoID: "123", source: .user, isLiveExpected: true, tagIDs: ["lofi", "rain"])
      let userChannel2 = Channel(id: "u2", title: "C2", youTubeVideoID: "456", source: .user, isLiveExpected: true, tagIDs: ["lofi"])
      localStore.addUserChannel(userChannel1)
      localStore.addUserChannel(userChannel2)
      
      let store = ChannelStore(remoteConfig: remoteConfig, localStore: localStore)
      await store.refresh()
      
      // "lofi" has 2 channels, "rain" has 1 channel (from catalog + user)
      // Default sort (visits = 0): content count DESC -> "lofi" then "rain"
      XCTAssertEqual(store.chipTags.map(\.id), ["lofi", "rain"])
      
      // Tap "rain", visit count increments to 1
      store.toggleTag("rain")
      
      // Now "rain" (1 visit) should bubble before "lofi" (0 visits)
      XCTAssertEqual(store.chipTags.map(\.id), ["rain", "lofi"])
  }
  ```

- [ ] **Step 2: Run test to verify it fails**
  
  Run:
  ```sh
  xcodebuild test -scheme 20Four7 -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing TwentyFourSevenTests/ChannelStoreTests/test_tagSortingByVisitsAndContentDensity
  ```
  Expected: FAIL (taps not accounted for and counts dictionary not exposed)

- [ ] **Step 3: Update `ChannelStore` code**
  
  Open [ChannelStore.swift](file:///Users/kevm/github/televista/Sources/Stores/ChannelStore.swift) and make the following changes:
  
  * Add the properties at the top of the class:
    ```swift
    @Published private(set) var tagTapCounts: [String: Int] = [:]
    @Published private(set) var tagChannelCounts: [String: Int] = [:]
    ```
  * In `setupInitialLineup()`, load `tagTapCounts` on launch:
    ```swift
    private func setupInitialLineup() {
        self.offlineChannelIDs = []
        self.tagTapCounts = localStore.tagTapCounts()
        reloadLineup()
    }
    ```
  * In `reloadLineup()`, compute channel density counts and apply the smart sorting comparator:
    Replace lines 66–67:
    ```swift
            let allTags = editorial + userTags
            self.chipTags = allTags.sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
    ```
    With:
    ```swift
            var counts: [String: Int] = [:]
            for channel in channels {
                for tagID in channel.tagIDs {
                    counts[tagID, default: 0] += 1
                }
            }
            self.tagChannelCounts = counts

            let allTags = editorial + userTags
            self.chipTags = allTags.sorted { a, b in
                let aTaps = tagTapCounts[a.id, default: 0]
                let bTaps = tagTapCounts[b.id, default: 0]
                if aTaps != bTaps {
                    return aTaps > bTaps
                }
                let aCount = tagChannelCounts[a.id, default: 0]
                let bCount = tagChannelCounts[b.id, default: 0]
                if aCount != bCount {
                    return aCount > bCount
                }
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
    ```
  * In `toggleTag(_ id: String)`, record and increment tap count in-memory, and persist it asynchronously using `Task`:
    Replace the `toggleTag` method (around line 90):
    ```swift
        func toggleTag(_ id: String) {
            if selectedTagIDs.contains(id) { selectedTagIDs.remove(id) } else { selectedTagIDs.insert(id) }
        }
    ```
    With:
    ```swift
        func toggleTag(_ id: String) {
            if selectedTagIDs.contains(id) {
                selectedTagIDs.remove(id)
            } else {
                selectedTagIDs.insert(id)
                tagTapCounts[id, default: 0] += 1
                Task {
                    localStore.incrementTagTapCount(tagID: id)
                }
            }
            reloadLineup()
        }
    ```

- [ ] **Step 4: Run test to verify it passes**
  
  Run:
  ```sh
  xcodebuild test -scheme 20Four7 -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing TwentyFourSevenTests/ChannelStoreTests/test_tagSortingByVisitsAndContentDensity
  ```
  Expected: PASS

- [ ] **Step 5: Commit sorting changes**
  
  Run:
  ```sh
  git add Sources/Stores/ChannelStore.swift Tests/ChannelStoreTests.swift
  git commit -m "feat: implement dynamic hybrid tag sorting and async updates in ChannelStore"
  ```

---

### Task 4: UI & Display Counters in TagChipBar

**Files:**
- Modify: `Sources/UI/TagChipBar.swift`
- Modify: `Sources/UI/GuideView.swift`

- [ ] **Step 1: Modify `TagChipBar.swift` to render capsule count badges**
  
  Open [TagChipBar.swift](file:///Users/kevm/github/televista/Sources/UI/TagChipBar.swift) and replace its contents with:
  
  ```swift
  import SwiftUI

  struct TagChipBar: View {
      let tags: [Tag]
      let selected: Set<String>
      let counts: [String: Int]
      let onToggle: (String) -> Void

      var body: some View {
          ScrollView(.horizontal, showsIndicators: false) {
              HStack(spacing: 8) {
                  chip(title: "All", count: nil, isOn: selected.isEmpty) { onToggle("__all__") }
                  ForEach(tags) { tag in
                      chip(title: tag.name, count: counts[tag.id, default: 0], isOn: selected.contains(tag.id)) {
                          onToggle(tag.id)
                      }
                  }
              }
              .padding(.horizontal, 16)
          }
      }

      private func chip(title: String, count: Int?, isOn: Bool, action: @escaping () -> Void) -> some View {
          Button(action: action) {
              HStack(spacing: 6) {
                  Text(title)
                      .font(.subheadline.weight(isOn ? .bold : .regular))
                  
                  if let count = count {
                      Text("\(count)")
                          .font(.caption2.bold())
                          .padding(.horizontal, 5)
                          .padding(.vertical, 1.5)
                          .background(isOn ? Color.black.opacity(0.12) : Color.white.opacity(0.15))
                          .foregroundStyle(isOn ? Color.black.opacity(0.7) : Color.white.opacity(0.7))
                          .clipShape(Capsule())
                  }
              }
              .padding(.vertical, 6)
              .padding(.horizontal, 12)
              .background(isOn ? Color.white : Color.white.opacity(0.12))
              .foregroundStyle(isOn ? Color.black : Color.white)
              .clipShape(Capsule())
          }
          .buttonStyle(.plain)
      }
  }
  ```

- [ ] **Step 2: Update `GuideView.swift` to pass counts dictionary**
  
  Open [GuideView.swift](file:///Users/kevm/github/televista/Sources/UI/GuideView.swift) and locate the `TagChipBar` instantiation (around line 17):
  
  ```swift
                  TagChipBar(tags: store.chipTags, selected: store.selectedTagIDs) { id in
                      withAnimation {
                          if id == "__all__" { store.selectedTagIDs.removeAll() } else { store.toggleTag(id) }
                      }
                      store.startBackgroundScan()
                  }
  ```
  
  Change it to:
  
  ```swift
                  TagChipBar(tags: store.chipTags, selected: store.selectedTagIDs, counts: store.tagChannelCounts) { id in
                      withAnimation {
                          if id == "__all__" { store.selectedTagIDs.removeAll() } else { store.toggleTag(id) }
                      }
                      store.startBackgroundScan()
                  }
  ```

- [ ] **Step 3: Run full test suite to check build sanity**
  
  Run:
  ```sh
  xcodebuild test -scheme 20Four7 -destination 'platform=iOS Simulator,name=iPhone 17'
  ```
  Expected: PASS (All tests compile and succeed)

- [ ] **Step 4: Commit UI changes**
  
  Run:
  ```sh
  git add Sources/UI/TagChipBar.swift Sources/UI/GuideView.swift
  git commit -m "feat: render clean numeric count badges on Guide tag chips"
  ```
