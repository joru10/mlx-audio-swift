import AVFoundation
import Foundation

public enum MediaExtractor {
    public static func normalizeToAudioFile(inputURL: URL, outputDirectory: URL) async throws -> URL {
        let ext = inputURL.pathExtension.lowercased()
        if ["mp4", "mov"].contains(ext) {
            let outputURL = outputDirectory.appendingPathComponent("\(inputURL.deletingPathExtension().lastPathComponent)-audio.m4a")
            try await extractAudioTrack(from: inputURL, to: outputURL)
            return outputURL
        }
        if ["ogg", "opus", "vorbis"].contains(ext) {
            let outputURL = outputDirectory.appendingPathComponent("\(inputURL.deletingPathExtension().lastPathComponent)-normalized.wav")
            try convertWithFFmpeg(inputURL: inputURL, outputURL: outputURL)
            return outputURL
        }
        return inputURL
    }

    private static func extractAudioTrack(from inputURL: URL, to outputURL: URL) async throws {
        let asset = AVAsset(url: inputURL)
        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw NSError(domain: "MediaExtractor", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not create export session."])
        }

        try? FileManager.default.removeItem(at: outputURL)
        export.outputURL = outputURL
        export.outputFileType = .m4a

        try await withCheckedThrowingContinuation { continuation in
            export.exportAsynchronously {
                switch export.status {
                case .completed:
                    continuation.resume(returning: ())
                case .failed, .cancelled:
                    continuation.resume(throwing: export.error ?? NSError(domain: "MediaExtractor", code: 3))
                default:
                    continuation.resume(throwing: NSError(domain: "MediaExtractor", code: 4))
                }
            }
        }
    }

    private static func convertWithFFmpeg(inputURL: URL, outputURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "ffmpeg",
            "-y",
            "-i", inputURL.path,
            "-vn",
            "-ac", "1",
            "-ar", "16000",
            outputURL.path,
        ]
        let stderr = Pipe()
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let detail = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            throw NSError(
                domain: "MediaExtractor",
                code: 5,
                userInfo: [NSLocalizedDescriptionKey: detail.isEmpty ? "ffmpeg failed to convert \(inputURL.lastPathComponent)." : detail]
            )
        }
    }
}
