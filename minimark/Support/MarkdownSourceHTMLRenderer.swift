import Foundation
import OSLog

enum MarkdownSourceHTMLRenderer {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "minimark",
        category: "MarkdownSourceHTMLRenderer"
    )

    private struct Payload: Encodable {
        let markdown: String
        let isEditable: Bool
        let backgroundHex: String
        let foregroundHex: String
        let secondaryForegroundHex: String
        let codeBackgroundHex: String
        let borderHex: String
        let linkHex: String
        let accentHex: String
        let stringHex: String
        let deletedHex: String
        let selectionHex: String
        let baseFontSize: Double
        let isDark: Bool
    }

    static func makeHTMLDocument(markdown: String, settings: ReaderSettings, isEditable: Bool) -> String {
        let theme = Theme.theme(for: settings.readerTheme)
        let baseCSS = theme.cssVariables(baseFontSize: settings.baseFontSize)
        let codeMirrorScriptPath = BundledAssets.availableCodeMirrorSourceViewScriptPath()
        let payloadBase64 = makePayloadBase64(
            markdown: markdown,
            theme: theme,
            settings: settings,
            isEditable: isEditable
        )
        let runtimeScriptTag: String
        let statusBootstrapScript: String
        let bootstrapScript: String

        if isEditable {
            runtimeScriptTag = ""
            statusBootstrapScript = """
            <script>
                window.__minimarkSourceBootstrapStatus = "bootstrapping";
            </script>
            """
            bootstrapScript = """
            <script>
                (function() {
                    function decodeBase64UTF8(base64Value) {
                        const binary = atob(base64Value);
                        const bytes = Uint8Array.from(binary, character => character.charCodeAt(0));
                        return new TextDecoder().decode(bytes);
                    }

                    function decodePayload(base64Value) {
                        return JSON.parse(decodeBase64UTF8(base64Value));
                    }

                    try {
                        const payload = decodePayload("\(payloadBase64)");
                        const root = document.getElementById("minimark-source-root");
                        if (!root) {
                            window.__minimarkSourceBootstrapStatus = "root-missing";
                            return;
                        }

                        const textarea = document.createElement("textarea");
                        textarea.className = "minimark-source-editor";
                        textarea.spellcheck = false;
                        textarea.setAttribute("aria-label", "Markdown source editor");
                        textarea.value = payload.markdown || "";
                        textarea.addEventListener("input", function() {
                            try {
                                window.webkit.messageHandlers.minimarkSourceEdit.postMessage({ markdown: textarea.value });
                            } catch (_) {}
                        });
                        textarea.addEventListener("keydown", function(event) {
                            const key = typeof event.key === "string" ? event.key.toLowerCase() : "";
                            const isSaveShortcut = (event.metaKey || event.ctrlKey) && !event.altKey && key === "s";
                            if (!isSaveShortcut) {
                                return;
                            }

                            try {
                                window.webkit.messageHandlers.minimarkSourceEditorDiagnostic.postMessage({
                                    event: "saveShortcutPressed",
                                    metaKey: !!event.metaKey,
                                    ctrlKey: !!event.ctrlKey,
                                    shiftKey: !!event.shiftKey,
                                    altKey: !!event.altKey
                                });
                            } catch (_) {}
                        });

                        root.replaceChildren(textarea);

                        var lastSourceHeadingsJSON = "";
                        var sourceHeadingsDebounceTimer = null;

                        function extractSourceHeadings(text) {
                            try {
                                var lines = text.split("\\n");
                                var result = [];
                                var inCodeFence = false;
                                for (var i = 0; i < lines.length; i++) {
                                    if (/^```|^~~~/.test(lines[i])) { inCodeFence = !inCodeFence; continue; }
                                    if (inCodeFence) continue;
                                    var match = lines[i].match(/^(#{1,3})\\s+(.+)/);
                                    if (match) {
                                        result.push({
                                            id: "",
                                            level: match[1].length,
                                            title: match[2].replace(/\\s+$/, ""),
                                            sourceLine: i + 1
                                        });
                                    }
                                }
                                var json = JSON.stringify(result);
                                if (json !== lastSourceHeadingsJSON) {
                                    lastSourceHeadingsJSON = json;
                                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.minimarkTOC) {
                                        window.webkit.messageHandlers.minimarkTOC.postMessage(result);
                                    }
                                }
                            } catch (_) {}
                        }

                        extractSourceHeadings(payload.markdown || "");

                        textarea.addEventListener("input", function() {
                            if (sourceHeadingsDebounceTimer) { clearTimeout(sourceHeadingsDebounceTimer); }
                            sourceHeadingsDebounceTimer = setTimeout(function() {
                                extractSourceHeadings(textarea.value);
                            }, 200);
                        });

                        window.__minimarkSourceBootstrapStatus = "ready";
                        requestAnimationFrame(function() {
                            const scrollX = window.scrollX || 0;
                            const scrollY = window.scrollY || 0;
                            try {
                                textarea.focus({ preventScroll: true });
                            } catch (_) {
                                textarea.focus();
                                window.scrollTo(scrollX, scrollY);
                            }
                        });
                    } catch (error) {
                        const message = error && error.message ? error.message : String(error);
                        window.__minimarkSourceBootstrapStatus = "bootstrap-error:" + message;
                    }
                })();
            </script>
            """
        } else if let codeMirrorScriptPath {
            runtimeScriptTag = isEditable ? "" : #"<script src="\#(codeMirrorScriptPath)"></script>"#
            statusBootstrapScript = """
            <script>
                window.__minimarkSourceBootstrapStatus = "bootstrapping";
            </script>
            """
            bootstrapScript = """
            <script>
                (function() {
                    if (!window.MinimarkCodeMirrorSourceView || typeof window.MinimarkCodeMirrorSourceView.bootstrap !== "function") {
                        window.__minimarkSourceBootstrapStatus = "runtime-missing";
                        return;
                    }

                    if (!"\(payloadBase64)") {
                        window.__minimarkSourceBootstrapStatus = "payload-empty";
                        return;
                    }

                    try {
                        window.MinimarkCodeMirrorSourceView.bootstrap("\(payloadBase64)");
                        window.__minimarkSourceBootstrapStatus = "ready";
                    } catch (error) {
                        const message = error && error.message ? error.message : String(error);
                        window.__minimarkSourceBootstrapStatus = "bootstrap-error:" + message;
                    }
                })();
            </script>
            """
        } else {
            runtimeScriptTag = ""
            statusBootstrapScript = """
            <script>
                window.__minimarkSourceBootstrapStatus = "runtime-bundle-unavailable";
            </script>
            """
            bootstrapScript = ""
        }

        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'unsafe-inline' file:; style-src 'unsafe-inline'; img-src data: https:; frame-ancestors 'none'">
            <style>
                \(baseCSS)

                html, body {
                    margin: 0;
                    padding: 0;
                    min-height: 100%;
                    background: var(--reader-bg);
                    color: var(--reader-fg);
                    font-family: SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", "Courier New", monospace;
                    font-size: var(--reader-font-size);
                }

                body {
                    box-sizing: border-box;
                }

                #minimark-source-root {
                    min-height: 100vh;
                    padding-top: \(Int(OverlayInsetCalculator.defaultScrollTargetTopInset.rounded()))px;
                }

                .minimark-source-editor {
                    display: block;
                    width: 100%;
                    min-height: 100vh;
                    box-sizing: border-box;
                    padding: 0 16px 32px;
                    border: 0;
                    outline: none;
                    resize: none;
                    background: var(--reader-bg);
                    color: var(--reader-fg);
                    font-family: SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", "Courier New", monospace;
                    font-size: var(--reader-font-size);
                    line-height: 1.55;
                }

                ::selection {
                    background: color-mix(in srgb, var(--reader-link) 22%, transparent);
                }
            </style>
            \(statusBootstrapScript)
            \(runtimeScriptTag)
        </head>
        <body>
            <div id="minimark-source-root"></div>
            \(bootstrapScript)
        </body>
        </html>
        """
    }

    private static func makePayloadBase64(
        markdown: String,
        theme: Theme,
        settings: ReaderSettings,
        isEditable: Bool
    ) -> String {
        let payload = Payload(
            markdown: markdown,
            isEditable: isEditable,
            backgroundHex: theme.backgroundHex,
            foregroundHex: theme.foregroundHex,
            secondaryForegroundHex: theme.secondaryForegroundHex,
            codeBackgroundHex: theme.codeBackgroundHex,
            borderHex: theme.borderHex,
            linkHex: theme.linkHex,
            accentHex: syntaxAccentHex(for: settings.syntaxTheme),
            stringHex: syntaxStringHex(for: settings.syntaxTheme),
            deletedHex: syntaxDeletedHex(for: settings.syntaxTheme),
            selectionHex: selectionHex(for: theme),
            baseFontSize: settings.baseFontSize,
            isDark: isDarkTheme(theme)
        )

        let data: Data
        do {
            data = try JSONEncoder().encode(payload)
        } catch {
            let nsError = error as NSError
            logger.error(
                "source HTML payload encode failed: domain=\(nsError.domain, privacy: .public) code=\(nsError.code, privacy: .public) description=\(nsError.localizedDescription, privacy: .private)"
            )
            return ""
        }

        return data.base64EncodedString()
    }

    private static func syntaxAccentHex(for kind: SyntaxThemeKind) -> String {
        switch kind {
        case .monokai: return "#f92672"
        case .github: return "#d73a49"
        case .githubDark: return "#ff7b72"
        case .oneLight: return "#a626a4"
        case .oneDark: return "#c678dd"
        case .dracula: return "#ff79c6"
        case .nord: return "#81a1c1"
        case .gruvboxLight: return "#9d0006"
        case .gruvboxDark: return "#fb4934"
        case .solarizedLight: return "#859900"
        case .solarizedDark: return "#859900"
        case .xcode: return "#ad3da4"
        }
    }

    private static func syntaxStringHex(for kind: SyntaxThemeKind) -> String {
        switch kind {
        case .monokai: return "#e6db74"
        case .github: return "#032f62"
        case .githubDark: return "#a5d6ff"
        case .oneLight: return "#50a14f"
        case .oneDark: return "#98c379"
        case .dracula: return "#f1fa8c"
        case .nord: return "#a3be8c"
        case .gruvboxLight: return "#79740e"
        case .gruvboxDark: return "#b8bb26"
        case .solarizedLight: return "#2aa198"
        case .solarizedDark: return "#2aa198"
        case .xcode: return "#c41a16"
        }
    }

    private static func syntaxDeletedHex(for kind: SyntaxThemeKind) -> String {
        switch kind {
        case .monokai: return "#f92672"
        case .github: return "#cf222e"
        case .githubDark: return "#f85149"
        case .oneLight: return "#e45649"
        case .oneDark: return "#e06c75"
        case .dracula: return "#ff5555"
        case .nord: return "#bf616a"
        case .gruvboxLight: return "#cc241d"
        case .gruvboxDark: return "#fb4934"
        case .solarizedLight: return "#dc322f"
        case .solarizedDark: return "#dc322f"
        case .xcode: return "#c41a16"
        }
    }

    private static func selectionHex(for theme: Theme) -> String {
        switch theme.kind {
        case .blackOnWhite: return "rgba(0, 95, 204, 0.18)"
        case .whiteOnBlack: return "rgba(125, 180, 255, 0.22)"
        case .darkGreyOnLightGrey: return "rgba(0, 79, 154, 0.18)"
        case .lightGreyOnDarkGrey: return "rgba(138, 185, 255, 0.22)"
        case .amberTerminal: return "rgba(255, 176, 0, 0.22)"
        case .greenTerminal, .greenTerminalStatic: return "rgba(0, 255, 65, 0.22)"
        case .newspaper: return "rgba(26, 77, 143, 0.18)"
        case .focus: return "rgba(44, 44, 44, 0.12)"
        case .commodore64: return "rgba(160, 160, 255, 0.22)"
        case .gameBoy: return "rgba(15, 56, 15, 0.22)"
        case .gruvboxDark: return "rgba(251, 73, 52, 0.18)"
        case .gruvboxLight: return "rgba(157, 0, 6, 0.18)"
        case .dracula: return "rgba(139, 233, 253, 0.22)"
        case .monokai: return "rgba(166, 226, 46, 0.22)"
        }
    }

    private static func isDarkTheme(_ theme: Theme) -> Bool {
        theme.kind.isDark
    }
}