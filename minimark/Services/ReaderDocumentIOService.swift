import Foundation

protocol ReaderDocumentIO: AnyObject {
    func load(at accessibleURL: URL) throws -> (markdown: String, modificationDate: Date)
    func write(_ markdown: String, to accessibleURL: URL) throws
    func modificationDate(for url: URL) -> Date
}

final class ReaderDocumentIOService: ReaderDocumentIO {
    func load(at accessibleURL: URL) throws -> (markdown: String, modificationDate: Date) {
        guard accessibleURL.isFileURL else {
            throw ReaderError.invalidFileURL
        }

        do {
            let markdown = try String(contentsOf: accessibleURL, encoding: .utf8)
            return (markdown: markdown, modificationDate: modificationDate(for: accessibleURL))
        } catch let error as ReaderError {
            throw error
        } catch {
            throw ReaderError.fileReadFailed(accessibleURL, underlying: error)
        }
    }

    func write(_ markdown: String, to accessibleURL: URL) throws {
        guard accessibleURL.isFileURL else {
            throw ReaderError.invalidFileURL
        }

        do {
            try markdown.write(to: accessibleURL, atomically: true, encoding: .utf8)
        } catch {
            throw ReaderError.fileWriteFailed(accessibleURL, underlying: error)
        }
    }

    func modificationDate(for url: URL) -> Date {
        let normalizedURL = ReaderFileRouting.normalizedFileURL(url)

        if let attributes = try? FileManager.default.attributesOfItem(atPath: normalizedURL.path),
           let modificationDate = attributes[.modificationDate] as? Date {
            return modificationDate
        }

        if let values = try? normalizedURL.resourceValues(forKeys: [.contentModificationDateKey]),
           let modificationDate = values.contentModificationDate {
            return modificationDate
        }

        return .distantPast
    }
}
