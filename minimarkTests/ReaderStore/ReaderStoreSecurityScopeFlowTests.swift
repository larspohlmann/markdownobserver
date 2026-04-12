import Foundation
import Testing
@testable import minimark

@Suite(.serialized)
struct ReaderStoreSecurityScopeFlowTests {

    // MARK: - effectiveAccessibleFileURL branches

    @Test @MainActor func branch1_fileScopeTokenUsedDirectly() throws {
        let fixture = try ReaderStoreTestFixture(autoRefreshOnExternalChange: false)
        defer { fixture.cleanup() }

        let resolver = fixture.store.securityScopeResolver
        resolver.activateFileSecurityScope(for: fixture.primaryFileURL, reason: "test")
        let result = resolver.effectiveAccessibleFileURL(
            for: fixture.primaryFileURL, reason: "test", folderWatchSession: nil
        )

        #expect(result == fixture.primaryFileURL)
        #expect(resolver.context.accessibleFileURLSource == .fileScope)
    }

    @Test @MainActor func branch2_cachedAccessibleURLMatchReturned() throws {
        let fixture = try ReaderStoreTestFixture(autoRefreshOnExternalChange: false)
        defer { fixture.cleanup() }

        let resolver = fixture.store.securityScopeResolver
        resolver.context.accessibleFileURL = fixture.primaryFileURL
        resolver.context.accessibleFileURLSource = .fileScope

        let result = resolver.effectiveAccessibleFileURL(
            for: fixture.primaryFileURL, reason: "test", folderWatchSession: nil
        )

        #expect(result == fixture.primaryFileURL)
        #expect(resolver.context.accessibleFileURLSource == .fileScope)
    }

    @Test @MainActor func branch3_folderScopeChildURLConstructed() throws {
        let fixture = try ReaderStoreTestFixture(autoRefreshOnExternalChange: false)
        defer { fixture.cleanup() }

        let resolver = fixture.store.securityScopeResolver
        let folderURL = fixture.temporaryDirectoryURL
        let options = ReaderFolderWatchOptions(openMode: .watchChangesOnly, scope: .includeSubfolders)
        let session = ReaderFolderWatchSession(folderURL: folderURL, options: options, startedAt: Date())

        fixture.settings.addRecentWatchedFolder(folderURL, options: options)
        fixture.store.setActiveFolderWatchSession(session)

        resolver.context.folderToken = fixture.securityScope.beginAccess(to: folderURL)
        resolver.context.fileToken = nil
        resolver.context.accessibleFileURL = nil
        resolver.context.accessibleFileURLSource = nil

        let result = resolver.effectiveAccessibleFileURL(
            for: fixture.primaryFileURL, reason: "test",
            folderWatchSession: fixture.store.activeFolderWatchSession
        )

        #expect(result.lastPathComponent == "first.md")
        #expect(resolver.context.accessibleFileURLSource == .folderScopeChildURL)
    }

    @Test @MainActor func branch4_fallbackReturnsNormalizedURL() throws {
        let fixture = try ReaderStoreTestFixture(autoRefreshOnExternalChange: false)
        defer { fixture.cleanup() }

        let resolver = fixture.store.securityScopeResolver
        resolver.context = SecurityScopeContext()

        let result = resolver.effectiveAccessibleFileURL(
            for: fixture.primaryFileURL, reason: "test", folderWatchSession: nil
        )

        #expect(result.lastPathComponent == "first.md")
    }

    // MARK: - folderScopedAccessibleFileURL

    @Test @MainActor func folderScopedAccessibleFileURLReturnsNilWithoutSession() throws {
        let fixture = try ReaderStoreTestFixture(autoRefreshOnExternalChange: false)
        defer { fixture.cleanup() }

        let resolver = fixture.store.securityScopeResolver
        let result = resolver.folderScopedAccessibleFileURL(
            for: fixture.primaryFileURL, folderWatchSession: nil
        )

        #expect(result == nil)
    }

    @Test @MainActor func folderScopedAccessibleFileURLReturnsNilWhenFileOutsideFolder() throws {
        let fixture = try ReaderStoreTestFixture(autoRefreshOnExternalChange: false)
        defer { fixture.cleanup() }

        let resolver = fixture.store.securityScopeResolver
        let folderURL = fixture.temporaryDirectoryURL
        let options = ReaderFolderWatchOptions(openMode: .watchChangesOnly, scope: .selectedFolderOnly)
        let session = ReaderFolderWatchSession(folderURL: folderURL, options: options, startedAt: Date())

        resolver.context.folderToken = fixture.securityScope.beginAccess(to: folderURL)

        let outsideURL = URL(fileURLWithPath: "/completely/different/path.md")
        let result = resolver.folderScopedAccessibleFileURL(
            for: outsideURL, folderWatchSession: session
        )

        #expect(result == nil)
    }

    // MARK: - watchedFolderSession

    @Test @MainActor func watchedFolderSessionAppliesToDirectChildInSelectedFolderOnlyMode() throws {
        let fixture = try ReaderStoreTestFixture(autoRefreshOnExternalChange: false)
        defer { fixture.cleanup() }

        let resolver = fixture.store.securityScopeResolver
        let folderURL = fixture.temporaryDirectoryURL
        let options = ReaderFolderWatchOptions(openMode: .watchChangesOnly, scope: .selectedFolderOnly)
        let session = ReaderFolderWatchSession(folderURL: folderURL, options: options, startedAt: Date())

        let directChild = folderURL.appendingPathComponent("file.md")
        let subfolderChild = folderURL.appendingPathComponent("sub/file.md")

        #expect(resolver.watchedFolderSession(session, appliesTo: directChild) == true)
        #expect(resolver.watchedFolderSession(session, appliesTo: subfolderChild) == false)
    }

    @Test @MainActor func watchedFolderSessionAppliesToSubfolderChildInIncludeSubfoldersMode() throws {
        let fixture = try ReaderStoreTestFixture(autoRefreshOnExternalChange: false)
        defer { fixture.cleanup() }

        let resolver = fixture.store.securityScopeResolver
        let folderURL = fixture.temporaryDirectoryURL
        let options = ReaderFolderWatchOptions(openMode: .watchChangesOnly, scope: .includeSubfolders)
        let session = ReaderFolderWatchSession(folderURL: folderURL, options: options, startedAt: Date())

        let subfolderChild = folderURL.appendingPathComponent("sub/nested/file.md")

        #expect(resolver.watchedFolderSession(session, appliesTo: subfolderChild) == true)
    }

    // MARK: - isPermissionDeniedWriteError

    @Test @MainActor func isPermissionDeniedWriteErrorRecognizesCocoaError() throws {
        let fixture = try ReaderStoreTestFixture(autoRefreshOnExternalChange: false)
        defer { fixture.cleanup() }

        let error = NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError)

        #expect(fixture.store.securityScopeResolver.isPermissionDeniedWriteError(error) == true)
    }

    @Test @MainActor func isPermissionDeniedWriteErrorRecognizesPOSIXEACCES() throws {
        let fixture = try ReaderStoreTestFixture(autoRefreshOnExternalChange: false)
        defer { fixture.cleanup() }

        let error = NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES))

        #expect(fixture.store.securityScopeResolver.isPermissionDeniedWriteError(error) == true)
    }

    @Test @MainActor func isPermissionDeniedWriteErrorRejectsUnrelatedError() throws {
        let fixture = try ReaderStoreTestFixture(autoRefreshOnExternalChange: false)
        defer { fixture.cleanup() }

        let error = NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoSuchFileError)

        #expect(fixture.store.securityScopeResolver.isPermissionDeniedWriteError(error) == false)
    }
}
