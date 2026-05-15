import Foundation

public struct RefreshHistoryEntry: Codable, Equatable, Sendable {
    public let provider: ProviderID
    public let timestamp: Date
    public let status: String
    public let usedCachedValue: Bool
    public let isStale: Bool

    public init(
        provider: ProviderID,
        timestamp: Date = Date(),
        status: String,
        usedCachedValue: Bool,
        isStale: Bool
    ) {
        self.provider = provider
        self.timestamp = timestamp
        self.status = status
        self.usedCachedValue = usedCachedValue
        self.isStale = isStale
    }
}

public actor RefreshHistoryStore {
    private let fileURL: URL
    private let maxEntries: Int
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(fileURL: URL? = nil, maxEntries: Int = 500) throws {
        self.maxEntries = maxEntries
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let supportDirectory = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let appDirectory = supportDirectory.appendingPathComponent("Reservoir", isDirectory: true)
            try FileManager.default.createDirectory(at: appDirectory, withIntermediateDirectories: true)
            self.fileURL = appDirectory.appendingPathComponent("refresh-history.jsonl")
        }

        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    public func append(_ entry: RefreshHistoryEntry) async throws {
        var entries = try await load()
        entries.append(entry)
        if entries.count > maxEntries {
            entries = Array(entries.suffix(maxEntries))
        }
        try write(entries)
    }

    public func load() async throws -> [RefreshHistoryEntry] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let raw = try String(contentsOf: fileURL, encoding: .utf8)
        return raw
            .split(separator: "\n")
            .compactMap { line in
                guard let data = String(line).data(using: .utf8) else { return nil }
                return try? decoder.decode(RefreshHistoryEntry.self, from: data)
            }
    }

    public func clear() async throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }

    private func write(_ entries: [RefreshHistoryEntry]) throws {
        let lines = try entries.map { entry in
            let data = try encoder.encode(entry)
            return String(decoding: data, as: UTF8.self)
        }
        let data = lines.joined(separator: "\n").appending(lines.isEmpty ? "" : "\n").data(using: .utf8) ?? Data()
        try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }
}
