import Foundation

enum AmberTerminalTheme {
    static var definition: ThemeDefinition {
        ThemeDefinition(
            kind: .amberTerminal,
            displayName: ReaderThemeKind.amberTerminal.displayName,
            colors: ReaderTheme.theme(for: .amberTerminal),
            customCSS: customCSS,
            customJavaScript: nil,
            providesSyntaxHighlighting: true,
            syntaxCSS: syntaxCSS,
            syntaxPreviewPalette: previewPalette
        )
    }

    static let customCSS: String = """
    /* ── Amber Terminal CRT Theme ── */

    /* Monospace font override */
    html, body, .markdown-body, .markdown-body * {
        font-family: 'Courier New', Menlo, 'Courier', monospace !important;
    }

    /* Text glow */
    .markdown-body {
        text-shadow: 0 0 6px rgba(255, 176, 0, 0.5),
                     0 0 12px rgba(255, 176, 0, 0.15);
    }

    /* Headings glow brighter */
    .markdown-body h1,
    .markdown-body h2,
    .markdown-body h3,
    .markdown-body h4,
    .markdown-body h5,
    .markdown-body h6 {
        text-shadow: 0 0 8px rgba(255, 176, 0, 0.6),
                     0 0 16px rgba(255, 176, 0, 0.2);
    }

    /* Links glow brighter */
    .markdown-body a {
        text-shadow: 0 0 8px rgba(255, 204, 0, 0.6),
                     0 0 16px rgba(255, 204, 0, 0.2);
    }

    /* Code blocks — amber tinted, no extra glow (monospace readability) */
    pre {
        box-shadow: inset 0 0 30px rgba(255, 176, 0, 0.04);
    }

    pre code, pre code.hljs, pre code[class*="language-"] {
        text-shadow: 0 0 4px rgba(255, 176, 0, 0.35);
    }

    /* Scanlines overlay */
    body::before {
        content: '';
        position: fixed;
        top: 0;
        left: 0;
        width: 100%;
        height: 100%;
        background: repeating-linear-gradient(
            0deg,
            transparent,
            transparent 2px,
            rgba(0, 0, 0, 0.12) 2px,
            rgba(0, 0, 0, 0.12) 4px
        );
        pointer-events: none;
        z-index: 1000;
    }

    /* Screen curvature vignette */
    body::after {
        content: '';
        position: fixed;
        top: 0;
        left: 0;
        width: 100%;
        height: 100%;
        background: radial-gradient(
            ellipse at center,
            transparent 60%,
            rgba(0, 0, 0, 0.4) 100%
        );
        pointer-events: none;
        z-index: 1001;
    }

    /* Gutter icons — amber tinted diff markers */
    .reader-gutter-row-added .reader-gutter-icon {
        color: #7A9A40;
        text-shadow: 0 0 4px rgba(122, 154, 64, 0.5);
    }
    .reader-gutter-row-edited .reader-gutter-icon {
        color: #CC8800;
        text-shadow: 0 0 4px rgba(204, 136, 0, 0.5);
    }
    .reader-gutter-row-deleted .reader-gutter-icon {
        color: #6A4A2A;
        text-shadow: 0 0 4px rgba(106, 74, 42, 0.5);
    }

    /* Horizontal rules — amber glow */
    .markdown-body hr {
        border: none;
        border-top: 1px solid #3D2E00;
        box-shadow: 0 0 6px rgba(255, 176, 0, 0.2);
    }

    /* Blockquote border — amber */
    .markdown-body blockquote {
        border-left-color: #CC8800;
    }
    """

    static let syntaxCSS: String = """
    /* ── Amber Terminal Syntax Highlighting ── */

    :root {
        --reader-mark-signal: #FFCC00;
        --reader-blockquote-accent: #CC8800;
        --reader-blockquote-bg: rgba(255, 176, 0, 0.06);
        --reader-blockquote-fg: #CC8800;
    }

    pre {
        background: var(--reader-code-bg);
        border: 1px solid var(--reader-border);
    }

    pre code,
    pre code.hljs,
    pre code[class*="language-"] {
        color: #FFB000;
        background: transparent;
        display: block;
        padding: 0;
    }

    pre code .hljs-comment { color: #806020; font-style: italic; }
    pre code .hljs-keyword { color: #FFCC00; }
    pre code .hljs-string  { color: #CC8800; }
    pre code .hljs-number  { color: #FF9500; }
    pre code .hljs-title   { color: #FFC040; }
    pre code .hljs-built_in { color: #E0A000; }
    """

    static let previewPalette: SyntaxThemePreviewPalette = SyntaxThemePreviewPalette(
        blockTextHex: "#FFB000",
        blockBackgroundHex: "#1F1600",
        blockBorderHex: "#3D2E00",
        commentHex: "#806020",
        keywordHex: "#FFCC00",
        stringHex: "#CC8800",
        numberHex: "#FF9500",
        titleHex: "#FFC040",
        builtInHex: "#E0A000"
    )
}
