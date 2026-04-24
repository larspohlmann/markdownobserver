import AppKit
import SwiftUI

struct AboutWindowView: View {
    private let appName: String
    private let appVersionText: String
    private let authorName = "Lars Pohlmann"
    private let authorURL = URL(string: "https://lars-pohlmann.de")!
    private let repositoryURL = URL(string: "https://github.com/larspohlmann/markdownobserver")!

    private var appIcon: NSImage? {
        NSApp.applicationIconImage
    }

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
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .center, spacing: 14) {
                        if let appIcon {
                            Image(nsImage: appIcon)
                                .resizable()
                                .interpolation(.high)
                                .frame(width: 76, height: 76)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .strokeBorder(.quaternary, lineWidth: 1)
                                )
                                .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
                                .accessibilityHidden(true)
                        }

                        VStack(alignment: .leading, spacing: 5) {
                            Text(appName)
                                .font(.system(size: 28, weight: .semibold, design: .rounded))
                            Text(appVersionText)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text("A focused macOS markdown reader")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 0)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 10) {
                        AboutDetailLinkItem(label: "Author", title: authorName, destination: authorURL)

                        Link(destination: repositoryURL) {
                            HStack(spacing: 7) {
                                Image(systemName: "link")
                                Text(repositoryURL.absoluteString)
                                    .font(.callout.monospaced())
                                    .underline()
                                    .textSelection(.enabled)
                                Image(systemName: "arrow.up.right")
                                    .font(.caption.weight(.semibold))
                            }
                        }
                        .buttonStyle(.link)
                        .accessibilityLabel("MarkdownObserver project repository: \(repositoryURL.absoluteString)")
                    }
                }
                .padding(18)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.regularMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(.separator.opacity(0.35), lineWidth: 1)
                )
                .accessibilityElement(children: .contain)
                .accessibilityLabel("\(appName), \(appVersionText)")

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    Text("Third-Party Licenses")
                        .font(.headline)

                    Text("MarkdownObserver bundles the open-source components listed below. Review each project and license before distribution.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(spacing: 0) {
                        HStack(spacing: 12) {
                            Text("Component")
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text("License")
                                .frame(width: 110, alignment: .leading)
                            Text("Link")
                                .frame(width: 86, alignment: .trailing)
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)

                        Divider()

                        ForEach(Array(ThirdPartyLicenseNote.allCases.enumerated()), id: \.element.id) { index, note in
                            ThirdPartyLicenseRow(note: note, index: index)

                            if index < ThirdPartyLicenseNote.allCases.count - 1 {
                                Divider()
                            }
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(.regularMaterial)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(.separator.opacity(0.35), lineWidth: 1)
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .frame(minWidth: 620, minHeight: 500)
    }
}

private struct AboutDetailLinkItem: View {
    let label: String
    let title: String
    let destination: URL

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)

            Link(title, destination: destination)
                .font(.subheadline.weight(.semibold))
                .underline()
                .buttonStyle(.link)
                .overlay(alignment: .trailing) {
                    Image(systemName: "arrow.up.right")
                        .font(.caption.weight(.semibold))
                        .padding(.leading, 4)
                        .offset(x: 14)
                }
        }
    }
}

private struct AboutDetailItem: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

private struct ThirdPartyLicenseRow: View {
    let note: ThirdPartyLicenseNote
    let index: Int

    private var hostText: String {
        note.projectURL.host?.replacingOccurrences(of: "www.", with: "") ?? ""
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(note.displayName)
                    .font(.body.weight(.medium))
                Text(hostText)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(note.licenseName)
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .leading)

            Link("Website", destination: note.projectURL)
                .font(.callout.weight(.semibold))
                .frame(width: 86, alignment: .trailing)
                .accessibilityLabel("\(note.displayName) project website")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(index.isMultiple(of: 2) ? Color.primary.opacity(0.025) : .clear)
    }
}

private enum ThirdPartyLicenseNote: String, CaseIterable, Identifiable {
    case codeMirror
    case markdownIt
    case markdownItAttrs
    case markdownItDeflist
    case markdownItFootnote
    case markdownItTaskLists
    case markdownItKatex
    case differ
    case highlightJS
    case katex
    case mermaidJS

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
        case .markdownItKatex:
            return "markdown-it-katex"
        case .differ:
            return "Differ (Swift package)"
        case .highlightJS:
            return "highlight.js"
        case .katex:
            return "KaTeX"
        case .mermaidJS:
            return "Mermaid"
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
        case .markdownItKatex:
            return "MIT"
        case .differ:
            return "MIT"
        case .highlightJS:
            return "BSD 3-Clause"
        case .katex:
            return "MIT"
        case .mermaidJS:
            return "MIT"
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
        case .markdownItKatex:
            return URL(string: "https://github.com/waylonflinn/markdown-it-katex")!
        case .differ:
            return URL(string: "https://github.com/tonyarnold/Differ")!
        case .highlightJS:
            return URL(string: "https://github.com/highlightjs/highlight.js")!
        case .katex:
            return URL(string: "https://github.com/KaTeX/KaTeX")!
        case .mermaidJS:
            return URL(string: "https://github.com/mermaid-js/mermaid")!
        }
    }
}
