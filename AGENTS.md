# Repository Guidelines

## Project Structure & Module Organization
This repository contains a lightweight macOS menu bar app named Quotax. Swift source files live in `Sources/` and are compiled directly by `build.sh`, not through an Xcode project or Swift Package manifest. `Sources/main.swift` starts the AppKit app, `AppDelegate.swift` wires the status item and menus, `Views.swift` and `StatusBarView.swift` contain UI, `ZenmuxAPIService.swift` handles the Zenmux Management API, and `SettingsManager.swift` owns persisted settings. App metadata is in `Info.plist`, assets are in `Resources/`, and generated output goes to `build/`.

## Build, Test, and Development Commands
- `chmod +x build.sh`: Ensure the build script is executable.
- `./build.sh`: Compile `Sources/*.swift`, copy app metadata/assets, lint the packaged plist, ad-hoc sign the app, and produce `build/Quotax.app`.
- `ARCH=x86_64 ./build.sh` or `ARCH=arm64 ./build.sh`: Build for a specific macOS architecture.
- `xcrun swift-format lint --configuration .swift-format <file.swift>`: Check Swift formatting for a specific file; use this before submitting Swift changes.
- `swiftlint lint --config .swiftlint.yml <file.swift>`: Run SwiftLint for a specific file after installing SwiftLint, for example with `brew install swiftlint`.
- `open build/Quotax.app`: Launch the built menu bar app for manual verification.

There is currently no package manager command or automated test target.

## Coding Style & Naming Conventions
Follow the existing Swift style: four-space indentation, `PascalCase` for types, `camelCase` for properties and methods, and descriptive file names tied to one responsibility. Keep UI coordination on the main actor where appropriate; current app-level types use `@MainActor` and observable state. Preserve explicit access control (`public`, `private`) and prefer focused files over expanding unrelated classes.

Before submitting Swift changes, run `xcrun swift-format lint --configuration .swift-format` on changed files and review any diagnostics. Run SwiftLint with `.swiftlint.yml`; warnings are advisory during rollout, but error-level findings must be fixed before opening a pull request.

## Testing Guidelines
No XCTest suite is configured. For each change, run `./build.sh`, run the applicable `swift-format` and SwiftLint checks on changed Swift files, and manually launch `build/Quotax.app`. Verify the status bar item renders, settings open, API keys persist, refresh behavior works with and without a key, and errors remain user-readable. If tests are added later, place them under `Tests/` and document the command here.

## Commit & Pull Request Guidelines
Recent history uses Conventional Commits with optional scopes and emoji, such as `feat(statusbar): ✨ reduce width and add background styling` and `ci(release): 👷 add macOS release workflow`. Use concise imperative summaries.

Pull requests should describe the user-visible change, list build/manual verification steps, link related issues when applicable, and include screenshots or recordings for menu bar or settings UI changes.

## Release & Configuration Notes
`.github/workflows/release.yml` runs on tags such as `v1.2.3`. It updates bundle versions from the tag, builds x86_64 and arm64 artifacts, signs, notarizes, staples, and uploads zipped apps. Never commit API keys or Apple signing credentials; release signing depends on GitHub Actions secrets.
