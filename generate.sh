#!/bin/bash

# Load environment variables from .env if it exists
if [ -f .env ]; then
    # Export all variables except comments
    export $(grep -v '^#' .env | xargs)
fi

# Run XcodeGen to generate the project
xcodegen generate
