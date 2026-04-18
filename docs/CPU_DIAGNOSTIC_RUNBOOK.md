# MarkdownObserver CPU Diagnostic Runbook

This runbook describes a fully repeatable CPU diagnostic for folder-watch behavior on macOS.

It is designed for fresh sessions and does not depend on previous traces.

## Goal

Capture a new Time Profiler trace for a known watch-folder scenario, then export machine-readable artifacts for analysis.

## Prerequisites

- macOS with Xcode command line tools
- Repository checked out locally
- Ability to run xcodebuild and xcrun xctrace

## One-Command Entry Point

Use the wrapper script for repeatable runs in new sessions.

```bash
bash scripts/run-cpu-diagnostic.sh
```

Useful variants:

```bash
# Attach mode, guarantees local launched binary is profiled
bash scripts/run-cpu-diagnostic.sh --strict

# Custom folder path and time limit
bash scripts/run-cpu-diagnostic.sh --watch-path /path/to/watch-folder --time-limit 60s

# Use current repository folder as watch path
bash scripts/run-cpu-diagnostic.sh --watch-path "$PWD" --time-limit 60s

# Skip build if you already built and want a faster rerun
bash scripts/run-cpu-diagnostic.sh --skip-build
```

Script options reference:

```bash
bash scripts/run-cpu-diagnostic.sh --help
```

## Standard Diagnostic (Fast Path)

Run these commands from repository root.

```bash
set -euo pipefail

TS="$(date +%Y%m%d-%H%M%S)"
WATCH_PATH="/path/to/watch-folder"

xcodebuild -project minimark.xcodeproj -scheme minimark -configuration Debug -destination 'platform=macOS' build

APP_PATH="$(find ~/Library/Developer/Xcode/DerivedData -type d -path '*/Build/Products/Debug/MarkdownObserver.app' | head -n 1)/Contents/MacOS/MarkdownObserver"

mkdir -p profiling

export MINIMARK_UI_TEST_WATCH_FOLDER_PATH="$WATCH_PATH"

xcrun xctrace record \
  --template 'Time Profiler' \
  --output "profiling/time-profiler-watch-eigenes-diagnostic-${TS}.trace" \
  --time-limit 40s \
  --launch -- "$APP_PATH" \
  -minimark-ui-test \
  -minimark-auto-start-watch-folder

xcrun xctrace export \
  --input "profiling/time-profiler-watch-eigenes-diagnostic-${TS}.trace" \
  --toc > "profiling/time-profiler-watch-eigenes-diagnostic-${TS}.toc.xml"

xcrun xctrace export \
  --input "profiling/time-profiler-watch-eigenes-diagnostic-${TS}.trace" \
  --xpath '/trace-toc/run[@number="1"]/data/table[@schema="time-profile"]' \
  > "profiling/watch-eigenes-diagnostic-time-profile-${TS}.xml"

xcrun xctrace export \
  --input "profiling/time-profiler-watch-eigenes-diagnostic-${TS}.trace" \
  --xpath '/trace-toc/run[@number="1"]/data/table[@schema="os-signpost"]' \
  > "profiling/watch-eigenes-diagnostic-signposts-${TS}.xml"

echo "Diagnostic capture completed with timestamp: ${TS}"
```

## Strict Diagnostic (Guaranteed Latest Local Build)

Use this if you want to ensure the profiled process is the exact local Debug build path.

```bash
set -euo pipefail

TS="$(date +%Y%m%d-%H%M%S)"
WATCH_PATH="/path/to/watch-folder"

xcodebuild -project minimark.xcodeproj -scheme minimark -configuration Debug -destination 'platform=macOS' build

APP_PATH="$(find ~/Library/Developer/Xcode/DerivedData -type d -path '*/Build/Products/Debug/MarkdownObserver.app' | head -n 1)/Contents/MacOS/MarkdownObserver"

mkdir -p profiling

export MINIMARK_UI_TEST_WATCH_FOLDER_PATH="$WATCH_PATH"
"$APP_PATH" -minimark-ui-test -minimark-auto-start-watch-folder >/tmp/markdownobserver-diagnostic.log 2>&1 &
APP_PID=$!

sleep 3

xcrun xctrace record \
  --template 'Time Profiler' \
  --output "profiling/time-profiler-watch-eigenes-diagnostic-${TS}.trace" \
  --time-limit 40s \
  --attach "$APP_PID"

osascript -e 'tell application "MarkdownObserver" to quit' || true

xcrun xctrace export \
  --input "profiling/time-profiler-watch-eigenes-diagnostic-${TS}.trace" \
  --toc > "profiling/time-profiler-watch-eigenes-diagnostic-${TS}.toc.xml"

xcrun xctrace export \
  --input "profiling/time-profiler-watch-eigenes-diagnostic-${TS}.trace" \
  --xpath '/trace-toc/run[@number="1"]/data/table[@schema="time-profile"]' \
  > "profiling/watch-eigenes-diagnostic-time-profile-${TS}.xml"

xcrun xctrace export \
  --input "profiling/time-profiler-watch-eigenes-diagnostic-${TS}.trace" \
  --xpath '/trace-toc/run[@number="1"]/data/table[@schema="os-signpost"]' \
  > "profiling/watch-eigenes-diagnostic-signposts-${TS}.xml"

echo "Strict diagnostic capture completed with timestamp: ${TS}"
```

## Sanity Checks

1. Confirm trace metadata and launch arguments:

```bash
rg -n "process arguments|start-date|end-date|duration|end-reason|time-limit|path=" profiling/time-profiler-watch-eigenes-diagnostic-<TIMESTAMP>.toc.xml
```

2. Confirm exported artifact sizes are non-trivial:

```bash
wc -c profiling/time-profiler-watch-eigenes-diagnostic-<TIMESTAMP>.toc.xml
wc -c profiling/watch-eigenes-diagnostic-time-profile-<TIMESTAMP>.xml
wc -c profiling/watch-eigenes-diagnostic-signposts-<TIMESTAMP>.xml
```

3. Quick hotspot grep examples:

```bash
rg -n "FolderChangeWatcher.verifyChanges|FolderChangeWatcher.enumerateMarkdownFiles|AppKitMainMenuItem.menuNeedsUpdate|RecentHistory.menuTitle|CFPrefsSearchListSource" profiling/watch-eigenes-diagnostic-time-profile-<TIMESTAMP>.xml | head -n 200
```

## Output Artifacts

Each run produces these files under profiling.

- time-profiler-watch-eigenes-diagnostic-<TIMESTAMP>.trace
- time-profiler-watch-eigenes-diagnostic-<TIMESTAMP>.toc.xml
- watch-eigenes-diagnostic-time-profile-<TIMESTAMP>.xml
- watch-eigenes-diagnostic-signposts-<TIMESTAMP>.xml

## Notes

- xctrace may end with non-zero exit code after time-limit completion; treat this as expected if output files were written.
- If the TOC process path shows /Applications/MarkdownObserver.app in launch mode, use Strict Diagnostic mode to guarantee profiling the local Debug binary path.
