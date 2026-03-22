import SwiftUI

struct DocumentLoadingOverlay: View {
    let theme: ReaderTheme

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color(hex: theme.backgroundHex) ?? .clear)

            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.large)
                    .tint(Color(hex: theme.foregroundHex) ?? .primary)

                Text("Waiting for file contents…")
                    .font(.headline)
                    .foregroundStyle(Color(hex: theme.foregroundHex) ?? .primary)
                Text("The new watched document will appear as soon as writing finishes.")
                    .font(.subheadline)
                    .foregroundStyle(Color(hex: theme.secondaryForegroundHex) ?? .secondary)
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct DeletedFileWarningBar: View {
    @Environment(\.colorScheme) private var colorScheme

    let fileName: String
    let message: String?

    private var deletedTint: Color {
        Color(nsColor: .systemRed)
    }

    private var backgroundColor: Color {
        deletedTint.opacity(colorScheme == .dark ? 0.20 : 0.12)
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(deletedTint)

            VStack(alignment: .leading, spacing: 2) {
                Text(fileName.isEmpty ? "File deleted externally" : "\(fileName) was deleted externally")
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)

                Text(message ?? "You are viewing the last loaded contents. Restore the file or open another document.")
                    .font(.system(size: 11.5, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(backgroundColor)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(deletedTint.opacity(0.45))
                .frame(height: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Deleted file")
        .accessibilityValue(fileName.isEmpty ? "Current file deleted externally" : "\(fileName) deleted externally")
    }
}

struct NativeMarkdownFallbackView: View {
    let markdown: String
    let onRetryPreview: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Preview unavailable")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)

                Spacer()

                Button("Retry Preview") {
                    onRetryPreview()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            ScrollView {
                Text(markdown.isEmpty ? "No markdown content." : markdown)
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct MarkdownSourceFallbackView: View {
    let markdown: String
    let onRetryHighlighting: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Source highlighting unavailable")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)

                Spacer()

                Button("Retry Highlighting") {
                    onRetryHighlighting()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            ScrollView {
                Text(markdown.isEmpty ? "No markdown content." : markdown)
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}