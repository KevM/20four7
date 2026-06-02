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

