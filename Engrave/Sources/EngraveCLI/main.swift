import Foundation
import EngraveInterposer

let args = CommandLine.arguments

if args.count < 2 || args[1] == "--help" || args[1] == "-h" {
    printUsage()
    exit(0)
}

let command = args[1]

switch command {
case "start":
    startServer(args: Array(args.dropFirst(2)))
case "status":
    print("engrave: use 'curl http://localhost:8900/health' to check status")
case "version":
    print("engrave 1.0.0 (Swift native)")
default:
    print("Unknown command: \(command)")
    printUsage()
    exit(1)
}

func startServer(args: [String]) {
    var port: UInt16 = 8900
    var configPath: String? = nil
    var backendURL: String? = nil

    var i = 0
    while i < args.count {
        switch args[i] {
        case "--port", "-p":
            if i + 1 < args.count, let p = UInt16(args[i + 1]) {
                port = p; i += 2
            } else { print("Invalid port"); exit(1) }
        case "--config", "-c":
            if i + 1 < args.count { configPath = args[i + 1]; i += 2 }
            else { print("Missing config path"); exit(1) }
        case "--backend", "-b":
            if i + 1 < args.count { backendURL = args[i + 1]; i += 2 }
            else { print("Missing backend URL"); exit(1) }
        default: i += 1
        }
    }

    var config: EngraveConfig
    if let path = configPath {
        do { config = try EngraveConfig.load(from: path) }
        catch { print("Failed to load config: \(error)"); exit(1) }
    } else {
        config = EngraveConfig.loadDefault()
    }
    config.server.port = port

    if let backend = backendURL {
        config.providers["local"] = EngraveConfig.ProviderConfig(
            type: "chat_completions", baseURL: backend
        )
        let target = EngraveConfig.RouteTarget(backend: "local", model: "*")
        config.routes.defaults["anthropic"] = target
        config.routes.defaults["openai"] = target
        config.routes.defaults["openai_compatible"] = target
        config.routes.defaults["gemini"] = target
    }

    let engrave = Engrave(config: config)

    // Signal handling
    signal(SIGINT, SIG_IGN)
    signal(SIGTERM, SIG_IGN)
    let sigintSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
    let sigtermSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
    sigintSource.setEventHandler {
        print("\nengrave: shutting down...")
        Task { await engrave.stop(); exit(0) }
    }
    sigtermSource.setEventHandler {
        Task { await engrave.stop(); exit(0) }
    }
    sigintSource.resume()
    sigtermSource.resume()

    // Log stream
    Task {
        for await message in await engrave.logStream {
            print(message)
        }
    }

    // Start server
    print("engrave: starting proxy on port \(port)")
    Task {
        do {
            try await engrave.start()
            print("engrave: proxy ready on port \(port)")
        } catch {
            print("engrave: failed to start: \(error)")
            exit(1)
        }
    }

    // Keep alive
    dispatchMain()
}

func printUsage() {
    print("""
    engrave - Native macOS AI API Translation Proxy

    USAGE:
        engrave <command> [options]

    COMMANDS:
        start       Start the proxy server
        status      Check proxy status
        version     Print version

    OPTIONS (start):
        --port, -p <port>       Listen port (default: 8900)
        --config, -c <path>     Config file path (JSON)
        --backend, -b <url>     Backend URL (e.g., http://localhost:1234)

    EXAMPLES:
        engrave start --port 8900 --backend http://localhost:1234
        engrave start -c ~/.config/engrave/config.json
    """)
}
