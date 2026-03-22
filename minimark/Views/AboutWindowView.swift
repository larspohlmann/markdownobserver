import SwiftUI

struct AboutWindowView: View {
    private let appName: String
    private let appVersionText: String

    init(
        appName: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "MarkdownObserver",
        appVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-",
        appBuild: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "-"
    ) {
        self.appName = appName
        self.appVersionText = "Version \(appVersion) (\(appBuild))"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(appName)
                        .font(.title2.weight(.semibold))
                    Text(appVersionText)
                        .foregroundStyle(.secondary)

                    Text("Open-source project")
                        .foregroundStyle(.secondary)

                    Link("Project repository", destination: URL(string: "https://github.com/REPLACE_WITH_OWNER/REPLACE_WITH_REPO")!)
                        .accessibilityLabel("MarkdownObserver project repository")
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(appName), \(appVersionText)")

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    Text("Third-Party Licenses")
                        .font(.headline)

                    Text("MarkdownObserver bundles the open-source components listed below. Review each project and license before distribution.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    ForEach(ThirdPartyLicenseNote.allCases) { note in
                        ThirdPartyLicenseRow(note: note)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .frame(minWidth: 560, minHeight: 460)
    }
}

private struct ThirdPartyLicenseRow: View {
    let note: ThirdPartyLicenseNote

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(note.displayName)
                .font(.body.weight(.medium))

            Text(note.licenseName)
                .foregroundStyle(.secondary)

            Link("Project website", destination: note.projectURL)
                .accessibilityLabel("\(note.displayName) project website")
        }
        .padding(.vertical, 6)
    }
}

private enum ThirdPartyLicenseNote: String, CaseIterable, Identifiable {
    case codeMirror
    case markdownIt
    case markdownItAttrs
    case markdownItDeflist
    case markdownItFootnote
    case markdownItTaskLists
    case differ
    case highlightJS

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .codeMirror:
            return "CodeMirror 6"
        case .markdownIt:
            return "markdown-it"
        case .markdownItAttrs:
            return "markdown-it-attrs"
        case .markdownItDeflist:
            return "markdown-it-deflist"
        case .markdownItFootnote:
            return "markdown-it-footnote"
        case .markdownItTaskLists:
            return "markdown-it-task-lists"
        case .differ:
            return "Differ (Swift package)"
        case .highlightJS:
            return "highlight.js"
        }
    }

    var licenseName: String {
        switch self {
        case .codeMirror:
            return "MIT"
        case .markdownIt:
            return "MIT"
        case .markdownItAttrs:
            return "MIT"
        case .markdownItDeflist:
            return "MIT"
        case .markdownItFootnote:
            return "MIT"
        case .markdownItTaskLists:
            return "ISC"
        case .differ:
            return "MIT"
        case .highlightJS:
            return "BSD 3-Clause"
        }
    }

    var projectURL: URL {
        switch self {
        case .codeMirror:
            return URL(string: "https://github.com/codemirror/dev")!
        case .markdownIt:
            return URL(string: "https://github.com/markdown-it/markdown-it")!
        case .markdownItAttrs:
            return URL(string: "https://github.com/arve0/markdown-it-attrs")!
        case .markdownItDeflist:
            return URL(string: "https://github.com/markdown-it/markdown-it-deflist")!
        case .markdownItFootnote:
            return URL(string: "https://github.com/markdown-it/markdown-it-footnote")!
        case .markdownItTaskLists:
            return URL(string: "https://github.com/revin/markdown-it-task-lists")!
        case .differ:
            return URL(string: "https://github.com/tonyarnold/Differ")!
        case .highlightJS:
            return URL(string: "https://github.com/highlightjs/highlight.js")!
        }
    }
}
