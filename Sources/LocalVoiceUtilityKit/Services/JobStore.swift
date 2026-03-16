import Foundation

public actor JobStore {
    private let paths: AppPaths

    public init(paths: AppPaths) {
        self.paths = paths
    }

    public func loadJobs() throws -> [JobRecord] {
        try JSONStore.load([JobRecord].self, from: paths.jobsIndexURL, defaultValue: [])
            .sorted { $0.createdAt > $1.createdAt }
    }

    public func upsert(_ job: JobRecord) throws {
        var jobs = try loadJobs()
        if let idx = jobs.firstIndex(where: { $0.id == job.id }) {
            jobs[idx] = job
        } else {
            jobs.append(job)
        }
        try saveAll(jobs)
    }

    public func remove(jobID: UUID) throws {
        var jobs = try loadJobs()
        jobs.removeAll { $0.id == jobID }
        try saveAll(jobs)
    }

    public func saveAll(_ jobs: [JobRecord]) throws {
        var mutable = jobs
        mutable.sort { $0.createdAt > $1.createdAt }
        try JSONStore.save(mutable, to: paths.jobsIndexURL)
    }
}
