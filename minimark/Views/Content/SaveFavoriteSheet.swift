import SwiftUI

struct SaveFavoriteSheet: View {
    @Binding var name: String
    let onSave: (String) -> Void
    let onCancel: () -> Void

    @FocusState private var isNameFocused: Bool

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespaces)
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
                            .strokeBorder(Color.accentColor.opacity(isNameFocused ? 0.4 : 0), lineWidth: 1)
                    )
                    .onSubmit {
                        guard !trimmedName.isEmpty else { return }
                        onSave(trimmedName)
                    }
            }
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
                .disabled(trimmedName.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(width: 340)
        .onAppear { isNameFocused = true }
    }
}
