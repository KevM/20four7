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
