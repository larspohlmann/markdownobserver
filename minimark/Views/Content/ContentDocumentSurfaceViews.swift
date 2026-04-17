import SwiftUI

struct DocumentLoadingOverlay: View {
    let theme: Theme
    let headline: String
    let subtitle: String?

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color(hex: theme.backgroundHex) ?? .clear)

            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.large)
                    .colorScheme(theme.kind.isDark ? .dark : .light)

                Text(headline)
                    .font(.headline)
                    .foregroundStyle(Color(hex: theme.foregroundHex) ?? .primary)

                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(Color(hex: theme.secondaryForegroundHex) ?? .secondary)
                }
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

struct ImageAccessWarningBar: View {
    @Environment(\.colorScheme) private var colorScheme

    let onGrantAccess: () -> Void

    private var tint: Color {
        Color(nsColor: .systemOrange)
    }

    private var backgroundColor: Color {
        tint.opacity(colorScheme == .dark ? 0.15 : 0.10)
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "photo.badge.exclamationmark")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)

            Text("Some images can't be displayed.")
                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)

            Spacer(minLength: 0)

            Button("Grant Folder Access") {
                onGrantAccess()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(backgroundColor)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(tint.opacity(0.40))
                .frame(height: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Image access required")
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

struct DocumentSurfaceHost: View {
    let configuration: DocumentSurfaceConfiguration
    let fallbackMarkdown: String

    var body: some View {
        Group {
            if configuration.usesWebSurface {
                MarkdownWebView(
                    htmlDocument: configuration.htmlDocument,
                    documentIdentity: configuration.documentIdentity,
                    accessibilityIdentifier: configuration.accessibilityIdentifier,
                    accessibilityValue: configuration.accessibilityValue,
                    reloadToken: configuration.reloadToken,
                    diagnosticName: configuration.diagnosticName,
                    postLoadStatusScript: configuration.postLoadStatusScript,
                    changedRegionNavigationRequest: configuration.changedRegionNavigationRequest,
                    scrollSyncRequest: configuration.scrollSyncRequest,
                    tocScrollRequest: configuration.tocScrollRequest,
                    supportsInPlaceContentUpdates: configuration.supportsInPlaceContentUpdates,
                    overlayTopInset: configuration.overlayTopInset,
                    reloadAnchorProgress: configuration.reloadAnchorProgress,
                    canAcceptDroppedFileURLs: configuration.canAcceptDroppedFileURLs,
                    onAction: configuration.onAction
                )
            } else {
                fallbackSurface
            }
        }
        .frame(minWidth: configuration.minimumWidth)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var fallbackSurface: some View {
        switch configuration.role {
        case .preview:
            NativeMarkdownFallbackView(
                markdown: fallbackMarkdown,
                onRetryPreview: { configuration.onAction(.retryFallback) }
            )
        case .source:
            MarkdownSourceFallbackView(
                markdown: fallbackMarkdown,
                onRetryHighlighting: { configuration.onAction(.retryFallback) }
            )
        }
    }
}

struct DocumentSurfaceLayoutView<PreviewSurface: View, SourceSurface: View>: View {
    let documentViewMode: DocumentViewMode
    let hasOpenDocument: Bool
    let showsLoadingOverlay: Bool
    let loadingOverlayHeadline: String
    let loadingOverlaySubtitle: String?
    let emptyStateVariant: ContentEmptyStateView.Variant
    let currentReaderTheme: Theme
    let onDroppedFileURLs: ([URL]) -> Void
    let previewSurface: PreviewSurface
    let sourceSurface: SourceSurface

    var body: some View {
        if showsLoadingOverlay {
            DocumentLoadingOverlay(
                theme: currentReaderTheme,
                headline: loadingOverlayHeadline,
                subtitle: loadingOverlaySubtitle
            )
        } else if !hasOpenDocument {
            ContentEmptyStateView(
                variant: emptyStateVariant,
                theme: currentReaderTheme
            )
            .dropDestination(for: URL.self) { urls, _ in
                let fileURLs = urls.filter { $0.isFileURL }
                guard !fileURLs.isEmpty else { return false }
                onDroppedFileURLs(fileURLs)
                return true
            }
        } else {
            switch documentViewMode {
            case .preview:
                previewSurface
            case .split:
                HSplitView {
                    previewSurface
                    sourceSurface
                }
            case .source:
                sourceSurface
            }
        }
    }
}