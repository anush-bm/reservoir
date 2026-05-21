import AppKit
import SwiftUI
import UsageMonitorCore

@main
struct ReservoirApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(appState: appDelegate.appState)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()
    private var menuBarController: MenuBarController?
    private var dashboardWindowController: DashboardWindowController?
    private var floatingBadgeController: FloatingBadgeWindowController?
    private let singleInstance = SingleInstanceLock(name: "local.reservoir.single-instance")
    private let showReservoirNotification = Notification.Name("local.reservoir.show")

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard singleInstance.acquire() else {
            DistributedNotificationCenter.default().post(name: showReservoirNotification, object: nil)
            NSApp.terminate(nil)
            return
        }

        NSApp.setActivationPolicy(.accessory)
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(showReservoirFromNotification),
            name: showReservoirNotification,
            object: nil
        )
        menuBarController = MenuBarController(appState: appState)
        floatingBadgeController = FloatingBadgeWindowController(appState: appState) { [weak self] in
            self?.showReservoir()
        }
        appState.onSnapshotsChanged = { [weak self] in
            self?.menuBarController?.refreshStatusItem()
            self?.floatingBadgeController?.update()
        }
        appState.start()
        floatingBadgeController?.show()
        showReservoir()
    }

    func applicationWillTerminate(_ notification: Notification) {
        DistributedNotificationCenter.default().removeObserver(self)
        appState.stop()
        singleInstance.release()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showReservoir()
        return true
    }

    @objc private func showReservoirFromNotification() {
        showReservoir()
    }

    private func showReservoir() {
        if menuBarController?.showPopover() != true {
            showDashboardWindow()
        }
    }

    private func showDashboardWindow() {
        if dashboardWindowController == nil {
            dashboardWindowController = DashboardWindowController(appState: appState)
        }
        dashboardWindowController?.show()
    }
}

@MainActor
final class FloatingBadgeWindowController: NSObject {
    private let appState: AppState
    private let onClick: () -> Void
    private let panel: NSPanel
    private let button = NSButton()

    init(appState: AppState, onClick: @escaping () -> Void) {
        self.appState = appState
        self.onClick = onClick
        self.panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 30, height: 22),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        super.init()

        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.isReleasedWhenClosed = false

        button.frame = NSRect(x: 0, y: 0, width: 30, height: 22)
        button.bezelStyle = .shadowlessSquare
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleNone
        button.target = self
        button.action = #selector(openReservoir)
        button.setAccessibilityLabel("Reservoir usage monitor")
        panel.contentView = button

        update()
        position()
    }

    func show() {
        update()
        position()
        panel.orderFrontRegardless()
    }

    func update() {
        let display = StatusIconRenderer.menuBarDisplay(for: appState.providers, snapshots: appState.snapshots)
        button.image = display.image
        button.toolTip = "Reservoir"
    }

    @objc private func openReservoir() {
        onClick()
    }

    private func position() {
        guard let screen = NSScreen.main else { return }
        let frame = screen.frame
        let size = panel.frame.size
        let x = frame.maxX - size.width - 12
        let y = frame.maxY - size.height - 4
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

@MainActor
final class DashboardWindowController {
    private let window: NSWindow

    init(appState: AppState) {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 540),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Reservoir"
        window.center()
        window.contentMinSize = NSSize(width: 420, height: 520)
        window.contentViewController = NSHostingController(rootView: DashboardView(appState: appState))
        window.isReleasedWhenClosed = false
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

final class SingleInstanceLock {
    private let name: String
    private var lockFileDescriptor: Int32 = -1

    init(name: String) {
        self.name = name
    }

    func acquire() -> Bool {
        let path = NSTemporaryDirectory().appending(name)
        lockFileDescriptor = open(path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard lockFileDescriptor >= 0 else { return false }
        return flock(lockFileDescriptor, LOCK_EX | LOCK_NB) == 0
    }

    func release() {
        guard lockFileDescriptor >= 0 else { return }
        flock(lockFileDescriptor, LOCK_UN)
        close(lockFileDescriptor)
        lockFileDescriptor = -1
    }
}
