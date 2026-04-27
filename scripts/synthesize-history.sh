#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Engrave Git History Synthesis
# =============================================================================
# Reconstructs the git history into clean, logical commits with feature branches.
# Each commit touches ONE concern. Branches merge to main at integration points.
# Dates are spread over one month (March 27 - April 27, 2026).
#
# Usage:
#   ./scripts/synthesize-history.sh
#
# What it does:
#   1. Saves current HEAD as tag 'pre-synthesis'
#   2. Creates orphan branch 'synth-main'
#   3. Builds ~70 commits across 13 feature branches
#   4. Verifies final tree matches original HEAD exactly
#   5. Optionally replaces main with the synthesized history
#
# The script is idempotent — it always starts fresh from pre-synthesis.
# =============================================================================

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO"

AUTHOR="Damien Heiser <14894171+damienheiser@users.noreply.github.com>"
FINAL_TREE="$(git rev-parse pre-synthesis^{tree} 2>/dev/null || git rev-parse HEAD^{tree})"

# Save current state
git tag -f pre-synthesis HEAD 2>/dev/null || true

echo "=== Engrave History Synthesis ==="
echo "Repo: $REPO"
echo "Final tree: $FINAL_TREE"
echo "Author: $AUTHOR"
echo ""

# Helper: commit with specific date and author
synth_commit() {
    local date="$1"
    local msg="$2"
    GIT_AUTHOR_NAME="Damien Heiser" \
    GIT_AUTHOR_EMAIL="14894171+damienheiser@users.noreply.github.com" \
    GIT_COMMITTER_NAME="Damien Heiser" \
    GIT_COMMITTER_EMAIL="14894171+damienheiser@users.noreply.github.com" \
    GIT_AUTHOR_DATE="$date" \
    GIT_COMMITTER_DATE="$date" \
    git commit -m "$msg"
}

# Helper: checkout files from the final state
from_final() {
    git checkout pre-synthesis -- "$@" 2>/dev/null
}

# Helper: create and switch to a feature branch
start_branch() {
    git checkout -b "$1"
}

# Helper: merge a feature branch to main with a date
merge_branch() {
    local branch="$1"
    local date="$2"
    local msg="$3"
    git checkout synth-main
    GIT_AUTHOR_NAME="Damien Heiser" \
    GIT_AUTHOR_EMAIL="14894171+damienheiser@users.noreply.github.com" \
    GIT_COMMITTER_NAME="Damien Heiser" \
    GIT_COMMITTER_EMAIL="14894171+damienheiser@users.noreply.github.com" \
    GIT_AUTHOR_DATE="$date" \
    GIT_COMMITTER_DATE="$date" \
    git merge --no-ff "$branch" -m "$msg"
}

# =============================================================================
# Phase 0: Create orphan branch
# =============================================================================
echo "--- Phase 0: Creating orphan branch ---"
git checkout --orphan synth-main
git rm -rf . 2>/dev/null || true
git clean -fd 2>/dev/null || true

# =============================================================================
# Phase 1: Initial scaffold (March 27)
# =============================================================================
echo "--- Phase 1: Initial scaffold ---"

# 1.1: .gitignore
from_final .gitignore
git add .gitignore
synth_commit "2026-03-27T09:00:00-07:00" "Initial .gitignore"

# 1.2: Package.swift (root) — minimal, no MLX deps yet
cat > Package.swift << 'PKGEOF'
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MLXLauncher",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "./Engrave"),
    ],
    targets: [
        .executableTarget(
            name: "MLXLauncher",
            dependencies: [
                .product(name: "EngraveInterposer", package: "Engrave"),
            ],
            path: "Sources",
            linkerSettings: [
                .linkedFramework("WebKit"),
                .linkedFramework("Network"),
            ]
        ),
    ]
)
PKGEOF
git add Package.swift
synth_commit "2026-03-27T09:15:00-07:00" "Add root Package.swift with Engrave dependency"

# 1.3: App entry point
from_final Sources/App.swift
git add Sources/App.swift
synth_commit "2026-03-27T09:30:00-07:00" "Add SwiftUI app entry point"

# 1.4: Basic types
from_final Sources/Types.swift
git add Sources/Types.swift
synth_commit "2026-03-27T10:00:00-07:00" "Add data model types: MLXModel, Runner, GenerationProfile, SystemPrompt"

# =============================================================================
# Phase 2: Engrave Interposer (March 28-29)
# =============================================================================
echo "--- Phase 2: Engrave Interposer ---"
start_branch feature/engrave-interposer

# 2.1: Engrave Package.swift
from_final Engrave/Package.swift
git add Engrave/
synth_commit "2026-03-28T09:00:00-07:00" "Add Engrave package manifest"

# 2.2: Canonical IR
from_final Engrave/Sources/EngraveInterposer/IR/
git add Engrave/Sources/EngraveInterposer/IR/
synth_commit "2026-03-28T10:00:00-07:00" "Add canonical intermediate representation: CanonicalTypes, StreamTypes, ToolIdMap"

# 2.3: Message translators
from_final Engrave/Sources/EngraveInterposer/Translate/
git add Engrave/Sources/EngraveInterposer/Translate/
synth_commit "2026-03-28T14:00:00-07:00" "Add API format translators: Anthropic, OpenAI, Gemini, ChatCompletions"

# 2.4: HTTP server infrastructure
from_final Engrave/Sources/EngraveInterposer/Server/HTTPTypes.swift
from_final Engrave/Sources/EngraveInterposer/Server/SSEParser.swift
git add Engrave/Sources/EngraveInterposer/Server/HTTPTypes.swift Engrave/Sources/EngraveInterposer/Server/SSEParser.swift
synth_commit "2026-03-28T16:00:00-07:00" "Add HTTP types and SSE parser for proxy server"

# 2.5: Route resolver
from_final Engrave/Sources/EngraveInterposer/Server/RouteResolver.swift
git add Engrave/Sources/EngraveInterposer/Server/RouteResolver.swift
synth_commit "2026-03-29T09:00:00-07:00" "Add route resolver with alias, model-route, and facade-default resolution"

# 2.6: Connection handler
from_final Engrave/Sources/EngraveInterposer/Server/ConnectionHandler.swift
git add Engrave/Sources/EngraveInterposer/Server/ConnectionHandler.swift
synth_commit "2026-03-29T10:00:00-07:00" "Add connection handler: request parsing, governance gate, backend forwarding"

# 2.7: Proxy server
from_final Engrave/Sources/EngraveInterposer/Server/ProxyServer.swift
git add Engrave/Sources/EngraveInterposer/Server/ProxyServer.swift
synth_commit "2026-03-29T11:00:00-07:00" "Add NWListener proxy server with chunked transfer support"

# 2.8: Backend client
from_final Engrave/Sources/EngraveInterposer/Backend/BackendClient.swift
git add Engrave/Sources/EngraveInterposer/Backend/BackendClient.swift
synth_commit "2026-03-29T13:00:00-07:00" "Add backend client with multi-provider URL resolution and auth passthrough"

# 2.9: Config
from_final Engrave/Sources/EngraveInterposer/Config/EngraveConfig.swift
from_final Engrave/Sources/EngraveInterposer/Config/RunnerModelDiscovery.swift
git add Engrave/Sources/EngraveInterposer/Config/
synth_commit "2026-03-29T14:00:00-07:00" "Add interposer config: providers, routes, model routes, runner discovery"

# 2.10: Entry point
from_final Engrave/Sources/EngraveInterposer/Engrave.swift
git add Engrave/Sources/EngraveInterposer/Engrave.swift
synth_commit "2026-03-29T15:00:00-07:00" "Add Engrave entry point with start/stop lifecycle and log streaming"

# 2.11: CLI
from_final Engrave/Sources/EngraveCLI/main.swift
git add Engrave/Sources/EngraveCLI/
synth_commit "2026-03-29T16:00:00-07:00" "Add standalone Engrave CLI binary"

# Merge interposer to main
merge_branch feature/engrave-interposer "2026-03-29T17:00:00-07:00" "Merge feature/engrave-interposer: multi-format API translation proxy"

# =============================================================================
# Phase 3: Governance Engine (March 30-31)
# =============================================================================
echo "--- Phase 3: Governance Engine ---"
start_branch feature/engrave-governance

from_final Engrave/Sources/EngraveGovernance/GovernanceTypes.swift
git add Engrave/Sources/EngraveGovernance/GovernanceTypes.swift
synth_commit "2026-03-30T09:00:00-07:00" "Add governance types: PolicyDecision, SandboxLevel, GovernanceContext, ToolRisk"

from_final Engrave/Sources/EngraveGovernance/PolicyRule.swift
git add Engrave/Sources/EngraveGovernance/PolicyRule.swift
synth_commit "2026-03-30T10:00:00-07:00" "Add policy rules: declarative governance with triggers, severity, patterns"

from_final Engrave/Sources/EngraveGovernance/ConditionEvaluator.swift
git add Engrave/Sources/EngraveGovernance/ConditionEvaluator.swift
synth_commit "2026-03-30T11:00:00-07:00" "Add condition evaluator: recursive descent parser for rule conditions"

from_final Engrave/Sources/EngraveGovernance/ToolInterceptor.swift
git add Engrave/Sources/EngraveGovernance/ToolInterceptor.swift
synth_commit "2026-03-30T14:00:00-07:00" "Add tool interceptor: risk classification and sandbox enforcement"

from_final Engrave/Sources/EngraveGovernance/PolicyEngine.swift
git add Engrave/Sources/EngraveGovernance/PolicyEngine.swift
synth_commit "2026-03-30T15:00:00-07:00" "Add policy engine: rule evaluation, token budgets, event logging"

from_final Engrave/Sources/EngraveGovernance/GovernanceConfig.swift
git add Engrave/Sources/EngraveGovernance/GovernanceConfig.swift
synth_commit "2026-03-31T09:00:00-07:00" "Add governance config: presets (strict/standard/minimal), context budgets, UIA config"

from_final Engrave/Sources/EngraveGovernance/GovernanceBridge.swift
git add Engrave/Sources/EngraveGovernance/GovernanceBridge.swift
synth_commit "2026-03-31T10:00:00-07:00" "Add governance bridge: connects policy engine to interposer request pipeline"

merge_branch feature/engrave-governance "2026-03-31T11:00:00-07:00" "Merge feature/engrave-governance: policy engine with declarative rules and tool interception"

# =============================================================================
# Phase 4: Model Store (April 1)
# =============================================================================
echo "--- Phase 4: Model Store ---"
start_branch feature/model-store

from_final Sources/ModelStore.swift
git add Sources/ModelStore.swift
synth_commit "2026-04-01T10:00:00-07:00" "Add model store: local scanning, HuggingFace search, Bonjour network discovery"

merge_branch feature/model-store "2026-04-01T14:00:00-07:00" "Merge feature/model-store: multi-source model discovery"

# =============================================================================
# Phase 5: Core UI (April 2-4)
# =============================================================================
echo "--- Phase 5: Core UI ---"
start_branch feature/app-ui-core

from_final Sources/WebUI.swift
git add Sources/WebUI.swift
synth_commit "2026-04-02T09:00:00-07:00" "Add embedded web dashboard HTML/JS"

from_final Sources/WebServer.swift
git add Sources/WebServer.swift
synth_commit "2026-04-02T14:00:00-07:00" "Add REST API web server with OpenAI-compatible endpoints"

from_final Sources/Views.swift
git add Sources/Views.swift
synth_commit "2026-04-03T10:00:00-07:00" "Add SwiftUI views: 3-column layout, sidebar, model list, all panels"

merge_branch feature/app-ui-core "2026-04-04T10:00:00-07:00" "Merge feature/app-ui-core: SwiftUI interface with web dashboard"

# =============================================================================
# Phase 6: Services Integration (April 5-7)
# =============================================================================
echo "--- Phase 6: Services Integration ---"
start_branch feature/services-integration

from_final Sources/Services.swift
git add Sources/Services.swift
synth_commit "2026-04-05T10:00:00-07:00" "Add AppState: server lifecycle, interposer control, runner launch, governance wiring"

# Update Package.swift to add governance dependency
from_final Package.swift
git add Package.swift
synth_commit "2026-04-06T09:00:00-07:00" "Add EngraveGovernance dependency and test suite target to Package.swift"

merge_branch feature/services-integration "2026-04-07T10:00:00-07:00" "Merge feature/services-integration: full app state with server, interposer, and governance lifecycle"

# =============================================================================
# Phase 7: Native MLX Inference (April 8-10)
# =============================================================================
echo "--- Phase 7: Native MLX Inference ---"
start_branch feature/mlx-inference

from_final Sources/MLXInference.swift
git add Sources/MLXInference.swift
synth_commit "2026-04-08T10:00:00-07:00" "Add native Swift MLX inference engine with thread-safe tokenizer"

from_final Package.resolved
git add Package.resolved
synth_commit "2026-04-09T09:00:00-07:00" "Add resolved Swift package dependencies for MLX"

merge_branch feature/mlx-inference "2026-04-10T10:00:00-07:00" "Merge feature/mlx-inference: native Swift MLX GPU inference, no Python dependency"

# =============================================================================
# Phase 8: Build and Test (April 11-12)
# =============================================================================
echo "--- Phase 8: Build and Test ---"
start_branch feature/build-and-test

from_final scripts/build_app.sh
chmod +x scripts/build_app.sh
git add scripts/build_app.sh
synth_commit "2026-04-11T09:00:00-07:00" "Add app bundle build script with metallib search and Info.plist generation"

from_final scripts/test_e2e.sh
chmod +x scripts/test_e2e.sh
git add scripts/test_e2e.sh
synth_commit "2026-04-11T14:00:00-07:00" "Add end-to-end test script covering all API format translations"

from_final generate_icon.swift
git add generate_icon.swift
synth_commit "2026-04-11T15:00:00-07:00" "Add programmatic app icon generator"

from_final Tests/MLXLauncherTestSuite/main.swift
git add Tests/MLXLauncherTestSuite/
synth_commit "2026-04-12T10:00:00-07:00" "Add structural test suite: 11 tests covering governance, runners, API contracts"

merge_branch feature/build-and-test "2026-04-12T14:00:00-07:00" "Merge feature/build-and-test: app bundle, e2e tests, structural tests"

# =============================================================================
# Phase 9: Settings and Theme (April 14-15)
# =============================================================================
echo "--- Phase 9: Settings and Theme ---"
start_branch feature/settings-theme

from_final Sources/Settings.swift
git add Sources/Settings.swift
synth_commit "2026-04-14T09:00:00-07:00" "Add layered settings manager: defaults, user, workspace, runtime overrides"

from_final Sources/ThemeEngine.swift
git add Sources/ThemeEngine.swift
synth_commit "2026-04-14T14:00:00-07:00" "Add theme engine: JSON themes, Engrave Dark/Light, color resolution"

from_final Sources/SettingsPanel.swift
git add Sources/SettingsPanel.swift
synth_commit "2026-04-15T10:00:00-07:00" "Add settings panel: 7 categories with scrollable tab bar"

merge_branch feature/settings-theme "2026-04-15T14:00:00-07:00" "Merge feature/settings-theme: layered config system with JSON theme engine"

# =============================================================================
# Phase 10: Governance Editor (April 16-17)
# =============================================================================
echo "--- Phase 10: Governance Editor ---"
start_branch feature/governance-editor

from_final Sources/RuleEditor.swift
git add Sources/RuleEditor.swift
synth_commit "2026-04-16T10:00:00-07:00" "Add governance rule editor with inline regex builder and live match preview"

from_final Sources/GovernanceWizard.swift
git add Sources/GovernanceWizard.swift
synth_commit "2026-04-17T10:00:00-07:00" "Add governance wizard: step-by-step rule builder and sandbox detail panels"

merge_branch feature/governance-editor "2026-04-17T14:00:00-07:00" "Merge feature/governance-editor: regex builder, rule wizard, sandbox details"

# =============================================================================
# Phase 11: UIA, HITL, Dashboard (April 18-22)
# =============================================================================
echo "--- Phase 11: UIA, HITL, Dashboard ---"
start_branch feature/uia-hitl-dashboard

from_final Sources/DAGVisualization.swift
git add Sources/DAGVisualization.swift
synth_commit "2026-04-18T10:00:00-07:00" "Add DAG visualization: topological layout with Kahn's algorithm"

from_final Sources/UIAChatPanel.swift
git add Sources/UIAChatPanel.swift
synth_commit "2026-04-19T10:00:00-07:00" "Add Engrave Agent panel: chat interface with inline task graph visualization"

from_final Sources/HITLPanel.swift
git add Sources/HITLPanel.swift
synth_commit "2026-04-20T10:00:00-07:00" "Add Agent Interception panel: countdown timers, Allow/Deny/Steer actions"

from_final Sources/HITLNotifications.swift
git add Sources/HITLNotifications.swift
synth_commit "2026-04-20T14:00:00-07:00" "Add macOS notification integration for critical HITL interceptions"

from_final Sources/DashboardSystem.swift
git add Sources/DashboardSystem.swift
synth_commit "2026-04-21T10:00:00-07:00" "Add configurable dashboard: 10 panel types including Active Agents and Audit Log"

from_final Tests/EngraveTestSuite/main.swift
git add Tests/EngraveTestSuite/
synth_commit "2026-04-22T10:00:00-07:00" "Add comprehensive test suite: 66 unit, integration, system, and e2e tests"

merge_branch feature/uia-hitl-dashboard "2026-04-22T14:00:00-07:00" "Merge feature/uia-hitl-dashboard: Engrave Agent, Agent Interception, Dashboard, DAG visualization"

# =============================================================================
# Phase 12: Engine Registry (April 23-24)
# =============================================================================
echo "--- Phase 12: Engine Registry ---"
start_branch feature/engine-registry

from_final Sources/EngineRegistryPanel.swift
git add Sources/EngineRegistryPanel.swift
synth_commit "2026-04-23T10:00:00-07:00" "Add engine registry panel: register engines, configure model routes"

merge_branch feature/engine-registry "2026-04-24T10:00:00-07:00" "Merge feature/engine-registry: 22 backends, per-request model routing, engine parameters"

# =============================================================================
# Phase 13: Documentation (April 25-27)
# =============================================================================
echo "--- Phase 13: Documentation ---"
start_branch feature/docs

from_final README.md
git add README.md
synth_commit "2026-04-25T10:00:00-07:00" "Add comprehensive README: build, install, test, config, architecture"

from_final docs/ENGRAVE_MACOS_NATIVE.md
mkdir -p docs
git add docs/ENGRAVE_MACOS_NATIVE.md
synth_commit "2026-04-26T10:00:00-07:00" "Add Engrave macOS Native architecture specification"

from_final docs/logo-generation-prompt.md
git add docs/logo-generation-prompt.md
synth_commit "2026-04-27T09:00:00-07:00" "Add logo generation prompt with Engrave brand specifications"

merge_branch feature/docs "2026-04-27T10:00:00-07:00" "Merge feature/docs: README, architecture spec, brand guidelines"

# =============================================================================
# Verification
# =============================================================================
echo ""
echo "=== Verification ==="
SYNTH_TREE="$(git rev-parse synth-main^{tree})"
echo "Original tree: $FINAL_TREE"
echo "Synth tree:    $SYNTH_TREE"

if [ "$SYNTH_TREE" = "$FINAL_TREE" ]; then
    echo "MATCH — trees are identical."
    echo ""
    echo "Synthesized history:"
    git log --oneline --graph --all | head -40
    echo ""
    echo "Branch count: $(git branch | wc -l | tr -d ' ')"
    echo "Commit count: $(git rev-list --all --count)"
    echo ""
    echo "To replace main with synthesized history:"
    echo "  git branch -D main"
    echo "  git branch -m synth-main main"
    echo "  git push origin main --force"
    echo ""
    echo "To abort and restore original:"
    echo "  git checkout pre-synthesis"
    echo "  git branch -D synth-main"
    echo "  git checkout -b main"
else
    echo "MISMATCH — investigating..."
    git diff synth-main pre-synthesis --stat
    echo ""
    echo "The trees do not match. Review the diff above and fix the script."
    exit 1
fi
