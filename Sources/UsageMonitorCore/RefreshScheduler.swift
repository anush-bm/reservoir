import Foundation

public actor RefreshScheduler {
    public enum Mode: Sendable {
        case background
        case foreground
    }

    public static let backgroundInterval: TimeInterval = 300
    public static let foregroundInterval: TimeInterval = 60

    private let jitterRange: ClosedRange<TimeInterval>

    public init(jitterRange: ClosedRange<TimeInterval> = 5...20) {
        self.jitterRange = jitterRange
    }

    public func interval(for mode: Mode) -> TimeInterval {
        switch mode {
        case .background:
            return Self.backgroundInterval
        case .foreground:
            return Self.foregroundInterval
        }
    }

    public func nextDelay(for mode: Mode) -> TimeInterval {
        interval(for: mode) + TimeInterval.random(in: jitterRange)
    }
}
