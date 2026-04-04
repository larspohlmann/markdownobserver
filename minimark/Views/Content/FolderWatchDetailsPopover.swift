import SwiftUI

struct FolderWatchDetailsPopover: View {
    let activeFolderWatch: ReaderFolderWatchSession
    var isCurrentWatchAFavorite: Bool = false
    var onSaveFolderWatchAsFavorite: ((String) -> Void)?

    @State private var isShowingSaveSheet = false
    @State private var favoriteName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "eye.circle.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.tint)
                    .frame(width: 32, height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.accentColor.opacity(0.12))
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text("Watching folder")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))

                    Text(activeFolderWatch.detailSummaryTitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if onSaveFolderWatchAsFavorite != nil {
                    favoriteStarButton
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Path")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                Text(activeFolderWatch.detailPathText)
                    .font(.system(size: 11.5, weight: .regular, design: .monospaced))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                ForEach(activeFolderWatch.detailRows, id: \.title) { row in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(row.title)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 110, alignment: .leading)

                        Text(row.value)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if !activeFolderWatch.excludedSubdirectoryRelativePaths.isEmpty {
                ExcludedSubdirectoriesSection(
                    relativePaths: activeFolderWatch.excludedSubdirectoryRelativePaths
                )
            }
        }
        .padding(16)
        .frame(width: 320, alignment: .leading)
        .sheet(isPresented: $isShowingSaveSheet) {
            SaveFavoriteSheet(
                name: $favoriteName,
                onSave: { name in
                    onSaveFolderWatchAsFavorite?(name)
                    isShowingSaveSheet = false
                },
                onCancel: {
                    isShowingSaveSheet = false
                }
            )
        }
    }

    @ViewBuilder
    private var favoriteStarButton: some View {
        if isCurrentWatchAFavorite {
            Image(systemName: "star.fill")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.yellow)
                .help("This watch configuration is saved as a favorite")
                .accessibilityLabel("Favorite saved")
        } else {
            Button {
                favoriteName = activeFolderWatch.detailSummaryTitle
                isShowingSaveSheet = true
            } label: {
                Image(systemName: "star")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Save as favorite")
            .accessibilityLabel("Save as favorite")
        }
    }
}

struct ExcludedSubdirectoriesSection: View {
    let relativePaths: [String]

    private static let collapsedLimit = 10

    @State private var isExpanded = false

    private var visiblePaths: [String] {
        if isExpanded || relativePaths.count <= Self.collapsedLimit {
            return relativePaths
        }
        return Array(relativePaths.prefix(Self.collapsedLimit))
    }

    private var hasMore: Bool {
        !isExpanded && relativePaths.count > Self.collapsedLimit
    }

    var body: some View {
        Divider()

        DisclosureGroup("Filtered subdirectories", isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(visiblePaths, id: \.self) { path in
                    Text(path)
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                if hasMore {
                    Button("and \(relativePaths.count - Self.collapsedLimit) more...") {
                        isExpanded = true
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tint)
                }
            }
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(.secondary)
    }
}
