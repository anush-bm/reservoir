import Foundation
import os

public struct SecureLog: Sendable {
    private let logger: Logger

    public init(subsystem: String = "local.reservoir", category: String = "usage") {
        self.logger = Logger(subsystem: subsystem, category: category)
    }

    public func refreshStarted(provider: ProviderID, at date: Date = Date()) {
        logger.info("refresh_started provider=\(provider.rawValue, privacy: .public) timestamp=\(date.ISO8601Format(), privacy: .public)")
    }

    public func refreshFinished(provider: ProviderID, status: String, at date: Date = Date()) {
        logger.info("refresh_finished provider=\(provider.rawValue, privacy: .public) status=\(status, privacy: .public) timestamp=\(date.ISO8601Format(), privacy: .public)")
    }

    public func parseResult(provider: ProviderID, success: Bool, at date: Date = Date()) {
        logger.info("parse_result provider=\(provider.rawValue, privacy: .public) success=\(success, privacy: .public) timestamp=\(date.ISO8601Format(), privacy: .public)")
    }
}
