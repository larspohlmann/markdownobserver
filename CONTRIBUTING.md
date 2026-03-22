# Contributing

Thanks for helping improve MarkdownObserver.

## Development Setup

1. Clone the repository.
2. Open `minimark.xcodeproj` in Xcode.
3. Build and run the `minimark` scheme on macOS.

## Validation Before Opening a PR

Run unit tests:

```bash
xcodebuild test -project minimark.xcodeproj -scheme minimark -destination 'platform=macOS' -only-testing:minimarkTests
```

## Pull Requests

- Keep changes focused and scoped.
- Add or update tests when behavior changes.
- Update docs when behavior, setup, or workflows change.
- Add a changelog entry when appropriate.

## Style and Architecture

- Keep business logic out of SwiftUI views when practical.
- Favor small, focused types and functions.
- Preserve public behavior unless the change explicitly requires it.
