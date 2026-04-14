import AppKit
import SwiftUI

enum ReaderSidebarWorkspaceMetrics {
    static let sidebarMinimumWidth: CGFloat = ReaderUITestLaunchConfiguration.current.isUITestModeEnabled ? 273 : 220
    static let sidebarIdealWidth: CGFloat = ReaderUITestLaunchConfiguration.current.isUITestModeEnabled ? 273 : 250
    static let detailMinimumWidth: CGFloat = 420
    static let toolbarHeight: CGFloat = ReaderTopBarMetrics.mainBarHeight
}

struct ReaderSidebarWorkspaceView<Detail: View>: View {
    var controller: ReaderSidebarDocumentController
    var settingsStore: ReaderSettingsStore
    var groupState: SidebarGroupStateController
    let sidebarPlacement: ReaderMultiFileDisplayMode.SidebarPlacement
    let sidebarWidth: CGFloat
    let onSidebarWidthChanged: (CGFloat) -> Void
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
    @State private var isDraggingDivider = false

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
            if filteredSelection.isEmpty {
                if let firstDocumentID = groupState.computedGrouping.firstDocumentID {
                    selectedDocumentIDs = [firstDocumentID]
                    scheduleControllerSelection(firstDocumentID)
                }
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

        if let nextSelectedDocumentID = groupState.computedGrouping.allDocumentIDs.first(where: { selection.contains($0) }) {
            scheduleControllerSelection(nextSelectedDocumentID)
        }
    }

    private func scheduleControllerSelection(_ documentID: UUID) {
        Task { @MainActor in
            controller.selectDocument(documentID)
        }
    }

    private var watchedDocumentIDs: Set<UUID> {
        controller.folderWatchCoordinator.watchedDocumentIDs()
    }

    private var sidebarColumn: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                sidebarToolbar

                Divider()

                SidebarGroupListContent(
                    groupState: groupState,
                    controller: controller,
                    settingsStore: settingsStore,
                    selectedDocumentIDs: $selectedDocumentIDs,
                    watchedDocumentIDs: watchedDocumentIDs,
                    onUpdateSelection: { updateSelection($0) },
                    onOpenInDefaultApp: onOpenInDefaultApp,
                    onOpenInApplication: { application, documentIDs in
                        onOpenInApplication(application, documentIDs)
                    },
                    onRevealInFinder: onRevealInFinder,
                    onStopWatchingFolders: onStopWatchingFolders,
                    onCloseDocuments: onCloseDocuments,
                    onCloseOtherDocuments: onCloseOtherDocuments,
                    onCloseAllDocuments: onCloseAllDocuments
                )
            }
            .frame(maxHeight: .infinity)

            SidebarScanProgressView(controller: controller)
        }
        .frame(
            minWidth: ReaderSidebarWorkspaceMetrics.sidebarMinimumWidth,
            idealWidth: sidebarWidth,
            maxWidth: isDraggingDivider ? .infinity : max(sidebarWidth, ReaderSidebarWorkspaceMetrics.sidebarMinimumWidth),
            maxHeight: .infinity
        )
        .background(SidebarDividerPositionSetter(
            targetWidth: sidebarWidth,
            placement: sidebarPlacement,
            onDividerDragged: { width in
                onSidebarWidthChanged(width)
            },
            onDividerDragActive: { active in
                isDraggingDivider = active
            }
        ))
        .accessibilityIdentifier("sidebar-column")
    }

    private var sidebarToolbar: some View {
        HStack(spacing: 6) {
            sidebarGroupSortMenu
                .firstUseHint(.manualGroupReorder, message: "Drag groups to reorder", settingsStore: settingsStore, isActive: groupState.sortMode == .manualOrder)

            sidebarFileSortMenu

            if selectedDocumentIDs.count > 1 {
                selectionCountBadge
                    .firstUseHint(.multiSelect, message: "⌘-click to select multiple files", settingsStore: settingsStore)
            }

            Spacer(minLength: 0)

            if groupState.isGrouped {
                sidebarExpandCollapseButtons
            }
        }
        .padding(.horizontal, 12)
        .frame(height: ReaderSidebarWorkspaceMetrics.toolbarHeight)
        .animation(.easeInOut(duration: 0.15), value: selectedDocumentIDs.count > 1)
    }

    private var selectionCountBadge: some View {
        Text("\(selectedDocumentIDs.count) selected")
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(.quaternary.opacity(0.5))
            .clipShape(Capsule())
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
    }

    private var sidebarExpandCollapseButtons: some View {
        HStack(spacing: 2) {
            sidebarToolbarButton("rectangle.expand.vertical", help: "Expand all groups") {
                groupState.expandAllGroups()
            }
            sidebarToolbarButton("rectangle.compress.vertical", help: "Collapse all groups") {
                groupState.collapseAllGroups()
            }
            sidebarToolbarButton("arrow.uturn.backward", help: "Restore manual expand/collapse state") {
                groupState.restoreManualExpandState()
            }
            .disabled(!groupState.isInBulkExpandState)
        }
    }

    private func sidebarToolbarButton(_ systemName: String, help: String, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { action() }
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(help)
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
            ForEach(ReaderSidebarSortMode.availableCases(hasManualOrder: groupState.manualGroupOrder != nil), id: \.self) { mode in
                Button {
                    groupState.sortMode = mode
                } label: {
                    if mode == groupState.sortMode {
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
                Text(groupState.sortMode.footerLabel)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
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
        .help("Sort groups by \(groupState.sortMode.displayName)")
        .accessibilityLabel("Sidebar group sorting")
        .accessibilityValue(groupState.sortMode.displayName)
    }

    private var sidebarFileSortMenu: some View {
        Menu {
            ForEach(ReaderSidebarSortMode.allCases, id: \.self) { mode in
                Button {
                    groupState.fileSortMode = mode
                } label: {
                    if mode == groupState.fileSortMode {
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
                Text(groupState.fileSortMode.footerLabel)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
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
        .help("Sort files by \(groupState.fileSortMode.displayName)")
        .accessibilityLabel("Sidebar file sorting")
        .accessibilityValue(groupState.fileSortMode.displayName)
    }

}

private struct ReaderSidebarDocumentRow: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false
    @State private var isIndicatorPulsing = false
    @State private var lastHandledIndicatorPulseToken: Int = -1
    @State private var indicatorPulseTask: Task<Void, Never>?

    let state: SidebarRowState
    let settings: ReaderSettings
    let documents: [ReaderSidebarDocumentController.Document]
    let readerStore: ReaderStore
    let watchedDocumentIDs: Set<UUID>
    let selectedDocumentIDs: Set<UUID>
    let showsSelectionBackground: Bool
    let canClose: Bool
    let onOpenInDefaultApp: (Set<UUID>) -> Void
    let onOpenInApplication: (ReaderExternalApplication, Set<UUID>) -> Void
    let onRevealInFinder: (Set<UUID>) -> Void
    let onStopWatchingFolders: (Set<UUID>) -> Void
    let onClose: (Set<UUID>) -> Void
    let onCloseOthers: (Set<UUID>) -> Void
    let onCloseAll: () -> Void

    private var effectiveDocumentIDs: Set<UUID> {
        if selectedDocumentIDs.contains(state.id), selectedDocumentIDs.count > 1 {
            return selectedDocumentIDs
        }

        return [state.id]
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
        indicatorState.color(for: settings, colorScheme: colorScheme)
    }

    private var indicatorState: ReaderDocumentIndicatorState {
        state.indicatorState
    }

    private var isSelected: Bool {
        selectedDocumentIDs.contains(state.id)
    }

    private var indicatorScale: CGFloat {
        isIndicatorPulsing ? 1.3 : 1.0
    }

    private var indicatorOpacity: Double {
        isIndicatorPulsing ? 0.45 : 1.0
    }

    private var lastChangedTextColor: Color {
        if isSelected {
            return Color.primary.opacity(0.72)
        }

        return colorScheme == .light ? Color.primary.opacity(0.62) : .secondary
    }

    private var selectionBackgroundColor: Color {
        Color(nsColor: .selectedContentBackgroundColor).opacity(colorScheme == .dark ? 0.35 : 0.45)
    }

    private var selectionBorderColor: Color {
        Color(nsColor: .selectedContentBackgroundColor).opacity(colorScheme == .dark ? 0.5 : 0.55)
    }

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)

                TimelineView(AdaptiveTimestampSchedule(lastModified: state.isFileMissing ? nil : state.lastModified)) { context in
                    Text(lastChangedText(currentDate: context.date))
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
                    .scaleEffect(indicatorScale)
                    .opacity(indicatorOpacity)
                    .animation(
                        isIndicatorPulsing
                            ? .easeInOut(duration: 0.25).repeatCount(4, autoreverses: true)
                            : .easeOut(duration: 0.18),
                        value: isIndicatorPulsing
                    )
                    .accessibilityHidden(true)
            }

            if canClose {
                Button {
                    onClose([state.id])
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .opacity(isHovered || isSelected ? 1 : 0)
                .scaleEffect(isHovered || isSelected ? 1 : 0.85)
                .allowsHitTesting(isHovered || isSelected)
                .accessibilityHidden(!(isHovered || isSelected))
                .help("Close")
            }
        }
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(
                    showsSelectionBackground && isSelected
                        ? selectionBackgroundColor
                        : (isHovered ? Color.primary.opacity(0.04) : .clear)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(
                    showsSelectionBackground && isSelected
                        ? selectionBorderColor
                        : .clear,
                    lineWidth: 0.5
                )
        )
        .animation(.easeInOut(duration: 0.15), value: isSelected)
        .padding(.vertical, 2)
        .accessibilityIdentifier("sidebar-document-\(title)")
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .onAppear {
            triggerIndicatorPulseIfNeeded(for: state.indicatorPulseToken)
        }
        .onChange(of: state.indicatorPulseToken) { _, newToken in
            triggerIndicatorPulseIfNeeded(for: newToken)
        }
        .onDisappear {
            indicatorPulseTask?.cancel()
            indicatorPulseTask = nil
            isIndicatorPulsing = false
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
        state.title
    }

    private func lastChangedText(currentDate: Date) -> String {
        if state.isFileMissing {
            return "File deleted externally"
        }

        guard let fileLastModifiedAt = state.lastModified else {
            return "No change timestamp"
        }

        return ReaderStatusFormatting.relativeText(
            for: fileLastModifiedAt,
            relativeTo: currentDate
        )
    }

    private func triggerIndicatorPulseIfNeeded(for token: Int) {
        guard token > lastHandledIndicatorPulseToken else { return }
        guard indicatorState.showsIndicator else { return }

        lastHandledIndicatorPulseToken = token
        indicatorPulseTask?.cancel()
        indicatorPulseTask = Task { @MainActor in
            isIndicatorPulsing = false
            await Task.yield()
            isIndicatorPulsing = true
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            isIndicatorPulsing = false
        }
    }
}

private struct ReaderSidebarGroupHeader: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var isIndicatorPulsing = false
    @State private var lastHandledPulseToken: Int = -1
    @State private var indicatorPulseTask: Task<Void, Never>?

    let displayName: String
    let documentCount: Int
    let isPinned: Bool
    let indicatorStates: [ReaderDocumentIndicatorState]
    let indicatorPulseToken: Int
    let settings: ReaderSettings
    let onTogglePin: () -> Void
    let onCloseGroup: () -> Void

    private var pinButtonLabel: String {
        isPinned ? "Unpin group \(displayName)" : "Pin group \(displayName)"
    }

    private var closeGroupLabel: String {
        "Close all files in group \(displayName)"
    }

    private var indicatorScale: CGFloat {
        isIndicatorPulsing ? 1.3 : 1.0
    }

    private var indicatorOpacity: Double {
        isIndicatorPulsing ? 0.45 : 1.0
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

            if !indicatorStates.isEmpty {
                HStack(spacing: 3) {
                    ForEach(Array(indicatorStates.enumerated()), id: \.offset) { _, indicatorState in
                        Circle()
                            .fill(indicatorState.color(for: settings, colorScheme: colorScheme))
                            .frame(width: 6, height: 6)
                            .scaleEffect(indicatorScale)
                            .opacity(indicatorOpacity)
                            .animation(
                                isIndicatorPulsing
                                    ? .easeInOut(duration: 0.25).repeatCount(4, autoreverses: true)
                                    : .easeOut(duration: 0.18),
                                value: isIndicatorPulsing
                            )
                            .accessibilityHidden(true)
                    }
                }
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
        .onAppear {
            triggerIndicatorPulseIfNeeded(for: indicatorPulseToken)
        }
        .onChange(of: indicatorPulseToken) { _, newToken in
            triggerIndicatorPulseIfNeeded(for: newToken)
        }
        .onDisappear {
            indicatorPulseTask?.cancel()
            indicatorPulseTask = nil
            isIndicatorPulsing = false
        }
    }

    private func triggerIndicatorPulseIfNeeded(for token: Int) {
        guard token > lastHandledPulseToken else { return }
        guard !indicatorStates.isEmpty else { return }

        lastHandledPulseToken = token
        indicatorPulseTask?.cancel()
        indicatorPulseTask = Task { @MainActor in
            isIndicatorPulsing = false
            await Task.yield()
            isIndicatorPulsing = true
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            isIndicatorPulsing = false
        }
    }
}

private struct SidebarGroupDropIndicator: View {
    var body: some View {
        Capsule()
            .fill(Color.accentColor)
            .frame(height: 4)
            .shadow(color: .accentColor.opacity(0.4), radius: 4)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .leading)))
    }
}

private struct SidebarGroupListContent: View {
    var groupState: SidebarGroupStateController
    var controller: ReaderSidebarDocumentController
    let settingsStore: ReaderSettingsStore
    @Binding var selectedDocumentIDs: Set<UUID>
    let watchedDocumentIDs: Set<UUID>
    let onUpdateSelection: (Set<UUID>) -> Void
    let onOpenInDefaultApp: (Set<UUID>) -> Void
    let onOpenInApplication: (ReaderExternalApplication, Set<UUID>) -> Void
    let onRevealInFinder: (Set<UUID>) -> Void
    let onStopWatchingFolders: (Set<UUID>) -> Void
    let onCloseDocuments: (Set<UUID>) -> Void
    let onCloseOtherDocuments: (Set<UUID>) -> Void
    let onCloseAllDocuments: () -> Void
    @State private var draggedGroupID: String?
    @State private var dropTargetIndex: Int?
    @State private var dragTranslation: CGSize = .zero
    @State private var groupFrameCache = GroupFrameCache()
    @State private var lastDragEndDate = Date.distantPast

    var body: some View {
        switch groupState.computedGrouping {
        case .flat(let documents):
            flatSidebarList(documents: documents)
        case .grouped(let groups):
            groupedSidebarList(groups: groups)
        }
    }

    @ViewBuilder
    private func flatSidebarList(
        documents: [ReaderSidebarDocumentController.Document]
    ) -> some View {
        List(
            selection: Binding(
                get: { selectedDocumentIDs },
                set: { onUpdateSelection($0) }
            )
        ) {
            ForEach(documents) { document in
                documentRow(for: document, allDocuments: controller.documents)
                    .tag(document.id)
            }
        }
        .listStyle(.sidebar)
    }

    @ViewBuilder
    private func groupedSidebarList(
        groups: [ReaderSidebarGrouping.Group]
    ) -> some View {
        let dragSourceIndex = draggedGroupID.flatMap { id in
            groups.firstIndex { $0.id == id }
        }
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4, pinnedViews: draggedGroupID == nil ? [.sectionHeaders] : []) {
                ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                    if let target = dropTargetIndex, let source = dragSourceIndex,
                       target == index && target != source && target != source + 1 {
                        SidebarGroupDropIndicator()
                    }

                    groupedSection(for: group, at: index)
                }

                if let target = dropTargetIndex, let source = dragSourceIndex,
                   target == groups.count && target != source && target != source + 1 {
                    SidebarGroupDropIndicator()
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
    }

    private func groupedSection(
        for group: ReaderSidebarGrouping.Group,
        at index: Int
    ) -> some View {
        let isExpanded = groupState.isGroupExpanded(group.id)
        let isDragging = draggedGroupID == group.id

        let groupHeader = ReaderSidebarGroupHeader(
            displayName: group.displayName,
            documentCount: group.documents.count,
            isPinned: group.isPinned,
            indicatorStates: group.indicatorStates,
            indicatorPulseToken: group.indicatorPulseToken,
            settings: settingsStore.currentSettings,
            onTogglePin: {
                groupState.toggleGroupPin(group.id)
            },
            onCloseGroup: {
                onCloseDocuments(Set(group.documents.map(\.id)))
            }
        )

        return Section {
            VStack(alignment: .leading, spacing: 0) {
                if isExpanded {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(group.documents) { document in
                            groupedDocumentRow(for: document, allDocuments: controller.documents)
                        }
                    }
                    .padding(.leading, 28)
                    .padding(.trailing, 6)
                    .padding(.bottom, 2)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .clipped()
        } header: {
            SidebarPinnableGroupHeader(
                groupDisplayName: group.displayName,
                isExpanded: isExpanded,
                onToggleExpanded: {
                    guard Date().timeIntervalSince(lastDragEndDate) > 0.3 else { return }
                    withAnimation(.easeInOut(duration: 0.2)) {
                        groupState.setGroupExpanded(group.id, isExpanded: !isExpanded)
                    }
                },
                header: groupHeader
            )
            .opacity(isDragging ? 0.7 : 1.0)
            .shadow(color: isDragging ? .black.opacity(0.2) : .clear, radius: 8, y: 4)
            .scaleEffect(isDragging ? 1.02 : 1.0)
            .offset(isDragging ? dragTranslation : .zero)
            .zIndex(isDragging ? 1 : 0)
            .simultaneousGesture(
                DragGesture(minimumDistance: 5, coordinateSpace: .global)
                    .onChanged { value in
                        handleDragUpdate(value, groupID: group.id)
                    }
                    .onEnded { value in
                        handleDragEnd(value, groups: groupState.computedGrouping)
                    }
            )
        }
        .background(GroupFrameTracker(groupID: group.id, cache: groupFrameCache))
        .animation(.easeInOut(duration: 0.2), value: isExpanded)
    }

    private func handleDragUpdate(_ value: DragGesture.Value, groupID: String) {
        if draggedGroupID == nil {
            draggedGroupID = groupID
        }
        dragTranslation = value.translation
        guard case .grouped(let groups) = groupState.computedGrouping else { return }
        let newTarget = targetIndexFromGlobalY(value.location.y, groups: groups)
        if newTarget != dropTargetIndex {
            withAnimation(.easeInOut(duration: 0.15)) {
                dropTargetIndex = newTarget
            }
        }
    }

    private func handleDragEnd(_ value: DragGesture.Value, groups grouping: ReaderSidebarGrouping) {
        guard let draggedID = draggedGroupID,
              case .grouped(let groups) = grouping,
              let sourceIndex = groups.firstIndex(where: { $0.id == draggedID }),
              let target = dropTargetIndex else {
            resetDragState()
            return
        }

        let destinationIndex: Int
        if target <= sourceIndex {
            destinationIndex = target
        } else {
            destinationIndex = target - 1
        }

        if sourceIndex != destinationIndex {
            withAnimation(.easeInOut(duration: 0.25)) {
                groupState.moveGroup(from: sourceIndex, to: destinationIndex)
            }
        }

        resetDragState()
    }

    private func resetDragState() {
        draggedGroupID = nil
        dropTargetIndex = nil
        dragTranslation = .zero
        lastDragEndDate = Date()
        if case .grouped(let groups) = groupState.computedGrouping {
            let activeIDs = Set(groups.map(\.id))
            groupFrameCache.frames = groupFrameCache.frames.filter { activeIDs.contains($0.key) }
        }
    }

    private func targetIndexFromGlobalY(_ globalY: CGFloat, groups: [ReaderSidebarGrouping.Group]) -> Int {
        for (index, group) in groups.enumerated() {
            if group.id == draggedGroupID { continue }
            guard let frame = groupFrameCache.frames[group.id] else { continue }
            if globalY < frame.midY {
                return index
            }
        }
        return groups.count
    }

    private func groupedDocumentRow(
        for document: ReaderSidebarDocumentController.Document,
        allDocuments: [ReaderSidebarDocumentController.Document]
    ) -> some View {
        documentRow(
            for: document,
            allDocuments: allDocuments,
            showsSelectionBackground: true
        )
            .contentShape(Rectangle())
            .onTapGesture {
                selectDocumentInGroupedSidebar(document.id)
            }
    }

    private func selectDocumentInGroupedSidebar(_ documentID: UUID) {
        let modifierFlags = NSApp.currentEvent?.modifierFlags ?? []
        let isCommandSelection = modifierFlags.contains(.command)
        let isShiftSelection = modifierFlags.contains(.shift)

        if isShiftSelection {
            let orderedDocumentIDs = groupState.computedGrouping.allDocumentIDs
            let anchorID = selectedDocumentIDs.contains(controller.selectedDocumentID)
                ? controller.selectedDocumentID
                : documentID

            guard
                let anchorIndex = orderedDocumentIDs.firstIndex(of: anchorID),
                let targetIndex = orderedDocumentIDs.firstIndex(of: documentID)
            else {
                onUpdateSelection([documentID])
                return
            }

            let lowerBound = min(anchorIndex, targetIndex)
            let upperBound = max(anchorIndex, targetIndex)
            let rangeSelection = Set(orderedDocumentIDs[lowerBound...upperBound])
            onUpdateSelection(rangeSelection)
            return
        }

        if isCommandSelection {
            var nextSelection = selectedDocumentIDs
            if nextSelection.contains(documentID) {
                nextSelection.remove(documentID)
            } else {
                nextSelection.insert(documentID)
            }

            if nextSelection.isEmpty {
                nextSelection = [documentID]
            }

            onUpdateSelection(nextSelection)
            return
        }

        onUpdateSelection([documentID])
    }

    private func documentRow(
        for document: ReaderSidebarDocumentController.Document,
        allDocuments: [ReaderSidebarDocumentController.Document],
        showsSelectionBackground: Bool = false
    ) -> some View {
        let rowState = controller.rowStates[document.id]
            ?? controller.deriveRowState(from: document)

        return ReaderSidebarDocumentRow(
            state: rowState,
            settings: settingsStore.currentSettings,
            documents: allDocuments,
            readerStore: document.readerStore,
            watchedDocumentIDs: watchedDocumentIDs,
            selectedDocumentIDs: selectedDocumentIDs,
            showsSelectionBackground: showsSelectionBackground,
            canClose: true,
            onOpenInDefaultApp: onOpenInDefaultApp,
            onOpenInApplication: { application, documentIDs in
                onOpenInApplication(application, documentIDs)
            },
            onRevealInFinder: onRevealInFinder,
            onStopWatchingFolders: onStopWatchingFolders,
            onClose: onCloseDocuments,
            onCloseOthers: onCloseOtherDocuments,
            onCloseAll: {
                onCloseAllDocuments()
            }
        )
    }
}

private struct SidebarPinnableGroupHeader: View {
    let groupDisplayName: String
    let isExpanded: Bool
    let onToggleExpanded: () -> Void
    let header: ReaderSidebarGroupHeader

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 16, height: 16)
                .background(.quaternary.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .rotationEffect(isExpanded ? .degrees(90) : .zero)

            header
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(isHovering ? Color.primary.opacity(0.06) : Color(nsColor: .labelColor).opacity(0.04))
                )
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onToggleExpanded()
        }
        .onHover { hovering in
            isHovering = hovering
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("sidebar-group-toggle")
        .accessibilityLabel(isExpanded ? "Collapse group" : "Expand group")
        .accessibilityValue(groupDisplayName)
    }
}

// MARK: - Drag-and-drop frame tracking

/// Reference-type cache so GeometryReader updates don't trigger SwiftUI re-renders.
private class GroupFrameCache {
    var frames: [String: CGRect] = [:]
}

/// Reads the group section's global frame into the cache without causing layout loops.
private struct GroupFrameTracker: View {
    let groupID: String
    let cache: GroupFrameCache

    var body: some View {
        GeometryReader { proxy in
            let _ = cache.frames[groupID] = proxy.frame(in: .global)
            Color.clear
        }
        .frame(width: 0, height: 0)
    }
}
