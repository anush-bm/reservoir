import Foundation
import UsageMonitorCore
import WebKit

@MainActor
final class WebUsageCollector: NSObject, ProviderCollector, WKNavigationDelegate, @unchecked Sendable {
    let definition: ProviderDefinition

    private struct Extraction {
        let snapshot: ProviderSnapshot?
        let visibleText: String
    }

    private var continuation: CheckedContinuation<Extraction, Error>?
    private var webView: WKWebView?

    init(definition: ProviderDefinition) {
        self.definition = definition
    }

    func refresh() async throws -> ProviderSnapshot {
        let extraction = try await loadExtraction()
        if let snapshot = extraction.snapshot {
            return snapshot
        }

        let parsed: ProviderSnapshot?
        switch definition.id {
        case .codex:
            parsed = UsageParsers.parseCodexVisibleText(extraction.visibleText)
        case .claude:
            parsed = UsageParsers.parseClaudeVisibleText(extraction.visibleText)
        }

        guard let snapshot = parsed else {
            throw classifiedFailure(from: extraction.visibleText)
        }
        webView = nil
        return snapshot
    }

    func clearSessionData() async {
        let dataStore = WKWebsiteDataStore.default()
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        let records = await dataStore.dataRecords(ofTypes: types)
        guard let host = definition.sourceURL.host else { return }
        let matching = records.filter { record in
            record.displayName.contains(host) || host.contains(record.displayName)
        }
        await dataStore.removeData(ofTypes: types, for: matching)
    }

    private func loadExtraction() async throws -> Extraction {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation

            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = .default()
            configuration.defaultWebpagePreferences.allowsContentJavaScript = true
            configuration.userContentController.addUserScript(Self.responseCaptureScript)
            configuration.applicationNameForUserAgent = "Version/17.0 Safari/605.1.15"

            let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1200, height: 900), configuration: configuration)
            webView.navigationDelegate = self
            self.webView = webView

            var request = URLRequest(url: definition.sourceURL)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            webView.load(request)
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
        self.webView = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
        self.webView = nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            do {
                let extraction = try await extractWhenReady(from: webView)
                self.continuation?.resume(returning: extraction)
            } catch {
                self.continuation?.resume(throwing: error)
            }
            self.continuation = nil
            self.webView = nil
        }
    }

    private func extractWhenReady(from webView: WKWebView) async throws -> Extraction {
        var latest = Extraction(snapshot: nil, visibleText: "")
        for _ in 0..<8 {
            let extraction = try await extractOnce(from: webView)
            latest = extraction
            if extraction.snapshot != nil || visibleTextLooksReady(extraction.visibleText) {
                return extraction
            }
            try? await Task.sleep(for: .seconds(1))
        }
        return latest
    }

    private func extractOnce(from webView: WKWebView) async throws -> Extraction {
        let script = """
        (() => {
          const captured = Array.isArray(window.__aiUsageMonitorResponses) ? window.__aiUsageMonitorResponses : [];
          const body = document.body ? document.body.innerText : "";
          return JSON.stringify({ captured, body });
        })();
        """

        let result = try await webView.evaluateJavaScript(script)
        guard let json = result as? String,
              let data = json.data(using: .utf8),
              let decoded = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return Extraction(snapshot: nil, visibleText: "")
        }

        let visibleText = decoded["body"] as? String ?? ""
        let captured = decoded["captured"] as? [Any] ?? []
        for candidate in captured {
            if let snapshot = UsageParsers.parseProviderJSON(candidate, provider: definition) {
                return Extraction(snapshot: snapshot, visibleText: visibleText)
            }
        }

        return Extraction(snapshot: nil, visibleText: visibleText)
    }

    private func visibleTextLooksReady(_ text: String) -> Bool {
        switch definition.id {
        case .codex:
            return text.localizedCaseInsensitiveContains("usage limit")
                && text.localizedCaseInsensitiveContains("remaining")
        case .claude:
            return text.localizedCaseInsensitiveContains("usage limits")
                && text.localizedCaseInsensitiveContains("used")
        }
    }

    private func classifiedFailure(from visibleText: String) -> ProviderError {
        let trimmed = visibleText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return .unavailable(definition.id, "Page loaded with no readable text. The provider may be blocking embedded WebKit.")
        }

        let loginMarkers = [
            "log in",
            "login",
            "sign in",
            "continue with google",
            "continue with apple",
            "verify you are human"
        ]
        if loginMarkers.contains(where: { trimmed.localizedCaseInsensitiveContains($0) }) {
            return .loggedOut(definition.id)
        }

        if trimmed.localizedCaseInsensitiveContains("enable javascript") {
            return .unavailable(definition.id, "Provider page asked for JavaScript even though WebKit JavaScript is enabled.")
        }

        return .unavailable(definition.id, "Page loaded, but usage text was not found. The provider page structure may have changed.")
    }

    private static let responseCaptureScript = WKUserScript(
        source: """
        (() => {
          if (window.__aiUsageMonitorInstalled) return;
          window.__aiUsageMonitorInstalled = true;
          window.__aiUsageMonitorResponses = [];
          const keep = (value) => {
            try {
              if (window.__aiUsageMonitorResponses.length < 20) {
                window.__aiUsageMonitorResponses.push(value);
              }
            } catch (_) {}
          };
          const originalFetch = window.fetch;
          window.fetch = async (...args) => {
            const response = await originalFetch(...args);
            try {
              const cloned = response.clone();
              const contentType = cloned.headers.get("content-type") || "";
              if (contentType.includes("application/json")) {
                cloned.json().then(keep).catch(() => {});
              }
            } catch (_) {}
            return response;
          };
          const originalOpen = XMLHttpRequest.prototype.open;
          const originalSend = XMLHttpRequest.prototype.send;
          XMLHttpRequest.prototype.open = function(method, url) {
            this.__aiUsageMonitorURL = url;
            return originalOpen.apply(this, arguments);
          };
          XMLHttpRequest.prototype.send = function() {
            this.addEventListener("load", function() {
              try {
                const contentType = this.getResponseHeader("content-type") || "";
                if (contentType.includes("application/json")) {
                  keep(JSON.parse(this.responseText));
                }
              } catch (_) {}
            });
            return originalSend.apply(this, arguments);
          };
        })();
        """,
        injectionTime: .atDocumentStart,
        forMainFrameOnly: false
    )
}
