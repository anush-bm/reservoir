import Foundation

public struct ProviderRegistry: Sendable {
    public private(set) var providers: [ProviderDefinition]

    public init(providers: [ProviderDefinition] = ProviderRegistry.defaults) {
        self.providers = providers
    }

    public static let defaults: [ProviderDefinition] = [
        ProviderDefinition(
            id: .codex,
            name: "Codex",
            sourceURL: URL(string: "https://chatgpt.com/codex/cloud/settings/analytics")!,
            isEnabled: true
        ),
        ProviderDefinition(
            id: .claude,
            name: "Claude",
            sourceURL: URL(string: "https://claude.ai/settings/usage")!,
            isEnabled: true
        )
    ]

    public func enabledProviders() -> [ProviderDefinition] {
        providers.filter(\.isEnabled)
    }
}
