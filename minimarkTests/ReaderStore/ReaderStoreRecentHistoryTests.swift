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

    @Test @MainActor func startWatchingFolderRecordsRecentWatchedFolderWithOptions() throws {
        let fixture = try ReaderStoreTestFixture(autoRefreshOnExternalChange: false)
        defer { fixture.cleanup() }

        let options = ReaderFolderWatchOptions(
            openMode: .openAllMarkdownFiles,
            scope: .includeSubfolders,
            excludedSubdirectoryPaths: [
                fixture.temporaryDirectoryURL.appendingPathComponent("node_modules", isDirectory: true).path
            ]
        )

        fixture.store.startWatchingFolder(folderURL: fixture.temporaryDirectoryURL, options: options)

        #expect(fixture.settings.recordedRecentWatchedFolders.map(\.folderPath) == [fixture.temporaryDirectoryURL.path])
        #expect(fixture.settings.recordedRecentWatchedFolders.first?.options == options)
    }
}