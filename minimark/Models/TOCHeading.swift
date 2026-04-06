// minimark/Models/TOCHeading.swift
import Foundation

struct TOCHeading: Equatable, Sendable {
    let elementID: String
    let level: Int
    let title: String
    let sourceLine: Int?

    static func fromJavaScriptPayload(_ payload: [[String: Any]]) -> [TOCHeading] {
        payload.compactMap { entry in
            guard let elementID = entry["id"] as? String,
                  let level = entry["level"] as? Int,
                  let title = entry["title"] as? String else {
                return nil
            }
            let sourceLine = entry["sourceLine"] as? Int
            return TOCHeading(elementID: elementID, level: level, title: title, sourceLine: sourceLine)
        }
    }
}

extension TOCHeading: Identifiable {
    var id: String {
        "\(elementID)-\(level)-\(sourceLine ?? 0)"
    }
}
