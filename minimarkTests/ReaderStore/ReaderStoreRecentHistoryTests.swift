import Foundation
import Testing
@testable import minimark

@Suite(.serialized)
struct ReaderStoreRecentHistoryTests {
    @Test @MainActor func manualFileOpenRecordsRecentFileHistoryButAutoOpenDoesNot() throws {
        let fixture = try ReaderStoreTestFixture(autoRefreshOnExternalChange: false)
        defer { fixture.cleanup() }

        fixture.store.openFile(at: fixture.primaryFileURL, origin: .manual)
        fixture.store.openFile(at: fixture.secondaryFileURL, origin: .folderWatchAutoOpen)

        #expect(fixture.settings.recordedRecentManuallyOpenedFiles.map(\.filePath) == [fixture.primaryFileURL.path])
    }
}