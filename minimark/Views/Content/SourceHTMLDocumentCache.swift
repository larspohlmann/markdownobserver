//
//  SourceHTMLDocumentCache.swift
//  minimark
//

import Foundation

struct SourceHTMLDocumentCache {
    private struct Inputs: Equatable {
        let markdown: String
        let settings: ReaderSettings
        let isEditable: Bool
    }

    private var lastInputs: Inputs?
    private(set) var document: String = ""

    mutating func refreshIfNeeded(markdown: String, settings: ReaderSettings, isEditable: Bool) {
        let inputs = Inputs(markdown: markdown, settings: settings, isEditable: isEditable)
        guard lastInputs != inputs else { return }
        lastInputs = inputs
        document = MarkdownSourceHTMLRenderer.makeHTMLDocument(
            markdown: markdown,
            settings: settings,
            isEditable: isEditable
        )
    }
}
