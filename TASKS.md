# TASKS.md -- mlxLauncher

## Governance Rules

1. **All work must be authorized by a task in this file.** Work without a task reference is unauthorized and constitutes a governance violation.
2. **Tasks are created before work begins.** A task describes intent. Provenance records describe action. Comparing the two is how governance failures are detected.
3. **Every commit must reference a task.** Commit messages include the task ID (e.g., `T-001`) that authorized the work.
4. **Tasks are append-only until completed.** A task can be updated with status changes and notes, but its original description is never rewritten.
5. **Completed tasks are not deleted.** They are marked complete with a completion date and moved to the Completed section. The full history remains.
6. **Governance violations trigger a Five Whys analysis.** Missing task references, orphaned commits, and untracked work are investigated for root cause.

## Task ID Format

- Format: `T-{sequential number}` (e.g., T-001, T-002)
- Each task has: ID, description, status, created date, assignee, and task reference in commits

---

## Active Tasks

### T-001 | Model Weight Validation Before Server Launch
- **Description**: Before launching mlx_lm.server, validate that the model directory contains at least one .safetensors or .gguf file. If missing, set server status to .error with clear message instead of silent hang. Already fixed in Services.swift but needs test coverage.
- **Created**: 2026-04-27
- **Status**: Open
- **Severity**: High
- **Assignee**: Unassigned

### T-002 | Chat Completions SSE Parser: Synthesize MessageStart on Missing Role
- **Description**: Some OpenAI-compatible backends (notably mlx_lm.server) skip the role field in the first SSE chunk. The StreamTranslator must synthesize a MessageStart event when it first sees content delta without a prior role announcement. Without this, downstream consumers never see message start.
- **Created**: 2026-04-27
- **Status**: Open
- **Severity**: Medium
- **Assignee**: Unassigned

### T-003 | CLI Subscription Auth Mode — Don't Force Proxy for Native Auth
- **Description**: Users with Claude Pro/Max subscriptions use native OAuth. Forcing ANTHROPIC_BASE_URL breaks that flow. The launch path needs a way to signal "use native auth, do not inject provider URL envs" when the runner has its own subscription.
- **Created**: 2026-04-27
- **Status**: Open
- **Severity**: Medium
- **Assignee**: Unassigned

### T-004 | Governance Artifact Parity with Rust
- **Description**: Compare generated hook scripts (pre-commit, session-close) with Rust's shell_integration.rs output. Ensure strict/standard/minimal presets produce behaviorally equivalent hooks.
- **Created**: 2026-04-27
- **Status**: Open
- **Severity**: Medium
- **Assignee**: Unassigned

### T-005 | Dynamic Model Fetching from Provider APIs
- **Description**: When API keys are set, query live /v1/models endpoints to populate available models. Already implemented in Types.swift but needs refresh/caching strategy.
- **Created**: 2026-04-27
- **Status**: Open
- **Severity**: Low
- **Assignee**: Unassigned

### T-006 | ERL Parser Support
- **Description**: When Rust implements the Engrave Rule Language (.engram files), the Swift EngraveAIGovernance library needs a matching parser so governance policies are portable across platforms. Track Rust ERL implementation progress.
- **Created**: 2026-04-27
- **Status**: Open
- **Severity**: Medium
- **Assignee**: Unassigned

### T-007 | Library Extraction — EngraveAIGovernance and EngraveAIInterposer
- **Description**: Extract Engrave/Sources/EngraveGovernance/ into libengrave-ai-governance-swift repo and Engrave/Sources/EngraveInterposer/ into libengrave-ai-interposer-swift repo. Update Package.swift to depend on external packages. See AgentInterposer/private/docs/engrave-ecosystem-audit-april-27-2026.md for full extraction plan.
- **Created**: 2026-04-27
- **Status**: Open
- **Severity**: Medium
- **Assignee**: Unassigned

### T-008 | Vocabulary Phase 1 — Engrave Naming in UI
- **Description**: Update SwiftUI labels to use Engrave vocabulary: "Governance" → "Engrams", "Provenance" → "Evidence", sidebar tabs, panel titles. Per canon A6 in AgentInterposer/docs/spec/A6-appendix-engrave-vocabulary.md.
- **Created**: 2026-04-27
- **Status**: Open
- **Severity**: Low
- **Assignee**: Unassigned

---

## Completed Tasks

(none yet)
