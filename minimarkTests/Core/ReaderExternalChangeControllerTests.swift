import Testing
@testable import minimark

@MainActor
@Suite("ReaderExternalChangeController")
struct ReaderExternalChangeControllerTests {
    @Test("noteObservedExternalChange sets state")
    func noteObservedExternalChangeSetsState() {
        let sut = ReaderExternalChangeController()
        sut.noteObservedExternalChange(kind: .modified)
        #expect(sut.hasUnacknowledgedExternalChange)
        #expect(sut.lastExternalChangeAt != nil)
        #expect(sut.unacknowledgedExternalChangeKind == .modified)
    }

    @Test("noteObservedExternalChange fires callback when kind changes")
    func noteObservedExternalChangeFiresCallback() {
        let sut = ReaderExternalChangeController()
        var callbackCount = 0
        sut.onExternalChangeKindChanged = { callbackCount += 1 }

        sut.noteObservedExternalChange(kind: .modified)
        #expect(callbackCount == 0)

        sut.noteObservedExternalChange(kind: .added)
        #expect(callbackCount == 1)
    }

    @Test("clear resets external change state")
    func clearResetsState() {
        let sut = ReaderExternalChangeController()
        sut.noteObservedExternalChange(kind: .added)
        sut.clear()
        #expect(!sut.hasUnacknowledgedExternalChange)
        #expect(sut.unacknowledgedExternalChangeKind == .modified)
    }
}
