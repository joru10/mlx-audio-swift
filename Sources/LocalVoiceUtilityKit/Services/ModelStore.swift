import Foundation

public actor ModelStore {
    private let paths: AppPaths

    public init(paths: AppPaths) {
        self.paths = paths
    }

    public func loadAll() throws -> [ModelRecord] {
        try JSONStore.load([ModelRecord].self, from: paths.modelsIndexURL, defaultValue: [])
            .sorted { $0.installedAt > $1.installedAt }
    }

    public func upsert(_ model: ModelRecord) throws {
        var models = try loadAll()
        if let idx = models.firstIndex(where: { $0.id == model.id }) {
            models[idx] = model
        } else {
            models.append(model)
        }
        try JSONStore.save(models, to: paths.modelsIndexURL)
    }

    public func delete(modelID: String) throws {
        var models = try loadAll()
        guard let existing = models.first(where: { $0.id == modelID }) else { return }
        if !existing.localPath.isEmpty {
            try? FileManager.default.removeItem(atPath: existing.localPath)
        }
        models.removeAll { $0.id == modelID }
        try JSONStore.save(models, to: paths.modelsIndexURL)
    }
}
