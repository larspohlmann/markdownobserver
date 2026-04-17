import Testing
@testable import minimark

@MainActor
@Suite("TOCController")
struct ReaderTOCControllerTests {
    private func heading(id: String = "h1", title: String = "Title", level: Int = 1, index: Int = 0) -> TOCHeading {
        TOCHeading(elementID: id, level: level, title: title, sourceLine: nil, index: index)
    }

    @Test("updateHeadings sets headings")
    func updateHeadingsSetsHeadings() {
        let sut = TOCController()
        let headings = [heading()]
        sut.updateHeadings(headings)
        #expect(sut.headings == headings)
    }

    @Test("updateHeadings hides TOC when headings become empty")
    func updateHeadingsHidesTOCWhenEmpty() {
        let sut = TOCController()
        sut.updateHeadings([heading()])
        sut.isVisible = true
        sut.updateHeadings([])
        #expect(!sut.isVisible)
    }

    @Test("updateHeadings skips no-op when headings unchanged")
    func updateHeadingsSkipsNoOp() {
        let sut = TOCController()
        let headings = [heading()]
        sut.updateHeadings(headings)
        sut.isVisible = true
        sut.updateHeadings(headings)
        #expect(sut.isVisible)
    }

    @Test("toggle shows TOC when headings exist")
    func toggleShowsTOC() {
        let sut = TOCController()
        sut.updateHeadings([heading()])
        sut.toggle()
        #expect(sut.isVisible)
    }

    @Test("toggle does nothing when headings empty")
    func toggleNoOpWhenEmpty() {
        let sut = TOCController()
        sut.toggle()
        #expect(!sut.isVisible)
    }

    @Test("scrollTo sets request and hides TOC")
    func scrollToSetsRequestAndHides() {
        let sut = TOCController()
        let h = heading()
        sut.updateHeadings([h])
        sut.isVisible = true
        sut.scrollTo(h)
        #expect(sut.scrollRequest?.heading == h)
        #expect(sut.scrollRequest?.requestID == 1)
        #expect(!sut.isVisible)
    }

    @Test("scrollTo increments request counter")
    func scrollToIncrementsCounter() {
        let sut = TOCController()
        let h = heading()
        sut.scrollTo(h)
        sut.scrollTo(h)
        #expect(sut.scrollRequest?.requestID == 2)
    }

    @Test("clear resets all state")
    func clearResetsState() {
        let sut = TOCController()
        sut.updateHeadings([heading()])
        sut.isVisible = true
        sut.clear()
        #expect(sut.headings.isEmpty)
        #expect(!sut.isVisible)
    }
}
