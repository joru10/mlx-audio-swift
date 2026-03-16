import Foundation

public struct FileTranscriptionPipeline {
    private let sttService: STTService

    public init(sttService: STTService) {
        self.sttService = sttService
    }

    public func run(
        inputURL: URL,
        options: STTOptions,
        textOutputURL: URL,
        jsonOutputURL: URL?,
        tempDirectory: URL,
        progress: @escaping (Double) async -> Void,
        logger: JobLogger
    ) async throws -> JobOutputRefs {
        logger.log("Preparing media input: \(inputURL.path)")
        let audioURL = try await MediaExtractor.normalizeToAudioFile(inputURL: inputURL, outputDirectory: tempDirectory)
        await progress(0.2)

        logger.log("Running STT with model \(options.modelId)")
        let transcript = try await sttService.transcribe(audioURL: audioURL, options: options)
        await progress(0.8)

        try transcript.fullText.write(to: textOutputURL, atomically: true, encoding: .utf8)
        logger.log("Wrote transcript: \(textOutputURL.path)")

        var jsonPath: String?
        if let jsonOutputURL {
            let data = try JSONEncoder.localVoice.encode(transcript)
            try data.write(to: jsonOutputURL, options: .atomic)
            logger.log("Wrote transcript JSON: \(jsonOutputURL.path)")
            jsonPath = jsonOutputURL.path
        }

        await progress(1.0)
        return JobOutputRefs(audioPath: audioURL.path == inputURL.path ? nil : audioURL.path, transcriptPath: textOutputURL.path, jsonPath: jsonPath)
    }
}
