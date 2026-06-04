# Guide — Featured Top Tiles (Larger Cards on Wide Layouts)

**Date:** 2026-06-04
**Status:** Approved design, ready for implementation planning

## Summary

On wide (regular horizontal size class) layouts, render the top-ranked
channels in the Guide as larger tiles. The first two rows' worth of
`store.filteredChannels` are drawn at ~1.2× the normal tile size; the
remaining channels flow into the existing normal-size grid directly below,
with no section header or divider (a seamless size change, not a separate
"featured" section). On compact width (iPhone, and iPad in a narrow Split
View / Slide Over pane) the Guide is unchanged — a single uniform grid.

## Motivation

The Guide already ranks channels by a dwell-boost popularity score
(`ChannelStore.recomputeFilteredChannels` → `popularityScore`). Giving the
top of that list bigger cards on larger form factors adds visual hierarchy
and makes the most-watched channels easier to hit, using the screen real
estate that iPad affords.

## Scope decisions (resolved during brainstorming)

- **Arrangement:** Inline, no section break. The bigger tiles flow straight
  into the normal tiles below. The two tile sizes fit a different number of
  columns per row, so their right edges will not align — this "seam" is
  accepted and intentional.
- **Magnitude:** Subtle, ~1.2×. Normal wide tile is 220×135pt; featured tile
  is 264×162pt.
- **How many:** Not a fixed count of channels — the **first two rows** at the
  featured size. Row count is width-dependent (more columns on a wide
  landscape iPad than in portrait or a split pane), computed from the
  measured content width.
- **Filter interaction:** Always the top of the *current* `filteredChannels`,
  so featuring follows whatever tag filter / sort is active.
- **Few channels:** If there are fewer channels than two featured rows, they
  are all featured (everything big). There is no minimum-count gate.
- **Form factor:** Featuring happens only on wide layouts. Compact width keeps
  the current single uniform grid with zero behavior change.

## Approach

Geometry-computed rows (chosen over a fixed featured count): measure the
Guide's available content width, compute how many featured-size columns fit,
and feature `columns × rowCount` channels. This honors "first one or two
rows" faithfully and stays reactive to rotation, resize, and multitasking
pane changes.

### Width measurement (iOS 17 compatible)

Deployment target is iOS 17.0, so `onGeometryChange` (iOS 18+) is not
available. Measure with the established pattern: a `GeometryReader` in the
`.background` of the grid container publishes the width through a
`PreferenceKey`, captured into a `@State` property on `GuideView`. This
updates reactively on rotation, resize, and Split View / Slide Over changes,
satisfying the reactivity requirement documented on `LayoutMetrics`.

## Components

### `LayoutMetrics` (Sources/UI/LayoutMetrics.swift)

All sizing and column math stays in this single source of truth, grouped
under the existing "Guide grid" section. New members:

- `featuredTileMinWidth: CGFloat` → `wide ? 264 : tileMinWidth`
- `featuredTileHeight: CGFloat` → `wide ? 162 : tileHeight`
- `featuredRowCount: Int` → `wide ? 2 : 0`
  The `0` on compact is what disables featuring there — callers treat
  `featuredRowCount == 0` as "no featured grid, render the normal grid only."
- `func featuredColumnCount(availableWidth: CGFloat) -> Int`
  Derives the number of featured columns that fit:
  `max(1, floor((availableWidth + gridSpacing) / (featuredTileMinWidth + gridSpacing)))`.
  `availableWidth` is the content width already inside `gridHPadding`.

The featured count of channels = `featuredColumnCount(...) * featuredRowCount`.

### `GuideView` (Sources/UI/GuideView.swift)

- Adds `@State private var contentWidth: CGFloat = 0`, fed by the background
  `GeometryReader` + `PreferenceKey`.
- Computes the featured slice: `featuredCount = m.featuredColumnCount(availableWidth: contentWidth) * m.featuredRowCount`, then
  `featured = filteredChannels.prefix(min(featuredCount, filteredChannels.count))`
  and `rest = filteredChannels` after that prefix.
- Rendering:
  - If `m.featuredRowCount == 0` **or** `contentWidth == 0` (not yet
    measured): render exactly the current single adaptive `LazyVGrid` over
    all `filteredChannels`. This guarantees no iPhone behavior change and no
    first-frame flash before the width is known.
  - Otherwise: a featured `LazyVGrid` with an **explicit** fixed column count
    (`featuredColumnCount` flexible columns, so "rows" are deterministic) of
    `isFeatured` tiles, stacked directly above a normal adaptive `LazyVGrid`
    of the remaining tiles. Same horizontal padding (`gridHPadding`) and
    spacing (`gridSpacing`) as today.
- The active-filter chip bar and all other Guide behavior (`refresh`,
  `refreshable`, edit sheet) are unchanged.

### `ChannelTile` (Sources/UI/ChannelTile.swift)

- Adds `var isFeatured: Bool = false`.
- When `isFeatured`, the tile uses `m.featuredTileHeight` instead of
  `m.tileHeight` (passed through to `ChannelTileContent.height`, which is
  already parameterized). The tile's width is governed by its grid column,
  not the tile itself.
- Tile content is otherwise unchanged: thumbnail scales to the taller frame,
  title stays `.body`. Appropriate for a subtle bump and keeps the change
  small. Context-menu preview sizing is untouched.

## Data flow

`ChannelStore.filteredChannels` (already ranked by popularity score) →
`GuideView` reads `contentWidth` from the geometry background → `LayoutMetrics`
computes `featuredColumnCount` → `GuideView` splits the list into featured
prefix + remainder → two grids render with `isFeatured` true/false. No store,
ranking, or persistence changes — this is purely presentational.

## Edge cases

- **Before width is measured** (`contentWidth == 0`): render the plain single
  grid; swap to the split layout once a real width arrives.
- **Compact width** (`featuredRowCount == 0`): single uniform grid, identical
  to today.
- **Fewer channels than two featured rows:** the `min(featuredCount, count)`
  prefix means every channel is featured; the remainder grid is empty and not
  rendered.
- **Empty guide:** both slices empty; nothing renders, as today.
- **Rotation / resize / split-view change:** `contentWidth` updates via the
  preference key, `featuredColumnCount` recomputes, the split re-lays out.

## Testing

- **Unit (`Tests`):** `LayoutMetrics` cases for
  - `featuredColumnCount(availableWidth:)` at representative widths (e.g. a
    portrait-iPad width, a landscape-iPad width, and a narrow value) asserting
    the expected integer column counts and the `max(1, …)` floor.
  - `featuredRowCount`, `featuredTileMinWidth`, `featuredTileHeight` returning
    the wide vs compact values for `.regular` vs `.compact` size classes.
  These are pure functions, so coverage is deterministic and cheap.
- **Manual:** build and run on iPhone 17 (compact — confirm unchanged) and an
  iPad target (wide — confirm the first two rows are larger, the seam looks
  right, and rotation/split-view re-lays out correctly).

## Out of scope

- Changing the ranking / popularity score.
- A labeled "Top Picks" section or any divider (explicitly rejected — inline).
- Any compact-width changes.
- Featured-specific title/typography changes beyond the larger frame.
