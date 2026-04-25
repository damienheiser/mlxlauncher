# MLX Launcher

A native macOS application for running large language models locally on Apple Silicon and connecting them to AI coding assistants.

MLX Launcher handles the entire workflow: discovering models on disk, managing the MLX inference server, translating between AI provider APIs, and launching coding tools -- all from a single interface.

## Features

### Model Management
- **Local model discovery** -- scans configurable directories (`~/.exo/models`, `~/.lmstudio/models`, `~/.cache/huggingface/hub`, custom paths) for MLX-format models
- **HuggingFace search** -- search and download MLX models directly from the Hub
- **Network discovery** -- finds model servers on the local network via Bonjour/mDNS
- **Manual server entry** -- connect to any OpenAI-compatible model server by host:port
- **Model metadata** -- displays architecture, quantization level, file size for each model

### Server Control
- **MLX inference server** -- starts/stops `mlx_lm server` with configurable generation parameters
- **Generation profiles** -- save and switch between parameter presets (temperature, top_p, top_k, min_p, max_tokens, repetition penalty)
- **Server health monitoring** -- polls the server endpoint and displays status in real time
- **Log tailing** -- live server output in the UI

### API Translation (Engrave Interposer)
- **Single-port proxy** -- all runners connect to one port (8900) regardless of their native API format
- **Anthropic Messages API** -- `POST /v1/messages` for Claude Code
- **OpenAI Chat Completions** -- `POST /v1/chat/completions` for Codex, Aider, gptme
- **OpenAI Responses API** -- `POST /v1/responses`
- **Google Gemini API** -- `POST /v1/models/{model}:generateContent` for Gemini CLI
- **Streaming SSE translation** -- full bidirectional stream translation with state machine
- **Tool call mapping** -- translates tool use/result blocks and IDs across provider formats
- **Route resolution** -- configurable aliases, default routes, and passthrough

### Runner Integration
- **Claude Code** -- launches with `ANTHROPIC_BASE_URL` pointing to interposer
- **Codex CLI** -- launches with `OPENAI_BASE_URL` pointing to interposer
- **Gemini CLI** -- launches with `GOOGLE_GEMINI_BASE_URL` pointing to interposer
- **Aider** -- launches with `--openai-api-base` pointing to MLX server
- **gptme** -- launches with `OPENAI_BASE_URL` pointing to MLX server
- **Per-runner configuration** -- flags, arguments, working directory, system prompts

### Embedded Web UI
- **REST API** on port 8421 for programmatic control
- **Browser-based dashboard** with model grid, runner buttons, server controls
- **Status polling** every 5 seconds

## Requirements

- macOS 14.0+
- Apple Silicon Mac (M1/M2/M3/M4)
- Python 3 with `mlx-lm` installed (`pip3 install mlx-lm`)

## Build

```bash
swift build -c release
```

## Install

```bash
./scripts/build_app.sh release
# Copy to Applications
cp -R MLXLauncher.app /Applications/
```

Or run directly:

```bash
.build/arm64-apple-macosx/release/MLXLauncher
```

## Project Structure

```
Package.swift                          Root package (depends on Engrave/)
Sources/
  App.swift                            SwiftUI entry point
  Services.swift                       AppState: server, interposer, model lifecycle
  Views.swift                          SwiftUI 3-column layout, all panels
  Types.swift                          Data models (MLXModel, Runner, profiles)
  ModelStore.swift                     Model discovery, HF search, network scanning
  WebServer.swift                      Embedded REST API (port 8421)
  WebUI.swift                          Embedded HTML/JS dashboard
Engrave/                               API translation proxy + governance engine
  Sources/EngraveInterposer/           Core proxy library
    IR/                                Canonical intermediate representation
    Translate/                         Format translators (Anthropic, OpenAI, Gemini)
    Server/                            NWListener HTTP server, routing, SSE
    Backend/                           URLSession streaming client
    Config/                            JSON configuration
  Sources/EngraveGovernance/           Governance engine
    PolicyEngine.swift                 Rule evaluation
    PolicyRule.swift                   Declarative rules
    ToolInterceptor.swift              Tool risk classification
    ConditionEvaluator.swift           Expression parser
    GovernanceConfig.swift             Governance configuration + presets
  Sources/EngraveCLI/                  Standalone CLI
```

## Governance Artifacts

When governance is enabled, MLX Launcher writes generated policy artifacts to:

- `~/.config/mlx-launcher/governance/engrave-governance-brief.md`
- `~/.config/mlx-launcher/governance/gemini-policy.md`
- `~/.config/mlx-launcher/governance/hooks/pre-commit`
- `~/.config/mlx-launcher/governance/hooks/session-close-check`

The packaged governance preset keeps configured runners on the Engrave interposer path and includes sub-agent launch control, context exhaustion relay, human-in-the-loop interception, UIA workflow DAG guidance, commit/worktree hygiene, TDD, and mock/stub disclosure rules.

## Architecture

MLX Launcher has three layers:

1. **Model Layer** -- discovers MLX models across local directories, HuggingFace, and network servers. Manages generation profiles and system prompts.

2. **Server Layer** -- controls the `mlx_lm` inference server lifecycle. Monitors health, tails logs, manages PIDs.

3. **Proxy Layer** -- the Engrave interposer sits between AI runners and the MLX backend. It accepts requests in any supported format (Anthropic, OpenAI, Gemini), translates them through a canonical intermediate representation, forwards to the backend, and translates the streaming response back to the caller's format. This means Claude Code (which speaks Anthropic API) can use a local MLX model (which speaks OpenAI Chat Completions) without any modification.

### Translation Pipeline

```
Client Request (Anthropic/OpenAI/Gemini)
  --> Parse to Canonical IR
  --> Resolve Route (alias -> default -> passthrough)
  --> Serialize to Backend Format
  --> Forward to MLX Server
  --> Parse Backend SSE Stream
  --> Translate Each Event to Canonical
  --> Serialize to Client Format
  --> Stream Back to Client
```

## Related Libraries

The interposer and governance engine are available as standalone open-source Swift packages:

- [libengrave-ai-interposer-swift](https://github.com/damienheiser/libengrave-ai-interposer-swift) -- API translation proxy library
- [libengrave-ai-governance-swift](https://github.com/damienheiser/libengrave-ai-governance-swift) -- Governance engine library

## License

MIT
