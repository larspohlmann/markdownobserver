import AppKit
import SwiftUI

enum ReaderDocumentIndicatorState: Equatable, Sendable {
    case none
    case externalChange
    case deletedExternalChange

    init(hasUnacknowledgedExternalChange: Bool, isCurrentFileMissing: Bool) {
        guard hasUnacknowledgedExternalChange else {
            self = .none
            return
        }

        self = isCurrentFileMissing ? .deletedExternalChange : .externalChange
    }

    var showsIndicator: Bool {
        self != .none
    }
}

struct ReaderWindowTitleFormatter {
    static let appName = "MarkdownObserver"

    static func resolveWindowTitle(
        documentTitle: String,
        activeFolderWatch: ReaderFolderWatchSession?,
        hasUnacknowledgedExternalChange: Bool
    ) -> String {
        let documentTitleWithPendingState = hasUnacknowledgedExternalChange
            ? "* \(documentTitle)"
            : documentTitle

        if let activeFolderWatch {
            return "\(documentTitleWithPendingState) | \(activeFolderWatch.titleLabel)"
        }

        return documentTitleWithPendingState
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
