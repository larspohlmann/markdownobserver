import SwiftUI

private enum ReaderSidebarWorkspaceMetrics {
    static let sidebarMinimumWidth: CGFloat = 220
    static let sidebarIdealWidth: CGFloat = 250
    static let detailMinimumWidth: CGFloat = 420
}

struct ReaderSidebarWorkspaceView<Detail: View>: View {
    @ObservedObject var controller: ReaderSidebarDocumentController
    @ObservedObject var settingsStore: ReaderSettingsStore
    let sidebarPlacement: ReaderMultiFileDisplayMode.SidebarPlacement
    let detail: (ReaderStore) -> Detail
    let onToggleSidebarPlacement: () -> Void
    let onOpenInDefaultApp: (Set<UUID>) -> Void
    let onOpenInApplication: (ReaderExternalApplication, Set<UUID>) -> Void
    let onRevealInFinder: (Set<UUID>) -> Void
    let onStopWatchingFolders: (Set<UUID>) -> Void
    let onCloseDocuments: (Set<UUID>) -> Void
    let onCloseOtherDocuments: (Set<UUID>) -> Void
    let onCloseAllDocuments: () -> Void
    @State private var selectedDocumentIDs: Set<UUID> = []

    var body: some View {
        Group {
            if controller.documents.count > 1 {
                HSplitView {
                    if sidebarPlacement == .left {
                        sidebarColumn
                        detailColumn
                    } else {
                        detailColumn
                        sidebarColumn
                    }
                }
            } else {
                detail(controller.selectedReaderStore)
            }
        }
        .onAppear {
            selectedDocumentIDs = [controller.selectedDocumentID]
        }
        .onChange(of: controller.selectedDocumentID) { _, selectedDocumentID in
            if !selectedDocumentIDs.contains(selectedDocumentID) || selectedDocumentIDs.isEmpty {
                selectedDocumentIDs = [selectedDocumentID]
            }
        }
        .onChange(of: controller.documents.map(\.id)) { _, documentIDs in
            let validIDs = Set(documentIDs)
            let filteredSelection = selectedDocumentIDs.intersection(validIDs)
            if filteredSelection.isEmpty, let firstDocumentID = displayedDocuments.first?.id {
                selectedDocumentIDs = [firstDocumentID]
                scheduleControllerSelection(firstDocumentID)
            } else if filteredSelection != selectedDocumentIDs {
                selectedDocumentIDs = filteredSelection
            }
        }
    }

    private func updateSelection(_ selection: Set<UUID>) {
        guard !selection.isEmpty else {
            selectedDocumentIDs = [controller.selectedDocumentID]
            return
        }

        selectedDocumentIDs = selection
        if selection.contains(controller.selectedDocumentID) {
            return
        }

        if let nextSelectedDocumentID = displayedDocuments.first(where: { selection.contains($0.id) })?.id {
            scheduleControllerSelection(nextSelectedDocumentID)
        }
    }

    private func scheduleControllerSelection(_ documentID: UUID) {
        Task { @MainActor in
            controller.selectDocument(documentID)
        }
    }

    private var currentSidebarSortMode: ReaderSidebarSortMode {
        settingsStore.currentSettings.sidebarSortMode
    }

    private var displayedDocuments: [ReaderSidebarDocumentController.Document] {
        currentSidebarSortMode.sorted(controller.documents) { document in
            ReaderSidebarSortDescriptor(
                displayName: document.readerStore.fileDisplayName,
                lastChangedAt: document.readerStore.fileLastModifiedAt ?? document.readerStore.lastExternalChangeAt ?? document.readerStore.lastRefreshAt
            )
        }
    }

    private var watchedDocumentIDs: Set<UUID> {
        controller.watchedDocumentIDs()
    }

    private var sidebarColumn: some View {
        VStack(spacing: 0) {
            List(
                displayedDocuments,
                selection: Binding(
                    get: { selectedDocumentIDs },
                    set: { updateSelection($0) }
                )
            ) { document in
                ReaderSidebarDocumentRow(
                    documentID: document.id,
                    documents: displayedDocuments,
                    readerStore: document.readerStore,
                    watchedDocumentIDs: watchedDocumentIDs,
                    selectedDocumentIDs: selectedDocumentIDs,
                    canClose: true,
                    onOpenInDefaultApp: {
                        onOpenInDefaultApp($0)
                    },
                    onOpenInApplication: { application, documentIDs in
                        onOpenInApplication(application, documentIDs)
                    },
                    onRevealInFinder: {
                        onRevealInFinder($0)
                    },
                    onStopWatchingFolders: {
                        onStopWatchingFolders($0)
                    },
                    onClose: {
                        onCloseDocuments($0)
                    },
                    onCloseOthers: {
                        onCloseOtherDocuments($0)
                    },
                    onCloseAll: {
                        onCloseAllDocuments()
                    }
                )
                .tag(document.id)
            }
            .listStyle(.sidebar)

            Divider()

            HStack(spacing: 8) {
                if sidebarPlacement == .left {
                    sidebarSortMenu
                    Spacer(minLength: 0)
                    sidebarPlacementButton
                } else {
                    sidebarPlacementButton
                    Spacer(minLength: 0)
                    sidebarSortMenu
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .frame(
            minWidth: ReaderSidebarWorkspaceMetrics.sidebarMinimumWidth,
            idealWidth: ReaderSidebarWorkspaceMetrics.sidebarIdealWidth,
            maxHeight: .infinity
        )
    }

    private var detailColumn: some View {
        detail(controller.selectedReaderStore)
            .frame(
                minWidth: ReaderSidebarWorkspaceMetrics.detailMinimumWidth,
                maxWidth: .infinity,
                maxHeight: .infinity
            )
    }

    private var sidebarSortMenu: some View {
        Menu {
            ForEach(ReaderSidebarSortMode.allCases, id: \.self) { mode in
                Button {
                    settingsStore.updateSidebarSortMode(mode)
                } label: {
                    if mode == currentSidebarSortMode {
                        Label(mode.displayName, systemImage: "checkmark")
                    } else {
                        Text(mode.displayName)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(currentSidebarSortMode.footerLabel)
                Image(systemName: "chevron.down")
            }
            .fixedSize(horizontal: true, vertical: false)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize(horizontal: true, vertical: false)
        .help("Sort sidebar by \(currentSidebarSortMode.displayName)")
        .accessibilityLabel("Sidebar sorting")
        .accessibilityValue(currentSidebarSortMode.displayName)
    }

    private var sidebarPlacementButton: some View {
        Button(action: onToggleSidebarPlacement) {
            HStack(spacing: 6) {
                Image(systemName: toggleButtonImageName)
                Image(systemName: toggleButtonArrowImageName)
            }
            .frame(maxWidth: .infinity, alignment: toggleButtonAlignment)
            .contentShape(Rectangle())
            .help(toggleButtonTitle)
        }
        .buttonStyle(.plain)
        .help(toggleButtonTitle)
        .accessibilityLabel(toggleButtonTitle)
    }

    private var toggleButtonTitle: String {
        switch sidebarPlacement {
        case .left:
            return "Move Sidebar Right"
        case .right:
            return "Move Sidebar Left"
        }
    }

    private var toggleButtonImageName: String {
        switch sidebarPlacement {
        case .left:
            return "sidebar.right"
        case .right:
            return "sidebar.left"
        }
    }

    private var toggleButtonArrowImageName: String {
        switch sidebarPlacement {
        case .left:
            return "arrow.right"
        case .right:
            return "arrow.left"
        }
    }

    private var toggleButtonAlignment: Alignment {
        switch sidebarPlacement {
        case .left:
            return .trailing
        case .right:
            return .leading
        }
    }

}

private struct ReaderSidebarDocumentRow: View {
    @Environment(\.colorScheme) private var colorScheme

    let documentID: UUID
    let documents: [ReaderSidebarDocumentController.Document]
    @ObservedObject var readerStore: ReaderStore
    let watchedDocumentIDs: Set<UUID>
    let selectedDocumentIDs: Set<UUID>
    let canClose: Bool
    let onOpenInDefaultApp: (Set<UUID>) -> Void
    let onOpenInApplication: (ReaderExternalApplication, Set<UUID>) -> Void
    let onRevealInFinder: (Set<UUID>) -> Void
    let onStopWatchingFolders: (Set<UUID>) -> Void
    let onClose: (Set<UUID>) -> Void
    let onCloseOthers: (Set<UUID>) -> Void
    let onCloseAll: () -> Void

    private var effectiveDocumentIDs: Set<UUID> {
        if selectedDocumentIDs.contains(documentID), selectedDocumentIDs.count > 1 {
            return selectedDocumentIDs
        }

        return [documentID]
    }

    private var effectiveDocuments: [ReaderSidebarDocumentController.Document] {
        documents.filter { effectiveDocumentIDs.contains($0.id) }
    }

    private var effectiveReaderStores: [ReaderStore] {
        effectiveDocuments.map(\.readerStore)
    }

    private var effectiveOpenInApplications: [ReaderExternalApplication] {
        guard let firstReaderStore = effectiveReaderStores.first(where: { $0.fileURL != nil }) else {
            return []
        }

        return firstReaderStore.openInApplications.filter { application in
            effectiveReaderStores
                .filter { $0.fileURL != nil }
                .allSatisfy { $0.openInApplications.contains(application) }
        }
    }

    private var hasAnyOpenFile: Bool {
        effectiveReaderStores.contains(where: { $0.fileURL != nil })
    }

    private var watchingDocumentCount: Int {
        effectiveDocumentIDs.intersection(watchedDocumentIDs).count
    }

    private var isMultiSelectionContext: Bool {
        effectiveDocumentIDs.count > 1
    }

    private var openInDefaultAppLabel: String {
        isMultiSelectionContext ? "Open Selected in Default App" : "Open in Default App"
    }

    private var openInLabel: String {
        isMultiSelectionContext ? "Open Selected in" : "Open in"
    }

    private var revealInFinderLabel: String {
        isMultiSelectionContext ? "Reveal Selected in Finder" : "Reveal in Finder"
    }

    private var stopWatchingLabel: String {
        watchingDocumentCount > 1 ? "Stop Watching Selected Folders" : "Stop Watching Folder"
    }

    private var closeLabel: String {
        isMultiSelectionContext ? "Close Selected Files" : "Close"
    }

    private var closeOtherLabel: String {
        isMultiSelectionContext ? "Close Unselected Files" : "Close Other Files"
    }

    private var changedIndicatorColor: Color {
        switch indicatorState {
        case .deletedExternalChange:
            return Color(hex: readerStore.currentSettings.syntaxTheme.changeDeletedHex) ?? .accentColor
        case .externalChange:
            return Color.folderWatchHighlight(for: readerStore.currentSettings, colorScheme: colorScheme)
        case .none:
            return .clear
        }
    }

    private var indicatorState: ReaderDocumentIndicatorState {
        ReaderDocumentIndicatorState(
            hasUnacknowledgedExternalChange: readerStore.hasUnacknowledgedExternalChange,
            isCurrentFileMissing: readerStore.isCurrentFileMissing
        )
    }

    private var isSelected: Bool {
        selectedDocumentIDs.contains(documentID)
    }

    private var directoryTextColor: Color {
        if isSelected {
            return .primary
        }

        return colorScheme == .light ? Color.primary.opacity(0.78) : .secondary
    }

    private var lastChangedTextColor: Color {
        if isSelected {
            return Color.primary.opacity(0.72)
        }

        return colorScheme == .light ? Color.primary.opacity(0.62) : .secondary
    }

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(directoryText)
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundStyle(directoryTextColor)
                    .lineLimit(1)
                    .truncationMode(.middle)

                TimelineView(.periodic(from: .now, by: 20)) { context in
                    Text(lastChangedText(relativeTo: context.date))
                        .font(.system(size: 10, weight: .regular, design: .rounded))
                        .foregroundStyle(lastChangedTextColor)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            Spacer(minLength: 8)

            if indicatorState.showsIndicator {
                Circle()
                    .fill(changedIndicatorColor)
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
            }

            if canClose {
                Button {
                    onClose([documentID])
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Close")
            }
        }
        .padding(.vertical, 2)
        .contextMenu {
            if hasAnyOpenFile {
                Button(openInDefaultAppLabel) {
                    onOpenInDefaultApp(effectiveDocumentIDs)
                }

                if !effectiveOpenInApplications.isEmpty {
                    Menu(openInLabel) {
                        ForEach(effectiveOpenInApplications) { application in
                            Button(application.displayName) {
                                onOpenInApplication(application, effectiveDocumentIDs)
                            }
                        }
                    }
                }

                Button(revealInFinderLabel) {
                    onRevealInFinder(effectiveDocumentIDs)
                }
            }

            if watchingDocumentCount > 0 {
                Divider()

                Button(stopWatchingLabel) {
                    onStopWatchingFolders(effectiveDocumentIDs)
                }
            }

            if canClose {
                Divider()

                Button(closeLabel) {
                    onClose(effectiveDocumentIDs)
                }

                if effectiveDocumentIDs.count < documents.count {
                    Button(closeOtherLabel) {
                        onCloseOthers(effectiveDocumentIDs)
                    }
                }

                Button("Close All Files") {
                    onCloseAll()
                }
            }
        }
    }

    private var title: String {
        if readerStore.fileDisplayName.isEmpty {
            return "Untitled"
        }

        return readerStore.fileDisplayName
    }

    private var directoryText: String {
        readerStore.fileURL?.deletingLastPathComponent().path(percentEncoded: false) ?? "No file open"
    }

    private func lastChangedText(relativeTo now: Date) -> String {
        if readerStore.isCurrentFileMissing {
            return "File deleted externally"
        }

        guard let fileLastModifiedAt = readerStore.fileLastModifiedAt else {
            return "No change timestamp"
        }

        let relativeText = ReaderStatusFormatting.relativeText(
            for: fileLastModifiedAt,
            relativeTo: now
        )
        return "Last modified \(relativeText)"
    }
}