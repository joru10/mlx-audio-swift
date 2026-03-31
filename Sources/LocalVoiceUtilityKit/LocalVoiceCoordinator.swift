import Foundation

public final class LocalVoiceCoordinator: @unchecked Sendable {
    public let paths: AppPaths
    public let jobStore: JobStore
    public let modelStore: ModelStore
    public let actionStore: ActionStore
    public let scaleCaptureStore: ScaleCaptureStore
    public let queue: JobQueue

    private let ttsService = TTSService()
    private let sttService = STTService()

    public init(paths: AppPaths = try! AppPaths()) {
        self.paths = paths
        jobStore = JobStore(paths: paths)
        modelStore = ModelStore(paths: paths)
        actionStore = ActionStore(paths: paths)
        scaleCaptureStore = ScaleCaptureStore(paths: paths)
        queue = JobQueue()
    }

    public func defaultSettings() -> AppSettings {
        AppSettings(outputFolderPath: paths.outputsDirectory.path)
    }

    public func loadSettings() throws -> AppSettings {
        try JSONStore.load(AppSettings.self, from: paths.settingsURL, defaultValue: defaultSettings())
    }

    public func saveSettings(_ settings: AppSettings) throws {
        try JSONStore.save(settings, to: paths.settingsURL)
    }

    public func enqueuePDFToAudio(
        inputURL: URL,
        options: TTSOptions,
        updates: @escaping @Sendable (JobRecord) async -> Void
    ) async throws -> UUID {
        let id = UUID()
        let initialJob = JobRecord(
            id: id,
            type: .pdfToAudio,
            inputRef: inputURL.path,
            optionsJSON: (try? stringify(options)) ?? "{}",
            logPath: logURL(for: id).path
        )

        try await jobStore.upsert(initialJob)
        await updates(initialJob)

        await queue.enqueue(jobID: id) { [self] in
            await executePDFJob(initialJob: initialJob, inputURL: inputURL, options: options, updates: updates)
        }

        return id
    }

    public func enqueueTranscription(
        inputURL: URL,
        options: STTOptions,
        updates: @escaping @Sendable (JobRecord) async -> Void
    ) async throws -> UUID {
        let id = UUID()
        let initialJob = JobRecord(
            id: id,
            type: .transcribeFile,
            inputRef: inputURL.path,
            optionsJSON: (try? stringify(options)) ?? "{}",
            logPath: logURL(for: id).path
        )

        try await jobStore.upsert(initialJob)
        await updates(initialJob)

        await queue.enqueue(jobID: id) { [self] in
            await executeTranscriptionJob(initialJob: initialJob, inputURL: inputURL, options: options, updates: updates)
        }

        return id
    }

    public func enqueueURLToAudio(
        urlString: String,
        options: TTSOptions,
        updates: @escaping @Sendable (JobRecord) async -> Void
    ) async throws -> UUID {
        let id = UUID()
        let initialJob = JobRecord(
            id: id,
            type: .urlToAudio,
            inputRef: urlString,
            optionsJSON: (try? stringify(options)) ?? "{}",
            logPath: logURL(for: id).path
        )

        try await jobStore.upsert(initialJob)
        await updates(initialJob)

        await queue.enqueue(jobID: id) { [self] in
            await executeURLJob(initialJob: initialJob, urlString: urlString, options: options, updates: updates)
        }

        return id
    }

    public func runPDFToAudioNow(
        inputURL: URL,
        options: TTSOptions,
        updates: @escaping @Sendable (JobRecord) async -> Void = { _ in }
    ) async throws -> JobRecord {
        let id = UUID()
        let initialJob = JobRecord(
            id: id,
            type: .pdfToAudio,
            inputRef: inputURL.path,
            optionsJSON: (try? stringify(options)) ?? "{}",
            logPath: logURL(for: id).path
        )
        try await jobStore.upsert(initialJob)
        await updates(initialJob)

        await executePDFJob(initialJob: initialJob, inputURL: inputURL, options: options) { job in
            await updates(job)
        }
        let jobs = try await jobStore.loadJobs()
        return jobs.first(where: { $0.id == id }) ?? initialJob
    }

    public func runTranscriptionNow(
        inputURL: URL,
        options: STTOptions,
        updates: @escaping @Sendable (JobRecord) async -> Void = { _ in }
    ) async throws -> JobRecord {
        let id = UUID()
        let initialJob = JobRecord(
            id: id,
            type: .transcribeFile,
            inputRef: inputURL.path,
            optionsJSON: (try? stringify(options)) ?? "{}",
            logPath: logURL(for: id).path
        )
        try await jobStore.upsert(initialJob)
        await updates(initialJob)

        await executeTranscriptionJob(initialJob: initialJob, inputURL: inputURL, options: options) { job in
            await updates(job)
        }
        let jobs = try await jobStore.loadJobs()
        return jobs.first(where: { $0.id == id }) ?? initialJob
    }

    public func loadJobs() async throws -> [JobRecord] {
        try await jobStore.loadJobs()
    }

    public func loadScaleCaptures() async throws -> [ScaleCaptureRecord] {
        try await scaleCaptureStore.loadCaptures()
    }

    public func captureScaleReading(
        urlString: String,
        title: String?,
        notes: String?
    ) async throws -> ScaleCaptureRecord {
        try await scaleCaptureStore.captureReading(from: urlString, title: title, notes: notes)
    }

    public func previewScaleCapture(_ record: ScaleCaptureRecord, limit: Int = 4_000) async -> String {
        await scaleCaptureStore.preview(for: record, limit: limit)
    }

    public func recoverInterruptedJobs() async throws -> [JobRecord] {
        var jobs = try await jobStore.loadJobs()
        var changed = false
        for index in jobs.indices {
            if jobs[index].status == .running || jobs[index].status == .queued {
                jobs[index].status = .failed
                jobs[index].finishedAt = Date()
                if jobs[index].errorMessage == nil || jobs[index].errorMessage?.isEmpty == true {
                    jobs[index].errorMessage = "Job was interrupted (app restarted or crashed)."
                }
                changed = true
            }
        }
        if changed {
            try await jobStore.saveAll(jobs)
        }
        return jobs
    }

    private func executePDFJob(
        initialJob: JobRecord,
        inputURL: URL,
        options: TTSOptions,
        updates: @escaping @Sendable (JobRecord) async -> Void
    ) async {
        var job = initialJob
        let logger = JobLogger(logURL: URL(fileURLWithPath: job.logPath))
        let pipeline = PDFToAudioPipeline(ttsService: ttsService)

        do {
            job.status = .running
            job.startedAt = Date()
            try await persistAndNotify(job: job, updates: updates)

            let outputURL = paths.outputsDirectory.appendingPathComponent("\(job.id.uuidString).wav")
            let output = try await pipeline.run(
                inputURL: inputURL,
                options: options,
                outputURL: outputURL,
                progress: { value in
                    job.progress = value
                    try? await self.persistAndNotify(job: job, updates: updates)
                },
                logger: logger
            )

            job.outputRefs = output
            job.status = .completed
            job.progress = 1.0
            job.finishedAt = Date()
            try await persistAndNotify(job: job, updates: updates)
        } catch {
            job.status = .failed
            job.errorMessage = error.localizedDescription
            job.finishedAt = Date()
            try? await persistAndNotify(job: job, updates: updates)
        }
    }

    private func executeTranscriptionJob(
        initialJob: JobRecord,
        inputURL: URL,
        options: STTOptions,
        updates: @escaping @Sendable (JobRecord) async -> Void
    ) async {
        var job = initialJob
        let logger = JobLogger(logURL: URL(fileURLWithPath: job.logPath))
        let pipeline = FileTranscriptionPipeline(sttService: sttService)

        do {
            job.status = .running
            job.startedAt = Date()
            try await persistAndNotify(job: job, updates: updates)

            let txtURL = paths.outputsDirectory.appendingPathComponent("\(job.id.uuidString).txt")
            let jsonURL = options.includeTimestamps
                ? paths.outputsDirectory.appendingPathComponent("\(job.id.uuidString).json") : nil

            let output = try await pipeline.run(
                inputURL: inputURL,
                options: options,
                textOutputURL: txtURL,
                jsonOutputURL: jsonURL,
                tempDirectory: paths.outputsDirectory,
                progress: { value in
                    job.progress = value
                    try? await self.persistAndNotify(job: job, updates: updates)
                },
                logger: logger
            )

            job.outputRefs = output
            job.status = .completed
            job.progress = 1.0
            job.finishedAt = Date()
            try await persistAndNotify(job: job, updates: updates)
        } catch {
            job.status = .failed
            job.errorMessage = error.localizedDescription
            job.finishedAt = Date()
            try? await persistAndNotify(job: job, updates: updates)
        }
    }

    private func executeURLJob(
        initialJob: JobRecord,
        urlString: String,
        options: TTSOptions,
        updates: @escaping @Sendable (JobRecord) async -> Void
    ) async {
        var job = initialJob
        let logger = JobLogger(logURL: URL(fileURLWithPath: job.logPath))
        let pipeline = URLToAudioPipeline(ttsService: ttsService)

        do {
            job.status = .running
            job.startedAt = Date()
            try await persistAndNotify(job: job, updates: updates)

            let outputURL = paths.outputsDirectory.appendingPathComponent("\(job.id.uuidString).wav")
            let output = try await pipeline.run(
                urlString: urlString,
                options: options,
                outputURL: outputURL,
                logger: logger
            )

            job.outputRefs = output
            job.status = .completed
            job.progress = 1.0
            job.finishedAt = Date()
            try await persistAndNotify(job: job, updates: updates)
        } catch {
            job.status = .failed
            job.errorMessage = error.localizedDescription
            job.finishedAt = Date()
            try? await persistAndNotify(job: job, updates: updates)
        }
    }

    private func persistAndNotify(
        job: JobRecord,
        updates: @escaping @Sendable (JobRecord) async -> Void
    ) async throws {
        try await jobStore.upsert(job)
        await updates(job)
    }

    private func logURL(for jobID: UUID) -> URL {
        paths.logsDirectory.appendingPathComponent("\(jobID.uuidString).log")
    }

    private func stringify<T: Encodable>(_ value: T) throws -> String {
        String(data: try JSONEncoder.localVoice.encode(value), encoding: .utf8) ?? "{}"
    }
}
