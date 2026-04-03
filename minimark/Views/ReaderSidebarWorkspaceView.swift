import SwiftUI

enum ReaderSidebarWorkspaceMetrics {
    static let sidebarMinimumWidth: CGFloat = ReaderUITestLaunchConfiguration.current.isUITestModeEnabled ? 160 : 220
    static let sidebarIdealWidth: CGFloat = ReaderUITestLaunchConfiguration.current.isUITestModeEnabled ? 160 : 250
    static let detailMinimumWidth: CGFloat = 420
    static let toolbarHeight: CGFloat = ReaderTopBarMetrics.mainBarHeight
}

private struct SidebarWidthPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        if next > 0 { value = next }
    }
}

/// Bridges to AppKit to set the NSSplitView divider position and holding priorities.
/// HSplitView ignores `idealWidth` for restored widths, so this applies the correct
/// position programmatically on first appearance and whenever width or placement changes.
private struct SidebarDividerPositionSetter: NSViewRepresentable {
    let targetWidth: CGFloat
    let placement: ReaderMultiFileDisplayMode.SidebarPlacement

    func makeNSView(context: Context) -> SidebarPositionHelperView {
        let view = SidebarPositionHelperView()
        view.isHidden = true
        view.targetWidth = targetWidth
        view.placement = placement
        return view
    }

    func updateNSView(_ nsView: SidebarPositionHelperView, context: Context) {
        nsView.updateIfNeeded(targetWidth: targetWidth, placement: placement)
    }
}

private final class SidebarPositionHelperView: NSView {
    /// Holding priority one tick above .defaultLow (250) so the sidebar
    /// resists proportional resizing when the window expands or shrinks.
    private static let sidebarHoldingPriority: NSLayoutConstraint.Priority = .init(251)
    private static let widthEpsilon: CGFloat = 1

    var targetWidth: CGFloat = 0
    var placement: ReaderMultiFileDisplayMode.SidebarPlacement = .left
    private var lastAppliedWidth: CGFloat = 0
    private var lastAppliedPlacement: ReaderMultiFileDisplayMode.SidebarPlacement?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        applyPosition()
    }

    func updateIfNeeded(targetWidth newWidth: CGFloat, placement newPlacement: ReaderMultiFileDisplayMode.SidebarPlacement) {
        let widthChanged = abs(targetWidth - newWidth) > Self.widthEpsilon
        let placementChanged = placement != newPlacement
        if widthChanged { targetWidth = newWidth }
        if placementChanged { placement = newPlacement }
        if widthChanged || placementChanged {
            lastAppliedWidth = 0
            applyPosition()
        }
    }

    private func applyPosition() {
        guard let splitView = ancestorSplitView(),
              splitView.arrangedSubviews.count > 1,
              splitView.delegate as? NSSplitViewController == nil else {
            return
        }
        guard abs(lastAppliedWidth - targetWidth) > Self.widthEpsilon
                || lastAppliedPlacement != placement else {
            return
        }
        lastAppliedWidth = targetWidth
        lastAppliedPlacement = placement

        let sidebarIndex = placement == .left ? 0 : 1
        let detailIndex = placement == .left ? 1 : 0
        splitView.setHoldingPriority(Self.sidebarHoldingPriority, forSubviewAt: sidebarIndex)
        splitView.setHoldingPriority(.defaultLow, forSubviewAt: detailIndex)

        let position: CGFloat
        if placement == .left {
            position = targetWidth
        } else {
            position = splitView.bounds.width - targetWidth - splitView.dividerThickness
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        splitView.setPosition(position, ofDividerAt: 0)
        CATransaction.commit()
    }

    private func ancestorSplitView() -> NSSplitView? {
        var current = superview
        while let view = current {
            if let split = view as? NSSplitView { return split }
            current = view.superview
        }
        return nil
    }
}

struct ReaderSidebarWorkspaceView<Detail: View>: View {
    @ObservedObject var controller: ReaderSidebarDocumentController
    @ObservedObject var settingsStore: ReaderSettingsStore
    let sidebarPlacement: ReaderMultiFileDisplayMode.SidebarPlacement
    @Binding var collapsedGroupIDs: Set<String>
    @Binding var pinnedGroupIDs: Set<String>
    @Binding var fileSortMode: ReaderSidebarSortMode
    @Binding var groupSortMode: ReaderSidebarSortMode
    @Binding var sidebarWidth: CGFloat
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
        .onChange(of: activeDirectoryPaths) { _, paths in
            let activeGroupIDs = Set(paths)
            collapsedGroupIDs.formIntersection(activeGroupIDs)
            pinnedGroupIDs.formIntersection(activeGroupIDs)
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

    private var currentFileSidebarSortMode: ReaderSidebarSortMode {
        fileSortMode
    }

    private var currentGroupSidebarSortMode: ReaderSidebarSortMode {
        groupSortMode
    }

    private var displayedDocuments: [ReaderSidebarDocumentController.Document] {
        currentFileSidebarSortMode.sorted(controller.documents) { document in
            ReaderSidebarSortDescriptor(
                displayName: document.readerStore.fileDisplayName,
                lastChangedAt: document.readerStore.fileLastModifiedAt ?? document.readerStore.lastExternalChangeAt ?? document.readerStore.lastRefreshAt
            )
        }
    }

    private func sidebarGrouping(for documents: [ReaderSidebarDocumentController.Document]) -> ReaderSidebarGrouping {
        let directoryOrderSourceDocuments: [ReaderSidebarDocumentController.Document]

        if currentGroupSidebarSortMode == .openOrder {
            let allowedDocumentIDs = Set(documents.map(\.id))
            directoryOrderSourceDocuments = controller.documents.filter { allowedDocumentIDs.contains($0.id) }
        } else {
            directoryOrderSourceDocuments = documents
        }

        return ReaderSidebarGrouping.group(
            documents,
            sortMode: currentGroupSidebarSortMode,
            directoryOrderSourceDocuments: directoryOrderSourceDocuments,
            pinnedGroupIDs: pinnedGroupIDs
        )
    }

    private func isGroupExpanded(_ groupID: String) -> Binding<Bool> {
        Binding(
            get: { !collapsedGroupIDs.contains(groupID) },
            set: { isExpanded in
                if isExpanded {
                    collapsedGroupIDs.remove(groupID)
                } else {
                    collapsedGroupIDs.insert(groupID)
                }
            }
        )
    }

    private func toggleGroupPin(_ groupID: String) {
        if pinnedGroupIDs.contains(groupID) {
            pinnedGroupIDs.remove(groupID)
        } else {
            pinnedGroupIDs.insert(groupID)
        }
    }

    private var activeDirectoryPaths: [String] {
        controller.documents.map { document in
            document.readerStore.fileURL?.deletingLastPathComponent().path(percentEncoded: false) ?? ""
        }
    }

    private var watchedDocumentIDs: Set<UUID> {
        controller.watchedDocumentIDs()
    }

    private var sidebarColumn: some View {
        let sortedDocuments = displayedDocuments
        let grouping = sidebarGrouping(for: sortedDocuments)

        return VStack(spacing: 0) {
            sidebarToolbar

            Divider()

            List(
                selection: Binding(
                    get: { selectedDocumentIDs },
                    set: { updateSelection($0) }
                )
            ) {
                switch grouping {
                case .flat(let documents):
                    ForEach(documents) { document in
                        documentRow(for: document, allDocuments: sortedDocuments)
                            .tag(document.id)
                    }
                case .grouped(let groups):
                    ForEach(groups) { group in
                        DisclosureGroup(isExpanded: isGroupExpanded(group.id)) {
                            ForEach(group.documents) { document in
                                documentRow(for: document, allDocuments: sortedDocuments)
                                    .tag(document.id)
                            }
                        } label: {
                            ReaderSidebarGroupHeader(
                                displayName: group.displayName,
                                documentCount: group.documents.count,
                                isPinned: group.isPinned,
                                indicatorState: group.indicatorState,
                                settings: settingsStore.currentSettings,
                                onTogglePin: {
                                    toggleGroupPin(group.id)
                                },
                                onCloseGroup: {
                                    onCloseDocuments(Set(group.documents.map(\.id)))
                                }
                            )
                        }
                        .disclosureGroupStyle(SidebarGroupDisclosureStyle())
                    }
                }
            }
            .listStyle(.sidebar)

            if let session = controller.activeFolderWatchSession {
                Divider()
                sidebarWatchingFooter(session: session)
            }
        }
        .frame(
            minWidth: ReaderSidebarWorkspaceMetrics.sidebarMinimumWidth,
            idealWidth: sidebarWidth,
            maxHeight: .infinity
        )
        .background(
            GeometryReader { geometry in
                Color.clear.preference(
                    key: SidebarWidthPreferenceKey.self,
                    value: geometry.size.width
                )
            }
        )
        .background(SidebarDividerPositionSetter(targetWidth: sidebarWidth, placement: sidebarPlacement))
        .onPreferenceChange(SidebarWidthPreferenceKey.self) { width in
            if width > 0 {
                sidebarWidth = width
            }
        }
    }

    private var sidebarToolbar: some View {
        HStack(spacing: 6) {
            Text("Files")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)

            Spacer(minLength: 0)

            sidebarGroupSortMenu

            sidebarFileSortMenu

            sidebarPlacementButton
        }
        .padding(.horizontal, 12)
        .frame(height: ReaderSidebarWorkspaceMetrics.toolbarHeight)
    }

    private func sidebarWatchingFooter(session: ReaderFolderWatchSession) -> some View {
        HStack(spacing: 6) {
            if let progress = controller.contentScanProgress, !progress.isFinished {
                ProgressView(value: Double(progress.completed), total: max(Double(progress.total), 1))
                    .progressViewStyle(.linear)
                    .frame(maxWidth: 60)

                Text("Scanning \(progress.completed)/\(progress.total) files")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Circle()
                    .fill(Color.green)
                    .frame(width: 6, height: 6)

                if let fileCount = controller.scannedFileCount, fileCount > 0 {
                    Text("\(fileCount) \(fileCount == 1 ? "file" : "files")")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

                Text(session.detailSummaryTitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .animation(.easeInOut(duration: 0.3), value: controller.contentScanProgress?.isFinished)
    }

    private func documentRow(
        for document: ReaderSidebarDocumentController.Document,
        allDocuments: [ReaderSidebarDocumentController.Document]
    ) -> some View {
        ReaderSidebarDocumentRow(
            documentID: document.id,
            documents: allDocuments,
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
    }

    private var detailColumn: some View {
        detail(controller.selectedReaderStore)
            .frame(
                minWidth: ReaderSidebarWorkspaceMetrics.detailMinimumWidth,
                maxWidth: .infinity,
                maxHeight: .infinity
            )
    }

    private var sidebarGroupSortMenu: some View {
        Menu {
            ForEach(ReaderSidebarSortMode.allCases, id: \.self) { mode in
                Button {
                    groupSortMode = mode
                } label: {
                    if mode == currentGroupSidebarSortMode {
                        Label(mode.displayName, systemImage: "checkmark")
                    } else {
                        Text(mode.displayName)
                    }
                }
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "folder")
                    .font(.system(size: 9, weight: .medium))
                Text(currentGroupSidebarSortMode.footerLabel)
                    .font(.system(size: 10, weight: .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .semibold))
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(.quaternary.opacity(0.5))
            .clipShape(Capsule())
            .contentShape(Capsule())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize(horizontal: true, vertical: false)
        .help("Sort groups by \(currentGroupSidebarSortMode.displayName)")
        .accessibilityLabel("Sidebar group sorting")
        .accessibilityValue(currentGroupSidebarSortMode.displayName)
    }

    private var sidebarFileSortMenu: some View {
        Menu {
            ForEach(ReaderSidebarSortMode.allCases, id: \.self) { mode in
                Button {
                    fileSortMode = mode
                } label: {
                    if mode == currentFileSidebarSortMode {
                        Label(mode.displayName, systemImage: "checkmark")
                    } else {
                        Text(mode.displayName)
                    }
                }
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "doc")
                    .font(.system(size: 9, weight: .medium))
                Text(currentFileSidebarSortMode.footerLabel)
                    .font(.system(size: 10, weight: .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .semibold))
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(.quaternary.opacity(0.5))
            .clipShape(Capsule())
            .contentShape(Capsule())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize(horizontal: true, vertical: false)
        .help("Sort files by \(currentFileSidebarSortMode.displayName)")
        .accessibilityLabel("Sidebar file sorting")
        .accessibilityValue(currentFileSidebarSortMode.displayName)
    }

    private var sidebarPlacementButton: some View {
        Button(action: onToggleSidebarPlacement) {
            Image(systemName: toggleButtonImageName)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
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


}

private struct ReaderSidebarDocumentRow: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false

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
        indicatorState.color(for: readerStore.currentSettings, colorScheme: colorScheme)
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
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)

                TimelineView(.periodic(from: .now, by: 20)) { context in
                    Text(lastChangedText(relativeTo: context.date))
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(lastChangedTextColor)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            Spacer(minLength: 8)

            if indicatorState.showsIndicator {
                Circle()
                    .fill(changedIndicatorColor)
                    .frame(width: 7, height: 7)
                    .accessibilityHidden(true)
            }

            if canClose {
                Button {
                    onClose([documentID])
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .opacity(isHovered || isSelected ? 1 : 0)
                .allowsHitTesting(isHovered || isSelected)
                .accessibilityHidden(!(isHovered || isSelected))
                .help("Close")
            }
        }
        .padding(.vertical, 2)
        .accessibilityIdentifier("sidebar-document-\(title)")
        .onHover { hovering in
            isHovered = hovering
        }
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

    private func lastChangedText(relativeTo now: Date) -> String {
        if readerStore.isCurrentFileMissing {
            return "File deleted externally"
        }

        guard let fileLastModifiedAt = readerStore.fileLastModifiedAt else {
            return "No change timestamp"
        }

        return ReaderStatusFormatting.relativeText(
            for: fileLastModifiedAt,
            relativeTo: now
        )
    }
}

private struct ReaderSidebarGroupHeader: View {
    @Environment(\.colorScheme) private var colorScheme

    let displayName: String
    let documentCount: Int
    let isPinned: Bool
    let indicatorState: ReaderDocumentIndicatorState
    let settings: ReaderSettings
    let onTogglePin: () -> Void
    let onCloseGroup: () -> Void

    private var pinButtonLabel: String {
        isPinned ? "Unpin group \(displayName)" : "Pin group \(displayName)"
    }

    private var closeGroupLabel: String {
        "Close all files in group \(displayName)"
    }

    var body: some View {
        HStack(spacing: 6) {
            Button {
                onTogglePin()
            } label: {
                Image(systemName: isPinned ? "pin.fill" : "pin")
                    .font(.system(size: 10))
                    .foregroundStyle(isPinned ? .primary : .tertiary)
                    .rotationEffect(.degrees(30))
            }
            .buttonStyle(.plain)
            .help(pinButtonLabel)
            .accessibilityLabel(pinButtonLabel)

            Text(displayName)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.middle)

            if indicatorState.showsIndicator {
                Circle()
                    .fill(indicatorState.color(for: settings, colorScheme: colorScheme))
                    .frame(width: 6, height: 6)
                    .accessibilityHidden(true)
            }

            Spacer(minLength: 4)

            Text("\(documentCount)")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(.quaternary.opacity(0.5))
                .clipShape(Capsule())
                .accessibilityLabel("\(documentCount) document\(documentCount == 1 ? "" : "s")")

            Button {
                onCloseGroup()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(closeGroupLabel)
            .accessibilityLabel(closeGroupLabel)
            .accessibilityHint("Closes every open file in this group")
        }
    }
}

private struct SidebarGroupDisclosureStyle: DisclosureGroupStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                configuration.isExpanded.toggle()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 16, height: 16)
                    .background(.quaternary.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .rotationEffect(configuration.isExpanded ? .degrees(90) : .zero)
                    .animation(.easeInOut(duration: 0.15), value: configuration.isExpanded)

                configuration.label
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color(nsColor: .labelColor).opacity(0.04))
            )
        }
        .buttonStyle(.plain)

        if configuration.isExpanded {
            configuration.content
                .padding(.leading, 12)
        }
    }
}