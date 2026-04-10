import Differ
import Foundation

protocol ChangedRegionDiffering {
    func computeChangedRegions(oldMarkdown: String, newMarkdown: String) -> [ChangedRegion]
    func blocks(for markdown: String) -> [MarkdownBlock]
}

struct ChangedRegionDiffer: ChangedRegionDiffering {
    private let maxSnippetLines = 8
    private let maxSnippetCharacters = 400

    func computeChangedRegions(oldMarkdown: String, newMarkdown: String) -> [ChangedRegion] {
        let oldSourceLines = sourceLines(for: oldMarkdown)
        let newSourceLines = sourceLines(for: newMarkdown)
        let newBlocks = blocks(for: newMarkdown)

        guard !oldSourceLines.isEmpty || !newSourceLines.isEmpty else {
            return []
        }

        let hunks = lineHunks(oldLines: oldSourceLines, newLines: newSourceLines)
        var changedRegions: [ChangedRegion] = []

        for hunk in hunks {
            changedRegions.append(
                contentsOf: regions(
                    for: hunk,
                    oldSourceLines: oldSourceLines,
                    newSourceLines: newSourceLines,
                    newBlocks: newBlocks
                )
            )
        }

        changedRegions = coalescedDeletedRegions(changedRegions)
        changedRegions = coalescedAdjacentRegions(changedRegions)

        return changedRegions.sorted { lhs, rhs in
            if lhs.lineRange.lowerBound != rhs.lineRange.lowerBound {
                return lhs.lineRange.lowerBound < rhs.lineRange.lowerBound
            }

            if lhs.kind != rhs.kind {
                return rank(for: lhs.kind) < rank(for: rhs.kind)
            }

            return lhs.blockIndex < rhs.blockIndex
        }
    }

    func blocks(for markdown: String) -> [MarkdownBlock] {
        let lines = sourceLines(for: markdown)
        var blocks: [MarkdownBlock] = []

        for (offset, line) in lines.enumerated() {
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty else {
                continue
            }

            let lineNumber = offset + 1
            blocks.append(
                MarkdownBlock(
                    index: blocks.count,
                    text: line,
                    lineRange: lineNumber...lineNumber
                )
            )
        }

        return blocks
    }

    private func regions(
        for hunk: LineChangeHunk,
        oldSourceLines: [String],
        newSourceLines: [String],
        newBlocks: [MarkdownBlock]
    ) -> [ChangedRegion] {
        let deletedLineNumbers = hunk.deletedLineNumbers
        let insertedLineNumbers = hunk.insertedLineNumbers
        let deletedSnippet = snippet(forLineNumbers: deletedLineNumbers, in: oldSourceLines, truncating: false)
        let insertedSnippet = snippet(forLineNumbers: insertedLineNumbers, in: newSourceLines, truncating: false)
        let deletedVisibleLines = deletedLineNumbers.compactMap { lineNumber -> String? in
            let index = lineNumber - 1
            guard oldSourceLines.indices.contains(index) else {
                return nil
            }

            let line = oldSourceLines[index]
            return line.trimmingCharacters(in: .whitespaces).isEmpty ? nil : line
        }
        let insertedBlocks = insertedLineNumbers.compactMap { lineNumber in
            block(for: lineNumber, in: newBlocks)
        }

        var changedRegions: [ChangedRegion] = []

        if !insertedBlocks.isEmpty {
            let regionKind: ChangedRegionKind = deletedVisibleLines.isEmpty ? .added : .edited

            for (offset, block) in insertedBlocks.enumerated() {
                let previousTextSnippet: String?
                if regionKind == .edited {
                    if deletedVisibleLines.indices.contains(offset) {
                        previousTextSnippet = truncatedSnippet(deletedVisibleLines[offset])
                    } else {
                        previousTextSnippet = deletedSnippet
                    }
                } else {
                    previousTextSnippet = nil
                }

                changedRegions.append(
                    ChangedRegion(
                        blockIndex: block.index,
                        lineRange: block.lineRange,
                        kind: regionKind,
                        previousTextSnippet: previousTextSnippet,
                        currentTextSnippet: regionKind == .edited ? truncatedSnippet(block.text) : nil
                    )
                )
            }
        }

        let deletedLineCount = max(deletedLineNumbers.count - insertedLineNumbers.count, 0)
        if shouldRenderDeletedRegion(
            deletedLineCount: deletedLineCount,
            insertedLineNumbers: insertedLineNumbers,
            deletedVisibleLines: deletedVisibleLines,
            deletedSnippet: deletedSnippet,
            insertedSnippet: insertedSnippet
        ),
           let anchor = deletionAnchor(
                insertionLineNumber: hunk.insertionLineNumber,
                newBlocks: newBlocks
           ) {
            changedRegions.append(
                ChangedRegion(
                    blockIndex: anchor.blockIndex,
                    lineRange: anchor.line...anchor.line,
                    kind: .deleted,
                    anchorPlacement: anchor.placement,
                    deletedLineCount: deletedLineCount,
                    previousTextSnippet: deletedSnippet
                )
            )
        }

        return changedRegions
    }

    private func lineHunks(oldLines: [String], newLines: [String]) -> [LineChangeHunk] {
        let traces = oldLines.outputDiffPathTraces(to: newLines, isEqual: ==)
        var hunks: [LineChangeHunk] = []
        var currentHunk: LineChangeHunk?

        for trace in traces {
            switch lineTraceKind(for: trace) {
            case .match:
                if let hunk = currentHunk {
                    hunks.append(hunk)
                    currentHunk = nil
                }

            case .deletion:
                if currentHunk == nil {
                    currentHunk = LineChangeHunk(insertionLineNumber: trace.from.y + 1)
                }
                currentHunk?.deletedLineNumbers.append(trace.from.x + 1)

            case .insertion:
                if currentHunk == nil {
                    currentHunk = LineChangeHunk(insertionLineNumber: trace.from.y + 1)
                }
                currentHunk?.insertedLineNumbers.append(trace.from.y + 1)
            }
        }

        if let hunk = currentHunk {
            hunks.append(hunk)
        }

        return hunks
    }

    private func lineTraceKind(for trace: Trace) -> LineTraceKind {
        if trace.to.x == trace.from.x + 1, trace.to.y == trace.from.y + 1 {
            return .match
        }

        if trace.to.y == trace.from.y + 1 {
            return .insertion
        }

        return .deletion
    }
    private func sourceLines(for markdown: String) -> [String] {
        let normalizedMarkdown = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        guard !normalizedMarkdown.isEmpty else {
            return []
        }

        return normalizedMarkdown.components(separatedBy: "\n")
    }

    private func block(for lineNumber: Int, in blocks: [MarkdownBlock]) -> MarkdownBlock? {
        blocks.first { $0.lineRange.lowerBound == lineNumber }
    }

    private func snippet(
        forLineNumbers lineNumbers: [Int],
        in lines: [String],
        truncating: Bool = true
    ) -> String? {
        guard !lineNumbers.isEmpty else {
            return nil
        }

        let text = lineNumbers.compactMap { lineNumber -> String? in
            let index = lineNumber - 1
            guard lines.indices.contains(index) else {
                return nil
            }

            return lines[index]
        }
        .joined(separator: "\n")

        return truncating ? truncatedSnippet(text) : normalizedSnippet(text)
    }

    private func normalizedSnippet(_ rawText: String) -> String? {
        let normalized = rawText
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        let lines = normalized.components(separatedBy: "\n")
        var start = 0
        var end = lines.count

        while start < end, lines[start].trimmingCharacters(in: .whitespaces).isEmpty {
            start += 1
        }

        while end > start, lines[end - 1].trimmingCharacters(in: .whitespaces).isEmpty {
            end -= 1
        }

        guard start < end else {
            return nil
        }

        let snippet = Array(lines[start..<end]).joined(separator: "\n")
        return snippet.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : snippet
    }

    private func truncatedSnippet(_ rawText: String) -> String? {
        guard let normalizedSnippet = normalizedSnippet(rawText) else {
            return nil
        }

        var visibleLines = normalizedSnippet.components(separatedBy: "\n")
        var wasTruncated = false

        if visibleLines.count > maxSnippetLines {
            visibleLines = Array(visibleLines.prefix(maxSnippetLines))
            wasTruncated = true
        }

        var snippet = visibleLines.joined(separator: "\n")
        if snippet.count > maxSnippetCharacters {
            let boundary = snippet.index(snippet.startIndex, offsetBy: maxSnippetCharacters)
            snippet = String(snippet[..<boundary])
            wasTruncated = true
        }

        if wasTruncated {
            snippet += "\n..."
        }

        return snippet.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : snippet
    }

    private func deletionAnchor(
        insertionLineNumber: Int,
        newBlocks: [MarkdownBlock]
    ) -> (blockIndex: Int, line: Int, placement: ChangedRegionAnchorPlacement)? {
        if let block = newBlocks.first(where: { $0.lineRange.lowerBound >= insertionLineNumber }) {
            return (blockIndex: block.index, line: block.lineRange.lowerBound, placement: .before)
        }

        if let previousBlock = newBlocks.last(where: { $0.lineRange.upperBound < insertionLineNumber }) {
            return (blockIndex: previousBlock.index, line: previousBlock.lineRange.upperBound, placement: .after)
        }

        return nil
    }

    private func shouldRenderDeletedRegion(
        deletedLineCount: Int,
        insertedLineNumbers: [Int],
        deletedVisibleLines: [String],
        deletedSnippet: String?,
        insertedSnippet: String?
    ) -> Bool {
        guard deletedLineCount > 0 else {
            return false
        }

        guard !insertedLineNumbers.isEmpty else {
            return true
        }

        if deletedVisibleLines.isEmpty {
            return false
        }

        return normalizedSnippet(deletedSnippet ?? "") != normalizedSnippet(insertedSnippet ?? "")
    }

    private func coalescedDeletedRegions(_ regions: [ChangedRegion]) -> [ChangedRegion] {
        var coalesced: [ChangedRegion] = []

        for region in regions {
            guard region.kind == .deleted else {
                coalesced.append(region)
                continue
            }

            guard let lastRegion = coalesced.last,
                  shouldMergeDeletedRegions(lastRegion, region) else {
                coalesced.append(region)
                continue
            }

            coalesced.removeLast()
            coalesced.append(mergedDeletedRegion(lastRegion, region))
        }

        return coalesced
    }

    private func shouldMergeDeletedRegions(_ lhs: ChangedRegion, _ rhs: ChangedRegion) -> Bool {
        guard lhs.kind == .deleted, rhs.kind == .deleted else {
            return false
        }

        guard lhs.anchorPlacement == rhs.anchorPlacement else {
            return false
        }

        let anchorDistance = rhs.lineRange.lowerBound - lhs.lineRange.upperBound
        return anchorDistance >= 0 && anchorDistance <= 1
    }

    private func mergedDeletedRegion(_ lhs: ChangedRegion, _ rhs: ChangedRegion) -> ChangedRegion {
        let mergedSnippet = mergedDeletedSnippet(lhs.previousTextSnippet, rhs.previousTextSnippet)
        return ChangedRegion(
            blockIndex: min(lhs.blockIndex, rhs.blockIndex),
            lineRange: lhs.lineRange.lowerBound...max(lhs.lineRange.upperBound, rhs.lineRange.upperBound),
            kind: .deleted,
            anchorPlacement: lhs.anchorPlacement,
            deletedLineCount: (lhs.deletedLineCount ?? 0) + (rhs.deletedLineCount ?? 0),
            previousTextSnippet: mergedSnippet
        )
    }

    private func mergedDeletedSnippet(_ lhs: String?, _ rhs: String?) -> String? {
        switch (lhs, rhs) {
        case let (lhs?, rhs?) where !lhs.isEmpty && !rhs.isEmpty:
            return normalizedSnippet(lhs + "\n" + rhs)
        case let (lhs?, _):
            return lhs
        case let (_, rhs?):
            return rhs
        default:
            return nil
        }
    }

    private func coalescedAdjacentRegions(_ regions: [ChangedRegion]) -> [ChangedRegion] {
        let sorted = regions.sorted { $0.lineRange.lowerBound < $1.lineRange.lowerBound }
        var coalesced: [ChangedRegion] = []

        for region in sorted {
            guard region.kind != .deleted,
                  let last = coalesced.last,
                  last.kind == region.kind,
                  region.lineRange.lowerBound == last.lineRange.upperBound + 1 else {
                coalesced.append(region)
                continue
            }

            coalesced.removeLast()
            coalesced.append(
                ChangedRegion(
                    blockIndex: min(last.blockIndex, region.blockIndex),
                    lineRange: last.lineRange.lowerBound...region.lineRange.upperBound,
                    kind: last.kind,
                    previousTextSnippet: mergedSnippet(last.previousTextSnippet, region.previousTextSnippet),
                    currentTextSnippet: mergedSnippet(last.currentTextSnippet, region.currentTextSnippet)
                )
            )
        }

        return coalesced
    }

    private func mergedSnippet(_ lhs: String?, _ rhs: String?) -> String? {
        switch (lhs, rhs) {
        case let (lhs?, rhs?) where !lhs.isEmpty && !rhs.isEmpty:
            return truncatedSnippet(lhs + "\n" + rhs)
        case let (lhs?, _):
            return lhs
        case let (_, rhs?):
            return rhs
        default:
            return nil
        }
    }

    private func rank(for kind: ChangedRegionKind) -> Int {
        switch kind {
        case .deleted:
            return 0
        case .edited:
            return 1
        case .added:
            return 2
        }
    }
}

private struct LineChangeHunk {
    let insertionLineNumber: Int
    var deletedLineNumbers: [Int] = []
    var insertedLineNumbers: [Int] = []
}

private enum LineTraceKind {
    case match
    case deletion
    case insertion
}
