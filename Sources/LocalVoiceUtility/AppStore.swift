import Foundation
import SwiftUI
import LocalVoiceUtilityKit

@MainActor
final class AppStore: ObservableObject {
    enum Screen: String, CaseIterable, Hashable {
        case home = "Home"
        case scale = "Scale Capture"
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
    @Published var scaleCaptures: [ScaleCaptureRecord] = []
    @Published var selectedScaleCaptureID: UUID?
    @Published var latestScaleCapturePreview: String = ""
    @Published var settings: AppSettings
    @Published var latestError: String?

    private let coordinator: LocalVoiceCoordinator

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
            _ = try await coordinator.recoverInterruptedJobs()
            jobs = try await coordinator.loadJobs()
            scaleCaptures = try await coordinator.loadScaleCaptures()
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
        do {
            settings.ttsDefaults.languageCode = settings.preferredReaderLanguage
            settings.ttsDefaults.pythonRepoPath = settings.pythonMLXRepoPath
            settings.sttDefaults.languageCode = settings.preferredTranscriptionLanguage
            settings.sttDefaults.pythonRepoPath = settings.pythonMLXRepoPath
            try coordinator.saveSettings(settings)
        } catch {
            latestError = error.localizedDescription
        }
    }

    func captureScaleReading(urlString: String, title: String, notes: String?) async throws -> ScaleCaptureRecord {
        let record = try await coordinator.captureScaleReading(urlString: urlString, title: title, notes: notes)
        scaleCaptures.insert(record, at: 0)
        selectedScaleCaptureID = record.id
        latestScaleCapturePreview = await coordinator.previewScaleCapture(record)
        return record
    }

    func loadScaleCapturePreview(_ record: ScaleCaptureRecord) {
        Task {
            let preview = await coordinator.previewScaleCapture(record)
            await MainActor.run {
                self.latestScaleCapturePreview = preview
                self.selectedScaleCaptureID = record.id
            }
        }
    }

    var scaleCaptureDirectoryPath: String {
        coordinator.paths.scaleReadingsDirectory.path
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
