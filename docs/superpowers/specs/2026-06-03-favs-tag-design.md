# Favs as a tag — design

- **Date:** 2026-06-03
- **Status:** Approved design, ready for implementation plan
- **Approach:** A — keep the existing `isFavorite` boolean as the source of truth; derive a `favs` tag at merge time.

## Goal

Favorited videos become their own tag named **"favs"** that users filter by exactly like
any other tag. Marking a catalog (curated) video as a favorite is per-user and local —
it never affects the shared catalog or other users.

## Background — how things are stored today

- A channel's tags are id-strings in `Channel.tagIDs`. For curated channels they come from
  the remote catalog; for user-added channels they're persisted in `UserChannel.tagIDs`.
- The "user tags" shown as chips are **synthesized at runtime** from channels' `tagIDs`
  (`ChannelStore.reloadLineup`); they are not stored as `Tag` records.
- Favorites are a single boolean `ChannelUserState.isFavorite`, keyed by `channelID`,
  applied uniformly to curated **and** user channels. This per-user overlay table also
  carries a `userID?` reserved for future CloudKit sync, which is why favorites are already
  isolated per-user.
- `ChannelUserState.userTagIDs` exists in the model but is **dormant** — never read or
  written, and not applied by `ChannelMerger`.

## Decision and rationale

We keep favorites as the existing `isFavorite` boolean (storage layer) and make `favs`
behave as a genuine tag at the runtime layer by injecting the id `"favs"` into a channel's
runtime `tagIDs` during the merge when it is favorited. The injected value is a pure derived
view, recomputed on every merge and never persisted — so there is a single source of truth
(the boolean) and **no data migration**.

We rejected storing favorites in `userTagIDs` (the "make favs a stored tag" approach). Its
only real advantage was building plumbing for *user-applied tags on catalog channels*, but
that need is better served by a separate **"adopt a catalog channel"** feature (see
Follow-ups), so the migration cost buys nothing here.

## Design

### 1. The favs tag

Add a reserved id and factory on `Tag`:

- `Tag.favsID = "favs"`
- A derived tag: `Tag(id: "favs", name: "favs", symbol: "star.fill", kind: .derived, sortOrder: -1)`
  (below editorial tags at `0+` and user tags at `100`, so it sorts first).

It is never persisted and never appears in any channel's stored `tagIDs`. It is constructed
on demand by `ChannelStore`. (`name` = "favs" and symbol `star.fill` are deliberate but
trivially changeable.)

### 2. Merge-time injection (single source of derivation)

In `ChannelMerger.merge`, when a channel's `ChannelUserState.isFavorite == true`, append
`Tag.favsID` to the merged channel's `tagIDs` (dedup; don't double-add). Because favoriting
always creates/updates a `ChannelUserState` (`LocalStore.setFavorite`), every favorited
channel — curated or user — flows through the state branch and receives the injected id.

Consequence: `favs` is now a real id in `Channel.tagIDs`, so **`TagFilter` needs no
change** — selecting favs filters via the existing union (OR) match, identical to every
other tag.

### 3. Chip presence, count, pinning

In `ChannelStore.reloadLineup`:

- The existing tag-count loop over `channel.tagIDs` now counts `favs` automatically, so
  `tagChannelCounts[Tag.favsID]` equals the number of favorited (visible) channels.
- If `tagChannelCounts[Tag.favsID] > 0`, prepend the derived favs `Tag` to `chipTags`;
  otherwise omit it. (Hidden until ≥1 favorite.)
- Pinning: give favs the lowest `sortOrder` and tie-break it first in `isBaseSortBefore`,
  so it sits at the front of both the filter picker and the active-chip bar, within its
  selected/unselected group (the existing "selected first" rule still applies).

### 4. Reactivity on favorite toggle

`ChannelStore.toggleFavorite` currently updates only `favoriteIDs`. It must re-derive the
lineup so the injected `favs` ids, chip presence, count, and filtered list all update:

- After persisting the new favorite state, re-run the merge-derivation (call `reloadLineup`,
  matching how `renameChannel` / `removeChannel` already refresh) **or** apply the
  equivalent incremental update (add/remove `Tag.favsID` on the toggled channel in the
  in-memory `channels`, update `tagChannelCounts[Tag.favsID]`, add/remove the favs chip,
  then `recomputeFilteredChannels`).
- Prefer the incremental update for the in-player star tap (`PlayerView`) to avoid rebuilding
  the whole lineup mid-playback; the plan may start with `reloadLineup` and optimize if it
  proves janky.
- When the favorite count drops to 0, remove `Tag.favsID` from `selectedTagIDs` so the guide
  doesn't get stuck on an empty, now-hidden filter.

### 5. Surfaces

- **Filter picker (`TagPickerSheetView`) and active-chip bar (`TagChipBar`)** render
  `store.chipTags` + `tagChannelCounts` — favs appears in both with no view changes.
- **On-tile tag chips** (per-channel display via `resolveTags`) must **exclude** derived
  tags so a favorited tile doesn't show a redundant favs chip next to its existing star.
  Filter `Tag.favsID` (or `kind == .derived`) out of the per-channel tag display path.
- **`AddChannelView`** builds its assignable tag list from `editorialTags` plus `.user`-kind
  entries of `chipTags`; since favs is `.derived` it is already excluded — no change needed.

### 6. Edge cases

- **Favs + another tag selected** → union (favs OR the other tag), consistent with existing
  multi-select behavior.
- **`showOffline` / hidden channels** → favs filtering runs on the same working list as every
  other tag; offline/hidden channels are handled upstream unchanged. Note: the favs count
  reflects visible favorited channels (favorited-but-offline channels are excluded when
  `showOffline` is false, same as any tag count).
- **Removing a channel** already clears its favorite; the re-derivation covers the
  "last favorite removed" → chip disappears case.

### 7. Tests

- **`ChannelMergerTests`**: a channel with `isFavorite` state gets `"favs"` in `tagIDs`;
  a non-favorited channel does not; holds for both curated and user channels; no duplicate
  when re-merged.
- **`ChannelStoreTests`**: favs chip absent at 0 favorites; appears with count 1 after the
  first favorite; count tracks the favorite set; chip disappears and `favs` is removed from
  `selectedTagIDs` after the last unfavorite; favs sorts first in `chipTags`.
- **`TagFilterTests` / store**: selecting `favs` yields exactly the favorited channels.

## Non-goals (out of scope for this spec)

- Letting users apply their own tags to catalog channels.
- Editing existing channels (tags/title) in place.
- "Adopt a catalog channel."
- Any change to the favorites storage model or a data migration.

## Follow-ups (TODO backlog)

1. **Edit a channel in place** — a unified edit sheet to add/remove tags, change the title,
   etc., on an existing channel (curated or user). Rename already exists
   (`ChannelStore.renameChannel`); tag editing on existing channels is the gap.
2. **Adopt a catalog channel** — clone a curated channel into a `UserChannel` so it becomes
   fully user-owned and editable (tags via the existing user-channel path). Cross-cutting
   detail: favorites/other per-user state live in `ChannelUserState` keyed by `channelID`,
   so adopt must preserve the channel's id (or migrate its state) or favoriting-then-adopting
   would orphan the favorite. This feature also subsumes "tag catalog channels."
