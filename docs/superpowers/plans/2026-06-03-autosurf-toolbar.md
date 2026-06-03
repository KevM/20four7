# Auto-Surf in the Toolbar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move Auto-Surf into the top-right toolbar as an icon-only button that appears only when a tag filter yields channels, and remove the playlist-copy toolbar button while preserving its code in a new unreferenced component.

**Architecture:** Three SwiftUI files. `GuideView` loses the inline pill button and its `onAutoSurf` parameter. `RootView` gains an Auto-Surf `ToolbarItem` (reusing its existing `startAutoSurfing` path) and loses the playlist `ToolbarItem`, its `copiedPlaylist` state, and the toast overlay. A new `PlaylistCopyButton.swift` holds the extracted, unreferenced playlist button plus the original toast preserved as a comment.

**Tech Stack:** Swift, SwiftUI, XcodeGen. No XCTest coverage for this layout change — verification is a clean build for the `iPhone 17` simulator (per `CLAUDE.md`) plus manual inspection.

---

### Task 1: Extract the playlist button into an unreferenced component

**Files:**
- Create: `Sources/UI/PlaylistCopyButton.swift`

This task only adds a new, unreferenced file. It cannot break the build on its own and sets up the removal in Task 3.

- [ ] **Step 1: Create the component file**

Create `Sources/UI/PlaylistCopyButton.swift` with the following exact contents. The button logic is lifted verbatim from `RootView`; the screen-level toast (which a toolbar button cannot own) is preserved as a comment with re-wiring instructions.

```swift
import SwiftUI

/// Copies the current filtered YouTube playlist URL to the clipboard, swapping
/// to a green checkmark for 1.5s as confirmation. Disabled when there is no
/// filtered playlist URL available.
///
/// Currently unreferenced. To restore it, drop it into the trailing toolbar:
///
///     ToolbarItem(placement: .topBarTrailing) {
///         PlaylistCopyButton(store: store)
///     }
///
/// The original design also showed a screen-level top toast. A toolbar button
/// cannot own a screen-level overlay, so re-wire it at the `RootView` level by
/// hoisting the `copiedPlaylist` flag up (e.g. via a binding) and re-adding:
///
///     .overlay(alignment: .top) {
///         if copiedPlaylist {
///             Text("Playlist URL copied to clipboard!")
///                 .font(.subheadline)
///                 .fontWeight(.medium)
///                 .foregroundColor(.white)
///                 .padding(.vertical, 8)
///                 .padding(.horizontal, 16)
///                 .background(Color.blue.opacity(0.9))
///                 .cornerRadius(20)
///                 .transition(.move(edge: .top).combined(with: .opacity))
///                 .padding(.top, 12)
///         }
///     }
struct PlaylistCopyButton: View {
    @ObservedObject var store: ChannelStore
    @State private var copiedPlaylist = false

    var body: some View {
        Button {
            if let url = store.filteredPlaylistURL {
                UIPasteboard.general.string = url.absoluteString
                withAnimation {
                    copiedPlaylist = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    withAnimation {
                        copiedPlaylist = false
                    }
                }
            }
        } label: {
            if copiedPlaylist {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            } else {
                Image(systemName: "play.rectangle.on.rectangle")
            }
        }
        .disabled(store.filteredPlaylistURL == nil)
    }
}
```

- [ ] **Step 2: Regenerate the Xcode project so the new file is included**

Run: `./generate.sh`
Expected: completes without error; `PlaylistCopyButton.swift` is now part of the project sources. Sources are directory-globbed (`project.yml` `sources: - path: Sources`) and the `.xcodeproj` is gitignored, so this regenerates the local project but changes no tracked files.

- [ ] **Step 3: Build to verify the new file compiles**

Run: `xcodebuild build -scheme 20Four7 -destination 'platform=iOS Simulator,name=iPhone 17'`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Commit**

```bash
git add Sources/UI/PlaylistCopyButton.swift
git commit -m "refactor: extract PlaylistCopyButton component (unreferenced)"
```

---

### Task 2: Remove the inline Auto-Surf pill from GuideView

**Files:**
- Modify: `Sources/UI/GuideView.swift`

- [ ] **Step 1: Remove the `onAutoSurf` stored property**

In `Sources/UI/GuideView.swift`, delete this line (currently line 6):

```swift
    let onAutoSurf: () -> Void
```

- [ ] **Step 2: Collapse the chip row to just the TagChipBar**

Replace the entire chip-row block (currently lines 22-57) — the comment, the `HStack`, and the Auto-Surf `Button` — with this:

```swift
                // While filtering: active-filter chips (tap to remove). The
                // Filter entry point and Auto-Surf both live in the toolbar
                // (RootView).
                if !store.selectedTagIDs.isEmpty {
                    TagChipBar(
                        tags: store.chipTags,
                        selected: store.selectedTagIDs,
                        counts: store.tagChannelCounts,
                        onToggle: { id in
                            withAnimation {
                                store.toggleTag(id)
                            }
                        }
                    )
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
```

This drops the `HStack`, the `if !store.filteredChannels.isEmpty { Button … }`, and the `.padding(.trailing, m.chipRowHPadding)` that only the button used. The `m` metrics property is still used by `columns`/grid padding, so leave it.

- [ ] **Step 3: Build to verify it compiles**

Run: `xcodebuild build -scheme 20Four7 -destination 'platform=iOS Simulator,name=iPhone 17'`
Expected: FAIL — `RootView.swift` still passes `onAutoSurf:` to `GuideView`, which no longer accepts it. This confirms the parameter was actually removed; Task 3 fixes the call site.

- [ ] **Step 4: Do not commit yet**

This task leaves the build red by design (the `GuideView` initializer changed). Proceed directly to Task 3, which updates the `RootView` call site, and commit the two together.

---

### Task 3: Add the Auto-Surf toolbar button and remove the playlist button in RootView

**Files:**
- Modify: `Sources/UI/RootView.swift`

- [ ] **Step 1: Drop the `onAutoSurf:` argument from the GuideView call**

In `Sources/UI/RootView.swift`, replace the `GuideView(...)` call (currently lines 21-27):

```swift
            GuideView(store: store, onSelect: { channel in
                startPlaying(channel)
            }, onAutoSurf: {
                if let firstChannel = store.filteredChannels.first {
                    startAutoSurfing(firstChannel)
                }
            })
```

with:

```swift
            GuideView(store: store, onSelect: { channel in
                startPlaying(channel)
            })
```

- [ ] **Step 2: Replace the playlist ToolbarItem with the Auto-Surf ToolbarItem**

Replace the playlist `ToolbarItem` block (currently lines 44-66, beginning `ToolbarItem(placement: .topBarTrailing) {` with the `if let url = store.filteredPlaylistURL` body and ending at its closing `}`) with this Auto-Surf item:

```swift
                if !store.selectedTagIDs.isEmpty && !store.filteredChannels.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            if let firstChannel = store.filteredChannels.first {
                                startAutoSurfing(firstChannel)
                            }
                        } label: {
                            Image(systemName: "play.circle.fill")
                        }
                        .tint(.red)
                        .accessibilityLabel("Auto-Surf")
                    }
                }
```

The resulting trailing toolbar order is Filter → Auto-Surf → `+`.

- [ ] **Step 3: Remove the `copiedPlaylist` state**

Delete this line (currently line 8):

```swift
    @State private var copiedPlaylist = false
```

- [ ] **Step 4: Remove the toast overlay**

Delete the `.overlay(alignment: .top) { … }` block (currently lines 105-118):

```swift
        .overlay(alignment: .top) {
            if copiedPlaylist {
                Text("Playlist URL copied to clipboard!")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 16)
                    .background(Color.blue.opacity(0.9))
                    .cornerRadius(20)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.top, 12)
            }
        }
```

- [ ] **Step 5: Build to verify the whole thing compiles**

Run: `xcodebuild build -scheme 20Four7 -destination 'platform=iOS Simulator,name=iPhone 17'`
Expected: `BUILD SUCCEEDED`. No remaining references to `copiedPlaylist` or `onAutoSurf`.

- [ ] **Step 6: Commit Tasks 2 and 3 together**

```bash
git add Sources/UI/GuideView.swift Sources/UI/RootView.swift
git commit -m "feat: move auto-surf into the toolbar, remove playlist button"
```

---

### Task 4: Manual verification

**Files:** none.

- [ ] **Step 1: Launch the app in the iPhone 17 simulator**

Run the app (via Xcode or `xcodebuild` + simctl). Confirm each of the following:

- [ ] **Step 2: No tags selected** — the trailing toolbar shows only Filter and `+`; no Auto-Surf button is present.
- [ ] **Step 3: Select a tag that matches channels** — a red `play.circle.fill` Auto-Surf button appears between Filter and `+`. Tapping it starts Auto-Surf on the first filtered channel.
- [ ] **Step 4: Select a tag whose filter yields zero channels** — the Auto-Surf button stays hidden.
- [ ] **Step 5: Confirm removals** — there is no `play.rectangle.on.rectangle` playlist button in the toolbar and no "Playlist URL copied to clipboard!" toast anywhere.
- [ ] **Step 6: Confirm the Guide body** — the old red "Auto-Surf" pill no longer appears next to the filter chips; only the chips remain in that row.

---

## Notes

- Line numbers reference the files as of this plan's writing; if they have drifted, match on the quoted code instead.
- `./generate.sh` is required after adding the new file — do **not** run `xcodegen generate` directly (per `CLAUDE.md`).
