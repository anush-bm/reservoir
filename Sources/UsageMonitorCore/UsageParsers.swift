import Foundation

public enum UsageParsers {
    public static func parseCodexVisibleText(_ text: String, now: Date = Date()) -> ProviderSnapshot? {
        parseRemainingProvider(
            id: .codex,
            name: "Codex",
            sourceURL: ProviderRegistry.defaults.first { $0.id == .codex }!.sourceURL,
            text: text,
            labels: [
                "5 hour usage limit": "Current session",
                "Weekly usage limit": "Weekly"
            ],
            now: now
        )
    }

    public static func parseClaudeVisibleText(_ text: String, now: Date = Date()) -> ProviderSnapshot? {
        let normalized = normalizedText(text)
        var limits: [UsageLimit] = []

        if let sessionUsed = firstPercent(beforeOrAfter: "Current session", in: normalized, suffix: "used") {
            let reset = normalizedResetText(resetText(after: "Current session", in: normalized), now: now)
            limits.append(usedLimit(provider: .claude, label: "Current session", used: sessionUsed, resetText: reset))
        }

        if let weeklyUsed = firstPercent(beforeOrAfter: "Weekly limits", in: normalized, suffix: "used")
            ?? firstPercent(beforeOrAfter: "All models", in: normalized, suffix: "used") {
            let reset = normalizedResetText(
                resetText(after: "All models", in: normalized) ?? resetText(after: "Weekly limits", in: normalized),
                now: now
            )
            limits.append(usedLimit(provider: .claude, label: "Weekly", used: weeklyUsed, resetText: reset))
        }

        if limits.isEmpty {
            return nil
        }

        return ProviderSnapshot(
            id: .claude,
            name: "Claude",
            limits: sortedLimits(limits),
            lastUpdated: now,
            sourceURL: ProviderRegistry.defaults.first { $0.id == .claude }!.sourceURL
        )
    }

    public static func parseProviderJSON(_ json: Any, provider: ProviderDefinition, now: Date = Date()) -> ProviderSnapshot? {
        guard let root = json as? [String: Any] else { return nil }
        let limitsArray = root["limits"] as? [[String: Any]]
            ?? root["usage_limits"] as? [[String: Any]]
            ?? root["usageLimits"] as? [[String: Any]]
            ?? []

        let limits = limitsArray.compactMap { item -> UsageLimit? in
            guard let rawLabel = item["label"] as? String ?? item["name"] as? String else { return nil }
            let remaining = intValue(item["remaining_percent"])
                ?? intValue(item["remainingPercent"])
                ?? intValue(item["percent_remaining"])
            let used = intValue(item["used_percent"])
                ?? intValue(item["usedPercent"])
                ?? intValue(item["percent_used"])
            let computedRemaining = remaining ?? used.map { UsageColorRules.normalizePercent(100 - $0) }
            let resetText = item["reset"] as? String
                ?? item["reset_text"] as? String
                ?? item["resetText"] as? String
            return UsageLimit(
                provider: provider.id,
                label: rawLabel,
                percentRemaining: computedRemaining,
                percentUsed: used,
                resetText: resetText,
                color: UsageColorRules.color(forRemaining: computedRemaining),
                source: .webAPI
            )
        }

        guard !limits.isEmpty else { return nil }
        return ProviderSnapshot(
            id: provider.id,
            name: provider.name,
            limits: sortedLimits(limits),
            lastUpdated: now,
            sourceURL: provider.sourceURL
        )
    }

    private static func parseRemainingProvider(
        id: ProviderID,
        name: String,
        sourceURL: URL,
        text: String,
        labels: [String: String],
        now: Date
    ) -> ProviderSnapshot? {
        let normalized = normalizedText(text)
        let limits = labels.compactMap { marker, label -> UsageLimit? in
            guard let remaining = firstPercent(beforeOrAfter: marker, in: normalized, suffix: "remaining") else {
                return nil
            }
            let reset = normalizedResetText(resetText(after: marker, in: normalized), now: now)
            return UsageLimit(
                provider: id,
                label: label,
                percentRemaining: remaining,
                percentUsed: 100 - remaining,
                resetText: reset,
                color: UsageColorRules.color(forRemaining: remaining),
                source: .domText
            )
        }

        guard !limits.isEmpty else { return nil }
        return ProviderSnapshot(id: id, name: name, limits: sortedLimits(limits), lastUpdated: now, sourceURL: sourceURL)
    }

    private static func usedLimit(provider: ProviderID, label: String, used: Int, resetText: String?) -> UsageLimit {
        let normalizedUsed = UsageColorRules.normalizePercent(used)
        let remaining = UsageColorRules.normalizePercent(100 - normalizedUsed)
        return UsageLimit(
            provider: provider,
            label: label,
            percentRemaining: remaining,
            percentUsed: normalizedUsed,
            resetText: resetText,
            color: UsageColorRules.color(forRemaining: remaining),
            source: .domText
        )
    }

    public static func sortedLimits(_ limits: [UsageLimit]) -> [UsageLimit] {
        limits.sorted { lhs, rhs in
            sortRank(lhs.label) < sortRank(rhs.label)
        }
    }

    private static func sortRank(_ label: String) -> Int {
        let normalized = label.lowercased()
        if normalized.contains("current") || normalized.contains("session") || normalized.contains("5 hour") {
            return 0
        }
        if normalized.contains("weekly") || normalized.contains("week") {
            return 1
        }
        return 2
    }

    private static func normalizedText(_ text: String) -> String {
        text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func firstPercent(beforeOrAfter marker: String, in text: String, suffix: String) -> Int? {
        guard let markerRange = text.range(of: marker, options: [.caseInsensitive]) else {
            return firstPercent(in: text, suffix: suffix)
        }

        let tail = String(text[markerRange.lowerBound...])
        return firstPercent(in: tail, suffix: suffix)
    }

    private static func firstPercent(in text: String, suffix: String) -> Int? {
        let pattern = #"(\d{1,3})\s*%\s*\#(suffix)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: nsRange),
              let range = Range(match.range(at: 1), in: text),
              let value = Int(text[range]) else {
            return nil
        }
        return UsageColorRules.normalizePercent(value)
    }

    private static func resetText(after marker: String, in text: String) -> String? {
        let startIndex: String.Index
        if let markerRange = text.range(of: marker, options: [.caseInsensitive]) {
            startIndex = markerRange.lowerBound
        } else {
            startIndex = text.startIndex
        }

        let tail = String(text[startIndex...])
        let patterns = [
            #"Resets\s+([^\.]+?)(?:\s+\d{1,3}%|\s+[A-Z][a-z]+ usage limit|$)"#,
            #"resets\s+([^\.]+?)(?:\s+\d{1,3}%|$)"#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let nsRange = NSRange(tail.startIndex..<tail.endIndex, in: tail)
            guard let match = regex.firstMatch(in: tail, range: nsRange),
                  let range = Range(match.range(at: 1), in: tail) else {
                continue
            }
            return String(tail[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    private static func normalizedResetText(_ raw: String?, now: Date) -> String? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }

        if let relativeDate = dateFromRelativeReset(raw, now: now) {
            return resetDateFormatter.string(from: relativeDate)
        }

        if let clockDate = dateFromClockReset(raw, now: now) {
            return resetDateFormatter.string(from: clockDate)
        }

        return raw
    }

    private static func dateFromRelativeReset(_ raw: String, now: Date) -> Date? {
        let pattern = #"^in\s+(?:(\d+)\s*h(?:r|our)?s?)?\s*(?:(\d+)\s*m(?:in|inute)?s?)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let nsRange = NSRange(raw.startIndex..<raw.endIndex, in: raw)
        guard let match = regex.firstMatch(in: raw, range: nsRange), match.range.location != NSNotFound else {
            return nil
        }

        let hours = intCapture(match, index: 1, in: raw) ?? 0
        let minutes = intCapture(match, index: 2, in: raw) ?? 0
        guard hours > 0 || minutes > 0 else { return nil }
        return Calendar.current.date(byAdding: DateComponents(hour: hours, minute: minutes), to: now)
    }

    private static func dateFromClockReset(_ raw: String, now: Date) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "h:mm a"
        guard let clockOnly = formatter.date(from: raw) else { return nil }

        let calendar = Calendar.current
        let clockComponents = calendar.dateComponents([.hour, .minute], from: clockOnly)
        var todayComponents = calendar.dateComponents([.year, .month, .day], from: now)
        todayComponents.hour = clockComponents.hour
        todayComponents.minute = clockComponents.minute
        todayComponents.second = 0

        guard let today = calendar.date(from: todayComponents) else { return nil }
        if today >= now {
            return today
        }
        return calendar.date(byAdding: .day, value: 1, to: today)
    }

    private static func intCapture(_ match: NSTextCheckingResult, index: Int, in text: String) -> Int? {
        guard match.numberOfRanges > index,
              match.range(at: index).location != NSNotFound,
              let range = Range(match.range(at: index), in: text) else {
            return nil
        }
        return Int(text[range])
    }

    private static let resetDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d, yyyy h:mm a"
        return formatter
    }()

    private static func intValue(_ value: Any?) -> Int? {
        switch value {
        case let int as Int:
            return UsageColorRules.normalizePercent(int)
        case let double as Double:
            return UsageColorRules.normalizePercent(Int(double.rounded()))
        case let string as String:
            return Int(string).map(UsageColorRules.normalizePercent)
        default:
            return nil
        }
    }
}
