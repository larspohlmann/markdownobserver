import Foundation

enum GameBoyTheme {
    static let definition = ThemeDefinition(
        kind: .gameBoy,
        displayName: ReaderThemeKind.gameBoy.displayName,
        colors: ReaderTheme.theme(for: .gameBoy),
        customCSS: customCSS,
        customJavaScript: nil,
        providesSyntaxHighlighting: true,
        syntaxCSS: syntaxCSS,
        syntaxPreviewPalette: previewPalette
    )

    static let customCSS: String = """
    /* ── Game Boy Theme ── */

    /* Monospace font override */
    html, body, .markdown-body, .markdown-body * {
        font-family: 'Courier New', Menlo, 'Courier', monospace !important;
    }

    /* Subtle pixel grid overlay */
    body::before {
        content: '';
        position: fixed;
        top: 0;
        left: 0;
        width: 100%;
        height: 100%;
        background-image:
            linear-gradient(rgba(15, 56, 15, 0.06) 1px, transparent 1px),
            linear-gradient(90deg, rgba(15, 56, 15, 0.06) 1px, transparent 1px);
        background-size: 3px 3px;
        pointer-events: none;
        z-index: 1000;
    }

    /* Horizontal rules */
    .markdown-body hr {
        border: none;
        border-top: 2px solid #306230;
    }

    /* Blockquote border */
    .markdown-body blockquote {
        border-left-color: #306230;
    }

    /* Gutter icons — 4-shade only */
    .reader-gutter-row-added .reader-gutter-icon {
        color: #0F380F;
    }
    .reader-gutter-row-edited .reader-gutter-icon {
        color: #306230;
    }
    .reader-gutter-row-deleted .reader-gutter-icon {
        color: #306230;
    }
    """

    static let syntaxCSS: String = """
    /* ── Game Boy Syntax Highlighting (4-shade palette) ── */

    :root {
        --reader-mark-signal: #0F380F;
        --reader-syntax-keyword: #0F380F;
        --reader-blockquote-accent: #306230;
        --reader-blockquote-bg: rgba(15, 56, 15, 0.08);
        --reader-blockquote-fg: #306230;
    }

    pre {
        background: var(--reader-code-bg);
        border: 2px solid var(--reader-border);
    }

    pre code,
    pre code.hljs,
    pre code[class*="language-"] {
        color: #0F380F;
        background: transparent;
        display: block;
        padding: 0;
    }

    /* Only 4 shades available — use weight and style to differentiate */
    pre code .hljs-comment { color: #306230; font-style: italic; }
    pre code .hljs-keyword { color: #0F380F; font-weight: bold; }
    pre code .hljs-string  { color: #306230; }
    pre code .hljs-number  { color: #0F380F; }
    pre code .hljs-title   { color: #0F380F; font-weight: bold; }
    pre code .hljs-built_in { color: #306230; font-weight: bold; }
    """

    static let previewPalette = SyntaxThemePreviewPalette(
        blockTextHex: "#0F380F",
        blockBackgroundHex: "#8BAC0F",
        blockBorderHex: "#306230",
        commentHex: "#306230",
        keywordHex: "#0F380F",
        stringHex: "#306230",
        numberHex: "#0F380F",
        titleHex: "#0F380F",
        builtInHex: "#306230"
    )
}
