import AppKit
import SwiftUI

struct ContentUtilityRail: View {
    let hasFile: Bool
    let documentViewMode: ReaderDocumentViewMode
    let showEditButton: Bool
    let canStartSourceEditing: Bool
    let onSetDocumentViewMode: (ReaderDocumentViewMode) -> Void
    let onStartSourceEditing: () -> Void
    let hasTOCHeadings: Bool
    let isTOCVisible: Binding<Bool>

    @State private var isHovering = false
    @Namespace private var viewModeNamespace

    private enum Metrics {
        static let railWidth: CGFloat = 44
        static let buttonSize: CGFloat = 32
        static let buttonCornerRadius: CGFloat = 8
        static let iconSize: CGFloat = 12
        static let groupSpacing: CGFloat = 8
        static let railCornerRadius: CGFloat = 12
        static let railInset: CGFloat = 8
        static let railTrailingInset: CGFloat = 18
        static let separatorWidth: CGFloat = 20
    }

    var body: some View {
        if hasFile {
            VStack(spacing: Metrics.groupSpacing) {
                viewModeGroup

                if showEditButton {
                    groupSeparator
                    editGroup
                }

                if hasTOCHeadings && documentViewMode == .preview {
                    groupSeparator
                    tocGroup
                }
            }
            .padding(.vertical, Metrics.groupSpacing)
            .frame(width: Metrics.railWidth)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Metrics.railCornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Metrics.railCornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(isHovering ? 0.16 : 0.08), lineWidth: 1)
            }
            .shadow(color: .black.opacity(isHovering ? 0.25 : 0.12), radius: isHovering ? 16 : 6, y: 2)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.25)) {
                    isHovering = hovering
                }
            }
            .padding(.top, Metrics.railInset)
            .padding(.trailing, Metrics.railTrailingInset)
        }
    }

    // MARK: - View Mode Group

    private var viewModeGroup: some View {
        VStack(spacing: 6) {
            ForEach(ReaderDocumentViewMode.allCases, id: \.self) { mode in
                viewModeButton(mode: mode)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: documentViewMode)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Document view mode")
        .accessibilityHint("Switch between preview, split, and source views of the document.")
    }

    private func viewModeButton(mode: ReaderDocumentViewMode) -> some View {
        let isSelected = documentViewMode == mode

        return Button {
            onSetDocumentViewMode(mode)
        } label: {
            Image(systemName: mode.systemImageName)
                .font(.system(size: Metrics.iconSize, weight: isSelected ? .bold : .semibold))
                .frame(width: Metrics.buttonSize, height: Metrics.buttonSize)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: Metrics.buttonCornerRadius, style: .continuous)
                            .fill(Color.primary.opacity(0.12))
                            .overlay(
                                RoundedRectangle(cornerRadius: Metrics.buttonCornerRadius, style: .continuous)
                                    .strokeBorder(Color.primary.opacity(0.18), lineWidth: 1)
                            )
                            .matchedGeometryEffect(id: "viewModeIndicator", in: viewModeNamespace)
                    }
                }
                .railButtonBackground(cornerRadius: Metrics.buttonCornerRadius,
                    fill: Color.clear,
                    border: Color.clear,
                    hoverFill: isSelected ? nil : Color.primary.opacity(0.06),
                    hoverBorder: isSelected ? nil : Color.primary.opacity(0.08)
                )
        }
        .buttonStyle(.plain)
        .disabled(!hasFile || isSelected)
        .foregroundStyle(isSelected ? .primary : (hasFile ? .secondary : .tertiary))
        .help(mode.displayName)
        .accessibilityLabel(mode.displayName)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }

    // MARK: - Edit Group

    private var editGroup: some View {
        Button {
            onStartSourceEditing()
        } label: {
            Image(systemName: "pencil")
                .font(.system(size: Metrics.iconSize, weight: .semibold))
                .frame(width: Metrics.buttonSize, height: Metrics.buttonSize)
                .railButtonBackground(cornerRadius: Metrics.buttonCornerRadius,
                    fill: Color.primary.opacity(canStartSourceEditing ? 0.06 : 0.03),
                    border: Color.primary.opacity(canStartSourceEditing ? 0.10 : 0.05),
                    hoverFill: canStartSourceEditing ? Color.primary.opacity(0.10) : nil,
                    hoverBorder: canStartSourceEditing ? Color.primary.opacity(0.14) : nil
                )
        }
        .buttonStyle(.plain)
        .disabled(!canStartSourceEditing)
        .foregroundStyle(canStartSourceEditing ? .primary : .tertiary)
        .help("Edit Source (⌘E)")
        .accessibilityLabel("Edit source")
    }

    // MARK: - TOC Group

    private var tocGroup: some View {
        let isActive = isTOCVisible.wrappedValue

        return Button {
            isTOCVisible.wrappedValue.toggle()
        } label: {
            Image(systemName: "list.bullet.indent")
                .font(.system(size: Metrics.iconSize, weight: isActive ? .bold : .semibold))
                .frame(width: Metrics.buttonSize, height: Metrics.buttonSize)
                .background {
                    if isActive {
                        RoundedRectangle(cornerRadius: Metrics.buttonCornerRadius, style: .continuous)
                            .fill(Color.primary.opacity(0.12))
                            .overlay(
                                RoundedRectangle(cornerRadius: Metrics.buttonCornerRadius, style: .continuous)
                                    .strokeBorder(Color.primary.opacity(0.18), lineWidth: 1)
                            )
                    }
                }
                .railButtonBackground(cornerRadius: Metrics.buttonCornerRadius,
                    fill: Color.clear,
                    border: Color.clear,
                    hoverFill: isActive ? nil : Color.primary.opacity(0.06),
                    hoverBorder: isActive ? nil : Color.primary.opacity(0.08)
                )
        }
        .buttonStyle(.plain)
        .foregroundStyle(isActive ? .primary : .secondary)
        .help("Table of Contents (⇧⌘T)")
        .accessibilityIdentifier(.tocButton)
        .accessibilityLabel("Table of Contents")
        .accessibilityValue(isTOCVisible.wrappedValue ? "Visible" : "Hidden")
        .anchorPreference(key: TOCButtonAnchorKey.self, value: .bounds) { $0 }
    }

    // MARK: - Separator

    private var groupSeparator: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.10))
            .frame(width: Metrics.separatorWidth, height: 1)
            .padding(.vertical, 4)
    }
}

// MARK: - TOC Button Anchor

struct TOCButtonAnchorKey: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

// MARK: - Rail Button Background

private struct RailButtonBackgroundModifier: ViewModifier {
    let fill: Color
    let hoverFill: Color
    let border: Color
    let hoverBorder: Color
    let cornerRadius: CGFloat

    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(isHovered ? hoverFill : fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(isHovered ? hoverBorder : border, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.12)) {
                    isHovered = hovering
                }
            }
    }
}

private extension View {
    func railButtonBackground(
        cornerRadius: CGFloat,
        fill: Color,
        border: Color,
        hoverFill: Color? = nil,
        hoverBorder: Color? = nil
    ) -> some View {
        modifier(RailButtonBackgroundModifier(
            fill: fill,
            hoverFill: hoverFill ?? fill,
            border: border,
            hoverBorder: hoverBorder ?? border,
            cornerRadius: cornerRadius
        ))
    }
}
