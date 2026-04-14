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
