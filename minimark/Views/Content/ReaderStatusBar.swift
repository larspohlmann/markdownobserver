import SwiftUI

struct ReaderStatusBar: View {
    let activeFolderWatch: ReaderFolderWatchSession?
    let watchIndicatorColor: Color
    let canStopFolderWatch: Bool
    let statusTimestamp: ReaderStatusBarTimestamp?
    let onStopFolderWatch: () -> Void

    private enum Metrics {
        static let horizontalPadding: CGFloat = 10
        static let verticalPadding: CGFloat = 4
        static let sectionSpacing: CGFloat = 8
        static let minimumHeight: CGFloat = 24
        static let separatorHeight: CGFloat = 11
    }

    var body: some View {
        HStack(spacing: Metrics.sectionSpacing) {
            if let activeFolderWatch {
                CompactFolderWatchStatus(
                    activeFolderWatch: activeFolderWatch,
                    watchIndicatorColor: watchIndicatorColor,
                    canStopFolderWatch: canStopFolderWatch,
                    onStopFolderWatch: onStopFolderWatch
                )
                .layoutPriority(1)
            }

            Spacer(minLength: 0)

            if let statusTimestamp {
                CompactDocumentTimestampText(timestamp: statusTimestamp)
                    .layoutPriority(1)
            }
        }
        .padding(.horizontal, Metrics.horizontalPadding)
        .padding(.vertical, Metrics.verticalPadding)
        .frame(minHeight: Metrics.minimumHeight)
        .background {
            Rectangle()
                .fill(Color(nsColor: .windowBackgroundColor))
        }
        .overlay(alignment: .top) {
            Divider()
                .overlay(Color.primary.opacity(0.08))
        }
    }

    private struct CompactFolderWatchStatus: View {
        let activeFolderWatch: ReaderFolderWatchSession
        let watchIndicatorColor: Color
        let canStopFolderWatch: Bool
        let onStopFolderWatch: () -> Void

        @State private var isShowingDetails = false
        @State private var isPulsing = false

        var body: some View {
            HStack(spacing: 6) {
                Circle()
                    .fill(watchIndicatorColor)
                    .frame(width: 6, height: 6)
                    .scaleEffect(isPulsing ? 1.18 : 0.88)
                    .opacity(isPulsing ? 1.0 : 0.58)
                    .animation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true), value: isPulsing)
                    .onAppear {
                        isPulsing = true
                    }
                    .accessibilityHidden(true)

                Button {
                    isShowingDetails = true
                } label: {
                    HStack(spacing: 4) {
                        Text(activeFolderWatch.titleLabel)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Image(systemName: "info.circle")
                            .font(.system(size: 10, weight: .regular))
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $isShowingDetails, arrowEdge: .bottom) {
                    FolderWatchDetailsPopover(activeFolderWatch: activeFolderWatch)
                }
                .help(activeFolderWatch.tooltipText)
                .accessibilityLabel("Folder watch details")
                .accessibilityValue(activeFolderWatch.accessibilityValue)
                .accessibilityHint("Shows details about the watched folder")

                CompactStatusSeparator()

                Button(action: onStopFolderWatch) {
                    stopButtonIcon
                }
                .buttonStyle(.plain)
                .disabled(!canStopFolderWatch)
                .accessibilityLabel("Stop watching folder")
                .accessibilityHint("Stops monitoring the current folder")
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .accessibilityElement(children: .contain)
        }

        private var stopButtonIcon: some View {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(canStopFolderWatch ? .secondary : .tertiary)
                .frame(width: 14, height: 14)
                .contentShape(Rectangle())
        }
    }

    private struct CompactDocumentTimestampText: View {
        let timestamp: ReaderStatusBarTimestamp

        var body: some View {
            TimelineView(.periodic(from: .now, by: 20)) { context in
                Text("\(label) \(relativeText(relativeTo: context.date))")
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .accessibilityLabel(label)
                    .accessibilityValue(relativeText(relativeTo: context.date))
            }
        }

        private var label: String {
            switch timestamp {
            case .updated:
                return "Updated"
            case .lastModified:
                return "Last modified"
            }
        }

        private func relativeText(relativeTo date: Date) -> String {
            switch timestamp {
            case let .updated(changedAt):
                return ReaderStatusFormatting.relativeText(for: changedAt, relativeTo: date)
            case let .lastModified(modifiedAt):
                return ReaderStatusFormatting.relativeText(for: modifiedAt, relativeTo: date)
            }
        }
    }

    private struct CompactStatusSeparator: View {
        var body: some View {
            Rectangle()
                .fill(Color.primary.opacity(0.12))
                .frame(width: 1, height: Metrics.separatorHeight)
                .accessibilityHidden(true)
        }
    }
}