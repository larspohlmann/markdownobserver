import AppKit
import SwiftUI

// MARK: - FolderWatchToolbarButton

struct FolderWatchToolbarButton: View {
    let activeFolderWatch: ReaderFolderWatchSession?
    let isInitialScanInProgress: Bool
    let didInitialScanFail: Bool
    let favoriteWatchedFolders: [ReaderFavoriteWatchedFolder]
    let recentWatchedFolders: [ReaderRecentWatchedFolder]
    let onActivate: () -> Void
    let onStartFavoriteWatch: (ReaderFavoriteWatchedFolder) -> Void
    let onStartRecentFolderWatch: (ReaderRecentWatchedFolder) -> Void
    let onEditFavoriteWatchedFolders: () -> Void
    let onClearRecentWatchedFolders: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isMenuPresented = false

    private enum Metrics {
        static let watchButtonMinWidth: CGFloat = 120
        static let controlHeight: CGFloat = 28
    }

    private var isActive: Bool { activeFolderWatch != nil }

    private var activeButtonColor: Color {
        colorScheme == .dark
            ? Color(red: 0.59, green: 0.49, blue: 1.0)
            : Color(red: 0.34, green: 0.24, blue: 0.71)
    }

    private var backgroundFill: Color {
        isActive ? activeButtonColor.opacity(colorScheme == .dark ? 0.10 : 0.07) : Color.primary.opacity(0.04)
    }

    private var borderColor: Color {
        isActive ? activeButtonColor.opacity(colorScheme == .dark ? 0.20 : 0.18) : Color.primary.opacity(0.08)
    }

    var body: some View {
        HStack(spacing: 0) {
            Button {
                onActivate()
            } label: {
                mainButtonLabel
            }
            .buttonStyle(.plain)
            .help(isActive ? "Watch a different folder" : "Watch Folder...")
            .accessibilityIdentifier("folder-watch-toolbar-button")
            .accessibilityLabel("Watch folder")
            .accessibilityValue(isActive ? "Active" : "Inactive")
            .accessibilityHint("Opens the folder picker for starting folder watch")

            Rectangle()
                .fill(isActive ? activeButtonColor.opacity(0.18) : Color.primary.opacity(0.08))
                .frame(width: 1, height: 16)

            Button {
                isMenuPresented = true
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .frame(width: 22, height: Metrics.controlHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Favorites and recent watches")
            .accessibilityLabel("Watch menu")
            .popover(isPresented: $isMenuPresented, arrowEdge: .bottom) {
                watchMenuPopover
            }
        }
        .foregroundStyle(isActive ? AnyShapeStyle(activeButtonColor) : AnyShapeStyle(.primary))
        .background {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(backgroundFill)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(borderColor, lineWidth: 1)
        }
        .overlay(alignment: .topTrailing) {
            Group {
                if isInitialScanInProgress {
                    ProgressView()
                        .scaleEffect(0.6)
                        .controlSize(.small)
                } else if didInitialScanFail {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.red)
                }
            }
            .offset(x: -4, y: 4)
            .allowsHitTesting(false)
        }
        .fixedSize(horizontal: true, vertical: true)
    }

    private var mainButtonLabel: some View {
        HStack(spacing: 6) {
            Image(systemName: "binoculars.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color(nsColor: .secondaryLabelColor))

            Text(isActive ? "Watching" : "Watch Folder")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
        }
        .frame(minWidth: Metrics.watchButtonMinWidth, alignment: .leading)
        .frame(height: Metrics.controlHeight)
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var watchMenuPopover: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !favoriteWatchedFolders.isEmpty {
                menuSectionHeader("Favorites")

                ForEach(favoriteWatchedFolders) { entry in
                    Button {
                        isMenuPresented = false
                        onStartFavoriteWatch(entry)
                    } label: {
                        Label {
                            Text(entry.name)
                                .lineLimit(1)
                        } icon: {
                            Image(systemName: "star.fill")
                                .foregroundStyle(.yellow)
                                .font(.system(size: 10))
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }

                Divider().padding(.vertical, 4)

                Button("Edit Favorites\u{2026}") {
                    isMenuPresented = false
                    onEditFavoriteWatchedFolders()
                }
                .accessibilityIdentifier("edit-favorites-button")
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }

            if !recentWatchedFolders.isEmpty {
                if !favoriteWatchedFolders.isEmpty {
                    Divider().padding(.vertical, 4)
                }

                menuSectionHeader("Recent")

                let titlesByPath = ReaderRecentHistory.menuTitles(for: recentWatchedFolders)
                ForEach(recentWatchedFolders) { entry in
                    Button {
                        isMenuPresented = false
                        onStartRecentFolderWatch(entry)
                    } label: {
                        Text(titlesByPath[entry.folderPath] ?? entry.displayName)
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }

                Button("Clear History") {
                    isMenuPresented = false
                    onClearRecentWatchedFolders()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }

            if favoriteWatchedFolders.isEmpty && recentWatchedFolders.isEmpty {
                Text("No favorites or recent watches")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
        }
        .font(.system(size: 13))
        .foregroundStyle(Color(nsColor: .labelColor))
        .padding(.vertical, 8)
        .frame(minWidth: 220, maxWidth: 320)
    }

    private func menuSectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
    }
}

// MARK: - BreadcrumbDocumentContext

struct BreadcrumbDocumentContext: View {
    let projection: ReaderTopBarStoreProjection
    let onRevealInFinder: () -> Void

    private var hasFile: Bool { projection.fileURL != nil }

    private var titleText: String {
        if projection.fileDisplayName.isEmpty {
            return "No document open"
        }
        return projection.fileDisplayName
    }

    private var breadcrumbPath: String {
        guard let url = projection.fileURL else { return "" }
        let abbreviated = abbreviatePathWithTilde(url.deletingLastPathComponent().path)
        let components = abbreviated
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        let joined = components.joined(separator: " \u{203A} ")
        if abbreviated.hasPrefix("/") {
            return joined.isEmpty ? "/" : "/ \u{203A} " + joined
        }
        return joined
    }

    var body: some View {
        if hasFile {
            Button {
                onRevealInFinder()
            } label: {
                VStack(alignment: .leading, spacing: 1) {
                    Text(titleText)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    BreadcrumbTimestampLine(
                        breadcrumbPath: breadcrumbPath,
                        statusTimestamp: projection.statusBarTimestamp,
                        isCurrentFileMissing: projection.isCurrentFileMissing
                    )
                }
            }
            .buttonStyle(.plain)
            .modifier(PointingHandCursor())
            .help("Reveal in Finder")
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Current document")
            .accessibilityHint("Reveals this file in Finder")
        } else {
            VStack(alignment: .leading, spacing: 1) {
                Text("No document open")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text("Open a Markdown file to start reading")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            .accessibilityLabel("No document open")
        }
    }
}

// MARK: - BreadcrumbTimestampLine

struct BreadcrumbTimestampLine: View {
    let breadcrumbPath: String
    let statusTimestamp: ReaderStatusBarTimestamp?
    let isCurrentFileMissing: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: 20)) { context in
            Text(lineText(relativeTo: context.date))
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.head)
        }
    }

    private func lineText(relativeTo now: Date) -> String {
        var parts = breadcrumbPath
        if isCurrentFileMissing {
            parts += " \u{00B7} File deleted externally"
        } else if let statusTimestamp {
            let date: Date
            switch statusTimestamp {
            case let .updated(d), let .lastModified(d):
                date = d
            }
            let relative = ReaderStatusFormatting.relativeText(for: date, relativeTo: now)
            parts += " \u{00B7} \(relative)"
        }
        return parts
    }
}

// MARK: - SourceEditingStatusBar

struct SourceEditingStatusBar: View {
    let hasUnsavedChanges: Bool
    let canSave: Bool
    let canDiscard: Bool
    let onSave: () -> Void
    let onDiscard: () -> Void

    private enum Metrics {
        static let barHorizontalPadding: CGFloat = 12
        static let editingBannerVerticalPadding: CGFloat = 3
        static let editingBannerTextSpacing: CGFloat = 6
        static let editingBannerLabelSize: CGFloat = 10
        static let editingBannerIconSize: CGFloat = 8
        static let editingBannerButtonIconSize: CGFloat = 8
        static let editingBannerButtonHeight: CGFloat = 16
        static let editingBannerCornerRadius: CGFloat = 8
    }

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: Metrics.editingBannerTextSpacing) {
                Image(systemName: hasUnsavedChanges ? "pencil.and.list.clipboard" : "pencil")
                    .font(.system(size: Metrics.editingBannerIconSize, weight: .semibold))

                Text(hasUnsavedChanges ? "Editing source with unsaved changes" : "Editing source")
                    .font(.system(size: Metrics.editingBannerLabelSize, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(Color.black.opacity(0.82))

            Spacer(minLength: 0)

            statusActionButton(
                title: "Save",
                systemImage: "square.and.arrow.down",
                isEnabled: canSave,
                isPrimary: true,
                action: onSave
            )
            .accessibilityLabel("Save source changes")

            statusActionButton(
                title: "Exit without saving",
                systemImage: "xmark",
                isEnabled: canDiscard,
                isPrimary: false,
                action: onDiscard
            )
            .accessibilityLabel(hasUnsavedChanges ? "Exit source editing and discard source changes" : "Exit source editing")
        }
        .padding(.horizontal, Metrics.barHorizontalPadding)
        .padding(.vertical, Metrics.editingBannerVerticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            Rectangle()
                .fill(editingBannerBackground)
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.black.opacity(0.08))
                .frame(height: 1)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.black.opacity(0.14))
                .frame(height: 1)
        }
        .help(hasUnsavedChanges ? "Editing Source With Unsaved Changes" : "Editing Source")
    }

    private func statusActionButton(
        title: String,
        systemImage: String,
        isEnabled: Bool,
        isPrimary: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            action()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: Metrics.editingBannerButtonIconSize, weight: .semibold))

                Text(title)
                    .font(.system(size: Metrics.editingBannerLabelSize, weight: .semibold, design: .rounded))
            }
            .padding(.horizontal, 10)
            .frame(height: Metrics.editingBannerButtonHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .foregroundStyle(statusActionForegroundStyle(isEnabled: isEnabled, isPrimary: isPrimary))
        .background(buttonBackground(isEnabled: isEnabled, isPrimary: isPrimary), in: RoundedRectangle(cornerRadius: Metrics.editingBannerCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Metrics.editingBannerCornerRadius, style: .continuous)
                .strokeBorder(buttonBorder(isEnabled: isEnabled, isPrimary: isPrimary), lineWidth: 1)
        }
    }

    private func statusActionForegroundStyle(isEnabled: Bool, isPrimary: Bool) -> AnyShapeStyle {
        if !isEnabled {
            return AnyShapeStyle(Color.black.opacity(0.55))
        }

        return AnyShapeStyle(isPrimary ? Color.white : Color.black.opacity(0.82))
    }

    private func buttonBackground(isEnabled: Bool, isPrimary: Bool) -> some ShapeStyle {
        if !isEnabled {
            return Color.black.opacity(isPrimary ? 0.18 : 0.08)
        }

        if isPrimary {
            return Color.black.opacity(0.88)
        }

        return Color.white.opacity(0.58)
    }

    private func buttonBorder(isEnabled: Bool, isPrimary: Bool) -> Color {
        if !isEnabled {
            return Color.black.opacity(isPrimary ? 0.18 : 0.12)
        }

        return isPrimary ? Color.black.opacity(0.24) : Color.black.opacity(0.14)
    }

    private var editingBannerBackground: some ShapeStyle {
        LinearGradient(
            colors: [
                Color(red: 0.98, green: 0.92, blue: 0.58),
                Color(red: 0.94, green: 0.79, blue: 0.29)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}
