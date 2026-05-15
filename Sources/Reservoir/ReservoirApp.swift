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
    private let singleInstance = SingleInstanceLock(name: "local.reservoir.single-instance")

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard singleInstance.acquire() else {
            NSApp.terminate(nil)
            return
        }

        NSApp.setActivationPolicy(.accessory)
        menuBarController = MenuBarController(appState: appState)
        appState.onSnapshotsChanged = { [weak self] in
            self?.menuBarController?.refreshStatusItem()
        }
        appState.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        appState.stop()
        singleInstance.release()
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
