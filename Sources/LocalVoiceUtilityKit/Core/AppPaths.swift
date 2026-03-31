import Foundation

public struct AppPaths: Sendable {
    public static let appName = "LocalVoiceUtility"

    public let appSupportRoot: URL
    public let jobsDirectory: URL
    public let outputsDirectory: URL
    public let modelsDirectory: URL
    public let logsDirectory: URL
    public let scaleReadingsDirectory: URL

    public init(fileManager: FileManager = .default) throws {
        let appSupportBase = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        appSupportRoot = appSupportBase.appendingPathComponent(Self.appName, isDirectory: true)
        jobsDirectory = appSupportRoot.appendingPathComponent("jobs", isDirectory: true)
        outputsDirectory = appSupportRoot.appendingPathComponent("outputs", isDirectory: true)
        modelsDirectory = appSupportRoot.appendingPathComponent("models", isDirectory: true)
        logsDirectory = appSupportRoot.appendingPathComponent("logs", isDirectory: true)
        scaleReadingsDirectory = appSupportRoot.appendingPathComponent("scale-readings", isDirectory: true)

        try [appSupportRoot, jobsDirectory, outputsDirectory, modelsDirectory, logsDirectory, scaleReadingsDirectory].forEach {
            try fileManager.createDirectory(at: $0, withIntermediateDirectories: true)
        }
    }

    public var jobsIndexURL: URL {
        jobsDirectory.appendingPathComponent("jobs.json")
    }

    public var modelsIndexURL: URL {
        modelsDirectory.appendingPathComponent("models.json")
    }

    public var settingsURL: URL {
        appSupportRoot.appendingPathComponent("settings.json")
    }

    public var scaleCapturesIndexURL: URL {
        scaleReadingsDirectory.appendingPathComponent("captures.json")
    }
}
