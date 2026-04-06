import Foundation

enum ReaderCSSThemeGenerator {
    // All production callers reach this via @MainActor ReaderStore → MarkdownRenderingService.
    private nonisolated(unsafe) static var cache: (theme: ThemeDefinition, syntaxTheme: SyntaxThemeKind, baseFontSize: Double, css: String)?

    static func makeCSS(theme: ThemeDefinition, syntaxTheme: SyntaxThemeKind, baseFontSize: Double) -> String {
        if let cache,
           cache.theme == theme,
           cache.syntaxTheme == syntaxTheme,
           cache.baseFontSize == baseFontSize {
            return cache.css
        }

        let css = generateCSS(theme: theme, syntaxTheme: syntaxTheme, baseFontSize: baseFontSize)
        cache = (theme, syntaxTheme, baseFontSize, css)
        return css
    }

    private static func generateCSS(theme: ThemeDefinition, syntaxTheme: SyntaxThemeKind, baseFontSize: Double) -> String {
        let variables = theme.colors.cssVariables(baseFontSize: baseFontSize)
        let syntaxLayer = theme.providesSyntaxHighlighting ? (theme.syntaxCSS ?? syntaxTheme.css) : syntaxTheme.css
        let themeLayer = theme.customCSS ?? ""
        return """
        \(variables)

        html, body {
          margin: 0;
          padding: 0;
          background: var(--reader-bg);
          color: var(--reader-fg);
          font-size: var(--reader-font-size);
          font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
          line-height: 1.6;
        }

        body {
          padding: 16px 16px 16px 0;
        }

        .reader-layout {
          --reader-gutter-base-width: 32px;
          --reader-gutter-lane-width: 18px;
          --reader-gutter-lane-count: 1;
          --reader-gutter-width: calc(var(--reader-gutter-base-width) + (var(--reader-gutter-lane-count) - 1) * var(--reader-gutter-lane-width));
          --reader-gutter-gap: 6px;
          --reader-gutter-icon-size: 18px;
          position: relative;
          box-sizing: border-box;
          width: 100%;
          margin: 0;
        }

        .markdown-body {
          position: relative;
          box-sizing: border-box;
          width: 100%;
          margin: 0;
          padding: 52px 12px 24px calc(var(--reader-gutter-width) + var(--reader-gutter-gap));
          color: var(--reader-fg);
          overflow-wrap: anywhere;
        }

        .reader-change-gutter {
          position: absolute;
          top: 0;
          bottom: 0;
          left: 0;
          width: var(--reader-gutter-width);
          background: var(--reader-bg);
          z-index: 2;
        }

        .reader-gutter-row {
          --reader-gutter-icon-top: 0px;
          position: absolute;
          left: 0;
          width: 100%;
          border: 0;
          padding: 0;
          margin: 0;
          background: transparent;
          cursor: pointer;
        }

        .reader-gutter-row-static {
          cursor: default;
        }

        .reader-gutter-row:focus-visible {
          outline: 2px solid var(--reader-link);
          outline-offset: -1px;
          border-radius: 6px;
        }

        .reader-gutter-pill {
          position: absolute;
          left: 3px;
          right: 3px;
          top: 1px;
          bottom: 1px;
          border-radius: 6px;
          min-height: 8px;
          transition: opacity 0.15s ease;
          opacity: 0.85;
        }

        .reader-gutter-row:hover .reader-gutter-pill {
          opacity: 1;
        }

        .reader-gutter-pill-accent {
          position: absolute;
          left: 0;
          top: 0;
          bottom: 0;
          width: 3px;
          border-radius: 6px 0 0 6px;
        }

        .reader-gutter-row-added .reader-gutter-pill {
          background: color-mix(in srgb, var(--reader-changed-added) 14%, transparent);
        }
        .reader-gutter-row-added .reader-gutter-pill-accent {
          background: var(--reader-changed-added);
        }

        .reader-gutter-row-edited .reader-gutter-pill {
          background: color-mix(in srgb, var(--reader-changed-edited) 14%, transparent);
        }
        .reader-gutter-row-edited .reader-gutter-pill-accent {
          background: var(--reader-changed-edited);
        }

        .reader-gutter-row-deleted .reader-gutter-pill {
          background: color-mix(in srgb, var(--reader-changed-deleted) 14%, transparent);
        }
        .reader-gutter-row-deleted .reader-gutter-pill-accent {
          background: var(--reader-changed-deleted);
        }

        .reader-gutter-row-active .reader-gutter-pill {
          opacity: 1;
          box-shadow: inset 0 0 0 1px color-mix(in srgb, var(--reader-link) 45%, transparent);
        }

        .reader-gutter-icon {
          position: absolute;
          left: 50%;
          top: var(--reader-gutter-icon-top);
          width: var(--reader-gutter-icon-size);
          height: var(--reader-gutter-icon-size);
          transform: translateX(-50%);
          font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
          font-size: 13px;
          font-weight: 700;
          line-height: var(--reader-gutter-icon-size);
          text-align: center;
          pointer-events: none;
        }

        .reader-gutter-row-added .reader-gutter-icon {
          color: var(--reader-changed-added);
        }
        .reader-gutter-row-edited .reader-gutter-icon {
          color: var(--reader-changed-edited);
        }
        .reader-gutter-row-deleted .reader-gutter-icon {
          color: var(--reader-changed-deleted);
        }

        /* Content background highlights for changed blocks */
        .reader-content-highlight-added {
          background: color-mix(in srgb, var(--reader-changed-added) 8%, transparent);
          border-radius: 4px;
        }
        .reader-content-highlight-edited {
          background: color-mix(in srgb, var(--reader-changed-edited) 8%, transparent);
          border-radius: 4px;
        }
        .reader-content-highlight-deleted {
          background: color-mix(in srgb, var(--reader-changed-deleted) 8%, transparent);
          border-radius: 4px;
        }

        /* Deleted content placeholder */
        .reader-deleted-placeholder {
          margin: 4px 0;
          padding: 6px 10px;
          border-radius: 6px;
          background: color-mix(in srgb, var(--reader-changed-deleted) 10%, transparent);
          border: 1px dashed color-mix(in srgb, var(--reader-changed-deleted) 30%, transparent);
          color: var(--reader-changed-deleted);
          font-size: 12px;
          font-weight: 500;
          font-style: italic;
        }

        .reader-inline-compare {
          margin: 8px 0 12px;
          padding: 8px 10px;
          border-radius: 8px;
          border: 1px solid color-mix(in srgb, var(--reader-border) 85%, transparent);
        }

        .reader-inline-compare-deleted {
          background: color-mix(in srgb, var(--reader-changed-deleted) 13%, transparent);
          border-color: color-mix(in srgb, var(--reader-changed-deleted) 45%, var(--reader-border));
        }

        .reader-inline-compare-edited {
          background: color-mix(in srgb, var(--reader-changed-edited) 16%, transparent);
          border-color: color-mix(in srgb, var(--reader-changed-edited) 45%, var(--reader-border));
        }

        .reader-inline-compare-header {
          margin: 0 0 6px;
          color: var(--reader-fg-secondary);
          font-size: 12px;
          font-weight: 600;
        }

        .reader-inline-compare-grid {
          display: grid;
          grid-template-columns: repeat(2, minmax(0, 1fr));
          gap: 10px;
        }

        .reader-inline-compare-column-label {
          margin: 0 0 4px;
          color: var(--reader-fg-secondary);
          font-size: 11px;
          font-weight: 600;
          text-transform: uppercase;
          letter-spacing: 0.04em;
        }

        .reader-inline-compare pre {
          margin: 0;
          font-family: "SF Mono", Menlo, ui-monospace, monospace;
          font-size: 12px;
          line-height: 1.45;
          white-space: pre-wrap;
          word-break: break-word;
          border-radius: 6px;
          border: 1px solid color-mix(in srgb, var(--reader-border) 85%, transparent);
          padding: 8px;
          background: color-mix(in srgb, var(--reader-code-bg) 75%, transparent);
        }

        .reader-inline-compare pre.reader-inline-diff {
          white-space: pre-wrap;
          word-break: break-word;
        }

        .reader-inline-diff-removed {
          background-color: var(--reader-changed-edited);
          background: color-mix(in srgb, var(--reader-changed-edited) 28%, transparent);
          border-radius: 3px;
          padding: 0 0.08em;
        }

        .reader-inline-diff-removed-deleted {
          background-color: var(--reader-changed-deleted);
          background: var(--reader-changed-deleted);
        }

        .reader-inline-compare-deleted .reader-inline-diff-removed {
          background-color: var(--reader-changed-deleted);
          background: color-mix(in srgb, var(--reader-changed-deleted) 34%, transparent);
        }

        .markdown-body .reader-unsaved-change {
          background: color-mix(in srgb, var(--reader-link) 12%, transparent);
          box-shadow: inset 3px 0 0 color-mix(in srgb, var(--reader-link) 55%, transparent);
          border-radius: 6px;
        }

        @media (max-width: 760px) {
          .reader-inline-compare-grid {
            grid-template-columns: 1fr;
          }
        }

        .markdown-body a {
          color: var(--reader-link);
        }

        .markdown-body p,
        .markdown-body li,
        .markdown-body table {
          color: var(--reader-fg);
        }

        .markdown-body blockquote {
          margin: 0.9em 0 1.1em;
          padding: 0.55em 0.95em 0.55em 1em;
          border-left: 0.25em solid var(--reader-blockquote-accent);
          background: var(--reader-blockquote-bg);
          color: var(--reader-blockquote-fg);
          border-radius: 0 6px 6px 0;
        }

        .markdown-body blockquote > :first-child {
          margin-top: 0;
        }

        .markdown-body blockquote > :last-child {
          margin-bottom: 0;
        }

        .markdown-body blockquote p {
          margin: 0.45em 0;
          color: inherit;
        }

        .markdown-body blockquote blockquote {
          margin: 0.55em 0 0.3em;
          padding-top: 0.45em;
          padding-bottom: 0.45em;
          border-left-width: 0.2em;
          background: var(--reader-blockquote-bg);
          color: var(--reader-blockquote-fg);
        }

        .markdown-body blockquote li,
        .markdown-body blockquote blockquote {
          color: inherit;
        }

        .markdown-body img,
        .markdown-body video,
        .markdown-body canvas,
        .markdown-body svg {
          max-width: 100%;
          height: auto;
        }

        code, pre {
          font-family: "SF Mono", Menlo, ui-monospace, monospace;
        }

        pre {
          background: var(--reader-code-bg);
          border: 1px solid var(--reader-border);
          border-radius: 8px;
          padding: 10px;
          overflow-x: auto;
        }

        code {
          background: var(--reader-code-bg);
          border-radius: 4px;
          padding: 0.1em 0.3em;
        }

        .markdown-body table {
          display: block;
          width: max-content;
          min-width: 100%;
          max-width: 100%;
          overflow-x: auto;
          border-collapse: collapse;
          border-spacing: 0;
          margin: 0.9em 0 1.1em;
          border: 1px solid var(--reader-border);
          background: var(--reader-bg);
        }

        .markdown-body th,
        .markdown-body td {
          padding: 0.45em 0.65em;
          border: 1px solid var(--reader-border);
          vertical-align: top;
          min-width: 4em;
          word-break: keep-all;
        }

        .markdown-body thead th {
          font-weight: 600;
          color: var(--reader-fg);
          background: var(--reader-code-bg);
          border-bottom: 1px solid var(--reader-border);
        }

        .markdown-body tbody tr:nth-child(even) td {
          background: var(--reader-code-bg);
        }

        .markdown-body th[align="right"],
        .markdown-body td[align="right"] {
          text-align: right;
        }

        .markdown-body th[align="center"],
        .markdown-body td[align="center"] {
          text-align: center;
        }

        .markdown-body th[align="left"],
        .markdown-body td[align="left"] {
          text-align: left;
        }

        .markdown-body a:focus-visible {
          outline: 2px solid var(--reader-link);
          outline-offset: 2px;
          border-radius: 3px;
        }

        .markdown-body .contains-task-list {
          list-style: none;
          padding-left: 0;
          margin-left: 0;
        }

        .markdown-body .task-list-item {
          list-style: none;
          margin: 0.3em 0;
          color: var(--reader-fg);
        }

        .markdown-body .task-list-item > p {
          display: inline;
          margin: 0;
        }

        .markdown-body .task-list-item > .task-list-item-label,
        .markdown-body .task-list-item > label {
          display: inline;
        }

        .markdown-body .task-list-item-checkbox {
          -webkit-appearance: none;
          appearance: none;
          margin: 0 0.55em 0 0;
          inline-size: 1.3em;
          block-size: 1.3em;
          vertical-align: -0.17em;
          border: 1.5px solid var(--reader-border);
          border-radius: 4px;
          background: transparent;
          pointer-events: none;
        }

        .markdown-body .task-list-item-checkbox:checked {
          background-color: var(--reader-link);
          border-color: var(--reader-link);
          background-image: url(\"data:image/svg+xml,%3Csvg viewBox='0 0 12 12' fill='none' xmlns='http://www.w3.org/2000/svg'%3E%3Cpath d='M2.5 6.5L5 9L9.5 3.5' stroke='white' stroke-width='1.8' stroke-linecap='round' stroke-linejoin='round'/%3E%3C/svg%3E\");
          background-size: 0.7em 0.7em;
          background-position: center;
          background-repeat: no-repeat;
        }

        .markdown-body .task-list-item:has(.task-list-item-checkbox:checked) {
          opacity: 0.55;
        }

        .markdown-body .task-list-item:has(.task-list-item-checkbox:checked) .task-list-item-checkbox {
          opacity: 1;
        }

        .markdown-body .task-list-item code {
          overflow-wrap: break-word;
          word-break: normal;
        }

        .markdown-body .footnote-ref {
          font-size: 0.8em;
          line-height: 0;
          vertical-align: super;
        }

        .markdown-body .footnotes {
          margin-top: 1.8em;
          padding-top: 0.9em;
          border-top: 1px solid var(--reader-border);
          color: var(--reader-fg-secondary);
          font-size: 0.92em;
        }

        .markdown-body .footnotes-list {
          margin: 0.45em 0 0;
          padding-left: 1.35em;
        }

        .markdown-body .footnote-item {
          margin: 0.4em 0;
        }

        .markdown-body .footnote-ref a,
        .markdown-body .footnote-backref {
          color: var(--reader-link);
          text-decoration: none;
        }

        .markdown-body .footnote-backref {
          margin-left: 0.3em;
        }

        .markdown-body dl {
          margin: 0.9em 0 1.1em;
          padding: 0.7em 0.85em;
          border: 1px solid var(--reader-border);
          border-radius: 8px;
          background: var(--reader-code-bg);
        }

        .markdown-body dt {
          margin: 0.35em 0 0.1em;
          font-weight: 600;
          color: var(--reader-fg);
        }

        .markdown-body dd {
          margin: 0 0 0.65em 1.1em;
          color: var(--reader-fg-secondary);
        }

        .markdown-body dd:last-child {
          margin-bottom: 0;
        }

        .markdown-body mark {
          background: color-mix(in srgb, var(--reader-mark-signal) 28%, transparent);
          color: inherit;
          border-radius: 3px;
          padding: 0 0.12em;
        }

        .markdown-body mjx-container {
          overflow-x: auto;
          overflow-y: hidden;
          max-width: 100%;
        }

        .markdown-body mjx-container[jax="CHTML"][display="true"] {
          margin: 0.9em 0;
          padding: 0.1em 0;
        }

        \(syntaxLayer)

        \(themeLayer)
        """
    }
}
