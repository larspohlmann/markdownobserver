import Foundation

struct SecurityScopeContext {
    var fileToken: SecurityScopedAccessToken?
    var directoryToken: SecurityScopedAccessToken?
    var folderToken: SecurityScopedAccessToken?
    var accessibleFileURL: URL?
    var accessibleFileURLSource: AccessibleFileURLSource?

    init(
        fileToken: SecurityScopedAccessToken? = nil,
        directoryToken: SecurityScopedAccessToken? = nil,
        folderToken: SecurityScopedAccessToken? = nil,
        accessibleFileURL: URL? = nil,
        accessibleFileURLSource: AccessibleFileURLSource? = nil
    ) {
        self.fileToken = fileToken
        self.directoryToken = directoryToken
        self.folderToken = folderToken
        self.accessibleFileURL = accessibleFileURL
        self.accessibleFileURLSource = accessibleFileURLSource
    }

    mutating func endAllAccess() {
        fileToken?.endAccess()
        directoryToken?.endAccess()
        folderToken?.endAccess()
        fileToken = nil
        directoryToken = nil
        folderToken = nil
        accessibleFileURL = nil
        accessibleFileURLSource = nil
    }

    mutating func endFileAndDirectoryAccess() {
        fileToken?.endAccess()
        fileToken = nil
        directoryToken?.endAccess()
        directoryToken = nil
        accessibleFileURL = nil
        accessibleFileURLSource = nil
    }
}
