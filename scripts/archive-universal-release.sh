#!/bin/sh

set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
ARCHIVE_PATH="$ROOT_DIR/build/Minimark.xcarchive"
APP_BINARY="$ARCHIVE_PATH/Products/Applications/MarkdownObserver.app/Contents/MacOS/MarkdownObserver"

cd "$ROOT_DIR"
rm -rf "$ARCHIVE_PATH"

xcodebuild \
  -project minimark.xcodeproj \
  -scheme minimark \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE_PATH" \
  archive

file "$APP_BINARY"