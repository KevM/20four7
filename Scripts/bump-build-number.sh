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

# Preserve the `KEY: "N"` quoted format; only the integer changes. Anchored to
# the start of the line so commented or otherwise-prefixed occurrences are left
# alone. If multiple matching lines exist they are all updated together.
# We also update MARKETING_VERSION to keep it in sync: "1.0.{build_number}".
sed -i.bak -E \
  -e "s/^([[:space:]]*${KEY}: \")[0-9]+(\")/\1${next}\2/" \
  -e "s/^([[:space:]]*MARKETING_VERSION: \")[0-9]+\.[0-9]+\.[0-9]+(\")/\11.0.${next}\2/" \
  "$PROJECT_FILE"
rm -f "${PROJECT_FILE}.bak"

# The read path tolerates an unquoted value but the write path requires the
# quoted form; fail loudly rather than silently no-op if they disagree.
if ! grep -q "${KEY}: \"${next}\"" "$PROJECT_FILE"; then
  echo "error: failed to update ${KEY} to ${next} in ${PROJECT_FILE} (unexpected value format?)" >&2
  exit 1
fi

if ! grep -q "MARKETING_VERSION: \"1.0.${next}\"" "$PROJECT_FILE"; then
  echo "error: failed to update MARKETING_VERSION to 1.0.${next} in ${PROJECT_FILE} (unexpected value format?)" >&2
  exit 1
fi

echo "$next"
