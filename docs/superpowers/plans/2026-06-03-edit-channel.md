# Edit an Existing Channel — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a unified per-channel Edit form (Title, Tags, Live/VOD, Favorite); editing a curated channel "adopts" it into a user copy.

**Architecture:** Editing always operates on a `UserChannel`. User channels are updated in place; curated channels are adopted (a `UserChannel` with the same video ID is written, and the merge's video-ID dedup hides the curated original). Persistence gains `updateUserChannel` / `adoptCuratedChannel`; the store gains `editChannel` and twin-hiding on `removeChannel`; the UI gains an `EditChannelView` plus a shared `TagSelectorSection` extracted from `AddChannelView`.

**Tech Stack:** Swift, SwiftUI, SwiftData, XCTest. Spec: [`docs/superpowers/specs/2026-06-03-edit-channel-design.md`](../specs/2026-06-03-edit-channel-design.md).

---

## Conventions

- **Run a single test:**
  ```sh
  xcodebuild test -scheme 20Four7 -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TwentyFourSevenTests/<Class>/<method>
  ```
- **Run the full suite:**
  ```sh
  xcodebuild test -scheme 20Four7 -destination 'platform=iOS Simulator,name=iPhone 17'
  ```
- **Build only:**
  ```sh
  xcodebuild build -scheme 20Four7 -destination 'platform=iOS Simulator,name=iPhone 17'
  ```
- After creating **new** source files, run `./generate.sh` (NOT `xcodegen` directly) so they're added to the Xcode project. Sources are globbed by directory.
- The test target is `TwentyFourSevenTests`; tests `@testable import TwentyFourSeven`.

## File Structure

- **Modify** [`Sources/Persistence/LocalStore.swift`](../../../Sources/Persistence/LocalStore.swift) — add `updateUserChannel`, `adoptCuratedChannel`; later remove `updateUserChannelTitle`.
- **Modify** [`Sources/Stores/ChannelStore.swift`](../../../Sources/Stores/ChannelStore.swift) — add `selectableTags(including:)`, `editChannel(...)`; extend `removeChannel`; later remove `renameChannel`.
- **Create** `Sources/UI/TagSelectorSection.swift` — shared tag-chips + add-custom-tag form sections.
- **Modify** [`Sources/UI/AddChannelView.swift`](../../../Sources/UI/AddChannelView.swift) — use `TagSelectorSection` + `store.selectableTags`.
- **Create** `Sources/UI/EditChannelView.swift` — the edit form.
- **Modify** [`Sources/UI/ChannelTile.swift`](../../../Sources/UI/ChannelTile.swift) — menu becomes Favorite · Edit… · Remove.
- **Modify** [`Sources/UI/GuideView.swift`](../../../Sources/UI/GuideView.swift) — present `EditChannelView` as a sheet.
- **Modify** [`Tests/LocalStoreTests.swift`](../../../Tests/LocalStoreTests.swift), [`Tests/ChannelStoreTests.swift`](../../../Tests/ChannelStoreTests.swift) — new tests; remove the obsolete rename test.

---

## Task 1: `LocalStore.updateUserChannel` (in-place update)

**Files:**
- Modify: `Sources/Persistence/LocalStore.swift`
- Test: `Tests/LocalStoreTests.swift`

- [ ] **Step 1: Write the failing test**

Add to `Tests/LocalStoreTests.swift` (inside the class):

```swift
func test_updateUserChannelInPlace() throws {
    let store = try makeStore()
    let channel = Channel(id: "u1", title: "Old", youTubeVideoID: "abcdefghijk",
                          source: .user, isLiveExpected: true,
                          dateAdded: Date(timeIntervalSince1970: 1000), tagIDs: ["old"])
    store.addUserChannel(channel)

    store.updateUserChannel(id: "u1", title: "New", youTubeVideoID: "abcdefghijk",
                            isLiveExpected: false, tagIDs: ["new", "cozy"])

    let fetched = store.userChannels()
    XCTAssertEqual(fetched.count, 1)
    XCTAssertEqual(fetched.first?.title, "New")
    XCTAssertEqual(fetched.first?.isLiveExpected, false)
    XCTAssertEqual(fetched.first?.tagIDs, ["new", "cozy"])
    // dateAdded is preserved (ranking stays stable).
    XCTAssertEqual(fetched.first?.dateAdded, Date(timeIntervalSince1970: 1000))
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme 20Four7 -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TwentyFourSevenTests/LocalStoreTests/test_updateUserChannelInPlace`
Expected: FAIL — compile error, `updateUserChannel` not found.

- [ ] **Step 3: Add the method**

In `Sources/Persistence/LocalStore.swift`, add right after `updateUserChannelTitle`:

```swift
/// Updates all mutable fields of a user channel in place, preserving `dateAdded`
/// so popularity/recency ranking is unaffected by an edit.
func updateUserChannel(id: String, title: String, youTubeVideoID: String,
                       isLiveExpected: Bool, tagIDs: [String]) {
    let descriptor = FetchDescriptor<UserChannel>(predicate: #Predicate { $0.id == id })
    if let record = (try? context.fetch(descriptor))?.first {
        record.title = title
        record.youTubeVideoID = youTubeVideoID
        record.isLiveExpected = isLiveExpected
        record.tagIDs = tagIDs
        try? context.save()
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme 20Four7 -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TwentyFourSevenTests/LocalStoreTests/test_updateUserChannelInPlace`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/Persistence/LocalStore.swift Tests/LocalStoreTests.swift
git commit -m "feat: add LocalStore.updateUserChannel for in-place edits"
```

---

## Task 2: `LocalStore.adoptCuratedChannel` (curated → user copy + state migration)

**Files:**
- Modify: `Sources/Persistence/LocalStore.swift`
- Test: `Tests/LocalStoreTests.swift`

- [ ] **Step 1: Write the failing test**

Add to `Tests/LocalStoreTests.swift`:

```swift
func test_adoptCuratedChannelMigratesState() throws {
    let store = try makeStore()

    // Existing per-channel state under the curated id "c1".
    store.setFavorite(channelID: "c1", isFavorite: true)
    _ = store.incrementPlayCount(channelID: "c1") // playCount 1, sets lastPlayedDate

    let edited = Channel(id: "user-abcdefghijk", title: "My Rain",
                         youTubeVideoID: "abcdefghijk", source: .user,
                         isLiveExpected: false, dateAdded: Date(timeIntervalSince1970: 0),
                         tagIDs: ["rain", "cozy"])
    store.adoptCuratedChannel(edited, fromCuratedID: "c1")

    // New user channel exists with edited fields.
    let channels = store.userChannels()
    XCTAssertEqual(channels.map(\.id), ["user-abcdefghijk"])
    XCTAssertEqual(channels.first?.title, "My Rain")
    XCTAssertEqual(channels.first?.tagIDs, ["rain", "cozy"])

    // Play history + favorite migrated to the new id.
    let states = store.allUserStates()
    let newState = states.first { $0.channelID == "user-abcdefghijk" }
    XCTAssertEqual(newState?.playCount, 1)
    XCTAssertNotNil(newState?.lastPlayedDate)
    XCTAssertEqual(newState?.isFavorite, true)

    // Old curated state row is deleted.
    XCTAssertNil(states.first { $0.channelID == "c1" })
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme 20Four7 -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TwentyFourSevenTests/LocalStoreTests/test_adoptCuratedChannelMigratesState`
Expected: FAIL — `adoptCuratedChannel` not found.

- [ ] **Step 3: Add the method**

In `Sources/Persistence/LocalStore.swift`, add after `updateUserChannel`:

```swift
/// Adopts a curated channel into a user copy: inserts the edited `UserChannel`,
/// migrates play history + favorite from the old curated state id to the new id,
/// and deletes the orphaned curated state row. Upserts the new-id state row so
/// re-adopting a previously removed video does not violate the unique constraint.
func adoptCuratedChannel(_ edited: Channel, fromCuratedID: String) {
    addUserChannel(edited)

    let old = userState(for: fromCuratedID)
    if let target = userState(for: edited.id) {
        target.playCount = old?.playCount ?? 0
        target.lastPlayedDate = old?.lastPlayedDate
        target.isFavorite = old?.isFavorite ?? false
    } else {
        let target = ChannelUserState(channelID: edited.id)
        target.playCount = old?.playCount ?? 0
        target.lastPlayedDate = old?.lastPlayedDate
        target.isFavorite = old?.isFavorite ?? false
        context.insert(target)
    }

    if let old, old.channelID != edited.id { context.delete(old) }
    try? context.save()
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme 20Four7 -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TwentyFourSevenTests/LocalStoreTests/test_adoptCuratedChannelMigratesState`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/Persistence/LocalStore.swift Tests/LocalStoreTests.swift
git commit -m "feat: add LocalStore.adoptCuratedChannel with state migration"
```

---

## Task 3: `ChannelStore.selectableTags(including:)` (shared available-tags computation)

This DRYs the available-tags logic currently inline in `AddChannelView.allAvailableTags` so both the add and edit forms use one source of truth.

**Files:**
- Modify: `Sources/Stores/ChannelStore.swift`
- Test: `Tests/ChannelStoreTests.swift`

- [ ] **Step 1: Write the failing test**

Add to `Tests/ChannelStoreTests.swift`:

```swift
func test_selectableTagsIncludesEditorialAndSelected() async throws {
    let localStore = try makeStore()
    let store = ChannelStore(remoteConfig: makeRemoteConfig(), localStore: localStore)
    await store.refresh()

    let tags = store.selectableTags(including: ["MyCustomTag"])
    let ids = tags.map(\.id)
    XCTAssertTrue(ids.contains("rain"))         // editorial, from catalog
    XCTAssertTrue(ids.contains("MyCustomTag"))  // a not-yet-existing selected id
    // Sorted by (sortOrder, name): editorial "rain" (1) before custom (100).
    XCTAssertLessThan(ids.firstIndex(of: "rain")!, ids.firstIndex(of: "MyCustomTag")!)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme 20Four7 -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TwentyFourSevenTests/ChannelStoreTests/test_selectableTagsIncludesEditorialAndSelected`
Expected: FAIL — `selectableTags` not found.

- [ ] **Step 3: Add the method**

In `Sources/Stores/ChannelStore.swift`, add after `resolveTags`:

```swift
/// Tags offered in the add/edit forms: editorial tags, plus any currently
/// selected ids not already present (materialized as `.user` tags), plus existing
/// user chip tags. Sorted by (sortOrder, name). Excludes the derived favs tag.
func selectableTags(including selectedTagIDs: Set<String>) -> [Tag] {
    var tags = editorialTags
    for tagID in selectedTagIDs where tagID != Tag.favsID {
        if !tags.contains(where: { $0.id == tagID }) {
            tags.append(Tag(id: tagID, name: tagID, symbol: nil, kind: .user, sortOrder: 100))
        }
    }
    for tag in chipTags where tag.kind == .user {
        if !tags.contains(where: { $0.id == tag.id }) {
            tags.append(tag)
        }
    }
    return tags.sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme 20Four7 -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TwentyFourSevenTests/ChannelStoreTests/test_selectableTagsIncludesEditorialAndSelected`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/Stores/ChannelStore.swift Tests/ChannelStoreTests.swift
git commit -m "feat: add ChannelStore.selectableTags for shared tag pickers"
```

---

## Task 4: `ChannelStore.editChannel` (branch on source: update vs adopt)

**Files:**
- Modify: `Sources/Stores/ChannelStore.swift`
- Test: `Tests/ChannelStoreTests.swift`

- [ ] **Step 1: Write the failing tests**

Add to `Tests/ChannelStoreTests.swift`:

```swift
func test_editUserChannelUpdatesInPlace() async throws {
    let localStore = try makeStore()
    localStore.addUserChannel(Channel(id: "user-vid", title: "Old",
        youTubeVideoID: "vid12345678", source: .user, isLiveExpected: true, tagIDs: ["old"]))
    let store = ChannelStore(remoteConfig: makeRemoteConfig(), localStore: localStore)
    await store.refresh()

    let userChan = try XCTUnwrap(store.channels.first { $0.id == "user-vid" })
    store.editChannel(userChan, title: "New", tagIDs: ["zen"],
                      isLiveExpected: false, isFavorite: true)

    let updated = try XCTUnwrap(store.channels.first { $0.id == "user-vid" })
    XCTAssertEqual(updated.title, "New")
    XCTAssertEqual(updated.isLiveExpected, false)
    XCTAssertTrue(updated.tagIDs.contains("zen"))
    XCTAssertTrue(store.isFavorite(updated))
}

func test_editCuratedChannelAdoptsIt() async throws {
    let localStore = try makeStore()
    let store = ChannelStore(remoteConfig: makeRemoteConfig(), localStore: localStore)
    await store.refresh()

    // Curated channel c1 (video "abcdefghijk") with prior play history.
    _ = localStore.incrementPlayCount(channelID: "c1")
    await store.refresh()
    let curated = try XCTUnwrap(store.channels.first { $0.id == "c1" })

    store.editChannel(curated, title: "My Rain", tagIDs: ["rain", "cozy"],
                      isLiveExpected: false, isFavorite: true)

    // Curated original is gone; only the adopted user copy remains.
    XCTAssertNil(store.channels.first { $0.id == "c1" })
    let adopted = try XCTUnwrap(store.channels.first { $0.id == "user-abcdefghijk" })
    XCTAssertEqual(adopted.source, .user)
    XCTAssertEqual(adopted.title, "My Rain")
    XCTAssertTrue(adopted.tagIDs.contains("cozy"))
    XCTAssertEqual(adopted.isLiveExpected, false)
    XCTAssertTrue(store.isFavorite(adopted))
    XCTAssertEqual(adopted.playCount, 1) // history carried over

    // Old curated state row is cleaned up.
    XCTAssertNil(localStore.allUserStates().first { $0.channelID == "c1" })
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme 20Four7 -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TwentyFourSevenTests/ChannelStoreTests/test_editCuratedChannelAdoptsIt`
Expected: FAIL — `editChannel` not found.

- [ ] **Step 3: Add the method**

In `Sources/Stores/ChannelStore.swift`, add after `renameChannel`:

```swift
/// Unified channel edit. User channels are updated in place; curated channels are
/// adopted into a user copy (the merge's video-id dedup hides the curated original).
/// Favorite is applied to whichever id is now authoritative.
func editChannel(_ original: Channel, title: String, tagIDs: [String],
                 isLiveExpected: Bool, isFavorite: Bool) {
    let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
    let finalTitle = trimmed.isEmpty ? "Untitled" : trimmed
    let cleanTags = tagIDs.filter { $0 != Tag.favsID }

    switch original.source {
    case .user:
        localStore.updateUserChannel(id: original.id, title: finalTitle,
                                     youTubeVideoID: original.youTubeVideoID,
                                     isLiveExpected: isLiveExpected, tagIDs: cleanTags)
        localStore.setFavorite(channelID: original.id, isFavorite: isFavorite)
    case .curated:
        let adopted = Channel(
            id: "user-\(original.youTubeVideoID)", title: finalTitle,
            youTubeVideoID: original.youTubeVideoID, thumbnailURL: original.thumbnailURL,
            source: .user, isLiveExpected: isLiveExpected,
            dateAdded: original.dateAdded, tagIDs: cleanTags)
        localStore.adoptCuratedChannel(adopted, fromCuratedID: original.id)
        localStore.setFavorite(channelID: adopted.id, isFavorite: isFavorite)
    }
    reloadLineup()
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme 20Four7 -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TwentyFourSevenTests/ChannelStoreTests/test_editUserChannelUpdatesInPlace -only-testing:TwentyFourSevenTests/ChannelStoreTests/test_editCuratedChannelAdoptsIt`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/Stores/ChannelStore.swift Tests/ChannelStoreTests.swift
git commit -m "feat: add ChannelStore.editChannel with curated adoption"
```

---

## Task 5: `removeChannel` hides the curated twin

After deleting a user channel, hide any curated channel that shares its video id, so an adopted-then-removed channel cannot silently reappear from the catalog.

**Files:**
- Modify: `Sources/Stores/ChannelStore.swift:225-238` (`removeChannel`)
- Test: `Tests/ChannelStoreTests.swift`

- [ ] **Step 1: Write the failing test**

Add to `Tests/ChannelStoreTests.swift`:

```swift
func test_removingAdoptedChannelDoesNotRevealCuratedTwin() async throws {
    let localStore = try makeStore()
    let store = ChannelStore(remoteConfig: makeRemoteConfig(), localStore: localStore)
    await store.refresh()

    // Adopt curated c1 (video "abcdefghijk") into a user copy.
    let curated = try XCTUnwrap(store.channels.first { $0.id == "c1" })
    store.editChannel(curated, title: "Mine", tagIDs: ["rain"],
                      isLiveExpected: true, isFavorite: false)
    let adopted = try XCTUnwrap(store.channels.first { $0.id == "user-abcdefghijk" })

    // Remove the adopted copy.
    store.removeChannel(adopted)

    // Neither the user copy nor the curated twin should appear.
    XCTAssertNil(store.channels.first { $0.id == "user-abcdefghijk" })
    XCTAssertNil(store.channels.first { $0.id == "c1" })
    XCTAssertEqual(store.filteredChannels.count, 0)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme 20Four7 -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TwentyFourSevenTests/ChannelStoreTests/test_removingAdoptedChannelDoesNotRevealCuratedTwin`
Expected: FAIL — curated `c1` reappears, `filteredChannels.count` is 1.

- [ ] **Step 3: Update `removeChannel`**

Replace the existing `removeChannel` in `Sources/Stores/ChannelStore.swift` with:

```swift
func removeChannel(_ channel: Channel) {
    if channel.source == .user {
        localStore.removeUserChannel(id: channel.id)
        // Hide a curated twin sharing this video id, so an adopted-then-removed
        // channel does not silently reappear from the catalog.
        let catalog = remoteConfig.cachedOrBundledCatalog()
        if let twin = catalog.asChannels().first(where: { $0.youTubeVideoID == channel.youTubeVideoID }) {
            localStore.setHidden(channelID: twin.id, isHidden: true)
        }
    } else {
        localStore.setHidden(channelID: channel.id, isHidden: true)
    }

    if favoriteIDs.contains(channel.id) {
        localStore.setFavorite(channelID: channel.id, isFavorite: false)
        favoriteIDs.remove(channel.id)
    }

    reloadLineup()
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme 20Four7 -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TwentyFourSevenTests/ChannelStoreTests/test_removingAdoptedChannelDoesNotRevealCuratedTwin`
Expected: PASS

- [ ] **Step 5: Run the existing remove/restore test to confirm no regression**

Run: `xcodebuild test -scheme 20Four7 -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TwentyFourSevenTests/ChannelStoreTests/test_store_hides_and_restores_channels`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add Sources/Stores/ChannelStore.swift Tests/ChannelStoreTests.swift
git commit -m "feat: hide curated twin when removing an adopted channel"
```

---

## Task 6: Extract `TagSelectorSection` and refactor `AddChannelView`

Pure refactor — the add flow's behavior must not change.

**Files:**
- Create: `Sources/UI/TagSelectorSection.swift`
- Modify: `Sources/UI/AddChannelView.swift`

- [ ] **Step 1: Create the shared view**

Create `Sources/UI/TagSelectorSection.swift`:

```swift
import SwiftUI

/// Shared "Tags" + "Add Custom Tag" form sections used by the add and edit
/// channel forms. Selection is driven through `selectedTagIDs`; creating a custom
/// tag inserts its trimmed name into the selection.
struct TagSelectorSection: View {
    let availableTags: [Tag]
    @Binding var selectedTagIDs: Set<String>

    @State private var newTagName = ""

    var body: some View {
        Group {
            Section("Tags") {
                FlowLayout(spacing: 8) {
                    ForEach(availableTags) { tag in
                        let isSelected = selectedTagIDs.contains(tag.id)
                        Button {
                            withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                                if isSelected { selectedTagIDs.remove(tag.id) }
                                else { selectedTagIDs.insert(tag.id) }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                if isSelected {
                                    Image(systemName: "checkmark")
                                        .font(.caption2)
                                }
                                Text(tag.name)
                                    .font(.caption)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(isSelected ? Color.blue : Color(.systemGray6))
                            .foregroundColor(isSelected ? .white : .primary)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }
            Section("Add Custom Tag") {
                HStack {
                    TextField("New tag name (e.g. Nature)", text: $newTagName)
                        .autocorrectionDisabled()
                    Button("Create") {
                        let trimmed = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            selectedTagIDs.insert(trimmed)
                            newTagName = ""
                        }
                    }
                    .disabled(newTagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
```

- [ ] **Step 2: Refactor `AddChannelView` to use it**

In `Sources/UI/AddChannelView.swift`:

1. Delete the `@State private var newTagName = ""` line.
2. Delete the entire `allAvailableTags` computed property (lines ~51–64).
3. Replace the two sections — the `Section("Tags") { ... }` block and the `Section("Add Custom Tag") { ... }` block (lines ~102–144) — with this single line:

```swift
            TagSelectorSection(
                availableTags: store.selectableTags(including: selectedTagIDs),
                selectedTagIDs: $selectedTagIDs
            )
```

Leave everything else (URL section, Title section, validation, save, watch alert) unchanged.

- [ ] **Step 3: Regenerate the project and build**

Run: `./generate.sh`
Then: `xcodebuild build -scheme 20Four7 -destination 'platform=iOS Simulator,name=iPhone 17'`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Run the full suite to confirm no regression**

Run: `xcodebuild test -scheme 20Four7 -destination 'platform=iOS Simulator,name=iPhone 17'`
Expected: all tests PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/UI/TagSelectorSection.swift Sources/UI/AddChannelView.swift project.yml *.xcodeproj
git commit -m "refactor: extract shared TagSelectorSection from AddChannelView"
```

---

## Task 7: Create `EditChannelView`

**Files:**
- Create: `Sources/UI/EditChannelView.swift`

- [ ] **Step 1: Create the view**

Create `Sources/UI/EditChannelView.swift`:

```swift
import SwiftUI

/// Unified edit form for an existing channel. Title, tags, live/VOD, and favorite
/// are editable; the YouTube link is fixed (it defines identity). Saving a curated
/// channel adopts it into a user copy via `ChannelStore.editChannel`.
struct EditChannelView: View {
    @ObservedObject var store: ChannelStore
    let channel: Channel
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var selectedTagIDs: Set<String>
    @State private var isLiveExpected: Bool
    @State private var isFavorite: Bool

    /// `initialTagIDs` and `initialIsFavorite` are computed by the presenter
    /// (which is already on the main actor) so this initializer stays pure.
    init(
        store: ChannelStore,
        channel: Channel,
        initialTagIDs: Set<String>,
        initialIsFavorite: Bool,
        onSaved: @escaping () -> Void
    ) {
        self.store = store
        self.channel = channel
        self.onSaved = onSaved
        self._title = State(initialValue: channel.title)
        self._selectedTagIDs = State(initialValue: initialTagIDs)
        self._isLiveExpected = State(initialValue: channel.isLiveExpected)
        self._isFavorite = State(initialValue: initialIsFavorite)
    }

    var body: some View {
        Form {
            Section("YouTube link") {
                Text("youtu.be/\(channel.youTubeVideoID)")
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Section("Title") {
                TextField("Channel name", text: $title)
            }
            TagSelectorSection(
                availableTags: store.selectableTags(including: selectedTagIDs),
                selectedTagIDs: $selectedTagIDs
            )
            Section("Status") {
                Toggle("Live", isOn: $isLiveExpected)
                Toggle("Favorite", isOn: $isFavorite)
            }
        }
        .navigationTitle("Edit Channel")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    store.editChannel(channel, title: title,
                                      tagIDs: Array(selectedTagIDs),
                                      isLiveExpected: isLiveExpected,
                                      isFavorite: isFavorite)
                    onSaved()
                    dismiss()
                }
            }
        }
    }
}
```

- [ ] **Step 2: Regenerate the project and build**

Run: `./generate.sh`
Then: `xcodebuild build -scheme 20Four7 -destination 'platform=iOS Simulator,name=iPhone 17'`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add Sources/UI/EditChannelView.swift project.yml *.xcodeproj
git commit -m "feat: add EditChannelView edit form"
```

---

## Task 8: Wire `ChannelTile` menu and `GuideView` sheet

**Files:**
- Modify: `Sources/UI/ChannelTile.swift`
- Modify: `Sources/UI/GuideView.swift`

- [ ] **Step 1: Update `ChannelTile` to expose Edit instead of Rename/Live**

In `Sources/UI/ChannelTile.swift`:

1. Replace the two closure properties:

```swift
    var onRename: (() -> Void)? = nil
    var onToggleLive: (() -> Void)? = nil
```

with:

```swift
    var onEdit: (() -> Void)? = nil
```

2. Replace the `if let onRename { ... }` and `if let onToggleLive { ... }` blocks in `.contextMenu` with a single Edit button (keep the Favorite block above it and the Remove block below it unchanged):

```swift
            if let onEdit {
                Button {
                    onEdit()
                } label: {
                    Label("Edit…", systemImage: "pencil")
                }
            }
```

- [ ] **Step 2: Update `GuideView` to present the edit sheet**

In `Sources/UI/GuideView.swift`:

1. Replace the rename-alert state declarations:

```swift
    @State private var renameText = ""
    @State private var channelToRename: Channel? = nil
    @State private var showingRenameAlert = false
```

with:

```swift
    @State private var channelToEdit: Channel? = nil
```

2. In the `ChannelTile(...)` call, replace the `onRename` / `onToggleLive` / `onRemove` arguments with:

```swift
                            onEdit: {
                                channelToEdit = channel
                            },
                            onRemove: { store.removeChannel(channel) }
```

(Keep `channel`, `isFavorite`, `isOffline`, `onTap`, and `onToggleFavorite` arguments as they are.)

3. Replace the `.alert("Rename Channel", ...) { ... }` modifier (lines ~89–99) with a sheet:

```swift
        .sheet(item: $channelToEdit) { channel in
            NavigationStack {
                EditChannelView(
                    store: store,
                    channel: channel,
                    initialTagIDs: Set(store.resolveTags(channel).map(\.id)),
                    initialIsFavorite: store.isFavorite(channel),
                    onSaved: {}
                )
            }
        }
```

- [ ] **Step 3: Build**

Run: `xcodebuild build -scheme 20Four7 -destination 'platform=iOS Simulator,name=iPhone 17'`
Expected: BUILD SUCCEEDED

> Note: `Channel` already conforms to `Identifiable` (its `id: String`), so `.sheet(item:)` compiles without changes.

- [ ] **Step 4: Commit**

```bash
git add Sources/UI/ChannelTile.swift Sources/UI/GuideView.swift
git commit -m "feat: surface Edit… on channel tiles via an edit sheet"
```

---

## Task 9: Retire the obsolete rename path

`renameChannel` (and its title-only `LocalStore.updateUserChannelTitle`) are no longer reachable — title now flows through the edit form. Remove them and the test that exercised them.

> Keep `LocalStore.setCustomTitle` and `ChannelMerger`'s `customTitle` handling: legacy `customTitle` data on existing installs is still applied by the merge.

**Files:**
- Modify: `Sources/Stores/ChannelStore.swift`
- Modify: `Sources/Persistence/LocalStore.swift`
- Modify: `Tests/ChannelStoreTests.swift`

- [ ] **Step 1: Confirm there are no remaining callers**

Run: `grep -rn "renameChannel\|updateUserChannelTitle" Sources Tests`
Expected: only the definitions in `ChannelStore.swift` / `LocalStore.swift` and the `test_store_renames_curated_and_user_channels` test.

- [ ] **Step 2: Delete the methods and obsolete test**

1. In `Sources/Stores/ChannelStore.swift`, delete the entire `renameChannel(_:to:)` method.
2. In `Sources/Persistence/LocalStore.swift`, delete the entire `updateUserChannelTitle(id:title:)` method.
3. In `Tests/ChannelStoreTests.swift`, delete the entire `test_store_renames_curated_and_user_channels()` function.

- [ ] **Step 3: Build and run the full suite**

Run: `xcodebuild test -scheme 20Four7 -destination 'platform=iOS Simulator,name=iPhone 17'`
Expected: BUILD SUCCEEDED and all tests PASS.

- [ ] **Step 4: Commit**

```bash
git add Sources/Stores/ChannelStore.swift Sources/Persistence/LocalStore.swift Tests/ChannelStoreTests.swift
git commit -m "refactor: retire rename path now covered by the edit form"
```

---

## Final verification

- [ ] Run the full test suite once more: `xcodebuild test -scheme 20Four7 -destination 'platform=iOS Simulator,name=iPhone 17'` — all PASS.
- [ ] Manual smoke (simulator): long-press a curated tile → **Edit…** → change title + tags, toggle Live and Favorite → **Save**. Confirm the tile updates and the change persists across relaunch. Long-press it again → **Remove** → confirm it does not reappear after pulling to refresh.
- [ ] Manual smoke: long-press a user-added tile → **Edit…** → change fields → **Save**; confirm in-place update.
```
