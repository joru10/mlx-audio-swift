import Foundation
import PDFKit

public struct PDFExtractionResult: Sendable {
    public let title: String
    public let pageCount: Int
    public let pages: [String]

    public var fullText: String {
        pages.joined(separator: "\n\n")
    }
}

public enum PDFTextExtractor {
    public static func extract(from url: URL) throws -> PDFExtractionResult {
        guard let document = PDFDocument(url: url) else {
            throw NSError(domain: "PDFTextExtractor", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to open PDF."])
        }

        let pageCount = document.pageCount
        var pages: [String] = []
        pages.reserveCapacity(pageCount)

        for index in 0 ..< pageCount {
            let raw = document.page(at: index)?.string ?? ""
            pages.append(cleanText(raw))
        }

        let title = document.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String
            ?? url.lastPathComponent

        return PDFExtractionResult(title: title, pageCount: pageCount, pages: pages)
    }

    private static func cleanText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: " +", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
