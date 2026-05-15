import SwiftUI
import UsageMonitorCore

struct DashboardView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(appState.providers) { provider in
                        ProviderCard(
                            provider: provider,
                            snapshot: appState.snapshots[provider.id],
                            appState: appState
                        )
                    }
                }
                .padding(16)
            }
            footer
        }
        .frame(minWidth: 420, minHeight: 520)
    }

    private var header: some View {
        HStack {
            Text("Reservoir")
                .font(.system(size: 18, weight: .semibold))
            Spacer()
            Button {
                appState.refreshNow()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Refresh")
            .disabled(appState.isRefreshing)
        }
        .padding(16)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var footer: some View {
        HStack {
            Button("Clear cached usage") {
                appState.clearCachedUsage()
            }
            Spacer()
            Button("Privacy") {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
            Button("Quit") {
                NSApp.terminate(nil)
            }
        }
        .font(.system(size: 12))
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

struct ProviderCard: View {
    let provider: ProviderDefinition
    let snapshot: ProviderSnapshot?
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ProviderLogo(provider: provider, color: StatusIconRenderer.worstColor(in: snapshot))
                VStack(alignment: .leading, spacing: 2) {
                    Text(provider.name)
                        .font(.system(size: 15, weight: .semibold))
                    Text(statusText)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if snapshot?.limits.isEmpty != false {
                    Button {
                        appState.connectProvider(provider)
                    } label: {
                        Image(systemName: "person.crop.circle.badge.checkmark")
                    }
                    .help("Connect \(provider.name) in this app")
                }
                Button {
                    appState.openProviderPage(provider)
                } label: {
                    Image(systemName: "safari")
                }
                .help("Open \(provider.name) in your browser")
            }

            if let snapshot, !snapshot.limits.isEmpty {
                ForEach(UsageParsers.sortedLimits(snapshot.limits)) { limit in
                    UsageLimitRow(limit: limit)
                }
            } else {
                Text("Connect or sign in to read usage.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button(snapshot?.limits.isEmpty == false ? "Reconnect" : "Connect") {
                    appState.connectProvider(provider)
                }
                Button("Refresh") {
                    appState.refreshProvider(provider)
                }
                Button("Disconnect") {
                    appState.disconnectProvider(provider)
                }
                Spacer()
                Text(lastUpdatedText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var statusText: String {
        if let snapshot, snapshot.isStale {
            return snapshot.statusMessage ?? "Stale"
        }
        if let snapshot, let statusMessage = snapshot.statusMessage {
            return statusMessage
        }
        return snapshot == nil ? "Not connected" : "Connected"
    }

    private var lastUpdatedText: String {
        guard let snapshot else { return "Never updated" }
        return "Updated \(DateFormatters.relative.string(for: snapshot.lastUpdated) ?? "recently")"
    }
}

struct UsageLimitRow: View {
    let limit: UsageLimit

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(limit.label)
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                Text(percentText)
                    .font(.system(size: 13, weight: .semibold))
            }

            ProgressView(value: Double(limit.percentRemaining ?? 0), total: 100)
                .tint(Color(nsColor: StatusIconRenderer.nsColor(for: limit.color)))

            if let reset = limit.resetText {
                Text("Resets \(reset)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var percentText: String {
        guard let remaining = limit.percentRemaining else { return "Unknown" }
        return "\(remaining)% left"
    }
}

struct ProviderLogo: View {
    let provider: ProviderDefinition
    let color: UsageColor

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color(nsColor: StatusIconRenderer.nsColor(for: color)), lineWidth: 2)
                .frame(width: 28, height: 28)
            Text(provider.id == .codex ? "C" : "A")
                .font(.system(size: 13, weight: .semibold))
        }
        .help(provider.name)
    }
}

struct SettingsView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Privacy")
                .font(.title2.bold())
            Text("Reservoir stores only normalized local snapshots. It does not use API keys, telemetry, remote logging, or third-party network libraries.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            Button("Clear cached usage") {
                appState.clearCachedUsage()
            }
            Button("Clear browser session") {
                appState.clearBrowserSession()
            }

            Divider()

            ForEach(appState.providers) { provider in
                HStack {
                    Text(provider.name)
                    Spacer()
                    Button("Open page") {
                        appState.openProviderPage(provider)
                    }
                    Button("Disconnect") {
                        appState.disconnectProvider(provider)
                    }
                }
            }
        }
        .padding(24)
        .frame(width: 520)
    }
}

enum DateFormatters {
    @MainActor
    static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()
}
