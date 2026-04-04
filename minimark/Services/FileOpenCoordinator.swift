import Foundation

struct FileOpenRequest {
    let fileURLs: [URL]
    let origin: ReaderOpenOrigin
    let folderWatchSession: ReaderFolderWatchSession?
    let initialDiffBaselineMarkdownByURL: [URL: String]
    let slotStrategy: SlotStrategy
    let materializationStrategy: MaterializationStrategy

    init(
        fileURLs: [URL],
        origin: ReaderOpenOrigin,
        folderWatchSession: ReaderFolderWatchSession? = nil,
        initialDiffBaselineMarkdownByURL: [URL: String] = [:],
        slotStrategy: SlotStrategy = .reuseEmptySlotForFirst,
        materializationStrategy: MaterializationStrategy = .loadAll
    ) {
        self.fileURLs = fileURLs
        self.origin = origin
        self.folderWatchSession = folderWatchSession
        self.initialDiffBaselineMarkdownByURL = initialDiffBaselineMarkdownByURL
        self.slotStrategy = slotStrategy
        self.materializationStrategy = materializationStrategy
    }

    enum SlotStrategy {
        /// First file reuses the empty slot if one exists; rest append.
        case reuseEmptySlotForFirst
        /// All files always append new slots.
        case alwaysAppend
        /// Replace the content of the currently selected slot (single-file only).
        case replaceSelectedSlot
    }

    enum MaterializationStrategy: Equatable {
        /// Open all files fully (sync load).
        case loadAll
        /// Defer all files, then materialize the N newest.
        case deferThenMaterializeNewest(count: Int)
        /// Defer all files, then materialize whichever ends up selected.
        case deferThenMaterializeSelected
    }
}

struct FileOpenPlan {
    struct SlotAssignment: Equatable {
        let fileURL: URL
        let target: SlotTarget
        let loadMode: LoadMode
        let initialDiffBaselineMarkdown: String?
    }

    enum SlotTarget: Equatable {
        case reuseExisting(documentID: UUID)
        case createNew
    }

    enum LoadMode: Equatable {
        case loadFully
        case deferOnly
    }

    let assignments: [SlotAssignment]
    let origin: ReaderOpenOrigin
    let folderWatchSession: ReaderFolderWatchSession?
    let materializationStrategy: FileOpenRequest.MaterializationStrategy
}

@MainActor
final class FileOpenCoordinator {
    private let controller: ReaderSidebarDocumentController

    init(controller: ReaderSidebarDocumentController) {
        self.controller = controller
    }

    func open(_ request: FileOpenRequest) {
        let plan = buildPlan(for: request)
        guard !plan.assignments.isEmpty else { return }
        controller.executePlan(plan)
    }

    func buildPlan(for request: FileOpenRequest) -> FileOpenPlan {
        let normalizedURLs = deduplicateAndSort(request.fileURLs)
        guard !normalizedURLs.isEmpty else {
            return FileOpenPlan(
                assignments: [],
                origin: request.origin,
                folderWatchSession: request.folderWatchSession,
                materializationStrategy: request.materializationStrategy
            )
        }

        let assignments = planSlotAssignments(
            normalizedURLs: normalizedURLs,
            request: request
        )

        return FileOpenPlan(
            assignments: assignments,
            origin: request.origin,
            folderWatchSession: request.folderWatchSession,
            materializationStrategy: request.materializationStrategy
        )
    }

    // MARK: - Private

    private nonisolated func deduplicateAndSort(_ urls: [URL]) -> [URL] {
        Array(Set(urls.map(ReaderFileRouting.normalizedFileURL)))
            .sorted { $0.path < $1.path }
    }

    private func planSlotAssignments(
        normalizedURLs: [URL],
        request: FileOpenRequest
    ) -> [FileOpenPlan.SlotAssignment] {
        let loadMode = loadMode(for: request.materializationStrategy)
        var emptySlotConsumed = false
        var assignments: [FileOpenPlan.SlotAssignment] = []

        for (index, fileURL) in normalizedURLs.enumerated() {
            if controller.document(for: fileURL) != nil {
                continue
            }

            let target: FileOpenPlan.SlotTarget

            switch request.slotStrategy {
            case .replaceSelectedSlot:
                if let selectedDocument = controller.selectedDocument {
                    target = .reuseExisting(documentID: selectedDocument.id)
                } else {
                    target = .reuseExisting(documentID: controller.documents[0].id)
                }

            case .reuseEmptySlotForFirst:
                if !emptySlotConsumed && index == firstNewAssignmentIndex(in: normalizedURLs),
                   canReuseEmptySlot {
                    target = .reuseExisting(documentID: controller.selectedDocumentID)
                    emptySlotConsumed = true
                } else {
                    target = .createNew
                }

            case .alwaysAppend:
                target = .createNew
            }

            assignments.append(FileOpenPlan.SlotAssignment(
                fileURL: fileURL,
                target: target,
                loadMode: loadMode,
                initialDiffBaselineMarkdown: request.initialDiffBaselineMarkdownByURL[fileURL]
            ))
        }

        return assignments
    }

    private func firstNewAssignmentIndex(in normalizedURLs: [URL]) -> Int {
        for (index, fileURL) in normalizedURLs.enumerated() {
            if controller.document(for: fileURL) == nil {
                return index
            }
        }
        return 0
    }

    private var canReuseEmptySlot: Bool {
        guard let selectedDocument = controller.selectedDocument else { return false }
        return selectedDocument.readerStore.fileURL == nil && controller.documents.count == 1
    }

    private nonisolated func loadMode(
        for strategy: FileOpenRequest.MaterializationStrategy
    ) -> FileOpenPlan.LoadMode {
        switch strategy {
        case .loadAll:
            return .loadFully
        case .deferThenMaterializeNewest, .deferThenMaterializeSelected:
            return .deferOnly
        }
    }
}
