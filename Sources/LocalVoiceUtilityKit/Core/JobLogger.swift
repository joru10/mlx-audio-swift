import Foundation
import OSLog

public final class JobLogger: @unchecked Sendable {
    private let logger = Logger(subsystem: "LocalVoiceUtility", category: "Jobs")
    private let logURL: URL

    public init(logURL: URL) {
        self.logURL = logURL
    }

    public func log(_ message: String) {
        logger.info("\(message, privacy: .public)")
        let line = "[\(ISO8601DateFormatter().string(from: Date()))] \(message)\n"
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logURL.path) {
                if let handle = try? FileHandle(forWritingTo: logURL) {
                    defer { try? handle.close() }
                    do {
                        try handle.seekToEnd()
                        try handle.write(contentsOf: data)
                    } catch {
                        logger.error("Failed to append log: \(error.localizedDescription, privacy: .public)")
                    }
                }
            } else {
                try? data.write(to: logURL, options: .atomic)
            }
        }
    }
}
