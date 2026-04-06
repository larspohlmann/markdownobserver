// minimark/Stores/Coordination/ReaderStore+TableOfContents.swift
import Foundation

extension ReaderStore {
    func updateTOCHeadings(_ headings: [TOCHeading]) {
        guard tocHeadings != headings else { return }
        tocHeadings = headings
    }

    func toggleTOC() {
        guard !tocHeadings.isEmpty else { return }
        isTOCVisible.toggle()
    }

    func hideTOC() {
        isTOCVisible = false
    }
}
