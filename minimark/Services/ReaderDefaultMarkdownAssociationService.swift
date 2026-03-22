import Foundation
import CoreServices
import UniformTypeIdentifiers

protocol ReaderDefaultMarkdownAssociationHandling {
    func setCurrentAppAsDefaultForMarkdown() throws -> MarkdownAssociationUpdateResult
}

struct MarkdownAssociationUpdateResult: Equatable, Sendable {
    let bundleIdentifier: String
    let updatedContentTypes: [String]
}

enum MarkdownAssociationRole: String, Equatable, Sendable {
    case all
    case viewer

    var lsRoleMask: LSRolesMask {
        switch self {
        case .all:
            return .all
        case .viewer:
            return .viewer
        }
    }
}

enum MarkdownAssociationError: LocalizedError, Equatable {
    struct Failure: Equatable {
        let contentType: String
        let role: MarkdownAssociationRole
        let status: OSStatus
    }

    case missingBundleIdentifier
    case bundleRegistrationFailed(status: OSStatus)
    case noMarkdownContentTypesResolved
    case launchServicesFailed([Failure])
    case verificationFailed(
        contentType: String,
        role: MarkdownAssociationRole,
        expectedBundleIdentifier: String,
        actualBundleIdentifier: String?
    )

    var errorDescription: String? {
        switch self {
        case .missingBundleIdentifier:
            return "Could not determine the app bundle identifier."
        case let .bundleRegistrationFailed(status):
            let description = NSError(
                domain: NSOSStatusErrorDomain,
                code: Int(status),
                userInfo: nil
            ).localizedDescription
            return "macOS could not register MarkdownObserver as a document handler. \(description) (OSStatus \(status))"
        case .noMarkdownContentTypesResolved:
            return "Could not resolve a content type for .md files."
        case let .launchServicesFailed(failures):
            let details = failures
                .map { failure in
                    let description = NSError(
                        domain: NSOSStatusErrorDomain,
                        code: Int(failure.status),
                        userInfo: nil
                    ).localizedDescription
                    return "\(failure.contentType) [\(failure.role.rawValue)]: \(description) (OSStatus \(failure.status))"
                }
                .joined(separator: "; ")
            return "macOS rejected the default app update. \(details)"
        case let .verificationFailed(contentType, role, expectedBundleIdentifier, actualBundleIdentifier):
            return "macOS reported \(actualBundleIdentifier ?? "no handler") for \(contentType) [\(role.rawValue)] instead of \(expectedBundleIdentifier)."
        }
    }
}

final class ReaderDefaultMarkdownAssociationService: ReaderDefaultMarkdownAssociationHandling {
    private let launchServices: LaunchServicesControlling
    private let typeResolver: MarkdownContentTypeResolving
    private let appBundle: Bundle

    init(
        launchServices: LaunchServicesControlling = SystemLaunchServices(),
        typeResolver: MarkdownContentTypeResolving = MarkdownContentTypeResolver(),
        appBundle: Bundle = .main
    ) {
        self.launchServices = launchServices
        self.typeResolver = typeResolver
        self.appBundle = appBundle
    }

    func setCurrentAppAsDefaultForMarkdown() throws -> MarkdownAssociationUpdateResult {
        guard let bundleIdentifier = appBundle.bundleIdentifier else {
            throw MarkdownAssociationError.missingBundleIdentifier
        }

        let registrationStatus = launchServices.registerApplication(at: appBundle.bundleURL)
        guard registrationStatus == noErr else {
            throw MarkdownAssociationError.bundleRegistrationFailed(status: registrationStatus)
        }

        let contentTypes = typeResolver.markdownContentTypeIdentifiers()
        guard !contentTypes.isEmpty else {
            throw MarkdownAssociationError.noMarkdownContentTypesResolved
        }

        var succeededTypeRoles: [(contentType: String, role: MarkdownAssociationRole)] = []
        var failures: [MarkdownAssociationError.Failure] = []
        let rolesToTry: [MarkdownAssociationRole] = [.all, .viewer]

        for contentType in contentTypes {
            var successfulRole: MarkdownAssociationRole?

            for role in rolesToTry {
                let status = launchServices.setDefaultRoleHandler(
                    contentType: contentType,
                    role: role.lsRoleMask,
                    handlerBundleID: bundleIdentifier
                )

                if status == noErr {
                    successfulRole = role
                    break
                }

                failures.append(
                    .init(contentType: contentType, role: role, status: status)
                )
            }

            if let successfulRole {
                succeededTypeRoles.append((contentType: contentType, role: successfulRole))
            }
        }

        guard !succeededTypeRoles.isEmpty else {
            throw MarkdownAssociationError.launchServicesFailed(failures)
        }

        for succeededTypeRole in succeededTypeRoles {
            let currentHandler = launchServices.copyDefaultRoleHandler(
                contentType: succeededTypeRole.contentType,
                role: succeededTypeRole.role.lsRoleMask
            )
            if currentHandler != bundleIdentifier {
                throw MarkdownAssociationError.verificationFailed(
                    contentType: succeededTypeRole.contentType,
                    role: succeededTypeRole.role,
                    expectedBundleIdentifier: bundleIdentifier,
                    actualBundleIdentifier: currentHandler
                )
            }
        }

        return MarkdownAssociationUpdateResult(
            bundleIdentifier: bundleIdentifier,
            updatedContentTypes: succeededTypeRoles.map(\.contentType)
        )
    }
}

protocol LaunchServicesControlling {
    func registerApplication(at url: URL) -> OSStatus
    func setDefaultRoleHandler(contentType: String, role: LSRolesMask, handlerBundleID: String) -> OSStatus
    func copyDefaultRoleHandler(contentType: String, role: LSRolesMask) -> String?
}

struct SystemLaunchServices: LaunchServicesControlling {
    func registerApplication(at url: URL) -> OSStatus {
        LSRegisterURL(url as CFURL, true)
    }

    func setDefaultRoleHandler(contentType: String, role: LSRolesMask, handlerBundleID: String) -> OSStatus {
        LSSetDefaultRoleHandlerForContentType(
            contentType as CFString,
            role,
            handlerBundleID as CFString
        )
    }

    func copyDefaultRoleHandler(contentType: String, role: LSRolesMask) -> String? {
        guard let unmanaged = LSCopyDefaultRoleHandlerForContentType(contentType as CFString, role) else {
            return nil
        }
        return unmanaged.takeRetainedValue() as String
    }
}

protocol MarkdownContentTypeResolving {
    func markdownContentTypeIdentifiers() -> [String]
}

struct MarkdownContentTypeResolver: MarkdownContentTypeResolving {
    func markdownContentTypeIdentifiers() -> [String] {
        var identifiers: [String] = []

        if let markdownType = UTType(filenameExtension: "md") {
            identifiers.append(markdownType.identifier)
        }

        // Fallback for systems that do not resolve .md through UTType lookups.
        identifiers.append("net.daringfireball.markdown")

        return identifiers.uniqued()
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { element in
            seen.insert(element).inserted
        }
    }
}
