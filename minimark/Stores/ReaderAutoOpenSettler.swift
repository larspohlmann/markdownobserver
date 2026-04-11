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
    func configure(
        currentFileURL: @escaping () -> URL?,
        loadFile: @escaping (URL) throws -> (markdown: String, modificationDate: Date),
        onDocumentSettled: @escaping (_ loaded: (markdown: String, modificationDate: Date), _ fileURL: URL, _ diffBaselineMarkdown: String?) -> Void,
        onLoadStateChanged: @escaping (ReaderDocumentLoadState) -> Void
    )
}

extension ReaderAutoOpenSettling {
    func configure(
        currentFileURL: @escaping () -> URL?,
        loadFile: @escaping (URL) throws -> (markdown: String, modificationDate: Date),
        onDocumentSettled: @escaping (_ loaded: (markdown: String, modificationDate: Date), _ fileURL: URL, _ diffBaselineMarkdown: String?) -> Void,
        onLoadStateChanged: @escaping (ReaderDocumentLoadState) -> Void
    ) {}
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

    #if compiler(>=6.2)
    nonisolated deinit {
        settlingTask?.cancel()
    }
    #endif

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
            while !Task.isCancelled {
                guard let settler = self else { return }
                guard let context = settler.settlingContext else { return }

                let now = Date()
                if let expiresAt = context.expiresAt, now >= expiresAt {
                    settler.clearSettling()
                    return
                }

                // Release the strong reference before suspending to avoid
                // retaining the settler (and its owner) across the sleep.
                try? await Task.sleep(for: .milliseconds(100))

                guard !Task.isCancelled else { return }
                guard let settler = self else { return }

                guard let fileURL = settler.currentFileURL?() else {
                    settler.clearSettling()
                    return
                }

                guard let loaded = try? settler.loadFile?(fileURL) else {
                    continue
                }

                _ = settler.evaluate(
                    context: context,
                    loaded: loaded,
                    presentedAs: fileURL,
                    now: now
                )
            }
        }
    }
}
