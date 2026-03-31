import AVFoundation
import AppKit
import Foundation
import LocalVoiceUtilityKit
import MLXAudioCore
import Speech

struct AudioInputDevice: Identifiable, Hashable {
    let id: String
    let name: String
}

enum LiveActionMode: String, CaseIterable {
    case none = "None"
    case clipboard = "Copy to Clipboard"
    case typeToFrontmost = "Type into Front App"
    case shell = "Run Shell Command"
    case webhook = "POST Webhook"
}

private func installSpeechInputTap(
    inputNode: AVAudioInputNode,
    request: SFSpeechAudioBufferRecognitionRequest
) {
    let format = inputNode.outputFormat(forBus: 0)
    inputNode.removeTap(onBus: 0)
    inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
        request.append(buffer)
    }
}

final class AudioChunkBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var samples: [Float] = []
    private var sampleRate: Int = 16_000

    func append(_ newSamples: [Float], sampleRate: Int) {
        lock.lock()
        self.sampleRate = sampleRate
        samples.append(contentsOf: newSamples)
        lock.unlock()
    }

    func drain() -> (samples: [Float], sampleRate: Int) {
        lock.lock()
        let out = samples
        let rate = sampleRate
        samples.removeAll(keepingCapacity: true)
        lock.unlock()
        return (out, rate)
    }

    func clear() {
        lock.lock()
        samples.removeAll(keepingCapacity: false)
        lock.unlock()
    }
}

@MainActor
final class LiveTranscriptionManager: NSObject, ObservableObject {
    @Published var isRunning = false
    @Published var availableInputDevices: [AudioInputDevice] = []
    @Published var selectedInputDeviceID: String = ""
    @Published var modelID = STTOptions().modelId
    @Published var languageCode = STTOptions().languageCode
    @Published var backend: InferenceBackend = STTOptions().backend
    @Published var enhancementMode: SpeechEnhancementMode = .off
    @Published var transcriptLines: [String] = []
    @Published var livePartialText: String = ""
    @Published var latestError: String?
    @Published var runtimeModeDescription = "MLX (local)"
    @Published var actionMode: LiveActionMode = .none
    @Published var shellTemplate = "echo '{{text}}'"
    @Published var webhookURL = ""
    @Published var pythonRepoPath = PythonMLXBridge.defaultRepoPath

    private let sttService = STTService()
    private let captureSession = AVCaptureSession()
    private let output = AVCaptureAudioDataOutput()
    private let outputQueue = DispatchQueue(label: "localvoice.live.capture", qos: .userInitiated)
    private let buffer = AudioChunkBuffer()

    private var captureInput: AVCaptureDeviceInput?
    private var loopTask: Task<Void, Never>?
    private var isTranscribing = false
    private var speechRecognizer: SFSpeechRecognizer?
    private var speechRequest: SFSpeechAudioBufferRecognitionRequest?
    private var speechTask: SFSpeechRecognitionTask?
    private let speechAudioEngine = AVAudioEngine()
    private var usingSpeechFallback = false

    override init() {
        super.init()
        refreshInputDevices()
    }

    func refreshInputDevices() {
        let devices = AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone], mediaType: .audio, position: .unspecified)
            .devices
            .map { AudioInputDevice(id: $0.uniqueID, name: $0.localizedName) }
            .sorted { $0.name < $1.name }

        availableInputDevices = devices
        if selectedInputDeviceID.isEmpty || !devices.contains(where: { $0.id == selectedInputDeviceID }) {
            selectedInputDeviceID = devices.first?.id ?? ""
        }
    }

    func start() {
        guard !isRunning else { return }
        latestError = nil

        Task { @MainActor in
            let effectiveBackend = resolvedBackend()
            do {
                usingSpeechFallback = false
                if effectiveBackend == .pythonMLX {
                    runtimeModeDescription = "Python MLX micro-batch"
                    try configureCaptureSession()
                    captureSession.startRunning()
                    isRunning = true
                    startLoop()
                    return
                }

                try MLXRuntimePreflight.ensureReady()
                runtimeModeDescription = "MLX (local)"

                try configureCaptureSession()
                captureSession.startRunning()
                isRunning = true
                startLoop()
            } catch {
                // Fallback for machines without MLX Metal runtime.
                do {
                    try await startSpeechFallback()
                    usingSpeechFallback = true
                    runtimeModeDescription = "System Speech (fallback)"
                    isRunning = true
                } catch {
                    latestError = error.localizedDescription
                    stop()
                }
            }
        }
    }

    func stop() {
        isRunning = false
        loopTask?.cancel()
        loopTask = nil

        if captureSession.isRunning {
            captureSession.stopRunning()
        }

        captureSession.beginConfiguration()
        if let captureInput {
            captureSession.removeInput(captureInput)
        }
        if captureSession.outputs.contains(output) {
            captureSession.removeOutput(output)
        }
        captureSession.commitConfiguration()

        self.captureInput = nil
        buffer.clear()
        stopSpeechFallback()
        livePartialText = ""
    }

    private func configureCaptureSession() throws {
        captureSession.beginConfiguration()
        defer { captureSession.commitConfiguration() }

        if let captureInput {
            captureSession.removeInput(captureInput)
        }
        if captureSession.outputs.contains(output) {
            captureSession.removeOutput(output)
        }

        let audioDevices = AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone], mediaType: .audio, position: .unspecified).devices
        let device: AVCaptureDevice
        if let selected = audioDevices.first(where: { $0.uniqueID == selectedInputDeviceID }) {
            device = selected
        } else if let fallback = AVCaptureDevice.default(for: .audio) {
            device = fallback
        } else {
            throw NSError(domain: "LiveTranscription", code: 1, userInfo: [NSLocalizedDescriptionKey: "No audio input device found."])
        }

        let input = try AVCaptureDeviceInput(device: device)
        guard captureSession.canAddInput(input) else {
            throw NSError(domain: "LiveTranscription", code: 2, userInfo: [NSLocalizedDescriptionKey: "Cannot attach selected audio device."])
        }
        captureSession.addInput(input)
        captureInput = input

        output.setSampleBufferDelegate(self, queue: outputQueue)
        guard captureSession.canAddOutput(output) else {
            throw NSError(domain: "LiveTranscription", code: 3, userInfo: [NSLocalizedDescriptionKey: "Cannot attach audio output."])
        }
        captureSession.addOutput(output)
    }

    private func startLoop() {
        loopTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                let backend = resolvedBackend()
                try? await Task.sleep(nanoseconds: backend == .pythonMLX ? 3_000_000_000 : 1_500_000_000)
                if !self.isRunning || self.isTranscribing {
                    continue
                }

                let chunk = self.buffer.drain()
                let minimumSampleCount = backend == .pythonMLX
                    ? max(chunk.sampleRate * 2, 24_000)
                    : max(8_000, chunk.sampleRate)
                if chunk.samples.count < minimumSampleCount {
                    continue
                }

                self.isTranscribing = true
                self.livePartialText = liveStatusText(for: backend)
                do {
                    let options = STTOptions(
                        modelId: self.modelID,
                        includeTimestamps: false,
                        useVAD: false,
                        languageCode: self.resolvedLanguageCode(),
                        backend: self.resolvedBackend(),
                        pythonRepoPath: self.pythonRepoPath,
                        enhancementMode: self.enhancementMode
                    )
                    let transcript: TranscriptDocument
                    if backend == .pythonMLX {
                        transcript = try await self.transcribeChunkViaFile(chunk.samples, sampleRate: chunk.sampleRate, options: options)
                    } else {
                        transcript = try await self.sttService.transcribe(
                            samples: chunk.samples,
                            sampleRate: chunk.sampleRate,
                            options: options
                        )
                    }
                    let text = transcript.fullText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !text.isEmpty {
                        self.transcriptLines.append(text)
                        self.livePartialText = text
                        await self.route(text: text)
                    } else {
                        self.livePartialText = ""
                    }
                } catch {
                    self.latestError = error.localizedDescription
                    self.livePartialText = ""
                }
                self.isTranscribing = false
            }
        }
    }

    private func transcribeChunkViaFile(_ samples: [Float], sampleRate: Int, options: STTOptions) async throws -> TranscriptDocument {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let prepared = try resampleAudio(samples, from: sampleRate, to: 16_000)
        try AudioUtils.writeWavFile(samples: prepared, sampleRate: 16_000, fileURL: tempURL)
        return try await sttService.transcribe(audioURL: tempURL, options: options)
    }

    private func resolvedBackend() -> InferenceBackend {
        switch backend {
        case .automatic:
            let lower = modelID.lowercased()
            if enhancementMode != .off {
                return .pythonMLX
            }
            if lower.contains("canary")
                || lower.contains("moonshine")
                || lower.contains("mms")
                || lower.contains("granite")
                || lower.contains("firered")
                || lower.contains("sensevoice")
                || lower.contains("whisper")
                || lower.contains("cohere")
                || lower.contains("parakeet")
            {
                return .pythonMLX
            }
            return .swiftMLX
        default:
            return backend
        }
    }

    private func resolvedLanguageCode() -> String {
        let lower = modelID.lowercased()
        if lower.contains("moonshine") {
            return "en"
        }
        return languageCode
    }

    private func liveStatusText(for backend: InferenceBackend) -> String {
        if backend == .pythonMLX {
            let lower = modelID.lowercased()
            if lower.contains("moonshine") {
                return "Transcribing... (first Moonshine run may download model files for up to ~1 minute)"
            }
            return "Transcribing... (Python model warm-up can take a few seconds)"
        }
        return "Transcribing..."
    }

    private func startSpeechFallback() async throws {
        let authStatus = await requestSpeechAuthorization()
        guard authStatus == .authorized else {
            throw NSError(
                domain: "LiveTranscription",
                code: 10,
                userInfo: [NSLocalizedDescriptionKey: "Speech recognition permission not granted."]
            )
        }

        let locale: Locale
        if languageCode.isEmpty || languageCode == "auto" {
            locale = Locale.current
        } else {
            locale = Locale(identifier: languageCode)
        }
        let recognizer = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        guard let recognizer else {
            throw NSError(
                domain: "LiveTranscription",
                code: 11,
                userInfo: [NSLocalizedDescriptionKey: "No speech recognizer available for current locale."]
            )
        }
        guard recognizer.isAvailable else {
            throw NSError(
                domain: "LiveTranscription",
                code: 12,
                userInfo: [NSLocalizedDescriptionKey: "Speech recognizer is currently unavailable."]
            )
        }

        speechRecognizer = recognizer
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        speechRequest = request

        let inputNode = speechAudioEngine.inputNode
        installSpeechInputTap(inputNode: inputNode, request: request)

        speechAudioEngine.prepare()
        try speechAudioEngine.start()

        speechTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            Task { @MainActor in
                if let result {
                    let text = result.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
                    self.livePartialText = text
                    if result.isFinal, !text.isEmpty {
                        self.transcriptLines.append(text)
                        self.livePartialText = ""
                        await self.route(text: text)
                    }
                }

                if let error {
                    // User-initiated stop cancels recognition; don't surface that as a failure.
                    if !self.isRunning || self.isIgnorableSpeechError(error) {
                        return
                    }
                    self.latestError = error.localizedDescription
                    self.stop()
                }
            }
        }
    }

    nonisolated private func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        let current = SFSpeechRecognizer.authorizationStatus()
        if current != .notDetermined {
            return current
        }
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    private func stopSpeechFallback() {
        guard usingSpeechFallback || speechTask != nil || speechRequest != nil || speechAudioEngine.isRunning else { return }
        if !livePartialText.isEmpty {
            transcriptLines.append(livePartialText)
        }
        speechAudioEngine.stop()
        speechAudioEngine.inputNode.removeTap(onBus: 0)
        speechRequest?.endAudio()
        speechTask?.cancel()
        speechTask = nil
        speechRequest = nil
        speechRecognizer = nil
        usingSpeechFallback = false
    }

    private func isIgnorableSpeechError(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain && nsError.code == NSUserCancelledError {
            return true
        }
        let lower = nsError.localizedDescription.lowercased()
        return lower.contains("canceled") || lower.contains("cancelled")
    }

    private func route(text: String) async {
        switch actionMode {
        case .none:
            break
        case .clipboard:
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(text, forType: .string)
        case .typeToFrontmost:
            if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.localvoiceutility.desktop" {
                latestError = "Type into Front App is ignored while Local Voice Utility is frontmost. Switch to the target app first, or use Action = None while testing."
                return
            }
            _ = runProcess("/usr/bin/osascript", ["-e", appleScriptForKeystroke(text)])
        case .shell:
            let command = shellTemplate.replacingOccurrences(of: "{{text}}", with: text)
            _ = runProcess("/bin/zsh", ["-lc", command])
        case .webhook:
            guard let url = URL(string: webhookURL), let body = try? JSONSerialization.data(withJSONObject: ["text": text]) else {
                return
            }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
            _ = try? await URLSession.shared.data(for: request)
        }
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
            latestError = error.localizedDescription
            return -1
        }
    }

    private func appleScriptForKeystroke(_ text: String) -> String {
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "tell application \"System Events\" to keystroke \"\(escaped)\""
    }
}

extension LiveTranscriptionManager: AVCaptureAudioDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }

        var length = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        let status = CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer)
        guard status == kCMBlockBufferNoErr,
              let dataPointer,
              length > 0,
              let format = CMSampleBufferGetFormatDescription(sampleBuffer),
              let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(format)
        else { return }

        let asbd = streamDescription.pointee
        let sampleRate = Int(asbd.mSampleRate)
        let channelCount = Int(asbd.mChannelsPerFrame)
        guard channelCount > 0 else { return }

        let bytesPerFrame = Int(asbd.mBytesPerFrame)
        guard bytesPerFrame > 0 else { return }

        let frameCount = length / bytesPerFrame
        if frameCount <= 0 { return }

        var mono: [Float] = []
        mono.reserveCapacity(frameCount)

        if asbd.mBitsPerChannel == 32 {
            let floatPointer = UnsafeRawPointer(dataPointer).bindMemory(to: Float.self, capacity: frameCount * channelCount)
            for frame in 0 ..< frameCount {
                var sum: Float = 0
                for channel in 0 ..< channelCount {
                    sum += floatPointer[frame * channelCount + channel]
                }
                mono.append(sum / Float(channelCount))
            }
        } else if asbd.mBitsPerChannel == 16 {
            let int16Pointer = UnsafeRawPointer(dataPointer).bindMemory(to: Int16.self, capacity: frameCount * channelCount)
            let scale: Float = 1.0 / Float(Int16.max)
            for frame in 0 ..< frameCount {
                var sum: Float = 0
                for channel in 0 ..< channelCount {
                    sum += Float(int16Pointer[frame * channelCount + channel]) * scale
                }
                mono.append(sum / Float(channelCount))
            }
        } else {
            return
        }

        Task { @MainActor in
            self.buffer.append(mono, sampleRate: sampleRate)
        }
    }
}
