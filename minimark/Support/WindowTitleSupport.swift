import AppKit
import SwiftUI

enum DocumentIndicatorState: Equatable, Sendable {
    case none
    case addedExternalChange
    case externalChange
    case deletedExternalChange

    init(
        hasUnacknowledgedExternalChange: Bool,
        isCurrentFileMissing: Bool,
        unacknowledgedExternalChangeKind: ReaderExternalChangeKind = .modified
    ) {
        guard hasUnacknowledgedExternalChange else {
            self = .none
            return
        }

        if isCurrentFileMissing {
            self = .deletedExternalChange
            return
        }

        switch unacknowledgedExternalChangeKind {
        case .added:
            self = .addedExternalChange
        case .modified:
            self = .externalChange
        }
    }

    var showsIndicator: Bool {
        self != .none
    }

    func color(for settings: ReaderSettings, colorScheme: ColorScheme) -> Color {
        switch self {
        case .deletedExternalChange:
            return Color(nsColor: .systemRed)
        case .addedExternalChange:
            return Color(nsColor: .systemGreen)
        case .externalChange:
            return Color(nsColor: .systemYellow)
        case .none:
            return .clear
        }
    }
}

struct WindowTitleFormatter {
    struct Mutation: Equatable {
        let effectiveTitle: String
        let shouldUpdateEffectiveTitle: Bool
        let shouldWriteHostWindowTitle: Bool
    }

    static let appName = "MarkdownObserver"

    static func resolveWindowTitle(
        documentTitle: String,
        activeFolderWatch: FolderWatchSession?,
        hasUnacknowledgedExternalChange: Bool
    ) -> String {
        let documentTitleWithPendingState = hasUnacknowledgedExternalChange
            ? "* \(documentTitle)"
            : documentTitle

        return documentTitleWithPendingState
    }

    static func mutation(
        resolvedTitle: String,
        currentEffectiveTitle: String,
        currentHostWindowTitle: String?
    ) -> Mutation {
        Mutation(
            effectiveTitle: resolvedTitle,
            shouldUpdateEffectiveTitle: currentEffectiveTitle != resolvedTitle,
            shouldWriteHostWindowTitle: currentHostWindowTitle != resolvedTitle
        )
    }
}

struct WindowAccessor: NSViewRepresentable {
    var onWindowChange: (NSWindow?) -> Void

    func makeNSView(context: Context) -> WindowObserverView {
        let view = WindowObserverView()
        view.onWindowChange = onWindowChange
        return view
    }

    func updateNSView(_ nsView: WindowObserverView, context: Context) {
        nsView.onWindowChange = onWindowChange
        DispatchQueue.main.async {
            nsView.onWindowChange(nsView.window)
        }
    }
}

final class WindowObserverView: NSView {
    var onWindowChange: (NSWindow?) -> Void = { _ in }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.onWindowChange(self.window)
        }
    }
}
