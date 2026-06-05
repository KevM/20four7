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
grep -q 'MARKETING_VERSION: "1.0.2"' "$tmp/project.yml" || { echo "FAIL: MARKETING_VERSION was not updated to 1.0.2"; exit 1; }

# Second run must keep the quoted format and increment again (monotonic).
out2="$("$BUMP" "$tmp/project.yml")"
[[ "$out2" == "3" ]] || { echo "FAIL: expected 3 on second run, got '$out2'"; exit 1; }
grep -q 'CURRENT_PROJECT_VERSION: "3"' "$tmp/project.yml" || { echo "FAIL: build number not updated to 3"; exit 1; }
grep -q 'MARKETING_VERSION: "1.0.3"' "$tmp/project.yml" || { echo "FAIL: MARKETING_VERSION was not updated to 1.0.3"; exit 1; }

# Missing key must fail loudly (non-zero exit), not silently succeed.
printf 'settings:\n  base:\n    MARKETING_VERSION: "1.0.0"\n' > "$tmp/nokey.yml"
if "$BUMP" "$tmp/nokey.yml" >/dev/null 2>&1; then
  echo "FAIL: expected non-zero exit when CURRENT_PROJECT_VERSION is absent"; exit 1
fi

echo "PASS"
