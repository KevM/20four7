# Guide Search with YouTube Fallback Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `.searchable` field to the Guide that filters the user's channel lineup by title or tag name, and always offers a "Search YouTube for '<query>'" button that drops into the existing add-channel workflow pre-seeded with that query.

**Architecture:** All filtering stays in `ChannelStore`, which already owns tag filtering and sorting. A new transient `searchQuery` folds into the existing `recomputeFilteredChannels()` pipeline (tag filter → search → sort), so `filteredChannels` remains the single source of truth and `GuideView` stays a pure renderer. A new pure `ChannelSearch` enum (mirroring `TagFilter`) does the matching and is unit-tested in isolation. `GuideView` gains a footer button wired up through `RootView` to the existing `YouTubeBrowserView`, which gains an optional initial search query.

**Tech Stack:** Swift 6, SwiftUI (`.searchable`), XCTest, XcodeGen (project generated from `project.yml` — new `.swift` files under `Sources/`/`Tests/` are auto-globbed; regenerate locally with `./generate.sh`).

---

## Important environment notes

- **The Xcode project is generated.** Adding `Sources/Core/ChannelSearch.swift` and `Tests/ChannelSearchTests.swift` requires **no** project-file edits, but you must regenerate before building locally: run **`./generate.sh`** (never `xcodegen generate` directly).
- **Simulator target:** use **iPhone 17** (iPhone 16 may be absent and fails with exit code 70).
- **Run the full test suite** with:
  ```sh
  xcodebuild test -scheme 20Four7 -destination 'platform=iOS Simulator,name=iPhone 17'
  ```
  Run a single class by appending `-only-testing:TwentyFourSevenTests/<ClassName>`.

---

## File Structure

- **Create** `Sources/Core/ChannelSearch.swift` — pure matching logic (title + tag name, case/diacritic-insensitive). One responsibility, no dependencies beyond `Channel`/`Tag`.
- **Create** `Tests/ChannelSearchTests.swift` — unit tests for `ChannelSearch`.
- **Modify** `Sources/Stores/ChannelStore.swift` — add `searchQuery` and fold it into `recomputeFilteredChannels()`.
- **Modify** `Tests/ChannelStoreTests.swift` — add search-composition tests.
- **Modify** `Sources/UI/YouTubeBrowserView.swift` — accept an optional `initialSearchQuery`.
- **Modify** `Sources/UI/GuideView.swift` — `onSearchYouTube` callback, featured-split suppression while searching, and the search footer.
- **Modify** `Sources/UI/RootView.swift` — `.searchable` binding, pending-query state, and pass-through wiring.

---

## Task 1: `ChannelSearch` matching logic

**Files:**
- Create: `Sources/Core/ChannelSearch.swift`
- Test: `Tests/ChannelSearchTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/ChannelSearchTests.swift`:

```swift
import XCTest
@testable import TwentyFourSeven

final class ChannelSearchTests: XCTestCase {
    private let tagsByID: [String: Tag] = [
        "rain": Tag(id: "rain", name: "Rain", kind: .editorial, sortOrder: 1),
        "nature": Tag(id: "nature", name: "Nature", kind: .user, sortOrder: 100),
    ]

    private let channels = [
        Channel(id: "a", title: "Cozy Fireplace", youTubeVideoID: "v1",
                source: .curated, isLiveExpected: true, tagIDs: ["rain"]),
        Channel(id: "b", title: "Café Jazz", youTubeVideoID: "v2",
                source: .curated, isLiveExpected: true, tagIDs: ["nature"]),
        Channel(id: "c", title: "City Walk", youTubeVideoID: "v3",
                source: .curated, isLiveExpected: true, tagIDs: []),
    ]

    func test_emptyQueryReturnsAll() {
        XCTAssertEqual(ChannelSearch.filter(channels, query: "", tagsByID: tagsByID).count, 3)
    }

    func test_whitespaceQueryReturnsAll() {
        XCTAssertEqual(ChannelSearch.filter(channels, query: "   ", tagsByID: tagsByID).count, 3)
    }

    func test_matchesTitleSubstringCaseInsensitively() {
        let result = ChannelSearch.filter(channels, query: "fire", tagsByID: tagsByID)
        XCTAssertEqual(result.map(\.id), ["a"])
    }

    func test_matchesTagNameEvenWhenTitleDoesNot() {
        // "a" is titled "Cozy Fireplace" but tagged Rain.
        let result = ChannelSearch.filter(channels, query: "rain", tagsByID: tagsByID)
        XCTAssertEqual(result.map(\.id), ["a"])
    }

    func test_matchIsDiacriticInsensitive() {
        let result = ChannelSearch.filter(channels, query: "cafe", tagsByID: tagsByID)
        XCTAssertEqual(result.map(\.id), ["b"])
    }

    func test_noMatchReturnsEmpty() {
        XCTAssertTrue(ChannelSearch.filter(channels, query: "zzz", tagsByID: tagsByID).isEmpty)
    }
}
```

- [ ] **Step 2: Regenerate the project so the new files are picked up**

Run: `./generate.sh`
Expected: exits 0, regenerates `20Four7.xcodeproj`.

- [ ] **Step 3: Run the tests to verify they fail**

Run:
```sh
xcodebuild test -scheme 20Four7 -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TwentyFourSevenTests/ChannelSearchTests
```
Expected: FAILS to compile — "cannot find 'ChannelSearch' in scope".

- [ ] **Step 4: Write the implementation**

Create `Sources/Core/ChannelSearch.swift`:

```swift
import Foundation

enum ChannelSearch {
    /// Free-text Guide search. A channel matches when the trimmed query is a
    /// substring of its title OR of any of its resolved tag names, compared
    /// case- and diacritic-insensitively. An empty/whitespace query returns the
    /// input unchanged (no-op), mirroring `TagFilter.filter`'s empty-selection
    /// behavior.
    static func filter(_ channels: [Channel], query: String,
                       tagsByID: [String: Tag]) -> [Channel] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return channels }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        return channels.filter { channel in
            if channel.title.range(of: trimmed, options: options) != nil { return true }
            return channel.tagIDs.contains { tagID in
                guard let name = tagsByID[tagID]?.name else { return false }
                return name.range(of: trimmed, options: options) != nil
            }
        }
    }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run:
```sh
xcodebuild test -scheme 20Four7 -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TwentyFourSevenTests/ChannelSearchTests
```
Expected: PASS (6 tests).

- [ ] **Step 6: Commit**

```bash
git add Sources/Core/ChannelSearch.swift Tests/ChannelSearchTests.swift
git commit -m "feat: add ChannelSearch title/tag-name matching"
```

---

## Task 2: Fold `searchQuery` into `ChannelStore`

**Files:**
- Modify: `Sources/Stores/ChannelStore.swift` (add property near the other `@Published` filter state ~line 12; update `recomputeFilteredChannels()` ~lines 106–129)
- Test: `Tests/ChannelStoreTests.swift`

- [ ] **Step 1: Write the failing test**

Add to `Tests/ChannelStoreTests.swift` (inside the `ChannelStoreTests` class):

```swift
func test_searchNarrowsWithinActiveTagFilter() async throws {
    let localStore = try makeStore()
    // Two user channels tagged "rain" (so both pass a rain tag filter),
    // with distinct titles so a title search can isolate one of them.
    localStore.addUserChannel(Channel(id: "u-jazz", title: "Jazz Cafe",
        youTubeVideoID: "jazz1234567", source: .user, isLiveExpected: true, tagIDs: ["rain"]))
    localStore.addUserChannel(Channel(id: "u-birds", title: "Forest Birds",
        youTubeVideoID: "birds123456", source: .user, isLiveExpected: true, tagIDs: ["rain"]))
    let store = ChannelStore(remoteConfig: makeRemoteConfig(), localStore: localStore)
    await store.refresh()

    // Filter to rain: catalog "c1" (Rain) + both user channels all qualify.
    store.selectedTagIDs = ["rain"]
    XCTAssertEqual(Set(store.filteredChannels.map(\.id)), ["c1", "u-jazz", "u-birds"])

    // Search "jazz": only the title "Jazz Cafe" matches, within the rain filter.
    store.searchQuery = "jazz"
    XCTAssertEqual(store.filteredChannels.map(\.id), ["u-jazz"])

    // Clearing the query restores the full filtered set.
    store.searchQuery = ""
    XCTAssertEqual(Set(store.filteredChannels.map(\.id)), ["c1", "u-jazz", "u-birds"])
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```sh
xcodebuild test -scheme 20Four7 -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TwentyFourSevenTests/ChannelStoreTests/test_searchNarrowsWithinActiveTagFilter
```
Expected: FAILS to compile — "value of type 'ChannelStore' has no member 'searchQuery'".

- [ ] **Step 3: Add the `searchQuery` property**

In `Sources/Stores/ChannelStore.swift`, immediately after the `selectedTagIDs` declaration block (after its closing `}` at line 18), add:

```swift
    /// Transient free-text Guide search. Composed on top of the tag filter in
    /// `recomputeFilteredChannels()`. Intentionally not persisted — search
    /// resets each session.
    @Published var searchQuery: String = "" {
        didSet {
            guard searchQuery != oldValue else { return }
            recomputeFilteredChannels()
        }
    }
```

- [ ] **Step 4: Fold search into the filter pipeline**

In `recomputeFilteredChannels()`, replace these lines:

```swift
        let now = Date()
        let filtered = TagFilter.filter(list, anyOf: selectedTagIDs)
            .sorted { a, b in
```

with:

```swift
        let now = Date()
        let tagFiltered = TagFilter.filter(list, anyOf: selectedTagIDs)
        let searched = ChannelSearch.filter(tagFiltered, query: searchQuery, tagsByID: tagsByID)
        let filtered = searched
            .sorted { a, b in
```

(The rest of the method — the sort body, `self.filteredChannels = filtered`, and the `filteredPlaylistURL` derivation — is unchanged.)

- [ ] **Step 5: Run the test to verify it passes**

Run:
```sh
xcodebuild test -scheme 20Four7 -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TwentyFourSevenTests/ChannelStoreTests/test_searchNarrowsWithinActiveTagFilter
```
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/Stores/ChannelStore.swift Tests/ChannelStoreTests.swift
git commit -m "feat: compose Guide search into ChannelStore filter pipeline"
```

---

## Task 3: Thread an initial search query into `YouTubeBrowserView`

**Files:**
- Modify: `Sources/UI/YouTubeBrowserView.swift` (property list ~lines 16–19; `initialURL` ~lines 40–45)

This task changes a SwiftUI view, so it is verified by a compile (no view unit tests in this project). `RootView` is updated in Task 5 to pass the new parameter — until then the build stays green because the parameter has a default.

- [ ] **Step 1: Add the `initialSearchQuery` stored property**

In `Sources/UI/YouTubeBrowserView.swift`, in the `YouTubeBrowserView` property list, add `initialSearchQuery` after `onWatchNow`:

```swift
    let store: ChannelStore
    let localStore: LocalStore
    let onSaved: () -> Void
    let onWatchNow: (Channel, Double) -> Void
    /// Optional query to pre-seed the YouTube search with. When nil, defaults to
    /// the curated "live nature" landing search.
    var initialSearchQuery: String? = nil
```

- [ ] **Step 2: Build the initial URL from the query**

Replace the existing `initialURL` computed property:

```swift
    var initialURL: URL {
        // Default to "live nature" with live stream filter
        let query = "live nature".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "https://m.youtube.com/results?search_query=\(query)&sp=EgJAAQ%3D%3D")
            ?? URL(string: "https://m.youtube.com")!
    }
```

with:

```swift
    var initialURL: URL {
        // Use the caller's query when provided, else the curated "live nature"
        // landing search. Either way keep YouTube's live-stream results filter.
        let trimmed = initialSearchQuery?.trimmingCharacters(in: .whitespacesAndNewlines)
        let searchText = (trimmed?.isEmpty == false) ? trimmed! : "live nature"
        let query = searchText.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "https://m.youtube.com/results?search_query=\(query)&sp=EgJAAQ%3D%3D")
            ?? URL(string: "https://m.youtube.com")!
    }
```

- [ ] **Step 3: Build to verify it compiles**

Run:
```sh
xcodebuild build -scheme 20Four7 -destination 'platform=iOS Simulator,name=iPhone 17'
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add Sources/UI/YouTubeBrowserView.swift
git commit -m "feat: let YouTubeBrowserView accept an initial search query"
```

---

## Task 4: Add the search footer and featured suppression to `GuideView`

**Files:**
- Modify: `Sources/UI/GuideView.swift` (property list ~lines 4–5; `body` ~lines 47–96; add a private footer view)

- [ ] **Step 1: Add the `onSearchYouTube` callback property**

In `Sources/UI/GuideView.swift`, add the callback next to the existing `onSelect`:

```swift
struct GuideView: View {
    @ObservedObject var store: ChannelStore
    let onSelect: (Channel) -> Void
    /// Invoked from the search footer with the current trimmed query to launch
    /// the YouTube add workflow pre-seeded with it.
    let onSearchYouTube: (String) -> Void
```

- [ ] **Step 2: Add a derived `trimmedQuery` / `isSearching` helper**

In `GuideView`, add these computed properties near `hasChips` (~line 16):

```swift
    private var trimmedQuery: String {
        store.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var isSearching: Bool { !trimmedQuery.isEmpty }
```

- [ ] **Step 3: Suppress the featured split while searching**

In `body`, inside the `Group`, change:

```swift
                    Group {
                        let count = featuredCount(availableWidth)
```

to:

```swift
                    Group {
                        let count = isSearching ? 0 : featuredCount(availableWidth)
```

- [ ] **Step 4: Add the search footer below the grid**

In `body`, locate the `.padding(.horizontal, m.gridHPadding)` that closes the `Group` (~line 93). Immediately **after** that line (still inside the outer `VStack`), add:

```swift
                    if isSearching {
                        GuideSearchFooter(
                            query: trimmedQuery,
                            hasMatches: !store.filteredChannels.isEmpty,
                            onSearchYouTube: { onSearchYouTube(trimmedQuery) }
                        )
                        .padding(.horizontal, m.gridHPadding)
                    }
```

- [ ] **Step 5: Add the `GuideSearchFooter` private view**

At the end of `Sources/UI/GuideView.swift`, after the closing brace of `struct GuideView`, add:

```swift
/// Footer shown beneath the Guide grid while a search is active: an optional
/// "no local matches" line plus a button that hands the query off to the
/// YouTube add workflow. Uses semantic fonts so it honors Dynamic Type.
private struct GuideSearchFooter: View {
    let query: String
    let hasMatches: Bool
    let onSearchYouTube: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !hasMatches {
                Text("No channels in your Guide match “\(query)”.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Button(action: onSearchYouTube) {
                Label("Search YouTube for “\(query)”", systemImage: "magnifyingglass")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .cornerRadius(10)
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
```

- [ ] **Step 6: Build to verify it compiles**

The `GuideView(...)` call site in `RootView` does not yet pass `onSearchYouTube`, so a build now is **expected to fail** at that call site only. Confirm `GuideView.swift` itself is internally consistent by checking the error is solely the missing-argument error in `RootView.swift`:

Run:
```sh
xcodebuild build -scheme 20Four7 -destination 'platform=iOS Simulator,name=iPhone 17'
```
Expected: FAILS with "missing argument for parameter 'onSearchYouTube' in call" pointing at `RootView.swift`. (Task 5 fixes this.) If any error points at `GuideView.swift`, fix it before moving on.

- [ ] **Step 7: Commit**

```bash
git add Sources/UI/GuideView.swift
git commit -m "feat: add Guide search footer and suppress featured tiles while searching"
```

---

## Task 5: Wire `.searchable` and the YouTube hand-off in `RootView`

**Files:**
- Modify: `Sources/UI/RootView.swift` (state ~lines 6–11; `GuideView`/toolbar ~lines 22–57; add-channel sheet ~lines 69–85)

- [ ] **Step 1: Add pending-query state**

In `Sources/UI/RootView.swift`, add a state property next to `showAddChannel` (~line 7):

```swift
    @State private var showAddChannel = false
    /// Query to pre-seed the add sheet with when launched from the search
    /// footer; nil for the plain "+" entry point.
    @State private var addSearchQuery: String? = nil
```

- [ ] **Step 2: Pass `onSearchYouTube` to `GuideView` and add `.searchable`**

Replace the `GuideView(...)` invocation and its `.toolbar` opening:

```swift
            GuideView(store: store, onSelect: { channel in
                startPlaying(channel)
            })
            .toolbar {
```

with:

```swift
            GuideView(store: store, onSelect: { channel in
                startPlaying(channel)
            }, onSearchYouTube: { query in
                addSearchQuery = query
                showAddChannel = true
            })
            .searchable(
                text: $store.searchQuery,
                placement: .navigationBarDrawer(displayMode: .automatic),
                prompt: "Search your Guide"
            )
            .toolbar {
```

- [ ] **Step 3: Reset the pending query from the "+" button**

Replace the add-channel toolbar button:

```swift
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAddChannel = true } label: { Image(systemName: "plus") }
                }
```

with:

```swift
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        addSearchQuery = nil
                        showAddChannel = true
                    } label: { Image(systemName: "plus") }
                }
```

- [ ] **Step 4: Pass the query into the add sheet**

In the `.sheet(isPresented: $showAddChannel)` content, add `initialSearchQuery` to the `YouTubeBrowserView` initializer:

```swift
            YouTubeBrowserView(
                store: store,
                localStore: env.localStore,
                initialSearchQuery: addSearchQuery,
                onSaved: {
                    Task { await store.refresh() }
                },
```

(The `onWatchNow` closure below it is unchanged.)

- [ ] **Step 5: Build to verify the whole app compiles**

Run:
```sh
xcodebuild build -scheme 20Four7 -destination 'platform=iOS Simulator,name=iPhone 17'
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 6: Run the full test suite**

Run:
```sh
xcodebuild test -scheme 20Four7 -destination 'platform=iOS Simulator,name=iPhone 17'
```
Expected: all tests PASS (including the new `ChannelSearchTests` and `test_searchNarrowsWithinActiveTagFilter`).

- [ ] **Step 7: Commit**

```bash
git add Sources/UI/RootView.swift
git commit -m "feat: wire Guide .searchable and YouTube fallback hand-off"
```

---

## Manual verification (after Task 5)

Run the app on the iPhone 17 simulator and confirm:

1. Pulling down / focusing the Guide reveals a "Search your Guide" field.
2. Typing a channel title or tag name filters the grid live; featured tiles collapse to a uniform grid while searching.
3. A "Search YouTube for '<query>'" button shows beneath results; with a no-match query, the grid is empty and a "No channels…match" line appears above the button.
4. Tapping the button opens Browse YouTube already showing results for the typed query (live-stream filtered). Selecting a video proceeds through the normal add form and the saved channel appears in the Guide.
5. The "+" toolbar button still opens Browse YouTube on the default "live nature" search.

---

## Self-Review Notes

- **Spec coverage:** ChannelSearch logic (Task 1) ✓; store composition / "within active filter" (Task 2) ✓; `.searchable` + title+tag matching (Tasks 1,5) ✓; always-on YouTube footer + empty state (Task 4) ✓; live-filter reuse of the query (Task 3) ✓; featured suppression (Task 4) ✓; transient/non-persisted query (Task 2) ✓; tests for ChannelSearch + ChannelStore (Tasks 1,2) ✓.
- **Known side effect (accepted in spec):** with a tag filter active, search also narrows `filteredPlaylistURL`, so Auto-Surf surfs the search results. No task changes this by design.
- **Type consistency:** `ChannelSearch.filter(_:query:tagsByID:)`, `ChannelStore.searchQuery`, `GuideView.onSearchYouTube`, `YouTubeBrowserView.initialSearchQuery`, and `GuideSearchFooter(query:hasMatches:onSearchYouTube:)` are referenced identically across all tasks.
