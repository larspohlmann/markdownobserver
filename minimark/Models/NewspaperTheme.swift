import Foundation

enum NewspaperTheme {
    static let definition = ThemeDefinition(
        kind: .newspaper,
        displayName: ReaderThemeKind.newspaper.displayName,
        colors: ReaderTheme.theme(for: .newspaper),
        customCSS: customCSS,
        customJavaScript: nil,
        providesSyntaxHighlighting: false,
        syntaxCSS: nil,
        syntaxPreviewPalette: nil
    )

    static let customCSS: String = """
    /* ── Newspaper Theme ── */

    /* Serif typography */
    html, body, .markdown-body {
        font-family: Charter, 'Iowan Old Style', Georgia, 'Times New Roman', serif !important;
    }

    .markdown-body {
        line-height: 1.55;
    }

    /* Strong heading hierarchy */
    .markdown-body h1 {
        font-weight: 900;
        letter-spacing: -0.02em;
        border-bottom: 2px solid #1A1A1A;
        padding-bottom: 6px;
        margin-bottom: 16px;
    }

    .markdown-body h2 {
        font-weight: 800;
        letter-spacing: -0.01em;
        border-bottom: 1px solid #D4CFC4;
        padding-bottom: 4px;
    }

    .markdown-body h3,
    .markdown-body h4,
    .markdown-body h5,
    .markdown-body h6 {
        font-weight: 700;
    }

    /* Subtle ruled lines on horizontal rules */
    .markdown-body hr {
        border: none;
        border-top: 1px solid #1A1A1A;
        margin: 24px 0;
    }

    /* Blockquotes — editorial pull-quote style */
    .markdown-body blockquote {
        border-left: 3px solid #1A1A1A;
        font-style: italic;
    }

    /* Code stays monospace */
    .markdown-body code,
    .markdown-body pre code {
        font-family: 'SFMono-Regular', Menlo, Monaco, Consolas, monospace !important;
    }
    """
}
