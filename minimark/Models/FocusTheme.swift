import Foundation

enum FocusTheme {
    static let definition = ThemeDefinition(
        kind: .focus,
        displayName: ReaderThemeKind.focus.displayName,
        colors: ReaderTheme.theme(for: .focus),
        customCSS: customCSS,
        customJavaScript: nil,
        providesSyntaxHighlighting: false,
        syntaxCSS: nil,
        syntaxPreviewPalette: nil
    )

    static let customCSS: String = """
    /* ── Focus Theme ── */

    .markdown-body {
        line-height: 1.8;
    }

    body {
        padding: 24px 32px 24px 0;
    }

    /* Headings differentiated by weight, not size */
    .markdown-body h1 {
        font-size: 1.3em;
        font-weight: 700;
    }

    .markdown-body h2 {
        font-size: 1.15em;
        font-weight: 700;
    }

    .markdown-body h3 {
        font-size: 1.05em;
        font-weight: 600;
    }

    .markdown-body h4,
    .markdown-body h5,
    .markdown-body h6 {
        font-size: 1em;
        font-weight: 600;
    }

    /* Muted horizontal rules */
    .markdown-body hr {
        border: none;
        border-top: 1px solid #E0E0E0;
    }

    /* Muted blockquotes */
    .markdown-body blockquote {
        border-left-color: #D0D0D0;
        color: #6B6B6B;
    }

    /* Links — same color as text, just underlined */
    .markdown-body a {
        text-decoration: underline;
        text-underline-offset: 2px;
    }
    """
}
