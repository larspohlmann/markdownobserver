#!/bin/sh

set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
ARCHIVE_PATH="$ROOT_DIR/build/Minimark.xcarchive"
EXPORT_PATH="$ROOT_DIR/build/exported"
EXPORT_OPTIONS_PLIST="$ROOT_DIR/build/ExportOptions-DeveloperID.plist"
RELEASE_ENV_FILE="$ROOT_DIR/.env.release"

if [ -f "$RELEASE_ENV_FILE" ]; then
  # Optional local release values (for example APPLE_TEAM_ID) live outside version control.
  set -a
  # shellcheck disable=SC1090
  . "$RELEASE_ENV_FILE"
  set +a
fi

APPLE_TEAM_ID_VALUE="${APPLE_TEAM_ID:-}"

if ! security find-identity -v -p codesigning | grep -q 'Developer ID Application:'; then
  echo "No Developer ID Application certificate found in the keychain."
  echo "Install a Developer ID Application certificate first, then rerun this script."
  exit 1
fi

mkdir -p "$ROOT_DIR/build"

cat > "$EXPORT_OPTIONS_PLIST" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>developer-id</string>
  <key>signingStyle</key>
  <string>automatic</string>
</dict>
</plist>
PLIST

if [ -n "$APPLE_TEAM_ID_VALUE" ]; then
  /usr/bin/plutil -replace teamID -string "$APPLE_TEAM_ID_VALUE" "$EXPORT_OPTIONS_PLIST"
fi

"$ROOT_DIR/scripts/archive-universal-release.sh"
rm -rf "$EXPORT_PATH"

xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS_PLIST"

codesign --verify --deep --strict --verbose=2 "$EXPORT_PATH/MarkdownObserver.app"
spctl --assess --type execute --verbose=4 "$EXPORT_PATH/MarkdownObserver.app"

echo "Exported app: $EXPORT_PATH/MarkdownObserver.app"