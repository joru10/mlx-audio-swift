import Foundation
import SwiftUI
import LocalVoiceUtilityKit
import AppKit

@MainActor
final class AppStore: ObservableObject {
    enum Screen: String, CaseIterable, Hashable {
        case home = "Home"
        case visual = "Visual Analysis"
        case scannedPDF = "Scanned PDF -> Audio"
        case pdf = "PDF -> Audio"
        case url = "URL -> Audio"
        case transcribe = "Transcribe"
        case live = "Live"
        case library = "Library"
        case models = "Models"
        case settings = "Settings"
    }

    @Published var selectedScreen: Screen = .home
    @Published var jobs: [JobRecord] = []
    @Published var actionProfiles: [ActionProfile] = []
    @Published var latestVisualAnalysis: VisualAnalysisResult?
    @Published var latestVisualNarrationPath: String?
    @Published var settings: AppSettings
    @Published var latestError: String?
    @Published var isTelegramRelayRunning = false
    @Published var telegramRelayStatus = "Stopped"

    private let coordinator: LocalVoiceCoordinator
    private var telegramRelayProcess: Process?
    private let telegramRelayScriptPath = "/Users/joru2/Applications/MLXAudio/scripts/telegram_relay.py"
    private let telegramRelayLogPath = "/Users/joru2/Library/Application Support/LocalVoiceUtility/logs/telegram-relay.log"

    init() {
        coordinator = LocalVoiceCoordinator()
        settings = coordinator.defaultSettings()

        Task {
            await loadInitialState()
        }
    }

    func loadInitialState() async {
        do {
            settings = try coordinator.loadSettings()
            syncDefaultWebhookTemplates()
            actionProfiles = try await coordinator.loadActionProfiles()
            _ = try await coordinator.recoverInterruptedJobs()
            jobs = try await coordinator.loadJobs()
        } catch {
            latestError = error.localizedDescription
        }
    }

    func runPDFToAudio(inputURL: URL, options: TTSOptions) {
        Task {
            do {
                var resolved = options
                resolved.voiceIdentifier = resolveVoiceIdentifier(for: resolved.modelId, explicitVoice: resolved.voiceIdentifier)
                if resolved.languageCode.isEmpty {
                    resolved.languageCode = settings.preferredReaderLanguage
                }
                if resolved.pythonRepoPath?.isEmpty != false {
                    resolved.pythonRepoPath = settings.pythonMLXRepoPath
                }
                _ = try await coordinator.enqueuePDFToAudio(inputURL: inputURL, options: resolved) { [weak self] updatedJob in
                    guard let self else { return }
                    await MainActor.run {
                        self.upsertJob(updatedJob)
                    }
                }
            } catch {
                await MainActor.run {
                    self.latestError = error.localizedDescription
                }
            }
        }
    }

    func runTranscription(inputURL: URL, options: STTOptions) {
        Task {
            do {
                var resolved = options
                if resolved.languageCode.isEmpty {
                    resolved.languageCode = settings.preferredTranscriptionLanguage
                }
                if resolved.pythonRepoPath?.isEmpty != false {
                    resolved.pythonRepoPath = settings.pythonMLXRepoPath
                }
                _ = try await coordinator.enqueueTranscription(inputURL: inputURL, options: resolved) { [weak self] updatedJob in
                    guard let self else { return }
                    await MainActor.run {
                        self.upsertJob(updatedJob)
                    }
                }
            } catch {
                await MainActor.run {
                    self.latestError = error.localizedDescription
                }
            }
        }
    }

    func runURLToAudio(urlString: String, options: TTSOptions) {
        Task {
            do {
                var resolved = options
                resolved.voiceIdentifier = resolveVoiceIdentifier(for: resolved.modelId, explicitVoice: resolved.voiceIdentifier)
                if resolved.languageCode.isEmpty {
                    resolved.languageCode = settings.preferredReaderLanguage
                }
                if resolved.pythonRepoPath?.isEmpty != false {
                    resolved.pythonRepoPath = settings.pythonMLXRepoPath
                }
                _ = try await coordinator.enqueueURLToAudio(urlString: urlString, options: resolved) { [weak self] updatedJob in
                    guard let self else { return }
                    await MainActor.run {
                        self.upsertJob(updatedJob)
                    }
                }
            } catch {
                await MainActor.run {
                    self.latestError = error.localizedDescription
                }
            }
        }
    }

    func saveSettings() {
        syncDefaultWebhookTemplates()
        let settingsSnapshot = settings
        let profilesSnapshot = actionProfiles
        Task {
            do {
                var resolved = settingsSnapshot
                resolved.ttsDefaults.languageCode = resolved.preferredReaderLanguage
                resolved.ttsDefaults.pythonRepoPath = resolved.pythonMLXRepoPath
                resolved.sttDefaults.languageCode = resolved.preferredTranscriptionLanguage
                resolved.sttDefaults.pythonRepoPath = resolved.pythonMLXRepoPath
                resolved.visualDefaults.pythonRepoPath = resolved.pythonMLXVLMRepoPath
                try coordinator.saveSettings(resolved)
                try await coordinator.saveActionProfiles(profilesSnapshot)
            } catch {
                await MainActor.run {
                    latestError = error.localizedDescription
                }
            }
        }
    }

    func upsertActionProfile(_ profile: ActionProfile) {
        if let index = actionProfiles.firstIndex(where: { $0.id == profile.id }) {
            actionProfiles[index] = profile
        } else {
            actionProfiles.append(profile)
        }
        actionProfiles.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        saveSettings()
    }

    func removeActionProfile(id: UUID) {
        actionProfiles.removeAll { $0.id == id }
        saveSettings()
    }

    func upsertSavedWebhookTemplate(_ template: SavedWebhookTemplate) {
        if let index = settings.savedWebhookTemplates.firstIndex(where: { $0.id == template.id }) {
            settings.savedWebhookTemplates[index] = template
        } else {
            settings.savedWebhookTemplates.append(template)
        }
        saveSettings()
    }

    func removeSavedWebhookTemplate(id: UUID) {
        settings.savedWebhookTemplates.removeAll { $0.id == id }
        saveSettings()
    }

    func startTelegramRelay() {
        let relay = settings.telegramRelay
        guard !relay.botToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !relay.chatID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            latestError = "Set Telegram bot token and chat ID in Settings before starting the relay."
            return
        }
        stopTelegramRelay()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", telegramRelayScriptPath]
        process.environment = ProcessInfo.processInfo.environment.merging([
            "TELEGRAM_BOT_TOKEN": relay.botToken,
            "TELEGRAM_CHAT_ID": relay.chatID,
            "TELEGRAM_RELAY_HOST": relay.host,
            "TELEGRAM_RELAY_PORT": String(relay.port),
        ]) { _, new in new }

        let logURL = URL(fileURLWithPath: telegramRelayLogPath)
        _ = FileManager.default.createFile(atPath: logURL.path, contents: nil)
        if let handle = try? FileHandle(forWritingTo: logURL) {
            _ = try? handle.seekToEnd()
            process.standardOutput = handle
            process.standardError = handle
        }

        process.terminationHandler = { [weak self] process in
            Task { @MainActor in
                guard let self else { return }
                if self.telegramRelayProcess?.processIdentifier == process.processIdentifier {
                    self.telegramRelayProcess = nil
                    self.isTelegramRelayRunning = false
                    self.telegramRelayStatus = "Stopped (\(process.terminationStatus))"
                }
            }
        }

        do {
            try process.run()
            telegramRelayProcess = process
            isTelegramRelayRunning = true
            telegramRelayStatus = "Running on \(relay.host):\(relay.port)"
            syncDefaultWebhookTemplates()
            saveSettings()
        } catch {
            latestError = error.localizedDescription
        }
    }

    func stopTelegramRelay() {
        telegramRelayProcess?.terminate()
        telegramRelayProcess = nil
        isTelegramRelayRunning = false
        telegramRelayStatus = "Stopped"
    }

    func revealTelegramRelayLog() {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: telegramRelayLogPath)])
    }

    private func syncDefaultWebhookTemplates() {
        let relayTemplates = AppSettings.defaultWebhookTemplates(relay: settings.telegramRelay)
        for relayTemplate in relayTemplates {
            if let index = settings.savedWebhookTemplates.firstIndex(where: { $0.name == relayTemplate.name }) {
                settings.savedWebhookTemplates[index].url = relayTemplate.url
            }
        }
    }

    func runVisualAnalysis(inputURL: URL, options: VisualAnalysisOptions) async throws -> VisualAnalysisResult {
        var resolved = options
        if resolved.pythonRepoPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            resolved.pythonRepoPath = settings.pythonMLXVLMRepoPath
        }
        let result = try await coordinator.runVisualAnalysis(inputURL: inputURL, options: resolved)
        latestVisualAnalysis = result
        return result
    }

    func captureInteractiveScreenshot() async throws -> URL {
        try await coordinator.captureInteractiveScreenshot()
    }

    func captureFullScreenScreenshot() async throws -> URL {
        try await coordinator.captureFullScreenScreenshot()
    }

    func captureFrontmostWindowScreenshot() async throws -> URL {
        try await coordinator.captureFrontmostWindowScreenshot()
    }

    func runTextToAudio(text: String, options: TTSOptions) async throws -> String {
        var resolved = options
        resolved.voiceIdentifier = resolveVoiceIdentifier(for: resolved.modelId, explicitVoice: resolved.voiceIdentifier)
        if resolved.languageCode.isEmpty {
            resolved.languageCode = settings.preferredReaderLanguage
        }
        if resolved.pythonRepoPath?.isEmpty != false {
            resolved.pythonRepoPath = settings.pythonMLXRepoPath
        }
        let outputURL = try await coordinator.runTextToAudioNow(text: text, options: resolved)
        latestVisualNarrationPath = outputURL.path
        return outputURL.path
    }

    private func upsertJob(_ job: JobRecord) {
        if let index = jobs.firstIndex(where: { $0.id == job.id }) {
            jobs[index] = job
        } else {
            jobs.insert(job, at: 0)
        }
        jobs.sort { $0.createdAt > $1.createdAt }
    }

    private func resolveVoiceIdentifier(for modelId: String, explicitVoice: String?) -> String? {
        if let explicitVoice, !explicitVoice.isEmpty {
            return explicitVoice
        }
        if let mapped = settings.ttsVoiceByModel[modelId], !mapped.isEmpty {
            return mapped
        }
        if let fallback = settings.ttsDefaults.voiceIdentifier, !fallback.isEmpty {
            return fallback
        }
        return nil
    }
}
