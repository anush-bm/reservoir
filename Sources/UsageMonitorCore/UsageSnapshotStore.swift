import Foundation

public actor UsageSnapshotStore {
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(fileURL: URL? = nil) throws {
        let resolvedURL: URL
        if let fileURL {
            resolvedURL = fileURL
        } else {
            let supportDirectory = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let appDirectory = supportDirectory.appendingPathComponent("Reservoir", isDirectory: true)
            try FileManager.default.createDirectory(at: appDirectory, withIntermediateDirectories: true)
            resolvedURL = appDirectory.appendingPathComponent("snapshots.json")
        }

        self.fileURL = resolvedURL
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    public func load() async throws -> [ProviderID: ProviderSnapshot] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [:] }
        let data = try Data(contentsOf: fileURL)
        let snapshots = try decoder.decode([ProviderSnapshot].self, from: data)
        return Dictionary(uniqueKeysWithValues: snapshots.map { ($0.id, $0) })
    }

    public func save(_ snapshots: [ProviderID: ProviderSnapshot]) async throws {
        let values = snapshots.values.sorted { $0.name < $1.name }
        let data = try encoder.encode(values)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }

    public func clear() async throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }
}
