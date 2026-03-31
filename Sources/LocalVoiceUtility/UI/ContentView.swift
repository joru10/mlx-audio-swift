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
        } detail: {
            screenView
        }
        .alert("Error", isPresented: Binding(
            get: { store.latestError != nil },
            set: { _ in store.latestError = nil }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.latestError ?? "Unknown error")
        }
    }

    @ViewBuilder
    private var screenView: some View {
        switch store.selectedScreen {
        case .home:
            HomeScreen()
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

struct HomeScreen: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Quick Actions")
                .font(.title2.bold())
            HStack {
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
        Form {
            Section("Input") {
                Text(selectedPDF?.path ?? "No file selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Select PDF") {
                    pickPDF()
                }
            }
            Section("Generation") {
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
                HStack {
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
        .padding(24)
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
        Form {
            Section("URL") {
                TextField("https://example.com/article", text: $urlString)
                HStack {
                    Button(isFetching ? "Fetching..." : "Fetch Preview") {
                        fetchPreview()
                    }
                    .disabled(isFetching || urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Spacer()
                    Button("Open in Browser") {
                        guard let url = URL(string: urlString) else { return }
                        NSWorkspace.shared.open(url)
                    }
                    .disabled(URL(string: urlString) == nil)
                }
            }

            Section("Generation") {
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

            Section("Extracted preview") {
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
        .padding(24)
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
        Form {
            Section("Input") {
                Text(selectedMedia?.path ?? "No file selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Select Audio/Video") {
                    pickMedia()
                }
            }
            Section("Transcription") {
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
        .padding(24)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Live Voice")
                .font(.title2.bold())

            HStack(spacing: 12) {
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

            Picker("Live preset", selection: $manager.modelID) {
                ForEach(SpeechCatalog.sttModels(for: .liveTranscription)) { preset in
                    Text(presetMenuLabel(preset)).tag(preset.id)
                }
            }

            TextField("STT model", text: $manager.modelID)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 12) {
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

            HStack(spacing: 12) {
                Picker("Action", selection: $manager.actionMode) {
                    ForEach(LiveActionMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .frame(maxWidth: 260)

                if manager.actionMode == .shell {
                    TextField("Shell template (use {{text}})", text: $manager.shellTemplate)
                } else if manager.actionMode == .webhook {
                    TextField("Webhook URL", text: $manager.webhookURL)
                }
            }

            HStack(spacing: 12) {
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

            Text("Transcript")
                .font(.headline)
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
            .frame(maxHeight: .infinity)

            if let error = manager.latestError, !error.isEmpty {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            Text("Tip: to transcribe Mac speaker output, select a loopback input device (for example BlackHole) in Input.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .onAppear {
            manager.languageCode = store.settings.preferredTranscriptionLanguage
            manager.backend = store.settings.sttDefaults.backend
            manager.enhancementMode = store.settings.sttDefaults.enhancementMode
            manager.pythonRepoPath = store.settings.pythonMLXRepoPath
        }
        .onChange(of: manager.modelID) { _, newValue in
            if let preset = SpeechCatalog.preset(for: newValue) {
                manager.backend = preset.backend
                if let firstLanguage = SpeechCatalog.languageOptions(for: preset, allowAutoDetect: true).first?.code {
                    manager.languageCode = firstLanguage
                }
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
            HStack {
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
                    HStack(spacing: 8) {
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
        VStack(alignment: .leading, spacing: 14) {
            Text("Models")
                .font(.title2.bold())
            Text("Preset catalog for mlx-audio Swift + Python backends.")
                .foregroundStyle(.secondary)
            GroupBox("TTS presets") {
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
            GroupBox("STT presets") {
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
        .padding(24)
    }
}

struct SettingsScreen: View {
    @EnvironmentObject private var store: AppStore
    @State private var systemVoices: [VoiceOption] = []
    @State private var selectedVoiceIdentifier: String = ""
    @State private var modelVoiceTarget: String = TTSOptions().modelId
    @State private var previewText: String = "This is a preview of the selected reader voice."
    @State private var previewSynth: NSSpeechSynthesizer?

    var body: some View {
        Form {
            Section("Defaults") {
                TextField("Output folder", text: $store.settings.outputFolderPath)
                TextField("Logging level", text: $store.settings.loggingLevel)
            }
            Section("TTS") {
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
            Section("Reader Voice") {
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
                HStack {
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
            Section("STT") {
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
            Section("Python mlx-audio 0.4.2") {
                TextField("Repo path", text: $store.settings.pythonMLXRepoPath)
                Text("Point this to your cloned Python mlx-audio repo for Whisper, Cohere, Canary, Moonshine, MMS, Granite, SenseVoice, FireRedASR2, Fish Audio, Irodori, KugelAudio, Voxtral TTS, HumeAI Tada, DeepFilterNet, and OGG/Opus/Vorbis workflows.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button("Save Settings") {
                store.saveSettings()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(24)
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
