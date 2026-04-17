import Foundation
import Testing
@testable import minimark

struct ReaderTopBarStoreProjectionTests {

    @MainActor
    @Test func projectionReflectsStoreState() throws {
        let fixture = try ReaderStoreTestFixture(autoRefreshOnExternalChange: false)
        defer { fixture.cleanup() }
        fixture.store.opener.open(at: fixture.primaryFileURL)
        let projection = TopBarStoreProjection(store: fixture.store)
        #expect(projection.fileURL != nil)
        #expect(projection.fileDisplayName == "first.md")
        #expect(projection.isSourceEditing == false)
        #expect(projection.hasUnsavedDraftChanges == false)
        #expect(projection.canSaveSourceDraft == false)
        #expect(projection.canDiscardSourceDraft == false)
        #expect(projection.isCurrentFileMissing == false)
    }

    @MainActor
    @Test func projectionReflectsEmptyStore() throws {
        let fixture = try ReaderStoreTestFixture(autoRefreshOnExternalChange: false)
        defer { fixture.cleanup() }
        let projection = TopBarStoreProjection(store: fixture.store)
        #expect(projection.fileURL == nil)
        #expect(projection.fileDisplayName == "")
        #expect(projection.isSourceEditing == false)
        #expect(projection.hasUnsavedDraftChanges == false)
        #expect(projection.canSaveSourceDraft == false)
        #expect(projection.canDiscardSourceDraft == false)
        #expect(projection.statusBarTimestamp == nil)
        #expect(projection.isCurrentFileMissing == false)
    }
}
