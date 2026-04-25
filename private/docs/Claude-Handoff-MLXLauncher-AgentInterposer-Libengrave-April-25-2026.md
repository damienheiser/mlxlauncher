# Claude Handoff — MLXLauncher, AgentInterposer, libengrave Swift Libraries

Date: April 25, 2026  
Prepared for: Claude / Claude Code  
Prepared by: Codex  
Primary objective: continue implementation of the Engrave-governed runner ecosystem across MLXLauncher, AgentInterposer, `libengrave-ai-interposer-swift`, and `libengrave-ai-governance-swift`.

## Current Repository State

### MLXLauncher

- Local path: `/Users/hedon/Augments/mlxLauncher`
- Branch: `main`
- Latest commit: `c3bfd86 Add Engrave-governed runner registry and governance controls`
- Remote pushed: `https://github.com/damienheiser/mlxlauncher.git main`
- Installed app: `/Applications/MLXLauncher.app`
- Validation performed:
  - `swift build`
  - `swift run MLXLauncherTestSuite`
  - `bash -n scripts/build_app.sh`
  - `./scripts/build_app.sh release`

### AgentInterposer

- Local path: `/Users/hedon/Augments/AgentInterposer`
- Branch: `main`
- Latest commit: `2b305f7 Add runner registry implementation plan`
- Remote pushed: `https://github.com/damienheiser/AgentInterposer.git main`
- Added doc: `private/docs/Runner-Registry.md`

### libengrave-ai-interposer-swift

- Local path status: not found adjacent to MLXLauncher during this handoff.
- Expected role: extracted Swift package for Engrave interposer/proxy code currently embedded under `MLXLauncher/Engrave/Sources/EngraveInterposer`.
- Recommended first action: locate or create this repo before extraction work.

### libengrave-ai-governance-swift

- Local path status: not found adjacent to MLXLauncher during this handoff.
- Expected role: extracted Swift package for Engrave governance code currently embedded under `MLXLauncher/Engrave/Sources/EngraveGovernance`.
- Recommended first action: locate or create this repo before extraction work.

## Executive Summary

MLXLauncher now works as a SwiftUI control surface for launching local/cloud/network models through Engrave. It includes:

- model discovery and Model Store loading into the main launcher selection path,
- local MLX server process lifecycle control,
- in-process Engrave interposer startup,
- cloud model routing through Engrave,
- non-streaming and streaming Engrave response handling,
- packaged governance presets and toggles,
- generated governance policy artifacts/hooks,
- dependency-free test suite,
- `.app` bundle build/install script,
- runner registry implementation plan.

The strategic next step is to move runner registry and deep runner governance into AgentInterposer on the Rust train, while extracting reusable Swift interposer/governance libraries from the embedded MLXLauncher `Engrave/` package.

## Important Documents To Read First

In MLXLauncher:

1. `private/docs/Runner-Registry.md`
2. `private/docs/mlx-launcher-analysis-april-25-2026.md`
3. `private/docs/hem-to-engrave-governance-priority-three-april-25-2026.md`
4. `README.md`

In AgentInterposer:

1. `private/docs/Runner-Registry.md`

## What Was Implemented In MLXLauncher

### Model Loading And Viewport Wiring

Files:

- `Sources/Types.swift`
- `Sources/ModelStore.swift`
- `Sources/Services.swift`
- `Sources/Views.swift`
- `Sources/WebUI.swift`
- `Sources/WebServer.swift`

Implemented behavior:

- `MLXModel` now carries `localPath`, `networkHost`, `networkPort`, and `launchIdentity`.
- `ModelSource.network` exists so LAN/manual servers are launchable.
- `AppState.mergeLaunchableModels()` merges script-discovered models, Model Store local models, network models, and cloud config models.
- `AppState.selectDiscoveredModel(_:)` loads `DiscoveredModel` rows into the primary launcher model selection.
- Model Store local/network rows have `Load` actions.
- Web UI periodically refreshes `/api/models` so async bootstrap does not leave it empty/stale.
- REST API uses `launchIdentity` to avoid provider/id collisions.

### Local MLX Server Lifecycle

Files:

- `Sources/Services.swift`

Implemented behavior:

- Local MLX server is launched with `Process`, not detached `nohup` shell.
- App tracks `mlxServerProcess` and PID.
- `stopServer()` terminates the tracked process or known PID instead of broad `pkill -f mlx_lm`.
- `modelPath(for:)` respects discovered `localPath`.

### Cloud/Network/Local Engrave Routing

Files:

- `Sources/Services.swift`
- `Sources/Types.swift`

Implemented behavior:

- Every runner is marked `needsProxy: true`.
- `startInterposer()` builds selected-model-specific `EngraveConfig`.
- Local and network models route to OpenAI-compatible chat completions backends.
- Anthropic cloud models route to Anthropic backend.
- OpenAI cloud models route to OpenAI backend.
- Google cloud models route to Gemini backend.
- Runner command generation no longer accidentally inherits a running local model when a cloud/network model is selected.
- Terminal launch waits for Engrave `/health` before starting governed runners.

### Runner Governance

Files:

- `Sources/Services.swift`
- `Sources/Types.swift`
- `Engrave/Sources/EngraveGovernance/PolicyRule.swift`
- `Engrave/Sources/EngraveGovernance/GovernanceConfig.swift`
- `Sources/Views.swift`

Implemented behavior:

- All bundled runners are Engrave-governed: Claude, Codex, Gemini, Aider, gptme.
- Runner environment includes:
  - `ENGRAVE_GOVERNANCE_ENABLED`
  - `ENGRAVE_GOVERNANCE_BRIEF`
  - `ENGRAVE_GOVERNANCE_POLICY`
  - `ENGRAVE_INTERPOSER_URL`
  - `ENGRAVE_ALL_AGENTS_THROUGH_INTERPOSER=1`
- Generated governance files:
  - `~/.config/mlx-launcher/governance/engrave-governance-brief.md`
  - `~/.config/mlx-launcher/governance/gemini-policy.md`
  - `~/.config/mlx-launcher/governance/hooks/pre-commit`
  - `~/.config/mlx-launcher/governance/hooks/session-close-check`

Packaged rules added:

- Sub-Agent Launch Control
- Context Exhaustion Relay
- Human In The Loop Interception
- UIA Prompt Decomposition And Task DAG
- Git Commit Hygiene
- Git Worktree Hygiene
- Test Driven Development
- No Undocumented Mocks Or Stubs

Governance config now includes:

- `featureToggles`
- `contextBudgets`
- `uiaConfig`

Governance UI now exposes:

- packaged feature toggles,
- Engrave UIA summary,
- context exhaustion relay budgets,
- presets including Packaged.

### Engrave Interposer Behavior

Files:

- `Engrave/Sources/EngraveInterposer/Backend/BackendClient.swift`
- `Engrave/Sources/EngraveInterposer/Server/ConnectionHandler.swift`

Implemented behavior:

- Backend client no longer forces every request to `stream = true`.
- Gemini backend chooses `generateContent` or `streamGenerateContent` based on incoming request.
- Gemini facade sets `canonical.stream` based on `:streamGenerateContent` path.
- Non-streaming requests use `BackendClient.send(...)`.
- Non-streaming response synthesis exists for:
  - Anthropic Messages format,
  - OpenAI Responses format,
  - OpenAI-compatible Chat Completions format,
  - Gemini format.

### Web Server Hardening

File:

- `Sources/WebServer.swift`

Implemented behavior:

- Replaced single fixed `recv` with `Content-Length` aware request reader.
- Added max request size guard.
- API now returns `404` for missing model or runner on launch/server-start paths.

### App Packaging

Files:

- `scripts/build_app.sh`
- `README.md`
- `generate_icon.swift`

Implemented behavior:

- `scripts/build_app.sh release` builds a release binary, creates `MLXLauncher.app`, writes `Info.plist`, generates `AppIcon.icns`, and copies executable/resources.
- Installed app exists at `/Applications/MLXLauncher.app`.

### Test Suite

File:

- `Tests/MLXLauncherTestSuite/main.swift`

Why custom test executable exists:

- This local toolchain did not expose `XCTest` or Swift Testing modules.
- The suite is dependency-free and validates structural/behavioral wiring.

Current checks cover:

1. Codex and bundled runners are Engrave-governed.
2. Cloud model routing through selected-model Engrave config.
3. Model identity and discovered paths.
4. Model Store selection wiring.
5. Web UI live refresh.
6. REST API endpoints and request handling.
7. Non-streaming Engrave behavior.
8. Priority 3 packaged governance availability.
9. Packaging and persistence wiring.
10. All bundled runners Engrave-governed.
11. HeM migration documentation scope.

Run:

```bash
swift run MLXLauncherTestSuite
```

## AgentInterposer Work To Pick Up

AgentInterposer should be the main Rust implementation home for runner registry and deeper runner governance.

Read:

- `/Users/hedon/Augments/AgentInterposer/private/docs/Runner-Registry.md`

Implement in phases:

### Phase A — Runner Registry Crate

Create a runner registry module/crate with:

- `RunnerDescriptor`
- `DetectedRunner`
- `RunnerCapability`
- `RunnerProbe`
- `RunnerLaunchAdapter`

Priority descriptors:

- Claude Code
- Codex CLI
- Gemini CLI
- Aider
- gptme
- OpenCode
- Goose
- Continue CLI
- Ollama/LM Studio as backends, not full agent runners

### Phase B — Detection Engine

Detect runners using:

- `PATH`
- Homebrew prefixes
- npm global bin paths
- pipx paths
- cargo bin
- manual configured paths
- version/help probes

Store:

- installed status,
- resolved path,
- version,
- help text hash,
- parsed flags,
- config/auth status.

### Phase C — Capability Matrix

Normalize capabilities:

- model flag support,
- provider/base URL support,
- API key env,
- policy file support,
- MCP support,
- tool allow/deny support,
- approval mode,
- sandbox mode,
- worktree support,
- headless mode,
- sub-agent support.

### Phase D — Launch Adapters

Every adapter must generate:

- command args,
- env vars,
- generated config paths,
- generated policy paths,
- preflight warnings,
- Engrave interposer base URL,
- `ENGRAVE_ALL_AGENTS_THROUGH_INTERPOSER=1`.

### Phase E — OpenRouter Model Catalog

OpenRouter should be a model/backend catalog, not a runner.

Implement:

- fetch/cache `GET https://openrouter.ai/api/v1/models`,
- parse model id/provider/context/pricing/modalities/params,
- expose OpenRouter models as governed backend selections,
- route through Engrave using OpenAI-compatible provider config.

### Phase F — Sub-Agent Launch Control

Runner-governance decision point:

1. Detect sub-agent spawn/delegation intent.
2. Evaluate task scope with a small local/cheap model.
3. Decide allow/redirect/split/hold.
4. Route selected sub-agent model through Engrave.
5. Log governance event.
6. Link task DAG node.

### Phase G — Context Exhaustion Relay

Implement:

- per-agent token budgets,
- percentage/absolute thresholds,
- relay model selection,
- handoff brief generation,
- replacement runner launch,
- session DAG linkage.

### Phase H — Human-In-The-Loop Queue

Implement hold queues for:

- inbound prompt,
- outbound response,
- tool call,
- sub-agent spawn,
- model redirection.

Actions:

- approve,
- reject,
- rewrite,
- modify model/backend,
- annotate reason.

### Phase I — Workflow Task DAG

Implement DAG nodes for:

- task,
- dependency,
- assigned runner/model,
- governance status,
- context budget,
- handoff target,
- verification node,
- commit/test linkage.

## libengrave-ai-interposer-swift Extraction Plan

This repo was not found locally, but it should receive the Swift interposer code currently embedded inside MLXLauncher.

Source path in MLXLauncher:

- `Engrave/Sources/EngraveInterposer/`

Target package should expose:

- `Engrave`
- `EngraveConfig`
- `ProxyServer`
- `ConnectionHandler`
- `BackendClient`
- `RouteResolver`
- canonical IR types
- stream/message/tool translators

Extraction steps:

1. Create or locate `libengrave-ai-interposer-swift`.
2. Add Swift Package manifest.
3. Copy `Engrave/Sources/EngraveInterposer` into package sources.
4. Preserve macOS 14 / Network framework linkage.
5. Add unit tests for:
   - route resolution,
   - request parsing,
   - model list output,
   - Gemini stream/non-stream endpoint choice,
   - OpenAI/Anthropic/Gemini translation paths,
   - non-streaming response synthesis.
6. Update MLXLauncher `Package.swift` to depend on this package instead of embedded `EngraveInterposer` target.
7. Keep AgentInterposer Rust implementation as the main runner-governance train; Swift package remains the macOS embedding layer.

## libengrave-ai-governance-swift Extraction Plan

This repo was not found locally, but it should receive the Swift governance code currently embedded inside MLXLauncher.

Source path in MLXLauncher:

- `Engrave/Sources/EngraveGovernance/`

Target package should expose:

- `GovernanceConfig`
- `GovernanceFeature`
- `ContextBudget`
- `UIAGovernanceConfig`
- `PolicyRule`
- `PolicyEngine`
- `GovernanceBridge`
- `ToolInterceptor`
- `ConditionEvaluator`
- governance events/types

Extraction steps:

1. Create or locate `libengrave-ai-governance-swift`.
2. Add Swift Package manifest.
3. Copy `Engrave/Sources/EngraveGovernance` into package sources.
4. Depend on `libengrave-ai-interposer-swift` for canonical request/event types.
5. Add tests for:
   - packaged rule names and patterns,
   - preset contents,
   - feature toggle defaults,
   - context budget serialization,
   - UIA config serialization,
   - condition evaluator arithmetic/string logic,
   - policy engine request/tool/stream decisions,
   - governance bridge provider parsing.
6. Update MLXLauncher `Package.swift` to depend on this package instead of embedded `EngraveGovernance` target.
7. Ensure generated policy artifact logic remains in MLXLauncher or moves to a shared helper if reusable.

## Known Caveats / Risks

1. **Native sub-agent interception is not fully implemented yet.**  
   MLXLauncher injects policy and routes traffic through Engrave, but true process-level sub-agent supervision requires runner-specific adapters in AgentInterposer.

2. **Human-in-the-loop rewriting is policy/config only right now.**  
   Full HITL requires a durable hold queue and UI.

3. **Context relay is budget/config/policy only right now.**  
   Actual compaction requires session transcript capture and replacement-runner launch adapters.

4. **Workflow DAG UI is not implemented.**  
   UIA/DAG concepts are represented as governance config and generated policy; an editable graph remains future work.

5. **Swift libraries are not extracted yet.**  
   MLXLauncher still contains an embedded `Engrave` Swift package.

6. **Release build warnings remain in embedded Engrave code.**  
   Warnings seen:
   - `ProxyServer.swift`: `await` with no async operations.
   - `ConditionEvaluator.swift`: `chars` can be `let`.
   These are non-fatal but should be cleaned.

## Claude Suggested First Actions

### In MLXLauncher

1. Run:
   ```bash
   cd /Users/hedon/Augments/mlxLauncher
   swift build
   swift run MLXLauncherTestSuite
   ```
2. Launch app from `/Applications/MLXLauncher.app` and inspect Governance panel.
3. Enable Packaged preset and confirm artifacts appear under `~/.config/mlx-launcher/governance/`.
4. Test launch command previews for Claude, Codex, Gemini, Aider, and gptme.
5. Add runtime integration tests where practical.

### In AgentInterposer

1. Read `private/docs/Runner-Registry.md`.
2. Create Rust runner-registry module/crate.
3. Implement descriptors and fixture-based detection tests for Claude, Codex, Gemini, Aider, and gptme first.
4. Implement launch adapter output structs before doing process spawning.
5. Add OpenRouter model catalog cache/parser.
6. Implement sub-agent launch control and context relay as governance decision services.

### In Swift Libraries

1. Locate/create `libengrave-ai-interposer-swift` and `libengrave-ai-governance-swift`.
2. Extract embedded Swift package targets out of MLXLauncher.
3. Add real tests in the extracted packages.
4. Repoint MLXLauncher dependencies to those packages.

## Commands Already Run Successfully

In MLXLauncher:

```bash
swift build
swift run MLXLauncherTestSuite
bash -n scripts/build_app.sh
./scripts/build_app.sh release
rm -rf /Applications/MLXLauncher.app
cp -R MLXLauncher.app /Applications/
git push https://github.com/damienheiser/mlxlauncher.git main
```

In AgentInterposer:

```bash
git add private/docs/Runner-Registry.md
git commit -m "Add runner registry implementation plan"
git push origin main
```

## Final State At Handoff

- MLXLauncher is pushed and clean at `c3bfd86`.
- AgentInterposer is pushed and clean at `2b305f7`.
- `/Applications/MLXLauncher.app` is installed.
- Runner Registry plan exists in both:
  - `MLXLauncher/private/docs/Runner-Registry.md`
  - `AgentInterposer/private/docs/Runner-Registry.md`
- This handoff doc exists at:
  - `MLXLauncher/private/docs/Claude-Handoff-MLXLauncher-AgentInterposer-Libengrave-April-25-2026.md`
