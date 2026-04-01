import Foundation

nonisolated enum ReaderThemeKind: String, CaseIterable, Codable, Sendable {
    case blackOnWhite
    case whiteOnBlack
    case darkGreyOnLightGrey
    case lightGreyOnDarkGrey

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
        case .blackOnWhite, .darkGreyOnLightGrey:
            return false
        case .whiteOnBlack, .lightGreyOnDarkGrey:
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
                changeDeletedHex: "#CF222E"
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
                changeDeletedHex: "#F85149"
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
                changeDeletedHex: "#CF222E"
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
                changeDeletedHex: "#F85149"
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
