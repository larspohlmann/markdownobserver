import SwiftUI

struct ContentEmptyStateView: View {
    @Environment(\.colorScheme) private var colorScheme

    enum Variant {
        case noDocument
        case folderWatchEmpty(folderName: String)
    }

    let variant: Variant
    let theme: ReaderTheme

    private var watchTintColor: Color {
        WatchActiveColor.color(for: colorScheme)
    }

    var body: some View {
        ZStack {
            background

            VStack(spacing: 0) {
                icon
                    .padding(.bottom, 16)

                headline
                    .padding(.bottom, subtitlePaddingBottom)

                subtitle
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .colorScheme(theme.kind.isDark ? .dark : .light)
    }

    @ViewBuilder
    private var background: some View {
        switch variant {
        case .noDocument:
            Rectangle()
                .fill(Color(hex: theme.backgroundHex) ?? .clear)
        case .folderWatchEmpty:
            Rectangle()
                .fill(Color(hex: theme.backgroundHex) ?? .clear)
                .overlay {
                    Rectangle()
                        .fill(watchTintColor.opacity(0.05))
                }
        }
    }

    @ViewBuilder
    private var icon: some View {
        switch variant {
        case .noDocument:
            Image(systemName: "doc.text")
                .font(.system(size: 48, weight: .thin))
                .foregroundStyle(Color(hex: theme.secondaryForegroundHex)?.opacity(0.5) ?? .secondary)
        case .folderWatchEmpty:
            Image(systemName: "binoculars.fill")
                .font(.system(size: 48, weight: .thin))
                .foregroundStyle(watchTintColor.opacity(0.5))
        }
    }

    @ViewBuilder
    private var headline: some View {
        switch variant {
        case .noDocument:
            Text("Open a Markdown File")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color(hex: theme.foregroundHex)?.opacity(0.7) ?? .primary)
        case .folderWatchEmpty:
            Text("Waiting for Markdown files\u{2026}")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color(hex: theme.foregroundHex)?.opacity(0.7) ?? .primary)
        }
    }

    private var subtitlePaddingBottom: CGFloat {
        switch variant {
        case .noDocument: return 0
        case .folderWatchEmpty: return 0
        }
    }

    @ViewBuilder
    private var subtitle: some View {
        switch variant {
        case .noDocument:
            VStack(spacing: 2) {
                Text("\u{2318}O to open a file  \u{00B7}  \u{2325}\u{2318}W to watch a folder")
                Text("or drop a file here")
            }
            .font(.system(size: 13))
            .foregroundStyle(Color(hex: theme.secondaryForegroundHex)?.opacity(0.6) ?? .secondary)

        case .folderWatchEmpty(let folderName):
            Text("Watching ")
                .font(.system(size: 13))
                .foregroundStyle(Color(hex: theme.secondaryForegroundHex)?.opacity(0.7) ?? .secondary)
            +
            Text(folderName)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(watchTintColor.opacity(0.7))
        }
    }
}
