import Foundation

/// Typed representation of the accessibility value carried by the reader
/// preview surface. Producer and consumer both round-trip through this shared
/// type, making it the single source of truth for the payload format.
struct PreviewAccessibilitySummary: Equatable, CustomStringConvertible {
    enum Surface: String {
        case preview
    }

    let fileName: String
    let regionCount: Int
    let mode: DocumentViewMode
    let surface: Surface

    init(
        fileName: String,
        regionCount: Int,
        mode: DocumentViewMode,
        surface: Surface = .preview
    ) {
        self.fileName = fileName
        self.regionCount = regionCount
        self.mode = mode
        self.surface = surface
    }

    var description: String {
        "file=\(fileName)|regions=\(regionCount)|mode=\(mode.rawValue)|surface=\(surface.rawValue)"
    }

    init?(rawValue: String) {
        var fields: [String: String] = [:]
        for component in rawValue.split(separator: "|", omittingEmptySubsequences: false) {
            guard let equalsIndex = component.firstIndex(of: "=") else { return nil }
            let key = String(component[..<equalsIndex])
            let value = String(component[component.index(after: equalsIndex)...])
            fields[key] = value
        }

        guard
            let fileName = fields["file"],
            let regionsRaw = fields["regions"],
            let regionCount = Int(regionsRaw),
            let modeRaw = fields["mode"],
            let mode = DocumentViewMode(rawValue: modeRaw),
            let surfaceRaw = fields["surface"],
            let surface = Surface(rawValue: surfaceRaw)
        else {
            return nil
        }

        self.init(fileName: fileName, regionCount: regionCount, mode: mode, surface: surface)
    }
}
