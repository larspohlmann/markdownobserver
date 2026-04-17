import AppKit
import SwiftUI

struct ReaderSettingsView: View {
    private var settingsStore: SettingsStore
    @ObservedObject private var notificationNotifier: SystemNotifier

    init(
        settingsStore: SettingsStore,
        notificationNotifier: SystemNotifier = .shared
    ) {
        self.settingsStore = settingsStore
        self.notificationNotifier = notificationNotifier
    }

    var body: some View {
        GeometryReader { geometry in
            let contentWidth = min(max(geometry.size.width - 40, 0), 1040)

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    typographySection
                    themeSection
                    windowLayoutSection
                    changeHighlightingSection
                    notificationsSection
                }
                .frame(width: contentWidth, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 780, minHeight: 720)
        .task {
            notificationNotifier.refreshNotificationStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            notificationNotifier.refreshNotificationStatus()
        }
    }

    private var typographySection: some View {
        SettingsSectionContainer(title: "Typography") {
            HStack(spacing: 14) {
                Text("Font size")
                    .foregroundStyle(.secondary)
                    .frame(width: 120, alignment: .leading)

                Slider(
                    value: Binding(
                        get: { settingsStore.currentSettings.baseFontSize },
                        set: { settingsStore.updateBaseFontSize($0) }
                    ),
                    in: 10...48,
                    step: 1
                )
                .frame(maxWidth: 440)
                .accessibilityLabel("Font size")

                Text("\(Int(settingsStore.currentSettings.baseFontSize)) pt")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 58, alignment: .trailing)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var themeSection: some View {
        SettingsSectionContainer(title: "Theme") {
            HStack(spacing: 14) {
                Text("App theme")
                    .foregroundStyle(.secondary)
                    .frame(width: 120, alignment: .leading)

                Spacer(minLength: 12)
                Picker("App theme", selection: Binding(
                    get: { settingsStore.currentSettings.appAppearance },
                    set: { settingsStore.updateAppAppearance($0) }
                )) {
                    ForEach(AppAppearance.allCases, id: \.self) { appearance in
                        Text(appearance.displayName).tag(appearance)
                    }
                }
                .labelsHidden()
                .frame(width: 190)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ThemeSelectorView(settingsStore: settingsStore)
                .frame(maxWidth: .infinity, minHeight: 420, alignment: .leading)
        }
    }

    private var windowLayoutSection: some View {
        SettingsSectionContainer(title: "Window Layout") {
            HStack(spacing: 14) {
                Text("Open multiple files in")
                    .foregroundStyle(.secondary)
                    .frame(width: 180, alignment: .leading)

                Spacer(minLength: 12)
                Picker("Open multiple files in", selection: Binding(
                    get: { settingsStore.currentSettings.multiFileDisplayMode },
                    set: { updateMultiFileDisplayMode($0) }
                )) {
                    ForEach(MultiFileDisplayMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .labelsHidden()
                .frame(width: 190)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(layoutHelpText)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var changeHighlightingSection: some View {
        SettingsSectionContainer(title: "Change Highlighting") {
            HStack(spacing: 14) {
                Text("Diff lookback")
                    .foregroundStyle(.secondary)
                    .frame(width: 180, alignment: .leading)

                Spacer(minLength: 12)
                Picker("Diff lookback", selection: Binding(
                    get: { settingsStore.currentSettings.diffBaselineLookback },
                    set: { settingsStore.updateDiffBaselineLookback($0) }
                )) {
                    ForEach(DiffBaselineLookback.allCases) { lookback in
                        Text(lookback.displayName).tag(lookback)
                    }
                }
                .labelsHidden()
                .frame(width: 190)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("How far back MarkdownObserver looks for the previous version of a file when highlighting changes. Longer values show more accumulated changes, which works better with AI tools that make many incremental edits.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var notificationsSection: some View {
        SettingsSectionContainer(title: "Notifications") {
            HStack(spacing: 14) {
                Text("System notifications")
                    .foregroundStyle(.secondary)
                    .frame(width: 180, alignment: .leading)

                Spacer(minLength: 12)

                Toggle("System notifications", isOn: Binding(
                    get: { settingsStore.currentSettings.notificationsEnabled },
                    set: { updateNotificationsEnabled($0) }
                ))
                .labelsHidden()
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            NotificationStatusCard(status: notificationNotifier.notificationStatus)

            HStack(spacing: 10) {
                if notificationNotifier.notificationStatus.canRequestAuthorization {
                    Button("Allow Notifications") {
                        notificationNotifier.requestAuthorizationIfNeeded()
                    }
                    .buttonStyle(.borderedProminent)
                }

                Button("Open Notification Settings") {
                    notificationNotifier.openSystemNotificationSettings()
                }

                Button("Send Background Test") {
                    notificationNotifier.sendTestNotification()
                }
                .disabled(!settingsStore.currentSettings.notificationsEnabled)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("Test notifications fire after 5 seconds so you can switch to another app and verify background delivery.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var layoutHelpText: String {
        SettingsGuidance.layoutHelpText(selectedMode: settingsStore.currentSettings.multiFileDisplayMode)
    }

    private func updateMultiFileDisplayMode(_ mode: MultiFileDisplayMode) {
        settingsStore.updateMultiFileDisplayMode(mode)
    }

    private func updateNotificationsEnabled(_ isEnabled: Bool) {
        settingsStore.updateNotificationsEnabled(isEnabled)
        guard isEnabled else {
            notificationNotifier.refreshNotificationStatus()
            return
        }

        notificationNotifier.requestAuthorizationIfNeeded()
    }
}

private struct SettingsSectionContainer<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))

            VStack(alignment: .leading, spacing: 10) {
                content()
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.22), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct NotificationStatusCard: View {
    let status: NotificationStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(status.title, systemImage: iconName)
                .font(.headline)

            Text(status.message)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var iconName: String {
        switch status.authorizationState {
        case .authorized:
            return status.alertsEnabled ? "checkmark.circle.fill" : "bell.slash.fill"
        case .denied:
            return "bell.slash.fill"
        case .notDetermined:
            return "bell.badge"
        case .unknown:
            return "questionmark.circle"
        }
    }
}

extension Color {
    init?(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard cleaned.count == 6,
              let int = Int(cleaned, radix: 16) else {
            return nil
        }

        let r = Double((int >> 16) & 0xFF) / 255.0
        let g = Double((int >> 8) & 0xFF) / 255.0
        let b = Double(int & 0xFF) / 255.0
        self = Color(red: r, green: g, blue: b)
    }

}

struct ThemePreviewCard: View {
    let settings: ReaderSettings

    private var theme: Theme {
        Theme.theme(for: settings.readerTheme)
    }

    private var syntaxPalette: SyntaxThemePreviewPalette {
        let themeDefinition = settings.readerTheme.themeDefinition
        if let themePalette = themeDefinition.syntaxPreviewPalette, themeDefinition.providesSyntaxHighlighting {
            return themePalette
        }
        return settings.syntaxTheme.previewPalette
    }

    private var effectiveBlockBackgroundHex: String {
        SyntaxBackgroundAdjuster.effectiveBlockBackgroundHex(
            theme: settings.readerTheme.themeDefinition,
            syntaxTheme: settings.syntaxTheme
        )
    }

    private var readerColorSamples: [ThemePreviewColorSample] {
        ThemePreviewReaderTextExamples.reader(theme: theme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Live preview")
                .font(.headline)
            Text("Heading")
                .font(.system(size: max(settings.baseFontSize + 4, 14), weight: .semibold))
                .foregroundStyle(color(theme.foregroundHex))

            Text("Body text in the selected reader theme.")
                .font(.system(size: settings.baseFontSize))
                .foregroundStyle(color(theme.secondaryForegroundHex))

            readerTextExamples

            RoundedRectangle(cornerRadius: 8)
                .fill(color(effectiveBlockBackgroundHex))
                .frame(maxWidth: .infinity, minHeight: 154, alignment: .topLeading)
                .overlay(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(codeSample.enumerated()), id: \.offset) { _, line in
                            line
                        }
                    }
                    .font(.system(size: max(settings.baseFontSize - 2, 10), design: .monospaced))
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(color(syntaxPalette.blockBorderHex), lineWidth: 1)
                )
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color(theme.backgroundHex))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(color(theme.borderHex), lineWidth: 1)
        )
    }

    private func color(_ hex: String) -> Color {
        Color(hex: hex) ?? .primary
    }

    private var codeSample: [Text] {
        [
            token("// Export a short reading list", hex: syntaxPalette.commentHex),
            token("struct ", hex: syntaxPalette.keywordHex)
                + token("ReadingListExporter", hex: syntaxPalette.titleHex)
                + token(" {"),
            token("    static func ", hex: syntaxPalette.keywordHex)
                + token("export", hex: syntaxPalette.titleHex)
                + token("(limit: ")
                + token("Int", hex: syntaxPalette.builtInHex)
                + token(" = ")
                + token("3", hex: syntaxPalette.numberHex)
                + token(") -> ")
                + token("String", hex: syntaxPalette.builtInHex)
                + token(" {"),
            token("        let ", hex: syntaxPalette.keywordHex)
                + token("files")
                + token(" = [")
                + token("\"roadmap.md\"", hex: syntaxPalette.stringHex)
                + token(", ")
                + token("\"notes.md\"", hex: syntaxPalette.stringHex)
                + token(", ")
                + token("\"release.md\"", hex: syntaxPalette.stringHex)
                + token("]"),
            token("        return ", hex: syntaxPalette.keywordHex)
                + token("files")
                + token(".")
                + token("prefix", hex: syntaxPalette.builtInHex)
                + token("(limit).")
                + token("joined", hex: syntaxPalette.builtInHex)
                + token("(separator: ")
                + token("\"\\n\"", hex: syntaxPalette.stringHex)
                + token(")"),
            token("    }"),
            token("}")
        ]
    }

    private func token(_ value: String, hex: String? = nil) -> Text {
        Text(value).foregroundStyle(color(hex ?? syntaxPalette.blockTextHex))
    }

    private var readerTextExamples: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Reader text colors")
                .font(.caption)
                .foregroundStyle(color(theme.secondaryForegroundHex))

            ForEach(readerColorSamples) { sample in
                Text(sample.text)
                    .font(sample.role == .heading
                          ? .system(size: max(settings.baseFontSize + 1, 13), weight: .semibold)
                          : .system(size: max(settings.baseFontSize - 1, 11)))
                    .foregroundStyle(color(sample.hex))
            }
        }
    }
}

struct ThemePreviewColorSample: Equatable, Identifiable, Sendable {
    let text: String
    let role: ThemePreviewTextRole
    let hex: String

    var id: String {
        role.rawValue
    }
}

enum ThemePreviewTextRole: String, Sendable {
    case heading
    case body
    case secondary
    case link
}

enum ThemePreviewReaderTextExamples {
    static func reader(theme: Theme) -> [ThemePreviewColorSample] {
        [
            ThemePreviewColorSample(text: "Heading accent sample", role: .heading, hex: theme.h1Hex ?? theme.foregroundHex),
            ThemePreviewColorSample(text: "Primary body sample text", role: .body, hex: theme.foregroundHex),
            ThemePreviewColorSample(text: "Secondary helper sample", role: .secondary, hex: theme.secondaryForegroundHex),
            ThemePreviewColorSample(text: "Link sample text", role: .link, hex: theme.linkHex)
        ]
    }
}
