import Foundation

public struct ScaleCaptureRecord: Codable, Identifiable, Sendable {
    public var id: UUID
    public var createdAt: Date
    public var sourceURL: String
    public var title: String
    public var notes: String?
    public var statusCode: Int
    public var contentType: String
    public var byteCount: Int
    public var rawPayloadPath: String
    public var metadataPath: String

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        sourceURL: String,
        title: String,
        notes: String? = nil,
        statusCode: Int,
        contentType: String,
        byteCount: Int,
        rawPayloadPath: String,
        metadataPath: String
    ) {
        self.id = id
        self.createdAt = createdAt
        self.sourceURL = sourceURL
        self.title = title
        self.notes = notes
        self.statusCode = statusCode
        self.contentType = contentType
        self.byteCount = byteCount
        self.rawPayloadPath = rawPayloadPath
        self.metadataPath = metadataPath
    }
}

public struct ScaleCaptureMetadata: Codable, Sendable {
    public var id: UUID
    public var capturedAt: Date
    public var sourceURL: String
    public var title: String
    public var notes: String?
    public var statusCode: Int
    public var contentType: String
    public var byteCount: Int
    public var responseHeaders: [String: String]
    public var payloadPath: String
}
