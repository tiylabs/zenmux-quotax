# Repository Guidelines

## Project Structure & Module Organization
This repository contains a lightweight macOS menu bar app named Quotax. Swift source files live under `Sources/` and are compiled directly by `scripts/build.sh`, not through an Xcode project or Swift Package manifest. `Sources/main.swift` starts the AppKit app, `Sources/Core/` contains constants, logging, and resource helpers, `Sources/Services/` contains API, settings, launch-at-login, and model code, and `Sources/UI/` contains AppKit/SwiftUI views and UI coordination. App metadata is in `Info.plist`, assets are in `Resources/`, helper scripts live in `scripts/`, and generated output goes to `build/`.

## Build, Test, and Development Commands
- `chmod +x scripts/build.sh`: Ensure the build script is executable.
- `./scripts/build.sh`: Recursively compile Swift files under `Sources/`, copy app metadata/assets, lint the packaged plist, ad-hoc sign the app, and produce `build/Quotax.app`.
- `ARCH=x86_64 ./scripts/build.sh` or `ARCH=arm64 ./scripts/build.sh`: Build for a specific macOS architecture.
- `xcrun swift-format lint --configuration .swift-format <file.swift>`: Check Swift formatting for a specific file; use this before submitting Swift changes.
- `swiftlint lint --config .swiftlint.yml <file.swift>`: Run SwiftLint for a specific file after installing SwiftLint, for example with `brew install swiftlint`.
- `open build/Quotax.app`: Launch the built menu bar app for manual verification.

There is currently no package manager command or automated test target.

## Debugging & Logs
Quotax uses macOS Unified Logging via `OSLog` and does not write custom log files. The subsystem is `com.zenmux.quotax`; categories are defined in `Sources/Core/AppLog.swift` and currently include `lifecycle`, `network`, `refresh`, `decode`, and `settings`.

Use `log stream --predicate 'subsystem == "com.zenmux.quotax"' --info --debug` to watch live logs while reproducing an issue. Use `log show --predicate 'subsystem == "com.zenmux.quotax"' --last 1h` to inspect historical logs, and add `&& category == "network"` to focus on API traffic. `URLError.cancelled` / `-999 cancelled` is normally a cancellation signal from a superseded refresh or shutdown path and should not be treated as fatal unless followed by crash or termination logs.

## Coding Style & Naming Conventions
Follow the existing Swift style: four-space indentation, `PascalCase` for types, `camelCase` for properties and methods, and descriptive file names tied to one responsibility. Keep UI coordination on the main actor where appropriate; current app-level types use `@MainActor` and observable state. Preserve explicit access control (`public`, `private`) and prefer focused files over expanding unrelated classes.

Before submitting Swift changes, run `xcrun swift-format lint --configuration .swift-format` on changed files and review any diagnostics. Run SwiftLint with `.swiftlint.yml`; warnings are advisory during rollout, but error-level findings must be fixed before opening a pull request.

## Testing Guidelines
No XCTest suite is configured. For each change, run `./scripts/build.sh`, run the applicable `swift-format` and SwiftLint checks on changed Swift files, and manually launch `build/Quotax.app`. Verify the status bar item renders, settings open, API keys persist, refresh behavior works with and without a key, and errors remain user-readable. If tests are added later, place them under `Tests/` and document the command here.

## Commit & Pull Request Guidelines
Recent history uses Conventional Commits with optional scopes and emoji, such as `feat(statusbar): ✨ reduce width and add background styling` and `ci(release): 👷 add macOS release workflow`. Use concise imperative summaries.

Pull requests should describe the user-visible change, list build/manual verification steps, link related issues when applicable, and include screenshots or recordings for menu bar or settings UI changes.

## Release & Configuration Notes
`.github/workflows/release.yml` runs on tags such as `v1.2.3`. It updates bundle versions from the tag, builds x86_64 and arm64 artifacts, signs, notarizes, staples, and uploads zipped apps. Never commit API keys or Apple signing credentials; release signing depends on GitHub Actions secrets.
