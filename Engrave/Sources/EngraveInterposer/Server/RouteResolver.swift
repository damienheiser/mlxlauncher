import Foundation

/// Resolved route: which backend to call with what model
public struct ResolvedRoute {
    public let backend: String
    public let provider: String
    public let model: String
    public let providerConfig: EngraveConfig.ProviderConfig?

    public init(backend: String, provider: String, model: String, providerConfig: EngraveConfig.ProviderConfig? = nil) {
        self.backend = backend
        self.provider = provider
        self.model = model
        self.providerConfig = providerConfig
    }
}

/// Resolves incoming requests to backend targets.
///
/// Resolution priority:
///   1. Aliases (exact model name match)
///   2. Model routes (model name prefix/pattern match → provider)
///   3. Default routes (per source facade)
///   4. Passthrough (same provider, same model)
///
/// Model routes (priority 2) are the key to multi-model concurrent routing.
/// They allow any runner to reach any model/provider without config changes:
///   - "claude-opus-4-6" → anthropic backend
///   - "gpt-5.5"         → openai backend
///   - "gemini-3.0-pro"  → gemini backend
///   - "ollama/mistral"  → ollama backend
///   - Unknown models     → fall through to facade defaults (usually local MLX)
public struct RouteResolver {
    private let config: EngraveConfig

    public init(config: EngraveConfig) {
        self.config = config
    }

    /// Resolve a route for the given source facade and model name.
    /// The model name from the request body determines the backend — not the
    /// source facade. This means Claude Code can talk to OpenAI models, Codex
    /// can talk to Anthropic models, etc. All without restarts.
    public func resolve(sourceProvider: String, model: String) -> ResolvedRoute {
        // 1. Check aliases (highest priority — exact match)
        if let alias = config.routes.aliases[model] {
            let providerName = alias.provider ?? alias.backend
            return ResolvedRoute(
                backend: alias.backend,
                provider: providerName,
                model: alias.model == "*" ? model : alias.model,
                providerConfig: config.providers[providerName]
            )
        }

        // 2. Check model routes (model name prefix/pattern → provider)
        //    This is what enables simultaneous multi-model routing.
        let modelLower = model.lowercased()
        for route in config.routes.modelRoutes {
            if modelLower.hasPrefix(route.provider.lowercased() + "/") ||
               modelLower.hasPrefix(route.pattern.lowercased()) {
                let providerName = route.provider
                // Strip provider prefix if present (e.g. "ollama/mistral" → "mistral")
                let resolvedModel: String
                let prefixWithSlash = route.provider.lowercased() + "/"
                if modelLower.hasPrefix(prefixWithSlash) {
                    resolvedModel = String(model.dropFirst(prefixWithSlash.count))
                } else {
                    resolvedModel = model
                }
                return ResolvedRoute(
                    backend: providerName,
                    provider: providerName,
                    model: resolvedModel,
                    providerConfig: config.providers[providerName]
                )
            }
        }

        // 3. Check default routes for this facade (fallback)
        if let defaultRoute = config.routes.defaults[sourceProvider] {
            let providerName = defaultRoute.provider ?? defaultRoute.backend
            let resolvedModel = defaultRoute.model == "*" ? model : defaultRoute.model
            return ResolvedRoute(
                backend: defaultRoute.backend,
                provider: providerName,
                model: resolvedModel,
                providerConfig: config.providers[providerName]
            )
        }

        // 4. Passthrough: same provider, same model
        return ResolvedRoute(
            backend: sourceProvider,
            provider: sourceProvider,
            model: model,
            providerConfig: nil
        )
    }

    /// Determine the source provider from the request path
    public static func sourceProvider(for path: String) -> (provider: String, model: String?) {
        if path.hasPrefix("/v1/messages") {
            return ("anthropic", nil)
        }
        if path.hasPrefix("/v1/chat/completions") {
            return ("openai_compatible", nil)
        }
        if path.hasPrefix("/v1/responses") {
            return ("openai", nil)
        }
        // Gemini: /v1/models/{model}:generateContent or :streamGenerateContent
        // Also handles /v1beta/models/ which Gemini CLI uses
        for prefix in ["/v1/models/", "/v1beta/models/"] {
            if path.hasPrefix(prefix) && (path.contains(":generateContent") || path.contains(":streamGenerateContent")) {
                let afterModels = path.dropFirst(prefix.count)
                if let colonIdx = afterModels.firstIndex(of: ":") {
                    let model = String(afterModels[afterModels.startIndex..<colonIdx])
                    guard !model.isEmpty else { continue }
                    return ("gemini", model)
                }
            }
        }
        return ("unknown", nil)
    }
}
