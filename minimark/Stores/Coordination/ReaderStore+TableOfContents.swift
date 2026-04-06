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

    func scrollToTOCHeading(_ heading: TOCHeading) {
        tocScrollRequestCounter += 1
        tocScrollRequest = TOCScrollRequest(heading: heading, requestID: tocScrollRequestCounter)
        isTOCVisible = false
    }
}
