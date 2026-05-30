# Build Number Automation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Auto-increment the app's build number (`CURRENT_PROJECT_VERSION`) on every PR merge to `main`, with `project.yml` as the single source of truth for versions.

**Architecture:** A small, locally-testable bash script (`Scripts/bump-build-number.sh`) reads, increments, and rewrites `CURRENT_PROJECT_VERSION` in `project.yml`. A GitHub Actions workflow (`bump-build.yml`) runs that script when a PR merges to `main` and commits the result back. Separately, `Sources/Info.plist` is rewired so its version keys reference the build settings instead of hardcoded literals, making `project.yml` authoritative.

**Tech Stack:** Bash, GitHub Actions, XcodeGen, Xcode/Swift (iOS).

---

## File Structure

- `Scripts/bump-build-number.sh` (new) — pure logic: read → increment → write `CURRENT_PROJECT_VERSION`. Prints the new value. Testable in isolation.
- `Tests/Scripts/test-bump-build-number.sh` (new) — self-contained assertions against a temp `project.yml` fixture.
- `.github/workflows/bump-build.yml` (new) — thin workflow that invokes the script on PR merge and pushes the commit.
- `Sources/Info.plist` (modify) — version keys → build-setting references.
- `.gitignore` / `project.yml` — no changes needed.

---

## Task 1: Build-number bump script (TDD)

**Files:**
- Create: `Scripts/bump-build-number.sh`
- Test: `Tests/Scripts/test-bump-build-number.sh`

- [ ] **Step 1: Write the failing test**

Create `Tests/Scripts/test-bump-build-number.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUMP="$SCRIPT_DIR/../../Scripts/bump-build-number.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

cat > "$tmp/project.yml" <<'EOF'
settings:
  base:
    CURRENT_PROJECT_VERSION: "1"
    MARKETING_VERSION: "1.0.0"
EOF

out="$("$BUMP" "$tmp/project.yml")"
[[ "$out" == "2" ]] || { echo "FAIL: expected printed 2, got '$out'"; exit 1; }
grep -q 'CURRENT_PROJECT_VERSION: "2"' "$tmp/project.yml" || { echo "FAIL: build number not updated to 2"; exit 1; }
grep -q 'MARKETING_VERSION: "1.0.0"' "$tmp/project.yml" || { echo "FAIL: MARKETING_VERSION was altered"; exit 1; }

# Second run must keep the quoted format and increment again (monotonic).
out2="$("$BUMP" "$tmp/project.yml")"
[[ "$out2" == "3" ]] || { echo "FAIL: expected 3 on second run, got '$out2'"; exit 1; }

echo "PASS"
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
chmod +x Tests/Scripts/test-bump-build-number.sh
./Tests/Scripts/test-bump-build-number.sh
```

Expected: fails (script does not exist yet) — error like `No such file or directory` for `Scripts/bump-build-number.sh`.

- [ ] **Step 3: Write the minimal script**

Create `Scripts/bump-build-number.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

PROJECT_FILE="${1:-project.yml}"
KEY="CURRENT_PROJECT_VERSION"

current="$(grep -E "^[[:space:]]*${KEY}:" "$PROJECT_FILE" | grep -oE '[0-9]+' | head -1)"
if [[ -z "${current:-}" ]]; then
  echo "error: ${KEY} not found in ${PROJECT_FILE}" >&2
  exit 1
fi

next="$((current + 1))"

# Preserve the `KEY: "N"` quoted format; only the integer changes.
sed -i.bak -E "s/(${KEY}: \")[0-9]+(\")/\1${next}\2/" "$PROJECT_FILE"
rm -f "${PROJECT_FILE}.bak"

echo "$next"
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
chmod +x Scripts/bump-build-number.sh
./Tests/Scripts/test-bump-build-number.sh
```

Expected: `PASS`.

- [ ] **Step 5: Sanity-check against the real project.yml (no mutation)**

```bash
cp project.yml /tmp/project.yml.check
./Scripts/bump-build-number.sh /tmp/project.yml.check
grep CURRENT_PROJECT_VERSION /tmp/project.yml.check
```

Expected: prints `2`, and the line reads `    CURRENT_PROJECT_VERSION: "2"`. (This touches only the temp copy; the repo's `project.yml` is unchanged.)

- [ ] **Step 6: Commit**

```bash
git add Scripts/bump-build-number.sh Tests/Scripts/test-bump-build-number.sh
git commit -m "feat: add build-number bump script with test"
```

---

## Task 2: PR-merge bump workflow

**Files:**
- Create: `.github/workflows/bump-build.yml`

- [ ] **Step 1: Write the workflow**

Create `.github/workflows/bump-build.yml`:

```yaml
name: Bump Build Number

on:
  pull_request:
    types: [closed]
    branches: [main]

concurrency:
  group: bump-build
  cancel-in-progress: false

jobs:
  bump:
    if: github.event.pull_request.merged == true
    name: Increment build number
    runs-on: ubuntu-latest
    permissions:
      contents: write
    steps:
      - name: Checkout main
        uses: actions/checkout@v6
        with:
          ref: main

      - name: Bump build number
        id: bump
        run: |
          new="$(./Scripts/bump-build-number.sh project.yml)"
          echo "version=$new" >> "$GITHUB_OUTPUT"

      - name: Commit and push
        run: |
          git config user.name "github-actions[bot]"
          git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
          git add project.yml
          git commit -m "chore: bump build number to ${{ steps.bump.outputs.version }} [skip ci]"
          git push
```

- [ ] **Step 2: Validate the workflow YAML locally**

```bash
python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/bump-build.yml')); print('YAML OK')"
```

Expected: `YAML OK`.

- [ ] **Step 3: Confirm the script is executable in git**

```bash
git ls-files -s Scripts/bump-build-number.sh
```

Expected: mode starts with `100755` (executable bit set, so the workflow can run `./Scripts/...`). If it shows `100644`, run `git update-index --chmod=+x Scripts/bump-build-number.sh`.

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/bump-build.yml
git commit -m "ci: auto-increment build number on PR merge to main"
```

---

## Task 3: Make project.yml the source of truth for Info.plist

**Files:**
- Modify: `Sources/Info.plist:18` and `Sources/Info.plist:20`

- [ ] **Step 1: Rewire CFBundleShortVersionString**

In `Sources/Info.plist`, change the value under `CFBundleShortVersionString` from the literal to a build-setting reference:

```xml
		<key>CFBundleShortVersionString</key>
		<string>$(MARKETING_VERSION)</string>
```

- [ ] **Step 2: Rewire CFBundleVersion**

In `Sources/Info.plist`, change the value under `CFBundleVersion`:

```xml
		<key>CFBundleVersion</key>
		<string>$(CURRENT_PROJECT_VERSION)</string>
```

- [ ] **Step 3: Regenerate the Xcode project**

```bash
xcodegen generate
```

Expected: completes without error (`Created project at .../20Four7.xcodeproj`).

- [ ] **Step 4: Verify the values resolve from build settings**

```bash
xcodebuild -scheme 20Four7 -showBuildSettings -destination 'platform=iOS Simulator,name=iPhone 16' 2>/dev/null | grep -E 'MARKETING_VERSION|CURRENT_PROJECT_VERSION'
```

Expected: shows `MARKETING_VERSION = 1.0.0` and `CURRENT_PROJECT_VERSION = 1` — confirming the plist now sources these from `project.yml`. (A full build, if run, will stamp `CFBundleVersion = 1` / `CFBundleShortVersionString = 1.0.0` into the bundle.)

- [ ] **Step 5: Commit**

```bash
git add Sources/Info.plist
git commit -m "fix: source bundle version keys from project.yml build settings"
```

---

## Verification (whole feature)

- [ ] `./Tests/Scripts/test-bump-build-number.sh` prints `PASS`.
- [ ] `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/bump-build.yml'))"` succeeds.
- [ ] `xcodegen generate` succeeds after the Info.plist change.
- [ ] `xcodebuild ... -showBuildSettings | grep VERSION` shows the values coming from `project.yml`.
- [ ] End-to-end (post-merge, on GitHub): merging a test PR into `main` produces exactly one `chore: bump build number to N` commit with `N` incremented, and that commit spawns no further workflow runs (it is pushed with `GITHUB_TOKEN` and tagged `[skip ci]`).

## Notes

- The bump workflow runs on `ubuntu-latest` (no Xcode needed — it only edits text), keeping it fast and cheap.
- `concurrency: bump-build` with `cancel-in-progress: false` serializes near-simultaneous merges so they don't race to the same number; the queued run checks out fresh `main` after the first pushes.
- `MARKETING_VERSION` stays manual — bump it by hand in `project.yml` when cutting a release.
