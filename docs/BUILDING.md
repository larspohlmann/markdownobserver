# Building MarkdownObserver From Source

This document explains how to compile and test MarkdownObserver locally on macOS.

## Prerequisites

- macOS
- Xcode (latest stable recommended)
- Command line developer tools installed (`xcode-select --install`)

## 1. Get the Source

```bash
git clone https://github.com/larspohlmann/markdownobserver.git
cd markdownobserver
```

## 2. Resolve Swift Package Dependencies

```bash
xcodebuild -resolvePackageDependencies -project minimark.xcodeproj -scheme minimark
```

## 3. Build (No Signing Required)

Open-source defaults disable code signing for local builds and tests.

Choose one of the following build configurations:

- Release (recommended for most users who just want to run the app):

```bash
xcodebuild -project minimark.xcodeproj -scheme minimark -configuration Release -destination 'platform=macOS' build
```

- Debug (recommended for contributors who are actively developing or debugging):

```bash
xcodebuild -project minimark.xcodeproj -scheme minimark -configuration Debug -destination 'platform=macOS' build
```

## 4. Run Tests

```bash
xcodebuild test -project minimark.xcodeproj -scheme minimark -destination 'platform=macOS' -only-testing:minimarkTests
```

## Optional: Build and Test via VS Code Task

If you use VS Code in this repository, run the `verify:macOS` task.

## Optional: Enable Signing for Your Own Distribution Build

Local development and tests do not need signing. If you want to create signed distributable builds:

1. Copy `Config/Signing.local.example.xcconfig` to `Config/Signing.local.xcconfig`.
2. Set your `DEVELOPMENT_TEAM` and any optional bundle identifier overrides.
3. Build using your preferred archive/export flow.

## Troubleshooting

- If package resolution fails, run dependency resolution again and verify network access.
- If Xcode selection is wrong, run `sudo xcode-select -switch /Applications/Xcode.app`.
- If a previous build appears stale, clean first:

```bash
xcodebuild -project minimark.xcodeproj -scheme minimark -configuration Debug clean
```
