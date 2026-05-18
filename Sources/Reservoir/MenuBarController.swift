import AppKit
import SwiftUI
import UsageMonitorCore

@MainActor
final class MenuBarController {
    private let appState: AppState
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private var eventMonitor: Any?

    init(appState: AppState) {
        self.appState = appState
        self.statusItem = NSStatusBar.system.statusItem(withLength: 30)
        self.popover.behavior = .transient
        self.popover.contentSize = NSSize(width: 420, height: 520)
        self.popover.contentViewController = NSHostingController(rootView: DashboardView(appState: appState))

        if let button = statusItem.button {
            button.action = #selector(togglePopover(_:))
            button.target = self
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleNone
            button.title = ""
            button.setAccessibilityLabel("Reservoir usage monitor")
        }

        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.closePopover() }
        }

        refreshStatusItem()
    }

    func refreshStatusItem() {
        guard let button = statusItem.button else { return }
        let display = StatusIconRenderer.menuBarDisplay(for: appState.providers, snapshots: appState.snapshots)
        button.image = display.image
        button.attributedTitle = NSAttributedString(string: "")
        button.title = ""
        button.contentTintColor = nil
        statusItem.length = display.width
        button.toolTip = tooltip()
    }

    func showPopover() -> Bool {
        refreshStatusItem()
        guard let button = statusItem.button else { return false }
        if popover.isShown {
            return true
        }
        appState.foregroundWindowOpen = true
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
        return true
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            closePopover()
        } else {
            _ = showPopover()
        }
    }

    private func closePopover() {
        if popover.isShown {
            popover.performClose(nil)
            appState.foregroundWindowOpen = false
        }
    }

    private func tooltip() -> String {
        appState.providers.map { provider in
            guard let snapshot = appState.snapshots[provider.id], !snapshot.limits.isEmpty else {
                return "\(provider.name): not connected"
            }
            let pieces = snapshot.limits.map { limit in
                let percent = limit.percentRemaining.map { "\($0)% left" } ?? "unknown"
                let reset = limit.resetText.map { ", resets \($0)" } ?? ""
                return "\(limit.label) \(percent)\(reset)"
            }
            let updated = DateFormatter.localizedString(from: snapshot.lastUpdated, dateStyle: .medium, timeStyle: .short)
            return "\(provider.name): \(pieces.joined(separator: ", "))\nUpdated \(updated)"
        }.joined(separator: "\n")
    }
}

enum StatusIconRenderer {
    static func menuBarDisplay(for providers: [ProviderDefinition], snapshots: [ProviderID: ProviderSnapshot]) -> (image: NSImage, width: CGFloat) {
        let items = menuBarLimits(for: providers, snapshots: snapshots)
        let worst = items.min { lhs, rhs in
            (lhs.limit.percentRemaining ?? 101) < (rhs.limit.percentRemaining ?? 101)
        }
        let percent = worst?.limit.percentRemaining
        let color = worst.map { $0.isStale ? UsageColor.gray : $0.limit.color } ?? .gray
        return (compactPercentImage(percent: percent, color: color), 30)
    }

    private static func compactPercentImage(percent: Int?, color: UsageColor) -> NSImage {
        let size = NSSize(width: 26, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()
        nsColor(for: color).setFill()
        NSBezierPath(roundedRect: NSRect(x: 0, y: 1, width: size.width, height: 16), xRadius: 4, yRadius: 4).fill()
        drawPercentText(percent.map { "\($0)" } ?? "--", in: NSRect(x: 0, y: 3, width: size.width, height: 12))

        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    private static func drawPercentText(_ label: String, in rect: NSRect) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .bold),
            .foregroundColor: NSColor.white
        ]
        let text = NSString(string: label)
        let textSize = text.size(withAttributes: attributes)
        let point = NSPoint(
            x: rect.midX - textSize.width / 2,
            y: rect.midY - textSize.height / 2
        )
        text.draw(at: point, withAttributes: attributes)
    }

    static func worstColor(in snapshot: ProviderSnapshot?) -> UsageColor {
        guard let snapshot, !snapshot.isStale else { return .gray }
        return snapshot.limits.map(\.color).min(by: colorRank) ?? .gray
    }

    private static func menuBarLimits(for providers: [ProviderDefinition], snapshots: [ProviderID: ProviderSnapshot]) -> [MenuBarLimit] {
        providers.compactMap { provider -> MenuBarLimit? in
            guard let snapshot = snapshots[provider.id] else { return nil }
            let limitsWithPercent = snapshot.limits.filter { $0.percentRemaining != nil }
            let limit = limitsWithPercent.first { $0.label.localizedCaseInsensitiveContains("current") }
                ?? limitsWithPercent.min { lhs, rhs in
                    (lhs.percentRemaining ?? 101) < (rhs.percentRemaining ?? 101)
                }
            guard let limit else { return nil }
            return MenuBarLimit(provider: provider, limit: limit, isStale: snapshot.isStale)
        }
    }

    static func nsColor(for color: UsageColor) -> NSColor {
        switch color {
        case .green: return NSColor.systemGreen
        case .yellow: return NSColor.systemYellow
        case .orange: return NSColor.systemOrange
        case .red: return NSColor.systemRed
        case .gray: return NSColor.systemGray
        case .blue: return NSColor.systemBlue
        }
    }

    private static func colorRank(_ lhs: UsageColor, _ rhs: UsageColor) -> Bool {
        rank(lhs) < rank(rhs)
    }

    private static func rank(_ color: UsageColor) -> Int {
        switch color {
        case .red: return 0
        case .orange: return 1
        case .yellow: return 2
        case .green: return 3
        case .blue: return 4
        case .gray: return 5
        }
    }

    private struct MenuBarLimit {
        let provider: ProviderDefinition
        let limit: UsageLimit
        let isStale: Bool
    }
}
