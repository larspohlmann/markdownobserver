import Foundation

nonisolated enum SyntaxThemeKind: String, CaseIterable, Codable, Sendable {
    case monokai
    case github
    case githubDark
    case oneLight
    case oneDark
    case dracula
    case nord
    case gruvboxLight
    case gruvboxDark
    case solarizedLight
    case solarizedDark
    case xcode

    static let `default`: SyntaxThemeKind = .monokai

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)

        if let kind = SyntaxThemeKind(rawValue: rawValue) {
            self = kind
            return
        }

        switch rawValue {
        case "atomLight":
            self = .github
        case "atomDark":
            self = .githubDark
        case "atomOneLight":
            self = .oneLight
        case "atomOneDark":
            self = .oneDark
        default:
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown SyntaxThemeKind: \(rawValue)"
            )
        }
    }

    var displayName: String {
        switch self {
        case .monokai:
            return "Monokai"
        case .github:
            return "GitHub"
        case .githubDark:
            return "GitHub Dark"
        case .oneLight:
            return "One Light"
        case .oneDark:
            return "One Dark"
        case .dracula:
            return "Dracula"
        case .nord:
            return "Nord"
        case .gruvboxLight:
            return "Gruvbox Light"
        case .gruvboxDark:
            return "Gruvbox Dark"
        case .solarizedLight:
            return "Solarized Light"
        case .solarizedDark:
            return "Solarized Dark"
        case .xcode:
            return "Xcode"
        }
    }

    var css: String {
        let palette = syntaxPalette
        return """
                :root {
                    --reader-mark-signal: \(palette.markSignalHex);
                    --reader-blockquote-accent: \(palette.blockquoteAccentHex);
                    --reader-blockquote-bg: \(palette.blockquoteBackgroundHex);
                    --reader-blockquote-fg: \(palette.blockquoteForegroundHex);
                }

        pre {
          background: \(palette.blockBackgroundHex);
          border: 1px solid \(palette.blockBorderHex);
        }

        pre code,
        pre code.hljs,
        pre code[class*="language-"] {
          color: \(palette.blockTextHex);
          background: transparent;
          display: block;
          padding: 0;
        }

        pre code .hljs-comment { color: \(palette.commentHex); }
        pre code .hljs-keyword { color: \(palette.keywordHex); }
        pre code .hljs-string { color: \(palette.stringHex); }
        pre code .hljs-number { color: \(palette.numberHex); }
        pre code .hljs-title { color: \(palette.titleHex); }
        pre code .hljs-built_in { color: \(palette.builtInHex); }
        """
    }

    var changeEditedHex: String {
        syntaxPalette.changeEditedHex
    }

    var changeDeletedHex: String {
        syntaxPalette.changeDeletedHex
    }

    var previewPalette: SyntaxThemePreviewPalette {
        let palette = syntaxPalette
        return SyntaxThemePreviewPalette(
            blockTextHex: palette.blockTextHex,
            blockBackgroundHex: palette.blockBackgroundHex,
            blockBorderHex: palette.blockBorderHex,
            commentHex: palette.commentHex,
            keywordHex: palette.keywordHex,
            stringHex: palette.stringHex,
            numberHex: palette.numberHex,
            titleHex: palette.titleHex,
            builtInHex: palette.builtInHex
        )
    }

    private var syntaxPalette: SyntaxPalette {
        switch self {
        case .monokai:
            return SyntaxPalette(
                blockTextHex: "#F8F8F2",
                blockBackgroundHex: "#272822",
                blockBorderHex: "#3A3C33",
                commentHex: "#75715E",
                keywordHex: "#F92672",
                stringHex: "#E6DB74",
                numberHex: "#AE81FF",
                titleHex: "#A6E22E",
                builtInHex: "#66D9EF",
                changeAddedHex: "#A6E22E",
                changeEditedHex: "#E6DB74",
                changeDeletedHex: "#F92672"
            )
        case .github:
            return SyntaxPalette(
                blockTextHex: "#24292F",
                blockBackgroundHex: "#F6F8FA",
                blockBorderHex: "#D0D7DE",
                commentHex: "#6A737D",
                keywordHex: "#D73A49",
                stringHex: "#032F62",
                numberHex: "#005CC5",
                titleHex: "#6F42C1",
                builtInHex: "#E36209",
                changeAddedHex: "#1A7F37",
                changeEditedHex: "#9A6700",
                changeDeletedHex: "#CF222E"
            )
        case .githubDark:
            return SyntaxPalette(
                blockTextHex: "#C9D1D9",
                blockBackgroundHex: "#161B22",
                blockBorderHex: "#30363D",
                commentHex: "#8B949E",
                keywordHex: "#FF7B72",
                stringHex: "#A5D6FF",
                numberHex: "#79C0FF",
                titleHex: "#D2A8FF",
                builtInHex: "#FFA657",
                changeAddedHex: "#3FB950",
                changeEditedHex: "#D29922",
                changeDeletedHex: "#F85149"
            )
        case .oneLight:
            return SyntaxPalette(
                blockTextHex: "#383A42",
                blockBackgroundHex: "#FAFAFA",
                blockBorderHex: "#D7DAE0",
                commentHex: "#A0A1A7",
                keywordHex: "#A626A4",
                stringHex: "#50A14F",
                numberHex: "#986801",
                titleHex: "#4078F2",
                builtInHex: "#C18401",
                changeAddedHex: "#22863A",
                changeEditedHex: "#9A6700",
                changeDeletedHex: "#CF222E"
            )
        case .oneDark:
            return SyntaxPalette(
                blockTextHex: "#ABB2BF",
                blockBackgroundHex: "#282C34",
                blockBorderHex: "#3A404A",
                commentHex: "#5C6370",
                keywordHex: "#C678DD",
                stringHex: "#98C379",
                numberHex: "#D19A66",
                titleHex: "#61AFEF",
                builtInHex: "#E5C07B",
                changeAddedHex: "#98C379",
                changeEditedHex: "#E5C07B",
                changeDeletedHex: "#E06C75"
            )
        case .dracula:
            return SyntaxPalette(
                blockTextHex: "#F8F8F2",
                blockBackgroundHex: "#282A36",
                blockBorderHex: "#44475A",
                commentHex: "#6272A4",
                keywordHex: "#FF79C6",
                stringHex: "#F1FA8C",
                numberHex: "#BD93F9",
                titleHex: "#8BE9FD",
                builtInHex: "#50FA7B",
                changeAddedHex: "#50FA7B",
                changeEditedHex: "#F1FA8C",
                changeDeletedHex: "#FF5555"
            )
        case .nord:
            return SyntaxPalette(
                blockTextHex: "#D8DEE9",
                blockBackgroundHex: "#2E3440",
                blockBorderHex: "#4C566A",
                commentHex: "#616E88",
                keywordHex: "#81A1C1",
                stringHex: "#A3BE8C",
                numberHex: "#B48EAD",
                titleHex: "#88C0D0",
                builtInHex: "#EBCB8B",
                changeAddedHex: "#A3BE8C",
                changeEditedHex: "#EBCB8B",
                changeDeletedHex: "#BF616A"
            )
        case .gruvboxLight:
            return SyntaxPalette(
                blockTextHex: "#3C3836",
                blockBackgroundHex: "#FBF1C7",
                blockBorderHex: "#D5C4A1",
                commentHex: "#928374",
                keywordHex: "#9D0006",
                stringHex: "#79740E",
                numberHex: "#8F3F71",
                titleHex: "#076678",
                builtInHex: "#B57614",
                changeAddedHex: "#79740E",
                changeEditedHex: "#B57614",
                changeDeletedHex: "#CC241D"
            )
        case .gruvboxDark:
            return SyntaxPalette(
                blockTextHex: "#EBDBB2",
                blockBackgroundHex: "#282828",
                blockBorderHex: "#504945",
                commentHex: "#928374",
                keywordHex: "#FB4934",
                stringHex: "#B8BB26",
                numberHex: "#D3869B",
                titleHex: "#83A598",
                builtInHex: "#FABD2F",
                changeAddedHex: "#B8BB26",
                changeEditedHex: "#FABD2F",
                changeDeletedHex: "#FB4934"
            )
        case .solarizedLight:
            return SyntaxPalette(
                blockTextHex: "#586E75",
                blockBackgroundHex: "#FDF6E3",
                blockBorderHex: "#EEE8D5",
                commentHex: "#93A1A1",
                keywordHex: "#859900",
                stringHex: "#2AA198",
                numberHex: "#D33682",
                titleHex: "#268BD2",
                builtInHex: "#B58900",
                changeAddedHex: "#859900",
                changeEditedHex: "#B58900",
                changeDeletedHex: "#DC322F"
            )
        case .solarizedDark:
            return SyntaxPalette(
                blockTextHex: "#93A1A1",
                blockBackgroundHex: "#002B36",
                blockBorderHex: "#073642",
                commentHex: "#586E75",
                keywordHex: "#859900",
                stringHex: "#2AA198",
                numberHex: "#D33682",
                titleHex: "#268BD2",
                builtInHex: "#B58900",
                changeAddedHex: "#859900",
                changeEditedHex: "#B58900",
                changeDeletedHex: "#DC322F"
            )
        case .xcode:
            return SyntaxPalette(
                blockTextHex: "#1F2328",
                blockBackgroundHex: "#F5F7FA",
                blockBorderHex: "#D0D7DE",
                commentHex: "#6C7986",
                keywordHex: "#AD3DA4",
                stringHex: "#C41A16",
                numberHex: "#1C00CF",
                titleHex: "#1C00CF",
                builtInHex: "#5D4FFF",
                changeAddedHex: "#248A3D",
                changeEditedHex: "#B57F00",
                changeDeletedHex: "#D12F1B"
            )
        }
    }
}

nonisolated struct SyntaxThemePreviewPalette: Sendable {
    let blockTextHex: String
    let blockBackgroundHex: String
    let blockBorderHex: String
    let commentHex: String
    let keywordHex: String
    let stringHex: String
    let numberHex: String
    let titleHex: String
    let builtInHex: String
}

nonisolated private struct SyntaxPalette: Sendable {
    let blockTextHex: String
    let blockBackgroundHex: String
    let blockBorderHex: String
    let commentHex: String
    let keywordHex: String
    let stringHex: String
    let numberHex: String
    let titleHex: String
    let builtInHex: String
    let changeAddedHex: String
    let changeEditedHex: String
    let changeDeletedHex: String
    let markSignalHex: String
    let blockquoteAccentHex: String
    let blockquoteBackgroundHex: String
    let blockquoteForegroundHex: String

    init(
        blockTextHex: String,
        blockBackgroundHex: String,
        blockBorderHex: String,
        commentHex: String,
        keywordHex: String,
        stringHex: String,
        numberHex: String,
        titleHex: String,
        builtInHex: String,
        changeAddedHex: String,
        changeEditedHex: String,
        changeDeletedHex: String,
        markSignalHex: String? = nil,
        blockquoteAccentHex: String? = nil,
        blockquoteBackgroundHex: String? = nil,
        blockquoteForegroundHex: String? = nil
    ) {
        self.blockTextHex = blockTextHex
        self.blockBackgroundHex = blockBackgroundHex
        self.blockBorderHex = blockBorderHex
        self.commentHex = commentHex
        self.keywordHex = keywordHex
        self.stringHex = stringHex
        self.numberHex = numberHex
        self.titleHex = titleHex
        self.builtInHex = builtInHex
        self.changeAddedHex = changeAddedHex
        self.changeEditedHex = changeEditedHex
        self.changeDeletedHex = changeDeletedHex
        self.markSignalHex = markSignalHex ?? changeEditedHex
        self.blockquoteAccentHex = blockquoteAccentHex ?? blockBorderHex
        self.blockquoteBackgroundHex = blockquoteBackgroundHex ?? blockBackgroundHex
        self.blockquoteForegroundHex = blockquoteForegroundHex ?? blockTextHex
    }
}
