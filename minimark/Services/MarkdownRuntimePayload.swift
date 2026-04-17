import Foundation

struct MarkdownRuntimePayload: Codable, Equatable, Sendable {
    let markdown: String
    let changedRegions: [ChangedRegionPayload]
    let unsavedChangedRegions: [ChangedRegionPayload]
}

struct ChangedRegionPayload: Codable, Equatable, Sendable {
    let blockIndex: Int
    let lineStart: Int
    let lineEnd: Int
    let kind: ChangedRegionKind
    let anchorPlacement: ChangedRegionAnchorPlacement?
    let deletedLineCount: Int?
    let previousTextSnippet: String?
    let currentTextSnippet: String?

    init(
        blockIndex: Int,
        lineStart: Int,
        lineEnd: Int,
        kind: ChangedRegionKind = .edited,
        anchorPlacement: ChangedRegionAnchorPlacement? = nil,
        deletedLineCount: Int? = nil,
        previousTextSnippet: String? = nil,
        currentTextSnippet: String? = nil
    ) {
        self.blockIndex = blockIndex
        self.lineStart = lineStart
        self.lineEnd = lineEnd
        self.kind = kind
        self.anchorPlacement = kind == .deleted ? anchorPlacement : nil

        if kind == .deleted, let deletedLineCount, deletedLineCount > 0 {
            self.deletedLineCount = deletedLineCount
        } else {
            self.deletedLineCount = nil
        }

        self.previousTextSnippet = Self.normalizedSnippet(previousTextSnippet)
        self.currentTextSnippet = Self.normalizedSnippet(currentTextSnippet)
    }

    private enum CodingKeys: String, CodingKey {
        case blockIndex
        case lineStart
        case lineEnd
        case kind
        case anchorPlacement
        case deletedLineCount
        case previousTextSnippet
        case currentTextSnippet
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        blockIndex = try container.decode(Int.self, forKey: .blockIndex)
        lineStart = try container.decode(Int.self, forKey: .lineStart)
        lineEnd = try container.decode(Int.self, forKey: .lineEnd)
        kind = try container.decodeIfPresent(ChangedRegionKind.self, forKey: .kind) ?? .edited
        anchorPlacement = kind == .deleted
            ? try container.decodeIfPresent(ChangedRegionAnchorPlacement.self, forKey: .anchorPlacement)
            : nil

        if kind == .deleted,
           let deletedLineCount = try container.decodeIfPresent(Int.self, forKey: .deletedLineCount),
           deletedLineCount > 0 {
            self.deletedLineCount = deletedLineCount
        } else {
            self.deletedLineCount = nil
        }

        previousTextSnippet = Self.normalizedSnippet(
            try container.decodeIfPresent(String.self, forKey: .previousTextSnippet)
        )
        currentTextSnippet = Self.normalizedSnippet(
            try container.decodeIfPresent(String.self, forKey: .currentTextSnippet)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(blockIndex, forKey: .blockIndex)
        try container.encode(lineStart, forKey: .lineStart)
        try container.encode(lineEnd, forKey: .lineEnd)
        try container.encode(kind, forKey: .kind)
        try container.encodeIfPresent(anchorPlacement, forKey: .anchorPlacement)
        try container.encodeIfPresent(deletedLineCount, forKey: .deletedLineCount)
        try container.encodeIfPresent(previousTextSnippet, forKey: .previousTextSnippet)
        try container.encodeIfPresent(currentTextSnippet, forKey: .currentTextSnippet)
    }

    private static func normalizedSnippet(_ snippet: String?) -> String? {
        guard let snippet else {
            return nil
        }

        let trimmed = snippet.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : snippet
    }
}

protocol MarkdownRuntimePayloadEncoding {
    func makePayloadBase64(
        markdown: String,
        changedRegions: [ChangedRegion],
        unsavedChangedRegions: [ChangedRegion]
    ) throws -> String
}

struct JSONBase64MarkdownRuntimePayloadEncoder: MarkdownRuntimePayloadEncoding {
    func makePayloadBase64(
        markdown: String,
        changedRegions: [ChangedRegion],
        unsavedChangedRegions: [ChangedRegion]
    ) throws -> String {
        let payload = MarkdownRuntimePayload(
            markdown: markdown,
            changedRegions: changedRegions.map {
                ChangedRegionPayload(
                    blockIndex: $0.blockIndex,
                    lineStart: $0.lineRange.lowerBound,
                    lineEnd: $0.lineRange.upperBound,
                    kind: $0.kind,
                    anchorPlacement: $0.anchorPlacement,
                    deletedLineCount: $0.deletedLineCount,
                    previousTextSnippet: $0.previousTextSnippet,
                    currentTextSnippet: $0.currentTextSnippet
                )
            },
            unsavedChangedRegions: unsavedChangedRegions.map {
                ChangedRegionPayload(
                    blockIndex: $0.blockIndex,
                    lineStart: $0.lineRange.lowerBound,
                    lineEnd: $0.lineRange.upperBound,
                    kind: $0.kind,
                    anchorPlacement: $0.anchorPlacement,
                    deletedLineCount: $0.deletedLineCount,
                    previousTextSnippet: $0.previousTextSnippet,
                    currentTextSnippet: $0.currentTextSnippet
                )
            }
        )

        do {
            let data = try JSONEncoder().encode(payload)
            return data.base64EncodedString()
        } catch {
            throw AppError.renderingFailed(underlying: error)
        }
    }
}
