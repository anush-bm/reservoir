import Foundation

public enum UsageColorRules {
    public static func color(forRemaining percent: Int?, justReset: Bool = false) -> UsageColor {
        guard let percent else { return .gray }
        if justReset { return .blue }
        switch percent {
        case 60...100:
            return .green
        case 30...59:
            return .yellow
        case 10...29:
            return .orange
        case 0...9:
            return .red
        default:
            return .gray
        }
    }

    public static func normalizePercent(_ percent: Int) -> Int {
        max(0, min(100, percent))
    }
}
