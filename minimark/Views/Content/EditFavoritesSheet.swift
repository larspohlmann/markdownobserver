import SwiftUI

struct EditFavoritesSheet: View {
    let favorites: [ReaderFavoriteWatchedFolder]
    let onRename: (UUID, String) -> Void
    let onDelete: (UUID) -> Void
    let onDismiss: () -> Void

    @State private var draftNames: [UUID: String] = [:]

    var body: some View {
        VStack(spacing: 0) {
            Text("Edit Favorites")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .padding(.top, 16)
                .padding(.bottom, 12)

            if favorites.isEmpty {
                Text("No favorites saved")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 13))
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                List {
                    ForEach(favorites) { entry in
                        FavoriteRow(
                            entry: entry,
                            draftName: bindingForDraft(entry),
                            onCommitRename: { commitRename(for: entry) },
                            onDelete: { onDelete(entry.id) }
                        )
                    }
                }
                .listStyle(.inset)
                .frame(minHeight: 120, maxHeight: 400)
            }

            HStack {
                Spacer()
                Button("Done") {
                    commitAllPendingRenames()
                    onDismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 380)
        .onAppear { seedDraftNames() }
    }

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
        for entry in favorites {
            commitRename(for: entry)
        }
    }

    private struct FavoriteRow: View {
        let entry: ReaderFavoriteWatchedFolder
        @Binding var draftName: String
        let onCommitRename: () -> Void
        let onDelete: () -> Void

        var body: some View {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "star.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.yellow)
                    .padding(.top, 4)

                VStack(alignment: .leading, spacing: 4) {
                    TextField("Name", text: $draftName)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 13))
                        .onSubmit { onCommitRename() }

                    Text(entry.pathText)
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                }
                .buttonStyle(.borderless)
                .padding(.top, 4)
                .help("Remove favorite")
            }
            .padding(.vertical, 4)
        }
    }
}
