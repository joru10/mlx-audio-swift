import Foundation
import CoreGraphics

public enum VLMKVQuantizationScheme: String, Codable, CaseIterable, Sendable {
    case uniform
    case turboquant
}

public enum SamTaskMode: String, Codable, CaseIterable, Sendable {
    case detect
    case segment

    public var displayName: String {
        switch self {
        case .detect: return "Detect"
        case .segment: return "Segment"
        }
    }
}

public enum VisualAnalysisWorkflow: String, Codable, CaseIterable, Sendable {
    case general
    case ocrPlainText
    case ocrStructured
    case ocrReceipt
    case ocrForm
    case ocrTable
    case screenSummary

    public var displayName: String {
        switch self {
        case .general: return "General"
        case .ocrPlainText: return "OCR Plain Text"
        case .ocrStructured: return "OCR Structured"
        case .ocrReceipt: return "Receipt OCR"
        case .ocrForm: return "Form OCR"
        case .ocrTable: return "Table OCR"
        case .screenSummary: return "Screen Summary"
        }
    }

    public var defaultPrompt: String {
        switch self {
        case .general:
            return "Describe this image in detail."
        case .ocrPlainText:
            return "Extract the visible text exactly as written. Preserve paragraphs and line breaks where possible."
        case .ocrStructured:
            return "Extract the visible text and return a structured summary with headings, key fields, tables, and notable values."
        case .ocrReceipt:
            return "Extract this receipt into merchant, date, line items, subtotal, taxes, total, payment method, and any loyalty or invoice identifiers."
        case .ocrForm:
            return "Extract this form into field names and values, keeping sections, checkbox states, signatures, dates, and any missing fields."
        case .ocrTable:
            return "Extract the table structure with headers, rows, totals, and any footnotes. Keep the row and column meaning explicit."
        case .screenSummary:
            return "Summarize what is on this screen, the main UI sections, important text, and the likely next actions for the user."
        }
    }
}

public struct VisualAnalysisOptions: Codable, Sendable {
    public var modelId: String
    public var workflow: VisualAnalysisWorkflow
    public var prompt: String
    public var maxTokens: Int
    public var audioInputPath: String?
    public var kvBits: Double?
    public var kvQuantScheme: VLMKVQuantizationScheme
    public var processAllPDFPages: Bool
    public var pythonRepoPath: String

    public init(
        modelId: String = "mlx-community/Qwen2-VL-2B-Instruct-4bit",
        workflow: VisualAnalysisWorkflow = .general,
        prompt: String = VisualAnalysisWorkflow.general.defaultPrompt,
        maxTokens: Int = 300,
        audioInputPath: String? = nil,
        kvBits: Double? = nil,
        kvQuantScheme: VLMKVQuantizationScheme = .uniform,
        processAllPDFPages: Bool = false,
        pythonRepoPath: String = PythonMLXVLMBridge.defaultRepoPath
    ) {
        self.modelId = modelId
        self.workflow = workflow
        self.prompt = prompt
        self.maxTokens = maxTokens
        self.audioInputPath = audioInputPath
        self.kvBits = kvBits
        self.kvQuantScheme = kvQuantScheme
        self.processAllPDFPages = processAllPDFPages
        self.pythonRepoPath = pythonRepoPath
    }

    private enum CodingKeys: String, CodingKey {
        case modelId
        case workflow
        case prompt
        case maxTokens
        case audioInputPath
        case kvBits
        case kvQuantScheme
        case processAllPDFPages
        case pythonRepoPath
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        modelId = try container.decodeIfPresent(String.self, forKey: .modelId) ?? "mlx-community/Qwen2-VL-2B-Instruct-4bit"
        workflow = try container.decodeIfPresent(VisualAnalysisWorkflow.self, forKey: .workflow) ?? .general
        prompt = try container.decodeIfPresent(String.self, forKey: .prompt) ?? workflow.defaultPrompt
        maxTokens = try container.decodeIfPresent(Int.self, forKey: .maxTokens) ?? 300
        audioInputPath = try container.decodeIfPresent(String.self, forKey: .audioInputPath)
        kvBits = try container.decodeIfPresent(Double.self, forKey: .kvBits)
        kvQuantScheme = try container.decodeIfPresent(VLMKVQuantizationScheme.self, forKey: .kvQuantScheme) ?? .uniform
        processAllPDFPages = try container.decodeIfPresent(Bool.self, forKey: .processAllPDFPages) ?? false
        pythonRepoPath = try container.decodeIfPresent(String.self, forKey: .pythonRepoPath) ?? PythonMLXVLMBridge.defaultRepoPath
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(modelId, forKey: .modelId)
        try container.encode(workflow, forKey: .workflow)
        try container.encode(prompt, forKey: .prompt)
        try container.encode(maxTokens, forKey: .maxTokens)
        try container.encodeIfPresent(audioInputPath, forKey: .audioInputPath)
        try container.encodeIfPresent(kvBits, forKey: .kvBits)
        try container.encode(kvQuantScheme, forKey: .kvQuantScheme)
        try container.encode(processAllPDFPages, forKey: .processAllPDFPages)
        try container.encode(pythonRepoPath, forKey: .pythonRepoPath)
    }
}

public struct VisualAnalysisResult: Sendable {
    public let text: String
    public let outputPath: String
    public let renderedInputPath: String
    public let jsonPath: String?
    public let statusLogPath: String?
}

public struct SegmentationResult: Sendable {
    public let summaryText: String
    public let outputImagePath: String
    public let jsonPath: String
    public let statusLogPath: String?
}

public enum PythonMLXVLMBridge {
    public static let defaultRepoPath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "\(home)/Applications/MLXAudio/Vendor/mlx-vlm",
            "/Users/joru2/Applications/MLXAudio/Vendor/mlx-vlm",
        ]
        return candidates.first(where: { FileManager.default.fileExists(atPath: $0) }) ?? candidates[0]
    }()

    public static func analyze(
        inputURL: URL,
        options: VisualAnalysisOptions,
        outputDirectory: URL,
        statusLogPath: String? = nil,
        progress: (@Sendable (String) -> Void)? = nil
    ) async throws -> VisualAnalysisResult {
        terminateStaleVLMProcesses()
        let repoPath = normalizedRepoPath(options.pythonRepoPath)
        let invocation = try resolvedInvocation(repoPath: repoPath)
        let renderedInputURLs = try renderedInputURLs(for: inputURL, options: options, outputDirectory: outputDirectory)
        let stem = "visual-analysis-\(UUID().uuidString)"
        let outputURL = outputDirectory.appendingPathComponent(stem).appendingPathExtension("txt")
        let jsonURL = outputDirectory.appendingPathComponent(stem).appendingPathExtension("json")
        let statusLogURL = statusLogPath.map { URL(fileURLWithPath: $0) }
            ?? outputDirectory.appendingPathComponent(stem + "-status").appendingPathExtension("log")

        let reportStatus: @Sendable (String) -> Void = { message in
            let line = message.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { return }
            appendLine(line, to: statusLogURL)
            progress?(line)
        }

        reportStatus("Preparing visual analysis input...")
        reportStatus("Using model \(options.modelId)")
        if let kvBits = options.kvBits {
            reportStatus("KV cache quantization enabled: \(kvBits) bits, scheme \(options.kvQuantScheme.rawValue)")
        }
        if renderedInputURLs.count > 1 {
            reportStatus("Rendered \(renderedInputURLs.count) PDF pages for analysis.")
        }

        var pageOutputs: [String] = []
        for (index, renderedInputURL) in renderedInputURLs.enumerated() {
            let prompt = renderedInputURLs.count > 1
                ? "\(options.prompt)\n\nThis is page \(index + 1) of \(renderedInputURLs.count)."
                : options.prompt
            reportStatus(renderedInputURLs.count > 1
                         ? "Analyzing page \(index + 1) of \(renderedInputURLs.count)..."
                         : "Running model inference...")
            let output = try runGeneration(
                invocation: invocation,
                repoPath: repoPath,
                modelId: options.modelId,
                prompt: prompt,
                maxTokens: options.maxTokens,
                imagePath: renderedInputURL.path,
                audioInputPath: options.audioInputPath,
                kvBits: options.kvBits,
                kvQuantScheme: options.kvQuantScheme,
                progress: reportStatus,
                statusLogURL: statusLogURL
            )
            let labeledOutput = renderedInputURLs.count > 1 ? "Page \(index + 1)\n\(output)" : output
            pageOutputs.append(labeledOutput)
        }

        let combinedOutput = pageOutputs.joined(separator: "\n\n---\n\n")
        try combinedOutput.write(to: outputURL, atomically: true, encoding: .utf8)
        let jsonPath = try writeStructuredResultJSON(
            options: options,
            sourceURL: inputURL,
            renderedInputURLs: renderedInputURLs,
            pageOutputs: pageOutputs,
            outputURL: jsonURL
        )
        return VisualAnalysisResult(
            text: combinedOutput,
            outputPath: outputURL.path,
            renderedInputPath: renderedInputURLs.first?.path ?? inputURL.path,
            jsonPath: jsonPath,
            statusLogPath: statusLogURL.path
        )
    }


    public static func captureInteractiveScreenshot(outputDirectory: URL) async throws -> URL {
        try captureWithScreencapture(arguments: ["-i", "-x"], outputDirectory: outputDirectory)
    }

    public static func captureFullScreen(outputDirectory: URL) async throws -> URL {
        try captureWithScreencapture(arguments: ["-x"], outputDirectory: outputDirectory)
    }

    public static func captureFrontmostWindow(outputDirectory: URL) async throws -> URL {
        guard let windowID = frontmostWindowID() else {
            throw NSError(
                domain: "PythonMLXVLMBridge",
                code: 8,
                userInfo: [NSLocalizedDescriptionKey: "Could not determine the frontmost window. Bring the target app forward and try again."]
            )
        }
        return try captureWithScreencapture(arguments: ["-l", String(windowID), "-x"], outputDirectory: outputDirectory)
    }

    public static func runSegmentation(
        inputURL: URL,
        task: SamTaskMode,
        modelId: String,
        prompt: String,
        boxes: String?,
        threshold: Double,
        showBoxes: Bool,
        pythonRepoPath: String,
        outputDirectory: URL,
        statusLogPath: String? = nil,
        progress: (@Sendable (String) -> Void)? = nil
    ) async throws -> SegmentationResult {
        terminateStaleVLMProcesses()
        let repoPath = normalizedRepoPath(pythonRepoPath)
        let pythonExecutable = try resolvedPythonExecutable(repoPath: repoPath)
        let scriptPath = try resolvedSegmentationScriptPath(repoPath: repoPath)
        let stem = "sam3-\(task.rawValue)-\(UUID().uuidString)"
        let outputImageURL = outputDirectory.appendingPathComponent(stem).appendingPathExtension("png")
        let jsonURL = outputDirectory.appendingPathComponent(stem).appendingPathExtension("json")
        let statusLogURL = statusLogPath.map { URL(fileURLWithPath: $0) }
            ?? outputDirectory.appendingPathComponent(stem + "-status").appendingPathExtension("log")

        guard FileManager.default.fileExists(atPath: inputURL.path) else {
            throw NSError(
                domain: "PythonMLXVLMBridge",
                code: 10,
                userInfo: [NSLocalizedDescriptionKey: "The selected image is no longer available at \(inputURL.path). Re-select the file and try again."]
            )
        }

        let reportStatus: @Sendable (String) -> Void = { message in
            let line = message.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { return }
            appendLine(line, to: statusLogURL)
            progress?(line)
        }
        reportStatus("Preparing segmentation input...")
        reportStatus("Using model \(modelId)")
        reportStatus(task == .detect ? "Running detection..." : "Running segmentation...")

        var arguments = [
            scriptPath,
            "--repo-path", repoPath,
            "--image", inputURL.path,
            "--task", task.rawValue,
            "--model", modelId,
            "--prompt", prompt,
            "--threshold", String(threshold),
            "--output-image", outputImageURL.path,
            "--output-json", jsonURL.path,
        ]
        if let boxes, !boxes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            arguments += ["--boxes", boxes]
        }
        if showBoxes {
            arguments.append("--show-boxes")
        }

        let process = Process()
        process.currentDirectoryURL = URL(fileURLWithPath: repoPath)
        process.executableURL = URL(fileURLWithPath: pythonExecutable)
        process.arguments = arguments
        process.environment = huggingFaceEnvironment()

        let stdout = Pipe()
        process.standardOutput = stdout
        FileManager.default.createFile(atPath: statusLogURL.path, contents: nil)
        let logHandle = try FileHandle(forWritingTo: statusLogURL)
        _ = try? logHandle.seekToEnd()
        process.standardError = logHandle

        try process.run()
        process.waitUntilExit()
        try? logHandle.close()

        let stdoutData = stdout.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: stdoutData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !output.isEmpty {
            appendLine(output, to: statusLogURL)
            progress?(output)
        }
        let errorOutput = (try? String(contentsOf: statusLogURL, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard process.terminationStatus == 0 else {
            throw NSError(
                domain: "PythonMLXVLMBridge",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: friendlyVLMError(errorOutput, modelId: modelId, fallback: "SAM 3 execution failed.")]
            )
        }

        return SegmentationResult(
            summaryText: output,
            outputImagePath: outputImageURL.path,
            jsonPath: jsonURL.path,
            statusLogPath: statusLogURL.path
        )
    }


    private static func friendlyVLMError(_ raw: String, modelId: String, fallback: String) -> String {
        let message = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return fallback }

        let lowercased = message.lowercased()
        if lowercased.contains("gated repo") || lowercased.contains("401 unauthorized") || lowercased.contains("repositorynotfounderror") {
            return """
            Model \(modelId) requires Hugging Face access or a valid HF_TOKEN. Configure access, then retry.

            Upstream error:
            \(message)
            """
        }

        if lowercased.contains("out of memory") || lowercased.contains("peak memory") {
            return """
            Model \(modelId) exceeded available memory on this Mac. Try a smaller preset or lower-cost workflow.

            Upstream error:
            \(message)
            """
        }

        return message
    }

    private static func captureWithScreencapture(arguments: [String], outputDirectory: URL) throws -> URL {
        let outputURL = outputDirectory.appendingPathComponent("visual-screenshot-\(UUID().uuidString).png")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = arguments + [outputURL.path]

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw NSError(
                domain: "PythonMLXVLMBridge",
                code: 6,
                userInfo: [NSLocalizedDescriptionKey: "Screenshot capture was canceled or failed."]
            )
        }

        guard FileManager.default.fileExists(atPath: outputURL.path) else {
            throw NSError(
                domain: "PythonMLXVLMBridge",
                code: 7,
                userInfo: [NSLocalizedDescriptionKey: "No screenshot was captured."]
            )
        }
        return outputURL
    }

    private static func runGeneration(
        invocation: (executable: String, arguments: [String]),
        repoPath: String,
        modelId: String,
        prompt: String,
        maxTokens: Int,
        imagePath: String,
        audioInputPath: String?,
        kvBits: Double?,
        kvQuantScheme: VLMKVQuantizationScheme,
        progress: (@Sendable (String) -> Void)? = nil,
        statusLogURL: URL
    ) throws -> String {
        var arguments = invocation.arguments + [
            "--model", modelId,
            "--max-tokens", String(maxTokens),
            "--prompt", prompt,
            "--image", imagePath,
        ]
        if let audioInputPath, !audioInputPath.isEmpty {
            arguments += ["--audio", audioInputPath]
        }
        if let kvBits {
            arguments += ["--kv-bits", String(kvBits), "--kv-quant-scheme", kvQuantScheme.rawValue]
        }

        let process = Process()
        process.currentDirectoryURL = URL(fileURLWithPath: repoPath)
        process.executableURL = URL(fileURLWithPath: invocation.executable)
        process.arguments = arguments
        process.environment = huggingFaceEnvironment()

        let stdout = Pipe()
        process.standardOutput = stdout
        FileManager.default.createFile(atPath: statusLogURL.path, contents: nil)
        let logHandle = try FileHandle(forWritingTo: statusLogURL)
        try logHandle.seekToEnd()
        process.standardError = logHandle

        try process.run()
        process.waitUntilExit()
        try? logHandle.close()

        let stdoutData = stdout.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: stdoutData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !output.isEmpty {
            appendLine(output, to: statusLogURL)
            progress?(normalizeProgressLine(output, modelId: modelId))
        }
        let errorOutput = (try? String(contentsOf: statusLogURL, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard process.terminationStatus == 0 else {
            throw NSError(
                domain: "PythonMLXVLMBridge",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: errorOutput.isEmpty ? "mlx-vlm failed." : errorOutput]
            )
        }
        guard !output.isEmpty else {
            throw NSError(
                domain: "PythonMLXVLMBridge",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: errorOutput.isEmpty ? "mlx-vlm returned no output." : errorOutput]
            )
        }
        return output
    }

    private static func appendLine(_ line: String, to url: URL) {
        let text = line.hasSuffix("\n") ? line : line + "\n"
        let data = Data(text.utf8)
        if FileManager.default.fileExists(atPath: url.path) {
            if let handle = try? FileHandle(forWritingTo: url) {
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
                try? handle.close()
            }
        } else {
            try? data.write(to: url, options: .atomic)
        }
    }

    private static func normalizeProgressLine(_ line: String, modelId: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let lower = trimmed.lowercased()
        if lower.contains("unauthenticated requests") || lower.contains("set a hf_token") {
            return "Hugging Face is downloading without authentication. Set HF_TOKEN for higher rate limits and faster downloads."
        }
        if lower.contains("fetching ") || lower.contains("downloading") {
            return "Downloading model assets: \(trimmed)"
        }
        if lower.contains("loading checkpoint") || lower.contains("loading model") {
            return "Loading model \(modelId): \(trimmed)"
        }
        if lower.contains("warming up") {
            return "Warming up model \(modelId): \(trimmed)"
        }
        return trimmed
    }

    private static func huggingFaceEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["HF_HUB_DISABLE_XET"] = "1"
        env["HF_HUB_ENABLE_HF_TRANSFER"] = "0"
        return env
    }

    private static func terminateStaleVLMProcesses() {
        let patterns = [
            "/Users/joru2/Applications/MLXAudio/Vendor/mlx-vlm/.venv/bin/mlx_vlm.generate",
            "/Users/joru2/Applications/MLXAudio/scripts/sam3_runner.py",
        ]

        for pattern in patterns {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
            process.arguments = ["-f", pattern]
            try? process.run()
            process.waitUntilExit()
        }
    }

    private static func normalizedRepoPath(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? defaultRepoPath : trimmed
    }

    private static func resolvedPythonExecutable(repoPath: String) throws -> String {
        let candidates = [
            URL(fileURLWithPath: repoPath).appendingPathComponent(".venv/bin/python").path,
            "/usr/bin/python3",
        ]
        if let match = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return match
        }
        throw NSError(
            domain: "PythonMLXVLMBridge",
            code: 9,
            userInfo: [NSLocalizedDescriptionKey: "Could not find a Python runtime for mlx-vlm."]
        )
    }

    private static func resolvedInvocation(repoPath: String) throws -> (executable: String, arguments: [String]) {
        let venvExecutable = URL(fileURLWithPath: repoPath)
            .appendingPathComponent(".venv/bin/mlx_vlm.generate")
            .path
        if FileManager.default.isExecutableFile(atPath: venvExecutable) {
            return (venvExecutable, [])
        }

        let uvCandidates = [
            ProcessInfo.processInfo.environment["UV_BIN"],
            "\(FileManager.default.homeDirectoryForCurrentUser.path)/.local/bin/uv",
            "/opt/homebrew/bin/uv",
            "/usr/local/bin/uv",
            "/Users/joru2/.local/bin/uv",
        ].compactMap { $0 }

        if let uv = uvCandidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return (uv, ["run", "mlx_vlm.generate"])
        }

        throw NSError(
            domain: "PythonMLXVLMBridge",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Could not find mlx-vlm runtime. Install it in \(repoPath)/.venv or provide UV_BIN."]
        )
    }

    private static func resolvedSegmentationScriptPath(repoPath: String) throws -> String {
        let candidates = [
            URL(fileURLWithPath: repoPath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("scripts/sam3_runner.py")
                .path,
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("scripts/sam3_runner.py")
                .path,
        ]

        if let match = candidates.first(where: { FileManager.default.fileExists(atPath: $0) }) {
            return match
        }

        throw NSError(
            domain: "PythonMLXVLMBridge",
            code: 11,
            userInfo: [NSLocalizedDescriptionKey: "Could not find the local SAM runner script. Expected one of: \(candidates.joined(separator: ", "))"]
        )
    }

    private static func renderedInputURLs(for inputURL: URL, options: VisualAnalysisOptions, outputDirectory: URL) throws -> [URL] {
        let ext = inputURL.pathExtension.lowercased()
        if ["png", "jpg", "jpeg", "webp", "heic", "gif", "bmp", "tiff"].contains(ext) {
            return [inputURL]
        }

        #if canImport(PDFKit)
        if ext == "pdf" {
            if options.processAllPDFPages {
                return try renderAllPDFPages(inputURL: inputURL, outputDirectory: outputDirectory)
            }
            return [try renderFirstPDFPage(inputURL: inputURL, outputDirectory: outputDirectory)]
        }
        #endif

        throw NSError(
            domain: "PythonMLXVLMBridge",
            code: 3,
            userInfo: [NSLocalizedDescriptionKey: "Unsupported input type. Use an image or PDF file."]
        )
    }
}

#if canImport(PDFKit)
import PDFKit
#if canImport(AppKit)
import AppKit
#endif

private extension PythonMLXVLMBridge {
    static func renderFirstPDFPage(inputURL: URL, outputDirectory: URL) throws -> URL {
        guard let document = PDFDocument(url: inputURL), let page = document.page(at: 0) else {
            throw NSError(domain: "PythonMLXVLMBridge", code: 4, userInfo: [NSLocalizedDescriptionKey: "Could not open PDF."])
        }

        let bounds = page.bounds(for: .mediaBox)
        let imageRep = page.thumbnail(of: CGSize(width: max(1200, bounds.width), height: max(1600, bounds.height)), for: .mediaBox)
        guard let tiff = imageRep.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "PythonMLXVLMBridge", code: 5, userInfo: [NSLocalizedDescriptionKey: "Could not render PDF preview."])
        }

        let renderedURL = outputDirectory.appendingPathComponent("visual-input-\(UUID().uuidString).png")
        try pngData.write(to: renderedURL, options: .atomic)
        return renderedURL
    }

    static func renderAllPDFPages(inputURL: URL, outputDirectory: URL) throws -> [URL] {
        guard let document = PDFDocument(url: inputURL), document.pageCount > 0 else {
            throw NSError(domain: "PythonMLXVLMBridge", code: 4, userInfo: [NSLocalizedDescriptionKey: "Could not open PDF."])
        }

        return try (0..<document.pageCount).map { index in
            guard let page = document.page(at: index) else {
                throw NSError(domain: "PythonMLXVLMBridge", code: 4, userInfo: [NSLocalizedDescriptionKey: "Could not render PDF page \(index + 1)."])
            }
            let bounds = page.bounds(for: .mediaBox)
            let imageRep = page.thumbnail(of: CGSize(width: max(1200, bounds.width), height: max(1600, bounds.height)), for: .mediaBox)
            guard let tiff = imageRep.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff),
                  let pngData = bitmap.representation(using: .png, properties: [:]) else {
                throw NSError(domain: "PythonMLXVLMBridge", code: 5, userInfo: [NSLocalizedDescriptionKey: "Could not render PDF page \(index + 1)."])
            }
            let renderedURL = outputDirectory.appendingPathComponent("visual-input-\(UUID().uuidString)-page-\(index + 1).png")
            try pngData.write(to: renderedURL, options: .atomic)
            return renderedURL
        }
    }
}
#endif

private extension PythonMLXVLMBridge {
    static func writeStructuredResultJSON(
        options: VisualAnalysisOptions,
        sourceURL: URL,
        renderedInputURLs: [URL],
        pageOutputs: [String],
        outputURL: URL
    ) throws -> String? {
        let pageObjects = pageOutputs.enumerated().map { index, text in
            var pageObject: [String: Any] = [
                "page": index + 1,
                "renderedInputPath": renderedInputURLs[safe: index]?.path ?? renderedInputURLs.first?.path ?? sourceURL.path,
                "text": text,
            ]
            let structured = structuredPayload(for: options.workflow, text: text)
            if !structured.isEmpty {
                pageObject["structured"] = structured
            }
            return pageObject
        }

        var payload: [String: Any] = [
            "sourcePath": sourceURL.path,
            "workflow": options.workflow.rawValue,
            "modelId": options.modelId,
            "createdAt": ISO8601DateFormatter().string(from: Date()),
            "pageCount": renderedInputURLs.count,
            "fullText": pageOutputs.joined(separator: "\n\n"),
            "pages": pageObjects,
        ]
        let structured = structuredPayload(for: options.workflow, text: pageOutputs.joined(separator: "\n\n"))
        if !structured.isEmpty {
            payload["structured"] = structured
        }

        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: outputURL, options: .atomic)
        return outputURL.path
    }

    static func structuredPayload(for workflow: VisualAnalysisWorkflow, text: String) -> [String: Any] {
        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lines = normalizedText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let fields = colonSeparatedFields(in: lines)
        let amounts = detectedAmounts(in: normalizedText)

        switch workflow {
        case .general, .ocrPlainText, .screenSummary:
            return [:]
        case .ocrStructured:
            return [
                "schema": "structured_document_v1",
                "fields": fields,
                "tables": detectedTables(in: lines),
                "amounts": amounts,
            ]
        case .ocrReceipt:
            return [
                "schema": "receipt_v1",
                "merchant": lines.first ?? "",
                "fields": fields,
                "amounts": amounts,
                "total": inferredTotal(from: lines, amounts: amounts),
            ]
        case .ocrForm:
            return [
                "schema": "form_v1",
                "fields": fields,
                "checkedLines": lines.filter { $0.localizedCaseInsensitiveContains("[x]") || $0.localizedCaseInsensitiveContains("checked") },
                "signatureLines": lines.filter { $0.localizedCaseInsensitiveContains("signature") },
            ]
        case .ocrTable:
            let rows = detectedTables(in: lines)
            return [
                "schema": "table_v1",
                "rows": rows,
                "columnCount": rows.map(\.count).max() ?? 0,
            ]
        }
    }

    static func colonSeparatedFields(in lines: [String]) -> [String: String] {
        var fields: [String: String] = [:]
        for line in lines {
            let separators = [":", "\t", " - "]
            guard let separator = separators.first(where: { line.contains($0) }) else { continue }
            let parts = line.components(separatedBy: separator).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard parts.count >= 2, !parts[0].isEmpty else { continue }
            fields[parts[0]] = parts.dropFirst().joined(separator: " ")
        }
        return fields
    }

    static func detectedAmounts(in text: String) -> [String] {
        let pattern = #"(?:(?:USD|EUR|GBP|CHF)\s*)?[$€£]?\d+(?:[.,]\d{2})"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap {
            Range($0.range, in: text).map { String(text[$0]) }
        }
    }

    static func inferredTotal(from lines: [String], amounts: [String]) -> String {
        if let line = lines.first(where: { $0.localizedCaseInsensitiveContains("total") }) {
            return line
        }
        return amounts.last ?? ""
    }

    static func detectedTables(in lines: [String]) -> [[String]] {
        lines.compactMap { line in
            let pipeParts = line
                .split(separator: "|")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if pipeParts.count > 1 {
                return pipeParts
            }

            let tabParts = line
                .split(separator: "\t")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if tabParts.count > 1 {
                return tabParts
            }

            let regex = try? NSRegularExpression(pattern: #"\s{2,}"#)
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            let splitPoints = regex?.matches(in: line, range: range) ?? []
            guard !splitPoints.isEmpty else { return nil }

            var columns: [String] = []
            var currentIndex = line.startIndex
            for match in splitPoints {
                guard let matchRange = Range(match.range, in: line) else { continue }
                let value = String(line[currentIndex..<matchRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty {
                    columns.append(value)
                }
                currentIndex = matchRange.upperBound
            }
            let tail = String(line[currentIndex...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !tail.isEmpty {
                columns.append(tail)
            }
            return columns.count > 1 ? columns : nil
        }
    }

    static func frontmostWindowID() -> Int? {
        #if canImport(AppKit)
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let targetPID = app.processIdentifier
        guard let windowInfo = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        let candidate = windowInfo
            .filter { info in
                guard let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid == targetPID else { return false }
                guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0 else { return false }
                guard let bounds = info[kCGWindowBounds as String] as? [String: Any],
                      let width = bounds["Width"] as? Double,
                      let height = bounds["Height"] as? Double else { return false }
                return width > 0 && height > 0
            }
            .max { lhs, rhs in
                let lhsBounds = lhs[kCGWindowBounds as String] as? [String: Any]
                let rhsBounds = rhs[kCGWindowBounds as String] as? [String: Any]
                let lhsArea = ((lhsBounds?["Width"] as? Double) ?? 0) * ((lhsBounds?["Height"] as? Double) ?? 0)
                let rhsArea = ((rhsBounds?["Width"] as? Double) ?? 0) * ((rhsBounds?["Height"] as? Double) ?? 0)
                return lhsArea < rhsArea
            }

        return candidate?[kCGWindowNumber as String] as? Int
        #else
        return nil
        #endif
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
