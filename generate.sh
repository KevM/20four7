#!/bin/bash
set -euo pipefail

# Load environment variables (e.g. DEVELOPMENT_TEAM) from .env if it exists.
# `set -a` exports everything sourced; sourcing handles quotes/spaces correctly,
# unlike `export $(... | xargs)`.
if [ -f .env ]; then
    set -a
    . ./.env
    set +a
fi

# Generate the Xcode project from project.yml.
xcodegen generate
