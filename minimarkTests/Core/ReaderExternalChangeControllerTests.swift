import Testing
@testable import minimark

@MainActor
@Suite("ExternalChangeController")
struct ReaderExternalChangeControllerTests {
    @Test("noteObservedExternalChange sets state")
    func noteObservedExternalChangeSetsState() {
        let sut = ExternalChangeController()
        sut.noteObservedExternalChange(kind: .modified)
        #expect(sut.hasUnacknowledgedExternalChange)
        #expect(sut.lastExternalChangeAt != nil)
        #expect(sut.unacknowledgedExternalChangeKind == .modified)
    }

    @Test("noteObservedExternalChange fires onStateChanged on meaningful change")
    func noteObservedExternalChangeFiresCallback() {
        let sut = ExternalChangeController()
        var callbackCount = 0
        sut.onStateChanged = { callbackCount += 1 }

        // First call: false → true (meaningful change)
        sut.noteObservedExternalChange(kind: .modified)
        #expect(callbackCount == 1)

        // Same kind while already unacknowledged: no state change
        sut.noteObservedExternalChange(kind: .modified)
        #expect(callbackCount == 1)

        // Kind change while unacknowledged: meaningful change
        sut.noteObservedExternalChange(kind: .added)
        #expect(callbackCount == 2)
    }

    @Test("clear resets external change state")
    func clearResetsState() {
        let sut = ExternalChangeController()
        sut.noteObservedExternalChange(kind: .added)
        sut.clear()
        #expect(!sut.hasUnacknowledgedExternalChange)
        #expect(sut.unacknowledgedExternalChangeKind == .modified)
    }

    @Test("clear fires onStateChanged only when unacknowledged")
    func clearFiresCallbackOnlyWhenUnacknowledged() {
        let sut = ExternalChangeController()
        var callbackCount = 0
        sut.onStateChanged = { callbackCount += 1 }

        // clear on already-clean state: no callback
        sut.clear()
        #expect(callbackCount == 0)

        sut.noteObservedExternalChange(kind: .added)
        callbackCount = 0

        // clear on dirty state: fires callback
        sut.clear()
        #expect(callbackCount == 1)
    }
}
