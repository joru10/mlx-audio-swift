import Foundation
import MLXAudioCore

public struct PDFToAudioPipeline {
    private let ttsService: TTSService

    public init(ttsService: TTSService) {
        self.ttsService = ttsService
    }

    public func run(
        inputURL: URL,
        options: TTSOptions,
        outputURL: URL,
        progress: @escaping (Double) async -> Void,
        logger: JobLogger
    ) async throws -> JobOutputRefs {
        logger.log("Extracting text from PDF: \(inputURL.path)")
        let extracted = try PDFTextExtractor.extract(from: inputURL)

        let chunks = buildChunks(from: extracted, options: options)
        if chunks.isEmpty {
            throw NSError(
                domain: "PDFToAudioPipeline",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "No text extracted from PDF (scanned PDF may require OCR)."]
            )
        }

        logger.log("Synthesizing \(chunks.count) chunks with model \(options.modelId)")
        var allSamples: [Float] = []
        var sampleRate: Double = 24_000

        for (index, chunk) in chunks.enumerated() {
            let result = try await ttsService.synthesize(text: chunk, options: options)
            sampleRate = result.sampleRate
            allSamples.append(contentsOf: result.samples)
            await progress(Double(index + 1) / Double(chunks.count))
        }

        try AudioUtils.writeWavFile(samples: allSamples, sampleRate: sampleRate, fileURL: outputURL)
        logger.log("Wrote wav output: \(outputURL.path)")

        return JobOutputRefs(audioPath: outputURL.path)
    }

    private func buildChunks(from extracted: PDFExtractionResult, options: TTSOptions) -> [String] {
        let sourceText: [String]
        switch options.chunkMode {
        case .paragraph:
            sourceText = [extracted.fullText]
        case .perPage:
            sourceText = extracted.pages
        }

        var chunks: [String] = []
        for unit in sourceText {
            let paragraphs = unit
                .split(separator: "\n")
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            var current = ""
            for paragraph in paragraphs {
                if current.count + paragraph.count + 1 > options.maxChunkCharacters, !current.isEmpty {
                    chunks.append(current)
                    current = paragraph
                } else {
                    current = current.isEmpty ? paragraph : "\(current) \(paragraph)"
                }
            }
            if !current.isEmpty {
                chunks.append(current)
            }
        }

        return chunks
    }
}
