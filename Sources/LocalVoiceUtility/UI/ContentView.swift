import LocalVoiceUtilityKit
import SwiftUI
import UniformTypeIdentifiers
import AppKit
import AVFoundation

struct ContentView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        NavigationSplitView {
            List(AppStore.Screen.allCases, id: \.self, selection: $store.selectedScreen) { screen in
                Text(screen.rawValue)
            }
            .navigationTitle("Local Voice Utility")
            .navigationSplitViewColumnWidth(min: 220, ideal: 250)
        } detail: {
            screenView
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .navigationSplitViewStyle(.balanced)
        .sheet(isPresented: Binding(
            get: { store.latestError != nil },
            set: { presented in
                if !presented {
                    store.latestError = nil
                }
            }
        )) {
            ErrorSheet(
                message: store.latestError ?? "Unknown error",
                onDismiss: { store.latestError = nil }
            )
        }
    }

    @ViewBuilder
    private var screenView: some View {
        switch store.selectedScreen {
        case .home:
            HomeScreen()
        case .assistant:
            LocalAssistantScreen()
        case .visual:
            VisualAnalysisScreen()
        case .segment:
            SegmentationScreen()
        case .scannedPDF:
            ScannedPDFToAudioScreen()
        case .pdf:
            PDFToAudioScreen()
        case .url:
            URLToAudioScreen()
        case .transcribe:
            TranscribeScreen()
        case .live:
            LivePlaceholderScreen()
        case .library:
            LibraryScreen()
        case .models:
            ModelsScreen()
        case .settings:
            SettingsScreen()
        }
    }
}

private struct ErrorSheet: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Error")
                .font(.title2.bold())
            ScrollView {
                Text(message)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 260)
            AdaptiveButtonRow {
                Button("Copy Error") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(message, forType: .string)
                }
                Button("Close") {
                    onDismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(minWidth: 720, minHeight: 420)
    }
}


private struct ScreenScrollView<Content: View>: View {
    let maxWidth: CGFloat
    @ViewBuilder let content: () -> Content

    init(maxWidth: CGFloat = 980, @ViewBuilder content: @escaping () -> Content) {
        self.maxWidth = maxWidth
        self.content = content
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                content()
            }
            .frame(maxWidth: maxWidth, alignment: .topLeading)
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct ScreenSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text(title)
                .font(.headline)
        }
    }
}

private struct AdaptiveButtonRow<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 12) {
                content()
            }
            VStack(alignment: .leading, spacing: 12) {
                content()
            }
        }
    }
}

struct HomeScreen: View {
    @EnvironmentObject private var store: AppStore
    private let quickActionColumns = [GridItem(.adaptive(minimum: 180, maximum: 260), spacing: 12)]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Quick Actions")
                .font(.title2.bold())
            LazyVGrid(columns: quickActionColumns, alignment: .leading, spacing: 12) {
                quickTile(title: "Local Assistant", action: { store.selectedScreen = .assistant })
                quickTile(title: "Analyze Image/PDF", action: { store.selectedScreen = .visual })
                quickTile(title: "Detect & Segment", action: { store.selectedScreen = .segment })
                quickTile(title: "Scanned PDF -> Audio", action: { store.selectedScreen = .scannedPDF })
                quickTile(title: "Read a PDF", action: { store.selectedScreen = .pdf })
                quickTile(title: "Read a Web Page", action: { store.selectedScreen = .url })
                quickTile(title: "Transcribe Audio/Video", action: { store.selectedScreen = .transcribe })
            }
            Text("Recent Jobs")
                .font(.headline)
            List(store.jobs.prefix(10), id: \.id) { job in
                HStack {
                    Text(job.type.rawValue)
                    Spacer()
                    Text(job.status.rawValue)
                }
            }
        }
        .padding(24)
    }

    @ViewBuilder
    private func quickTile(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .frame(maxWidth: .infinity, minHeight: 80)
        }
        .buttonStyle(.borderedProminent)
    }
}

private struct VisualPreset: Identifiable, Hashable {
    let id: String
    let title: String
    let summary: String
    let bestForOCR: Bool
    let supportsAudio: Bool
    let supportsTurboQuant: Bool
}

private struct SegmentationPreset: Identifiable, Hashable {
    let id: String
    let title: String
    let summary: String
}

private enum VisualResultAction: String, CaseIterable {
    case none = "None"
    case clipboard = "Copy to Clipboard"
    case typeToFrontmost = "Type into Front App"
    case webhook = "POST Webhook"
}

private struct BatchScannedPDFResult: Identifiable, Hashable {
    let id = UUID()
    let pdfPath: String
    let transcriptPath: String
    let jsonPath: String?
    let audioPath: String
}

private struct VisualActionProfileDraft {
    var id: UUID?
    var name: String = ""
    var payload: String = ""
}

private struct SavedWebhookTemplateDraft {
    var id: UUID?
    var name: String = ""
    var url: String = ""
}

private struct SegmentationBoxDraft {
    var text: String = ""
}

private struct AssistantMessage: Identifiable, Hashable {
    enum Role {
        case user
        case assistant
    }

    let id = UUID()
    let role: Role
    let text: String
}

private let visualPresets: [VisualPreset] = [
    .init(id: "mlx-community/Qwen2-VL-2B-Instruct-4bit", title: "Qwen2-VL 2B", summary: "General image understanding", bestForOCR: false, supportsAudio: false, supportsTurboQuant: false),
    .init(id: "mlx-community/gemma-3n-E2B-it-4bit", title: "Gemma 3n E2B", summary: "Image + audio capable omni model", bestForOCR: false, supportsAudio: true, supportsTurboQuant: false),
    .init(id: "google/gemma-4-e2b-it", title: "Gemma 4 E2B", summary: "Smaller Gemma 4 multimodal model with image and audio support", bestForOCR: false, supportsAudio: true, supportsTurboQuant: false),
    .init(id: "google/gemma-4-e4b-it", title: "Gemma 4 E4B", summary: "Gemma 4 multimodal model with image and audio support", bestForOCR: false, supportsAudio: true, supportsTurboQuant: false),
    .init(id: "google/gemma-4-31b-it", title: "Gemma 4 31B", summary: "Large Gemma 4 model; best candidate for TurboQuant KV cache", bestForOCR: false, supportsAudio: false, supportsTurboQuant: true),
    .init(id: "mlx-community/granite-vision-3.2-2b-4bit", title: "Granite Vision 3.2", summary: "Compact document and image reasoning", bestForOCR: false, supportsAudio: false, supportsTurboQuant: false),
    .init(id: "ibm-granite/granite-4.0-3b-vision", title: "Granite 4.0 Vision", summary: "IBM Granite 4.0 vision model from mlx-vlm v0.4.3", bestForOCR: false, supportsAudio: false, supportsTurboQuant: false),
    .init(id: "tiiuae/Falcon-OCR", title: "Falcon OCR", summary: "OCR-oriented extraction", bestForOCR: true, supportsAudio: false, supportsTurboQuant: false),
    .init(id: "tiiuae/Falcon-Perception", title: "Falcon Perception", summary: "Detection and perception model for vision tasks", bestForOCR: false, supportsAudio: false, supportsTurboQuant: false),
    .init(id: "mlx-community/deepseek-ocr-2-4bit", title: "DeepSeek OCR 2", summary: "Structured OCR and layout reading", bestForOCR: true, supportsAudio: false, supportsTurboQuant: false),
]

private let segmentationPresets: [SegmentationPreset] = [
    .init(id: "mlx-community/sam3.1-bf16", title: "SAM 3.1", summary: "Latest SAM 3.1 detection and segmentation"),
    .init(id: "facebook/sam3", title: "SAM 3", summary: "Detection and segmentation (gated)"),
]

struct VisualAnalysisScreen: View {
    @EnvironmentObject private var store: AppStore
    @State private var selectedInput: URL?
    @State private var selectedAudioInput: URL?
    @State private var workflow: VisualAnalysisWorkflow = .general
    @State private var modelID = VisualAnalysisOptions().modelId
    @State private var prompt = VisualAnalysisOptions().prompt
    @State private var maxTokens = "300"
    @State private var kvBits = ""
    @State private var kvQuantScheme: VLMKVQuantizationScheme = .uniform
    @State private var isRunning = false
    @State private var isCapturingScreenshot = false
    @State private var isNarrating = false
    @State private var resultText = ""
    @State private var outputPath: String?
    @State private var renderedInputPath: String?
    @State private var jsonPath: String?
    @State private var statusLogPath: String?
    @State private var analysisStatusText = ""
    @State private var narrationPath: String?
    @State private var narrationModelID = TTSOptions().modelId
    @State private var narrationLanguageCode = TTSOptions().languageCode
    @State private var narrationVoiceIdentifier = ""
    @State private var systemVoices: [VoiceOption] = []
    @State private var narrationPlayer: AVAudioPlayer?
    @State private var resultAction: VisualResultAction = .none
    @State private var selectedWebhookTemplateID: UUID?
    @State private var webhookURL = ""
    @State private var additionalContext = ""
    @State private var selectedActionProfileID: UUID?
    @State private var actionProfileDraft = VisualActionProfileDraft()
    @State private var statusPollingTask: Task<Void, Never>?

    private var selectedPreset: VisualPreset? {
        visualPresets.first(where: { $0.id == modelID })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Visual Analysis")
                .font(.title2.bold())
            Text("Analyze an image, screenshot, or the first page of a PDF using the local `mlx-vlm` environment, then optionally read the result aloud.")
                .foregroundStyle(.secondary)

            Form {
                Section("Input") {
                    Text(selectedInput?.path ?? "No file selected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack {
                        Button("Select Image or PDF") {
                            pickVisualInput()
                        }
                        Button(isCapturingScreenshot ? "Capturing..." : "Capture Screenshot") {
                            captureScreenshot()
                        }
                        .disabled(isCapturingScreenshot)
                        Button("Front Window") {
                            captureFrontWindow()
                        }
                        .disabled(isCapturingScreenshot)
                        Button("Full Screen") {
                            captureFullScreen()
                        }
                        .disabled(isCapturingScreenshot)
                        if let selectedInput {
                            Button("Reveal Input") {
                                NSWorkspace.shared.activateFileViewerSelecting([selectedInput])
                            }
                        }
                    }
                    if selectedInput?.pathExtension.lowercased() == "pdf" {
                        Toggle("Process all PDF pages", isOn: Binding(
                            get: { store.settings.visualDefaults.processAllPDFPages },
                            set: { store.settings.visualDefaults.processAllPDFPages = $0 }
                        ))
                        .toggleStyle(.switch)
                    }
                    if selectedPreset?.supportsAudio == true {
                        Divider()
                        Text(selectedAudioInput?.path ?? "No audio context selected")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack {
                            Button("Select Audio Context") {
                                pickAudioContext()
                            }
                            if let selectedAudioInput {
                                Button("Reveal Audio") {
                                    NSWorkspace.shared.activateFileViewerSelecting([selectedAudioInput])
                                }
                                Button("Clear Audio") {
                                    self.selectedAudioInput = nil
                                }
                            }
                        }
                    }
                }

                Section("Workflow") {
                    Picker("Mode", selection: $workflow) {
                        ForEach(VisualAnalysisWorkflow.allCases, id: \.self) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    HStack {
                        Button("Use Suggested Prompt") {
                            applyWorkflowDefaults(resetPromptOnly: true)
                        }
                        if workflow == .ocrPlainText || workflow == .ocrStructured {
                            Text("OCR models are listed first for this mode.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Model") {
                    Picker("Preset", selection: $modelID) {
                        ForEach(sortedVisualPresets) { preset in
                            Text("\(preset.title) — \(preset.summary)").tag(preset.id)
                        }
                    }
                    TextField("Model ID", text: $modelID)
                    TextField("Prompt", text: $prompt, axis: .vertical)
                        .lineLimit(4, reservesSpace: true)
                    TextField("Max tokens", text: $maxTokens)
                    if selectedPreset?.supportsTurboQuant == true {
                        TextField("KV bits", text: $kvBits)
                        Picker("KV quant scheme", selection: $kvQuantScheme) {
                            ForEach(VLMKVQuantizationScheme.allCases, id: \.self) { option in
                                Text(option.rawValue).tag(option)
                            }
                        }
                        Text("Use TurboQuant for Gemma 4 long-context runs to reduce KV cache memory.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if modelID == "google/gemma-4-31b-it" {
                        Text("Gemma 4 31B is a high-memory model. Expect slow first-run downloads and large RAM use; TurboQuant is mainly useful here.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if workflow == .ocrStructured || workflow == .ocrReceipt || workflow == .ocrForm || workflow == .ocrTable {
                        Text("Structured OCR modes emit both plain text and schema-shaped JSON output.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text("Repo path: \(store.settings.pythonMLXVLMRepoPath)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Additional Context") {
                    TextField("Transcript, notes, or audio context to include with the analysis prompt", text: $additionalContext, axis: .vertical)
                        .lineLimit(4, reservesSpace: true)
                    Text("Use this to combine what is on screen with meeting notes, transcript text, or related audio context.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            AdaptiveButtonRow {
                Button(isRunning ? "Analyzing..." : "Run Analysis") {
                    runAnalysis()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isRunning || selectedInput == nil)

                if let outputPath {
                    Button("Open Result") {
                        NSWorkspace.shared.open(URL(fileURLWithPath: outputPath))
                    }
                }
                if let jsonPath {
                    Button("Open JSON") {
                        NSWorkspace.shared.open(URL(fileURLWithPath: jsonPath))
                    }
                }
                if let statusLogPath {
                    Button("Open Status Log") {
                        NSWorkspace.shared.open(URL(fileURLWithPath: statusLogPath))
                    }
                }
                if let outputPath {
                    Button("Reveal Result") {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: outputPath)])
                    }
                }
                if let renderedInputPath {
                    Button("Reveal Rendered Input") {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: renderedInputPath)])
                    }
                }
            }

            Text("Result")
                .font(.headline)
            if isRunning || !analysisStatusText.isEmpty {
                GroupBox("Run Status") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(analysisStatusText.isEmpty ? "Preparing analysis..." : analysisStatusText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if isRunning {
                            ProgressView()
                        }
                    }
                    .padding(.top, 4)
                }
            }
            ScrollView {
                Text(resultText.isEmpty ? "No result yet." : resultText)
                    .font(.system(.body, design: .default))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity)

            GroupBox("Readback") {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Reader model", selection: $narrationModelID) {
                        ForEach(SpeechCatalog.ttsModels(for: .documentReader)) { preset in
                            Text(presetMenuLabel(preset)).tag(preset.id)
                        }
                    }
                    Picker("Reader language", selection: $narrationLanguageCode) {
                        ForEach(SpeechCatalog.languageOptions(for: SpeechCatalog.preset(for: narrationModelID), allowAutoDetect: false)) { language in
                            Text(language.label).tag(language.code)
                        }
                    }
                    Picker("Reader voice", selection: $narrationVoiceIdentifier) {
                        Text("System Default").tag("")
                        ForEach(systemVoices, id: \.id) { voice in
                            Text(voice.label).tag(voice.id)
                        }
                    }
                    AdaptiveButtonRow {
                        Button(isNarrating ? "Generating Audio..." : "Read Result Aloud") {
                            narrateResult()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isNarrating || resultText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        if let narrationPath {
                            Button(narrationPlayer?.isPlaying == true ? "Stop Playback" : "Play Narration") {
                                toggleNarrationPlayback(path: narrationPath)
                            }
                            Button("Reveal Narration") {
                                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: narrationPath)])
                            }
                        }
                    }
                }
                .padding(.top, 4)
            }

            GroupBox("Result Actions") {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Action", selection: $resultAction) {
                        ForEach(VisualResultAction.allCases, id: \.self) { action in
                            Text(action.rawValue).tag(action)
                        }
                    }
                    if resultAction == .webhook {
                        Picker("Saved profile", selection: $selectedActionProfileID) {
                            Text("None").tag(UUID?.none)
                            ForEach(store.actionProfiles) { profile in
                                Text(profile.name).tag(UUID?.some(profile.id))
                            }
                        }
                        Picker("Webhook template", selection: $selectedWebhookTemplateID) {
                            Text("Custom").tag(UUID?.none)
                            ForEach(store.settings.savedWebhookTemplates) { template in
                                Text(template.name).tag(UUID?.some(template.id))
                            }
                        }
                        TextField("Webhook URL", text: $webhookURL)
                        AdaptiveButtonRow {
                            TextField("Profile name", text: $actionProfileDraft.name)
                            Button("Save Profile") {
                                saveCurrentActionProfile()
                            }
                            .disabled(actionProfileDraft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || webhookURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            if let selectedActionProfileID {
                                Button("Delete Profile") {
                                    store.removeActionProfile(id: selectedActionProfileID)
                                    self.selectedActionProfileID = nil
                                }
                                .disabled(store.actionProfiles.first(where: { $0.id == selectedActionProfileID }) == nil)
                            }
                        }
                    }
                    AdaptiveButtonRow {
                        Button("Run Action on Result") {
                            Task { @MainActor in
                                await performResultAction()
                            }
                        }
                        .disabled(resultAction == .none || resultText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(24)
        .onAppear {
            workflow = store.settings.visualDefaults.workflow
            modelID = store.settings.visualDefaults.modelId
            prompt = store.settings.visualDefaults.prompt
            maxTokens = String(store.settings.visualDefaults.maxTokens)
            selectedAudioInput = store.settings.visualDefaults.audioInputPath.map { URL(fileURLWithPath: $0) }
            kvBits = store.settings.visualDefaults.kvBits.map { String($0) } ?? ""
            kvQuantScheme = store.settings.visualDefaults.kvQuantScheme
            narrationModelID = store.settings.ttsDefaults.modelId
            narrationLanguageCode = store.settings.preferredReaderLanguage
            narrationVoiceIdentifier = store.settings.ttsDefaults.voiceIdentifier ?? ""
            systemVoices = availableSystemVoices()
            selectedWebhookTemplateID = store.settings.savedWebhookTemplates.first?.id
            if let latest = store.latestVisualAnalysis {
                resultText = latest.text
                outputPath = latest.outputPath
                renderedInputPath = latest.renderedInputPath
                jsonPath = latest.jsonPath
                statusLogPath = latest.statusLogPath
            }
            narrationPath = store.latestVisualNarrationPath
        }
        .onChange(of: workflow) { _, _ in
            applyWorkflowDefaults(resetPromptOnly: false)
        }
        .onChange(of: modelID) { _, newValue in
            if let preset = visualPresets.first(where: { $0.id == newValue }) {
                if !preset.supportsAudio {
                    selectedAudioInput = nil
                }
                if !preset.supportsTurboQuant {
                    kvBits = ""
                    kvQuantScheme = .uniform
                }
            }
        }
        .onChange(of: selectedWebhookTemplateID) { _, newValue in
            if let template = store.settings.savedWebhookTemplates.first(where: { $0.id == newValue }), !template.url.isEmpty {
                webhookURL = template.url
            }
        }
        .onChange(of: selectedActionProfileID) { _, newValue in
            guard let id = newValue,
                  let profile = store.actionProfiles.first(where: { $0.id == id }),
                  let route = profile.routes.first(where: { $0.actionType == "webhook" }) else { return }
            actionProfileDraft.id = profile.id
            actionProfileDraft.name = profile.name
            actionProfileDraft.payload = route.payload
            webhookURL = route.payload
            selectedWebhookTemplateID = nil
        }
        .onDisappear {
            statusPollingTask?.cancel()
        }
    }

    private func pickVisualInput() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .pdf]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK {
            selectedInput = panel.url
        }
    }

    private func pickAudioContext() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK {
            selectedAudioInput = panel.url
        }
    }

    private func captureScreenshot() {
        isCapturingScreenshot = true
        Task { @MainActor in
            do {
                selectedInput = try await store.captureInteractiveScreenshot()
                if workflow == .general {
                    workflow = .screenSummary
                    prompt = workflow.defaultPrompt
                }
            } catch {
                store.latestError = error.localizedDescription
            }
            isCapturingScreenshot = false
        }
    }

    private func captureFrontWindow() {
        isCapturingScreenshot = true
        Task { @MainActor in
            do {
                selectedInput = try await store.captureFrontmostWindowScreenshot()
                if workflow == .general {
                    workflow = .screenSummary
                }
                applyWorkflowDefaults(resetPromptOnly: true)
            } catch {
                store.latestError = error.localizedDescription
            }
            isCapturingScreenshot = false
        }
    }

    private func captureFullScreen() {
        isCapturingScreenshot = true
        Task { @MainActor in
            do {
                selectedInput = try await store.captureFullScreenScreenshot()
                if workflow == .general {
                    workflow = .screenSummary
                }
                applyWorkflowDefaults(resetPromptOnly: true)
            } catch {
                store.latestError = error.localizedDescription
            }
            isCapturingScreenshot = false
        }
    }

    private func runAnalysis() {
        guard let selectedInput, let tokenCount = Int(maxTokens.trimmingCharacters(in: .whitespacesAndNewlines)) else { return }
        isRunning = true
        analysisStatusText = "Preparing visual analysis..."
        let logURL = URL(fileURLWithPath: store.settings.outputFolderPath, isDirectory: true)
            .appendingPathComponent("visual-analysis-status-\(UUID().uuidString)")
            .appendingPathExtension("log")
        statusLogPath = logURL.path
        startPollingStatusLog(at: logURL)
        let resolvedKVBits = Double(kvBits.trimmingCharacters(in: .whitespacesAndNewlines))
        Task { @MainActor in
            do {
                store.settings.visualDefaults = VisualAnalysisOptions(
                    modelId: modelID,
                    workflow: workflow,
                    prompt: prompt,
                    maxTokens: tokenCount,
                    audioInputPath: selectedAudioInput?.path,
                    kvBits: resolvedKVBits,
                    kvQuantScheme: kvQuantScheme,
                    processAllPDFPages: store.settings.visualDefaults.processAllPDFPages,
                    pythonRepoPath: store.settings.pythonMLXVLMRepoPath
                )
                store.saveSettings()
                let result = try await store.runVisualAnalysis(
                    inputURL: selectedInput,
                    options: VisualAnalysisOptions(
                        modelId: modelID,
                        workflow: workflow,
                        prompt: combinedPrompt(),
                        maxTokens: tokenCount,
                        audioInputPath: selectedAudioInput?.path,
                        kvBits: resolvedKVBits,
                        kvQuantScheme: kvQuantScheme,
                        processAllPDFPages: store.settings.visualDefaults.processAllPDFPages,
                        pythonRepoPath: store.settings.pythonMLXVLMRepoPath
                    ),
                    statusLogPath: logURL.path,
                    progress: { message in
                        Task { @MainActor in
                            analysisStatusText = message
                        }
                    }
                )
                resultText = result.text
                outputPath = result.outputPath
                renderedInputPath = result.renderedInputPath
                jsonPath = result.jsonPath
                statusLogPath = result.statusLogPath
                analysisStatusText = "Analysis completed."
            } catch {
                store.latestError = error.localizedDescription
                analysisStatusText = "Analysis failed."
            }
            statusPollingTask?.cancel()
            isRunning = false
        }
    }

    private func startPollingStatusLog(at url: URL) {
        statusPollingTask?.cancel()
        statusPollingTask = Task {
            while !Task.isCancelled {
                if let content = try? String(contentsOf: url, encoding: .utf8) {
                    let lastLine = latestStatusLine(in: content)
                    if let lastLine, !lastLine.isEmpty {
                        await MainActor.run {
                            analysisStatusText = lastLine
                        }
                    }
                }
                try? await Task.sleep(for: .milliseconds(700))
            }
        }
    }

    private func narrateResult() {
        let text = resultText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isNarrating = true
        Task { @MainActor in
            do {
                let path = try await store.runTextToAudio(
                    text: text,
                    options: TTSOptions(
                        modelId: narrationModelID,
                        outputFormat: "wav",
                        voiceIdentifier: narrationVoiceIdentifier.isEmpty ? nil : narrationVoiceIdentifier,
                        languageCode: narrationLanguageCode,
                        backend: .automatic,
                        pythonRepoPath: store.settings.pythonMLXRepoPath
                    )
                )
                narrationPath = path
                toggleNarrationPlayback(path: path)
            } catch {
                store.latestError = error.localizedDescription
            }
            isNarrating = false
        }
    }

    private func toggleNarrationPlayback(path: String) {
        if narrationPlayer?.isPlaying == true {
            narrationPlayer?.stop()
            narrationPlayer = nil
            return
        }

        do {
            let player = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: path))
            narrationPlayer = player
            player.prepareToPlay()
            player.play()
        } catch {
            store.latestError = error.localizedDescription
            narrationPlayer = nil
        }
    }

    private var sortedVisualPresets: [VisualPreset] {
        switch workflow {
        case .ocrPlainText, .ocrStructured, .ocrReceipt, .ocrForm, .ocrTable:
            return visualPresets.sorted { lhs, rhs in
                if lhs.bestForOCR != rhs.bestForOCR {
                    return lhs.bestForOCR && !rhs.bestForOCR
                }
                return lhs.title < rhs.title
            }
        case .general, .screenSummary:
            return visualPresets
        }
    }

    private func applyWorkflowDefaults(resetPromptOnly: Bool) {
        prompt = workflow.defaultPrompt
        switch workflow {
        case .ocrPlainText:
            maxTokens = "1200"
        case .ocrStructured, .ocrReceipt, .ocrForm:
            maxTokens = "1500"
        case .ocrTable:
            maxTokens = "1800"
        case .general, .screenSummary:
            maxTokens = "300"
        }
        if !resetPromptOnly {
            if workflow == .ocrPlainText || workflow == .ocrStructured || workflow == .ocrReceipt || workflow == .ocrForm || workflow == .ocrTable,
               let ocrPreset = visualPresets.first(where: { $0.bestForOCR }) {
                modelID = ocrPreset.id
            } else if workflow == .screenSummary,
                      let screenPreset = visualPresets.first(where: { $0.id == "mlx-community/granite-4.0-vision-2b-4bit" }) {
                modelID = screenPreset.id
            }
        }
    }

    private func combinedPrompt() -> String {
        let context = additionalContext.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !context.isEmpty else { return prompt }
        return "\(prompt)\n\nAdditional transcript/audio context:\n\(context)"
    }

    private func performResultAction() async {
        let text = resultText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        switch resultAction {
        case .none:
            break
        case .clipboard:
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
        case .typeToFrontmost:
            if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.localvoiceutility.desktop" {
                store.latestError = "Type into Front App is ignored while Local Voice Utility is frontmost. Switch to the target app first."
                return
            }
            _ = runProcess("/usr/bin/osascript", ["-e", appleScriptForKeystroke(text)])
        case .webhook:
            guard let url = URL(string: webhookURL),
                  let body = try? JSONSerialization.data(withJSONObject: ["text": text]) else {
                store.latestError = "Invalid webhook URL."
                return
            }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
            do {
                _ = try await URLSession.shared.data(for: request)
            } catch {
                store.latestError = error.localizedDescription
            }
        }
    }

    private func saveCurrentActionProfile() {
        let name = actionProfileDraft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let payload = webhookURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !payload.isEmpty else { return }
        let route = ActionRoute(pattern: "visual-analysis", actionType: "webhook", payload: payload)
        let profile = ActionProfile(id: actionProfileDraft.id ?? UUID(), name: name, confirmationPolicy: .never, routes: [route])
        store.upsertActionProfile(profile)
        actionProfileDraft.id = profile.id
        selectedActionProfileID = profile.id
    }
}

struct SegmentationScreen: View {
    @EnvironmentObject private var store: AppStore
    @State private var selectedInput: URL?
    @State private var task: SamTaskMode = .segment
    @State private var modelID = segmentationPresets.first?.id ?? "mlx-community/sam3.1-bf16"
    @State private var prompt = "a person"
    @State private var boxes = ""
    @State private var threshold = "0.3"
    @State private var showBoxes = true
    @State private var isRunning = false
    @State private var summaryText = ""
    @State private var outputImagePath: String?
    @State private var jsonPath: String?
    @State private var statusLogPath: String?
    @State private var runStatusText = ""
    @State private var statusPollingTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Detection & Segmentation")
                .font(.title2.bold())
            Text("Use SAM 3 / 3.1 for object detection or segmentation, with optional box prompts.")
                .foregroundStyle(.secondary)

            Form {
                Section("Input") {
                    Text(selectedInput?.path ?? "No image selected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack {
                        Button("Select Image") {
                            pickImage()
                        }
                        if let selectedInput {
                            Button("Reveal Image") {
                                NSWorkspace.shared.activateFileViewerSelecting([selectedInput])
                            }
                        }
                    }
                }

                Section("Model") {
                    Picker("Preset", selection: $modelID) {
                        ForEach(segmentationPresets) { preset in
                            Text("\(preset.title) — \(preset.summary)").tag(preset.id)
                        }
                    }
                    TextField("Model ID", text: $modelID)
                    Picker("Task", selection: $task) {
                        ForEach(SamTaskMode.allCases, id: \.self) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    TextField("Prompt", text: $prompt)
                    TextField("Box prompts (x1,y1,x2,y2;...)", text: $boxes)
                    TextField("Threshold", text: $threshold)
                    Toggle("Show boxes in output", isOn: $showBoxes)
                    Text("Use box prompts to constrain segmentation to specific regions. Example: `10,50,300,400`")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if modelID == "facebook/sam3" {
                        Text("`facebook/sam3` is gated on Hugging Face. If access fails, switch to `mlx-community/sam3.1-bf16` or configure `HF_TOKEN`.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            AdaptiveButtonRow {
                Button(isRunning ? "Running..." : "Run") {
                    runSegmentation()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isRunning || selectedInput == nil)

                if let outputImagePath {
                    Button("Open Output") {
                        NSWorkspace.shared.open(URL(fileURLWithPath: outputImagePath))
                    }
                    Button("Reveal Output") {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: outputImagePath)])
                    }
                }
                if let jsonPath {
                    Button("Open JSON") {
                        NSWorkspace.shared.open(URL(fileURLWithPath: jsonPath))
                    }
                }
                if let statusLogPath {
                    Button("Open Status Log") {
                        NSWorkspace.shared.open(URL(fileURLWithPath: statusLogPath))
                    }
                }
                if store.latestVisualAnalysis != nil {
                    Button("Ask About Result") {
                        store.askAboutLatestVisualResult()
                    }
                }
            }

            Text("Summary")
                .font(.headline)
            if isRunning || !runStatusText.isEmpty {
                GroupBox("Run Status") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(runStatusText.isEmpty ? "Preparing segmentation..." : runStatusText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if isRunning {
                            ProgressView()
                        }
                    }
                    .padding(.top, 4)
                }
            }
            ScrollView {
                Text(summaryText.isEmpty ? "No result yet." : summaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity)
        }
        .padding(24)
        .onDisappear {
            statusPollingTask?.cancel()
        }
    }

    private func pickImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK {
            selectedInput = panel.url
        }
    }

    private func runSegmentation() {
        guard let selectedInput,
              let resolvedThreshold = Double(threshold.trimmingCharacters(in: .whitespacesAndNewlines)) else { return }
        isRunning = true
        summaryText = ""
        runStatusText = "Preparing segmentation..."
        let logURL = URL(fileURLWithPath: store.settings.outputFolderPath, isDirectory: true)
            .appendingPathComponent("segmentation-status-\(UUID().uuidString)")
            .appendingPathExtension("log")
        statusLogPath = logURL.path
        startPollingStatusLog(at: logURL)
        Task { @MainActor in
            do {
                let result = try await PythonMLXVLMBridge.runSegmentation(
                    inputURL: selectedInput,
                    task: task,
                    modelId: modelID,
                    prompt: prompt.trimmingCharacters(in: .whitespacesAndNewlines),
                    boxes: boxes.trimmingCharacters(in: .whitespacesAndNewlines),
                    threshold: resolvedThreshold,
                    showBoxes: showBoxes,
                    pythonRepoPath: store.settings.pythonMLXVLMRepoPath,
                    outputDirectory: URL(fileURLWithPath: store.settings.outputFolderPath, isDirectory: true),
                    statusLogPath: logURL.path,
                    progress: { message in
                        Task { @MainActor in
                            runStatusText = message
                        }
                    }
                )
                summaryText = result.summaryText
                outputImagePath = result.outputImagePath
                jsonPath = result.jsonPath
                statusLogPath = result.statusLogPath
                runStatusText = "Segmentation completed."
            } catch {
                store.latestError = error.localizedDescription
                runStatusText = "Segmentation failed."
            }
            statusPollingTask?.cancel()
            isRunning = false
        }
    }

    private func startPollingStatusLog(at url: URL) {
        statusPollingTask?.cancel()
        statusPollingTask = Task {
            while !Task.isCancelled {
                if let content = try? String(contentsOf: url, encoding: .utf8) {
                    let lastLine = latestStatusLine(in: content)
                    if let lastLine, !lastLine.isEmpty {
                        await MainActor.run {
                            runStatusText = lastLine
                        }
                    }
                }
                try? await Task.sleep(for: .milliseconds(700))
            }
        }
    }
}

struct LocalAssistantScreen: View {
    @EnvironmentObject private var store: AppStore
    @State private var modelID = LMOptions().modelId
    @State private var systemPrompt = LMOptions().systemPrompt
    @State private var maxTokens = String(LMOptions().maxTokens)
    @State private var temperature = String(LMOptions().temperature)
    @State private var backend = LMOptions().backend
    @State private var draftPrompt = ""
    @State private var pinnedContextTitle = ""
    @State private var pinnedContext = ""
    @State private var messages: [AssistantMessage] = []
    @State private var isRunning = false
    @State private var runStatus = ""

    var body: some View {
        ScreenScrollView(maxWidth: 1080) {
            Text("Local Assistant")
                .font(.title2.bold())

            ScreenSection(title: "Model") {
                Picker("Preset", selection: $modelID) {
                    ForEach(TextModelCatalog.presets) { preset in
                        Text("\(preset.title) (\(preset.backend.rawValue)) — \(preset.summary)").tag(preset.id)
                    }
                }
                TextField("Model ID", text: $modelID)
                Picker("Backend", selection: $backend) {
                    ForEach(InferenceBackend.allCases, id: \.self) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                TextField("Max tokens", text: $maxTokens)
                TextField("Temperature", text: $temperature)
                TextField("System prompt", text: $systemPrompt, axis: .vertical)
                    .lineLimit(3, reservesSpace: true)
            }

            if !pinnedContext.isEmpty {
                ScreenSection(title: pinnedContextTitle.isEmpty ? "Context" : pinnedContextTitle) {
                    ScrollView {
                        Text(pinnedContext)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(minHeight: 120, maxHeight: 220)
                    AdaptiveButtonRow {
                        Button("Clear Context") {
                            pinnedContextTitle = ""
                            pinnedContext = ""
                        }
                        Button("Copy Context") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(pinnedContext, forType: .string)
                        }
                    }
                }
            }

            ScreenSection(title: "Conversation") {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if messages.isEmpty {
                            Text("No messages yet.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(messages) { message in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(message.role == .user ? "You" : "Assistant")
                                        .font(.caption.bold())
                                        .foregroundStyle(.secondary)
                                    Text(message.text)
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 260, maxHeight: 420)
                if isRunning || !runStatus.isEmpty {
                    Text(runStatus)
                        .font(.caption)
                        .foregroundStyle(isRunning ? .secondary : .secondary)
                }
            }

            ScreenSection(title: "Prompt") {
                TextField("Ask the local assistant", text: $draftPrompt, axis: .vertical)
                    .lineLimit(4, reservesSpace: true)
                AdaptiveButtonRow {
                    Button("Send") {
                        sendPrompt()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isRunning || draftPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button("Clear Conversation") {
                        clearConversation()
                    }
                    .disabled(isRunning && messages.isEmpty)
                }
            }
        }
        .onAppear {
            modelID = store.settings.lmDefaults.modelId
            systemPrompt = store.settings.lmDefaults.systemPrompt
            maxTokens = String(store.settings.lmDefaults.maxTokens)
            temperature = String(store.settings.lmDefaults.temperature)
            backend = store.settings.lmDefaults.backend
            applyPendingSeedIfNeeded()
        }
        .onChange(of: modelID) { _, newValue in
            if let preset = TextModelCatalog.preset(for: newValue) {
                backend = preset.backend
            }
        }
    }

    private func applyPendingSeedIfNeeded() {
        guard let seed = store.consumeAssistantSeed() else { return }
        pinnedContextTitle = seed.title
        pinnedContext = seed.context
        if draftPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            draftPrompt = seed.suggestedPrompt
        }
    }

    private func sendPrompt() {
        guard let resolvedMaxTokens = Int(maxTokens.trimmingCharacters(in: .whitespacesAndNewlines)),
              let resolvedTemperature = Double(temperature.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            store.latestError = "Enter numeric values for max tokens and temperature."
            return
        }

        let prompt = draftPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        messages.append(AssistantMessage(role: .user, text: prompt))
        messages.append(AssistantMessage(role: .assistant, text: ""))
        draftPrompt = ""
        isRunning = true
        runStatus = "Preparing local model..."

        let assistantIndex = messages.count - 1
        let options = LMOptions(
            modelId: modelID,
            systemPrompt: systemPrompt,
            maxTokens: resolvedMaxTokens,
            temperature: resolvedTemperature,
            backend: backend
        )
        store.settings.lmDefaults = options
        store.saveSettings()

        Task {
            do {
                let response = try await store.sendAssistantPrompt(
                    prompt: prompt,
                    context: pinnedContext.isEmpty ? nil : pinnedContext,
                    options: options,
                    progress: { message in
                        Task { @MainActor in
                            runStatus = message
                        }
                    },
                    onChunk: { partial in
                        Task { @MainActor in
                            messages[assistantIndex] = AssistantMessage(role: .assistant, text: partial)
                        }
                    }
                )
                await MainActor.run {
                    messages[assistantIndex] = AssistantMessage(role: .assistant, text: response)
                    runStatus = "Response completed."
                    isRunning = false
                }
            } catch {
                await MainActor.run {
                    messages.removeLast()
                    store.latestError = error.localizedDescription
                    runStatus = "Assistant failed."
                    isRunning = false
                }
            }
        }
    }

    private func clearConversation() {
        messages.removeAll()
        runStatus = ""
        Task {
            await store.resetAssistantConversation()
        }
    }
}

struct ScannedPDFToAudioScreen: View {
    @EnvironmentObject private var store: AppStore
    @State private var selectedPDF: URL?
    @State private var selectedPDFs: [URL] = []
    @State private var batchMode = false
    @State private var isRunning = false
    @State private var ocrWorkflow: VisualAnalysisWorkflow = .ocrPlainText
    @State private var ocrModelID = "mlx-community/falcon-ocr-3b-4bit"
    @State private var readModelID = TTSOptions().modelId
    @State private var readLanguageCode = TTSOptions().languageCode
    @State private var readVoiceIdentifier = ""
    @State private var systemVoices: [VoiceOption] = []
    @State private var extractedText = ""
    @State private var transcriptPath: String?
    @State private var audioPath: String?
    @State private var audioPlayer: AVAudioPlayer?
    @State private var batchResults: [BatchScannedPDFResult] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Scanned PDF -> Audio")
                .font(.title2.bold())
            Text("Run OCR across all pages of a scanned PDF, then generate narration in one pass.")
                .foregroundStyle(.secondary)

            Form {
                Section("Input") {
                    Toggle("Batch mode", isOn: $batchMode)
                    Text(batchMode ? batchInputSummary : (selectedPDF?.path ?? "No PDF selected"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack {
                        Button(batchMode ? "Select PDFs" : "Select PDF") {
                            let panel = NSOpenPanel()
                            panel.allowedContentTypes = [.pdf]
                            panel.allowsMultipleSelection = batchMode
                            if panel.runModal() == .OK {
                                if batchMode {
                                    selectedPDFs = panel.urls
                                    selectedPDF = selectedPDFs.first
                                } else {
                                    selectedPDF = panel.url
                                    selectedPDFs = panel.url.map { [$0] } ?? []
                                }
                            }
                        }
                        if batchMode, !selectedPDFs.isEmpty {
                            Button("Reveal PDFs") {
                                NSWorkspace.shared.activateFileViewerSelecting(selectedPDFs)
                            }
                        } else if let selectedPDF {
                            Button("Reveal PDF") {
                                NSWorkspace.shared.activateFileViewerSelecting([selectedPDF])
                            }
                        }
                    }
                }

                Section("OCR") {
                    Picker("OCR mode", selection: $ocrWorkflow) {
                        Text("Plain text").tag(VisualAnalysisWorkflow.ocrPlainText)
                        Text("Structured").tag(VisualAnalysisWorkflow.ocrStructured)
                    }
                    Picker("OCR model", selection: $ocrModelID) {
                        ForEach(visualPresets.filter(\.bestForOCR)) { preset in
                            Text("\(preset.title) — \(preset.summary)").tag(preset.id)
                        }
                    }
                }

                Section("Reader") {
                    Picker("Reader model", selection: $readModelID) {
                        ForEach(SpeechCatalog.ttsModels(for: .documentReader)) { preset in
                            Text(presetMenuLabel(preset)).tag(preset.id)
                        }
                    }
                    Picker("Reader language", selection: $readLanguageCode) {
                        ForEach(SpeechCatalog.languageOptions(for: SpeechCatalog.preset(for: readModelID), allowAutoDetect: false)) { language in
                            Text(language.label).tag(language.code)
                        }
                    }
                    Picker("Reader voice", selection: $readVoiceIdentifier) {
                        Text("System Default").tag("")
                        ForEach(systemVoices, id: \.id) { voice in
                            Text(voice.label).tag(voice.id)
                        }
                    }
                }
            }

            AdaptiveButtonRow {
                Button(isRunning ? "Processing..." : (batchMode ? "Process Batch" : "Extract OCR and Generate Audio")) {
                    runScannedPDFWorkflow()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isRunning || activePDFInputs.isEmpty)

                if let transcriptPath {
                    Button("Open OCR Text") {
                        NSWorkspace.shared.open(URL(fileURLWithPath: transcriptPath))
                    }
                    Button("Ask About OCR Text") {
                        store.askAboutFile(
                            path: transcriptPath,
                            title: "Scanned PDF OCR result",
                            suggestedPrompt: "Summarize this scanned document and identify the key points, entities, and next actions."
                        )
                    }
                }
                if let audioPath {
                    Button(audioPlayer?.isPlaying == true ? "Stop Audio" : "Play Audio") {
                        toggleAudioPlayback(path: audioPath)
                    }
                    Button("Reveal Audio") {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: audioPath)])
                    }
                }
            }

            Text("OCR Output")
                .font(.headline)
            ScrollView {
                Text(extractedText.isEmpty ? "No OCR output yet." : extractedText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity)

            if batchMode, !batchResults.isEmpty {
                GroupBox("Batch Results") {
                    List(batchResults) { result in
                        HStack {
                            Text(URL(fileURLWithPath: result.pdfPath).lastPathComponent)
                            Spacer()
                            Button("OCR Text") {
                                NSWorkspace.shared.open(URL(fileURLWithPath: result.transcriptPath))
                            }
                            Button("Ask") {
                                store.askAboutFile(
                                    path: result.transcriptPath,
                                    title: URL(fileURLWithPath: result.pdfPath).lastPathComponent,
                                    suggestedPrompt: "Summarize this scanned document and answer questions using the OCR text."
                                )
                            }
                            if let jsonPath = result.jsonPath {
                                Button("JSON") {
                                    NSWorkspace.shared.open(URL(fileURLWithPath: jsonPath))
                                }
                            }
                            Button("Audio") {
                                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: result.audioPath)])
                            }
                        }
                    }
                    .frame(minHeight: 160)
                }
            }
        }
        .padding(24)
        .onAppear {
            systemVoices = availableSystemVoices()
            readLanguageCode = store.settings.preferredReaderLanguage
            readVoiceIdentifier = store.settings.ttsDefaults.voiceIdentifier ?? ""
        }
    }

    private func runScannedPDFWorkflow() {
        let inputs = activePDFInputs
        guard !inputs.isEmpty else { return }
        isRunning = true
        batchResults = []
        Task { @MainActor in
            defer { isRunning = false }
            do {
                for input in inputs {
                    let analysis = try await store.runVisualAnalysis(
                        inputURL: input,
                        options: VisualAnalysisOptions(
                            modelId: ocrModelID,
                            workflow: ocrWorkflow,
                            prompt: ocrWorkflow.defaultPrompt,
                            maxTokens: ocrWorkflow == .ocrStructured ? 1500 : 1200,
                            processAllPDFPages: true,
                            pythonRepoPath: store.settings.pythonMLXVLMRepoPath
                        )
                    )
                    let generatedAudioPath = try await store.runTextToAudio(
                        text: analysis.text,
                        options: TTSOptions(
                            modelId: readModelID,
                            outputFormat: "wav",
                            voiceIdentifier: readVoiceIdentifier.isEmpty ? nil : readVoiceIdentifier,
                            languageCode: readLanguageCode,
                            backend: .automatic,
                            pythonRepoPath: store.settings.pythonMLXRepoPath
                        )
                    )

                    extractedText = analysis.text
                    transcriptPath = analysis.outputPath
                    audioPath = generatedAudioPath
                    batchResults.append(
                        BatchScannedPDFResult(
                            pdfPath: input.path,
                            transcriptPath: analysis.outputPath,
                            jsonPath: analysis.jsonPath,
                            audioPath: generatedAudioPath
                        )
                    )
                }

                if !batchMode, let audioPath {
                    toggleAudioPlayback(path: audioPath)
                }
            } catch {
                store.latestError = error.localizedDescription
            }
        }
    }

    private func toggleAudioPlayback(path: String) {
        if audioPlayer?.isPlaying == true {
            audioPlayer?.stop()
            audioPlayer = nil
            return
        }
        do {
            let player = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: path))
            audioPlayer = player
            player.prepareToPlay()
            player.play()
        } catch {
            store.latestError = error.localizedDescription
            audioPlayer = nil
        }
    }

    private var activePDFInputs: [URL] {
        batchMode ? selectedPDFs : (selectedPDF.map { [$0] } ?? [])
    }

    private var batchInputSummary: String {
        if selectedPDFs.isEmpty { return "No PDFs selected" }
        if selectedPDFs.count == 1 { return selectedPDFs[0].path }
        return "\(selectedPDFs.count) PDFs selected"
    }
}

struct PDFToAudioScreen: View {
    @EnvironmentObject private var store: AppStore
    @State private var selectedPDF: URL?
    @State private var modelID = TTSOptions().modelId
    @State private var chunkMode: TTSOptions.ChunkMode = .paragraph
    @State private var maxChunkChars = "750"
    @State private var selectedVoiceIdentifier = ""
    @State private var languageCode = TTSOptions().languageCode
    @State private var backend: InferenceBackend = TTSOptions().backend
    @State private var systemVoices: [VoiceOption] = []
    @State private var previewSynth: NSSpeechSynthesizer?

    var body: some View {
        ScreenScrollView {
            Text("PDF to Audio")
                .font(.title2.bold())
            ScreenSection(title: "Input") {
                Text(selectedPDF?.path ?? "No file selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Select PDF") {
                    pickPDF()
                }
            }
            ScreenSection(title: "Generation") {
                Picker("Preset", selection: $modelID) {
                    ForEach(SpeechCatalog.ttsModels(for: .documentReader)) { preset in
                        Text(presetMenuLabel(preset)).tag(preset.id)
                    }
                }
                TextField("TTS model", text: $modelID)
                Picker("Backend", selection: $backend) {
                    ForEach(InferenceBackend.allCases, id: \.self) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                Picker("Language", selection: $languageCode) {
                    ForEach(SpeechCatalog.languageOptions(for: SpeechCatalog.preset(for: modelID), allowAutoDetect: false)) { language in
                        Text(language.label).tag(language.code)
                    }
                }
                presetDetailsView(for: SpeechCatalog.preset(for: modelID))
                Picker("Chunk mode", selection: $chunkMode) {
                    ForEach(TTSOptions.ChunkMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue)
                    }
                }
                TextField("Max chunk chars", text: $maxChunkChars)
                Picker("Reader voice", selection: $selectedVoiceIdentifier) {
                    Text("System Default").tag("")
                    ForEach(systemVoices, id: \.id) { voice in
                        Text(voice.label).tag(voice.id)
                    }
                }
                AdaptiveButtonRow {
                    Button("Preview Voice") {
                        previewSelectedVoice()
                    }
                    .disabled(systemVoices.isEmpty)
                    Text(voiceLabel(for: selectedVoiceIdentifier))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Button("Run PDF to Audio") {
                guard let selectedPDF,
                      let chunk = Int(maxChunkChars) else { return }
                store.runPDFToAudio(
                    inputURL: selectedPDF,
                    options: TTSOptions(
                        modelId: modelID,
                        chunkMode: chunkMode,
                        maxChunkCharacters: chunk,
                        voiceIdentifier: selectedVoiceIdentifier.isEmpty ? nil : selectedVoiceIdentifier,
                        languageCode: languageCode,
                        backend: backend
                    )
                )
                store.selectedScreen = .library
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedPDF == nil)
        }
        .onAppear {
            systemVoices = availableSystemVoices()
            selectedVoiceIdentifier = resolveDefaultVoice(for: modelID, settings: store.settings)
            languageCode = store.settings.preferredReaderLanguage
            backend = store.settings.ttsDefaults.backend
        }
        .onChange(of: modelID) { _, newValue in
            selectedVoiceIdentifier = resolveDefaultVoice(for: newValue, settings: store.settings)
            if let preset = SpeechCatalog.preset(for: newValue) {
                backend = preset.backend
                if let firstLanguage = SpeechCatalog.languageOptions(for: preset, allowAutoDetect: false).first?.code {
                    languageCode = firstLanguage
                }
            }
        }
    }

    private func pickPDF() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK {
            selectedPDF = panel.url
        }
    }

    private func previewSelectedVoice() {
        let synth = NSSpeechSynthesizer()
        if !selectedVoiceIdentifier.isEmpty {
            _ = synth.setVoice(NSSpeechSynthesizer.VoiceName(rawValue: selectedVoiceIdentifier))
        }
        synth.startSpeaking("Previewing selected reader voice for PDF to audio.")
        previewSynth = synth
    }

    private func voiceLabel(for identifier: String) -> String {
        if identifier.isEmpty { return "System Default" }
        return systemVoices.first(where: { $0.id == identifier })?.label ?? identifier
    }
}

struct URLToAudioScreen: View {
    @EnvironmentObject private var store: AppStore
    @State private var urlString = ""
    @State private var modelID = TTSOptions().modelId
    @State private var maxChunkChars = "750"
    @State private var selectedVoiceIdentifier = ""
    @State private var languageCode = TTSOptions().languageCode
    @State private var backend: InferenceBackend = TTSOptions().backend
    @State private var systemVoices: [VoiceOption] = []
    @State private var extractedPreview = ""
    @State private var isFetching = false
    @State private var previewSynth: NSSpeechSynthesizer?

    var body: some View {
        ScreenScrollView {
            Text("URL to Audio")
                .font(.title2.bold())
            ScreenSection(title: "URL") {
                TextField("https://example.com/article", text: $urlString)
                AdaptiveButtonRow {
                    Button(isFetching ? "Fetching..." : "Fetch Preview") {
                        fetchPreview()
                    }
                    .disabled(isFetching || urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("Open in Browser") {
                        guard let url = URL(string: urlString) else { return }
                        NSWorkspace.shared.open(url)
                    }
                    .disabled(URL(string: urlString) == nil)
                }
            }

            ScreenSection(title: "Generation") {
                Picker("Preset", selection: $modelID) {
                    ForEach(SpeechCatalog.ttsModels(for: .documentReader)) { preset in
                        Text(presetMenuLabel(preset)).tag(preset.id)
                    }
                }
                TextField("TTS model", text: $modelID)
                Picker("Backend", selection: $backend) {
                    ForEach(InferenceBackend.allCases, id: \.self) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                Picker("Language", selection: $languageCode) {
                    ForEach(SpeechCatalog.languageOptions(for: SpeechCatalog.preset(for: modelID), allowAutoDetect: false)) { language in
                        Text(language.label).tag(language.code)
                    }
                }
                presetDetailsView(for: SpeechCatalog.preset(for: modelID))
                TextField("Max chunk chars", text: $maxChunkChars)
                Picker("Reader voice", selection: $selectedVoiceIdentifier) {
                    Text("System Default").tag("")
                    ForEach(systemVoices, id: \.id) { voice in
                        Text(voice.label).tag(voice.id)
                    }
                }
                Button("Preview Voice") {
                    previewSelectedVoice()
                }
                .disabled(systemVoices.isEmpty)
            }

            ScreenSection(title: "Extracted preview") {
                ScrollView {
                    Text(extractedPreview.isEmpty ? "No preview yet." : extractedPreview)
                        .font(.caption)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                }
                .frame(minHeight: 120)
            }

            Button("Run URL to Audio") {
                guard let chunk = Int(maxChunkChars) else { return }
                store.runURLToAudio(
                    urlString: urlString.trimmingCharacters(in: .whitespacesAndNewlines),
                    options: TTSOptions(
                        modelId: modelID,
                        chunkMode: .paragraph,
                        maxChunkCharacters: chunk,
                        voiceIdentifier: selectedVoiceIdentifier.isEmpty ? nil : selectedVoiceIdentifier,
                        languageCode: languageCode,
                        backend: backend
                    )
                )
                store.selectedScreen = .library
            }
            .buttonStyle(.borderedProminent)
            .disabled(URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)) == nil)
        }
        .onAppear {
            systemVoices = availableSystemVoices()
            selectedVoiceIdentifier = resolveDefaultVoice(for: modelID, settings: store.settings)
            languageCode = store.settings.preferredReaderLanguage
            backend = store.settings.ttsDefaults.backend
        }
        .onChange(of: modelID) { _, newValue in
            selectedVoiceIdentifier = resolveDefaultVoice(for: newValue, settings: store.settings)
            if let preset = SpeechCatalog.preset(for: newValue) {
                backend = preset.backend
                if let firstLanguage = SpeechCatalog.languageOptions(for: preset, allowAutoDetect: false).first?.code {
                    languageCode = firstLanguage
                }
            }
        }
    }

    private func fetchPreview() {
        let current = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !current.isEmpty else { return }
        isFetching = true
        extractedPreview = ""

        Task {
            do {
                let text = try await WebTextExtractor.extract(from: current)
                await MainActor.run {
                    extractedPreview = String(text.prefix(2000))
                    isFetching = false
                }
            } catch {
                await MainActor.run {
                    store.latestError = error.localizedDescription
                    isFetching = false
                }
            }
        }
    }

    private func previewSelectedVoice() {
        let synth = NSSpeechSynthesizer()
        if !selectedVoiceIdentifier.isEmpty {
            _ = synth.setVoice(NSSpeechSynthesizer.VoiceName(rawValue: selectedVoiceIdentifier))
        }
        synth.startSpeaking("Previewing selected reader voice for URL to audio.")
        previewSynth = synth
    }
}

struct TranscribeScreen: View {
    @EnvironmentObject private var store: AppStore
    @State private var selectedMedia: URL?
    @State private var modelID = STTOptions().modelId
    @State private var includeTimestamps = false
    @State private var useVAD = false
    @State private var languageCode = STTOptions().languageCode
    @State private var backend: InferenceBackend = STTOptions().backend
    @State private var enhancementMode: SpeechEnhancementMode = .off

    var body: some View {
        ScreenScrollView {
            Text("Transcribe")
                .font(.title2.bold())
            ScreenSection(title: "Input") {
                Text(selectedMedia?.path ?? "No file selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Select Audio/Video") {
                    pickMedia()
                }
            }
            ScreenSection(title: "Transcription") {
                Picker("Preset", selection: $modelID) {
                    ForEach(SpeechCatalog.sttModels(for: .fileTranscription)) { preset in
                        Text(presetMenuLabel(preset)).tag(preset.id)
                    }
                }
                TextField("STT model", text: $modelID)
                Picker("Backend", selection: $backend) {
                    ForEach(InferenceBackend.allCases, id: \.self) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                Picker("Language", selection: $languageCode) {
                    ForEach(SpeechCatalog.languageOptions(for: SpeechCatalog.preset(for: modelID), allowAutoDetect: true)) { language in
                        Text(language.label).tag(language.code)
                    }
                }
                presetDetailsView(for: SpeechCatalog.preset(for: modelID))
                Picker("Enhancement", selection: $enhancementMode) {
                    ForEach(SpeechEnhancementMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                Toggle("Include timestamps JSON", isOn: $includeTimestamps)
                    .disabled(!SpeechCatalog.supportsTimestamps(modelID))
                Toggle("Use VAD segmentation", isOn: $useVAD)
            }
            Button("Run Transcription") {
                guard let selectedMedia else { return }
                store.runTranscription(
                    inputURL: selectedMedia,
                    options: STTOptions(
                        modelId: modelID,
                        includeTimestamps: includeTimestamps,
                        useVAD: useVAD,
                        languageCode: languageCode,
                        backend: backend,
                        enhancementMode: enhancementMode
                    )
                )
                store.selectedScreen = .library
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedMedia == nil)
        }
        .onAppear {
            languageCode = store.settings.preferredTranscriptionLanguage
            backend = store.settings.sttDefaults.backend
            enhancementMode = store.settings.sttDefaults.enhancementMode
        }
        .onChange(of: modelID) { _, newValue in
            if let preset = SpeechCatalog.preset(for: newValue) {
                backend = preset.backend
                if !SpeechCatalog.supportsTimestamps(newValue) {
                    includeTimestamps = false
                }
                if let firstLanguage = SpeechCatalog.languageOptions(for: preset, allowAutoDetect: true).first?.code {
                    languageCode = firstLanguage
                }
            }
        }
    }

    private func pickMedia() {
        let panel = NSOpenPanel()
        panel.allowedFileTypes = [
            "m4a", "mp3", "wav", "aiff", "mp4", "mov", "ogg", "opus", "vorbis",
        ]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK {
            selectedMedia = panel.url
        }
    }
}

struct LivePlaceholderScreen: View {
    @EnvironmentObject private var store: AppStore
    @StateObject private var manager = LiveTranscriptionManager()
    @State private var selectedWebhookTemplateID: UUID?

    var body: some View {
        ScreenScrollView(maxWidth: 1080) {
            Text("Live Voice")
                .font(.title2.bold())

            ScreenSection(title: "Input") {
            AdaptiveButtonRow {
                Picker("Input", selection: $manager.selectedInputDeviceID) {
                    ForEach(manager.availableInputDevices) { device in
                        Text(device.name).tag(device.id)
                    }
                }
                .frame(maxWidth: 360)

                Button("Refresh Inputs") {
                    manager.refreshInputDevices()
                }
            }
            }

            ScreenSection(title: "Recognition") {
                Picker("Live preset", selection: $manager.modelID) {
                    ForEach(SpeechCatalog.sttModels(for: .liveTranscription)) { preset in
                        Text(presetMenuLabel(preset)).tag(preset.id)
                    }
                }

                TextField("STT model", text: $manager.modelID)
                    .textFieldStyle(.roundedBorder)

                AdaptiveButtonRow {
                    Picker("Backend", selection: $manager.backend) {
                        ForEach(InferenceBackend.allCases, id: \.self) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .frame(maxWidth: 220)

                    Picker("Enhancement", selection: $manager.enhancementMode) {
                        ForEach(SpeechEnhancementMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .frame(maxWidth: 220)
                }

                Picker("Live language", selection: $manager.languageCode) {
                    ForEach(SpeechCatalog.languageOptions(for: SpeechCatalog.preset(for: manager.modelID), allowAutoDetect: true)) { language in
                        Text(language.label).tag(language.code)
                    }
                }
                .frame(maxWidth: 260)
                presetDetailsView(for: SpeechCatalog.preset(for: manager.modelID))
            }

            ScreenSection(title: "Actions") {
                AdaptiveButtonRow {
                    Picker("Action", selection: $manager.actionMode) {
                        ForEach(LiveActionMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .frame(maxWidth: 260)

                    if manager.actionMode == .shell {
                        TextField("Shell template (use {{text}})", text: $manager.shellTemplate)
                    } else if manager.actionMode == .webhook {
                        VStack(alignment: .leading, spacing: 8) {
                            Picker("Webhook template", selection: $selectedWebhookTemplateID) {
                                Text("Custom").tag(UUID?.none)
                                ForEach(store.settings.savedWebhookTemplates) { template in
                                    Text(template.name).tag(UUID?.some(template.id))
                                }
                            }
                            TextField("Webhook URL", text: $manager.webhookURL)
                        }
                    }
                }
            }

            ScreenSection(title: "Session") {
            AdaptiveButtonRow {
                Button(manager.isRunning ? "Stop Live Transcript" : "Start Live Transcript") {
                    if manager.isRunning {
                        manager.stop()
                    } else {
                        manager.start()
                    }
                }
                .buttonStyle(.borderedProminent)

                Text(manager.isRunning ? "Listening..." : "Stopped")
                    .foregroundStyle(manager.isRunning ? .green : .secondary)
            }
            Text("Engine: \(manager.runtimeModeDescription)")
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            ScreenSection(title: "Transcript") {
                if !manager.livePartialText.isEmpty {
                    Text(manager.livePartialText)
                        .foregroundStyle(.secondary)
                        .italic()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(manager.transcriptLines.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 2)
                        }
                    }
                }
                .frame(minHeight: 220, maxHeight: 420)
            }

            if let error = manager.latestError, !error.isEmpty {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            Text("Tip: to transcribe Mac speaker output, select a loopback input device (for example BlackHole) in Input.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onAppear {
            manager.languageCode = store.settings.preferredTranscriptionLanguage
            manager.backend = store.settings.sttDefaults.backend
            manager.enhancementMode = store.settings.sttDefaults.enhancementMode
            manager.pythonRepoPath = store.settings.pythonMLXRepoPath
            if manager.webhookURL.isEmpty {
                selectedWebhookTemplateID = store.settings.savedWebhookTemplates.first?.id
                if let template = store.settings.savedWebhookTemplates.first {
                    manager.webhookURL = template.url
                }
            } else {
                selectedWebhookTemplateID = store.settings.savedWebhookTemplates.first(where: { $0.url == manager.webhookURL })?.id
            }
        }
        .onChange(of: manager.modelID) { _, newValue in
            if let preset = SpeechCatalog.preset(for: newValue) {
                manager.backend = preset.backend
                if let firstLanguage = SpeechCatalog.languageOptions(for: preset, allowAutoDetect: true).first?.code {
                    manager.languageCode = firstLanguage
                }
            }
        }
        .onChange(of: selectedWebhookTemplateID) { _, newValue in
            if let template = store.settings.savedWebhookTemplates.first(where: { $0.id == newValue }) {
                manager.webhookURL = template.url
            }
        }
        .onDisappear {
            manager.stop()
        }
    }
}

struct LibraryScreen: View {
    @EnvironmentObject private var store: AppStore
    @State private var player: AVAudioPlayer?
    @State private var playingAudioPath: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            AdaptiveButtonRow {
                Text("Jobs")
                    .font(.title2.bold())
                Spacer()
                Button("Open Outputs Folder") {
                    openPath(store.settings.outputFolderPath)
                }
                Button("Refresh") {
                    Task { await store.loadInitialState() }
                }
            }
            List(store.jobs, id: \.id) { job in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(job.type.rawValue)
                        Spacer()
                        Text(job.status.rawValue)
                    }
                    ProgressView(value: job.progress)
                    Text(job.inputRef)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let transcriptPath = job.outputRefs.transcriptPath {
                        Text("Transcript: \(transcriptPath)")
                            .font(.caption2)
                    }
                    if let audioPath = job.outputRefs.audioPath {
                        Text("Audio: \(audioPath)")
                            .font(.caption2)
                    }
                    AdaptiveButtonRow {
                        if let audioPath = job.outputRefs.audioPath {
                            Button(playingAudioPath == audioPath ? "Stop Audio" : "Play Audio") {
                                toggleAudioPlayback(path: audioPath)
                            }
                            Button("Reveal Audio") {
                                revealFile(audioPath)
                            }
                        }
                        if let transcriptPath = job.outputRefs.transcriptPath {
                            Button("Open Transcript") {
                                openPath(transcriptPath)
                            }
                            Button("Reveal Transcript") {
                                revealFile(transcriptPath)
                            }
                            Button("Ask About Transcript") {
                                store.askAboutFile(
                                    path: transcriptPath,
                                    title: URL(fileURLWithPath: transcriptPath).lastPathComponent,
                                    suggestedPrompt: "Summarize this transcript and answer questions using only its content."
                                )
                            }
                        }
                        Button("Open Log") {
                            openPath(job.logPath)
                        }
                    }
                    .font(.caption)
                    if let errorMessage = job.errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding(24)
    }

    private func openPath(_ path: String) {
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    private func revealFile(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    private func toggleAudioPlayback(path: String) {
        if playingAudioPath == path, player?.isPlaying == true {
            player?.stop()
            player = nil
            playingAudioPath = nil
            return
        }

        do {
            let audioPlayer = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: path))
            player = audioPlayer
            playingAudioPath = path
            audioPlayer.prepareToPlay()
            audioPlayer.play()
        } catch {
            store.latestError = error.localizedDescription
            player = nil
            playingAudioPath = nil
        }
    }
}

struct ModelsScreen: View {
    var body: some View {
        ScreenScrollView {
            Text("Models")
                .font(.title2.bold())
            Text("Preset catalog for local text, audio, and vision backends.")
                .foregroundStyle(.secondary)
            ScreenSection(title: "Text presets") {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(TextModelCatalog.presets) { preset in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(preset.title) (\(preset.backend.rawValue)) — \(preset.summary)")
                            Text(preset.id)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            ScreenSection(title: "TTS presets") {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(SpeechCatalog.ttsPresets) { preset in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(preset.title) (\(preset.backend.rawValue)) — \(preset.summary)")
                            Text("Workflows: \(preset.workflows.map(\.rawValue).sorted().joined(separator: ", "))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            ScreenSection(title: "STT presets") {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(SpeechCatalog.sttPresets) { preset in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(preset.title) (\(preset.backend.rawValue)) — \(preset.summary)")
                            Text("Workflows: \(preset.workflows.map(\.rawValue).sorted().joined(separator: ", "))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }
}

struct SettingsScreen: View {
    @EnvironmentObject private var store: AppStore
    @State private var systemVoices: [VoiceOption] = []
    @State private var selectedVoiceIdentifier: String = ""
    @State private var modelVoiceTarget: String = TTSOptions().modelId
    @State private var previewText: String = "This is a preview of the selected reader voice."
    @State private var previewSynth: NSSpeechSynthesizer?
    @State private var webhookTemplateDraft = SavedWebhookTemplateDraft()

    var body: some View {
        ScreenScrollView {
            Text("Settings")
                .font(.title2.bold())
            Text("Application defaults, local backends, relay integration, and reusable templates.")
                .foregroundStyle(.secondary)
            ScreenSection(title: "Defaults") {
                TextField("Output folder", text: $store.settings.outputFolderPath)
                TextField("Logging level", text: $store.settings.loggingLevel)
            }
            ScreenSection(title: "Local Assistant") {
                Picker("Default text model", selection: $store.settings.lmDefaults.modelId) {
                    ForEach(TextModelCatalog.presets) { preset in
                        Text("\(preset.title) (\(preset.backend.rawValue)) — \(preset.summary)").tag(preset.id)
                    }
                }
                Picker("Assistant backend", selection: $store.settings.lmDefaults.backend) {
                    ForEach(InferenceBackend.allCases, id: \.self) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                TextField("System prompt", text: $store.settings.lmDefaults.systemPrompt, axis: .vertical)
                    .lineLimit(3, reservesSpace: true)
                TextField("Max tokens", value: $store.settings.lmDefaults.maxTokens, format: .number)
                TextField("Temperature", value: $store.settings.lmDefaults.temperature, format: .number)
            }
            ScreenSection(title: "TTS") {
                Picker("Default TTS preset", selection: $store.settings.ttsDefaults.modelId) {
                    ForEach(SpeechCatalog.ttsModels(for: .documentReader)) { preset in
                        Text(presetMenuLabel(preset)).tag(preset.id)
                    }
                }
                Picker("TTS backend", selection: $store.settings.ttsDefaults.backend) {
                    ForEach(InferenceBackend.allCases, id: \.self) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                Picker("Reader language", selection: $store.settings.preferredReaderLanguage) {
                    ForEach(SpeechCatalog.languages.filter { $0.code != "auto" }) { language in
                        Text(language.label).tag(language.code)
                    }
                }
                TextField("Output format", text: $store.settings.ttsDefaults.outputFormat)
            }
            ScreenSection(title: "Reader Voice") {
                Text("Choose voice and map it per model.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Model ID", text: $modelVoiceTarget)
                Picker("Voice", selection: $selectedVoiceIdentifier) {
                    Text("System Default").tag("")
                    ForEach(systemVoices, id: \.id) { voice in
                        Text(voice.label).tag(voice.id)
                    }
                }
                AdaptiveButtonRow {
                    Button("Preview Voice") {
                        previewSelectedVoice()
                    }
                    Button("Assign Voice to Model") {
                        assignSelectedVoiceToModel()
                    }
                }
                TextField("Preview text", text: $previewText)
                if !store.settings.ttsVoiceByModel.isEmpty {
                    ForEach(store.settings.ttsVoiceByModel.keys.sorted(), id: \.self) { modelID in
                        HStack {
                            Text(modelID).font(.caption)
                            Spacer()
                            Text(voiceLabel(for: store.settings.ttsVoiceByModel[modelID] ?? ""))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button("Remove") {
                                store.settings.ttsVoiceByModel.removeValue(forKey: modelID)
                            }
                            .font(.caption)
                        }
                    }
                }
            }
            ScreenSection(title: "STT") {
                Picker("Default STT preset", selection: $store.settings.sttDefaults.modelId) {
                    ForEach(SpeechCatalog.sttModels(for: .fileTranscription)) { preset in
                        Text(presetMenuLabel(preset)).tag(preset.id)
                    }
                }
                Picker("STT backend", selection: $store.settings.sttDefaults.backend) {
                    ForEach(InferenceBackend.allCases, id: \.self) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                Picker("Transcription language", selection: $store.settings.preferredTranscriptionLanguage) {
                    ForEach(SpeechCatalog.languages) { language in
                        Text(language.label).tag(language.code)
                    }
                }
                Picker("Default enhancement", selection: $store.settings.sttDefaults.enhancementMode) {
                    ForEach(SpeechEnhancementMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                Toggle("Include timestamps", isOn: $store.settings.sttDefaults.includeTimestamps)
                Toggle("Use VAD", isOn: $store.settings.sttDefaults.useVAD)
            }
            ScreenSection(title: "Python mlx-audio 0.4.2") {
                TextField("Repo path", text: $store.settings.pythonMLXRepoPath)
                Text("Point this to your cloned Python mlx-audio repo for Whisper, Cohere, Canary, Moonshine, MMS, Granite, SenseVoice, FireRedASR2, Fish Audio, Irodori, KugelAudio, Voxtral TTS, HumeAI Tada, DeepFilterNet, and OGG/Opus/Vorbis workflows.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ScreenSection(title: "Python mlx-lm 0.31.2") {
                TextField("Repo path", text: $store.settings.pythonMLXLMRepoPath)
                Text("Use this for Gemma 4 and other text models that land first in Python mlx-lm. The Local Assistant will use it when the selected text model backend is pythonMLX.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ScreenSection(title: "Python mlx-vlm 0.4.3") {
                Picker("Default workflow", selection: $store.settings.visualDefaults.workflow) {
                    ForEach(VisualAnalysisWorkflow.allCases, id: \.self) { workflow in
                        Text(workflow.displayName).tag(workflow)
                    }
                }
                Toggle("Default to all PDF pages", isOn: $store.settings.visualDefaults.processAllPDFPages)
                Picker("Default visual model", selection: $store.settings.visualDefaults.modelId) {
                    ForEach(visualPresets) { preset in
                        Text("\(preset.title) — \(preset.summary)").tag(preset.id)
                    }
                }
                Button("Use default workflow prompt") {
                    store.settings.visualDefaults.prompt = store.settings.visualDefaults.workflow.defaultPrompt
                }
                TextField("Default visual prompt", text: $store.settings.visualDefaults.prompt, axis: .vertical)
                    .lineLimit(3, reservesSpace: true)
                TextField("Default VLM max tokens", value: $store.settings.visualDefaults.maxTokens, format: .number)
                TextField("Default KV bits", value: Binding(
                    get: { store.settings.visualDefaults.kvBits ?? 0 },
                    set: { store.settings.visualDefaults.kvBits = $0 == 0 ? nil : $0 }
                ), format: .number)
                Picker("Default KV quant scheme", selection: $store.settings.visualDefaults.kvQuantScheme) {
                    ForEach(VLMKVQuantizationScheme.allCases, id: \.self) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                TextField("VLM repo path", text: $store.settings.pythonMLXVLMRepoPath)
                Text("Use this for image, screenshot, and PDF-page analysis through the local mlx-vlm environment. OCR workflows pair best with Falcon OCR and DeepSeek OCR, and all-page PDF processing is intended for scanned documents.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ScreenSection(title: "Webhook Templates") {
                Text("These templates are shared by Visual Analysis and Live webhook actions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(store.settings.savedWebhookTemplates) { template in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(template.name)
                            Text(template.url)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Use") {
                            webhookTemplateDraft = SavedWebhookTemplateDraft(id: template.id, name: template.name, url: template.url)
                        }
                        Button("Delete") {
                            store.removeSavedWebhookTemplate(id: template.id)
                        }
                    }
                }
                TextField("Template name", text: $webhookTemplateDraft.name)
                TextField("Template URL", text: $webhookTemplateDraft.url)
                AdaptiveButtonRow {
                    Button(webhookTemplateDraft.id == nil ? "Add Template" : "Update Template") {
                        let template = SavedWebhookTemplate(
                            id: webhookTemplateDraft.id ?? UUID(),
                            name: webhookTemplateDraft.name.trimmingCharacters(in: .whitespacesAndNewlines),
                            url: webhookTemplateDraft.url.trimmingCharacters(in: .whitespacesAndNewlines)
                        )
                        store.upsertSavedWebhookTemplate(template)
                        webhookTemplateDraft = SavedWebhookTemplateDraft()
                    }
                    .disabled(webhookTemplateDraft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || webhookTemplateDraft.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if webhookTemplateDraft.id != nil {
                        Button("Clear") {
                            webhookTemplateDraft = SavedWebhookTemplateDraft()
                        }
                    }
                }
            }
            ScreenSection(title: "Telegram Relay") {
                SecureField("Bot token", text: $store.settings.telegramRelay.botToken)
                TextField("Chat ID", text: $store.settings.telegramRelay.chatID)
                TextField("Host", text: $store.settings.telegramRelay.host)
                Stepper(value: $store.settings.telegramRelay.port, in: 1...65535) {
                    Text("Port: \(store.settings.telegramRelay.port)")
                }
                Text("Status: \(store.telegramRelayStatus)")
                    .font(.caption)
                    .foregroundStyle(store.isTelegramRelayRunning ? .green : .secondary)
                AdaptiveButtonRow {
                    Button(store.isTelegramRelayRunning ? "Restart Relay" : "Start Relay") {
                        store.startTelegramRelay()
                    }
                    Button("Stop Relay") {
                        store.stopTelegramRelay()
                    }
                    .disabled(!store.isTelegramRelayRunning)
                    Button("Reveal Relay Log") {
                        store.revealTelegramRelayLog()
                    }
                }
                Text("When the relay is running, the default Telegram webhook template points to the local endpoint automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ScreenSection(title: "Relay Helpers") {
                Text("Telegram relay helper: /Users/joru2/Applications/MLXAudio/scripts/telegram_relay.py")
                    .font(.caption)
                Button("Reveal Telegram Relay Script") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: "/Users/joru2/Applications/MLXAudio/scripts/telegram_relay.py")])
                }
                Text("Run with TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID to use the built-in Telegram webhook preset.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button("Save Settings") {
                store.saveSettings()
            }
            .buttonStyle(.borderedProminent)
        }
        .onAppear {
            loadSystemVoices()
            modelVoiceTarget = store.settings.ttsDefaults.modelId
            selectedVoiceIdentifier = store.settings.ttsDefaults.voiceIdentifier ?? ""
        }
    }

    private func loadSystemVoices() {
        systemVoices = NSSpeechSynthesizer.availableVoices.compactMap { id in
            let attributes = NSSpeechSynthesizer.attributes(forVoice: id)
            let name = attributes[.name] as? String ?? id.rawValue
            let locale = attributes[.localeIdentifier] as? String ?? ""
            let label = locale.isEmpty ? name : "\(name) (\(locale))"
            return VoiceOption(id: id.rawValue, label: label)
        }
        .sorted { $0.label < $1.label }
    }

    private func previewSelectedVoice() {
        let synth = NSSpeechSynthesizer()
        if !selectedVoiceIdentifier.isEmpty {
            _ = synth.setVoice(NSSpeechSynthesizer.VoiceName(rawValue: selectedVoiceIdentifier))
        }
        synth.startSpeaking(previewText)
        previewSynth = synth
    }

    private func assignSelectedVoiceToModel() {
        let model = modelVoiceTarget.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else { return }
        if selectedVoiceIdentifier.isEmpty {
            store.settings.ttsVoiceByModel.removeValue(forKey: model)
        } else {
            store.settings.ttsVoiceByModel[model] = selectedVoiceIdentifier
        }
        if model == store.settings.ttsDefaults.modelId {
            store.settings.ttsDefaults.voiceIdentifier = selectedVoiceIdentifier.isEmpty ? nil : selectedVoiceIdentifier
        }
    }

    private func voiceLabel(for identifier: String) -> String {
        if identifier.isEmpty {
            return "System Default"
        }
        return systemVoices.first(where: { $0.id == identifier })?.label ?? identifier
    }
}

private struct VoiceOption {
    let id: String
    let label: String
}

private func availableSystemVoices() -> [VoiceOption] {
    NSSpeechSynthesizer.availableVoices.compactMap { id in
        let attributes = NSSpeechSynthesizer.attributes(forVoice: id)
        let name = attributes[.name] as? String ?? id.rawValue
        let locale = attributes[.localeIdentifier] as? String ?? ""
        let label = locale.isEmpty ? name : "\(name) (\(locale))"
        return VoiceOption(id: id.rawValue, label: label)
    }
    .sorted { $0.label < $1.label }
}

private func latestStatusLine(in content: String) -> String? {
    content
        .split(whereSeparator: { $0.isNewline || $0 == "\r" })
        .map(String.init)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .last(where: { !$0.isEmpty })
}

private func runProcess(_ launchPath: String, _ args: [String]) -> Int32 {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: launchPath)
    process.arguments = args
    do {
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    } catch {
        return -1
    }
}

private func appleScriptForKeystroke(_ text: String) -> String {
    let escaped = text
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
    return "tell application \"System Events\" to keystroke \"\(escaped)\""
}

@ViewBuilder
private func presetDetailsView(for preset: ModelPreset?) -> some View {
    if let preset {
        VStack(alignment: .leading, spacing: 4) {
            Text(preset.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
            if !preset.languageCodes.isEmpty {
                Text("Languages: \(preset.languageCodes.map(languageLabel(for:)).joined(separator: ", "))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            let badges = SpeechCatalog.capabilityBadges(for: preset)
            if !badges.isEmpty {
                Text("Capabilities: \(badges.joined(separator: " • "))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if SpeechCatalog.supportsAudioUnderstanding(preset.id) {
                Text("This model also supports richer audio understanding upstream; the app currently uses it in transcription mode.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private func presetMenuLabel(_ preset: ModelPreset) -> String {
    "\(preset.title) — \(preset.summary)"
}

private func languageLabel(for code: String) -> String {
    SpeechCatalog.languages.first(where: { $0.code == code })?.label ?? code.uppercased()
}

private func resolveDefaultVoice(for modelID: String, settings: AppSettings) -> String {
    if let mapped = settings.ttsVoiceByModel[modelID], !mapped.isEmpty {
        return mapped
    }
    if let fallback = settings.ttsDefaults.voiceIdentifier, !fallback.isEmpty {
        return fallback
    }
    return ""
}
