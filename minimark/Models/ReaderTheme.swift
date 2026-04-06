import Foundation

nonisolated enum ReaderThemeKind: String, CaseIterable, Codable, Sendable {
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

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)

        if let kind = ReaderThemeKind(rawValue: rawValue) {
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
                debugDescription: "Unknown ReaderThemeKind: \(rawValue)"
            )
        }
    }

    var isDark: Bool {
        switch self {
        case .blackOnWhite, .darkGreyOnLightGrey, .newspaper, .focus, .gameBoy:
            return false
        case .whiteOnBlack, .lightGreyOnDarkGrey, .amberTerminal, .greenTerminal, .greenTerminalStatic, .commodore64:
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
        }
    }
}

nonisolated struct ReaderTheme: Equatable, Codable, Sendable {
    let kind: ReaderThemeKind
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

    static let `default` = ReaderTheme.theme(for: .blackOnWhite)

    static func theme(for kind: ReaderThemeKind) -> ReaderTheme {
        switch kind {
        case .blackOnWhite:
            return ReaderTheme(
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
                hasLightBackground: true
            )
        case .whiteOnBlack:
            return ReaderTheme(
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
                hasLightBackground: false
            )
        case .darkGreyOnLightGrey:
            return ReaderTheme(
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
                hasLightBackground: true
            )
        case .lightGreyOnDarkGrey:
            return ReaderTheme(
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
                hasLightBackground: false
            )
        case .amberTerminal:
            return ReaderTheme(
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
                hasLightBackground: false
            )
        case .greenTerminal, .greenTerminalStatic:
            return ReaderTheme(
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
                hasLightBackground: false
            )
        case .newspaper:
            return ReaderTheme(
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
                hasLightBackground: true
            )
        case .focus:
            return ReaderTheme(
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
                hasLightBackground: true
            )
        case .commodore64:
            return ReaderTheme(
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
                hasLightBackground: false
            )
        case .gameBoy:
            return ReaderTheme(
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
                hasLightBackground: true
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
        }
        """
    }
}
