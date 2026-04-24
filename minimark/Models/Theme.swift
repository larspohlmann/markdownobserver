import Foundation

nonisolated enum ThemeKind: String, CaseIterable, Codable, Sendable {
    case blackOnWhite
    case whiteOnBlack
    case darkGreyOnLightGrey
    case lightGreyOnDarkGrey
    case amberTerminal
    case greenTerminal
    case greenTerminalStatic
    case newspaper
    case focus
    case commodore64
    case gameBoy
    case gruvboxDark
    case gruvboxLight
    case dracula
    case monokai
    case reef
    case neon
    case nord
    case tokyoNight
    case tufte
    case paper

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)

        if let kind = ThemeKind(rawValue: rawValue) {
            self = kind
            return
        }

        switch rawValue {
        case "paper":
            self = .blackOnWhite
        case "graphite":
            self = .whiteOnBlack
        case "sepia":
            self = .darkGreyOnLightGrey
        default:
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown ThemeKind: \(rawValue)"
            )
        }
    }

    var isDark: Bool {
        switch self {
        case .blackOnWhite, .darkGreyOnLightGrey, .newspaper, .focus, .gameBoy, .gruvboxLight, .tufte, .paper:
            return false
        case .whiteOnBlack, .lightGreyOnDarkGrey, .amberTerminal, .greenTerminal, .greenTerminalStatic, .commodore64, .gruvboxDark, .dracula, .monokai, .reef, .neon, .nord, .tokyoNight:
            return true
        }
    }

    var displayName: String {
        switch self {
        case .blackOnWhite:
            return "White background / Black text"
        case .whiteOnBlack:
            return "Black background / White text"
        case .darkGreyOnLightGrey:
            return "Light gray background / Dark gray text"
        case .lightGreyOnDarkGrey:
            return "Dark gray background / Light gray text"
        case .amberTerminal:
            return "Amber Terminal"
        case .greenTerminal:
            return "Green Terminal"
        case .greenTerminalStatic:
            return "Green Terminal (Static)"
        case .newspaper:
            return "Newspaper"
        case .focus:
            return "Focus"
        case .commodore64:
            return "Commodore 64"
        case .gameBoy:
            return "Game Boy"
        case .gruvboxDark:
            return "Gruvbox Dark"
        case .gruvboxLight:
            return "Gruvbox Light"
        case .dracula:
            return "Dracula"
        case .monokai:
            return "Monokai"
        case .reef:
            return "Reef"
        case .neon:
            return "Neon"
        case .nord:
            return "Nord"
        case .tokyoNight:
            return "Tokyo Night"
        case .tufte:
            return "Tufte"
        case .paper:
            return "Paper"
        }
    }
}

nonisolated struct Theme: Equatable, Codable, Sendable {
    let kind: ThemeKind
    let backgroundHex: String
    let foregroundHex: String
    let secondaryForegroundHex: String
    let codeBackgroundHex: String
    let borderHex: String
    let linkHex: String
    let changedBlockHex: String
    let changeAddedHex: String
    let changeEditedHex: String
    let changeDeletedHex: String
    let hasLightBackground: Bool
    let h1Hex: String?
    let h2Hex: String?
    let h3Hex: String?

    static let `default` = Theme.theme(for: .blackOnWhite)

    static func theme(for kind: ThemeKind) -> Theme {
        switch kind {
        case .blackOnWhite:
            return Theme(
                kind: .blackOnWhite,
                backgroundHex: "#FFFFFF",
                foregroundHex: "#111111",
                secondaryForegroundHex: "#4A4A4A",
                codeBackgroundHex: "#F3F3F3",
                borderHex: "#D9D9D9",
                linkHex: "#005FCC",
                changedBlockHex: "#FFF5CC",
                changeAddedHex: "#2DA44E",
                changeEditedHex: "#BF8700",
                changeDeletedHex: "#CF222E",
                hasLightBackground: true,
                h1Hex: nil, h2Hex: nil, h3Hex: nil
            )
        case .whiteOnBlack:
            return Theme(
                kind: .whiteOnBlack,
                backgroundHex: "#0D0D0D",
                foregroundHex: "#F5F5F5",
                secondaryForegroundHex: "#C6C6C6",
                codeBackgroundHex: "#1A1A1A",
                borderHex: "#303030",
                linkHex: "#7DB4FF",
                changedBlockHex: "#2C3A20",
                changeAddedHex: "#3FB950",
                changeEditedHex: "#D29922",
                changeDeletedHex: "#F85149",
                hasLightBackground: false,
                h1Hex: nil, h2Hex: nil, h3Hex: nil
            )
        case .darkGreyOnLightGrey:
            return Theme(
                kind: .darkGreyOnLightGrey,
                backgroundHex: "#E6E6E6",
                foregroundHex: "#2A2A2A",
                secondaryForegroundHex: "#505050",
                codeBackgroundHex: "#D9D9D9",
                borderHex: "#B8B8B8",
                linkHex: "#004F9A",
                changedBlockHex: "#F0E3B5",
                changeAddedHex: "#1A7F37",
                changeEditedHex: "#9A6700",
                changeDeletedHex: "#CF222E",
                hasLightBackground: true,
                h1Hex: nil, h2Hex: nil, h3Hex: nil
            )
        case .lightGreyOnDarkGrey:
            return Theme(
                kind: .lightGreyOnDarkGrey,
                backgroundHex: "#2B2B2B",
                foregroundHex: "#DCDCDC",
                secondaryForegroundHex: "#B5B5B5",
                codeBackgroundHex: "#3A3A3A",
                borderHex: "#5A5A5A",
                linkHex: "#8AB9FF",
                changedBlockHex: "#4D5128",
                changeAddedHex: "#3FB950",
                changeEditedHex: "#D29922",
                changeDeletedHex: "#F85149",
                hasLightBackground: false,
                h1Hex: nil, h2Hex: nil, h3Hex: nil
            )
        case .amberTerminal:
            return Theme(
                kind: .amberTerminal,
                backgroundHex: "#1A1200",
                foregroundHex: "#FFB000",
                secondaryForegroundHex: "#CC8800",
                codeBackgroundHex: "#1F1600",
                borderHex: "#3D2E00",
                linkHex: "#FFCC00",
                changedBlockHex: "#2A2000",
                changeAddedHex: "#7A9A40",
                changeEditedHex: "#CC8800",
                changeDeletedHex: "#6A4A2A",
                hasLightBackground: false,
                h1Hex: nil, h2Hex: nil, h3Hex: nil
            )
        case .greenTerminal, .greenTerminalStatic:
            return Theme(
                kind: kind,
                backgroundHex: "#0D0208",
                foregroundHex: "#00FF41",
                secondaryForegroundHex: "#008F11",
                codeBackgroundHex: "#0A0A0A",
                borderHex: "#003B00",
                linkHex: "#41FF7F",
                changedBlockHex: "#0A1F0A",
                changeAddedHex: "#00CC33",
                changeEditedHex: "#7FCC00",
                changeDeletedHex: "#1A3320",
                hasLightBackground: false,
                h1Hex: nil, h2Hex: nil, h3Hex: nil
            )
        case .newspaper:
            return Theme(
                kind: .newspaper,
                backgroundHex: "#FAF7F0",
                foregroundHex: "#1A1A1A",
                secondaryForegroundHex: "#4A4A4A",
                codeBackgroundHex: "#F0EDE4",
                borderHex: "#D4CFC4",
                linkHex: "#1A4D8F",
                changedBlockHex: "#F5F0D8",
                changeAddedHex: "#1A7F37",
                changeEditedHex: "#9A6700",
                changeDeletedHex: "#CF222E",
                hasLightBackground: true,
                h1Hex: nil, h2Hex: nil, h3Hex: nil
            )
        case .focus:
            return Theme(
                kind: .focus,
                backgroundHex: "#FAFAFA",
                foregroundHex: "#2C2C2C",
                secondaryForegroundHex: "#6B6B6B",
                codeBackgroundHex: "#F0F0F0",
                borderHex: "#E0E0E0",
                linkHex: "#2C2C2C",
                changedBlockHex: "#F0F0E8",
                changeAddedHex: "#5A9A5A",
                changeEditedHex: "#9A9A5A",
                changeDeletedHex: "#9A6A6A",
                hasLightBackground: true,
                h1Hex: nil, h2Hex: nil, h3Hex: nil
            )
        case .commodore64:
            return Theme(
                kind: .commodore64,
                backgroundHex: "#40318D",
                foregroundHex: "#C8C8FF",
                secondaryForegroundHex: "#7069C4",
                codeBackgroundHex: "#352879",
                borderHex: "#504694",
                linkHex: "#FFFFFF",
                changedBlockHex: "#4A3E9A",
                changeAddedHex: "#5CAB5E",
                changeEditedHex: "#C9D487",
                changeDeletedHex: "#9F4E44",
                hasLightBackground: false,
                h1Hex: nil, h2Hex: nil, h3Hex: nil
            )
        case .gameBoy:
            return Theme(
                kind: .gameBoy,
                backgroundHex: "#9BBC0F",
                foregroundHex: "#0F380F",
                secondaryForegroundHex: "#306230",
                codeBackgroundHex: "#8BAC0F",
                borderHex: "#306230",
                linkHex: "#0F380F",
                changedBlockHex: "#8BAC0F",
                changeAddedHex: "#0F380F",
                changeEditedHex: "#306230",
                changeDeletedHex: "#306230",
                hasLightBackground: true,
                h1Hex: nil, h2Hex: nil, h3Hex: nil
            )
        case .gruvboxDark:
            return Theme(
                kind: .gruvboxDark,
                backgroundHex: "#282828",
                foregroundHex: "#EBDBB2",
                secondaryForegroundHex: "#BDAE93",
                codeBackgroundHex: "#1D2021",
                borderHex: "#504945",
                linkHex: "#FE8019",
                changedBlockHex: "#2A2820",
                changeAddedHex: "#B8BB26",
                changeEditedHex: "#FABD2F",
                changeDeletedHex: "#FB4934",
                hasLightBackground: false,
                h1Hex: "#FB4934",
                h2Hex: "#B8BB26",
                h3Hex: "#83A598"
            )
        case .gruvboxLight:
            return Theme(
                kind: .gruvboxLight,
                backgroundHex: "#FBF1C7",
                foregroundHex: "#3C3836",
                secondaryForegroundHex: "#504945",
                codeBackgroundHex: "#EBDBB2",
                borderHex: "#D5C4A1",
                linkHex: "#076678",
                changedBlockHex: "#D5C4A1",
                changeAddedHex: "#79740E",
                changeEditedHex: "#B57614",
                changeDeletedHex: "#9D0006",
                hasLightBackground: true,
                h1Hex: "#9D0006",
                h2Hex: "#79740E",
                h3Hex: "#076678"
            )
        case .dracula:
            return Theme(
                kind: .dracula,
                backgroundHex: "#282A36",
                foregroundHex: "#F8F8F2",
                secondaryForegroundHex: "#BFC0D0",
                codeBackgroundHex: "#21222C",
                borderHex: "#44475A",
                linkHex: "#8BE9FD",
                changedBlockHex: "#1E3028",
                changeAddedHex: "#50FA7B",
                changeEditedHex: "#BD93F9",
                changeDeletedHex: "#FF79C6",
                hasLightBackground: false,
                h1Hex: "#FF79C6",
                h2Hex: "#50FA7B",
                h3Hex: "#8BE9FD"
            )
        case .monokai:
            return Theme(
                kind: .monokai,
                backgroundHex: "#272822",
                foregroundHex: "#F8F8F2",
                secondaryForegroundHex: "#CFCFC2",
                codeBackgroundHex: "#1E1F1C",
                borderHex: "#3A3C33",
                linkHex: "#A6E22E",
                changedBlockHex: "#1E2618",
                changeAddedHex: "#A6E22E",
                changeEditedHex: "#E6DB74",
                changeDeletedHex: "#F92672",
                hasLightBackground: false,
                h1Hex: "#F92672",
                h2Hex: "#A6E22E",
                h3Hex: "#66D9EF"
            )
        case .reef:
            return Theme(
                kind: .reef,
                backgroundHex: "#062B2E",
                foregroundHex: "#D0F0E8",
                secondaryForegroundHex: "#68B8B0",
                codeBackgroundHex: "#041A1C",
                borderHex: "#144048",
                linkHex: "#4ADCBA",
                changedBlockHex: "#0C3A40",
                changeAddedHex: "#7AE89C",
                changeEditedHex: "#E8C070",
                changeDeletedHex: "#E88080",
                hasLightBackground: false,
                h1Hex: nil, h2Hex: nil, h3Hex: nil
            )
        case .neon:
            return Theme(
                kind: .neon,
                backgroundHex: "#0A0820",
                foregroundHex: "#F2E8FF",
                secondaryForegroundHex: "#B478E8",
                codeBackgroundHex: "#140F2E",
                borderHex: "#3A1E6E",
                linkHex: "#FF2E8A",
                changedBlockHex: "#1F1440",
                changeAddedHex: "#00E8D6",
                changeEditedHex: "#FFCA28",
                changeDeletedHex: "#FF2E8A",
                hasLightBackground: false,
                h1Hex: nil, h2Hex: nil, h3Hex: nil
            )
        case .nord:
            return Theme(
                kind: .nord,
                backgroundHex: "#2E3440",
                foregroundHex: "#ECEFF4",
                secondaryForegroundHex: "#81A1C1",
                codeBackgroundHex: "#242933",
                borderHex: "#3B4252",
                linkHex: "#88C0D0",
                changedBlockHex: "#353B48",
                changeAddedHex: "#A3BE8C",
                changeEditedHex: "#EBCB8B",
                changeDeletedHex: "#BF616A",
                hasLightBackground: false,
                h1Hex: "#88C0D0",
                h2Hex: "#8FBCBB",
                h3Hex: "#5E81AC"
            )
        case .tokyoNight:
            return Theme(
                kind: .tokyoNight,
                backgroundHex: "#1A1B26",
                foregroundHex: "#C0CAF5",
                secondaryForegroundHex: "#9AA5CE",
                codeBackgroundHex: "#16161E",
                borderHex: "#292E42",
                linkHex: "#7AA2F7",
                changedBlockHex: "#1F2335",
                changeAddedHex: "#9ECE6A",
                changeEditedHex: "#E0AF68",
                changeDeletedHex: "#F7768E",
                hasLightBackground: false,
                h1Hex: "#BB9AF7",
                h2Hex: "#7AA2F7",
                h3Hex: "#7DCFFF"
            )
        case .tufte:
            return Theme(
                kind: .tufte,
                backgroundHex: "#FFFFF8",
                foregroundHex: "#111111",
                secondaryForegroundHex: "#5A5A5A",
                codeBackgroundHex: "#F5F3E9",
                borderHex: "#D4CEC0",
                linkHex: "#A01010",
                changedBlockHex: "#F5F3E9",
                changeAddedHex: "#2E4A1A",
                changeEditedHex: "#553F1F",
                changeDeletedHex: "#A01010",
                hasLightBackground: true,
                h1Hex: nil, h2Hex: nil, h3Hex: nil
            )
        case .paper:
            return Theme(
                kind: .paper,
                backgroundHex: "#FCFCFA",
                foregroundHex: "#1A1A1A",
                secondaryForegroundHex: "#555555",
                codeBackgroundHex: "#F4F4F0",
                borderHex: "#E4E2DC",
                linkHex: "#0B5FB8",
                changedBlockHex: "#F4F4F0",
                changeAddedHex: "#116622",
                changeEditedHex: "#AA5500",
                changeDeletedHex: "#B82020",
                hasLightBackground: true,
                h1Hex: nil, h2Hex: nil, h3Hex: nil
            )
        }
    }

    func cssVariables(baseFontSize: Double) -> String {
        let clampedSize = min(max(baseFontSize, 10.0), 48.0)
        return """
        :root {
          --reader-bg: \(backgroundHex);
          --reader-fg: \(foregroundHex);
          --reader-fg-secondary: \(secondaryForegroundHex);
          --reader-code-bg: \(codeBackgroundHex);
          --reader-border: \(borderHex);
          --reader-link: \(linkHex);
          --reader-changed-bg: \(changedBlockHex);
          --reader-changed-added: \(changeAddedHex);
          --reader-changed-edited: \(changeEditedHex);
          --reader-changed-deleted: \(changeDeletedHex);
          --reader-font-size: \(String(format: "%.1f", clampedSize))px;
          \(h1Hex.map { "--reader-h1: \($0);" } ?? "")
          \(h2Hex.map { "--reader-h2: \($0);" } ?? "")
          \(h3Hex.map { "--reader-h3: \($0);" } ?? "")
        }
        """
    }
}

extension Theme {
    func applyingOverride(_ override: ThemeOverride?) -> Theme {
        guard let override, override.themeKind == kind else { return self }
        let newBackground = override.backgroundHex ?? backgroundHex
        let newForeground = override.foregroundHex ?? foregroundHex
        if newBackground == backgroundHex && newForeground == foregroundHex {
            return self
        }
        return Theme(
            kind: kind,
            backgroundHex: newBackground,
            foregroundHex: newForeground,
            secondaryForegroundHex: secondaryForegroundHex,
            codeBackgroundHex: codeBackgroundHex,
            borderHex: borderHex,
            linkHex: linkHex,
            changedBlockHex: changedBlockHex,
            changeAddedHex: changeAddedHex,
            changeEditedHex: changeEditedHex,
            changeDeletedHex: changeDeletedHex,
            hasLightBackground: hasLightBackground,
            h1Hex: h1Hex,
            h2Hex: h2Hex,
            h3Hex: h3Hex
        )
    }
}
