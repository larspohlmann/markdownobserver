# Theme Selector Redesign — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the picker-based theme section in `ReaderSettingsView` with a three-column layout (reader themes with light/dark tabs | syntax themes | live preview) and a dedicated Apply button.

**Architecture:** A staging view model (`ThemeSelectorViewModel`) holds candidate reader/syntax theme selections. The preview reads from staged values. Apply writes to `ReaderSettingsStore`, which triggers the existing rendering pipeline. The view replaces only the "Theme" `Section` inside the existing `ReaderSettingsView` `Form`.

**Tech Stack:** SwiftUI (macOS), `@Observable`, existing `ReaderSettingsStore` / `ReaderThemeKind` / `SyntaxThemeKind` / `ThemeDefinition` types.

**Worktree:** `.worktrees/theme-selector-redesign` on branch `feature/297-theme-selector-redesign` (based on `develop`).

---

## File Structure

| Action | Path | Responsibility |
|--------|------|---------------|
| Create | `minimark/Views/ThemeSelectorView.swift` | Three-column layout, apply/reset bar, staging wiring |
| Create | `minimark/Views/ThemeCardView.swift` | Reusable card component for list items |
| Modify | `minimark/Views/ReaderSettingsView.swift` | Replace "Theme" section with `ThemeSelectorView`; keep `ThemePreviewCard` for reuse |
| Unchanged | `minimark/Stores/ReaderSettingsStore.swift` | Existing `updateTheme` / `updateSyntaxTheme` called as-is |
| Unchanged | All theme model files | No changes to `ReaderTheme`, `SyntaxTheme`, `ThemeDefinition`, etc. |

---

### Task 1: Create `ThemeCardView`

**Files:**
- Create: `minimark/Views/ThemeCardView.swift`

- [ ] **Step 1: Create the file with the reader theme card**

```swift
import SwiftUI

struct ReaderThemeCard: View {
    let kind: ReaderThemeKind
    let isSelected: Bool
    let action: () -> Void

    private var theme: ReaderTheme {
        ReaderTheme.theme(for: kind)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(hex: theme.backgroundHex) ?? Color(nsColor: .controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color(hex: theme.foregroundHex)?.opacity(0.2) ?? .clear, lineWidth: 1)
                    )
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.displayName)
                        .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.15) : Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 2)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
```

- [ ] **Step 2: Add the syntax theme card in the same file**

```swift
struct SyntaxThemeCard: View {
    let kind: SyntaxThemeKind
    let isSelected: Bool
    let action: () -> Void

    private var palette: SyntaxThemePreviewPalette {
        kind.previewPalette
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(hex: palette.keywordHex) ?? .gray,
                                Color(hex: palette.stringHex) ?? .gray,
                                Color(hex: palette.numberHex) ?? .gray,
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: 28, height: 18)

                Text(kind.displayName)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.15) : Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 2)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
```

- [ ] **Step 3: Build the project to verify compilation**

Run: `xcodebuild -project minimark.xcodeproj -scheme minimark -configuration Debug -destination 'platform=macOS' build`

Expected: Build succeeds (the new views are not yet referenced, but must compile on their own — they reference existing types).

- [ ] **Step 4: Commit**

```bash
git add minimark/Views/ThemeCardView.swift
git commit -m "Add ReaderThemeCard and SyntaxThemeCard components"
```

---

### Task 2: Create `ThemeSelectorView` — staging view with three-column layout

**Files:**
- Create: `minimark/Views/ThemeSelectorView.swift`

This is the largest task. The view manages its own staging state inline (no separate ViewModel file — the state is simple enough to keep in the view, matching the codebase pattern where views like `FolderWatchOptionsSheet.swift` embed a `FolderWatchOptionsViewModel` in the same file).

- [ ] **Step 1: Create `ThemeSelectorView` with staging state and full layout**

```swift
import SwiftUI

private enum ColumnLayout {
    static let selectorRatio: CGFloat = 0.25
    static let previewRatio: CGFloat = 0.50
}

struct ThemeSelectorView: View {
    private let settingsStore: ReaderSettingsStore

    @State private var stagedReaderTheme: ReaderThemeKind
    @State private var stagedSyntaxTheme: SyntaxThemeKind
    @State private var selectedBackgroundTab: BackgroundTab = .light

    init(settingsStore: ReaderSettingsStore) {
        self.settingsStore = settingsStore
        self._stagedReaderTheme = State(initialValue: settingsStore.currentSettings.readerTheme)
        self._stagedSyntaxTheme = State(initialValue: settingsStore.currentSettings.syntaxTheme)
        self._selectedBackgroundTab = State(
            initialValue: settingsStore.currentSettings.readerTheme.isDark ? .dark : .light
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            threeColumnLayout
            applyBar
        }
    }

    // MARK: - Three-Column Layout

    private var threeColumnLayout: some View {
        GeometryReader { geometry in
            let totalWidth = geometry.size.width
            let selectorWidth = totalWidth * ColumnLayout.selectorRatio
            let previewWidth = totalWidth * ColumnLayout.previewRatio

            HStack(spacing: 12) {
                readerThemesColumn
                    .frame(width: selectorWidth)

                syntaxThemesColumn
                    .frame(width: selectorWidth)

                previewColumn
                    .frame(width: previewWidth)
            }
        }
        .frame(minHeight: 340)
    }

    // MARK: - Reader Themes Column

    private var readerThemesColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Reader Theme")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            Picker("Background", selection: $selectedBackgroundTab) {
                Text("Light").tag(BackgroundTab.light)
                Text("Dark").tag(BackgroundTab.dark)
            }
            .pickerStyle(.segmented)
            .onChange(of: selectedBackgroundTab) { _, newTab in
                if !filteredReaderThemes.contains(stagedReaderTheme) {
                    stagedReaderTheme = filteredReaderThemes.first ?? stagedReaderTheme
                }
            }

            ScrollView {
                VStack(spacing: 4) {
                    ForEach(filteredReaderThemes, id: \.self) { kind in
                        ReaderThemeCard(
                            kind: kind,
                            isSelected: kind == stagedReaderTheme
                        ) {
                            stagedReaderTheme = kind
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Syntax Themes Column

    private var syntaxThemesColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Syntax Theme")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            if syntaxHighlightingControlledByTheme {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "paintbrush.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("Syntax highlighting is controlled by the active theme.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(SyntaxThemeKind.allCases, id: \.self) { kind in
                            SyntaxThemeCard(
                                kind: kind,
                                isSelected: kind == stagedSyntaxTheme
                            ) {
                                stagedSyntaxTheme = kind
                            }
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Preview Column

    private var previewColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Preview")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            ThemePreviewCard(settings: previewSettings)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Theme preview")
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Apply Bar

    private var applyBar: some View {
        HStack {
            Text("Current: \(appliedReaderTheme.displayName) + \(appliedSyntaxTheme.displayName)")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            Spacer()

            if WindowAppearanceController.lockedWindowCount > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 9))
                    Text("Some windows locked")
                }
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            }

            if hasUnsavedChanges {
                Text("Unsaved changes")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
            }

            Button("Reset") {
                stagedReaderTheme = appliedReaderTheme
                stagedSyntaxTheme = appliedSyntaxTheme
                selectedBackgroundTab = appliedReaderTheme.isDark ? .dark : .light
            }
            .disabled(!hasUnsavedChanges)

            Button("Apply") {
                applyStagedChanges()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!hasUnsavedChanges)
        }
        .padding(.horizontal, 4)
        .padding(.top, 12)
    }

    // MARK: - Computed

    private var filteredReaderThemes: [ReaderThemeKind] {
        ReaderThemeKind.allCases.filter {
            selectedBackgroundTab == .light ? !$0.isDark : $0.isDark
        }
    }

    private var syntaxHighlightingControlledByTheme: Bool {
        stagedReaderTheme.themeDefinition.providesSyntaxHighlighting
    }

    private var hasUnsavedChanges: Bool {
        stagedReaderTheme != appliedReaderTheme || stagedSyntaxTheme != appliedSyntaxTheme
    }

    private var appliedReaderTheme: ReaderThemeKind {
        settingsStore.currentSettings.readerTheme
    }

    private var appliedSyntaxTheme: SyntaxThemeKind {
        settingsStore.currentSettings.syntaxTheme
    }

    private var previewSettings: ReaderSettings {
        var settings = settingsStore.currentSettings
        settings.readerTheme = stagedReaderTheme
        settings.syntaxTheme = stagedSyntaxTheme
        return settings
    }

    // MARK: - Actions

    private func applyStagedChanges() {
        if stagedReaderTheme != appliedReaderTheme {
            settingsStore.updateTheme(stagedReaderTheme)
        }
        if stagedSyntaxTheme != appliedSyntaxTheme {
            settingsStore.updateSyntaxTheme(stagedSyntaxTheme)
        }
    }
}

private enum BackgroundTab: String, CaseIterable {
    case light
    case dark
}
```

- [ ] **Step 2: Build the project to verify compilation**

Run: `xcodebuild -project minimark.xcodeproj -scheme minimark -configuration Debug -destination 'platform=macOS' build`

Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
git add minimark/Views/ThemeSelectorView.swift
git commit -m "Add ThemeSelectorView with three-column layout and staging"
```

---

### Task 3: Integrate `ThemeSelectorView` into `ReaderSettingsView`

**Files:**
- Modify: `minimark/Views/ReaderSettingsView.swift`

Replace the "Theme" section (lines 37–73) with the new `ThemeSelectorView`. Remove the standalone "Preview" section (lines 136–140) since preview is now embedded in the selector. Remove the now-unused `syntaxHighlightingControlledByTheme` and `lockedWindowsHint` computed properties from `ReaderSettingsView` (they are now handled inside `ThemeSelectorView`).

- [ ] **Step 1: Replace the Theme section and remove the Preview section**

In `ReaderSettingsView.swift`, replace the entire `Section("Theme")` block (lines 37–73) with:

```swift
            Section("Theme") {
                Picker("App theme", selection: Binding(
                    get: { settingsStore.currentSettings.appAppearance },
                    set: { settingsStore.updateAppAppearance($0) }
                )) {
                    ForEach(AppAppearance.allCases, id: \.self) { appearance in
                        Text(appearance.displayName).tag(appearance)
                    }
                }

                ThemeSelectorView(settingsStore: settingsStore)
            }
```

Then remove the `Section("Preview")` block (lines 136–140):

```swift
            Section("Preview") {
                ThemePreviewCard(settings: settingsStore.currentSettings)
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Theme preview")
            }
```

Remove the now-unused `lockedWindowsHint` computed property (lines 153–164) and `syntaxHighlightingControlledByTheme` computed property (lines 166–168).

- [ ] **Step 2: Make `ThemePreviewCard` internal (remove `private`)**

Change `private struct ThemePreviewCard` (line 237) to `struct ThemePreviewCard` so `ThemeSelectorView` can reference it.

- [ ] **Step 3: Build the project**

Run: `xcodebuild -project minimark.xcodeproj -scheme minimark -configuration Debug -destination 'platform=macOS' build`

Expected: Build succeeds.

- [ ] **Step 4: Commit**

```bash
git add minimark/Views/ReaderSettingsView.swift
git commit -m "Integrate ThemeSelectorView into ReaderSettingsView"
```

---

### Task 4: Adjust settings window minimum size

**Files:**
- Modify: `minimark/Views/ReaderSettingsView.swift`

The three-column layout needs more horizontal space than the previous picker-based form.

- [ ] **Step 1: Update the minimum width**

In `ReaderSettingsView`, change the frame modifier from:

```swift
.frame(minWidth: 560, minHeight: 720)
```

to:

```swift
.frame(minWidth: 780, minHeight: 720)
```

- [ ] **Step 2: Build and verify**

Run: `xcodebuild -project minimark.xcodeproj -scheme minimark -configuration Debug -destination 'platform=macOS' build`

Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
git add minimark/Views/ReaderSettingsView.swift
git commit -m "Increase settings window min width for three-column theme layout"
```

---

### Task 5: Build verification and manual smoke test

- [ ] **Step 1: Full clean build**

Run: `xcodebuild -project minimark.xcodeproj -scheme minimark -configuration Debug -destination 'platform=macOS' clean build`

Expected: Build succeeds with no warnings related to the changed files.

- [ ] **Step 2: Run unit tests**

Run: `xcodebuild test -project minimark.xcodeproj -scheme minimark -destination 'platform=macOS' -only-testing:minimarkTests`

Expected: All existing tests pass (no test changes expected — the theme models and store are untouched).

- [ ] **Step 3: Final commit (if any fixups needed)**

If any issues were found and fixed, commit them.

---

## Self-Review

**Spec coverage:**
- Three-column layout (25/25/50): Task 2 (`ColumnLayout` enum) ✓
- Reader themes with light/dark tabs: Task 2 (`BackgroundTab` + filtered list) ✓
- Scrollable lists: Task 2 (`ScrollView` in each column) ✓
- Theme cards with color swatch + name: Task 1 (`ReaderThemeCard`, `SyntaxThemeCard`) ✓
- Preview updates instantly: Task 2 (`previewSettings` computed from staged values) ✓
- Apply/Reset bar with unsaved indicator: Task 2 (`applyBar`) ✓
- Syntax column disabled message: Task 2 (`syntaxHighlightingControlledByTheme` branch) ✓
- Locked windows hint: Task 2 (in `applyBar`) ✓
- Column proportions configurable: Task 2 (`ColumnLayout` enum) ✓

**Placeholder scan:** No TBDs, no "TODO", no "implement later". All code shown in full.

**Type consistency:** `ReaderThemeKind`, `SyntaxThemeKind`, `ReaderSettings`, `ReaderSettingsStore`, `ThemeDefinition`, `SyntaxThemePreviewPalette`, `ThemePreviewCard` — all reference existing types correctly. `BackgroundTab` is defined in Task 2. `ColumnLayout` is defined in Task 2.
