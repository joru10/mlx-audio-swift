import Foundation
import MLXAudioCore

public struct URLToAudioPipeline {
    private let ttsService: TTSService

    public init(ttsService: TTSService) {
        self.ttsService = ttsService
    }

    public func run(
        urlString: String,
        options: TTSOptions,
        outputURL: URL,
        logger: JobLogger
    ) async throws -> JobOutputRefs {
        let extractedText = try await WebTextExtractor.extract(from: urlString)
        let previewText = String(extractedText.prefix(max(options.maxChunkCharacters, 300)))
        let output = try await ttsService.synthesize(text: previewText, options: options)
        try AudioUtils.writeWavFile(samples: output.samples, sampleRate: output.sampleRate, fileURL: outputURL)
        logger.log("URL audio generated for \(urlString)")
        return JobOutputRefs(audioPath: outputURL.path)
    }
}
