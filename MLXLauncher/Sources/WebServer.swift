import Foundation

// Lightweight HTTP server using BSD sockets — no dependencies.

class WebServer {
    let port: UInt16
    let appState: AppState
    private var serverFd: Int32 = -1
    private let queue = DispatchQueue(label: "mlx.webserver", attributes: .concurrent)

    init(port: UInt16, appState: AppState) {
        self.port = port
        self.appState = appState
    }

    func start() {
        queue.async { [self] in
            serverFd = socket(AF_INET, SOCK_STREAM, 0)
            guard serverFd >= 0 else { return }

            var yes: Int32 = 1
            setsockopt(serverFd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
            setsockopt(serverFd, SOL_SOCKET, SO_REUSEPORT, &yes, socklen_t(MemoryLayout<Int32>.size))

            var addr = sockaddr_in()
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = port.bigEndian
            addr.sin_addr.s_addr = INADDR_ANY

            let bindResult = withUnsafePointer(to: &addr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { ptr in
                    bind(serverFd, ptr, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            guard bindResult == 0 else { return }

            listen(serverFd, 128)

            while serverFd >= 0 {
                let clientFd = accept(serverFd, nil, nil)
                guard clientFd >= 0 else { continue }
                queue.async { self.handleClient(clientFd) }
            }
        }
    }

    private func handleClient(_ fd: Int32) {
        var buffer = [UInt8](repeating: 0, count: 65536)
        let n = recv(fd, &buffer, buffer.count, 0)
        guard n > 0 else { close(fd); return }

        let raw = String(bytes: buffer[0..<n], encoding: .utf8) ?? ""
        let (method, path) = parseRequestLine(raw)
        let body = extractBody(raw)

        let response: (Int, String, String) // (status, contentType, body)

        if path == "/" || path == "/index.html" {
            response = (200, "text/html", WebUI.html)
        } else if path.hasPrefix("/api/") {
            response = handleAPI(method: method, path: path, body: body)
        } else {
            response = (404, "application/json", #"{"error":"not found"}"#)
        }

        let (status, contentType, respBody) = response
        let statusText = status == 200 ? "OK" : (status == 404 ? "Not Found" : "Bad Request")
        let httpResponse = """
        HTTP/1.1 \(status) \(statusText)\r
        Content-Type: \(contentType); charset=utf-8\r
        Content-Length: \(respBody.utf8.count)\r
        Access-Control-Allow-Origin: *\r
        Access-Control-Allow-Methods: GET, POST, DELETE, OPTIONS\r
        Access-Control-Allow-Headers: Content-Type\r
        Connection: close\r
        \r
        \(respBody)
        """

        let data = Array(httpResponse.utf8)
        _ = send(fd, data, data.count, 0)
        close(fd)
    }

    private func parseRequestLine(_ raw: String) -> (String, String) {
        let firstLine = raw.components(separatedBy: "\r\n").first ?? ""
        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2 else { return ("GET", "/") }
        return (String(parts[0]), String(parts[1]))
    }

    private func extractBody(_ raw: String) -> String {
        guard let range = raw.range(of: "\r\n\r\n") else { return "" }
        return String(raw[range.upperBound...])
    }

    // MARK: - API Router

    private func handleAPI(method: String, path: String, body: String) -> (Int, String, String) {
        let ct = "application/json"

        if method == "OPTIONS" {
            return (200, ct, "{}")
        }

        switch (method, path) {
        case ("GET", "/api/models"):
            return (200, ct, modelsJSON())
        case ("GET", "/api/runners"):
            return (200, ct, runnersJSON())
        case ("GET", "/api/server"):
            return (200, ct, serverJSON())
        case ("POST", "/api/server/start"):
            return startServerAPI(body: body)
        case ("POST", "/api/server/stop"):
            DispatchQueue.main.async { self.appState.stopServer() }
            return (200, ct, #"{"ok":true}"#)
        case ("POST", "/api/server/restart"):
            DispatchQueue.main.async { self.appState.restartServer() }
            return (200, ct, #"{"ok":true}"#)
        case ("GET", "/api/profiles"):
            return (200, ct, profilesJSON())
        case ("GET", "/api/prompts"):
            return (200, ct, promptsJSON())
        case ("POST", "/api/launch"):
            return launchAPI(body: body)
        default:
            return (404, ct, #"{"error":"unknown endpoint"}"#)
        }
    }

    private func modelsJSON() -> String {
        var models: [[String: Any]] = []
        DispatchQueue.main.sync {
            for m in appState.allModels {
                models.append([
                    "id": m.id, "index": m.index, "size": m.size,
                    "source": m.source.rawValue, "shortName": m.shortName,
                    "provider": m.providerBadge
                ])
            }
        }
        return jsonEncode(models)
    }

    private func runnersJSON() -> String {
        let runners = allRunners.map { r in
            ["id": r.id, "name": r.name, "installed": r.isInstalled, "needsProxy": r.needsProxy] as [String: Any]
        }
        return jsonEncode(runners)
    }

    private func serverJSON() -> String {
        var dict: [String: Any] = [:]
        DispatchQueue.main.sync {
            dict = [
                "state": appState.serverStatus.state.rawValue,
                "model": appState.serverStatus.modelName ?? "",
                "port": appState.serverStatus.port,
                "pid": appState.serverStatus.pid ?? 0
            ]
        }
        return jsonEncode(dict)
    }

    private func profilesJSON() -> String {
        var profiles: [[String: Any]] = []
        DispatchQueue.main.sync {
            for p in appState.profiles {
                profiles.append([
                    "name": p.name, "temp": p.temp, "top_p": p.top_p, "top_k": p.top_k,
                    "min_p": p.min_p, "max_tokens": p.max_tokens,
                    "repetition_penalty": p.repetition_penalty,
                    "repetition_context_size": p.repetition_context_size,
                    "system_prompt": p.system_prompt
                ])
            }
        }
        return jsonEncode(profiles)
    }

    private func promptsJSON() -> String {
        var prompts: [[String: Any]] = []
        DispatchQueue.main.sync {
            for p in appState.prompts {
                prompts.append(["name": p.name, "prompt": p.prompt, "source": p.source])
            }
        }
        return jsonEncode(prompts)
    }

    private func startServerAPI(body: String) -> (Int, String, String) {
        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let modelId = json["model"] as? String else {
            return (400, "application/json", #"{"error":"missing model field"}"#)
        }
        DispatchQueue.main.async {
            if let model = self.appState.allModels.first(where: { $0.id == modelId }) {
                self.appState.startServer(model: model)
            }
        }
        return (200, "application/json", #"{"ok":true}"#)
    }

    private func launchAPI(body: String) -> (Int, String, String) {
        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let modelId = json["model"] as? String,
              let runnerId = json["runner"] as? String else {
            return (400, "application/json", #"{"error":"missing model or runner"}"#)
        }
        DispatchQueue.main.async {
           if let model = self.appState.allModels.first(where: { $0.id == modelId }),
               let runner = allRunners.first(where: { $0.id == runnerId }) {
                self.appState.selectedModel = model
                self.appState.selectedRunner = runner
                var settings = self.appState.settings(for: runner)
                if let workingDirectory = json["workingDirectory"] as? String, !workingDirectory.isEmpty {
                    settings.workingDirectory = workingDirectory
                }
                if let args = json["args"] as? [String] {
                    settings.extraArguments = args.joined(separator: " ")
                } else if let args = json["args"] as? String {
                    settings.extraArguments = args
                }
                self.appState.updateSettings(for: runner, settings)
                self.appState.launch()
            }
        }
        return (200, "application/json", #"{"ok":true}"#)
    }

    private func jsonEncode(_ obj: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]),
              let str = String(data: data, encoding: .utf8) else { return "[]" }
        return str
    }
}
