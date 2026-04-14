import Foundation

enum GreenTerminalTheme {
    static let definition = ThemeDefinition(
        kind: .greenTerminal,
        displayName: ReaderThemeKind.greenTerminal.displayName,
        colors: ReaderTheme.theme(for: .greenTerminal),
        customCSS: customCSS,
        customJavaScript: digitalRainJavaScript,
        providesSyntaxHighlighting: true,
        syntaxCSS: syntaxCSS,
        syntaxPreviewPalette: previewPalette
    )

    static let staticDefinition = ThemeDefinition(
        kind: .greenTerminalStatic,
        displayName: ReaderThemeKind.greenTerminalStatic.displayName,
        colors: ReaderTheme.theme(for: .greenTerminalStatic),
        customCSS: customCSS,
        customJavaScript: nil,
        providesSyntaxHighlighting: true,
        syntaxCSS: syntaxCSS,
        syntaxPreviewPalette: previewPalette
    )

    static let customCSS: String = """
    /* ── Green Terminal (Matrix) Theme ── */

    /* Content above digital rain canvas */
    .reader-layout {
        position: relative;
        z-index: 2;
    }

    /* Monospace font override */
    html, body, .markdown-body, .markdown-body * {
        font-family: 'Courier New', Menlo, 'Courier', monospace !important;
    }

    /* Text glow */
    .markdown-body {
        text-shadow: 0 0 6px rgba(0, 255, 65, 0.5),
                     0 0 12px rgba(0, 255, 65, 0.15);
    }

    /* Headings glow brighter */
    .markdown-body h1,
    .markdown-body h2,
    .markdown-body h3,
    .markdown-body h4,
    .markdown-body h5,
    .markdown-body h6 {
        text-shadow: 0 0 8px rgba(0, 255, 65, 0.6),
                     0 0 16px rgba(0, 255, 65, 0.2);
    }

    /* Links glow brighter */
    .markdown-body a {
        text-shadow: 0 0 8px rgba(65, 255, 127, 0.6),
                     0 0 16px rgba(65, 255, 127, 0.2);
    }

    /* Code blocks — green tinted */
    pre {
        box-shadow: inset 0 0 30px rgba(0, 255, 65, 0.04);
    }

    pre code, pre code.hljs, pre code[class*="language-"] {
        text-shadow: 0 0 4px rgba(0, 255, 65, 0.35);
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

    /* Gutter icons — green tinted diff markers */
    .reader-gutter-row-added .reader-gutter-icon {
        color: #00CC33;
        text-shadow: 0 0 4px rgba(0, 204, 51, 0.5);
    }
    .reader-gutter-row-edited .reader-gutter-icon {
        color: #7FCC00;
        text-shadow: 0 0 4px rgba(127, 204, 0, 0.5);
    }
    .reader-gutter-row-deleted .reader-gutter-icon {
        color: #2D5A3A;
        text-shadow: 0 0 4px rgba(45, 90, 58, 0.5);
    }

    /* Horizontal rules — green glow */
    .markdown-body hr {
        border: none;
        border-top: 1px solid #003B00;
        box-shadow: 0 0 6px rgba(0, 255, 65, 0.2);
    }

    /* Blockquote border — green */
    .markdown-body blockquote {
        border-left-color: #008F11;
    }
    """

    static let syntaxCSS: String = """
    /* ── Green Terminal Syntax Highlighting ── */

    :root {
        --reader-mark-signal: #00FF41;
        --reader-syntax-keyword: #00FF41;
        --reader-blockquote-accent: #008F11;
        --reader-blockquote-bg: rgba(0, 255, 65, 0.06);
        --reader-blockquote-fg: #008F11;
    }

    pre {
        background: var(--reader-code-bg);
        border: 1px solid var(--reader-border);
    }

    pre code,
    pre code.hljs,
    pre code[class*="language-"] {
        color: #00FF41;
        background: transparent;
        display: block;
        padding: 0;
    }

    pre code .hljs-comment { color: #2E7D32; font-style: italic; }
    pre code .hljs-keyword { color: #00FF41; }
    pre code .hljs-string  { color: #41FF7F; }
    pre code .hljs-number  { color: #76FF03; }
    pre code .hljs-title   { color: #69F0AE; }
    pre code .hljs-built_in { color: #00E676; }
    """

    static let previewPalette: SyntaxThemePreviewPalette = SyntaxThemePreviewPalette(
        blockTextHex: "#00FF41",
        blockBackgroundHex: "#0A0A0A",
        blockBorderHex: "#003B00",
        commentHex: "#2E7D32",
        keywordHex: "#00FF41",
        stringHex: "#41FF7F",
        numberHex: "#76FF03",
        titleHex: "#69F0AE",
        builtInHex: "#00E676"
    )

    // MARK: - Digital Rain Animation

    static let digitalRainJavaScript: String = """
    (function() {
        var CHARS = 'ﾊﾐﾋｰｳｼﾅﾓﾆｻﾜﾂｵﾘｱﾎﾃﾏｹﾒｴｶｷﾑﾕﾗｾﾈｽﾀﾇﾍ0123456789';
        var FONT_SIZE = 16;
        var STEP_MS = 100;
        var COLUMN_CHANCE = 0.008;
        var TRAIL_LENGTH = 12;
        var HEAD_ALPHA = 0.18;
        var TRAIL_START_ALPHA = 0.06;

        var canvas = document.createElement('canvas');
        canvas.id = '__minimark-matrix-rain';
        canvas.style.cssText = 'position:fixed;top:0;left:0;width:100%;height:100%;z-index:1;pointer-events:none;';
        document.body.appendChild(canvas);

        var ctx = canvas.getContext('2d');
        var columns = [];
        var intervalId = null;

        function makeColumn() {
            return { head: 0, active: false, chars: [] };
        }

        function resize() {
            canvas.width = window.innerWidth;
            canvas.height = window.innerHeight;
            var colCount = Math.floor(canvas.width / FONT_SIZE);
            while (columns.length < colCount) columns.push(makeColumn());
            while (columns.length > colCount) columns.pop();
        }

        function step() {
            ctx.clearRect(0, 0, canvas.width, canvas.height);
            ctx.font = FONT_SIZE + 'px monospace';

            for (var i = 0; i < columns.length; i++) {
                var col = columns[i];

                if (!col.active) {
                    if (Math.random() < COLUMN_CHANCE) {
                        col.active = true;
                        col.head = 0;
                        col.chars = [];
                    } else {
                        continue;
                    }
                }

                var ch = CHARS[Math.floor(Math.random() * CHARS.length)];
                col.chars.push(ch);
                if (col.chars.length > TRAIL_LENGTH) col.chars.shift();

                var x = i * FONT_SIZE;

                for (var j = 0; j < col.chars.length; j++) {
                    var age = col.chars.length - 1 - j;
                    var row = col.head - age;
                    if (row < 0) continue;
                    var y = row * FONT_SIZE;
                    if (y > canvas.height) continue;

                    var alpha = (age === 0) ? HEAD_ALPHA : TRAIL_START_ALPHA * (1 - age / TRAIL_LENGTH);
                    if (alpha <= 0) continue;

                    var r = (age === 0) ? 180 : 0;
                    var g = 255;
                    var b = (age === 0) ? 200 : 65;
                    ctx.fillStyle = 'rgba(' + r + ',' + g + ',' + b + ',' + alpha + ')';
                    ctx.fillText(col.chars[j], x, y);
                }

                col.head++;

                if ((col.head - TRAIL_LENGTH) * FONT_SIZE > canvas.height && Math.random() > 0.975) {
                    col.active = false;
                }
            }
        }

        function start() {
            resize();
            intervalId = setInterval(step, STEP_MS);
        }

        var reducedMotion = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
        if (!reducedMotion) {
            start();
            window.addEventListener('resize', resize);
        }

        window.__minimarkThemeCleanup = function() {
            if (intervalId) clearInterval(intervalId);
            window.removeEventListener('resize', resize);
            var el = document.getElementById('__minimark-matrix-rain');
            if (el) el.remove();
        };
    })();
    """
}
