# MarkdownObserver

A native macOS Markdown reader focused on fast preview, practical workspace workflows, and reliable file/folder watching.

[![Download on the App Store](https://developer.apple.com/assets/elements/badges/download-on-the-app-store.svg)](https://apps.apple.com/app/id6760550501)

**Website:** [lars-pohlmann.de/markdownobserver](https://lars-pohlmann.de/markdownobserver/)

![MarkdownObserver](screenshots/screenshot_1.png)

[More screenshots](SCREENSHOTS.md)

## Install

- App Store: https://apps.apple.com/app/id6760550501
- Build from source: see [Building From Source](docs/BUILDING.md)

## Features

- Open and preview Markdown files in a native macOS app with syntax highlighting and rendered output.
- Show breadcrumb context and watch details in the top bar.
- Organize workspace files by subfolder with collapsible, pinnable sidebar groups.
- Sort sidebar groups and files independently to match your workflow.
- Save folder watches as favorites, then rename, reorder, edit, and reopen them quickly.
- Handle large watched folders with a file selection dialog when many files are available.
- Open multiple files at once and use window-local drag-and-drop routing.
- Track live document changes with gutter indicators and comparison highlighting.

## Requirements

- macOS
- Xcode (latest stable recommended)
- Command line developer tools installed (`xcode-select --install`)

## Quick Start (Source Build)

```bash
git clone https://github.com/larspohlmann/markdownobserver.git
cd markdownobserver
xcodebuild -resolvePackageDependencies -project minimark.xcodeproj -scheme minimark
xcodebuild -project minimark.xcodeproj -scheme minimark -configuration Debug -destination 'platform=macOS' build
```

Run tests:

```bash
xcodebuild test -project minimark.xcodeproj -scheme minimark -destination 'platform=macOS' -only-testing:minimarkTests
```

More details: [docs/BUILDING.md](docs/BUILDING.md)

## Project Layout

- `minimark/`: App source code (views, stores, services, models, support types)
- `minimarkTests/`: Unit and integration-style tests
- `minimarkUITests/`: UI tests
- `Config/`: Build and signing configuration
- `scripts/`: Utility scripts for release/export workflows

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for local setup, pull request flow, and quality checks.

## Security

See [SECURITY.md](SECURITY.md) for how to report vulnerabilities.

## Code of Conduct

See [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).

## Author

Lars Pohlmann

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE).

## Third-Party Notices

MarkdownObserver includes third-party components distributed under their respective licenses.
For full attributions and license links, see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
