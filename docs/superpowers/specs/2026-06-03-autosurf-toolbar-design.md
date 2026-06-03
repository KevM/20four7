# Auto-Surf in the Toolbar — Design

**Date:** 2026-06-03
**Status:** Approved

## Goal

Move the Auto-Surf affordance out of the Guide content area and into the
top-right navigation toolbar, make it less verbose (icon-only), and remove the
"copy YouTube playlist" toolbar button while preserving its code for a future
re-introduction.

## Current State

- **Auto-Surf** lives in `Sources/UI/GuideView.swift`. It is a verbose red pill
  button (`play.circle.fill` glyph + "Auto-Surf" label) rendered in the chip
  row next to `TagChipBar`, shown only when tags are selected *and*
  `store.filteredChannels` is non-empty. The action is passed in via an
  `onAutoSurf: () -> Void` closure owned by `RootView`.
- **Playlist copy** lives in `Sources/UI/RootView.swift` as a
  `ToolbarItem(placement: .topBarTrailing)`. It copies `store.filteredPlaylistURL`
  to the clipboard, swaps to a green checkmark for 1.5s (`@State copiedPlaylist`),
  and shows a screen-level top toast overlay ("Playlist URL copied to clipboard!").

## Decisions

- **No-tags behavior:** the Auto-Surf toolbar button appears only when active —
  it is absent from the toolbar until at least one tag is selected (not a
  disabled placeholder).
- **Empty filter:** when tags are selected but zero channels match, the button
  is hidden (matches the old button's `!filteredChannels.isEmpty` guard).
- **Verbosity:** icon-only, consistent with the existing Filter and `+` toolbar
  items.
- **Playlist code:** extract into a reusable, unreferenced component so re-adding
  later is a one-liner. The screen-level toast is preserved as a commented block
  in that same file.

## Changes

### 1. `Sources/UI/GuideView.swift` — strip the inline button

- Remove the red "Auto-Surf" `Button` and its enclosing
  `if !store.filteredChannels.isEmpty { … }` block. The chip-row `HStack`
  collapses to just `TagChipBar`.
- Remove the now-unused `onAutoSurf: () -> Void` stored property — the action
  moves to the toolbar owner (`RootView`).

### 2. `Sources/UI/RootView.swift` — new toolbar button, remove playlist

- Add a `ToolbarItem(placement: .topBarTrailing)` for Auto-Surf, rendered only
  when `!store.selectedTagIDs.isEmpty && !store.filteredChannels.isEmpty`.
  Icon-only `play.circle.fill`, tinted **red** to preserve the "go watch"
  identity. The action reuses the existing `startAutoSurfing(...)` path with
  `store.filteredChannels.first`.
- Update the `GuideView(...)` call site to drop the `onAutoSurf:` argument.
- Remove the playlist `ToolbarItem`, the `@State private var copiedPlaylist`,
  and the top toast `.overlay`.

Resulting trailing toolbar order: **Filter → Auto-Surf → +**.

### 3. `Sources/UI/PlaylistCopyButton.swift` (new) — preserved, unreferenced

- A self-contained `View` that owns its own `@State private var copiedPlaylist`,
  performs the clipboard copy of `store.filteredPlaylistURL`, swaps to the green
  checkmark for 1.5s, and applies `.disabled(store.filteredPlaylistURL == nil)`.
- Takes the `ChannelStore` so it stays a drop-in: re-adding later is
  `ToolbarItem(placement: .topBarTrailing) { PlaylistCopyButton(store: store) }`.
- The original screen-level toast overlay code is preserved verbatim as a
  commented block in this file, with a note explaining how to re-wire it at the
  `RootView` level (since a toolbar button cannot own a screen-level overlay).
- Not referenced anywhere yet, so it has no runtime effect.

## Out of Scope

- No change to the Auto-Surf playback behavior, interval, or lineup logic.
- No change to `ChannelStore.filteredPlaylistURL` or the playlist URL format.
- No new UI affordance for the playlist feature in this change.

## Testing

- Build the app for the `iPhone 17` simulator target (per `CLAUDE.md`).
- Manual verification: with no tags selected, no Auto-Surf button in the
  toolbar; selecting a tag with matching channels shows the red `play.circle.fill`
  toolbar button, and tapping it starts Auto-Surf; selecting a tag whose filter
  yields zero channels keeps the button hidden. Confirm the playlist toolbar
  button is gone and no "copied" toast appears.
