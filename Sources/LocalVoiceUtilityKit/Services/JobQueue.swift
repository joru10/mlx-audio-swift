import Foundation

public actor JobQueue {
    public typealias JobOperation = @Sendable () async -> Void

    private struct QueuedJob {
        let id: UUID
        let run: JobOperation
    }

    private var jobs: [QueuedJob] = []
    private var canceledJobIDs: Set<UUID> = []
    private var isRunning = false

    public init() {}

    public func enqueue(jobID: UUID, operation: @escaping JobOperation) {
        jobs.append(QueuedJob(id: jobID, run: operation))
        guard !isRunning else { return }
        isRunning = true
        Task { await self.runLoop() }
    }

    public func cancel(jobID: UUID) {
        canceledJobIDs.insert(jobID)
    }

    private func runLoop() async {
        while !jobs.isEmpty {
            let next = jobs.removeFirst()
            if canceledJobIDs.contains(next.id) {
                continue
            }
            await next.run()
        }
        isRunning = false
    }
}
