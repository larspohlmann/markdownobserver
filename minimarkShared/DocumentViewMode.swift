import Foundation

enum DocumentViewMode: String, CaseIterable, Sendable {
    case preview
    case split
    case source

    var displayName: String {
        switch self {
        case .preview:
            return "Preview"
        case .split:
            return "Split"
        case .source:
            return "Source"
        }
    }

    var systemImageName: String {
        switch self {
        case .preview:
            return "doc.richtext"
        case .split:
            return "rectangle.split.2x1"
        case .source:
            return "text.alignleft"
        }
    }

    var next: DocumentViewMode {
        switch self {
        case .preview:
            return .split
        case .split:
            return .source
        case .source:
            return .preview
        }
    }

    var accessibilityIdentifier: AccessibilityID {
        switch self {
        case .preview:
            return .viewModePreviewButton
        case .split:
            return .viewModeSplitButton
        case .source:
            return .viewModeSourceButton
        }
    }
}
