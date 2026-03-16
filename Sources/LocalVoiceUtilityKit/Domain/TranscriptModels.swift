import Foundation

public struct TranscriptSegment: Codable, Sendable {
    public var startSec: Double
    public var endSec: Double
    public var speaker: String?
    public var text: String

    public init(startSec: Double, endSec: Double, speaker: String? = nil, text: String) {
        self.startSec = startSec
        self.endSec = endSec
        self.speaker = speaker
        self.text = text
    }
}

public struct TranscriptDocument: Codable, Sendable {
    public struct Source: Codable, Sendable {
        public var path: String
        public var type: String

        public init(path: String, type: String) {
            self.path = path
            self.type = type
        }
    }

    public struct Model: Codable, Sendable {
        public var id: String

        public init(id: String) {
            self.id = id
        }
    }

    public var source: Source
    public var model: Model
    public var createdAt: Date
    public var fullText: String
    public var segments: [TranscriptSegment]

    public init(source: Source, model: Model, createdAt: Date = Date(), fullText: String, segments: [TranscriptSegment]) {
        self.source = source
        self.model = model
        self.createdAt = createdAt
        self.fullText = fullText
        self.segments = segments
    }
}
