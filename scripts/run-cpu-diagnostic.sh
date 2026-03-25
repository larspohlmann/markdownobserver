#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/run-cpu-diagnostic.sh [options]

Runs a fresh MarkdownObserver CPU diagnostic and exports trace artifacts.

Options:
  --watch-path PATH     Folder to watch during diagnostic
                        Default: current working directory
  --time-limit DURATION Time limit passed to xctrace (for example: 40s)
                        Default: 40s
  --strict              Use attach mode to guarantee profiling of launched local binary
  --skip-build          Skip xcodebuild step
  --app-path PATH       Explicit app executable path to profile
  --timestamp VALUE     Override timestamp suffix used in artifact names
  --help                Show this help

Outputs:
  profiling/time-profiler-watch-eigenes-diagnostic-<timestamp>.trace
  profiling/time-profiler-watch-eigenes-diagnostic-<timestamp>.toc.xml
  profiling/watch-eigenes-diagnostic-time-profile-<timestamp>.xml
  profiling/watch-eigenes-diagnostic-signposts-<timestamp>.xml
EOF
}

WATCH_PATH="$PWD"
TIME_LIMIT="40s"
STRICT_MODE=0
SKIP_BUILD=0
APP_PATH=""
TIMESTAMP=""
APP_PID=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --watch-path)
      WATCH_PATH="${2:-}"
      shift 2
      ;;
    --time-limit)
      TIME_LIMIT="${2:-}"
      shift 2
      ;;
    --strict)
      STRICT_MODE=1
      shift
      ;;
    --skip-build)
      SKIP_BUILD=1
      shift
      ;;
    --app-path)
      APP_PATH="${2:-}"
      shift 2
      ;;
    --timestamp)
      TIMESTAMP="${2:-}"
      shift 2
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 2
      ;;
  esac
done

if [[ -z "$TIMESTAMP" ]]; then
  TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
fi

if [[ ! -d "minimark.xcodeproj" && ! -f "minimark.xcodeproj/project.pbxproj" ]]; then
  echo "Run this script from repository root." >&2
  exit 2
fi

if [[ ! -d "$WATCH_PATH" ]]; then
  echo "Watch path does not exist: $WATCH_PATH" >&2
  exit 2
fi

if [[ "$SKIP_BUILD" -eq 0 ]]; then
  xcodebuild -project minimark.xcodeproj -scheme minimark -configuration Debug -destination 'platform=macOS' build
fi

resolve_default_app_path() {
  local app_candidates=()
  local candidate
  while IFS= read -r candidate; do
    app_candidates+=("$candidate")
  done < <(
    find "$HOME/Library/Developer/Xcode/DerivedData" \
      -type f \
      -path '*/Build/Products/Debug/MarkdownObserver.app/Contents/MacOS/MarkdownObserver' \
      ! -path '*/Index.noindex/*' \
      -perm -111 \
      -print
  )

  if [[ "${#app_candidates[@]}" -eq 0 ]]; then
    return
  fi

  local app_binary
  app_binary="$(
    for candidate in "${app_candidates[@]}"; do
      stat -f '%m %N' "$candidate"
    done | \
    sort -nr | \
    head -n 1 | \
    cut -d' ' -f2-
  )"

  if [[ -n "$app_binary" ]]; then
    printf '%s\n' "$app_binary"
  fi
}

if [[ -z "$APP_PATH" ]]; then
  APP_PATH="$(resolve_default_app_path)"
  if [[ -z "$APP_PATH" ]]; then
    echo "Could not find Debug MarkdownObserver.app in DerivedData. Use --app-path." >&2
    exit 2
  fi
fi

if [[ ! -x "$APP_PATH" ]]; then
  echo "Executable not found or not executable: $APP_PATH" >&2
  exit 2
fi

mkdir -p profiling

TRACE_FILE="profiling/time-profiler-watch-eigenes-diagnostic-${TIMESTAMP}.trace"
TOC_FILE="profiling/time-profiler-watch-eigenes-diagnostic-${TIMESTAMP}.toc.xml"
PROFILE_XML="profiling/watch-eigenes-diagnostic-time-profile-${TIMESTAMP}.xml"
SIGNPOSTS_XML="profiling/watch-eigenes-diagnostic-signposts-${TIMESTAMP}.xml"

export MINIMARK_UI_TEST_WATCH_FOLDER_PATH="$WATCH_PATH"

cleanup() {
  if [[ -z "${APP_PID:-}" ]]; then
    return
  fi

  if kill -0 "$APP_PID" 2>/dev/null; then
    osascript -e 'tell application "MarkdownObserver" to quit' >/dev/null 2>&1 || true
    kill "$APP_PID" 2>/dev/null || true
    wait "$APP_PID" 2>/dev/null || true
  fi
}

trap cleanup EXIT INT TERM

if [[ "$STRICT_MODE" -eq 1 ]]; then
  "$APP_PATH" -minimark-ui-test -minimark-auto-start-watch-folder >/tmp/markdownobserver-diagnostic.log 2>&1 &
  APP_PID=$!
  sleep 3

  set +e
  xcrun xctrace record \
    --template 'Time Profiler' \
    --output "$TRACE_FILE" \
    --time-limit "$TIME_LIMIT" \
    --attach "$APP_PID"
  TRACE_EXIT=$?
  set -e
else
  set +e
  xcrun xctrace record \
    --template 'Time Profiler' \
    --output "$TRACE_FILE" \
    --time-limit "$TIME_LIMIT" \
    --launch -- "$APP_PATH" \
    -minimark-ui-test \
    -minimark-auto-start-watch-folder
  TRACE_EXIT=$?
  set -e
fi

if [[ ! -e "$TRACE_FILE" ]]; then
  echo "Trace capture failed and no trace file was created." >&2
  exit 1
fi

xcrun xctrace export --input "$TRACE_FILE" --toc > "$TOC_FILE"
xcrun xctrace export --input "$TRACE_FILE" --xpath '/trace-toc/run[@number="1"]/data/table[@schema="time-profile"]' > "$PROFILE_XML"
xcrun xctrace export --input "$TRACE_FILE" --xpath '/trace-toc/run[@number="1"]/data/table[@schema="os-signpost"]' > "$SIGNPOSTS_XML"

echo "CPU diagnostic completed."
echo "xctrace exit code: $TRACE_EXIT"
echo "Trace: $TRACE_FILE"
echo "TOC: $TOC_FILE"
echo "Time profile XML: $PROFILE_XML"
echo "Signposts XML: $SIGNPOSTS_XML"
