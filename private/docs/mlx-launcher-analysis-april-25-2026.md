# MLX Launcher Analysis — April 25, 2026

## Executive Summary

The launcher compiled, but several features were presentational rather than wired end-to-end. The major breakages were:

1. Model Store-discovered models were not launchable from the main viewport/model list.
2. Downloaded/local/network models did not carry their real path or endpoint into launch commands.
3. Codex was incorrectly marked as non-proxy even though it is part of the governed interpositional path.
4. Proxy-governed launches could race Engrave startup because Terminal waited only for MLX readiness.
5. The web UI model list could go stale after async bootstrap and had a prior JavaScript mutability hazard.
6. There was no runnable test suite in the repository.

The first fix pass implemented the foundational wiring and added a dependency-free Swift test suite that validates the high-risk launch and model-selection paths.

## Engrave Sub-Agent Findings

### Model Loading / Viewport Wiring

- `AppState.refreshModels()` populated `allModels` only from `~/mlx/bin/mlx-models` plus cloud config.
- `ModelStore.scanLocalModels()` discovered real model directories, but its results stayed in `state.modelStore.localModels`.
- Model Store local rows had only delete controls; they did not load a model into `state.selectedModel`.
- Network-discovered models were displayed but not selectable or launchable.
- Downloaded Hugging Face models refreshed only `ModelStore`, not the main launch list.
- `modelPath(for:)` assumed `~/.lmstudio/models/<model.id>` and ignored discovered paths such as HF cache snapshots or custom directories.

### Claude / Codex / Gemini Through Interposer

- Codex was set to `needsProxy: false` while `runnerCommand` pointed it at `http://localhost:8900/v1`; local Codex launches could connect to a stopped proxy.
- Codex launch arguments lacked explicit provider configuration for the governed Engrave endpoint.
- Proxy launches started MLX and Engrave asynchronously, but Terminal waited only for MLX `/v1/models`, creating a race against Engrave startup.
- `startInterposer()` always creates a local-MLX route with `EngraveConfig.forLocalMLX`; cloud model launch behavior should be clarified separately because this task is about interpositional governance into MLX.
- Engrave currently streams backend responses for all requests; non-streaming/headless tool modes may need future handling.

### Additional Defects

- Web UI loaded `/api/models` once, so it could render before async bootstrap populated models and never update.
- Web server uses a simple single-buffer `recv`; large/split POST bodies may need a more robust HTTP read loop.
- README app bundle instructions do not wire `Info.plist` or generated icons.
- `EngraveGovernance.PolicyEngine` has Swift 6 actor-isolation warning risk around init-time rule compilation.

## Fixes Implemented In This Pass

### Launchable Model Metadata

- Extended `MLXModel` with:
  - `localPath`
  - `networkHost`
  - `networkPort`
  - `launchIdentity`
  - `isNetwork`
- Added `ModelSource.network` so LAN/manual model servers are first-class launch candidates.
- Updated `isCloud` so network models are not treated as cloud providers.
- Updated `modelPath(for:)` to prefer discovered `localPath` before falling back to `~/.lmstudio/models/<id>`.

### Model Store Wiring

- Added `AppState.mergeLaunchableModels()` to combine:
  - script-discovered MLX models
  - Model Store local models
  - network-discovered models
  - configured cloud models
- Added `AppState.selectDiscoveredModel(_:)` to load a `DiscoveredModel` into the main launcher selection.
- Added `Load` controls to Model Store local and network rows.

### Governed Interposer Launches

- Changed Codex runner metadata to `needsProxy: true` to reflect governed interpositional routing.
- Added Terminal-side waiting for `http://localhost:8900/health` for proxy-governed launches.
- Expanded default Codex launch configuration with an MLX/Engrave model provider and `-m <model>` when the user did not supply model flags.

### Web UI

- Ensured mutable JavaScript state for models/runners/selection.
- Added periodic `/api/models` refresh so the web viewport picks up models after async app bootstrap and Model Store updates.

### Test Suite

- Added `MLXLauncherTestSuite`, a dependency-free executable test suite because this local toolchain does not provide `XCTest` or Swift Testing modules.
- Covered:
  - Codex governed proxy configuration
  - discovered model path identity
  - Model Store-to-launcher selection wiring
  - live web UI refresh behavior
  - REST API endpoint presence

## Remaining Plan

### Priority 1 — Complete Launch Semantics

1. Verify Claude Code accepts arbitrary `--model` names when `ANTHROPIC_BASE_URL` is pointed at Engrave.
2. Verify Gemini CLI base URL configuration; if `GOOGLE_GEMINI_BASE_URL` is unsupported, add a wrapper/config strategy.
3. Add user-visible validation when a cloud model is selected for a local-MLX governed launch, or add explicit non-local provider routing in Engrave config.
4. Track the launched `mlx_lm.server` PID instead of using broad `pkill -f mlx_lm`.

### Priority 2 — Harden Engrave / Web Server

1. Preserve non-streaming request semantics in Engrave for clients that expect JSON responses.
2. Add a robust HTTP request reader in `WebServer` that honors `Content-Length` across split reads.
3. Add API error responses when a requested model or runner does not exist.
4. Surface Engrave route and health status in the launch UI.

### Priority 3 — Package And UX Polish

1. Wire generated app icon and `Info.plist` into the app bundle workflow.
2. Persist runner settings and Model Store scan directories.
3. Add visible status when Model Store-discovered models have been loaded into the main launcher.
4. Add a dedicated embedded web viewport panel if the desired UX is to view `http://localhost:8421` inside the app.

## Validation Performed

- `swift build` passes.
- `swift run MLXLauncherTestSuite` passes all tests.

## Files Changed

- `Package.swift`
- `Sources/Types.swift`
- `Sources/ModelStore.swift`
- `Sources/Services.swift`
- `Sources/Views.swift`
- `Sources/WebUI.swift`
- `Tests/MLXLauncherTestSuite/main.swift`
- `private/docs/mlx-launcher-analysis-april-25-2026.md`

## April 25 Follow-Up — Priority 1 And 2 Fixes

### Priority 1 Completed

- Added selected-model Engrave routing for local, network, Anthropic, OpenAI, and Google/Gemini models.
- Made cloud models arbitrary launcher targets: any runner can select a cloud model and the runner request is governed through Engrave to that model/provider.
- Prevented cloud/network launches from accidentally inheriting a currently running local MLX model name.
- Added Engrave health waiting before governed runners start their terminal session.
- Replaced broad `pkill -f mlx_lm` shutdown behavior with tracked `Process`/PID control for app-launched MLX servers.
- Verified local runner CLI affordances with installed `claude`, `codex`, and `gemini` binaries; Claude and Gemini both expose model flags, and Codex exposes `-m/--model` plus `-c/--config` used by the launcher.

### Priority 2 Completed

- Preserved non-streaming Engrave requests instead of forcing every backend call to `stream = true`.
- Added non-streaming response synthesis for Anthropic, OpenAI Responses, OpenAI-compatible Chat Completions, and Gemini facades from common backend JSON shapes.
- Made Gemini backend routing choose `generateContent` vs. `streamGenerateContent` based on the incoming facade request.
- Replaced the launcher REST server's single fixed `recv` with a `Content-Length` aware request reader for split/larger POST bodies.
- Added API 404 responses when launch/server-start requests refer to missing models or runners.
- Surfaced the selected Engrave target in the Interposer panel so the user can see local/network/cloud routing at launch time.

### Additional Validation

- `swift build` passes after Priority 1/2 changes.
- `swift run MLXLauncherTestSuite` now covers seven checks, including cloud route selection, robust WebServer request handling, and non-streaming Engrave behavior.

## April 25 Follow-Up — Priority 3 Fixes

### Priority 3 Completed

- Added `scripts/build_app.sh` to produce a real `.app` bundle with `Info.plist` and generated `AppIcon.icns`.
- Persisted runner settings in `~/.config/mlx-launcher/runner-settings.json`.
- Persisted Model Store scan directories in `~/.config/mlx-launcher/model-store.json`.
- Added packaged governance rules for sub-agent launch control, context exhaustion relay, human-in-the-loop interception, UIA prompt decomposition, workflow DAGs, git commit hygiene, git worktree hygiene, TDD, and mock/stub disclosure.
- Added governance feature toggles in the Governance panel so each packaged control can be enabled or disabled.
- Added UIA and context budget surfaces in the Governance panel.
- Marked all configured runners as Engrave-governed so local, cloud, and sub-agent model traffic stays on the interposer path.
- Generated policy artifacts and hooks under `~/.config/mlx-launcher/governance/`.
- Added HeM migration notes at `private/docs/hem-to-engrave-governance-priority-three-april-25-2026.md`.
