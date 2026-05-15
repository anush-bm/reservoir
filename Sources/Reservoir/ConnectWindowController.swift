import AppKit
import UsageMonitorCore
import WebKit

@MainActor
final class ConnectWindowController: NSObject, NSWindowDelegate {
    private let provider: ProviderDefinition
    private let onClose: () -> Void
    private var window: NSWindow?
    private var webView: WKWebView?

    init(provider: ProviderDefinition, onClose: @escaping () -> Void) {
        self.provider = provider
        self.onClose = onClose
        super.init()
    }

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 980, height: 720), configuration: configuration)
        self.webView = webView

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Connect \(provider.name)"
        window.contentView = webView
        window.center()
        window.delegate = self
        self.window = window

        webView.load(URLRequest(url: provider.sourceURL))
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        webView = nil
        window = nil
        onClose()
    }
}
