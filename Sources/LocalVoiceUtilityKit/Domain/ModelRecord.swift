import Foundation

public enum ModelType: String, Codable, CaseIterable, Sendable {
    case tts
    case stt
    case vad
    case other
}

public struct ModelRecord: Identifiable, Codable, Sendable {
    public var id: String
    public var type: ModelType
    public var localPath: String
    public var sizeBytes: Int64
    public var installedAt: Date

    public init(id: String, type: ModelType, localPath: String, sizeBytes: Int64 = 0, installedAt: Date = Date()) {
        self.id = id
        self.type = type
        self.localPath = localPath
        self.sizeBytes = sizeBytes
        self.installedAt = installedAt
    }
}
