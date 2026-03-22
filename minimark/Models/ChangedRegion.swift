import Foundation

enum ChangedRegionKind: String, Codable, Equatable, Sendable {
    case added
    case edited
    case deleted
}

enum ChangedRegionAnchorPlacement: String, Codable, Equatable, Sendable {
    case before
    case after
}

struct ChangedRegion: Equatable, Sendable {
    let blockIndex: Int
    let lineRange: ClosedRange<Int>
    let kind: ChangedRegionKind
    let anchorPlacement: ChangedRegionAnchorPlacement?
    let deletedLineCount: Int?
    let previousTextSnippet: String?
    let currentTextSnippet: String?

    init(
        blockIndex: Int,
        lineRange: ClosedRange<Int>,
        kind: ChangedRegionKind = .edited,
        anchorPlacement: ChangedRegionAnchorPlacement? = nil,
        deletedLineCount: Int? = nil,
        previousTextSnippet: String? = nil,
        currentTextSnippet: String? = nil
    ) {
        self.blockIndex = blockIndex
        self.lineRange = lineRange
        self.kind = kind
        self.anchorPlacement = kind == .deleted ? anchorPlacement : nil

        if kind == .deleted, let deletedLineCount, deletedLineCount > 0 {
            self.deletedLineCount = deletedLineCount
        } else {
            self.deletedLineCount = nil
        }

        let normalizedPreviousTextSnippet = Self.normalizedSnippet(previousTextSnippet)
        let normalizedCurrentTextSnippet = Self.normalizedSnippet(currentTextSnippet)
        self.previousTextSnippet = normalizedPreviousTextSnippet
        self.currentTextSnippet = normalizedCurrentTextSnippet
    }

    var supportsInlineComparisonToggle: Bool {
        (kind == .edited || kind == .deleted) && previousTextSnippet != nil
    }

    private static func normalizedSnippet(_ snippet: String?) -> String? {
        guard let snippet else {
            return nil
        }

        let trimmed = snippet.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : snippet
    }
}

struct MarkdownBlock: Equatable, Sendable {
    let index: Int
    let text: String
    let lineRange: ClosedRange<Int>
}
