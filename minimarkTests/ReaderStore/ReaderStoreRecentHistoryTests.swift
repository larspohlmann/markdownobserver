import Foundation
import Testing
@testable import minimark

@Suite(.serialized)
struct ReaderStoreRecentHistoryTests {
    @Test @MainActor func manualFileOpenRecordsRecentFileHistoryButAutoOpenDoesNot() throws {
        let fixture = try ReaderStoreTestFixture(autoRefreshOnExternalChange: false)
        defer { fixture.cleanup() }

        fixture.store.opener.open(at: fixture.primaryFileURL, origin: .manual)
        fixture.store.opener.open(at: fixture.secondaryFileURL, origin: .folderWatchAutoOpen)

        #expect(fixture.settings.recordedRecentManuallyOpenedFiles.map(\.filePath) == [fixture.primaryFileURL.path])
    }
}