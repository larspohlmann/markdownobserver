#!/usr/bin/env bash
#
# take-real-screenshots.sh — Capture screenshots using the real project folder
#
# Usage: ./scripts/screenshots/take-real-screenshots.sh [--skip-build] [--only N] [--skip-composite]
#
# Watches the actual MarkdownObserver repo, captures 6 screenshots showing
# real user journeys: exclusion dialog, file selection, rendered plan files,
# change gutters, favorites, and dark mode.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
RAW_DIR="$PROJECT_DIR/screenshots/raw"
OUTPUT_DIR="$PROJECT_DIR/screenshots"
BACKGROUND="$PROJECT_DIR/docs/assets/screenshot_bck.png"
COMPOSITE_SCRIPT="$SCRIPT_DIR/composite.py"
PLAN_FILE="$PROJECT_DIR/plans/177-auto-open-change-indicator.md"

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
[[ -f "$PLAN_FILE" ]] || { echo "Error: Plan file not found at $PLAN_FILE"; exit 1; }

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
echo "App binary: $APP_BINARY"

# --- Settings management ---
backup_settings() {
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
    defaults delete "$BUNDLE_ID" NSQuitAlwaysKeepsWindows 2>/dev/null || true
    defaults delete "$BUNDLE_ID" ApplePersistenceIgnoreState 2>/dev/null || true
    # Restore the plan file if backup exists
    if [[ -f "$PLAN_FILE.screenshot-backup" ]]; then
        mv "$PLAN_FILE.screenshot-backup" "$PLAN_FILE"
        echo "Plan file restored."
    fi
}

write_theme_settings() {
    local reader_theme="$1"
    local syntax_theme="$2"
    local app_appearance="$3"

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
        'sidebarSortMode': 'openOrder',
        'favoriteWatchedFolders': [],
        'recentWatchedFolders': [],
        'recentManuallyOpenedFiles': [],
        'trustedImageFolders': []
    }

settings['readerTheme'] = '$reader_theme'
settings['syntaxTheme'] = '$syntax_theme'
settings['appAppearance'] = '$app_appearance'
settings['autoRefreshOnExternalChange'] = True

json_bytes = json.dumps(settings, ensure_ascii=False).encode('utf-8')
hex_str = json_bytes.hex()
subprocess.check_call(['defaults', 'write', bundle_id, key, '-data', hex_str])
"
}

# --- App control ---
clean_saved_state() {
    defaults write "$BUNDLE_ID" NSQuitAlwaysKeepsWindows -bool false 2>/dev/null || true
    defaults write "$BUNDLE_ID" ApplePersistenceIgnoreState -bool true 2>/dev/null || true
    rm -rf "$HOME/Library/Saved Application State/${BUNDLE_ID}.savedState" 2>/dev/null || true
    rm -rf "$HOME/Library/Containers/${BUNDLE_ID}/Data/Library/Saved Application State/${BUNDLE_ID}.savedState" 2>/dev/null || true
    find "$HOME/Library/Containers/${BUNDLE_ID}" -name "*.savedState" -type d -exec rm -rf {} + 2>/dev/null || true
}

dismiss_crash_dialog() {
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
    pkill -f "MarkdownObserver" 2>/dev/null || true
    sleep 0.5
    clean_saved_state
}

# --- Window helpers ---
WINDOW_ID_HELPER="$SCRIPT_DIR/get-window-id"

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
            tell process \"MarkdownObserver\"
                set frontmost to true
                delay 0.3
                set win to window 1
                set position of win to {100, 100}
                set size of win to {$width, $height}
            end tell
        end tell
    " 2>/dev/null
}

shrink_window_height() {
    # Reduce window height slightly from its default size
    osascript -e '
        tell application "System Events"
            tell process "MarkdownObserver"
                set frontmost to true
                delay 0.3
                set win to window 1
                set winSize to size of win
                set currentWidth to item 1 of winSize
                set currentHeight to item 2 of winSize
                set newHeight to round (currentHeight * 0.94)
                set size of win to {currentWidth, newHeight}
            end tell
        end tell
    ' 2>/dev/null
}

# --- Folder selection via NSOpenPanel ---
# The env var approach (MINIMARK_UI_TEST_WATCH_FOLDER_PATH) doesn't grant
# security-scoped access, so the directory scan fails. Using the real
# NSOpenPanel flow (Cmd+Shift+G) ensures the app gets proper access.
open_folder_via_picker() {
    local folder_path="$1"
    echo "    Clicking Watch Folder button..."
    # The button has accessibilityIdentifier "folder-watch-toolbar-button" in the native NSToolbar
    click_by_identifier "folder-watch-toolbar-button"
    sleep 1

    echo "    Navigating to folder via Cmd+Shift+G..."
    osascript -e "
        tell application \"System Events\"
            tell process \"MarkdownObserver\"
                set frontmost to true
                delay 0.5
                keystroke \"g\" using {command down, shift down}
                delay 1.5
                keystroke \"$folder_path\"
                delay 0.5
                keystroke return
                delay 2
                -- Click the Open button explicitly instead of pressing Return
                try
                    click button \"Open\" of sheet 1 of window 1
                on error
                    -- Fallback: try the front sheet/panel
                    try
                        click button \"Open\" of window 1
                    on error
                        keystroke return
                    end try
                end try
            end tell
        end tell
    " 2>/dev/null
    echo "    Folder selected."
}

click_open_existing_and_include_subfolders() {
    osascript -l JavaScript -e '
        const se = Application("System Events");
        const proc = se.processes["MarkdownObserver"];
        proc.frontmost = true;
        delay(0.3);
        const win = proc.windows[0];
        var radios = [];
        function findRadios(el) {
            try {
                if (el.role() === "AXRadioButton" || el.role() === "AXCheckBox") {
                    radios.push(el);
                }
            } catch(e) {}
            try {
                var kids = el.uiElements();
                for (var i = 0; i < kids.length; i++) findRadios(kids[i]);
            } catch(e) {}
        }
        findRadios(win);
        // [Open Existing, Watch Only, Selected Folder, Include Subfolders]
        if (radios.length >= 4) {
            radios[0].actions["AXPress"].perform();
            delay(0.3);
            radios[3].actions["AXPress"].perform();
            "clicked (" + radios.length + " radios)";
        } else {
            "found only " + radios.length + " radios";
        }
    ' 2>/dev/null
}

click_choose_subdirectories_to_deactivate() {
    osascript -l JavaScript -e '
        const se = Application("System Events");
        const proc = se.processes["MarkdownObserver"];
        proc.frontmost = true;
        delay(0.3);
        const win = proc.windows[0];
        function findBtn(el) {
            try {
                if (el.role() === "AXButton") {
                    var t = el.title ? el.title() : "";
                    if (t.indexOf("subdirectories") !== -1 || t.indexOf("deactivate") !== -1) {
                        el.actions["AXPress"].perform();
                        return "clicked";
                    }
                }
            } catch(e) {}
            try {
                var kids = el.uiElements();
                for (var i = 0; i < kids.length; i++) {
                    var r = findBtn(kids[i]);
                    if (r === "clicked") return r;
                }
            } catch(e) {}
            return "not_found";
        }
        findBtn(win);
    ' 2>/dev/null
}

toggle_directory_in_exclusion_dialog() {
    local dir_name="$1"
    # Toggle a specific directory's checkbox in the exclusion dialog.
    # The toggles are in a list; we find the one next to the target name.
    osascript -l JavaScript -e "
        const se = Application('System Events');
        const proc = se.processes['MarkdownObserver'];
        proc.frontmost = true;
        delay(0.3);
        const win = proc.windows[0];

        // Collect all text elements and toggles in the list
        var toggles = [];
        var texts = [];
        function collect(el) {
            try {
                var role = el.role();
                if (role === 'AXCheckBox' || role === 'AXSwitch') {
                    toggles.push({el: el, y: el.position()[1]});
                }
                if (role === 'AXStaticText') {
                    var val = el.value ? el.value() : '';
                    if (val === '$dir_name') {
                        texts.push({el: el, y: el.position()[1]});
                    }
                }
            } catch(e) {}
            try {
                var kids = el.uiElements();
                for (var i = 0; i < kids.length; i++) collect(kids[i]);
            } catch(e) {}
        }
        collect(win);

        // Find toggle closest to the target text's y position
        if (texts.length > 0) {
            var targetY = texts[0].y;
            var best = null;
            var bestDist = 99999;
            for (var i = 0; i < toggles.length; i++) {
                var d = Math.abs(toggles[i].y - targetY);
                if (d < bestDist) {
                    bestDist = d;
                    best = toggles[i].el;
                }
            }
            if (best && bestDist < 20) {
                best.actions['AXPress'].perform();
                'toggled ' + '$dir_name';
            } else {
                'no close toggle for $dir_name (best dist: ' + bestDist + ')';
            }
        } else {
            'text $dir_name not found';
        }
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

# --- UI automation helpers ---
click_edited_gutter_pill() {
    osascript -e '
        tell application "System Events"
            tell process "MarkdownObserver"
                set frontmost to true
                delay 0.3
            end tell
        end tell
    ' 2>/dev/null

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

select_sidebar_document() {
    local target_doc="$1"
    echo "    Selecting sidebar document: $target_doc"
    # Use File > Recent Opened Files menu to switch documents.
    # This is more reliable than sidebar interaction with 81+ files.
    osascript -e "
        tell application \"System Events\"
            tell process \"MarkdownObserver\"
                set frontmost to true
                delay 0.3
                click menu item \"${target_doc}.md\" of menu of menu item \"Recent Opened Files\" of menu \"File\" of menu bar 1
            end tell
        end tell
    " 2>/dev/null && echo "selected via menu" || echo "not_found"
}

click_button_by_title() {
    local title="$1"
    osascript -e "
        tell application \"System Events\"
            tell process \"MarkdownObserver\"
                set frontmost to true
                delay 0.3
                tell window 1
                    set allButtons to every button
                    repeat with b in allButtons
                        try
                            if title of b contains \"$title\" then
                                click b
                                return \"clicked\"
                            end if
                        end try
                        try
                            if description of b contains \"$title\" then
                                click b
                                return \"clicked\"
                            end if
                        end try
                    end repeat
                end tell
            end tell
        end tell
        return \"not_found\"
    " 2>/dev/null || echo "not_found"
}

click_menu_item() {
    local menu_name="$1"
    local item_name="$2"
    osascript -e "
        tell application \"System Events\"
            tell process \"MarkdownObserver\"
                set frontmost to true
                delay 0.3
                click menu item \"$item_name\" of menu \"$menu_name\" of menu bar 1
            end tell
        end tell
    " 2>/dev/null || echo "menu_failed"
}

press_return() {
    osascript -e '
        tell application "System Events"
            tell process "MarkdownObserver"
                set frontmost to true
                delay 0.3
                keystroke return
            end tell
        end tell
    ' 2>/dev/null
}

# --- Favorites setup ---
setup_favorites() {
    echo "Setting up favorites in settings..."
    local container_home="$HOME/Library/Containers/$BUNDLE_ID/Data"

    # Create realistic project folders for favorites
    local fav_folders=(
        "$container_home/api-gateway"
        "$container_home/mobile-app"
        "$container_home/shared-models"
    )
    for folder in "${fav_folders[@]}"; do
        rm -rf "$folder"
        mkdir -p "$folder"
        echo "# $(basename "$folder")" > "$folder/README.md"
    done

    # Launch the app to watch each folder briefly to populate recents with bookmarks
    for folder in "${fav_folders[@]}"; do
        clean_saved_state
        open --env MINIMARK_UI_TEST_WATCH_FOLDER_PATH="$folder" \
            -a "$APP_PATH" \
            --args -minimark-ui-test -minimark-auto-start-watch-folder
        sleep 2
        osascript -e 'tell application "MarkdownObserver" to quit' 2>/dev/null || true
        sleep 1
        pkill -f "MarkdownObserver" 2>/dev/null || true
        sleep 0.5
    done

    # Promote recents to favorites
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
    echo "Favorites setup complete."
}

# --- Plan file modification for gutter screenshot ---
create_modified_plan_file() {
    # Creates a modified version of the plan file that will produce
    # green (added), amber (edited), and red (deleted) gutter indicators
    # when it replaces the original.
    local output="$1"

    python3 -c "
import sys

with open('$PLAN_FILE', 'r') as f:
    lines = f.readlines()

# Modifications in the first few lines to showcase all 3 gutter types:
# - Amber (edited): change the title
# - Green (added): insert new lines after title
# - Red (deleted): remove '## Problem' heading
modified = []
for i, line in enumerate(lines):
    # Line 0: Edit the title (amber gutter)
    if i == 0:
        modified.append('# Fix #177: Show change indicator for auto-opened files\n')
        # Insert new lines after title (green gutter — added)
        modified.append('\n')
        modified.append('> **Status:** Fixed | **Priority:** High\n')
        modified.append('\n')
        continue

    # Line 1: keep blank line
    if i == 1:
        modified.append(line)
        continue

    # Line 2: delete '## Problem' heading (red gutter — deleted)
    if i == 2:
        continue

    # Line 3: delete blank line after heading (red gutter — deleted)
    if i == 3:
        continue

    # Line 4: Edit the description (amber gutter — edited)
    if i == 4:
        modified.append('When a watched folder detects a new markdown file and the app auto-opens it, the sidebar now shows a green change indicator. Previously there was no visual cue.\n')
        continue

    # Keep remaining lines unchanged
    modified.append(line)

with open('$output', 'w') as f:
    f.writelines(modified)
print('Modified plan file created')
"
}

# --- JXA helpers for clicking buttons by AXIdentifier ---
click_by_identifier() {
    local target_id="$1"
    local max_depth="${2:-12}"
    osascript -l JavaScript -e "
        var se = Application('System Events');
        var proc = se.processes['MarkdownObserver'];
        proc.frontmost = true;
        delay(0.3);
        var win = proc.windows[0];
        var found = false;
        function findById(el, targetId, depth) {
            if (depth > $max_depth || found) return null;
            try {
                var ident = null;
                try { ident = el.attributes.byName('AXIdentifier').value(); } catch(e) {}
                if (ident === targetId) {
                    el.actions['AXPress'].perform();
                    found = true;
                    return 'clicked: ' + targetId;
                }
            } catch(e) {}
            // At window level, also search toolbar items
            if (depth === 0) {
                try {
                    var toolbars = el.toolbars();
                    for (var t = 0; t < toolbars.length; t++) {
                        var r = findById(toolbars[t], targetId, depth + 1);
                        if (r) return r;
                    }
                } catch(e) {}
            }
            try {
                var kids = el.uiElements();
                for (var i = 0; i < kids.length; i++) {
                    var r = findById(kids[i], targetId, depth + 1);
                    if (r) return r;
                }
            } catch(e) {}
            return null;
        }
        findById(win, '$target_id', 0);
    " 2>/dev/null || echo "not_found"
}

click_button_by_description() {
    local desc_text="$1"
    osascript -l JavaScript -e "
        const se = Application('System Events');
        const proc = se.processes['MarkdownObserver'];
        proc.frontmost = true;
        delay(0.3);
        const win = proc.windows[0];
        function findBtn(el, target, depth) {
            if (depth > 15) return null;
            try {
                if (el.role() === 'AXButton') {
                    var d = ''; try { d = el.description(); } catch(e) {}
                    var lbl = ''; try { lbl = el.attributes.byName('AXLabel').value(); } catch(e) {}
                    var ident = ''; try { ident = el.attributes.byName('AXIdentifier').value(); } catch(e) {}
                    if (d === target || lbl === target || ident === target) {
                        el.actions['AXPress'].perform();
                        return 'clicked';
                    }
                }
            } catch(e) {}
            // At window level, also search toolbar
            if (depth === 0) {
                try {
                    var toolbars = el.toolbars();
                    for (var t = 0; t < toolbars.length; t++) {
                        var r = findBtn(toolbars[t], target, depth + 1);
                        if (r) return r;
                    }
                } catch(e) {}
            }
            try {
                var kids = el.uiElements();
                for (var i = 0; i < kids.length; i++) {
                    var r = findBtn(kids[i], target, depth + 1);
                    if (r) return r;
                }
            } catch(e) {}
            return null;
        }
        findBtn(win, '$desc_text', 0);
    " 2>/dev/null || echo "not_found"
}

click_button_by_title_jxa() {
    local title_text="$1"
    osascript -l JavaScript -e "
        const se = Application('System Events');
        const proc = se.processes['MarkdownObserver'];
        proc.frontmost = true;
        delay(0.3);
        const win = proc.windows[0];
        function findBtn(el, text, depth) {
            if (depth > 15) return null;
            try {
                if (el.role() === 'AXButton') {
                    var t = el.title ? el.title() : '';
                    var d = el.description ? el.description() : '';
                    if (t.indexOf(text) !== -1 || d.indexOf(text) !== -1) {
                        el.actions['AXPress'].perform();
                        return 'clicked: ' + t;
                    }
                }
            } catch(e) {}
            try {
                var kids = el.uiElements();
                for (var i = 0; i < kids.length; i++) {
                    var r = findBtn(kids[i], text, depth + 1);
                    if (r) return r;
                }
            } catch(e) {}
            return null;
        }
        findBtn(win, '$title_text', 0);
    " 2>/dev/null || echo "not_found"
}

click_popup_by_value() {
    # Click a popup button with the given value, in a specific window (by title substring).
    # After clicking, press arrow key (up or down) then Return to select an item.
    local window_title="$1"
    local popup_value="$2"
    local arrow_direction="$3"   # "up" or "down"
    local arrow_count="${4:-1}"

    osascript -l JavaScript -e "
        const se = Application('System Events');
        const proc = se.processes['MarkdownObserver'];
        const wins = proc.windows();
        for (var w = 0; w < wins.length; w++) {
            if (wins[w].title().indexOf('$window_title') !== -1) {
                function findPopup(el, val, depth) {
                    if (depth > 10) return null;
                    try {
                        if (el.role() === 'AXPopUpButton' && el.value() === val) {
                            el.actions['AXPress'].perform();
                            return 'clicked';
                        }
                    } catch(e) {}
                    try {
                        var kids = el.uiElements();
                        for (var i = 0; i < kids.length; i++) {
                            var r = findPopup(kids[i], val, depth + 1);
                            if (r) return r;
                        }
                    } catch(e) {}
                    return null;
                }
                findPopup(wins[w], '$popup_value', 0);
                break;
            }
        }
    " 2>/dev/null
    sleep 0.3

    # Press arrow key the specified number of times
    local key_code
    if [[ "$arrow_direction" == "up" ]]; then
        key_code=126
    else
        key_code=125
    fi
    for (( i=0; i<arrow_count; i++ )); do
        osascript -e "tell application \"System Events\" to tell process \"MarkdownObserver\" to key code $key_code" 2>/dev/null
        sleep 0.1
    done
    osascript -e 'tell application "System Events" to tell process "MarkdownObserver" to keystroke return' 2>/dev/null
}

# --- Main capture flow ---
# ALL 6 screenshots are captured in a single app session. The app is never
# quit or restarted between shots. Theme switching for screenshot 6 is done
# via the Settings UI while the app is running.

backup_settings
trap restore_settings EXIT

echo ""
echo "Starting real-project screenshot capture..."
echo "============================================"

# --- Setup ---
quit_app
setup_favorites
write_theme_settings "darkGreyOnLightGrey" "github" "light"
clean_saved_state

echo "    Launching app..."
open --env MINIMARK_SCREENSHOT_OPEN_EXCLUSION="true" \
    --env MINIMARK_SCREENSHOT_EXCLUDED_PATHS=".git,profiling" \
    --env MINIMARK_SCREENSHOT_EXPANDED_PATHS="minimark,scripts" \
    --env MINIMARK_SCREENSHOT_SELECT_FILE="177-auto-open-change-indicator.md" \
    -a "$APP_PATH" \
    --args -minimark-ui-test
sleep 2
dismiss_crash_dialog
sleep 1

WID=$(wait_for_window 15 || true)
if [[ -z "$WID" ]]; then
    echo "    ERROR: Window not found"
    exit 1
fi

echo "    Resizing window..."
shrink_window_height
sleep 1

# ========================================
# Phase 1: Exclusion dialog (Screenshot 1)
# ========================================
echo ""
echo "--- Screenshot 1: Exclusion dialog ---"

# Use NSOpenPanel to select the project folder (grants security-scoped access)
open_folder_via_picker "$PROJECT_DIR"
sleep 1

# Click "Open Existing" + "Include Subfolders" in the watch options sheet
echo "    Setting Open Existing + Include Subfolders..."
click_open_existing_and_include_subfolders
sleep 1

# The directory scan starts automatically after selecting "Include Subfolders".
# With >256 subdirs and MINIMARK_SCREENSHOT_OPEN_EXCLUSION=true, the exclusion
# dialog auto-opens on top of the watch options sheet. Wait for it.
echo "    Waiting for exclusion dialog to appear..."
sleep 2

if [[ -z "$ONLY_SHOT" || "$ONLY_SHOT" == "1" ]]; then
    RAW_FILE="$RAW_DIR/screenshot_1_raw.png"
    echo "    Capturing screenshot 1..."
    capture_window "$RAW_FILE"
    echo "    Saved: $RAW_FILE"
fi

# ========================================
# Phase 2: Confirm exclusion → Start Watching → file chooser (Screenshot 2)
# ========================================
echo ""
echo "--- Screenshot 2: File selection dialog ---"

# Confirm the exclusion dialog's "Start Watching" button
echo "    Confirming exclusion dialog..."
click_by_identifier "folder-watch-dialog-start-button"
sleep 1

# The watch options sheet is now visible again. Click its "Start Watching" button.
echo "    Clicking Start Watching in watch options sheet..."
click_by_identifier "folder-watch-start-button"
sleep 2

if [[ -z "$ONLY_SHOT" || "$ONLY_SHOT" == "2" ]]; then
    RAW_FILE="$RAW_DIR/screenshot_2_raw.png"
    echo "    Capturing screenshot 2..."
    capture_window "$RAW_FILE"
    echo "    Saved: $RAW_FILE"
fi

# ========================================
# Phase 3: Confirm file chooser → rendered plan file (Screenshot 3)
# ========================================
echo ""
echo "--- Screenshot 3: Plan file rendered ---"

# Click "Open XX Files" in the file chooser dialog via AXIdentifier
echo "    Clicking Open Files..."
click_by_identifier "file-selection-open-button"
sleep 2

# The app auto-selects the plan file via MINIMARK_SCREENSHOT_SELECT_FILE env var
echo "    Waiting for plan file to render..."
sleep 3

if [[ -z "$ONLY_SHOT" || "$ONLY_SHOT" == "3" ]]; then
    RAW_FILE="$RAW_DIR/screenshot_3_raw.png"
    echo "    Capturing screenshot 3..."
    capture_window "$RAW_FILE"
    echo "    Saved: $RAW_FILE"
fi

# ========================================
# Phase 3b: Table of Contents overlay (Screenshot 3b)
# ========================================
echo ""
echo "--- Screenshot 3b: Table of Contents ---"

sleep 2
echo "    Opening TOC..."
click_by_identifier "toc-button"
sleep 2

if [[ -z "$ONLY_SHOT" || "$ONLY_SHOT" == "3b" ]]; then
    RAW_FILE="$RAW_DIR/screenshot_3b_raw.png"
    echo "    Capturing screenshot 3b..."
    capture_window "$RAW_FILE"
    echo "    Saved: $RAW_FILE"
fi

# Close TOC before continuing
echo "    Closing TOC..."
click_by_identifier "toc-button"
sleep 0.5

# ========================================
# Phase 4: External modification → gutters (Screenshot 4)
# ========================================
echo ""
echo "--- Screenshot 4: Change gutters ---"

echo "    Backing up plan file..."
cp "$PLAN_FILE" "$PLAN_FILE.screenshot-backup"

echo "    Creating modified version for gutter demo..."
MODIFIED_PLAN=$(mktemp)
create_modified_plan_file "$MODIFIED_PLAN"

echo "    Applying external modification..."
cp "$MODIFIED_PLAN" "$PLAN_FILE"
rm -f "$MODIFIED_PLAN"

echo "    Waiting for gutter rendering..."
sleep 2

echo "    Expanding edited gutter pill..."
click_edited_gutter_pill
sleep 1

if [[ -z "$ONLY_SHOT" || "$ONLY_SHOT" == "4" ]]; then
    RAW_FILE="$RAW_DIR/screenshot_4_raw.png"
    echo "    Capturing screenshot 4..."
    capture_window "$RAW_FILE"
    echo "    Saved: $RAW_FILE"
fi

# Restore plan file
echo "    Restoring plan file..."
mv "$PLAN_FILE.screenshot-backup" "$PLAN_FILE"

# ========================================
# Phase 5: Edit Favorites dialog (Screenshot 5)
# ========================================
echo ""
echo "--- Screenshot 5: Edit Favorites ---"

# Wait for file restoration to re-render
sleep 2

# Click the "Watch menu" chevron button (identifier: "chevron.down")
echo "    Opening Watch menu..."
click_by_identifier "chevron.down"
sleep 1

# Click "Edit Favorites..." button (identifier: "edit-favorites-button")
echo "    Clicking Edit Favorites..."
click_by_identifier "edit-favorites-button"
sleep 1

if [[ -z "$ONLY_SHOT" || "$ONLY_SHOT" == "5" ]]; then
    RAW_FILE="$RAW_DIR/screenshot_5_raw.png"
    echo "    Capturing screenshot 5..."
    capture_window "$RAW_FILE"
    echo "    Saved: $RAW_FILE"
fi

# ========================================
# Phase 6: Dark mode via Settings UI (Screenshot 6)
# ========================================
echo ""
echo "--- Screenshot 6: Dark mode ---"

# Close the Edit Favorites dialog
echo "    Closing Edit Favorites..."
osascript -e '
    tell application "System Events"
        tell process "MarkdownObserver"
            set frontmost to true
            delay 0.3
            key code 53
        end tell
    end tell
' 2>/dev/null
sleep 0.5

# Open Settings with Cmd+,
echo "    Opening Settings..."
osascript -e '
    tell application "System Events"
        tell process "MarkdownObserver"
            set frontmost to true
            delay 0.3
            keystroke "," using command down
        end tell
    end tell
' 2>/dev/null
sleep 1

# Switch App theme: Light → Dark (Down once)
echo "    Switching App theme to Dark..."
click_popup_by_value "Settings" "Light" "down" 1
sleep 0.5

# Switch Reader theme: darkGreyOnLightGrey → lightGreyOnDarkGrey (Down once)
# The popup shows the display name "Light gray background / Dark gray text"
echo "    Switching Reader theme to dark gray..."
click_popup_by_value "Settings" "Light gray background / Dark gray text" "down" 1
sleep 0.5

# Switch Syntax theme: GitHub → Monokai (Up once)
echo "    Switching Syntax theme to Monokai..."
click_popup_by_value "Settings" "GitHub" "up" 1
sleep 1

# Close the Settings window by clicking its close button, then focus the main window
echo "    Closing Settings..."
osascript -e '
    tell application "System Events"
        tell process "MarkdownObserver"
            set frontmost to true
            delay 0.3
            repeat with w in windows
                if title of w contains "Settings" then
                    click button 1 of w
                    exit repeat
                end if
            end repeat
            delay 0.3
            -- Focus the main document window
            repeat with w in windows
                if title of w does not contain "Settings" then
                    perform action "AXRaise" of w
                    exit repeat
                end if
            end repeat
        end tell
    end tell
' 2>/dev/null
sleep 1

if [[ -z "$ONLY_SHOT" || "$ONLY_SHOT" == "6" ]]; then
    RAW_FILE="$RAW_DIR/screenshot_6_raw.png"
    echo "    Capturing screenshot 6..."
    capture_window "$RAW_FILE"
    echo "    Saved: $RAW_FILE"
fi

# ========================================
# Phase 7: Amber Terminal theme (Screenshot 7)
# ========================================
echo ""
echo "--- Screenshot 7: Amber Terminal ---"

# Open Settings with Cmd+,
echo "    Opening Settings..."
osascript -e '
    tell application "System Events"
        tell process "MarkdownObserver"
            set frontmost to true
            delay 0.3
            keystroke "," using command down
        end tell
    end tell
' 2>/dev/null
sleep 1

# Switch Reader theme: "Dark gray background / Light gray text" → "Amber Terminal" (Down 1)
echo "    Switching Reader theme to Amber Terminal..."
click_popup_by_value "Settings" "Dark gray background / Light gray text" "down" 1
sleep 1

# Close the Settings window and focus main window
echo "    Closing Settings..."
osascript -e '
    tell application "System Events"
        tell process "MarkdownObserver"
            set frontmost to true
            delay 0.3
            repeat with w in windows
                if title of w contains "Settings" then
                    click button 1 of w
                    exit repeat
                end if
            end repeat
            delay 0.3
            repeat with w in windows
                if title of w does not contain "Settings" then
                    perform action "AXRaise" of w
                    exit repeat
                end if
            end repeat
        end tell
    end tell
' 2>/dev/null
sleep 1

if [[ -z "$ONLY_SHOT" || "$ONLY_SHOT" == "7" ]]; then
    RAW_FILE="$RAW_DIR/screenshot_7_raw.png"
    echo "    Capturing screenshot 7..."
    capture_window "$RAW_FILE"
    echo "    Saved: $RAW_FILE"
fi

# ========================================
# Phase 8: Newspaper theme (Screenshot 8)
# ========================================
echo ""
echo "--- Screenshot 8: Newspaper ---"

# Open Settings with Cmd+,
echo "    Opening Settings..."
osascript -e '
    tell application "System Events"
        tell process "MarkdownObserver"
            set frontmost to true
            delay 0.3
            keystroke "," using command down
        end tell
    end tell
' 2>/dev/null
sleep 1

# Switch App theme: Dark → Light (Up 1)
echo "    Switching App theme to Light..."
click_popup_by_value "Settings" "Dark" "up" 1
sleep 0.5

# Switch Reader theme: "Amber Terminal" → "Newspaper" (Down 3)
echo "    Switching Reader theme to Newspaper..."
click_popup_by_value "Settings" "Amber Terminal" "down" 3
sleep 0.5

# Switch Syntax theme: Monokai → GitHub (Down 1)
echo "    Switching Syntax theme to GitHub..."
click_popup_by_value "Settings" "Monokai" "down" 1
sleep 1

# Close the Settings window and focus main window
echo "    Closing Settings..."
osascript -e '
    tell application "System Events"
        tell process "MarkdownObserver"
            set frontmost to true
            delay 0.3
            repeat with w in windows
                if title of w contains "Settings" then
                    click button 1 of w
                    exit repeat
                end if
            end repeat
            delay 0.3
            repeat with w in windows
                if title of w does not contain "Settings" then
                    perform action "AXRaise" of w
                    exit repeat
                end if
            end repeat
        end tell
    end tell
' 2>/dev/null
sleep 1

if [[ -z "$ONLY_SHOT" || "$ONLY_SHOT" == "8" ]]; then
    RAW_FILE="$RAW_DIR/screenshot_8_raw.png"
    echo "    Capturing screenshot 8..."
    capture_window "$RAW_FILE"
    echo "    Saved: $RAW_FILE"
fi

# Restore theme settings back to light
write_theme_settings "darkGreyOnLightGrey" "github" "light"

quit_app

echo ""
echo "============================================"
echo "Raw screenshots captured."

# --- Composite ---
if [[ "$SKIP_COMPOSITE" == false ]]; then
    echo ""
    echo "Compositing final screenshots..."

    # Presentation order: 3, 3b, 4, 6, 7, 8, 1, 2, 5
    PUNCHLINES=""
    PUNCHLINES="${PUNCHLINES}1|Your AI agent writes markdown. See it rendered — live.|0|0|top\n"
    PUNCHLINES="${PUNCHLINES}2|Jump to any section. Table of Contents built in.|0|0|top\n"
    PUNCHLINES="${PUNCHLINES}3|Instant diff. Know what your agent changed at a glance.|0|0|top\n"
    PUNCHLINES="${PUNCHLINES}4|Your preferred theme. 10+ syntax highlighting options.|1|0|top\n"
    PUNCHLINES="${PUNCHLINES}5|Terminal aesthetic. Amber on black.|1|0|top\n"
    PUNCHLINES="${PUNCHLINES}6|Classic typography. Read like it's in print.|0|0|top\n"
    PUNCHLINES="${PUNCHLINES}7|Monitor your project — exclude what doesn't matter.|0|0|top\n"
    PUNCHLINES="${PUNCHLINES}8|Too many files? Pick which ones to open.|0|0|top\n"
    PUNCHLINES="${PUNCHLINES}9|One click to resume watching.|0|0|top\n"

    # Map capture numbers to presentation order
    CAPTURE_TO_PRESENTATION=("3:1" "3b:2" "4:3" "6:4" "7:5" "8:6" "1:7" "2:8" "5:9")

    COMPOSITE_RAW_DIR="$RAW_DIR/composite"
    mkdir -p "$COMPOSITE_RAW_DIR"
    for mapping in "${CAPTURE_TO_PRESENTATION[@]}"; do
        IFS=':' read -r cap_num pres_num <<< "$mapping"
        src="$RAW_DIR/screenshot_${cap_num}_raw.png"
        dst="$COMPOSITE_RAW_DIR/screenshot_${pres_num}_raw.png"
        if [[ -f "$src" ]]; then
            cp "$src" "$dst"
        else
            echo "    Warning: Raw screenshot $src not found for slide $pres_num"
        fi
    done

    "$PYTHON" "$COMPOSITE_SCRIPT" \
        --raw-dir "$COMPOSITE_RAW_DIR" \
        --output-dir "$OUTPUT_DIR" \
        --background "$BACKGROUND" \
        --punchlines "$(echo -e "$PUNCHLINES")"

    rm -rf "$COMPOSITE_RAW_DIR"

    echo ""
    echo "Done. Final screenshots in: $OUTPUT_DIR"
    ls -la "$OUTPUT_DIR"/screenshot_*.png 2>/dev/null || echo "(no output files found)"
else
    echo "Skipping composite step (--skip-composite)."
fi

# --- Generate SCREENSHOTS.md ---
echo ""
echo "Generating SCREENSHOTS.md..."

cat > "$PROJECT_DIR/SCREENSHOTS.md" << 'SCREENSHOTS_EOF'
# Screenshots

## Your AI agent writes markdown. See it rendered — live.

![Rendered markdown](screenshots/raw/screenshot_3_raw.png)

## Jump to any section. Table of Contents built in.

![Table of Contents](screenshots/raw/screenshot_3b_raw.png)

## Instant diff. Know what your agent changed at a glance.

![Change gutters](screenshots/raw/screenshot_4_raw.png)

## Your preferred theme. 10+ syntax highlighting options.

![Dark mode](screenshots/raw/screenshot_6_raw.png)

## Terminal aesthetic. Amber on black.

![Amber Terminal](screenshots/raw/screenshot_7_raw.png)

## Classic typography. Read like it's in print.

![Newspaper](screenshots/raw/screenshot_8_raw.png)

## Monitor your project — exclude what doesn't matter.

![Subfolder exclusion](screenshots/raw/screenshot_1_raw.png)

## Too many files? Pick which ones to open.

![File selection](screenshots/raw/screenshot_2_raw.png)

## One click to resume watching.

![Favorites](screenshots/raw/screenshot_5_raw.png)
SCREENSHOTS_EOF

echo "SCREENSHOTS.md generated."
echo ""
echo "All done."
