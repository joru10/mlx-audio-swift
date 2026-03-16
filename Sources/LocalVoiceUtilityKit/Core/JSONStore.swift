import Foundation

public enum JSONStore {
    public static func load<T: Decodable>(_ type: T.Type, from url: URL, defaultValue: @autoclosure () -> T) throws -> T {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else {
            return defaultValue()
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder.localVoice.decode(type, from: data)
    }

    public static func save<T: Encodable>(_ value: T, to url: URL) throws {
        let data = try JSONEncoder.localVoice.encode(value)
        try data.write(to: url, options: .atomic)
    }
}

public extension JSONEncoder {
    static var localVoice: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

public extension JSONDecoder {
    static var localVoice: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
