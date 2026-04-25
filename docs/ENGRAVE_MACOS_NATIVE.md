# Engrave macOS Native — Prompt Novel

> Architecture document for the full Engrave platform as a native macOS application.
> Based on the Rust AgentInterposer implementation, TypeScript HeM/Groundwork prototypes,
> and the current MLXLauncher Swift codebase.

## 1. Vision

Engrave macOS Native is the macOS-native GUI for the Engrave platform — a governance-aware
AI agent orchestration system. It wraps MLX local model serving with a multi-provider
interposition proxy, governance engine, UIA (Unified Intelligence Architecture) orchestrator,
HITL (Human In The Loop) controls, and a configurable dashboard system.

The Rust AgentInterposer is the canonical engine. The Swift app is the native macOS surface
that consumes the engine's capabilities. Where the Rust implementation provides a TUI,
the macOS app provides a rich GUI with breakout windows, DAG visualization, and deep
system integration.

## 2. Architecture Layers

```
┌─────────────────────────────────────────────────────┐
│                   macOS Native UI                    │
│   Dashboard │ UIA Chat │ Services │ Governance       │
├─────────────────────────────────────────────────────┤
│                 Swift App State                      │
│   ObservableObject tree, Combine pipelines           │
├─────────────────────────────────────────────────────┤
│            Engrave Swift Interposer                  │
│   In-process proxy: Facade → IR → Governance → Backend│
├─────────────────────────────────────────────────────┤
│              Governance Engine                       │
│   PolicyEngine, CircuitBreakers, ToolInterceptor     │
├─────────────────────────────────────────────────────┤
│            UIA Orchestrator                          │
│   Classifier, Decomposer, TaskGraph, Scorer          │
├─────────────────────────────────────────────────────┤
│         Providers (Backends)                         │
│   MLX Local │ Anthropic │ OpenAI │ Google            │
└─────────────────────────────────────────────────────┘
```

## 3. Module Breakdown

### 3.1 Core Proxy (EngraveInterposer — exists, needs expansion)

The in-process HTTP proxy that sits between agent runners and model providers.

**Current state:** Basic request/response forwarding with Anthropic/OpenAI/Gemini facade
translation. Streaming support via SSE passthrough.

**Target state (from Rust impl):**
- CanonicalRequest/Response IR with full content block typing (Text, ToolUse, ToolResult, Thinking, Image)
- Stream event evaluation (governance can inspect/modify/terminate mid-stream)
- Provider scoring with EMA learning (pick best backend for each task trait)
- CLI subscription backend (zero-cost auth via logged-in CLI tools)

### 3.2 Governance Engine (EngraveGovernance — exists, needs expansion)

**Current state:** PolicyEngine with declarative rules, basic severity levels, tool interception.

**Target state (from Rust impl):**
- Circuit breakers (6 types): TokenBudget, RepeatedFailure, Stall, ScopeViolation, FileConflict, HealthDegradation
  - Each with Closed/HalfOpen/Open FSM, configurable thresholds and cooldowns
- Rogue agent detection: process scanning, network monitoring, event recording
- Session governor with per-session token/cost/time budgets
- Tool risk classification: Safe (Read/Glob/Grep), NeedsGovernance (Write/Edit/Bash/Unknown)
- Governance middleware that wraps the stream — each event evaluated inline
- Provenance recording with Ed25519 signed records
- Merkle DAG for causal history with multi-parent support (parallel agent convergence)
- DAG verification (detect tampering, missing parents)
- Vault: credential management with scoped tokens, approval workflows
- Worktree isolation per agent with conflict detection
- Quality gates tied to complexity levels
- Commit manifest enforcement

### 3.3 UIA Orchestrator (new — port from Rust)

The Unified Intelligence Architecture — classifies, decomposes, and dispatches complex tasks.

**Components:**
- **Classifier**: Categorize prompt complexity (Trivial/Simple/Medium/Complex/Critical) with
  associated token budgets (5K–150K) and timeouts (30s–15min)
- **Decomposer**: Break complex prompts into leaf tasks. Two modes:
  - LLM-assisted (via local model or cloud)
  - Rule-based fallback
- **TaskGraph**: DAG of task nodes with:
  - Kahn's algorithm topological sort into parallel execution layers
  - Dependencies from explicit `blocked_by`, file overlap heuristics, trait ordering
  - Mark completed/failed with BFS failure cascade
- **Scorer**: 12 TaskTrait categories × engine capabilities. EMA-weighted scoring.
  TraitSelector picks best engine per sub-task.
- **Dispatcher**: Ready tasks from graph → selected engines

### 3.4 HITL System (new)

Human In The Loop interception and approval.

**From Rust TUI impl:**
- Interception modal with Allow/Deny/Steer options
- 60-second auto-deny countdown (configurable)
- Severity-based flagging
- Steer option: user provides text directive to redirect agent

**macOS Native additions:**
- Notification Center integration for critical interceptions
- Breakout window for HITL feed
- Batch approve/deny for related tool calls
- Time-delay interception: all calls held for N seconds (configurable) with intercept button
  that disappears once dispatched
- Related calls flagged when one is intercepted

### 3.5 Dashboard System (new)

User-configurable dashboard panels, inspired by the Rust TUI's multiple panes.

**Panel types:**
- Agent Activity Feed — streaming log of all agent actions with risk indicators
- Task DAG Viewer — interactive graph visualization of decomposed tasks
- Governance Events — real-time decision log with filtering
- Diff Viewer — side-by-side file comparison
- Worktree Status — git worktree list with per-agent isolation
- File Change Feed — all files modified across all agents
- Merkle DSG Log — provenance chain with optional cloud attestation
- Services Monitor — MLX server + Interposer health and traffic

**Dashboard configuration:**
- Sidebar entries are user-configurable
- Each panel can break out into its own window
- Layouts save/restore per-workspace
- Multiple dashboards can be active simultaneously

### 3.6 UIA Chat Interface (new)

A chatbot interface for the UIA orchestrator.

**Features:**
- Chat with the UIA to decompose and manage tasks
- Inline DAG visualization of task hierarchy
- Explanation of how to read the graph
- Approval/rejection of decomposed task lists with configurable timeout
- Task status updates in real-time
- Direct agent steering from chat

### 3.7 Services View (consolidation)

Merge current Server + Interposer panels into unified "Services" view.

**Components:**
- MLX Server status, model, config, and log
- Interposer status, traffic log, and route visualization
- Dependency health checks (python, mlx-lm, runners)
- One-click start/stop/restart for all services

## 4. Settings System

On par with iTerm2's settings architecture.

### 4.1 Theme Engine
- JSON-based theme definitions
- Synthaer.ai Indigo Cream as default
- Support for light/dark/custom themes
- Per-component color overrides
- Font family and size preferences (minimum 12pt enforced)
- Dynamic Type / accessibility scaling

### 4.2 Configuration Layers
```
Defaults (built-in)
  └─ User Settings (~/.config/mlx-launcher/settings.json)
      └─ Workspace Settings (.engrave/settings.json)
          └─ Runtime Overrides (env vars, CLI flags)
```

### 4.3 Settings Categories
- **General**: Default working directory, startup behavior, update checks
- **Appearance**: Theme, font, layout preferences
- **Models**: Scan directories, cloud model catalog, default profiles
- **Runners**: Per-runner configuration, flags, working directories
- **Services**: MLX server port/args, interposer port/routes, auto-start
- **Governance**: Default policy, sandbox level, circuit breaker thresholds
- **UIA**: Orchestrator model, cheap/local model, decomposition preferences
- **Dashboards**: Panel layout, breakout window preferences
- **Keys**: API keys, credential vault
- **Advanced**: Debug logging, experimental features

## 5. Governance Rule Editor

### 5.1 Rule Viewing
- Each built-in rule has a full description, example triggers, and expected behavior
- Rules show their regex patterns, conditions, and actions in a readable format
- Severity indicators with color coding

### 5.2 Rule Editing
- Inline regex builder with test input and live match preview
- Variable name autocomplete for conditions (request.model, request.temperature, etc.)
- Comparator picker (==, !=, >, <, contains, matches)
- Action configuration: clamp values, inject system messages, rewrite, shell script, circuit break
- Severity selector with descriptions of each level's behavior

### 5.3 Rule Management
- Duplicate any rule as starting point
- Reset built-in rules to defaults
- Create rules from templates
- Import/export rules as TOML or JSON

### 5.4 Governance Wizard
For users who don't know regex or variable names:
- Step-by-step rule builder
- Natural language description → rule generation
- "When [trigger] and [condition], then [action] with severity [level]"
- Preview of generated rule before saving

### 5.5 Sandbox Level Details
Each level gets a full description panel:
- **Jailed**: All tool execution blocked. Agent can only respond with text. No file reads, no commands, no network. Use for: untrusted models, sensitive conversations.
- **Sandbox**: Read-only tools allowed (Read, Glob, Grep, LSP). No writes, no commands. Use for: code review, exploration, Q&A.
- **Workspace**: Read-write within project directory. Bash restricted to safe commands. No system-wide access. Use for: standard development, feature work.
- **Full**: Unrestricted access. All tools available. Use for: trusted models, admin tasks. Risk: agent can modify system files, install packages, access network.

## 6. Context Exhaustion Relay

Three configurable thresholds per agent type:
- **Warning (50%)**: Log event, inject system hint to be concise
- **Handoff (80%)**: Generate context brief, prepare handoff payload
- **Critical (90%)**: Force-finalize agent, spawn continuation with handoff brief

The relay agent (local/cheap model) compacts the context into a structured brief containing:
- Task summary and progress
- Key decisions made
- Remaining work
- File state snapshot
- Active constraints

## 7. Merkle DSG & Attestation

Every governance decision produces a signed provenance record:
```
SignedProvenanceRecord {
    id: UUID
    sequence: u64
    session_id: String
    timestamp: ISO8601
    event_type: String
    details: JSON
    actor: String (agent/model/user)
    content_hash: SHA256
    causal_parents: [UUID]  // DAG structure
    prev_hash: SHA256       // Linear chain (compat)
    signature: Ed25519
}
```

**Local signing**: Ed25519 keypair generated on first run, stored in keychain.
**Cloud attestation**: Optional upload to Synthaer.ai for timestamped third-party verification.
**Verification**: DAG traversal detects tampered nodes and missing parents.
**Export**: JSON or binary proof bundles for audit trails.

## 8. Migration from Current State

### Phase 1: Production-Ready MLXLauncher (current)
- [x] Fix crash bugs (AsyncPublisher, Task.detached)
- [x] Fix MLX server startup (python discovery, dependency install)
- [x] Add cloud models, system prompts, generation profiles
- [x] Synthaer.ai theme, accessibility fonts
- [x] Fix runner launch (bash script, shell-agnostic)
- [x] Fix all P0/P1 audit issues

### Phase 2: Services & Settings Foundation
- [ ] Merge Server + Interposer into Services view
- [ ] Settings system with JSON persistence
- [ ] Theme engine with Synthaer defaults
- [ ] Breakout window support for any panel

### Phase 3: Governance Editor & Wizard
- [ ] Full rule editor with regex builder
- [ ] Governance wizard for non-technical users
- [ ] Sandbox level detail panels
- [ ] Rule import/export

### Phase 4: UIA & HITL
- [ ] Port UIA classifier, decomposer, task graph from Rust
- [ ] UIA chat interface
- [ ] DAG visualization
- [ ] HITL interception feed with time-delay dispatch
- [ ] Notification Center integration

### Phase 5: Dashboards & Observability
- [ ] Configurable dashboard panels
- [ ] Agent activity feed
- [ ] Diff viewer
- [ ] Worktree status
- [ ] Merkle DSG log with local signing
- [ ] Optional Synthaer.ai cloud attestation

## 9. Key Design Principles

1. **The Rust engine is canonical.** The Swift app consumes its capabilities, it does not
   re-implement them. Where the Swift interposer exists for in-process performance, it
   must maintain protocol parity with the Rust version.

2. **Every governance decision is observable.** No silent policy application. Users must be
   able to see what was evaluated, what the decision was, and why.

3. **Breakout everything.** Any panel can become its own window. Multi-monitor workflows
   are first-class.

4. **Accessibility is not optional.** Minimum 12pt fonts, system Dynamic Type scaling,
   high-contrast Synthaer theme defaults, full keyboard navigation.

5. **Configuration is layered.** Defaults → User → Workspace → Runtime. Each layer is
   inspectable and overridable.

6. **The UIA explains itself.** Task decomposition is visible, editable, and approvable.
   The user always knows what the system is about to do.

7. **HITL is the safety net.** Critical operations are held until human approval. The
   timeout is configurable. The intercept window is always visible.

---

*This document serves as the architectural specification for building out the full
Engrave macOS Native platform. Each phase should be implemented with its own prompt
novel that references this master document for context.*
