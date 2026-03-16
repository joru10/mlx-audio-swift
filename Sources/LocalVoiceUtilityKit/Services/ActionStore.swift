import Foundation

public actor ActionStore {
    private let fileURL: URL

    public init(paths: AppPaths) {
        fileURL = paths.appSupportRoot.appendingPathComponent("action_profiles.json")
    }

    public func loadAll() throws -> [ActionProfile] {
        try JSONStore.load([ActionProfile].self, from: fileURL, defaultValue: [])
    }

    public func saveAll(_ profiles: [ActionProfile]) throws {
        try JSONStore.save(profiles, to: fileURL)
    }
}
