import AppKit
import SwiftUI
import UsageMonitorCore

@MainActor
final class StatusBuddyController {
    private let appState: AppState
    private let onClick: () -> Void
    private let panel: NSPanel
    private let model = StatusBuddyModel()
    private var timer: Timer?
    private var direction: CGFloat = 1
    private var progress: CGFloat = 0

    init(appState: AppState, onClick: @escaping () -> Void) {
        self.appState = appState
        self.onClick = onClick
        self.panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 88, height: 112),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        panel.contentViewController = NSHostingController(
            rootView: StatusBuddyView(model: model) { [weak self] in
                self?.onClick()
            }
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func sync() {
        updateStatus()
        if appState.showDockBuddy {
            show()
        } else {
            hide()
        }
    }

    func updateStatus() {
        let status = StatusBuddyStatus.make(providers: appState.providers, snapshots: appState.snapshots)
        model.color = StatusIconRenderer.nsColor(for: status.color)
        model.percentText = status.percentText
        model.isTired = status.isTired
        model.isStale = status.isStale
    }

    private func show() {
        position()
        panel.orderFrontRegardless()
        startTimer()
    }

    private func hide() {
        stopTimer()
        panel.orderOut(nil)
    }

    private func startTimer() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 24.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard appState.showDockBuddy else {
            hide()
            return
        }

        let speed: CGFloat = model.isTired ? 0.0025 : 0.0045
        progress += speed * direction
        if progress >= 1 {
            progress = 1
            direction = -1
        } else if progress <= 0 {
            progress = 0
            direction = 1
        }
        model.phase += model.isTired ? 0.07 : 0.12
        model.facingRight = direction > 0
        position()
    }

    @objc private func screenParametersChanged() {
        position()
    }

    private func position() {
        guard let screen = NSScreen.main else { return }
        let placement = DockBuddyPlacement(screen: screen, panelSize: panel.frame.size)
        panel.setFrameOrigin(placement.point(progress: progress))
    }
}

@MainActor
final class StatusBuddyModel: ObservableObject {
    @Published var color: NSColor = .systemGray
    @Published var percentText: String = "--"
    @Published var phase: Double = 0
    @Published var facingRight = true
    @Published var isTired = false
    @Published var isStale = true
}

private struct StatusBuddyStatus {
    let color: UsageColor
    let percentText: String
    let isTired: Bool
    let isStale: Bool

    static func make(providers: [ProviderDefinition], snapshots: [ProviderID: ProviderSnapshot]) -> StatusBuddyStatus {
        let limits = providers.compactMap { provider -> (limit: UsageLimit, stale: Bool)? in
            guard let snapshot = snapshots[provider.id] else { return nil }
            let current = snapshot.limits.first {
                $0.label.localizedCaseInsensitiveContains("current") && $0.percentRemaining != nil
            }
            guard let limit = current else { return nil }
            return (limit, snapshot.isStale)
        }

        guard let worst = limits.min(by: { lhs, rhs in
            (lhs.limit.percentRemaining ?? 101) < (rhs.limit.percentRemaining ?? 101)
        }) else {
            return StatusBuddyStatus(color: .gray, percentText: "--", isTired: true, isStale: true)
        }

        let remaining = worst.limit.percentRemaining ?? 0
        let stale = worst.stale
        return StatusBuddyStatus(
            color: stale ? .gray : worst.limit.color,
            percentText: "\(remaining)",
            isTired: stale || remaining < 30,
            isStale: stale
        )
    }
}

private struct DockBuddyPlacement {
    private let frame: NSRect
    private let visibleFrame: NSRect
    private let panelSize: NSSize
    private let padding: CGFloat = 10

    init(screen: NSScreen, panelSize: NSSize) {
        self.frame = screen.frame
        self.visibleFrame = screen.visibleFrame
        self.panelSize = panelSize
    }

    func point(progress: CGFloat) -> NSPoint {
        let clamped = max(0, min(1, progress))
        let bottomGap = visibleFrame.minY - frame.minY
        let leftGap = visibleFrame.minX - frame.minX
        let rightGap = frame.maxX - visibleFrame.maxX

        if bottomGap > 40 {
            let minX = visibleFrame.minX + padding
            let maxX = visibleFrame.maxX - panelSize.width - padding
            return NSPoint(
                x: minX + (maxX - minX) * clamped,
                y: visibleFrame.minY + padding
            )
        }

        if leftGap > 40 {
            let minY = visibleFrame.minY + padding
            let maxY = visibleFrame.maxY - panelSize.height - padding
            return NSPoint(
                x: visibleFrame.minX + padding,
                y: minY + (maxY - minY) * clamped
            )
        }

        if rightGap > 40 {
            let minY = visibleFrame.minY + padding
            let maxY = visibleFrame.maxY - panelSize.height - padding
            return NSPoint(
                x: visibleFrame.maxX - panelSize.width - padding,
                y: minY + (maxY - minY) * clamped
            )
        }

        return NSPoint(
            x: visibleFrame.maxX - panelSize.width - padding,
            y: visibleFrame.minY + padding
        )
    }
}

struct StatusBuddyView: View {
    @ObservedObject var model: StatusBuddyModel
    let onClick: () -> Void

    var body: some View {
        Button(action: onClick) {
            ZStack {
                speechBubble
                    .offset(y: -38)
                character
            }
            .frame(width: 88, height: 112)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Open Reservoir")
    }

    private var speechBubble: some View {
        Text(model.percentText)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: 42, height: 26)
            .background(Color(nsColor: model.color))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(.white.opacity(0.85), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.22), radius: 2, x: 0, y: 1)
            .opacity(model.isStale ? 0.72 : 1)
    }

    private var character: some View {
        let bob = model.isTired ? sin(model.phase) * 1.5 : sin(model.phase) * 3.5
        let foot = sin(model.phase) * (model.isTired ? 1.5 : 4.0)

        return ZStack {
            Capsule()
                .fill(Color(nsColor: model.color).opacity(model.isStale ? 0.45 : 0.96))
                .frame(width: 38, height: 56)
                .overlay(
                    Capsule()
                        .stroke(.white.opacity(0.18), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
                .offset(y: 10 + bob)

            Circle()
                .fill(Color.white.opacity(model.isStale ? 0.55 : 0.95))
                .frame(width: 31, height: 28)
                .offset(y: -18 + bob)

            HStack(spacing: 5) {
                Circle().fill(.black.opacity(0.72)).frame(width: 4, height: 4)
                Circle().fill(.black.opacity(0.72)).frame(width: 4, height: 4)
            }
            .offset(y: -20 + bob)

            Capsule()
                .fill(Color.black.opacity(0.85))
                .frame(width: 23, height: 9)
                .offset(y: -35 + bob)

            HStack(spacing: 12) {
                Capsule()
                    .fill(Color(nsColor: model.color).opacity(model.isStale ? 0.35 : 0.78))
                    .frame(width: 10, height: 35)
                    .overlay(
                        Capsule()
                            .stroke(.white.opacity(0.08), lineWidth: 1)
                    )
                    .rotationEffect(.degrees(model.facingRight ? -7 : 7))
                Capsule()
                    .fill(Color(nsColor: model.color).opacity(model.isStale ? 0.35 : 0.78))
                    .frame(width: 10, height: 35)
                    .overlay(
                        Capsule()
                            .stroke(.white.opacity(0.08), lineWidth: 1)
                    )
                    .rotationEffect(.degrees(model.facingRight ? 7 : -7))
            }
            .offset(y: 15 + bob)

            HStack(spacing: 10) {
                Capsule()
                    .fill(Color.black.opacity(0.85))
                    .frame(width: 13, height: 7)
                    .offset(y: foot)
                Capsule()
                    .fill(Color.black.opacity(0.85))
                    .frame(width: 13, height: 7)
                    .offset(y: -foot)
            }
            .offset(y: 40)
        }
        .scaleEffect(x: model.facingRight ? 1 : -1, y: 1)
        .animation(.linear(duration: 0.05), value: model.phase)
    }
}
