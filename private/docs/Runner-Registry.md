# Runner Registry And Engrave-Governed Control Surfaces

## Purpose

MLX Launcher and Engrave should treat CLI AI tools as **runners** and model catalogs such as OpenRouter, MLX, Ollama, Anthropic, OpenAI, and Gemini as **model backends**. The runner registry is the bridge between them: it detects installed runners, understands their capabilities, exposes safe control surfaces, and forces all model traffic and sub-agent launches back through Engrave governance.

This plan is intended to move into `../AgentInterposer` for implementation on the main Rust train while MLX Launcher keeps a Swift UI/control-plane surface.

## Core Principle

All configured runners, including their sub-agents, must remain inside the Engrave governance engine.

- Runner launches receive Engrave interposer URLs and governance policy artifacts.
- Runners that can configure providers directly are pointed at Engrave.
- Runners that spawn sub-agents must do so through Engrave policy and model-routing controls.
- Local, cloud, and cheap-model redirection decisions happen at the Engrave runner-governance boundary.

## Runner Registry Data Model

A `RunnerDescriptor` should capture:

- `id`: stable runner id, e.g. `claude`, `codex`, `gemini`, `aider`.
- `displayName`: human-readable name.
- `binaryNames`: possible executable names.
- `installSources`: Homebrew, npm, pipx, cargo, app bundle, manual path.
- `versionCommand`: command used to detect version.
- `helpCommand`: command used to parse supported flags.
- `configFiles`: known config locations.
- `authSignals`: env vars or files indicating auth state.
- `providerControls`: base URL, model, provider, API key env, config file support.
- `governanceControls`: policy file support, MCP support, hooks, sandbox, approval mode.
- `agentControls`: sub-agent support, task delegation knobs, worktree controls, context controls.
- `launchAdapter`: command/env generation strategy.

A `DetectedRunner` should capture:

- `descriptorId`
- `installed`
- `resolvedPath`
- `version`
- `authStatus`
- `configStatus`
- `capabilities`
- `warnings`
- `lastDetectedAt`

## Priority Runner Set

### Tier 1 — Immediate

| Runner | Detection | Engrave Control Surface |
|---|---|---|
| Claude Code | `claude --version`, `claude --help` | `ANTHROPIC_BASE_URL`, `ANTHROPIC_API_KEY`, `--model`, `--permission-mode`, `--append-system-prompt`, MCP config, tool allow/deny |
| Codex CLI | `codex --version`, `codex --help` | `OPENAI_BASE_URL`, `OPENAI_API_KEY`, `-m`, `-c model_provider`, `-c model_providers.*`, sandbox, approval policy |
| Gemini CLI | `gemini --version`, `gemini --help` | `GOOGLE_GEMINI_BASE_URL`, `GEMINI_API_KEY`, `GOOGLE_API_KEY`, `-m`, `--policy`, `--approval-mode`, sandbox |
| Aider | `aider --version`, `aider --help` | OpenAI-compatible API base, model, auto-commit controls, lint/test hooks, edit format |
| gptme | `gptme --version`, `gptme --help` | OpenAI-compatible API base, model, workspace controls |

### Tier 2 — Next

| Runner | Detection | Engrave Control Surface |
|---|---|---|
| OpenCode | `opencode --version`, config probe | provider/model config, base URL, tool/MCP policy, headless/TUI controls |
| Goose | `goose --version`, `goose configure` probe | provider/model config, extensions, local provider routing, ACP/API mode |
| Continue CLI | `continue --version` if available | provider/model config, workspace policy |
| Ollama CLI | `ollama --version`, `ollama list` | local backend discovery and model metadata, not a full agent runner |
| LM Studio CLI/server | process/API probe | local OpenAI-compatible backend discovery, not a full agent runner |

### Tier 3 — IDE/Extension Or Policy Export

| Runner/Tool | Strategy |
|---|---|
| Cline | Export Engrave policy/config; detect extension config where possible |
| Roo Code | Export Engrave policy/config; detect extension config where possible |
| Kilo Code | Export Engrave policy/config; detect extension config where possible |
| Cursor/Windsurf | Policy/rules export and git hooks; limited process control |

## OpenRouter And Model Catalog Integration

OpenRouter should be treated as a model catalog and cloud backend, not a runner.

Implementation:

1. Sync `GET https://openrouter.ai/api/v1/models`.
2. Store model id, provider, context length, pricing, modality, supported parameters.
3. Expose OpenRouter models alongside MLX/cloud models.
4. Route OpenRouter selections through Engrave using an OpenAI-compatible provider config.
5. Allow runner adapters to select any OpenRouter model while keeping requests governed.

## Common Control Surface Buckets

Every runner card should expose only supported controls, normalized into these groups:

1. **Model And Provider**
   - selected model
   - provider/backend
   - base URL
   - API key env
   - OpenRouter/MLX/Ollama/OpenAI/Anthropic/Gemini backend status

2. **Governance**
   - force Engrave interposer
   - policy file path
   - human-in-the-loop hold/rewrite
   - sub-agent launch control
   - context exhaustion relay
   - workflow DAG requirement

3. **Autonomy**
   - approval policy
   - permission mode
   - sandbox mode
   - dangerous bypass flags warning/lockout

4. **Tools And MCP**
   - MCP config path
   - allowed tools
   - denied tools
   - external network warning
   - filesystem boundary controls

5. **Git Hygiene**
   - auto-commit on/off
   - one logical change per commit
   - one concern per branch
   - end-of-session worktree cleanliness
   - generated pre-commit/session-close hooks

6. **Testing**
   - test command
   - lint command
   - positive test required
   - negative test required
   - no undocumented mocks/stubs/scaffolds

7. **Context Relay**
   - per-agent token budget
   - percentage threshold
   - relay model
   - handoff brief style
   - replacement runner/model

## Detection Plan

### Phase 1 — Static Descriptor Registry

Create a checked-in descriptor table for known runners.

- Rust: `crates/runner-registry/src/descriptors/*.rs` or JSON/TOML registry.
- Swift: consume serialized registry from Engrave or mirror minimal display metadata.
- Include command probes, config paths, and capability flags.

### Phase 2 — Local Probe Engine

Implement local detection:

- search `PATH`
- Homebrew prefixes: `/opt/homebrew/bin`, `/usr/local/bin`
- npm global bins
- pipx bins
- cargo bins
- common app bundle helper paths
- user-configured paths

Probe outputs:

- installed/not installed
- version
- help text hash
- parsed flags
- config presence
- auth signal presence

### Phase 3 — Capability Parser

Parse `--help` output and config schemas into normalized capabilities:

- supports base URL env
- supports model flag
- supports policy file
- supports MCP config
- supports approval mode
- supports sandbox
- supports worktree
- supports headless mode
- supports sub-agents

### Phase 4 — Engrave Launch Adapters

Each runner gets a launch adapter that returns:

- command arguments
- environment
- generated config files
- generated policy files
- warnings
- required preflight checks

All adapters must include:

- Engrave base URL env/config
- dummy local API key when needed
- governance brief path
- policy path
- `ENGRAVE_ALL_AGENTS_THROUGH_INTERPOSER=1`

### Phase 5 — UI Control Surfaces

MLX Launcher shows:

- runner installed/version status
- auth/config status
- detected capabilities
- unsupported controls disabled with explanation
- command preview
- governance warnings
- generated policy/config paths

### Phase 6 — OpenRouter Sync

Add catalog sync:

- API fetcher
- local cache
- search/filter by provider, price, context, modality
- model selection writes to launch config
- OpenRouter backend routes through Engrave

### Phase 7 — Sub-Agent Launch Control

Implement sub-agent governance as a runner-layer decision point:

1. Detect spawn/delegation intent from prompts, tool calls, or runner events.
2. Evaluate work scope with a small local/cheap model.
3. Choose one of:
   - allow requested model
   - redirect to cheaper cloud model
   - redirect to local MLX model
   - split into multiple local workers
   - hold for human approval
4. Log decision as governance event.
5. Emit updated task DAG node.

### Phase 8 — Context Exhaustion Relay

Implement per-agent context budgets:

1. Track estimated tokens per runner/session/agent type.
2. At threshold, pause or warn.
3. Launch relay model through Engrave.
4. Generate detailed handoff brief:
   - goal
   - constraints
   - completed work
   - changed files
   - unresolved decisions
   - tests run
   - next actions
5. Start replacement runner/agent with handoff brief.
6. Link old/new sessions in governance event DAG.

### Phase 9 — Human-In-The-Loop Interception

Add message hold queues:

- incoming prompt hold
- outgoing assistant response hold
- tool-call hold
- sub-agent spawn hold

Actions:

- approve
- reject
- rewrite
- modify model/backend
- redirect to local/cheap model
- annotate with reason

### Phase 10 — Workflow Task DAG

Add a workflow DAG model:

- task nodes
- dependencies
- assigned runner/model
- governance status
- context budget
- handoff target
- verification node
- commit/test linkage

The UIA should generate and maintain this DAG while informing the user what work is happening.

## Rust Train Implementation Sketch

Suggested crates/modules in `AgentInterposer`:

```text
crates/
  runner-registry/
    descriptors/
    probe.rs
    capabilities.rs
    detected_runner.rs
  runner-adapters/
    claude.rs
    codex.rs
    gemini.rs
    aider.rs
    gptme.rs
    opencode.rs
    goose.rs
  model-catalog/
    openrouter.rs
    mlx.rs
    ollama.rs
  governance-runtime/
    subagent_control.rs
    context_relay.rs
    hitl_queue.rs
    workflow_dag.rs
```

## Acceptance Criteria

- Detect at least Claude, Codex, Gemini, Aider, and gptme locally.
- Display runner version, install status, and supported controls.
- Launch every configured runner through Engrave by default.
- Sync OpenRouter model catalog and select OpenRouter models as governed backends.
- Generate runner-specific policy/config artifacts.
- Provide toggles for packaged governance controls.
- Add tests for each runner adapter's generated command/env.
- Add tests for detection parsing from fixture help output.
- Add tests for OpenRouter model cache parsing.
- Add tests for sub-agent redirection decisions.
