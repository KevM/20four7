# Guide Search with YouTube Fallback — Design

**Date:** 2026-06-05
**Status:** Approved, ready for implementation planning

## Summary

Add a search field to the Guide's toolbar. By default it searches the user's
own Guide (the merged channel lineup). When a query is active, the Guide always
offers a "Search YouTube for '<query>'" affordance at the bottom that launches
the existing add-channel workflow pre-seeded with that query. If the Guide has
no matches, that same affordance is the natural empty state.

## Decisions (from brainstorming)

- **Interaction model:** SwiftUI's native `.searchable` on the Guide — typing
  filters the existing channel grid live. No separate search screen.
- **Match scope:** A channel matches against its **title or any of its tag
  names** (case- and diacritic-insensitive).
- **Matching model:** Hybrid fuzzy. The query is tokenized on whitespace; every
  token must match some field (AND across tokens, OR across fields). Each token
  is scored against a field with three tiers, strongest first: contiguous
  substring → subsequence (scored by tightness of the minimal containing window)
  → bounded Damerau-Levenshtein typo tolerance (length-scaled budget; none for
  tokens ≤ 3 chars).
- **Ranking:** While a query is active, results are ordered by aggregate match
  score (best first), with the popularity/recency order as the tiebreaker. With
  no query, the existing popularity/recency order applies unchanged. Ranking is
  what lets the subsequence tier be permissive — weak matches sink rather than
  masquerade as good ones.
- **Filter + search composition:** Search refines **within** the active tag
  filter (filter AND search), not across all channels.
- **YouTube fallback placement:** Shown **always** while a query is active (a
  row beneath any Guide matches), not only on an empty result set.
- **YouTube fallback behavior:** Reuses the existing add flow's **live-stream
  search filter** (`sp=EgJAAQ%3D%3D`), swapping in the user's query for the
  default `"live nature"`.

## Components

### 1. `Sources/Core/ChannelSearch.swift` (new)

A pure, testable enum scoring one channel against a query:

```swift
enum ChannelSearch {
    /// Aggregate fuzzy score for `channel` against `query`, or `nil` if it does
    /// not match every token. Empty/whitespace query scores 0 (matches all).
    static func score(_ channel: Channel, query: String,
                      tagsByID: [String: Tag]) -> Double?
}
```

- Tokenized AND / per-field OR: a channel matches only when **every**
  whitespace-separated token matches at least one field; tokens may match
  different fields. This makes "Norway Rail" match a title like "Norway's
  Railway ..." that no whole-query substring match would.
- Three-tier per-token scoring (contiguous → subsequence-by-tightness → bounded
  typo). `nil` is the AND gate (some token matched nowhere); otherwise the summed
  best-per-token score, used for ranking. Higher is better; exact contiguous
  matches outscore loose subsequence matches.
- Resolves tag names via `tagsByID`, so "nature" matches a channel tagged
  *Nature* even when its title doesn't say so.

### 2. `ChannelStore` changes

- New `@Published var searchQuery: String = ""` with a `didSet` calling
  `recomputeFilteredChannels()`. Transient per session — **not persisted**.
- `recomputeFilteredChannels()` branches after the tag filter: with no query it
  applies the popularity/recency sort (extracted into a `popularityOrders`
  comparator); with a query it keeps channels whose `ChannelSearch.score` is
  non-nil and sorts by score descending, using `popularityOrders` as the
  tiebreaker.
- `filteredChannels` (and the derived `filteredPlaylistURL`) remain the single
  source of truth. The "within active filter" behavior falls out for free.

### 3. `GuideView` changes

- New callback: `let onSearchYouTube: (String) -> Void`.
- Derive `isSearching` from `store.searchQuery` (trimmed non-empty).
- When `isSearching`, **suppress the featured-tile split** — render the plain
  adaptive grid only (large featured tiles among search hits look wrong).
- When `isSearching`, append a footer below the grid:
  - If zero matches: a muted line — "No channels in your Guide match '<query>'."
  - Always: a **"Search YouTube for '<query>'"** button calling
    `onSearchYouTube(query)`.
- Use semantic fonts. Add `LayoutMetrics` computed properties only if phone vs
  iPad sizing actually diverges (per the project's `LayoutMetrics` convention).

### 4. `RootView` wiring

- Apply `.searchable(text: $store.searchQuery,`
  `placement: .navigationBarDrawer(displayMode: .automatic),`
  `prompt: "Search your Guide")` to `GuideView`.
- New `@State private var addSearchQuery: String? = nil`.
- The existing `+` toolbar button sets `addSearchQuery = nil` before presenting
  (unchanged behavior — defaults to "live nature").
- Pass `onSearchYouTube: { query in addSearchQuery = query; showAddChannel = true }`
  to `GuideView`.
- Pass `initialSearchQuery: addSearchQuery` into the add sheet.

### 5. `YouTubeBrowserView` changes

- New `let initialSearchQuery: String?` (default `nil`).
- `initialURL` builds its query from `initialSearchQuery ?? "live nature"`,
  keeping the existing live-stream `sp=EgJAAQ%3D%3D` filter.
- Everything downstream (embeddability validation, `AddChannelView`) is
  unchanged — the fallback drops the user into the exact same add workflow.

## Data flow

1. User types in the search field → `store.searchQuery` updates →
   `recomputeFilteredChannels()` → grid re-renders and the footer appears.
2. User taps "Search YouTube for X" → `RootView` stashes the query and presents
   `YouTubeBrowserView` pre-searched.
3. User picks a video → `AddChannelView` → saved channel appears back in the
   Guide via the normal refresh.

## Error handling

- Search is pure local filtering — no failure modes.
- A whitespace-only query is treated as no search: footer hidden, full list
  shown.
- YouTube-side errors (non-embeddable video, etc.) are handled by the existing
  validation in the add flow — out of scope here.

## Testing

- `ChannelSearchTests` (new): title/tag-name matching, case- & diacritic-
  insensitivity, empty/whitespace passthrough, multi-token AND across fields,
  subsequence abbreviation, typo tolerance (and its absence for short tokens),
  and score ordering (exact > loose; tighter > looser).
- `ChannelStoreTests` (extend): `searchQuery` narrows `filteredChannels`
  **within** an active tag filter and clears back; ranking by match score
  overrides popularity while searching.

## Known side effect

With a tag filter active, searching also narrows `filteredPlaylistURL` and
re-orders it by match score, so **Auto-Surf will surf the current search results
in ranked order**. This is accepted as the intended behavior. If it later proves
surprising, Auto-Surf could be made to ignore the search query, but that is out
of scope for this change.

## Out of scope

- Search history / recent searches.
- Searching the remote catalog beyond what's already merged into the lineup.
- Persisting the query across launches.
