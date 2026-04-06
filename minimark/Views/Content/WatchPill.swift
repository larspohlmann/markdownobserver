import SwiftUI

struct WatchPill: View {
    let activeFolderWatch: ReaderFolderWatchSession
    let isCurrentWatchAFavorite: Bool
    let canStop: Bool
    let onStop: () -> Void
    let onSaveFavorite: (String) -> Void
    let onRemoveFavorite: () -> Void
    let onRevealInFinder: () -> Void
    let isAppearanceLocked: Bool
    let onToggleAppearanceLock: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false
    @State private var isShowingDetails = false

    private enum Metrics {
        static let pillHeight: CGFloat = 30
        static let pillCornerRadius: CGFloat = 15
        static let pillVerticalInset: CGFloat = 8
        static let horizontalPadding: CGFloat = 14
        static let buttonHeight: CGFloat = 22
        static let controlHeight: CGFloat = 28
    }

    private var stripGreen: Color {
        colorScheme == .dark
            ? Color(red: 0.30, green: 0.81, blue: 0.49)
            : Color(red: 0.13, green: 0.54, blue: 0.33)
    }

    private var greenTint: Color {
        stripGreen.opacity(colorScheme == .dark ? 0.08 : 0.10)
    }

    private var pillBorder: Color {
        stripGreen.opacity(isHovering ? 0.25 : 0.15)
    }

    private var tildeAbbreviatedPath: String {
        abbreviatePathWithTilde(activeFolderWatch.folderURL.path)
    }

    private var filteredCount: Int {
        activeFolderWatch.excludedSubdirectoryRelativePaths.count
    }

    var body: some View {
        HStack(spacing: 8) {
            Button {
                isShowingDetails = true
            } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: Metrics.controlHeight, height: Metrics.controlHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(stripGreen.opacity(colorScheme == .dark ? 0.90 : 0.72))
            .popover(isPresented: $isShowingDetails, arrowEdge: .bottom) {
                FolderWatchDetailsPopover(
                    activeFolderWatch: activeFolderWatch,
                    isCurrentWatchAFavorite: isCurrentWatchAFavorite,
                    onSaveFolderWatchAsFavorite: onSaveFavorite
                )
            }
            .help(activeFolderWatch.tooltipText)
            .accessibilityLabel("Folder watch details")
            .accessibilityValue(activeFolderWatch.accessibilityValue)
            .accessibilityHint("Shows details about the watched folder")

            Button {
                onToggleAppearanceLock()
            } label: {
                Image(systemName: isAppearanceLocked ? "lock.fill" : "lock.open")
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: Metrics.controlHeight, height: Metrics.controlHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(
                isAppearanceLocked
                    ? stripGreen.opacity(colorScheme == .dark ? 0.90 : 0.72)
                    : .primary.opacity(0.4)
            )
            .help(isAppearanceLocked ? "Unlock appearance" : "Lock appearance")
            .accessibilityLabel(isAppearanceLocked ? "Unlock appearance" : "Lock appearance")
            .accessibilityHint("Locks the current theme, syntax theme, and font size for this window")
            .accessibilityValue(isAppearanceLocked ? "Locked" : "Unlocked")

            Text("WATCHING")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(stripGreen.opacity(colorScheme == .dark ? 0.85 : 0.55))
                .tracking(0.4)
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.9 : 0), radius: 2, y: 0)

            Button {
                onRevealInFinder()
            } label: {
                HStack(spacing: 5) {
                    Text(tildeAbbreviatedPath)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(stripGreen.opacity(colorScheme == .dark ? 1.0 : 0.85))
                        .shadow(color: .black.opacity(colorScheme == .dark ? 0.9 : 0), radius: 2, y: 0)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    if filteredCount > 0 {
                        Text("[\(filteredCount) filtered]")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(stripGreen.opacity(colorScheme == .dark ? 0.70 : 0.45))
                            .shadow(color: .black.opacity(colorScheme == .dark ? 0.9 : 0), radius: 2, y: 0)
                    }
                }
            }
            .buttonStyle(.plain)
            .help("Reveal in Finder")
            .accessibilityLabel("Watched folder path")
            .accessibilityValue(tildeAbbreviatedPath)
            .accessibilityHint("Opens the watched folder in Finder")

            WatchPillFavoriteStarToggle(
                isCurrentWatchAFavorite: isCurrentWatchAFavorite,
                folderDisplayName: activeFolderWatch.detailSummaryTitle,
                onSave: onSaveFavorite,
                onRemove: onRemoveFavorite
            )

            Button {
                onStop()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 7, weight: .bold))
                    Text("Stop")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                }
                .padding(.horizontal, 8)
                .frame(height: Metrics.buttonHeight)
                .contentShape(RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary.opacity(0.4))
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.primary.opacity(0.08)))
            .disabled(!canStop)
            .accessibilityLabel("Stop watching folder")
            .accessibilityHint("Stops monitoring the current folder")
        }
        .padding(.horizontal, Metrics.horizontalPadding)
        .frame(minHeight: Metrics.pillHeight)
        .background(.ultraThinMaterial, in: Capsule(style: .continuous))
        .background {
            Capsule(style: .continuous)
                .fill(greenTint)
        }
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(pillBorder, lineWidth: 1)
        }
        .shadow(color: .black.opacity(isHovering ? 0.25 : 0.12), radius: isHovering ? 16 : 6, y: 2)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.25)) {
                isHovering = hovering
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .contain)
    }
}

private struct WatchPillFavoriteStarToggle: View {
    let isCurrentWatchAFavorite: Bool
    let folderDisplayName: String
    let onSave: (String) -> Void
    let onRemove: () -> Void

    @State private var isShowingSaveSheet = false
    @State private var favoriteName = ""

    private enum Metrics {
        static let controlHeight: CGFloat = 28
    }

    var body: some View {
        Button {
            if isCurrentWatchAFavorite {
                onRemove()
            } else {
                favoriteName = folderDisplayName
                isShowingSaveSheet = true
            }
        } label: {
            Image(systemName: isCurrentWatchAFavorite ? "star.fill" : "star")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isCurrentWatchAFavorite ? .yellow : .secondary)
                .frame(width: Metrics.controlHeight, height: Metrics.controlHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isCurrentWatchAFavorite ? "Remove from favorites" : "Save as favorite")
        .accessibilityLabel(isCurrentWatchAFavorite ? "Remove from favorites" : "Save as favorite")
        .sheet(isPresented: $isShowingSaveSheet) {
            SaveFavoriteSheet(
                name: $favoriteName,
                onSave: { name in
                    onSave(name)
                    isShowingSaveSheet = false
                },
                onCancel: {
                    isShowingSaveSheet = false
                }
            )
        }
    }
}
