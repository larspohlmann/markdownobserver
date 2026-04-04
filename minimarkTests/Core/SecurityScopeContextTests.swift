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
        context.accessibleFileURLSource = .fileScope

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
        context.accessibleFileURLSource = .fileScope

        context.endFileAndDirectoryAccess()

        #expect(context.fileToken == nil)
        #expect(context.directoryToken == nil)
        #expect(context.accessibleFileURL == nil)
        #expect(context.accessibleFileURLSource == nil)
        // folderToken is preserved (not cleared by this method)
        #expect(context.folderToken == nil) // was nil to start, still nil
    }

    @Test func endFileAndDirectoryAccessPreservesNonNilFolderToken() {
        let fileToken = TestSecurityToken(url: URL(fileURLWithPath: "/file-scope"))
        let directoryToken = TestSecurityToken(url: URL(fileURLWithPath: "/dir-scope"))
        let folderToken = TestSecurityToken(url: URL(fileURLWithPath: "/folder-scope"))
        var context = SecurityScopeContext(
            fileToken: fileToken,
            directoryToken: directoryToken,
            folderToken: folderToken
        )
        context.accessibleFileURL = URL(fileURLWithPath: "/test.md")
        context.accessibleFileURLSource = .fileScope

        context.endFileAndDirectoryAccess()

        #expect(context.fileToken == nil)
        #expect(context.directoryToken == nil)
        #expect(context.accessibleFileURL == nil)
        #expect(context.accessibleFileURLSource == nil)
        #expect(context.folderToken != nil)
    }

    @Test func endAllAccessClearsAllTokensIncludingFolder() {
        let fileToken = TestSecurityToken(url: URL(fileURLWithPath: "/file-scope"))
        let directoryToken = TestSecurityToken(url: URL(fileURLWithPath: "/dir-scope"))
        let folderToken = TestSecurityToken(url: URL(fileURLWithPath: "/folder-scope"))
        var context = SecurityScopeContext(
            fileToken: fileToken,
            directoryToken: directoryToken,
            folderToken: folderToken
        )
        context.accessibleFileURL = URL(fileURLWithPath: "/test.md")
        context.accessibleFileURLSource = .fileScope

        context.endAllAccess()

        #expect(context.fileToken == nil)
        #expect(context.directoryToken == nil)
        #expect(context.folderToken == nil)
        #expect(context.accessibleFileURL == nil)
        #expect(context.accessibleFileURLSource == nil)
    }

    @Test func accessibleFileURLSourceTracksFileScope() {
        var context = SecurityScopeContext()
        context.accessibleFileURLSource = .fileScope
        #expect(context.accessibleFileURLSource == .fileScope)
    }

    @Test func accessibleFileURLSourceTracksFolderScopeChildURL() {
        var context = SecurityScopeContext()
        context.accessibleFileURLSource = .folderScopeChildURL
        #expect(context.accessibleFileURLSource == .folderScopeChildURL)
    }

    @Test func initWithAllParametersPopulated() {
        let fileToken = TestSecurityToken(url: URL(fileURLWithPath: "/file-scope"))
        let directoryToken = TestSecurityToken(url: URL(fileURLWithPath: "/dir-scope"))
        let folderToken = TestSecurityToken(url: URL(fileURLWithPath: "/folder-scope"))
        let fileURL = URL(fileURLWithPath: "/test.md")
        let context = SecurityScopeContext(
            fileToken: fileToken,
            directoryToken: directoryToken,
            folderToken: folderToken,
            accessibleFileURL: fileURL,
            accessibleFileURLSource: .fileScope
        )
        #expect(context.fileToken != nil)
        #expect(context.directoryToken != nil)
        #expect(context.folderToken != nil)
        #expect(context.accessibleFileURL == fileURL)
        #expect(context.accessibleFileURLSource == .fileScope)
    }
}
