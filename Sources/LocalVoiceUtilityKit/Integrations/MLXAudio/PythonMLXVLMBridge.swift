import Foundation

public enum VisualAnalysisWorkflow: String, Codable, CaseIterable, Sendable {
    case general
    case ocrPlainText
    case ocrStructured
    case screenSummary

    public var displayName: String {
        switch self {
        case .general: return "General"
        case .ocrPlainText: return "OCR Plain Text"
        case .ocrStructured: return "OCR Structured"
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
    public var pythonRepoPath: String

    public init(
        modelId: String = "mlx-community/Qwen2-VL-2B-Instruct-4bit",
        workflow: VisualAnalysisWorkflow = .general,
        prompt: String = VisualAnalysisWorkflow.general.defaultPrompt,
        maxTokens: Int = 300,
        pythonRepoPath: String = PythonMLXVLMBridge.defaultRepoPath
    ) {
        self.modelId = modelId
        self.workflow = workflow
        self.prompt = prompt
        self.maxTokens = maxTokens
        self.pythonRepoPath = pythonRepoPath
    }

    private enum CodingKeys: String, CodingKey {
        case modelId
        case workflow
        case prompt
        case maxTokens
        case pythonRepoPath
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        modelId = try container.decodeIfPresent(String.self, forKey: .modelId) ?? "mlx-community/Qwen2-VL-2B-Instruct-4bit"
        workflow = try container.decodeIfPresent(VisualAnalysisWorkflow.self, forKey: .workflow) ?? .general
        prompt = try container.decodeIfPresent(String.self, forKey: .prompt) ?? workflow.defaultPrompt
        maxTokens = try container.decodeIfPresent(Int.self, forKey: .maxTokens) ?? 300
        pythonRepoPath = try container.decodeIfPresent(String.self, forKey: .pythonRepoPath) ?? PythonMLXVLMBridge.defaultRepoPath
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(modelId, forKey: .modelId)
        try container.encode(workflow, forKey: .workflow)
        try container.encode(prompt, forKey: .prompt)
        try container.encode(maxTokens, forKey: .maxTokens)
        try container.encode(pythonRepoPath, forKey: .pythonRepoPath)
    }
}

public struct VisualAnalysisResult: Sendable {
    public let text: String
    public let outputPath: String
    public let renderedInputPath: String
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
        outputDirectory: URL
    ) async throws -> VisualAnalysisResult {
        let repoPath = normalizedRepoPath(options.pythonRepoPath)
        let invocation = try resolvedInvocation(repoPath: repoPath)
        let renderedInputURL = try renderedInputURL(for: inputURL, outputDirectory: outputDirectory)
        let outputURL = outputDirectory.appendingPathComponent("visual-analysis-\(UUID().uuidString).txt")

        let arguments = invocation.arguments + [
            "--model", options.modelId,
            "--max-tokens", String(options.maxTokens),
            "--prompt", options.prompt,
            "--image", renderedInputURL.path,
        ]

        let process = Process()
        process.currentDirectoryURL = URL(fileURLWithPath: repoPath)
        process.executableURL = URL(fileURLWithPath: invocation.executable)
        process.arguments = arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        let stdoutData = stdout.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: stdoutData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let errorOutput = String(data: stderrData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

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

        try output.write(to: outputURL, atomically: true, encoding: .utf8)
        return VisualAnalysisResult(text: output, outputPath: outputURL.path, renderedInputPath: renderedInputURL.path)
    }


    public static func captureInteractiveScreenshot(outputDirectory: URL) async throws -> URL {
        let outputURL = outputDirectory.appendingPathComponent("visual-screenshot-\(UUID().uuidString).png")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-i", "-x", outputURL.path]

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

    private static func normalizedRepoPath(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? defaultRepoPath : trimmed
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

    private static func renderedInputURL(for inputURL: URL, outputDirectory: URL) throws -> URL {
        let ext = inputURL.pathExtension.lowercased()
        if ["png", "jpg", "jpeg", "webp", "heic", "gif", "bmp", "tiff"].contains(ext) {
            return inputURL
        }

        #if canImport(PDFKit)
        if ext == "pdf" {
            return try renderFirstPDFPage(inputURL: inputURL, outputDirectory: outputDirectory)
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
import CoreGraphics
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
}
#endif
