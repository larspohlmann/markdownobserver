import SwiftUI

struct EditFavoritesSheet: View {
    let favorites: [ReaderFavoriteWatchedFolder]
    let onRename: (UUID, String) -> Void
    let onDelete: (UUID) -> Void
    let onReorder: ([UUID]) -> Void
    let onDismiss: () -> Void

    @State private var draftNames: [UUID: String] = [:]
    @State private var localOrder: [ReaderFavoriteWatchedFolder] = []

    var body: some View {
        VStack(spacing: 0) {
            header

            if localOrder.isEmpty {
                emptyState
            } else {
                favoritesList
            }

            footer
        }
        .frame(width: 420)
        .onAppear {
            localOrder = favorites
            seedDraftNames()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Favorites")
                .font(.system(size: 17, weight: .semibold))
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 16)
    }

    // MARK: - List

    private var favoritesList: some View {
        List {
            ForEach(localOrder) { entry in
                FavoriteRow(
                    entry: entry,
                    draftName: bindingForDraft(entry),
                    onCommitRename: { commitRename(for: entry) },
                    onDelete: { deleteEntry(entry) }
                )
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
            }
            .onMove(perform: moveEntries)
        }
        .listStyle(.plain)
        .frame(minHeight: 160, maxHeight: 400)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "star")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.quaternary)

            Text("No favorites yet")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)

            Text("Use the Watch menu to save a folder as a favorite")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 100)
        .padding(.vertical, 20)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            if !localOrder.isEmpty {
                Text("Drag to reorder")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Button("Done") {
                commitAllPendingRenames()
                let newIDs = localOrder.map(\.id)
                if newIDs != favorites.map(\.id) {
                    onReorder(newIDs)
                }
                onDismiss()
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Actions

    private func seedDraftNames() {
        draftNames = Dictionary(
            uniqueKeysWithValues: favorites.map { ($0.id, $0.name) }
        )
    }

    private func bindingForDraft(_ entry: ReaderFavoriteWatchedFolder) -> Binding<String> {
        Binding(
            get: { draftNames[entry.id] ?? entry.name },
            set: { draftNames[entry.id] = $0 }
        )
    }

    private func commitRename(for entry: ReaderFavoriteWatchedFolder) {
        guard let draft = draftNames[entry.id] else { return }
        let trimmed = draft.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != entry.name else { return }
        onRename(entry.id, trimmed)
    }

    private func commitAllPendingRenames() {
        for entry in localOrder {
            commitRename(for: entry)
        }
    }

    private func deleteEntry(_ entry: ReaderFavoriteWatchedFolder) {
        localOrder.removeAll { $0.id == entry.id }
        draftNames.removeValue(forKey: entry.id)
        onDelete(entry.id)
    }

    private func moveEntries(from source: IndexSet, to destination: Int) {
        localOrder.move(fromOffsets: source, toOffset: destination)
    }
}

// MARK: - Favorite Row

private struct FavoriteRow: View {
    let entry: ReaderFavoriteWatchedFolder
    @Binding var draftName: String
    let onCommitRename: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false
    @State private var isExcludedExpanded = false
    @FocusState private var isNameFocused: Bool

    private var excludedPaths: [String] {
        entry.excludedSubdirectoryRelativePaths
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            folderIcon

            VStack(alignment: .leading, spacing: 3) {
                nameField
                metaRow

                if isExcludedExpanded, !excludedPaths.isEmpty {
                    excludedFoldersDisclosure
                }
            }

            Spacer(minLength: 0)

            removeButton
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovering ? Color.primary.opacity(0.04) : .clear)
                .animation(.easeInOut(duration: 0.15), value: isHovering)
        )
        .onHover { hovering in
            isHovering = hovering
        }
    }

    // MARK: - Icon

    private var folderIcon: some View {
        ZStack(alignment: .bottomTrailing) {
            Image(systemName: "folder.fill")
                .font(.system(size: 20))
                .foregroundStyle(.orange)

            Image(systemName: "star.fill")
                .font(.system(size: 8))
                .foregroundStyle(.yellow)
                .offset(x: 3, y: 2)
        }
        .frame(width: 28, height: 24)
        .padding(.top, 2)
    }

    // MARK: - Name

    private var nameField: some View {
        TextField("Name", text: $draftName)
            .textFieldStyle(.plain)
            .font(.system(size: 13, weight: .medium))
            .focused($isNameFocused)
            .onSubmit { onCommitRename() }
            .padding(.horizontal, isNameFocused ? 6 : 0)
            .padding(.vertical, isNameFocused ? 2 : 0)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isNameFocused ? Color.accentColor.opacity(0.08) : .clear)
            )
    }

    // MARK: - Path + Filter Badge

    private var metaRow: some View {
        HStack(spacing: 6) {
            Text(abbreviatePathWithTilde(entry.folderPath))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            if !excludedPaths.isEmpty {
                filterBadge
            }
        }
    }

    private var filterBadge: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExcludedExpanded.toggle()
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 7, weight: .bold))
                    .rotationEffect(.degrees(isExcludedExpanded ? 90 : 0))

                Text("\(excludedPaths.count) filtered")
                    .font(.system(size: 9, weight: .medium))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.primary.opacity(0.06))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Excluded Folders Disclosure

    @State private var isFullExcludedListShown = false
    private static let collapsedLimit = 3

    private var excludedFoldersDisclosure: some View {
        VStack(alignment: .leading, spacing: 2) {
            let visiblePaths = isFullExcludedListShown
                ? excludedPaths
                : Array(excludedPaths.prefix(Self.collapsedLimit))

            ForEach(visiblePaths, id: \.self) { path in
                Text(path)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            if !isFullExcludedListShown, excludedPaths.count > Self.collapsedLimit {
                Button("and \(excludedPaths.count - Self.collapsedLimit) more\u{2026}") {
                    isFullExcludedListShown = true
                }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tint)
            }
        }
        .padding(.top, 4)
    }

    // MARK: - Remove Button

    private var removeButton: some View {
        Button {
            onDelete()
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .symbolRenderingMode(.hierarchical)
        }
        .buttonStyle(.plain)
        .opacity(isHovering ? 1 : 0)
        .animation(.easeInOut(duration: 0.15), value: isHovering)
        .padding(.top, 4)
        .help("Remove favorite")
    }
}
