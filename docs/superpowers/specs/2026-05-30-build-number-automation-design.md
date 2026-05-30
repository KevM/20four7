# Build Number Automation — Design

**Date:** 2026-05-30
**Status:** Approved (pending spec review)

## Problem

When the app eventually ships to TestFlight, every upload requires a unique,
strictly increasing `CFBundleVersion` (build number). We want that number to
increment automatically when a PR lands on `main`, so it is always ready and a
human never has to remember to bump it.

A secondary problem surfaced during design: the version source of truth is
currently split. `project.yml` declares build settings:

```yaml
MARKETING_VERSION: "1.0.0"
CURRENT_PROJECT_VERSION: "1"
```

but `Sources/Info.plist` hardcodes the same keys as literals:

```xml
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>CFBundleVersion</key><string>1</string>
```

Because an explicit Info.plist's literals win over the build settings, the
`project.yml` values are effectively ignored today. Automation needs exactly one
place to bump.

## Goals

- Build number (`CURRENT_PROJECT_VERSION`) auto-increments by 1 on every PR
  merge to `main`.
- `project.yml` is the single source of truth for both version numbers.
- Marketing version (`MARKETING_VERSION`, currently `1.0.0`) stays **manual** —
  bumped by hand when cutting a release.
- No infinite CI loops, no wasted CI runs from the bump commit.

## Non-Goals

- No TestFlight / App Store upload pipeline (none exists yet; out of scope).
- No marketing-version automation or PR-label-driven semantic versioning.
- No change to how tests run in `ci.yml`.

## Approach

Chosen: **increment-and-commit on PR merge.** A workflow fires when a PR merges
to `main`, increments the build number in `project.yml`, and commits the change
back to `main`. The number stays human-readable and version-controlled, and the
trigger matches the "when a PR is landed" intent exactly.

Rejected alternative — *derive build number at build time from
`git rev-list --count HEAD`*: avoids bot commits, but nothing runs at archive
time today (archives are manual in Xcode, no pipeline), and
`ENABLE_USER_SCRIPT_SANDBOXING: YES` blocks build-phase git access, forcing a
scheme-pre-action + generated-xcconfig setup that is far more machinery than the
current need justifies. Can replace approach A cleanly if/when a release
pipeline is added.

## Design

### 1. Fix the source-of-truth split

Edit `Sources/Info.plist` so the version keys reference build settings instead
of literals:

| Key                          | From    | To                          |
| ---------------------------- | ------- | --------------------------- |
| `CFBundleShortVersionString` | `1.0`   | `$(MARKETING_VERSION)`      |
| `CFBundleVersion`            | `1`     | `$(CURRENT_PROJECT_VERSION)`|

After this, `project.yml` is the only place versions are defined.

### 2. New workflow: `.github/workflows/bump-build.yml`

- **Trigger:** `pull_request` with `types: [closed]`, `branches: [main]`,
  guarded by `if: github.event.pull_request.merged == true` so a PR that is
  closed without merging does nothing.
- **Permissions:** `contents: write` (needed to push back to `main`).
- **Concurrency:** `group: bump-build`, `cancel-in-progress: false` so two PRs
  merging in quick succession serialize instead of racing to the same number.
  The queued run checks out fresh `main` after the first run pushes, so it reads
  the already-incremented value.
- **Steps:**
  1. `actions/checkout` on `main`.
  2. Read current `CURRENT_PROJECT_VERSION` from `project.yml`.
  3. Increment by 1.
  4. Write the new value back into `project.yml` (single-key edit; the value is
     a quoted integer, e.g. `CURRENT_PROJECT_VERSION: "2"`).
  5. Commit as `chore: bump build number to N [skip ci]`.
  6. Push to `main`.

### 3. Loop / churn prevention

- The bump commit is pushed with the built-in `GITHUB_TOKEN`. GitHub does not
  trigger new workflow runs from `GITHUB_TOKEN` pushes, so the bump cannot
  re-trigger itself, and it will not start a `ci.yml` push run.
- `[skip ci]` in the commit subject is belt-and-suspenders in case the repo is
  later reconfigured to allow such triggers.

### 4. No `ci.yml` change

`ci.yml` keeps running tests on PRs and pushes to `main`. It does not read the
build number, and the bump commit will not trigger it.

## Files Touched

- `Sources/Info.plist` — two literal values → build-setting references.
- `.github/workflows/bump-build.yml` — new workflow.
- (No change to `project.yml` in this repo; the workflow edits it at runtime on
  CI. The `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` keys already exist.)

## Testing / Verification

- After editing Info.plist, run `xcodegen generate` and build locally; confirm
  the app's `CFBundleVersion`/`CFBundleShortVersionString` resolve to the
  `project.yml` values (e.g. via the built `Info.plist` or an in-app display).
- Workflow correctness is validated by merging a test PR and confirming a single
  `chore: bump build number to N` commit lands on `main` with `N` incremented,
  and that it does not spawn further workflow runs.

## Risks / Notes

- Build number increments by exactly 1 per merged PR — clean and monotonic,
  which is all TestFlight requires.
- A direct (non-PR) push to `main` will not bump the number. That is acceptable
  given the team works through PRs; direct pushes are not the release path.
- If a future release pipeline is added, revisit whether to switch to the
  build-time-derivation approach (and add `fetch-depth: 0` to its checkout).
