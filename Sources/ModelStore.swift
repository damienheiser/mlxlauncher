import Foundation
import Network

// MARK: - Model Location

/// Represents where a model lives
enum ModelLocation: String, Codable, Hashable {
    case local          // On disk
    case network        // Discovered on LAN via Bonjour
    case huggingFace    // Available for download from HF
}

/// A discovered or downloadable model
struct DiscoveredModel: Identifiable, Hashable {
    let id: String                    // HuggingFace repo ID or local path
    var displayName: String
    var size: String                  // Human-readable size
    var quantization: String?         // e.g. "4bit", "8bit", "fp16"
    var architecture: String?         // e.g. "qwen3", "gemma4", "llama"
    var location: ModelLocation
    var localPath: String?            // Path on disk if local
    var networkHost: String?          // Host if network-discovered
    var networkPort: UInt16?          // Port if network-discovered
    var downloadURL: String?          // HuggingFace URL if remote
    var sizeBytes: UInt64?            // Size in bytes for sorting
    var isDownloading: Bool = false
    var downloadProgress: Double = 0  // 0.0 to 1.0

    var index: Int? {
        guard let last = id.split(separator: "/").last,
              let number = last.split(separator: "-").first,
              let parsed = Int(number) else { return nil }
        return parsed
    }

    var launchIdentity: String {
        if let localPath { return "local:\(localPath)" }
        if let networkHost, let networkPort { return "network:\(networkHost):\(networkPort)/\(id)" }
        return "\(location.rawValue):\(id)"
    }
}

// MARK: - HuggingFace API Types

private struct HFSearchResult: Codable {
    let id: String                    // e.g. "mlx-community/Llama-3.2-1B-4bit"
    let modelId: String?
    let downloads: Int?
    let likes: Int?
    let tags: [String]?
    let siblings: [HFSibling]?

    enum CodingKeys: String, CodingKey {
        case id, modelId, downloads, likes, tags, siblings
    }
}

private struct HFSibling: Codable {
    let rfilename: String
    let size: Int?
}

// MARK: - Model Store

/// Manages model discovery, search, download, and network location.
@MainActor
class ModelStore: ObservableObject {
    @Published var localModels: [DiscoveredModel] = []
    @Published var networkModels: [DiscoveredModel] = []
    @Published var searchResults: [DiscoveredModel] = []
    @Published var isSearching = false
    @Published var isScanning = false
    @Published var searchQuery = ""
    @Published var downloadingModels: [String: DiscoveredModel] = [:]

    /// Directories to scan for local models
    var scanDirectories: [String] = []

    private var browser: NWBrowser?
    private var networkEndpoints: [NWEndpoint: DiscoveredModel] = [:]

    init() {
        let home = NSHomeDirectory()
        scanDirectories = [
            "\(home)/.lmstudio/models",
            "\(home)/.exo/models",
            "\(home)/.cache/huggingface/hub",
            "\(home)/mlx-models",
        ]
    }

    // MARK: - Local Model Scanning

    /// Scan all configured directories for local models
    func scanLocalModels() {
        isScanning = true
        Task {
            let models = await Self.scanAllDirectories(scanDirectories)
            self.localModels = models
            self.isScanning = false
        }
    }

    private nonisolated static func scanAllDirectories(_ dirs: [String]) async -> [DiscoveredModel] {
        var models: [DiscoveredModel] = []
        for dir in dirs {
            let found = scanDirectory(dir)
            models.append(contentsOf: found)
        }
        var seen = Set<String>()
        models = models.filter { seen.insert($0.id).inserted }
        models.sort { ($0.displayName) < ($1.displayName) }
        return models
    }

    /// Add a custom scan directory
    func addScanDirectory(_ path: String) {
        let expanded = (path as NSString).expandingTildeInPath
        if !scanDirectories.contains(expanded) {
            scanDirectories.append(expanded)
            scanLocalModels()
        }
    }

    /// Remove a scan directory
    func removeScanDirectory(_ path: String) {
        scanDirectories.removeAll { $0 == path }
        scanLocalModels()
    }

    private nonisolated static func scanDirectory(_ dir: String) -> [DiscoveredModel] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: dir) else { return [] }

        var models: [DiscoveredModel] = []

        // Look for directories containing config.json (standard HF model layout)
        guard let enumerator = fm.enumerator(
            at: URL(fileURLWithPath: dir),
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var visited = Set<String>()

        while let url = enumerator.nextObject() as? URL {
            let path = url.path
            guard url.lastPathComponent == "config.json",
                  !visited.contains(url.deletingLastPathComponent().path) else { continue }

            let modelDir = url.deletingLastPathComponent()
            visited.insert(modelDir.path)
            enumerator.skipDescendants()

            // Read config.json for architecture info
            var architecture: String? = nil
            if let data = fm.contents(atPath: path),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                architecture = json["model_type"] as? String
            }

            // Compute total model size from safetensors files
            var totalBytes: UInt64 = 0
            if let files = try? fm.contentsOfDirectory(atPath: modelDir.path) {
                for file in files where file.hasSuffix(".safetensors") || file.hasSuffix(".gguf") {
                    let filePath = modelDir.appendingPathComponent(file).path
                    if let attrs = try? fm.attributesOfItem(atPath: filePath),
                       let size = attrs[.size] as? UInt64 {
                        totalBytes += size
                    }
                }
            }

            // Extract model ID from path
            let modelId = extractModelId(from: modelDir.path, baseDir: dir)

            // Detect quantization from name or files
            let quant = detectQuantization(modelId)

            models.append(DiscoveredModel(
                id: modelId,
                displayName: modelId.components(separatedBy: "/").last ?? modelId,
                size: formatBytes(totalBytes),
                quantization: quant,
                architecture: architecture,
                location: .local,
                localPath: modelDir.path,
                sizeBytes: totalBytes
            ))
        }

        return models
    }

    private nonisolated static func extractModelId(from path: String, baseDir: String) -> String {
        // Try to extract "owner/repo" format from path
        let relative = path.replacingOccurrences(of: baseDir + "/", with: "")

        // Handle HF cache format: models--owner--repo/snapshots/hash/
        if relative.contains("models--") {
            let parts = relative.components(separatedBy: "/")
            if let modelPart = parts.first(where: { $0.hasPrefix("models--") }) {
                let cleaned = modelPart.replacingOccurrences(of: "models--", with: "")
                let ownerRepo = cleaned.replacingOccurrences(of: "--", with: "/")
                return ownerRepo
            }
        }

        // Handle exo format: owner--repo
        if relative.contains("--") {
            let parts = relative.components(separatedBy: "/").first ?? relative
            return parts.replacingOccurrences(of: "--", with: "/")
        }

        return relative
    }

    private nonisolated static func detectQuantization(_ name: String) -> String? {
        let lower = name.lowercased()
        if lower.contains("fp16") || lower.contains("float16") { return "fp16" }
        if lower.contains("bf16") || lower.contains("bfloat16") { return "bf16" }
        if lower.contains("8bit") || lower.contains("q8") || lower.contains("mxfp8") { return "8bit" }
        if lower.contains("4bit") || lower.contains("q4") || lower.contains("int4") || lower.contains("nvfp4") || lower.contains("mxfp4") { return "4bit" }
        if lower.contains("3bit") || lower.contains("q3") || lower.contains("int3") { return "3bit" }
        if lower.contains("2bit") || lower.contains("q2") || lower.contains("int2") { return "2bit" }
        return nil
    }

    private nonisolated static func formatBytes(_ bytes: UInt64) -> String {
        if bytes == 0 { return "—" }
        let gb = Double(bytes) / 1_073_741_824
        if gb >= 1.0 { return String(format: "%.1f GB", gb) }
        let mb = Double(bytes) / 1_048_576
        return String(format: "%.0f MB", mb)
    }

    // MARK: - HuggingFace Search

    /// Search HuggingFace for MLX models
    func searchHuggingFace(query: String) {
        guard !query.isEmpty else {
            searchResults = []
            return
        }
        isSearching = true
        searchQuery = query

        Task {
            let results = await Self.performHFSearch(query: query)
            if searchQuery == query {
                searchResults = results
                isSearching = false
            }
        }
    }

    private nonisolated static func performHFSearch(query: String) async -> [DiscoveredModel] {
        // Search for MLX models on HuggingFace
        let searchTerms = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let urlStr = "https://huggingface.co/api/models?search=\(searchTerms)+mlx&sort=downloads&direction=-1&limit=30&filter=mlx"
        guard let url = URL(string: urlStr) else { return [] }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return [] }
            let results = try JSONDecoder().decode([HFSearchResult].self, from: data)

            return results.map { result in
                let totalSize = result.siblings?.compactMap { $0.size }.reduce(0, +) ?? 0
                let quant = detectQuantization(result.id)
                let arch = extractArchFromTags(result.tags ?? [])

                return DiscoveredModel(
                    id: result.id,
                    displayName: result.id.components(separatedBy: "/").last ?? result.id,
                    size: totalSize > 0 ? formatBytes(UInt64(totalSize)) : "—",
                    quantization: quant,
                    architecture: arch,
                    location: .huggingFace,
                    downloadURL: "https://huggingface.co/\(result.id)",
                    sizeBytes: totalSize > 0 ? UInt64(totalSize) : nil
                )
            }
        } catch {
            return []
        }
    }

    private nonisolated static func extractArchFromTags(_ tags: [String]) -> String? {
        let archTags = ["llama", "qwen", "qwen2", "gemma", "gemma2", "phi", "mistral", "mixtral", "starcoder"]
        for tag in tags {
            let lower = tag.lowercased()
            if archTags.contains(lower) { return lower }
        }
        return nil
    }

    // MARK: - Model Download

    /// Download a model from HuggingFace using huggingface-cli or mlx_lm.convert
    func downloadModel(_ model: DiscoveredModel, to directory: String? = nil) {
        let targetDir = directory ?? scanDirectories.first ?? NSHomeDirectory() + "/.exo/models"
        var downloading = model
        downloading.isDownloading = true
        downloading.downloadProgress = 0
        downloadingModels[model.id] = downloading

        Task.detached { [weak self] in
            let modelSlug = model.id.replacingOccurrences(of: "/", with: "--")
            let destPath = "\(targetDir)/\(modelSlug)"

            // Use huggingface-cli if available, otherwise try mlx_lm.convert
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")

            // Try huggingface-cli download first
            proc.arguments = ["huggingface-cli", "download", model.id, "--local-dir", destPath]
            proc.environment = ProcessInfo.processInfo.environment

            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError = pipe

            do {
                try proc.run()

                // Monitor progress from output
                let handle = pipe.fileHandleForReading
                Task {
                    for try await line in handle.bytes.lines {
                        if line.contains("%") {
                            // Parse progress percentage
                            if let pctStr = line.components(separatedBy: "%").first?.components(separatedBy: " ").last,
                               let pct = Double(pctStr) {
                                await MainActor.run { [weak self] in
                                    self?.downloadingModels[model.id]?.downloadProgress = pct / 100.0
                                }
                            }
                        }
                    }
                }

                proc.waitUntilExit()

                await MainActor.run { [weak self] in
                    self?.downloadingModels.removeValue(forKey: model.id)
                    if proc.terminationStatus == 0 {
                        self?.scanLocalModels()
                    }
                }
            } catch {
                _ = await MainActor.run { [weak self] in
                    self?.downloadingModels.removeValue(forKey: model.id)
                } as Void
            }
        }
    }

    /// Delete a local model
    func deleteModel(_ model: DiscoveredModel) {
        guard let path = model.localPath else { return }
        try? FileManager.default.removeItem(atPath: path)
        scanLocalModels()
    }

    // MARK: - Network Discovery (Bonjour)

    /// Start scanning for MLX/LM Studio servers on the local network
    func startNetworkDiscovery() {
        // Browse for HTTP services that might be model servers
        // Common service types: _http._tcp (generic), _mlx._tcp (custom)
        let descriptor = NWBrowser.Descriptor.bonjour(type: "_http._tcp", domain: "local.")
        let params = NWParameters()
        params.includePeerToPeer = true

        let browser = NWBrowser(for: descriptor, using: params)
        self.browser = browser

        browser.browseResultsChangedHandler = { [weak self] results, changes in
            Task { @MainActor [weak self] in
                self?.processNetworkResults(results)
            }
        }

        browser.stateUpdateHandler = { state in
            switch state {
            case .ready: break
            case .failed(let error):
                print("[ModelStore] network discovery failed: \(error)")
            default: break
            }
        }

        browser.start(queue: .global(qos: .utility))
    }

    /// Stop network discovery
    func stopNetworkDiscovery() {
        browser?.cancel()
        browser = nil
        networkModels = []
    }

    private func processNetworkResults(_ results: Set<NWBrowser.Result>) {
        // Filter for services that look like model servers
        // We'll probe them asynchronously
        for result in results {
            if case .service(let name, _, _, _) = result.endpoint {
                // Look for services with "mlx", "lm", "llm", "model" in the name
                let lower = name.lowercased()
                if lower.contains("mlx") || lower.contains("lmstudio") || lower.contains("llm") || lower.contains("model") {
                    probeNetworkService(result.endpoint, name: name)
                }
            }
        }
    }

    private func probeNetworkService(_ endpoint: NWEndpoint, name: String) {
        // Try to connect and check if it's an OpenAI-compatible model server
        Task {
            if case .service(let name, _, _, _) = endpoint {
                // Resolve the service to get host:port
                let connection = NWConnection(to: endpoint, using: .tcp)
                connection.stateUpdateHandler = { [weak self] state in
                    if case .ready = state {
                        if let path = connection.currentPath,
                           let remoteEndpoint = path.remoteEndpoint,
                           case .hostPort(let host, let port) = remoteEndpoint {
                            let hostStr = "\(host)"
                            let portNum = port.rawValue
                            Task { @MainActor in
                                self?.checkModelServer(host: hostStr, port: portNum, name: name)
                            }
                        }
                        connection.cancel()
                    }
                }
                connection.start(queue: .global())
            }
        }
    }

    private func checkModelServer(host: String, port: UInt16, name: String) {
        Task {
            // Try the OpenAI-compatible /v1/models endpoint
            guard let url = URL(string: "http://\(host):\(port)/v1/models") else { return }
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let models = json["data"] as? [[String: Any]] else { return }

                for modelInfo in models {
                    guard let modelId = modelInfo["id"] as? String else { continue }
                    let model = DiscoveredModel(
                        id: "\(host):\(port)/\(modelId)",
                        displayName: "\(modelId) (\(name))",
                        size: "Network",
                        location: .network,
                        networkHost: host,
                        networkPort: port
                    )
                    if !networkModels.contains(where: { $0.id == model.id }) {
                        networkModels.append(model)
                    }
                }
            } catch {
                // Not a model server, ignore
            }
        }
    }

    /// Manually add a network model server
    func addNetworkServer(host: String, port: UInt16) {
        checkModelServer(host: host, port: port, name: host)
    }
}
