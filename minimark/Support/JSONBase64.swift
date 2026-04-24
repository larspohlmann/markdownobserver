import Foundation

enum JSONBase64 {
    static func encode<T: Encodable>(_ value: T) throws -> String {
        try JSONEncoder().encode(value).base64EncodedString()
    }

    // Byte-stable across process launches — use when the output participates
    // in equality / hashing comparisons downstream.
    static func encodeStable<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value).base64EncodedString()
    }
}
