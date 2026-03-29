#!/usr/bin/env bash
#
# take-screenshots.sh — Capture App Store screenshots for MarkdownObserver
#
# Usage: ./scripts/screenshots/take-screenshots.sh [--skip-build] [--only N] [--skip-composite]
#
# Requires: Xcode, Python 3, Pillow (auto-installed if missing)
# Captures 8 screenshots across themes, composites over aurora background.
# Safe to rerun after design changes.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
CONTENT_DIR="$SCRIPT_DIR/content"
RAW_DIR="$PROJECT_DIR/docs/assets/screenshots/raw"
OUTPUT_DIR="$PROJECT_DIR/docs/assets/screenshots"
BACKGROUND="$PROJECT_DIR/docs/assets/screenshot_bck.png"
COMPOSITE_SCRIPT="$SCRIPT_DIR/composite.py"

# --- Parse arguments ---
SKIP_BUILD=false
ONLY_SHOT=""
SKIP_COMPOSITE=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --skip-build) SKIP_BUILD=true; shift ;;
        --only) ONLY_SHOT="$2"; shift 2 ;;
        --skip-composite) SKIP_COMPOSITE=true; shift ;;
        *) echo "Unknown argument: $1"; exit 1 ;;
    esac
done

# --- Detect bundle ID ---
detect_bundle_id() {
    local signing_config="$PROJECT_DIR/Config/Signing.local.xcconfig"
    if [[ -f "$signing_config" ]]; then
        local bid
        bid=$(grep '^APP_BUNDLE_IDENTIFIER' "$signing_config" | head -1 | sed 's/.*= *//')
        if [[ -n "$bid" ]]; then
            echo "$bid"
            return
        fi
    fi
    echo "org.markdownobserver.app"
}

BUNDLE_ID="$(detect_bundle_id)"
SETTINGS_KEY="reader.settings.v1"
echo "Bundle ID: $BUNDLE_ID"

# --- Pre-flight checks ---
command -v xcodebuild >/dev/null 2>&1 || { echo "Error: xcodebuild not found"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "Error: python3 not found"; exit 1; }

# Ensure Pillow is available via a local venv
VENV_DIR="$SCRIPT_DIR/.venv"
if [[ ! -d "$VENV_DIR" ]]; then
    echo "Creating Python virtual environment..."
    python3 -m venv "$VENV_DIR"
fi
PYTHON="$VENV_DIR/bin/python3"
PIP="$VENV_DIR/bin/pip3"

if ! "$PYTHON" -c "import PIL" 2>/dev/null; then
    echo "Installing Pillow..."
    "$PIP" install --quiet Pillow
fi

[[ -f "$BACKGROUND" ]] || { echo "Error: Background image not found at $BACKGROUND"; exit 1; }

mkdir -p "$RAW_DIR" "$OUTPUT_DIR"

# --- Build ---
if [[ "$SKIP_BUILD" == false ]]; then
    echo "Building MarkdownObserver (Debug)..."
    xcodebuild -project "$PROJECT_DIR/minimark.xcodeproj" \
        -scheme minimark \
        -configuration Debug \
        -destination 'platform=macOS' \
        build 2>&1 | tail -5
    echo "Build complete."
fi

# --- Locate built binary ---
find_app_binary() {
    local derived_data
    derived_data=$(xcodebuild -project "$PROJECT_DIR/minimark.xcodeproj" \
        -scheme minimark -configuration Debug \
        -showBuildSettings 2>/dev/null | grep '^\s*BUILT_PRODUCTS_DIR' | head -1 | sed 's/.*= *//')
    if [[ -z "$derived_data" ]]; then
        echo "Error: Could not find BUILT_PRODUCTS_DIR" >&2
        exit 1
    fi
    local app_path="$derived_data/MarkdownObserver.app"
    if [[ ! -d "$app_path" ]]; then
        echo "Error: Built app not found at $app_path" >&2
        exit 1
    fi
    echo "$app_path"
}

APP_PATH="$(find_app_binary)"
APP_BINARY="$APP_PATH/Contents/MacOS/MarkdownObserver"
PROCESS_NAME="MarkdownObserver"
echo "App binary: $APP_BINARY"

# --- Settings management ---
backup_settings() {
    # Export via defaults (handles sandboxed container path automatically)
    defaults export "$BUNDLE_ID" "$SCRIPT_DIR/.settings-backup.plist" 2>/dev/null || true
    echo "Settings backed up."
}

restore_settings() {
    local backup="$SCRIPT_DIR/.settings-backup.plist"
    if [[ -f "$backup" ]]; then
        defaults import "$BUNDLE_ID" "$backup" 2>/dev/null || true
        rm -f "$backup"
        echo "Settings restored."
    fi
    # Remove overrides we set for the screenshot session
    defaults delete "$BUNDLE_ID" NSQuitAlwaysKeepsWindows 2>/dev/null || true
    defaults delete "$BUNDLE_ID" ApplePersistenceIgnoreState 2>/dev/null || true
}

write_theme_settings() {
    local reader_theme="$1"
    local syntax_theme="$2"
    local app_appearance="$3"
    local sidebar_placement="${4:-sidebarLeft}"

    python3 -c "
import json, subprocess, sys

bundle_id = '$BUNDLE_ID'
key = '$SETTINGS_KEY'

settings = None
try:
    result = subprocess.run(['defaults', 'export', bundle_id, '-'], capture_output=True)
    if result.returncode == 0:
        import plistlib
        plist = plistlib.loads(result.stdout)
        raw = plist.get(key)
        if isinstance(raw, bytes):
            settings = json.loads(raw.decode('utf-8'))
except Exception:
    pass

if settings is None:
    settings = {
        'baseFontSize': 15,
        'autoRefreshOnExternalChange': True,
        'notificationsEnabled': True,
        'multiFileDisplayMode': 'sidebarLeft',
        'sidebarSortMode': 'openOrder',
        'favoriteWatchedFolders': [],
        'recentWatchedFolders': [],
        'recentManuallyOpenedFiles': [],
        'trustedImageFolders': []
    }

settings['readerTheme'] = '$reader_theme'
settings['syntaxTheme'] = '$syntax_theme'
settings['appAppearance'] = '$app_appearance'
settings['multiFileDisplayMode'] = '$sidebar_placement'
settings['autoRefreshOnExternalChange'] = True

json_bytes = json.dumps(settings, ensure_ascii=False).encode('utf-8')
hex_str = json_bytes.hex()
subprocess.check_call(['defaults', 'write', bundle_id, key, '-data', hex_str])
"
}

# --- App control ---
clean_saved_state() {
    # Disable window restoration and state persistence entirely
    defaults write "$BUNDLE_ID" NSQuitAlwaysKeepsWindows -bool false 2>/dev/null || true
    defaults write "$BUNDLE_ID" ApplePersistenceIgnoreState -bool true 2>/dev/null || true
    # Remove any existing saved state
    rm -rf "$HOME/Library/Saved Application State/${BUNDLE_ID}.savedState" 2>/dev/null || true
    rm -rf "$HOME/Library/Containers/${BUNDLE_ID}/Data/Library/Saved Application State/${BUNDLE_ID}.savedState" 2>/dev/null || true
    find "$HOME/Library/Containers/${BUNDLE_ID}" -name "*.savedState" -type d -exec rm -rf {} + 2>/dev/null || true
}

dismiss_crash_dialog() {
    # If a crash recovery dialog appears, click "Don't Reopen"
    osascript -e '
        tell application "System Events"
            tell process "MarkdownObserver"
                try
                    set allSheets to every sheet of window 1
                    repeat with s in allSheets
                        try
                            click button "Don'\''t Reopen" of s
                            return "dismissed"
                        end try
                    end repeat
                end try
                -- Try as a standalone dialog window
                repeat with w in windows
                    try
                        click button "Don'\''t Reopen" of w
                        return "dismissed"
                    end try
                end repeat
            end tell
        end tell
        return "none"
    ' 2>/dev/null || echo "none"
}

quit_app() {
    osascript -e 'tell application "MarkdownObserver" to quit' 2>/dev/null || true
    sleep 1
    # Force kill if still running
    pkill -f "MarkdownObserver" 2>/dev/null || true
    sleep 0.5
    clean_saved_state
}

launch_app_showcase() {
    local content_path="$1"
    local active_file="${2:-README.md}"
    local expand_edit="${3:-false}"
    local split_view="${4:-false}"
    clean_saved_state
    open --env MINIMARK_SCREENSHOT_CONTENT_PATH="$content_path" \
        --env MINIMARK_SCREENSHOT_ACTIVE_FILE="$active_file" \
        --env MINIMARK_SCREENSHOT_EXPAND_FIRST_EDIT="$expand_edit" \
        --env MINIMARK_SCREENSHOT_SPLIT_VIEW="$split_view" \
        -a "$APP_PATH" \
        --args \
        -minimark-ui-test \
        -minimark-simulate-screenshot-showcase
}

select_sidebar_document() {
    local shot_num="$1"
    local target_doc
    case "$shot_num" in
        1) target_doc="README" ;;
        2) target_doc="README" ;;
        3) target_doc="api-reference" ;;
        4) target_doc="architecture" ;;
        5) target_doc="changelog" ;;
        6) target_doc="README" ;;
        *) return ;;
    esac
    echo "    Selecting sidebar document: $target_doc"
    # Use accessibility identifier "sidebar-document-<title>" added to each row
    osascript -l JavaScript -e "
        const se = Application('System Events');
        const proc = se.processes['MarkdownObserver'];
        proc.frontmost = true;
        delay(0.5);

        function findByIdentifier(element, prefix) {
            try {
                const ident = element.description();
                if (ident && ident.indexOf(prefix) !== -1) {
                    element.actions['AXPress'].perform();
                    return 'selected';
                }
            } catch(e) {}
            try {
                const children = element.uiElements();
                for (let i = 0; i < children.length; i++) {
                    const result = findByIdentifier(children[i], prefix);
                    if (result === 'selected') return result;
                }
            } catch(e) {}
            return 'not_found';
        }

        const win = proc.windows[0];
        findByIdentifier(win, 'sidebar-document-$target_doc');
    " 2>/dev/null || echo "not_found"
}

launch_app_watch_dialog() {
    local watch_folder="$1"
    local watch_scope="${2:-selectedFolderOnly}"
    local open_exclusion="${3:-false}"
    clean_saved_state
    open --env MINIMARK_UI_TEST_WATCH_FOLDER_PATH="$watch_folder" \
        --env MINIMARK_SCREENSHOT_WATCH_SCOPE="$watch_scope" \
        --env MINIMARK_SCREENSHOT_OPEN_EXCLUSION="$open_exclusion" \
        -a "$APP_PATH" \
        --args \
        -minimark-ui-test \
        -minimark-present-watch-folder-sheet
}

WINDOW_ID_HELPER="$SCRIPT_DIR/get-window-id"

# Compile window ID helper if needed
if [[ ! -x "$WINDOW_ID_HELPER" ]] || [[ "$SCRIPT_DIR/get-window-id.swift" -nt "$WINDOW_ID_HELPER" ]]; then
    echo "Compiling window ID helper..."
    swiftc -O "$SCRIPT_DIR/get-window-id.swift" -o "$WINDOW_ID_HELPER"
fi

get_window_id() {
    "$WINDOW_ID_HELPER" MarkdownObserver 2>/dev/null
}

wait_for_window() {
    local max_wait=${1:-10}
    local elapsed=0
    while [[ $elapsed -lt $max_wait ]]; do
        local wid
        wid=$(get_window_id)
        if [[ -n "$wid" ]]; then
            echo "$wid"
            return 0
        fi
        sleep 0.5
        elapsed=$((elapsed + 1))
    done
    echo ""
    return 1
}

resize_window() {
    local width="$1"
    local height="$2"
    osascript -e "
        tell application \"System Events\"
            tell process \"minimark\"
                set frontmost to true
                delay 0.3
                set win to window 1
                set position of win to {100, 100}
                set size of win to {$width, $height}
            end tell
        end tell
    " 2>/dev/null
}

capture_window() {
    local output_file="$1"
    local wid
    wid=$(get_window_id)

    if [[ -z "$wid" ]]; then
        echo "    Warning: Could not get window ID, using full-screen capture"
        screencapture -o "$output_file"
    else
        screencapture -o -l "$wid" "$output_file"
    fi
}

click_edited_gutter_pill() {
    # Gutter pills are inside WKWebView — use JavaScript to click them.
    # We inject JS via the accessibility tree's AXWebArea element.
    osascript -e '
        tell application "System Events"
            tell process "MarkdownObserver"
                set frontmost to true
                delay 0.5
            end tell
        end tell
    ' 2>/dev/null

    # Use osascript with JavaScript for Automation to find and click
    # the WKWebView content via accessibility
    osascript -l JavaScript -e '
        const se = Application("System Events");
        const proc = se.processes["MarkdownObserver"];
        const win = proc.windows[0];

        function findEditedButton(element) {
            try {
                const role = element.role();
                if (role === "AXButton") {
                    const desc = element.description();
                    if (desc && desc.indexOf("Edited") !== -1) {
                        element.actions["AXPress"].perform();
                        return "clicked";
                    }
                }
            } catch(e) {}
            try {
                const children = element.uiElements();
                for (let i = 0; i < children.length; i++) {
                    const result = findEditedButton(children[i]);
                    if (result === "clicked") return result;
                }
            } catch(e) {}
            return "not_found";
        }

        findEditedButton(win);
    ' 2>/dev/null || echo "not_found"
}

trigger_split_view() {
    osascript -e '
        tell application "System Events"
            tell process "MarkdownObserver"
                set frontmost to true
                delay 0.3
                -- Cmd+E to toggle edit mode
                keystroke "e" using command down
                delay 1.0
                -- Access View menu for Split
                click menu item "Show Split" of menu "View" of menu bar 1
            end tell
        end tell
    ' 2>/dev/null
}

click_include_subfolders() {
    osascript -e '
        tell application "System Events"
            tell process "MarkdownObserver"
                set frontmost to true
                delay 0.5
                -- Click "Include Subfolders" radio button / segmented control
                tell window 1
                    set allRadios to every radio button
                    repeat with r in allRadios
                        try
                            set radioTitle to title of r
                            if radioTitle contains "Include" or radioTitle contains "Subfolders" then
                                click r
                                return "clicked"
                            end if
                        end try
                        try
                            set radioDesc to description of r
                            if radioDesc contains "Include" or radioDesc contains "Subfolders" then
                                click r
                                return "clicked"
                            end if
                        end try
                    end repeat
                    -- Try segmented controls (Picker style)
                    set allGroups to every group
                    repeat with g in allGroups
                        try
                            set groupRadios to every radio button of g
                            repeat with r in groupRadios
                                try
                                    if title of r contains "Include" or title of r contains "Subfolders" then
                                        click r
                                        return "clicked"
                                    end if
                                end try
                            end repeat
                        end try
                    end repeat
                end tell
            end tell
        end tell
        return "not_found"
    ' 2>/dev/null || echo "not_found"
}

click_choose_subdirectories() {
    osascript -e '
        tell application "System Events"
            tell process "MarkdownObserver"
                set frontmost to true
                delay 0.3
                tell window 1
                    set allButtons to every button
                    repeat with b in allButtons
                        try
                            set btnTitle to title of b
                            if btnTitle contains "subdirectories" or btnTitle contains "deactivate" then
                                click b
                                return "clicked"
                            end if
                        end try
                        try
                            set btnDesc to description of b
                            if btnDesc contains "subdirectories" or btnDesc contains "deactivate" then
                                click b
                                return "clicked"
                            end if
                        end try
                    end repeat
                end tell
            end tell
        end tell
        return "not_found"
    ' 2>/dev/null || echo "not_found"
}

# --- Temp folder helpers ---
create_watch_dialog_folder() {
    local base="$1"
    mkdir -p "$base"
    local dirs=(
        "Sources/App" "Sources/Models" "Sources/Views" "Sources/Services"
        "Sources/Support" "Sources/Networking" "Sources/Database"
        "Tests/Unit" "Tests/Integration" "Tests/Snapshots"
        "docs/guides" "docs/api" "docs/tutorials"
        "Resources/Fonts" "Resources/Images" "Resources/Strings"
        "Scripts" "Config"
    )
    for d in "${dirs[@]}"; do
        mkdir -p "$base/$d"
        # Create some .md files in each directory
        for f in README.md NOTES.md TODO.md; do
            echo "# $(basename "$d")" > "$base/$d/$f"
        done
    done
    # Create root-level files
    for f in README.md CONTRIBUTING.md CHANGELOG.md SECURITY.md CODE_OF_CONDUCT.md; do
        echo "# $f" > "$base/$f"
    done
}

create_exclusion_dialog_folder() {
    local base="$1"
    mkdir -p "$base"

    # Realistic top-level project structure
    local top_dirs=(
        "Sources/App" "Sources/Models" "Sources/Views" "Sources/ViewModels"
        "Sources/Services" "Sources/Networking" "Sources/Database"
        "Sources/Extensions" "Sources/Protocols" "Sources/Support"
        "Tests/Unit" "Tests/Integration" "Tests/Snapshots" "Tests/Performance"
        "Packages/CoreKit/Sources" "Packages/CoreKit/Tests"
        "Packages/UIKit/Sources" "Packages/UIKit/Tests"
        "Packages/NetworkLayer/Sources" "Packages/NetworkLayer/Tests"
        "Packages/Analytics/Sources" "Packages/Analytics/Tests"
        "Packages/FeatureFlags/Sources" "Packages/FeatureFlags/Tests"
        "Resources/Fonts" "Resources/Images" "Resources/Strings" "Resources/Sounds"
        "docs/api" "docs/guides" "docs/internal"
        "Scripts" "Config" "Fastlane"
        ".build/checkouts" ".build/artifacts" ".build/repositories"
        "DerivedData/Build" "DerivedData/Index" "DerivedData/Logs"
        "node_modules/.bin" "node_modules/@types" "node_modules/webpack"
        "vendor/bundle" "vendor/cache"
        "Pods/Alamofire" "Pods/SnapKit" "Pods/Kingfisher"
    )

    for d in "${top_dirs[@]}"; do
        mkdir -p "$base/$d"
        echo "# $(basename "$d")" > "$base/$d/README.md"
    done

    # Add numbered feature modules to reach >256 total subdirs
    local features=(
        "Auth" "Profile" "Settings" "Onboarding" "Search" "Feed"
        "Messaging" "Notifications" "Payments" "Analytics" "Storage"
        "Camera" "Maps" "Social" "Sync" "Export" "Import" "Sharing"
        "Bookmarks" "History" "Downloads" "Offline" "Widgets" "Shortcuts"
        "Accessibility" "Localization" "DeepLinks" "PushNotifications"
        "CloudSync" "DataMigration" "FeatureFlags" "ABTesting" "Logging"
        "Caching" "Theming" "Navigation" "Permissions" "MediaPicker"
        "RichText" "FilePreview" "UserDefaults" "Keychain" "Biometrics"
    )
    for feature in "${features[@]}"; do
        for sub in Sources Tests Resources Mocks; do
            mkdir -p "$base/Features/$feature/$sub"
            echo "# $feature $sub" > "$base/Features/$feature/$sub/README.md"
        done
    done

    # Additional platform targets
    local platforms=("iOS" "macOS" "watchOS" "tvOS" "visionOS")
    for p in "${platforms[@]}"; do
        for sub in Sources Tests Resources; do
            mkdir -p "$base/Platforms/$p/$sub"
            echo "# $p" > "$base/Platforms/$p/$sub/README.md"
        done
    done

    # CI/CD configs
    for ci in github gitlab jenkins buildkite; do
        mkdir -p "$base/.ci/$ci"
        echo "# CI" > "$base/.ci/$ci/README.md"
    done
}

# --- Screenshot definitions ---
# Format: number|reader_theme|syntax_theme|appearance|punchline|type|active_file|is_dark|nocrop|crop_anchor|sidebar|extras
SCREENSHOTS=(
    "1|darkGreyOnLightGrey|monokai|light|Render your agent's markdown, instantly|showcase_diff|auth-migration.md|0|||sidebarRight|"
    "2|lightGreyOnDarkGrey|oneDark|dark|Syntax highlighting for 150+ languages|showcase|cache-redesign.md|1|||sidebarRight|"
    "3|whiteOnBlack|dracula|dark|Tables, task lists, code blocks — all rendered|showcase|architecture.md|1|||sidebarLeft|"
    "4|whiteOnBlack|nord|dark|See what changed at a glance|showcase_diff|changelog.md|1|||sidebarRight|"
    "5|darkGreyOnLightGrey|github|light|Review plans and tasks from any agent|showcase|session-log.md|0|||sidebarLeft|"
    "6|blackOnWhite|solarizedLight|light|Edit and preview, side by side|showcase_split|auth-migration.md|0|||sidebarRight|"
    "7|darkGreyOnLightGrey|monokai|light|Watch folders for live updates|showcase_watch_active|session-log.md|0|||sidebarLeft|"
    "8|blackOnWhite|github|light|Quick access to your projects|showcase_favorites|pr-847-review.md|0|||sidebarRight|favorites"
    "9|darkGreyOnLightGrey|github|light|Auto-reload on file changes|dialog_watch_over_content|session-log.md|0|||sidebarLeft|"
    "10|lightGreyOnDarkGrey|oneDark|dark|Manage monitoring for large projects|dialog_exclusion_over_content|security-audit.md|1|nocrop|center|sidebarRight|"
)

# --- Main capture loop ---
backup_settings
trap restore_settings EXIT

# Use the app's sandbox container for temp files so the sandboxed app can access them
CONTAINER_TMP="$HOME/Library/Containers/$BUNDLE_ID/Data/tmp"
mkdir -p "$CONTAINER_TMP"
TEMP_BASE="$CONTAINER_TMP/screenshot-session"
rm -rf "$TEMP_BASE"
mkdir -p "$TEMP_BASE"
# Put watch folders directly in the container's home for a shorter display path.
# The app shows the full path but truncates the middle — a short parent path
# means the truncation hides the container prefix entirely.
CONTAINER_HOME="$HOME/Library/Containers/$BUNDLE_ID/Data"
WATCH_FOLDER="$CONTAINER_HOME/my-swift-project"
rm -rf "$WATCH_FOLDER"
EXCLUSION_FOLDER="$CONTAINER_HOME/enterprise-monorepo"
rm -rf "$EXCLUSION_FOLDER"

# --- Setup: build authentic favorites and recent watched folders ---
echo ""
echo "Setting up favorites and recent watched folders..."

# Create project folders that the app will watch to build real recents
SETUP_FOLDERS=(
    "$CONTAINER_HOME/hive-server"
    "$CONTAINER_HOME/ios-app"
    "$CONTAINER_HOME/shared-models"
    "$CONTAINER_HOME/design-system"
)
for folder in "${SETUP_FOLDERS[@]}"; do
    rm -rf "$folder"
    mkdir -p "$folder"
    echo "# $(basename "$folder")" > "$folder/README.md"
done

# Launch the app to watch each folder briefly — this populates the recent list
for folder in "${SETUP_FOLDERS[@]}"; do
    clean_saved_state
    open --env MINIMARK_UI_TEST_WATCH_FOLDER_PATH="$folder" \
        -a "$APP_PATH" \
        --args -minimark-ui-test -minimark-auto-start-watch-folder
    sleep 3
    osascript -e 'tell application "MarkdownObserver" to quit' 2>/dev/null || true
    sleep 1
    pkill -f "MarkdownObserver" 2>/dev/null || true
    sleep 0.5
done

# Promote the first 3 recents to favorites (using the app's own data format)
python3 -c "
import json, subprocess, plistlib, uuid, time

bundle_id = '$BUNDLE_ID'
key = '$SETTINGS_KEY'

result = subprocess.run(['defaults', 'export', bundle_id, '-'], capture_output=True)
if result.returncode != 0:
    exit(0)
plist = plistlib.loads(result.stdout)
raw = plist.get(key)
if not isinstance(raw, bytes):
    exit(0)
settings = json.loads(raw.decode('utf-8'))

recents = settings.get('recentWatchedFolders', [])
ref = time.time() - 978307200
favorites = []
for i, recent in enumerate(recents[:3]):
    name = recent['folderPath'].rstrip('/').split('/')[-1]
    favorites.append({
        'id': str(uuid.uuid4()),
        'name': name,
        'folderPath': recent['folderPath'],
        'options': recent['options'],
        'bookmarkData': recent.get('bookmarkData'),
        'createdAt': ref - (i * 86400)
    })

settings['favoriteWatchedFolders'] = favorites
json_bytes = json.dumps(settings, ensure_ascii=False).encode('utf-8')
subprocess.check_call(['defaults', 'write', bundle_id, key, '-data', json_bytes.hex()])
print(f'Created {len(favorites)} favorites from {len(recents)} recents')
"

echo "Setup complete."

echo ""
echo "Starting screenshot capture..."
echo "================================"

for shot_def in "${SCREENSHOTS[@]}"; do
    IFS='|' read -r num reader_theme syntax_theme appearance punchline shot_type active_file is_dark nocrop crop_anchor sidebar_mode extras <<< "$shot_def"

    # Skip if --only specified and doesn't match
    if [[ -n "$ONLY_SHOT" && "$num" != "$ONLY_SHOT" ]]; then
        continue
    fi

    echo ""
    echo "--- Screenshot $num: $punchline ---"
    echo "    Theme: $reader_theme / $syntax_theme ($appearance)"

    # Quit any running instance
    quit_app

    # Write theme settings
    write_theme_settings "$reader_theme" "$syntax_theme" "$appearance" "${sidebar_mode:-sidebarLeft}"

    case "$shot_type" in
        showcase_watch_active)
            # Use a real folder watch flow:
            # 1. Open the app with showcase content (so there's a window with documents)
            # 2. Use Watch menu → Recent to start watching a folder from the setup phase
            # 3. The recent entry triggers watching with its saved options
            # 4. Then touch files in the watched folder to trigger auto-open
            STAGING_DIR="$TEMP_BASE/content-$num"
            rm -rf "$STAGING_DIR"
            mkdir -p "$STAGING_DIR"
            for f in "$CONTENT_DIR"/*.md; do
                [[ -f "$f" ]] || continue
                fname=$(basename "$f")
                [[ "$fname" == *-before* ]] && continue
                cp "$f" "$STAGING_DIR/"
            done

            clean_saved_state
            open --env MINIMARK_SCREENSHOT_CONTENT_PATH="$STAGING_DIR" \
                --env MINIMARK_SCREENSHOT_ACTIVE_FILE="$active_file" \
                --env MINIMARK_SCREENSHOT_EXPAND_FIRST_EDIT="false" \
                --env MINIMARK_SCREENSHOT_SPLIT_VIEW="false" \
                --env MINIMARK_SCREENSHOT_SHOW_WATCH_SHEET="" \
                --env MINIMARK_SCREENSHOT_SHOW_WATCH_MENU="" \
                -a "$APP_PATH" \
                --args \
                -minimark-ui-test \
                -minimark-simulate-screenshot-showcase
            sleep 2
            dismiss_crash_dialog
            sleep 4

            WID=$(wait_for_window 15 || true)
            if [[ -z "$WID" ]]; then
                echo "    ERROR: Window not found, skipping"
                quit_app
                continue
            fi

            # Use Watch menu to start watching the first setup folder
            echo "    Starting folder watch via menu..."
            osascript -e '
                tell application "System Events"
                    tell process "MarkdownObserver"
                        set frontmost to true
                        delay 0.5
                        click menu item 1 of menu of menu item "Recent Watched Folders" of menu "Watch" of menu bar 1
                    end tell
                end tell
            ' 2>/dev/null || echo "    Menu click failed"
            sleep 2

            # Press Return to confirm the "Start Watching" dialog
            echo "    Confirming watch dialog..."
            osascript -e '
                tell application "System Events"
                    tell process "MarkdownObserver"
                        set frontmost to true
                        delay 0.3
                        keystroke return
                    end tell
                end tell
            ' 2>/dev/null
            sleep 3

            # Touch files in the watched folder to trigger auto-open
            echo "    Triggering file opens..."
            WATCHED="${SETUP_FOLDERS[0]}"
            for f in "$WATCHED"/*.md; do
                [[ -f "$f" ]] && echo "" >> "$f"
            done
            sleep 4

            # Now externally edit the active file to trigger gutter changes
            echo "    Externally editing watched file..."
            WATCHED_FILE="$WATCHED/$active_file"
            if [[ -f "$WATCHED_FILE" ]]; then
                # Append new content (added lines), modify would need the file to exist with known content
                # Write the "after" version from the content dir if a before/after pair exists
                if [[ -f "$CONTENT_DIR/${active_file%.md}-before.md" ]]; then
                    cat "$CONTENT_DIR/$active_file" > "$WATCHED_FILE"
                else
                    # Just append some lines to trigger added-type gutter
                    printf '\n## Recent Changes\n\n- Updated authentication flow\n- Fixed token refresh race condition\n' >> "$WATCHED_FILE"
                fi
            fi
            sleep 4
            ;;

        showcase|showcase_diff|showcase_split|showcase_favorites|dialog_watch_over_content|dialog_exclusion_over_content)
            # Prepare content in the app's container (sandbox-accessible)
            STAGING_DIR="$TEMP_BASE/content-$num"
            rm -rf "$STAGING_DIR"
            mkdir -p "$STAGING_DIR"

            # Copy content files — skip "-before" files (those are never opened)
            for f in "$CONTENT_DIR"/*.md; do
                [[ -f "$f" ]] || continue
                fname=$(basename "$f")
                [[ "$fname" == *-before* ]] && continue
                cp "$f" "$STAGING_DIR/"
            done

            # For diff shots: replace target files with "before" versions now.
            # The app will load these. After the app is ready, the script will
            # overwrite them with the "after" versions externally — triggering
            # the real file-watch change detection with yellow indicators,
            # correct sidebar timestamps, and gutter diff rendering.
            if [[ "$shot_type" == "showcase_diff" ]]; then
                for bf in "$CONTENT_DIR"/*-before.md; do
                    [[ -f "$bf" ]] || continue
                    target=$(basename "$bf" | sed 's/-before//')
                    cp "$bf" "$STAGING_DIR/$target"
                done
            fi

            # Expand first edited gutter pill for diff shots
            expand_edit="false"
            if [[ "$shot_type" == "showcase_diff" ]]; then
                expand_edit="true"
            fi
            # Enable split view for split screenshots
            split_view="false"
            if [[ "$shot_type" == "showcase_split" ]]; then
                split_view="true"
            fi

            # Prepare type-specific env vars
            watch_sheet_path=""
            watch_scope="selectedFolderOnly"
            show_watch_menu="false"

            if [[ "$shot_type" == "dialog_watch_over_content" ]]; then
                echo "    Creating watch folder structure..."
                create_watch_dialog_folder "$WATCH_FOLDER"
                watch_sheet_path="$WATCH_FOLDER"
                watch_scope="includeSubfolders"
            elif [[ "$shot_type" == "dialog_exclusion_over_content" ]]; then
                echo "    Creating large folder structure..."
                create_exclusion_dialog_folder "$EXCLUSION_FOLDER"
                watch_sheet_path="$EXCLUSION_FOLDER"
                watch_scope="includeSubfolders"
            elif [[ "$shot_type" == "showcase_favorites" ]]; then
                show_watch_menu="true"
            fi

            # Launch app (portrait window, composite crops upper portion to landscape)
            clean_saved_state
            open --env MINIMARK_SCREENSHOT_CONTENT_PATH="$STAGING_DIR" \
                --env MINIMARK_SCREENSHOT_ACTIVE_FILE="$active_file" \
                --env MINIMARK_SCREENSHOT_EXPAND_FIRST_EDIT="$expand_edit" \
                --env MINIMARK_SCREENSHOT_SPLIT_VIEW="$split_view" \
                --env MINIMARK_SCREENSHOT_SHOW_WATCH_SHEET="$watch_sheet_path" \
                --env MINIMARK_SCREENSHOT_WATCH_SCOPE="$watch_scope" \
                --env MINIMARK_SCREENSHOT_OPEN_EXCLUSION="$( [[ "$shot_type" == "dialog_exclusion_over_content" ]] && echo true || echo false )" \
                --env MINIMARK_SCREENSHOT_EXCLUDED_PATHS="$( [[ "$shot_type" == "dialog_exclusion_over_content" ]] && echo '.build,DerivedData,node_modules,vendor,Pods' || echo '' )" \
                --env MINIMARK_SCREENSHOT_EXPANDED_PATHS="$( [[ "$shot_type" == "dialog_exclusion_over_content" ]] && echo 'Features,Packages' || echo '' )" \
                --env MINIMARK_SCREENSHOT_SHOW_WATCH_MENU="$show_watch_menu" \
                -a "$APP_PATH" \
                --args \
                -minimark-ui-test \
                -minimark-simulate-screenshot-showcase
            sleep 2
            dismiss_crash_dialog

            # Type-specific wait times
            if [[ "$shot_type" == dialog_*_over_content ]]; then
                sleep 8
            elif [[ "$shot_type" == "showcase_favorites" ]]; then
                sleep 8  # Wait for documents to load + popover to auto-present
            else
                sleep 4
            fi

            # Wait for window
            WID=$(wait_for_window 15 || true)
            if [[ -z "$WID" ]]; then
                echo "    ERROR: Window not found, skipping"
                quit_app
                continue
            fi

            # For diff shots: now externally overwrite files with "after" versions.
            # This triggers the real file-watch flow: yellow indicators, correct
            # sidebar timestamps ("just now"), and gutter change rendering.
            if [[ "$shot_type" == "showcase_diff" ]]; then
                SHOWCASE_DIR="$CONTAINER_TMP/minimark-screenshot-showcase"
                sleep 2  # Let file watchers fully initialize
                for bf in "$CONTENT_DIR"/*-before.md; do
                    [[ -f "$bf" ]] || continue
                    target=$(basename "$bf" | sed 's/-before//')
                    # Search recursively — files may be in subdirectories
                    target_path=$(find "$SHOWCASE_DIR" -name "$target" -type f 2>/dev/null | head -1)
                    if [[ -n "$target_path" ]]; then
                        echo "    Externally modifying $target..."
                        cat "$CONTENT_DIR/$target" > "$target_path"
                    fi
                done
                sleep 5  # Wait for file watcher + reload + diff render + auto-expand
            else
                sleep 1
            fi
            ;;

        *)
            echo "    ERROR: Unknown shot type '$shot_type', skipping"
            continue
            ;;
    esac

    # Capture
    RAW_FILE="$RAW_DIR/screenshot_${num}_raw.png"
    echo "    Capturing screenshot..."
    capture_window "$RAW_FILE"

    if [[ -f "$RAW_FILE" ]]; then
        echo "    Saved: $RAW_FILE"
    else
        echo "    ERROR: Screenshot file not created"
    fi

    quit_app
done

# Clean up temp folders
rm -rf "$TEMP_BASE" 2>/dev/null || true
rm -rf "$WATCH_FOLDER" 2>/dev/null || true
rm -rf "$EXCLUSION_FOLDER" 2>/dev/null || true

echo ""
echo "================================"
echo "Raw screenshots captured."

# --- Composite ---
if [[ "$SKIP_COMPOSITE" == false ]]; then
    echo ""
    echo "Compositing final screenshots..."

    # Build the punchlines array for composite.py (num|text|is_dark|is_dialog)
    PUNCHLINES=""
    for shot_def in "${SCREENSHOTS[@]}"; do
        IFS='|' read -r num _ _ _ punchline shot_type _ is_dark p_nocrop p_crop_anchor _ _ <<< "$shot_def"
        if [[ -n "$ONLY_SHOT" && "$num" != "$ONLY_SHOT" ]]; then
            continue
        fi
        is_dialog="0"
        if [[ "$shot_type" == dialog_* && "$p_nocrop" != "nocrop" ]]; then
            is_dialog="1"
        fi
        anchor="${p_crop_anchor:-top}"
        PUNCHLINES="$PUNCHLINES$num|$punchline|$is_dark|$is_dialog|$anchor\n"
    done

    "$PYTHON" "$COMPOSITE_SCRIPT" \
        --raw-dir "$RAW_DIR" \
        --output-dir "$OUTPUT_DIR" \
        --background "$BACKGROUND" \
        --punchlines "$(echo -e "$PUNCHLINES")"

    echo ""
    echo "Done. Final screenshots in: $OUTPUT_DIR"
    ls -la "$OUTPUT_DIR"/screenshot_*.png 2>/dev/null || echo "(no output files found)"
else
    echo "Skipping composite step (--skip-composite)."
fi
