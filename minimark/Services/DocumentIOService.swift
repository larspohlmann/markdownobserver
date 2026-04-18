import Foundation

protocol DocumentIO: AnyObject {
    func load(at accessibleURL: URL) throws -> (markdown: String, modificationDate: Date)
    func write(_ markdown: String, to accessibleURL: URL) throws
    func modificationDate(for url: URL) -> Date
}

final class DocumentIOService: DocumentIO {
    func load(at accessibleURL: URL) throws -> (markdown: String, modificationDate: Date) {
        guard accessibleURL.isFileURL else {
            throw AppError.invalidFileURL
        }

        do {
            let markdown = try String(contentsOf: accessibleURL, encoding: .utf8)
            return (markdown: markdown, modificationDate: modificationDate(for: accessibleURL))
        } catch let error as AppError {
            throw error
        } catch {
            throw AppError.fileReadFailed(accessibleURL, underlying: error)
        }
    }

    func write(_ markdown: String, to accessibleURL: URL) throws {
        guard accessibleURL.isFileURL else {
            throw AppError.invalidFileURL
        }

        do {
            try markdown.write(to: accessibleURL, atomically: true, encoding: .utf8)
        } catch {
            throw AppError.fileWriteFailed(accessibleURL, underlying: error)
        }
    }

    func modificationDate(for url: URL) -> Date {
        let normalizedURL = FileRouting.normalizedFileURL(url)

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
