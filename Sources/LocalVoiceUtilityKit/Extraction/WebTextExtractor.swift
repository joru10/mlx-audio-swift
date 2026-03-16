import Foundation

public enum WebTextExtractor {
    public static func extract(from urlString: String) async throws -> String {
        guard let url = URL(string: urlString),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme) else {
            throw NSError(domain: "WebTextExtractor", code: 1, userInfo: [NSLocalizedDescriptionKey: "Only http/https URLs are supported."])
        }

        let (data, _) = try await URLSession.shared.data(from: url)
        guard let html = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "WebTextExtractor", code: 2, userInfo: [NSLocalizedDescriptionKey: "Unable to decode webpage content."])
        }

        return html
            .replacingOccurrences(of: "<script[^>]*>[\\s\\S]*?</script>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "<style[^>]*>[\\s\\S]*?</style>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
