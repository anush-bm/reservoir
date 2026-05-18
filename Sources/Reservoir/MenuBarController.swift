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
        self.statusItem = NSStatusBar.system.statusItem(withLength: 74)
        self.popover.behavior = .transient
        self.popover.contentSize = NSSize(width: 420, height: 520)
        self.popover.contentViewController = NSHostingController(rootView: DashboardView(appState: appState))

        if let button = statusItem.button {
            button.action = #selector(togglePopover(_:))
            button.target = self
            button.image = nil
            button.imagePosition = .noImage
            button.title = ""
            button.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
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
        button.image = nil
        button.attributedTitle = NSAttributedString(string: "")
        button.title = display.title
        button.contentTintColor = display.color
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
    static func menuBarDisplay(for providers: [ProviderDefinition], snapshots: [ProviderID: ProviderSnapshot]) -> (title: String, color: NSColor, width: CGFloat) {
        let items = menuBarLimits(for: providers, snapshots: snapshots)
        let title = items.isEmpty ? "C-- A--" : items.map(menuBarTitle).joined(separator: " ")
        let color = items
            .map { $0.isStale ? UsageColor.gray : $0.limit.color }
            .min(by: colorRank) ?? .gray
        let width = max(54, min(92, CGFloat(title.count * 7 + 14)))
        return (title, nsColor(for: color), width)
    }

    static func image(for providers: [ProviderDefinition], snapshots: [ProviderID: ProviderSnapshot]) -> NSImage {
        let size = NSSize(width: 54, height: 20)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor(calibratedRed: 0.02, green: 0.48, blue: 0.68, alpha: 1).setFill()
        NSRect(origin: .zero, size: size).fill()

        drawReservoirMark(in: NSRect(x: 7, y: 3, width: 14, height: 14))
        drawPercentText(percentText(for: providers, snapshots: snapshots), at: NSPoint(x: 25, y: 4))

        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    private static func drawReservoirMark(in rect: NSRect) {
        NSColor(calibratedWhite: 0.68, alpha: 1).setFill()
        let drop = NSBezierPath()
        drop.move(to: NSPoint(x: rect.midX, y: rect.maxY))
        drop.curve(
            to: NSPoint(x: rect.maxX, y: rect.midY - 1),
            controlPoint1: NSPoint(x: rect.midX + 5, y: rect.maxY - 5),
            controlPoint2: NSPoint(x: rect.maxX, y: rect.midY + 4)
        )
        drop.curve(
            to: NSPoint(x: rect.midX, y: rect.minY),
            controlPoint1: NSPoint(x: rect.maxX, y: rect.minY + 3),
            controlPoint2: NSPoint(x: rect.midX + 4, y: rect.minY)
        )
        drop.curve(
            to: NSPoint(x: rect.minX, y: rect.midY - 1),
            controlPoint1: NSPoint(x: rect.midX - 4, y: rect.minY),
            controlPoint2: NSPoint(x: rect.minX, y: rect.minY + 3)
        )
        drop.curve(
            to: NSPoint(x: rect.midX, y: rect.maxY),
            controlPoint1: NSPoint(x: rect.minX, y: rect.midY + 4),
            controlPoint2: NSPoint(x: rect.midX - 5, y: rect.maxY - 5)
        )
        drop.close()
        drop.fill()
    }

    private static func drawPercentText(_ label: String, at point: NSPoint) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .bold),
            .foregroundColor: NSColor.white
        ]
        label.draw(at: point, withAttributes: attributes)
    }

    private static func percentText(for providers: [ProviderDefinition], snapshots: [ProviderID: ProviderSnapshot]) -> String {
        let items = menuBarLimits(for: providers, snapshots: snapshots)
        guard !items.isEmpty else { return "--%" }
        return items.map { "\($0.limit.percentRemaining ?? 0)%" }.joined(separator: " ")
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

    private static func menuBarTitle(for item: MenuBarLimit) -> String {
        let provider = providerAbbreviation(item.provider)
        let percent = item.limit.percentRemaining.map { "\($0)%" } ?? "--%"
        let stale = item.isStale ? "*" : ""
        return "\(provider)\(percent)\(stale)"
    }

    private static func providerAbbreviation(_ provider: ProviderDefinition) -> String {
        switch provider.id {
        case .codex: return "C"
        case .claude: return "A"
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
