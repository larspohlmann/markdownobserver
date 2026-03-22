import Foundation

protocol SecurityScopedResourceAccessing {
    func beginAccess(to url: URL) -> SecurityScopedAccessToken
}

protocol SecurityScopedAccessToken: AnyObject {
    var url: URL { get }
    var didStartAccess: Bool { get }
    func endAccess()
}

final class SecurityScopedResourceAccess: SecurityScopedResourceAccessing {
    func beginAccess(to url: URL) -> SecurityScopedAccessToken {
        let didStart = url.startAccessingSecurityScopedResource()
        return Token(url: url, didStart: didStart)
    }
}

private final class Token: SecurityScopedAccessToken {
    let url: URL
    let didStartAccess: Bool
    private var ended = false

    init(url: URL, didStart: Bool) {
        self.url = url
        self.didStartAccess = didStart
    }

    func endAccess() {
        guard didStartAccess, !ended else {
            return
        }
        ended = true
        url.stopAccessingSecurityScopedResource()
    }

    deinit {
        endAccess()
    }
}
