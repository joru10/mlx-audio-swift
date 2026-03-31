import Foundation

public actor ScaleCaptureStore {
    private let paths: AppPaths
    private let session: URLSession

    public init(paths: AppPaths, session: URLSession = .shared) {
        self.paths = paths
        self.session = session
    }

    public func loadCaptures() throws -> [ScaleCaptureRecord] {
        try JSONStore.load([ScaleCaptureRecord].self, from: paths.scaleCapturesIndexURL, defaultValue: [])
            .sorted { $0.createdAt > $1.createdAt }
    }

    public func captureReading(from urlString: String, title: String?, notes: String?) async throws -> ScaleCaptureRecord {
        let trimmedURL = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmedURL), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) else {
            throw NSError(domain: "ScaleCapture", code: 1, userInfo: [NSLocalizedDescriptionKey: "Enter a valid http or https URL."])
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 30

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "ScaleCapture", code: 2, userInfo: [NSLocalizedDescriptionKey: "Expected an HTTP response."])
        }
        guard (200 ... 299).contains(httpResponse.statusCode) else {
            throw NSError(
                domain: "ScaleCapture",
                code: httpResponse.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "Request failed with status \(httpResponse.statusCode)."]
            )
        }

        let id = UUID()
        let createdAt = Date()
        let resolvedTitle = normalizedTitle(title, fallbackURL: url)
        let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "application/octet-stream"
        let payloadExtension = payloadFileExtension(for: contentType, url: url)
        let fileStem = fileSafeStem(for: resolvedTitle.isEmpty ? url.lastPathComponent : resolvedTitle)
        let rawPayloadURL = paths.scaleReadingsDirectory.appendingPathComponent("\(timestamp(createdAt))-\(fileStem)-\(id.uuidString).\(payloadExtension)")
        let metadataURL = paths.scaleReadingsDirectory.appendingPathComponent("\(timestamp(createdAt))-\(fileStem)-\(id.uuidString).json")

        try data.write(to: rawPayloadURL, options: .atomic)

        let metadata = ScaleCaptureMetadata(
            id: id,
            capturedAt: createdAt,
            sourceURL: trimmedURL,
            title: resolvedTitle,
            notes: cleanedNotes(notes),
            statusCode: httpResponse.statusCode,
            contentType: contentType,
            byteCount: data.count,
            responseHeaders: httpResponse.allHeaderFields.reduce(into: [:]) { result, element in
                result[String(describing: element.key)] = String(describing: element.value)
            },
            payloadPath: rawPayloadURL.path
        )
        try JSONStore.save(metadata, to: metadataURL)

        let record = ScaleCaptureRecord(
            id: id,
            createdAt: createdAt,
            sourceURL: trimmedURL,
            title: resolvedTitle,
            notes: cleanedNotes(notes),
            statusCode: httpResponse.statusCode,
            contentType: contentType,
            byteCount: data.count,
            rawPayloadPath: rawPayloadURL.path,
            metadataPath: metadataURL.path
        )

        var captures = try loadCaptures()
        captures.insert(record, at: 0)
        try JSONStore.save(captures, to: paths.scaleCapturesIndexURL)

        return record
    }

    public func preview(for record: ScaleCaptureRecord, limit: Int = 4_000) -> String {
        let url = URL(fileURLWithPath: record.rawPayloadPath)
        guard let data = try? Data(contentsOf: url) else {
            return "Could not read saved payload."
        }
        if let text = String(data: data, encoding: .utf8) {
            return String(text.prefix(limit))
        }
        if let text = String(data: data, encoding: .ascii) {
            return String(text.prefix(limit))
        }
        return "Saved \(record.byteCount) bytes of non-text payload (\(record.contentType))."
    }

    private func normalizedTitle(_ title: String?, fallbackURL: URL) -> String {
        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty {
            return trimmed
        }
        if !fallbackURL.lastPathComponent.isEmpty {
            return fallbackURL.lastPathComponent
        }
        return fallbackURL.host ?? "scale-reading"
    }

    private func cleanedNotes(_ notes: String?) -> String? {
        let trimmed = notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func payloadFileExtension(for contentType: String, url: URL) -> String {
        let normalized = contentType.lowercased()
        if normalized.contains("json") { return "json" }
        if normalized.contains("html") { return "html" }
        if normalized.contains("xml") { return "xml" }
        if normalized.contains("csv") { return "csv" }
        if normalized.contains("plain") { return "txt" }
        let pathExtension = url.pathExtension.lowercased()
        return pathExtension.isEmpty ? "bin" : pathExtension
    }

    private func fileSafeStem(for title: String) -> String {
        let cleaned = title
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return cleaned.isEmpty ? "scale-reading" : cleaned
    }

    private func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }
}
