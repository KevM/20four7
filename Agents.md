# Agent Instructions

## Xcode Simulator Targets

When running unit tests or builds via command-line tools like `xcodebuild`, please note the following environment constraint:

- **iPhone 16 Simulator Target**: The default `iPhone 16` simulator profile might not be installed or available on this system. Targeting it directly will cause builds/tests to fail with exit code `70` (`Unable to find a device matching the provided destination specifier`).
- **Recommended Target**: Use `iPhone 17` (which aligns with the latest `26.5` iOS Simulator runtime on this machine), or list the available simulators via `xcodebuild -showdestinations` to select an installed device profile.

To run the project unit tests successfully:
```sh
xcodebuild test -scheme 20Four7 -destination 'platform=iOS Simulator,name=iPhone 17'
```

## Regenerating the Xcode Project

Whenever you modify `project.yml` or need to regenerate the Xcode project file:
- **Do not run `xcodegen generate` directly.**
- **Instead, run `./generate.sh`** to ensure local variables (such as `DEVELOPMENT_TEAM` and custom variables from `.env`) are correctly exported and applied to the generated project.

## Adaptive Layout — `LayoutMetrics`

All phone-vs-iPad sizing flows through a single type:
[`Sources/UI/LayoutMetrics.swift`](Sources/UI/LayoutMetrics.swift). Follow this
pattern for any new adaptive UI — do not scatter device/size checks across views.

**Use the horizontal size class, never the device idiom.** A view reads:

```swift
@Environment(\.horizontalSizeClass) private var hSizeClass
private var m: LayoutMetrics { LayoutMetrics(hSizeClass) }
```

`LayoutMetrics.wide` is `true` only for a **regular** horizontal size class (a
full-screen iPad) and `false` for **compact** width (iPhone, *and* an iPad in a
narrow Split View / Slide Over pane).

- **Do NOT** use `UIDevice.current.userInterfaceIdiom == .pad`. It misreports a
  narrow split-view pane as a full iPad, and it is not reactive — it never
  changes, so the layout will not adjust on resize or rotation. The app does not
  set `UIRequiresFullScreen`, so multitasking is live and this matters.
- **Add new values as computed properties on `LayoutMetrics`**, grouped by the
  feature that uses them. Keep this the single source of truth rather than
  inlining `wide ? a : b` ternaries in view bodies.
- **Prefer semantic fonts** (`.headline`, `.body`, `.title3`, …) so text honors
  Dynamic Type. Reserve fixed `.system(size:)` for glyphs in fixed-size chrome
  (e.g. media-control buttons, the close chevron).

