import Foundation

enum JSONBase64 {
    // JSONEncoder is safe to share across threads as long as mutable state
    // (outputFormatting, userInfo, dateEncodingStrategy, …) is not changed
    // after configuration. Two encoders so neither caller has to touch state.
    private static let defaultEncoder = JSONEncoder()
    private static let stableEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    static func encode<T: Encodable>(_ value: T) throws -> String {
        try defaultEncoder.encode(value).base64EncodedString()
    }

    // Byte-stable across process launches — use when the output participates
    // in equality / hashing comparisons downstream.
    static func encodeStable<T: Encodable>(_ value: T) throws -> String {
        try stableEncoder.encode(value).base64EncodedString()
    }
}
