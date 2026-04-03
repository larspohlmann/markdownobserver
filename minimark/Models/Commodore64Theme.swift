import Foundation

enum Commodore64Theme {
    static let definition = ThemeDefinition(
        kind: .commodore64,
        displayName: ReaderThemeKind.commodore64.displayName,
        colors: ReaderTheme.theme(for: .commodore64),
        customCSS: customCSS,
        customJavaScript: nil,
        providesSyntaxHighlighting: true,
        syntaxCSS: syntaxCSS,
        syntaxPreviewPalette: previewPalette
    )

    static let customCSS: String = """
    /* ── Commodore 64 Theme ── */

    /* Monospace font override */
    html, body, .markdown-body, .markdown-body * {
        font-family: 'Courier New', Menlo, 'Courier', monospace !important;
    }

    /* Headings in white like C64 system messages */
    .markdown-body h1,
    .markdown-body h2,
    .markdown-body h3,
    .markdown-body h4,
    .markdown-body h5,
    .markdown-body h6 {
        color: #FFFFFF;
    }

    /* Links in white */
    .markdown-body a {
        color: #FFFFFF;
    }

    /* Code blocks */
    pre {
        border: 1px solid #504694;
    }

    /* Horizontal rules */
    .markdown-body hr {
        border: none;
        border-top: 1px solid #7069C4;
    }

    /* Blockquote border */
    .markdown-body blockquote {
        border-left-color: #7069C4;
    }

    /* Gutter icons in C64 palette */
    .reader-gutter-row-added .reader-gutter-icon {
        color: #5CAB5E;
    }
    .reader-gutter-row-edited .reader-gutter-icon {
        color: #C9D487;
    }
    .reader-gutter-row-deleted .reader-gutter-icon {
        color: #9F4E44;
    }
    """

    static let syntaxCSS: String = """
    /* ── Commodore 64 Syntax Highlighting ── */

    :root {
        --reader-mark-signal: #FFFFFF;
        --reader-blockquote-accent: #7069C4;
        --reader-blockquote-bg: rgba(112, 105, 196, 0.1);
        --reader-blockquote-fg: #A0A0FF;
    }

    pre {
        background: var(--reader-code-bg);
        border: 1px solid var(--reader-border);
    }

    pre code,
    pre code.hljs,
    pre code[class*="language-"] {
        color: #A0A0FF;
        background: transparent;
        display: block;
        padding: 0;
    }

    pre code .hljs-comment { color: #504694; font-style: italic; }
    pre code .hljs-keyword { color: #FFFFFF; }
    pre code .hljs-string  { color: #5CAB5E; }
    pre code .hljs-number  { color: #C9D487; }
    pre code .hljs-title   { color: #6ABFC6; }
    pre code .hljs-built_in { color: #887ECB; }
    """

    static let previewPalette = SyntaxThemePreviewPalette(
        blockTextHex: "#A0A0FF",
        blockBackgroundHex: "#352879",
        blockBorderHex: "#504694",
        commentHex: "#504694",
        keywordHex: "#FFFFFF",
        stringHex: "#5CAB5E",
        numberHex: "#C9D487",
        titleHex: "#6ABFC6",
        builtInHex: "#887ECB"
    )
}
