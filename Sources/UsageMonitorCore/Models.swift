import Foundation

public enum ProviderID: String, Codable, CaseIterable, Sendable, Identifiable {
    case codex
    case claude

    public var id: String { rawValue }
}

public enum UsageColor: String, Codable, Sendable {
    case green
    case yellow
    case orange
    case red
    case gray
    case blue
}

public enum UsageSource: String, Codable, Sendable {
    case webAPI
    case domText
    case cache
    case disconnected
    case unknown
}

public struct UsageLimit: Codable, Equatable, Sendable, Identifiable {
    public var id: String { "\(provider.rawValue)-\(label)" }
    public let provider: ProviderID
    public let label: String
    public let percentRemaining: Int?
    public let percentUsed: Int?
    public let resetText: String?
    public let resetAt: Date?
    public let color: UsageColor
    public let source: UsageSource

    public init(
        provider: ProviderID,
        label: String,
        percentRemaining: Int?,
        percentUsed: Int?,
        resetText: String?,
        resetAt: Date? = nil,
        color: UsageColor,
        source: UsageSource
    ) {
        self.provider = provider
        self.label = label
        self.percentRemaining = percentRemaining
        self.percentUsed = percentUsed
        self.resetText = resetText
        self.resetAt = resetAt
        self.color = color
        self.source = source
    }
}

public struct ProviderSnapshot: Codable, Equatable, Sendable, Identifiable {
    public let id: ProviderID
    public let name: String
    public let limits: [UsageLimit]
    public let lastUpdated: Date
    public let sourceURL: URL
    public let isStale: Bool
    public let statusMessage: String?

    public init(
        id: ProviderID,
        name: String,
        limits: [UsageLimit],
        lastUpdated: Date,
        sourceURL: URL,
        isStale: Bool = false,
        statusMessage: String? = nil
    ) {
        self.id = id
        self.name = name
        self.limits = limits
        self.lastUpdated = lastUpdated
        self.sourceURL = sourceURL
        self.isStale = isStale
        self.statusMessage = statusMessage
    }
}

public struct ProviderDefinition: Codable, Equatable, Sendable, Identifiable {
    public let id: ProviderID
    public let name: String
    public let sourceURL: URL
    public var isEnabled: Bool

    public init(id: ProviderID, name: String, sourceURL: URL, isEnabled: Bool = true) {
        self.id = id
        self.name = name
        self.sourceURL = sourceURL
        self.isEnabled = isEnabled
    }
}

public enum ProviderError: Error, LocalizedError, Sendable {
    case loggedOut(ProviderID)
    case parseFailed(ProviderID)
    case unavailable(ProviderID, String)

    public var errorDescription: String? {
        switch self {
        case .loggedOut(let id):
            return "\(id.rawValue) is not connected."
        case .parseFailed(let id):
            return "Could not read \(id.rawValue) usage."
        case .unavailable(let id, let message):
            return "\(id.rawValue) unavailable: \(message)"
        }
    }
}

public protocol ProviderCollector: Sendable {
    var definition: ProviderDefinition { get }
    func refresh() async throws -> ProviderSnapshot
    func clearSessionData() async
}
