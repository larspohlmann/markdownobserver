import Foundation

@MainActor protocol ReaderAutoOpenSettling: AnyObject {
    var pendingContext: PendingAutoOpenSettlingContext? { get }
    func makePendingContext(
        origin: ReaderOpenOrigin,
        initialDiffBaselineMarkdown: String?,
        loadedMarkdown: String,
        now: Date
    ) -> PendingAutoOpenSettlingContext?
    func beginSettling(_ context: PendingAutoOpenSettlingContext?)
    func clearSettling()
    func handleChangeIfNeeded(
        fileURL: URL,
        loader: (URL) throws -> (markdown: String, modificationDate: Date)
    ) -> Bool
}

@MainActor
final class ReaderAutoOpenSettler: ReaderAutoOpenSettling {
    private let settlingInterval: TimeInterval
    private var currentFileURL: (() -> URL?)?
    private var loadFile: ((URL) throws -> (markdown: String, modificationDate: Date))?
    private var onDocumentSettled: ((_ loaded: (markdown: String, modificationDate: Date), _ fileURL: URL, _ diffBaselineMarkdown: String?) -> Void)?
    private var onLoadStateChanged: ((ReaderDocumentLoadState) -> Void)?

    private var settlingContext: PendingAutoOpenSettlingContext?
    private var settlingTask: Task<Void, Never>?

    var pendingContext: PendingAutoOpenSettlingContext? { settlingContext }

    nonisolated deinit {}

    init(settlingInterval: TimeInterval) {
        self.settlingInterval = settlingInterval
    }

    func configure(
        currentFileURL: @escaping () -> URL?,
        loadFile: @escaping (URL) throws -> (markdown: String, modificationDate: Date),
        onDocumentSettled: @escaping (_ loaded: (markdown: String, modificationDate: Date), _ fileURL: URL, _ diffBaselineMarkdown: String?) -> Void,
        onLoadStateChanged: @escaping (ReaderDocumentLoadState) -> Void
    ) {
        self.currentFileURL = currentFileURL
        self.loadFile = loadFile
        self.onDocumentSettled = onDocumentSettled
        self.onLoadStateChanged = onLoadStateChanged
    }

    func makePendingContext(
        origin: ReaderOpenOrigin,
        initialDiffBaselineMarkdown: String?,
        loadedMarkdown: String,
        now: Date
    ) -> PendingAutoOpenSettlingContext? {
        guard origin.isFolderWatchAutoOpen else {
            return nil
        }

        let showsLoadingOverlay = origin == .folderWatchAutoOpen
            && initialDiffBaselineMarkdown == nil
            && loadedMarkdown.isEmpty

        return PendingAutoOpenSettlingContext(
            loadedMarkdown: loadedMarkdown,
            diffBaselineMarkdown: initialDiffBaselineMarkdown,
            expiresAt: showsLoadingOverlay ? nil : now.addingTimeInterval(settlingInterval),
            showsLoadingOverlay: showsLoadingOverlay
        )
    }

    func beginSettling(_ context: PendingAutoOpenSettlingContext?) {
        settlingTask?.cancel()
        settlingTask = nil
        settlingContext = context
        onLoadStateChanged?(context?.showsLoadingOverlay == true ? .settlingAutoOpen : .ready)

        guard context != nil else {
            return
        }

        schedulePollLoop()
    }

    func clearSettling() {
        let wasActive = settlingContext != nil || settlingTask != nil
        settlingTask?.cancel()
        settlingTask = nil
        settlingContext = nil
        if wasActive {
            onLoadStateChanged?(.ready)
        }
    }

    func handleChangeIfNeeded(
        fileURL: URL,
        loader: (URL) throws -> (markdown: String, modificationDate: Date)
    ) -> Bool {
        guard let context = settlingContext else {
            return false
        }

        guard let loaded = try? loader(fileURL) else {
            return false
        }

        switch evaluate(context: context, loaded: loaded, presentedAs: fileURL, now: Date()) {
        case .unhandled:
            return false
        case .handled:
            return true
        }
    }

    // MARK: - Private

    private func evaluate(
        context: PendingAutoOpenSettlingContext,
        loaded: (markdown: String, modificationDate: Date),
        presentedAs fileURL: URL,
        now: Date
    ) -> PendingAutoOpenSettlingEvaluation {
        if let expiresAt = context.expiresAt,
           now > expiresAt {
            clearSettling()
            return .unhandled
        }

        guard loaded.markdown != context.loadedMarkdown else {
            if !context.showsLoadingOverlay {
                clearSettling()
            }
            return .handled
        }

        clearSettling()
        onDocumentSettled?(loaded, fileURL, context.diffBaselineMarkdown)
        return .handled
    }

    private func schedulePollLoop() {
        settlingTask?.cancel()
        settlingTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            while !Task.isCancelled {
                guard let context = self.settlingContext else {
                    return
                }

                let now = Date()
                if let expiresAt = context.expiresAt,
                   now >= expiresAt {
                    self.clearSettling()
                    return
                }

                try? await Task.sleep(for: .milliseconds(100))

                guard !Task.isCancelled else {
                    return
                }

                guard let fileURL = self.currentFileURL?() else {
                    self.clearSettling()
                    return
                }

                guard let loaded = try? self.loadFile?(fileURL) else {
                    continue
                }

                switch self.evaluate(
                    context: context,
                    loaded: loaded,
                    presentedAs: fileURL,
                    now: now
                ) {
                case .unhandled:
                    continue
                case .handled:
                    return
                }
            }
        }
    }
}
