import Foundation

struct TOCHeading: Equatable, Sendable {
    let elementID: String
    let level: Int
    let title: String
    let sourceLine: Int?
    let index: Int

    static func fromJavaScriptPayload(_ payload: [[String: Any]]) -> [TOCHeading] {
        var result: [TOCHeading] = []
        for (index, entry) in payload.enumerated() {
            guard let elementID = entry["id"] as? String,
                  let level = entry["level"] as? Int,
                  let title = entry["title"] as? String else {
                continue
            }
            let sourceLine = entry["sourceLine"] as? Int
            result.append(TOCHeading(elementID: elementID, level: level, title: title, sourceLine: sourceLine, index: index))
        }
        return result
    }
}

extension TOCHeading: Identifiable {
    var id: Int { index }
}

struct TOCScrollRequest: Equatable {
    let heading: TOCHeading
    let requestID: Int
}
