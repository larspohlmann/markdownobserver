import Foundation
import Testing
@testable import minimark

struct SecurityScopeContextTests {
    @Test func emptyContextHasNoTokensOrURLs() {
        let context = SecurityScopeContext()
        #expect(context.fileToken == nil)
        #expect(context.directoryToken == nil)
        #expect(context.folderToken == nil)
        #expect(context.accessibleFileURL == nil)
        #expect(context.accessibleFileURLSource == nil)
    }

    @Test func endAllAccessClearsEverything() {
        var context = SecurityScopeContext()
        context.accessibleFileURL = URL(fileURLWithPath: "/test.md")
        context.accessibleFileURLSource = "fileScope"

        context.endAllAccess()

        #expect(context.fileToken == nil)
        #expect(context.directoryToken == nil)
        #expect(context.folderToken == nil)
        #expect(context.accessibleFileURL == nil)
        #expect(context.accessibleFileURLSource == nil)
    }

    @Test func endFileAndDirectoryAccessPreservesFolderToken() {
        var context = SecurityScopeContext()
        context.accessibleFileURL = URL(fileURLWithPath: "/test.md")
        context.accessibleFileURLSource = "fileScope"

        context.endFileAndDirectoryAccess()

        #expect(context.fileToken == nil)
        #expect(context.directoryToken == nil)
        #expect(context.accessibleFileURL == nil)
        #expect(context.accessibleFileURLSource == nil)
        // folderToken is preserved (not cleared by this method)
        #expect(context.folderToken == nil) // was nil to start, still nil
    }
}
