//
//  ReaderStoreSecurityScopeFlowTests.swift
//  minimarkTests
//

import Foundation
import Testing
@testable import minimark

@Suite(.serialized)
struct ReaderStoreSecurityScopeFlowTests {

    // MARK: - effectiveAccessibleFileURL branches

    @Test @MainActor func branch1_fileScopeTokenUsedDirectly() throws {
        let fixture = try ReaderStoreTestFixture(autoRefreshOnExternalChange: false)
        defer { fixture.cleanup() }

        fixture.store.activateFileSecurityScope(for: fixture.primaryFileURL, reason: "test")
        let result = fixture.store.effectiveAccessibleFileURL(for: fixture.primaryFileURL, reason: "test")

        #expect(result == fixture.primaryFileURL)
        #expect(fixture.store.scopeContext.accessibleFileURLSource == .fileScope)
    }

    @Test @MainActor func branch2_cachedAccessibleURLMatchReturned() throws {
        let fixture = try ReaderStoreTestFixture(autoRefreshOnExternalChange: false)
        defer { fixture.cleanup() }

        // No active token — set cached URL directly
        fixture.store.scopeContext.accessibleFileURL = fixture.primaryFileURL
        fixture.store.scopeContext.accessibleFileURLSource = .fileScope

        let result = fixture.store.effectiveAccessibleFileURL(for: fixture.primaryFileURL, reason: "test")

        #expect(result == fixture.primaryFileURL)
        #expect(fixture.store.scopeContext.accessibleFileURLSource == .fileScope)
    }

    @Test @MainActor func branch3_folderScopeChildURLConstructed() throws {
        let fixture = try ReaderStoreTestFixture(autoRefreshOnExternalChange: false)
        defer { fixture.cleanup() }

        let folderURL = fixture.temporaryDirectoryURL
        let options = ReaderFolderWatchOptions(openMode: .watchChangesOnly, scope: .includeSubfolders)
        let session = ReaderFolderWatchSession(folderURL: folderURL, options: options, startedAt: Date())

        // Register folder so resolvedWatchedFolderAccessURL can resolve the URL
        fixture.settings.addRecentWatchedFolder(folderURL, options: options)

        // Activate folder watch session
        fixture.store.setActiveFolderWatchSession(session)

        // Begin folder-scoped access manually so the token is active
        fixture.store.scopeContext.folderToken = fixture.securityScope.beginAccess(to: folderURL)

        // Clear any file-level scope
        fixture.store.scopeContext.fileToken = nil
        fixture.store.scopeContext.accessibleFileURL = nil
        fixture.store.scopeContext.accessibleFileURLSource = nil

        let result = fixture.store.effectiveAccessibleFileURL(for: fixture.primaryFileURL, reason: "test")

        #expect(result.lastPathComponent == "first.md")
        #expect(fixture.store.scopeContext.accessibleFileURLSource == .folderScopeChildURL)
    }

    @Test @MainActor func branch4_fallbackReturnsNormalizedURL() throws {
        let fixture = try ReaderStoreTestFixture(autoRefreshOnExternalChange: false)
        defer { fixture.cleanup() }

        // Reset scope context to completely empty state
        fixture.store.scopeContext = SecurityScopeContext()

        let result = fixture.store.effectiveAccessibleFileURL(for: fixture.primaryFileURL, reason: "test")

        #expect(result.lastPathComponent == "first.md")
    }

    // MARK: - folderScopedAccessibleFileURL

    @Test @MainActor func folderScopedAccessibleFileURLReturnsNilWithoutSession() throws {
        let fixture = try ReaderStoreTestFixture(autoRefreshOnExternalChange: false)
        defer { fixture.cleanup() }

        // No active folder watch session
        let result = fixture.store.folderScopedAccessibleFileURL(for: fixture.primaryFileURL)

        #expect(result == nil)
    }

    @Test @MainActor func folderScopedAccessibleFileURLReturnsNilWhenFileOutsideFolder() throws {
        let fixture = try ReaderStoreTestFixture(autoRefreshOnExternalChange: false)
        defer { fixture.cleanup() }

        let folderURL = fixture.temporaryDirectoryURL
        let options = ReaderFolderWatchOptions(openMode: .watchChangesOnly, scope: .selectedFolderOnly)
        let session = ReaderFolderWatchSession(folderURL: folderURL, options: options, startedAt: Date())

        fixture.store.setActiveFolderWatchSession(session)
        fixture.store.scopeContext.folderToken = fixture.securityScope.beginAccess(to: folderURL)

        let outsideURL = URL(fileURLWithPath: "/completely/different/path.md")
        let result = fixture.store.folderScopedAccessibleFileURL(for: outsideURL)

        #expect(result == nil)
    }

    // MARK: - watchedFolderSession

    @Test @MainActor func watchedFolderSessionAppliesToDirectChildInSelectedFolderOnlyMode() throws {
        let fixture = try ReaderStoreTestFixture(autoRefreshOnExternalChange: false)
        defer { fixture.cleanup() }

        let folderURL = fixture.temporaryDirectoryURL
        let options = ReaderFolderWatchOptions(openMode: .watchChangesOnly, scope: .selectedFolderOnly)
        let session = ReaderFolderWatchSession(folderURL: folderURL, options: options, startedAt: Date())

        let directChild = folderURL.appendingPathComponent("file.md")
        let subfolderChild = folderURL.appendingPathComponent("sub/file.md")

        #expect(fixture.store.watchedFolderSession(session, appliesTo: directChild) == true)
        #expect(fixture.store.watchedFolderSession(session, appliesTo: subfolderChild) == false)
    }

    @Test @MainActor func watchedFolderSessionAppliesToSubfolderChildInIncludeSubfoldersMode() throws {
        let fixture = try ReaderStoreTestFixture(autoRefreshOnExternalChange: false)
        defer { fixture.cleanup() }

        let folderURL = fixture.temporaryDirectoryURL
        let options = ReaderFolderWatchOptions(openMode: .watchChangesOnly, scope: .includeSubfolders)
        let session = ReaderFolderWatchSession(folderURL: folderURL, options: options, startedAt: Date())

        let subfolderChild = folderURL.appendingPathComponent("sub/nested/file.md")

        #expect(fixture.store.watchedFolderSession(session, appliesTo: subfolderChild) == true)
    }

    // MARK: - isPermissionDeniedWriteError

    @Test @MainActor func isPermissionDeniedWriteErrorRecognizesCocoaError() throws {
        let fixture = try ReaderStoreTestFixture(autoRefreshOnExternalChange: false)
        defer { fixture.cleanup() }

        let error = NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError)

        #expect(fixture.store.isPermissionDeniedWriteError(error) == true)
    }

    @Test @MainActor func isPermissionDeniedWriteErrorRecognizesPOSIXEACCES() throws {
        let fixture = try ReaderStoreTestFixture(autoRefreshOnExternalChange: false)
        defer { fixture.cleanup() }

        let error = NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES))

        #expect(fixture.store.isPermissionDeniedWriteError(error) == true)
    }

    @Test @MainActor func isPermissionDeniedWriteErrorRejectsUnrelatedError() throws {
        let fixture = try ReaderStoreTestFixture(autoRefreshOnExternalChange: false)
        defer { fixture.cleanup() }

        let error = NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoSuchFileError)

        #expect(fixture.store.isPermissionDeniedWriteError(error) == false)
    }
}
