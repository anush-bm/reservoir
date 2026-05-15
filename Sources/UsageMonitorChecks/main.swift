import Foundation
import UsageMonitorCore

enum CheckFailure: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self {
        case .failed(let message): return message
        }
    }
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() {
        throw CheckFailure.failed(message)
    }
}

func runChecks() async throws {
    try checkCodexParser()
    try checkClaudeParser()
    try checkResetNormalization()
    try checkColorThresholds()
    try checkJSONParser()
    try await checkSnapshotStoreSecurity()
    try await checkRefreshHistorySecurity()
}

func checkCodexParser() throws {
    let text = """
    Balance Codex usage draws from your shared agentic usage limit
    5 hour usage limit 27% remaining Resets 10:30 PM
    Weekly usage limit 53% remaining Resets May 18, 2026 11:24 AM
    """

    guard let snapshot = UsageParsers.parseCodexVisibleText(text) else {
        throw CheckFailure.failed("Codex parser returned nil")
    }
    try expect(snapshot.id == .codex, "Codex snapshot id")
    try expect(snapshot.limits.count == 2, "Codex limit count")
    try expect(snapshot.limits.first { $0.label == "Current session" }?.percentRemaining == 27, "Codex current session remaining")
    try expect(snapshot.limits.first { $0.label == "Weekly" }?.percentRemaining == 53, "Codex weekly remaining")
    try expect(snapshot.limits.first { $0.label == "Weekly" }?.resetText?.contains("May 18, 2026") == true, "Codex reset date")
    try expect(snapshot.limits.map(\.label) == ["Current session", "Weekly"], "Codex limit order")
}

func checkClaudeParser() throws {
    let text = """
    Plan usage limits Pro
    Current session Resets 3:30 PM 0% used
    Weekly limits All models Resets Thu 10:30 PM 100% used
    Claude Design You haven't used Claude Design yet 0% used
    """

    guard let snapshot = UsageParsers.parseClaudeVisibleText(text) else {
        throw CheckFailure.failed("Claude parser returned nil")
    }
    try expect(snapshot.id == .claude, "Claude snapshot id")
    try expect(snapshot.limits.first { $0.label == "Current session" }?.percentRemaining == 100, "Claude session remaining")
    try expect(snapshot.limits.first { $0.label == "Current session" }?.resetText?.contains("2026") == true, "Claude session reset")
    try expect(snapshot.limits.first { $0.label == "Weekly" }?.percentRemaining == 0, "Claude weekly remaining")
    try expect(snapshot.limits.first { $0.label == "Weekly" }?.color == .red, "Claude weekly color")
}

func checkResetNormalization() throws {
    let calendar = Calendar(identifier: .gregorian)
    let now = calendar.date(from: DateComponents(timeZone: .current, year: 2026, month: 5, day: 14, hour: 10, minute: 30))!

    let claudeText = """
    Weekly limits All models Resets in 12 hr 1 min 60% used
    """
    guard let claude = UsageParsers.parseClaudeVisibleText(claudeText, now: now) else {
        throw CheckFailure.failed("Claude reset normalization returned nil")
    }
    try expect(claude.limits.first { $0.label == "Weekly" }?.resetText?.contains("2026") == true, "relative reset becomes absolute")

    let codexText = """
    5 hour usage limit 99% remaining Resets 3:28 PM
    """
    guard let codex = UsageParsers.parseCodexVisibleText(codexText, now: now) else {
        throw CheckFailure.failed("Codex reset normalization returned nil")
    }
    try expect(codex.limits.first { $0.label == "Current session" }?.resetText?.contains("May 14, 2026") == true, "clock reset gets date")
}


func checkColorThresholds() throws {
    try expect(UsageColorRules.color(forRemaining: 60) == .green, "green threshold")
    try expect(UsageColorRules.color(forRemaining: 30) == .yellow, "yellow threshold")
    try expect(UsageColorRules.color(forRemaining: 10) == .orange, "orange threshold")
    try expect(UsageColorRules.color(forRemaining: 9) == .red, "red threshold")
    try expect(UsageColorRules.color(forRemaining: nil) == .gray, "gray threshold")
    try expect(UsageColorRules.color(forRemaining: 99, justReset: true) == .blue, "blue threshold")
}

func checkJSONParser() throws {
    let provider = ProviderRegistry.defaults.first { $0.id == .codex }!
    let json: [String: Any] = [
        "limits": [
            [
                "label": "5 hour",
                "remaining_percent": 27,
                "reset_text": "May 13, 2026 10:30 PM"
            ]
        ]
    ]

    guard let snapshot = UsageParsers.parseProviderJSON(json, provider: provider) else {
        throw CheckFailure.failed("JSON parser returned nil")
    }
    try expect(snapshot.limits.first?.percentRemaining == 27, "JSON remaining")
    try expect(snapshot.limits.first?.source == .webAPI, "JSON source")
}

func checkSnapshotStoreSecurity() async throws {
    let fileURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension("json")
    defer { try? FileManager.default.removeItem(at: fileURL) }

    let store = try UsageSnapshotStore(fileURL: fileURL)
    let snapshot = ProviderSnapshot(
        id: .codex,
        name: "Codex",
        limits: [
            UsageLimit(
                provider: .codex,
                label: "5 hour",
                percentRemaining: 27,
                percentUsed: 73,
                resetText: "May 13, 2026 10:30 PM",
                color: .orange,
                source: .domText
            )
        ],
        lastUpdated: Date(timeIntervalSince1970: 1_778_699_000),
        sourceURL: URL(string: "https://chatgpt.com/codex/cloud/settings/analytics")!
    )

    try await store.save([.codex: snapshot])
    let raw = try String(contentsOf: fileURL, encoding: .utf8)
    try expect(raw.contains("percentRemaining"), "store has normalized field")
    try expect(!raw.localizedCaseInsensitiveContains("cookie"), "store does not contain cookie")
    try expect(!raw.localizedCaseInsensitiveContains("authorization"), "store does not contain authorization")
    try expect(!raw.localizedCaseInsensitiveContains("<html"), "store does not contain raw HTML")

    let loaded = try await store.load()
    try expect(loaded[.codex]?.limits.first?.percentRemaining == 27, "store round trip")
}

func checkRefreshHistorySecurity() async throws {
    let fileURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension("jsonl")
    defer { try? FileManager.default.removeItem(at: fileURL) }

    let store = try RefreshHistoryStore(fileURL: fileURL, maxEntries: 2)
    try await store.append(
        RefreshHistoryEntry(
            provider: .codex,
            timestamp: Date(timeIntervalSince1970: 1_778_699_000),
            status: "success",
            usedCachedValue: false,
            isStale: false
        )
    )
    try await store.append(
        RefreshHistoryEntry(
            provider: .claude,
            timestamp: Date(timeIntervalSince1970: 1_778_699_060),
            status: "failed",
            usedCachedValue: true,
            isStale: false
        )
    )
    try await store.append(
        RefreshHistoryEntry(
            provider: .codex,
            timestamp: Date(timeIntervalSince1970: 1_778_699_120),
            status: "failed",
            usedCachedValue: true,
            isStale: true
        )
    )

    let loaded = try await store.load()
    try expect(loaded.count == 2, "refresh history is capped")
    try expect(loaded.first?.provider == .claude, "refresh history keeps latest entries")

    let raw = try String(contentsOf: fileURL, encoding: .utf8)
    try expect(raw.contains("usedCachedValue"), "refresh history has normalized cache field")
    try expect(!raw.localizedCaseInsensitiveContains("https://"), "refresh history does not contain URLs")
    try expect(!raw.localizedCaseInsensitiveContains("cookie"), "refresh history does not contain cookie")
    try expect(!raw.localizedCaseInsensitiveContains("authorization"), "refresh history does not contain authorization")
    try expect(!raw.localizedCaseInsensitiveContains("<html"), "refresh history does not contain raw HTML")
}

do {
    try await runChecks()
    print("All UsageMonitorChecks passed")
} catch {
    fputs("UsageMonitorChecks failed: \(error)\n", stderr)
    exit(1)
}
