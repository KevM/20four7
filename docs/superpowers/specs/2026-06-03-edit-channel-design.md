# Edit an Existing Channel — Design

**Date:** 2026-06-03
**Status:** Approved (pre-implementation)

## Problem

The app can **add** channels (via [`AddChannelView`](../../../Sources/UI/AddChannelView.swift))
and **remove** them, plus piecemeal context-menu actions (rename via a one-field
alert, mark Live/VOD, favorite). There is **no unified way to edit** an existing
channel, and notably **no way to change a channel's tags** after creation.

## Goals

Provide a single **Edit** surface, reachable from each channel tile, that lets the
user change:

- **Title**
- **Tags** (the current biggest gap)
- **Live/VOD status** (`isLiveExpected`)
- **Favorite** status

The YouTube URL / video ID is **not** editable — it defines channel identity.

## Core concept: Adoption

Editing always operates on a `UserChannel`.

- **User channels** are updated in place.
- **Curated channels** (from the remote catalog) are **adopted** into a user copy
  on first edit. Because [`ChannelMerger`](../../../Sources/Core/ChannelMerger.swift)
  dedupes by `youTubeVideoID` with the user copy winning, writing a `UserChannel`
  with the same video ID automatically hides the curated original. Only the
  adopted version is shown.

**Adoption rule:** saving the edit form on a curated channel **always adopts** it,
regardless of which field changed. This keeps the model uniform (no mix of
override + adoption).

### Trade-off (accepted)

Once adopted, a channel is **frozen** from future catalog updates — it won't pick
up a new title/thumbnail and won't be auto-removed if the catalog drops that
stream. This is inherent to the adoption model and is accepted; no mitigation.

## Data flow

```
ChannelTile menu ──"Edit…"──▶ EditChannelView (form)
                                     │ save()
                                     ▼
                            ChannelStore.editChannel(...)
                              ├─ source == .user  → LocalStore.updateUserChannel(...)   (in place, keeps dateAdded)
                              └─ source == .curated → LocalStore.adoptCuratedChannel(...)
                                                         • insert UserChannel (id "user-<vid>", edited fields)
                                                         • carry over playCount / lastPlayedDate / favorite
                                                         • delete orphaned ChannelUserState (old curated id)
                                     │
                                     ▼
                            store.reloadLineup()  → merge dedups by videoID, curated twin drops out
```

## Persistence layer (`LocalStore`)

- `updateUserChannel(id:title:youTubeVideoID:isLiveExpected:tagIDs:)` — fetch the
  `UserChannel` and update fields **in place** (preserves `dateAdded` so
  popularity ranking is stable). Replaces the narrow `updateUserChannelTitle`.
- `adoptCuratedChannel(_ edited:Channel, fromCuratedID:String)` — insert a new
  `UserChannel` (`id = "user-<videoID>"`) from the edited channel; then migrate
  state: read the old `ChannelUserState` for `fromCuratedID`, copy
  `playCount` / `lastPlayedDate` / `isFavorite` onto a fresh state row keyed by
  the new id, and **delete** the old curated state row.
- `setHidden` (exists) — reused when removing an adopted channel to hide the
  curated twin.

## Store layer (`ChannelStore`)

- `editChannel(_ original:Channel, title:tagIDs:isLiveExpected:isFavorite:)` —
  branch on `original.source`:
  - `.user` → `updateUserChannel` + apply favorite
  - `.curated` → `adoptCuratedChannel` + apply favorite

  Then `reloadLineup()`.
- `removeChannel(_:)` — extended: after deleting a `.user` channel, look up the
  catalog (via `remoteConfig`) for a curated channel sharing its
  `youTubeVideoID`; if found, `setHidden(curatedID, true)` so the twin can't
  silently reappear. Curated-source removal keeps today's `setHidden` behavior.
- `renameChannel` and the curated `setCustomTitle` path become **unused** (title
  now flows through the edit form) and are retired. `setLiveExpectedOverride`
  **stays** — the player's automatic live/VOD detection still uses it for
  not-yet-adopted curated channels. The merge still applies any legacy
  `customTitle` data harmlessly.

## UI layer

### `TagSelectorSection` (new, extracted, shared)

The tag-chips `FlowLayout` + "Add Custom Tag" row currently inline in
[`AddChannelView`](../../../Sources/UI/AddChannelView.swift) (lines ~102–144),
extracted into a reusable view taking a `Binding<Set<String>>` of selected tag
ids plus the available-tags list. Both Add and Edit render it. `AddChannelView`
shrinks to use it with no behavior change.

### `EditChannelView` (new)

A `Form` seeded from the channel being edited:

- **YouTube link** — read-only row (identity fixed).
- **Title** — pre-filled `TextField`.
- **Tags** — `TagSelectorSection`, pre-selected from `store.resolveTags(channel)`
  (which already drops `.derived` tags, so the `favs` tag never appears as an
  editable chip).
- **Status** — `Toggle` for Live/VOD, `Toggle` for Favorite.
- Toolbar **Save** → `store.editChannel(...)` then `dismiss`; **Cancel**
  discards. No URL validation, no embeddability check, no watch-now alert.
- Empty title falls back to "Untitled" (mirrors `makeUserChannel`).

### `ChannelTile`

Context menu becomes **Favorite · Edit… · Remove**. Drop `onRename` /
`onToggleLive` closures; add `onEdit`.

### `GuideView`

Replace the rename-alert state with edit-sheet presentation
(`@State channelToEdit: Channel?` + `.sheet(item:)` wrapping `EditChannelView`
in a `NavigationStack`). Wire `onEdit`; keep `onToggleFavorite` and `onRemove`.

## Edge cases & behavior rules

- **Favorite consistency:** the quick menu Favorite toggle and the form's
  Favorite toggle both write `ChannelUserState` under the channel's current id.
  On adoption, favorite migrates to the new id, so the paths never diverge.
- **Favorite-only edit still adopts** (cost of the uniform model).
- **Derived `favs` tag** is never an editable chip (seeded via `resolveTags`).
- **Custom tags** created in the form follow the existing add-flow behavior: a
  typed tag id is inserted into the selection and materializes as a `.user` tag
  on `reloadLineup`.
- **Removing an adopted channel** deletes the user copy *and* hides the curated
  twin (looked up by video ID). Pure user channels (no twin) are just deleted.

## Testing

- **`ChannelMerger`:** assert an adopted user copy hides the curated twin.
- **Adoption:** `adoptCuratedChannel` produces a `user-<vid>` channel with edited
  fields and carries over play history/favorite; touches `LocalStore`/SwiftData
  via an in-memory `ModelContainer`.
- **`removeChannel` twin-hiding:** adopt → remove → curated twin does not
  reappear.
- **`TagSelectorSection` extraction:** add flow still behaves (no regression).

## Out of scope

- Editing the YouTube URL / video ID.
- Reverting an adopted channel back to the catalog default.
- Keeping adopted channels in sync with future catalog updates.
