import Foundation

public enum JobType: String, Codable, CaseIterable, Sendable {
    case pdfToAudio
    case urlToAudio
    case transcribeFile
    case liveSession
}

public enum JobStatus: String, Codable, CaseIterable, Sendable {
    case queued
    case running
    case completed
    case failed
    case canceled
}

public struct JobOutputRefs: Codable, Sendable {
    public var audioPath: String?
    public var transcriptPath: String?
    public var jsonPath: String?

    public init(audioPath: String? = nil, transcriptPath: String? = nil, jsonPath: String? = nil) {
        self.audioPath = audioPath
        self.transcriptPath = transcriptPath
        self.jsonPath = jsonPath
    }
}

public struct JobRecord: Identifiable, Codable, Sendable {
    public var id: UUID
    public var type: JobType
    public var status: JobStatus
    public var createdAt: Date
    public var startedAt: Date?
    public var finishedAt: Date?
    public var inputRef: String
    public var outputRefs: JobOutputRefs
    public var optionsJSON: String
    public var progress: Double
    public var errorMessage: String?
    public var logPath: String

    public init(
        id: UUID = UUID(),
        type: JobType,
        status: JobStatus = .queued,
        createdAt: Date = Date(),
        startedAt: Date? = nil,
        finishedAt: Date? = nil,
        inputRef: String,
        outputRefs: JobOutputRefs = JobOutputRefs(),
        optionsJSON: String = "{}",
        progress: Double = 0,
        errorMessage: String? = nil,
        logPath: String
    ) {
        self.id = id
        self.type = type
        self.status = status
        self.createdAt = createdAt
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.inputRef = inputRef
        self.outputRefs = outputRefs
        self.optionsJSON = optionsJSON
        self.progress = progress
        self.errorMessage = errorMessage
        self.logPath = logPath
    }
}
