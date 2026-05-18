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
    private let singleInstance = SingleInstanceLock(name: "local.reservoir.single-instance")
    private let showDashboardNotification = Notification.Name("local.reservoir.show-dashboard")

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard singleInstance.acquire() else {
            DistributedNotificationCenter.default().post(name: showDashboardNotification, object: nil)
            NSApp.terminate(nil)
            return
        }

        NSApp.setActivationPolicy(.accessory)
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(showDashboardFromNotification),
            name: showDashboardNotification,
            object: nil
        )
        menuBarController = MenuBarController(appState: appState)
        appState.onSnapshotsChanged = { [weak self] in
            self?.menuBarController?.refreshStatusItem()
        }
        appState.start()
        showDashboardWindow()
    }

    func applicationWillTerminate(_ notification: Notification) {
        DistributedNotificationCenter.default().removeObserver(self)
        appState.stop()
        singleInstance.release()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showDashboardWindow()
        return true
    }

    @objc private func showDashboardFromNotification() {
        showDashboardWindow()
    }

    private func showDashboardWindow() {
        if dashboardWindowController == nil {
            dashboardWindowController = DashboardWindowController(appState: appState)
        }
        dashboardWindowController?.show()
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
