import AppKit
import Foundation
import SwiftUI
import UsageMonitorCore
import WebKit

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var snapshots: [ProviderID: ProviderSnapshot] = [:]
    @Published private(set) var isRefreshing = false
    @Published var foregroundWindowOpen = false {
        didSet { restartTimer() }
    }

    var onSnapshotsChanged: (() -> Void)?

    private let registry = ProviderRegistry()
    private let logger = SecureLog()
    private let scheduler = RefreshScheduler()
    private var store: UsageSnapshotStore?
    private var historyStore: RefreshHistoryStore?
    private var refreshTask: Task<Void, Never>?
    private var timerTask: Task<Void, Never>?
    private var connectWindows: [ProviderID: ConnectWindowController] = [:]
    private var scheduledRefreshEnabled = false

    var providers: [ProviderDefinition] {
        registry.providers
    }

    func start() {
        do {
            store = try UsageSnapshotStore()
            historyStore = try RefreshHistoryStore()
        } catch {
            logger.refreshFinished(provider: .codex, status: "store_init_failed")
        }

        Task { [weak self] in
            guard let self else { return }
            if let loaded = try? await store?.load() {
                snapshots = loaded
                onSnapshotsChanged?()
            }
            if !snapshots.isEmpty {
                scheduledRefreshEnabled = true
                restartTimer()
                if shouldRefreshOnStartup(snapshots: snapshots) {
                    refreshNow()
                }
            }
        }
    }

    func stop() {
        timerTask?.cancel()
        refreshTask?.cancel()
    }

    func refreshNow() {
        scheduledRefreshEnabled = true
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            await self?.refreshProviders(self?.registry.enabledProviders() ?? [])
            self?.restartTimer()
        }
    }

    func openProviderPage(_ provider: ProviderDefinition) {
        NSWorkspace.shared.open(provider.sourceURL)
    }

    func connectProvider(_ provider: ProviderDefinition) {
        let controller = ConnectWindowController(provider: provider) { [weak self] in
            self?.connectWindows.removeValue(forKey: provider.id)
            self?.refreshProvider(provider)
        }
        connectWindows[provider.id] = controller
        controller.show()
    }

    func refreshProvider(_ provider: ProviderDefinition) {
        scheduledRefreshEnabled = true
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            await self?.refreshProviders([provider])
            self?.restartTimer()
        }
    }

    func clearCachedUsage() {
        Task { [weak self] in
            guard let self else { return }
            try? await store?.clear()
            try? await historyStore?.clear()
            snapshots = [:]
            onSnapshotsChanged?()
        }
    }

    func clearBrowserSession() {
        Task {
            let dataStore = WKWebsiteDataStore.default()
            let dataTypes = WKWebsiteDataStore.allWebsiteDataTypes()
            let records = await dataStore.dataRecords(ofTypes: dataTypes)
            let providerHosts = Set(registry.providers.compactMap { $0.sourceURL.host })
            let matching = records.filter { record in
                providerHosts.contains { host in
                    record.displayName.contains(host) || host.contains(record.displayName)
                }
            }
            await dataStore.removeData(ofTypes: dataTypes, for: matching)
        }
    }

    func disconnectProvider(_ provider: ProviderDefinition) {
        snapshots.removeValue(forKey: provider.id)
        onSnapshotsChanged?()
        Task {
            try? await store?.save(snapshots)
            await clearSessionData(for: provider)
        }
    }

    private func restartTimer() {
        timerTask?.cancel()
        guard scheduledRefreshEnabled else { return }
        timerTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                let mode: RefreshScheduler.Mode = foregroundWindowOpen ? .foreground : .background
                let delay = await scheduler.nextDelay(for: mode)
                try? await Task.sleep(for: .seconds(delay))
                if Task.isCancelled { break }
                await refreshProviders(registry.enabledProviders())
            }
        }
    }

    private func refreshProviders(_ providers: [ProviderDefinition]) async {
        if isRefreshing { return }
        isRefreshing = true
        defer { isRefreshing = false }

        var updated = snapshots
        for provider in providers where provider.isEnabled {
            logger.refreshStarted(provider: provider.id)
            do {
                let snapshot = try await WebUsageCollector(definition: provider).refresh()
                updated[provider.id] = snapshot
                logger.parseResult(provider: provider.id, success: true)
                logger.refreshFinished(provider: provider.id, status: "success")
                await recordRefresh(provider: provider.id, status: "success", usedCachedValue: false, isStale: false)
            } catch {
                logger.parseResult(provider: provider.id, success: false)
                logger.refreshFinished(provider: provider.id, status: "failed")
                let safeMessage = error.localizedDescription
                if let cached = updated[provider.id] {
                    let age = Date().timeIntervalSince(cached.lastUpdated)
                    let shouldMarkStale = age > 30 * 60
                    updated[provider.id] = ProviderSnapshot(
                        id: cached.id,
                        name: cached.name,
                        limits: cached.limits,
                        lastUpdated: cached.lastUpdated,
                        sourceURL: cached.sourceURL,
                        isStale: shouldMarkStale,
                        statusMessage: shouldMarkStale ? "Refresh failed. Showing last good data." : "Last refresh failed; retry later."
                    )
                    await recordRefresh(provider: provider.id, status: "failed", usedCachedValue: true, isStale: shouldMarkStale)
                } else {
                    updated[provider.id] = ProviderSnapshot(
                        id: provider.id,
                        name: provider.name,
                        limits: [],
                        lastUpdated: Date(),
                        sourceURL: provider.sourceURL,
                        isStale: true,
                        statusMessage: safeMessage
                    )
                    await recordRefresh(provider: provider.id, status: "failed", usedCachedValue: false, isStale: true)
                }
            }
            try? await Task.sleep(for: .seconds(1))
        }

        snapshots = updated
        try? await store?.save(updated)
        onSnapshotsChanged?()
    }

    private func clearSessionData(for provider: ProviderDefinition) async {
        await WebUsageCollector(definition: provider).clearSessionData()
    }

    private func shouldRefreshOnStartup(snapshots: [ProviderID: ProviderSnapshot]) -> Bool {
        let staleThreshold: TimeInterval = 10 * 60
        return snapshots.values.contains { snapshot in
            snapshot.isStale || Date().timeIntervalSince(snapshot.lastUpdated) > staleThreshold
        }
    }

    private func recordRefresh(provider: ProviderID, status: String, usedCachedValue: Bool, isStale: Bool) async {
        try? await historyStore?.append(
            RefreshHistoryEntry(
                provider: provider,
                status: status,
                usedCachedValue: usedCachedValue,
                isStale: isStale
            )
        )
    }
}
