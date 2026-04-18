import SwiftUI

struct SaveFavoriteSheet: View {
    @Binding var name: String
    let onSave: (String) -> Void
    let onCancel: () -> Void

    @Environment(SettingsStore.self) private var settingsStore
    @FocusState private var isNameFocused: Bool

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespaces)
    }

    private var isDuplicateName: Bool {
        guard !trimmedName.isEmpty else { return false }
        let needle = trimmedName.lowercased()
        return settingsStore.currentSettings.favoriteWatchedFolders.contains {
            $0.name.trimmingCharacters(in: .whitespaces).lowercased() == needle
        }
    }

    private var isSaveDisabled: Bool {
        trimmedName.isEmpty || isDuplicateName
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Save as Favorite")
                    .font(.system(size: 17, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 12) {
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

                    TextField("Favorite name", text: $name)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, weight: .medium))
                        .focused($isNameFocused)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.primary.opacity(0.04))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(
                                    isDuplicateName
                                        ? Color.red.opacity(0.55)
                                        : Color.accentColor.opacity(isNameFocused ? 0.4 : 0),
                                    lineWidth: 1
                                )
                        )
                        .onSubmit {
                            guard !isSaveDisabled else { return }
                            onSave(trimmedName)
                        }
                }

                if isDuplicateName {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10, weight: .semibold))
                        Text("A favorite with this name already exists.")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(Color.red.opacity(0.85))
                    .padding(.leading, 40)
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.12), value: isDuplicateName)
            .padding(.horizontal, 20)
            .padding(.bottom, 20)

            HStack {
                Spacer()

                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)

                Button("Save") {
                    onSave(trimmedName)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isSaveDisabled)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(width: 340)
        .onAppear { isNameFocused = true }
    }
}
