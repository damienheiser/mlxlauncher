# Appendix A6: Engrave Vocabulary — Canon

**Version:** 1.0.0
**Status:** CANON — ratified by operator review, April 25 2026
**Inputs:** `engrave-vocabulary-alignment.md`, `vocabulary.md`, Rust feedback (agent session), MLX feedback (agent session), operator decisions
**Scope:** All Engrave codebases (Rust, Swift, future SDKs), CLI, TUI, API, logs, documentation, DSL

---

## 1. Core Vocabulary (8 Terms)

These are the canonical Engrave product terms. Use them in all user-facing surfaces: CLI output, TUI labels, API responses, log events, documentation, and config files.

| Term | Definition | Replaces | Permanence |
|------|-----------|----------|------------|
| **Engram** | An immutable unit of governance logic. A named collection of rules loaded from `.engram` or TOML files. | Governance Policy, DeclarativePolicy | Permanent — the atom of governance |
| **Enclave** | The protected, governed runtime boundary for an agent session. Everything inside an enclave is examined, recorded, and enveloped. | Governance Context, GovernanceContext | Permanent — the scope of governance |
| **Envelope** | The protective layer surrounding a request or agent process. Envelopes filter environment, restrict tool access, and enforce sandbox levels. | Sandbox, SandboxEnforcer (user-facing only) | Permanent — what wraps agents |
| **Engraving** | A signed, cryptographically verified record of a governance evaluation. Engravings are permanent and immutable — they cannot be appealed, overturned, or deleted. | Policy Decision, PolicyDecision, ProvenanceRecord | Permanent — the audit atom |
| **Evidence** | The tamper-evident, hash-linked DAG of all engravings. Evidence is structured as a Merkle DAG with causal parents, not a linear chain. | Provenance, Event Log, ProvenanceChain | Permanent — the audit structure |
| **Examination** | The process of evaluating an action against the loaded engrams. An examination produces an engraving. | Policy Evaluation, governance evaluate | Permanent — the governance verb |
| **Entitlement** | A specific capability or resource access granted to an agent within an enclave. Entitlements are scoped, revocable, and recorded. | Permission, Grant, SandboxLevel (user-facing only) | Permanent — the permission model |
| **Embargo** | A hard-block state triggered when a circuit breaker trips or a critical safety threshold is exceeded. All agent activity within the enclave is halted until the embargo is lifted. | Circuit Breaker Trip | Permanent — the safety stop |

### Operator Decisions

- **Engraving** stays. Both feedback sessions considered alternatives (Verdict, Decision). Engravings are permanent and immutable — that permanence is the feature, not a quirk.
- **Entitlement** stays. Apple/AWS collision was considered and dismissed — different domain, no confusion in practice. Alliterative consistency matters for brand coherence.
- **Embargo** replaces "Enragement." Enragement is fun for internal culture but toxic in compliance audits, incident reports, and customer-facing logs. Embargo conveys the same hard-block semantics without anthropomorphizing the safety system.

---

## 2. Vocabulary Grammar

Engrave terms follow four patterns. Use the correct pattern for the context.

| Pattern | Meaning | Example |
|---------|---------|---------|
| **verb + engrave** | User/operator action | `engage engrave`, `examine engrave` |
| **engrave + state** | System condition | `engrave engaged`, `engrave embargoed` |
| **engrave + object** | Internal component | `engrave enclave`, `engrave envelope` |
| **engrave + modifier** | Mode or behavior | `engrave explicit`, `engrave elastic` |

---

## 3. CLI Aliases

These 6 aliases ship immediately alongside existing commands. They are permanent — the underlying commands they alias are not deprecated.

| Alias | Maps To | Meaning |
|-------|---------|---------|
| `engrave engage` | `engrave start` | Initialize the governed proxy |
| `engrave examine` | `engrave governance status` | Inspect enclave state and health |
| `engrave engram` | `engrave governance rules` | List and manage loaded engrams |
| `engrave evidence` | `engrave provenance` | Inspect and verify the evidence DAG |
| `engrave envelope` | `engrave governance sandbox` | Inspect agent envelope configuration |
| `engrave enclave` | `engrave status` | Show governed runtime state |

The original commands (`start`, `governance`, `provenance`, etc.) remain as permanent alternatives. They are not deprecated — they honor the lineage and provide clarity for developers who think in infrastructure terms rather than product terms.

---

## 4. Engrave Rule Language (ERL)

The ERL is the canonical policy DSL. Files use the `.engram` extension. TOML-based rules (`rules.toml`, `[governance]` config sections) remain permanently supported — both formats are first-class.

### 4.1 File Structure

```
.engrave/
  config.toml              # accepts both [governance] and [engrams] sections
  policies/
    default.engram          # ERL format
    strict.engram
    local-only.engram
  rules.toml                # TOML format (permanent, not deprecated)
```

### 4.2 Syntax

```erl
engram "default-governance" {
    version = "1.0"
    mode = enforce

    applies_to {
        runners = ["claude-code", "codex", "gemini"]
        engines = ["ollama/*", "lmstudio/*", "vllm/*"]
        scopes  = ["project", "worktree", "vault", "git", "ssh"]
    }

    rule "deny-secret-exfiltration" {
        when request.contains_secret == true
        then deny "Secret material may not leave the enclave"
        severity = deny
    }

    rule "protect-main-branch" {
        when git.branch == "main" and action in ["commit", "push"]
        then deny "Direct mutation of main is blocked"
    }

    rule "require-evidence" {
        when task.kind in ["write_file", "run_command", "git_commit"]
        then require evidence.signed == true
    }

    rule "steer-to-local" {
        when engine.location == "remote" and risk.score < 0.3
        then rewrite request.model = "ollama/qwen3.5"
    }

    rule "review-destructive" {
        when request.command.matches("rm -rf *")
        then hold until approval.human == true
    }
}
```

### 4.3 Actions

| Action | Meaning |
|--------|---------|
| `allow` | Permit the action |
| `deny "reason"` | Block the action with a recorded reason |
| `warn "reason"` | Permit but flag for review |
| `require condition` | Block until condition is met |
| `hold until condition` | Pause execution (human-in-the-loop) |
| `rewrite field = value` | Silently modify the request (model steering, token clamping) |
| `relay agent = "x"` | Hand off to a different agent (context exhaustion) |
| `redact target` | Strip sensitive content from request/response |
| `route engine = "x"` | Redirect to a different backend |
| `limit field = value` | Constrain a numeric field (max_tokens, temperature) |
| `emit "event.name"` | Fire a custom evidence event |
| `break circuit "name"` | Trip a specific circuit breaker (trigger embargo) |
| `pause task` | Pause the current task |
| `quarantine agent` | Isolate the agent from shared resources |

### 4.4 Conditions

```erl
# Request attributes
when request.contains_secret == true
when request.model == "claude-opus-4-20250514"
when request.tokens > 50000
when request.diff.touches("crates/engrave-governance/**")
when request.command.matches("rm -rf *")

# Agent attributes
when agent.runner == "claude-code"
when agent.depth > 2                          # sub-agent nesting
when agent.parent.runner == "codex"
when agent.budget.tokens_remaining < 10000    # context exhaustion
when agent.task.tier == 3

# Environment
when engine.location == "remote"
when engine.location == "local"
when git.branch == "main"
when file.path.matches("**/.env")
when vault.secret.scope != task.scope

# State
when evidence.chain.valid == false
when risk.score > 0.75
when enclave.embargo == true
```

### 4.5 Config Key Compatibility

The TOML config parser accepts both `[governance]` and `[engrams]` as section keys. They are semantically identical. Neither is deprecated — `[governance]` honors the implementation lineage, `[engrams]` aligns with the product vocabulary.

```toml
# Both of these are permanently valid:

[governance]
profile = "standard"
rules_path = ".engrave/rules.toml"

[engrams]
profile = "standard"
rules_path = ".engrave/policies/default.engram"
```

---

## 5. Log Taxonomy

All structured events follow `domain.action.outcome`. Domains align with the Engrave vocabulary.

### 5.1 Domains

```
enclave.session.started
enclave.session.ended
enclave.health.graded

engram.rule.loaded
engram.rule.matched
engram.rule.unmatched

engraving.examination.allowed
engraving.examination.denied
engraving.examination.steered
engraving.signed
engraving.cosigned                 # Synthaer co-signature

evidence.dag.appended
evidence.dag.branched
evidence.dag.merged
evidence.dag.verified

envelope.agent.wrapped
envelope.agent.unwrapped
envelope.sandbox.applied

embargo.breaker.tripped
embargo.breaker.reset
embargo.scope.activated

proxy.request.received
proxy.request.translated
proxy.response.translated
proxy.stream.started
proxy.stream.chunk
proxy.stream.completed

agent.task.spawned
agent.task.paused
agent.task.resumed
agent.task.completed
agent.task.failed
agent.context.exhaustion
agent.context.relay

runner.launch.started
runner.launch.ready
runner.launch.failed

vault.secret.requested
vault.secret.checked_out
vault.secret.denied
vault.secret.rotated

git.commit.validated
git.branch.validated
git.push.denied
```

### 5.2 Severity Levels

```
TRACE    protocol/frame/internal detail
DEBUG    diagnostic detail
INFO     normal lifecycle event
NOTICE   governance-relevant but benign
STEER    governance silently modified request (model steering, rewrite, relay)
WARN     suspicious / degraded / policy near-miss
DENY     governance blocked action
ERROR    failed operation
FATAL    unsafe/unrecoverable condition
AUDIT    immutable evidence-worthy event (always recorded regardless of level)
```

`STEER` is a governance-specific severity between NOTICE and WARN. It means: "governance altered the request without blocking it." The agent may not be aware of the change. The evidence trail always records it.

---

## 6. Enclave Levels (Envelope Configuration)

5 levels, replacing the HeM 9-level system:

| Level | Name | Description |
|-------|------|-------------|
| 0 | **Locked** | No tool execution. Read-only inspection only. |
| 1 | **Sandboxed** | Read-only tools. No writes, no network, no git. |
| 2 | **Workspace** | Read-write within project directory. No system access. |
| 3 | **Extended** | Project + approved external tools. Network for approved APIs. |
| 4 | **Full** | Full system access. Use with explicit trust only. |

---

## 7. API Surface

### 7.1 Resource Naming

Public API uses conventional REST nouns. Engrave vocabulary appears in documentation and response bodies, not URL paths.

```
/api/v1/sessions          # enclave sessions
/api/v1/agents            # enrolled agents
/api/v1/tasks             # orchestrated tasks
/api/v1/policies          # loaded engrams
/api/v1/rules             # rules within engrams
/api/v1/decisions         # engravings (examination results)
/api/v1/events            # evidence entries
/api/v1/provenance        # evidence DAG operations
/api/v1/violations        # embargo triggers
/api/v1/worktrees         # agent worktrees
/api/v1/vault/secrets     # vault operations
/api/v1/fleet             # fleet management
/api/v1/models            # available models (local + cloud)
```

### 7.2 Key Operations

```
POST   /api/v1/sessions                        # create enclave session
GET    /api/v1/sessions/{id}                    # inspect enclave

POST   /api/v1/tasks                            # launch orchestrated task
POST   /api/v1/tasks/{id}/pause                 # pause task
POST   /api/v1/tasks/{id}/resume                # resume task
POST   /api/v1/tasks/{id}/cancel                # cancel task

GET    /api/v1/policies                         # list loaded engrams
POST   /api/v1/policies                         # load new engram
POST   /api/v1/policies/{id}/evaluate           # dry-run examination

GET    /api/v1/provenance/dag                   # evidence DAG structure
POST   /api/v1/provenance/verify                # verify evidence integrity
POST   /api/v1/provenance/export                # export evidence bundle

POST   /api/v1/agents/{id}/subagent             # spawn governed sub-agent
GET    /api/v1/models                           # list available models
POST   /api/v1/models/{id}/serve                # start serving local model
```

---

## 8. Implementation Phases

### Phase 1: Surface Rename (CLI + TUI + Logs) — Ship Now
- Add 6 CLI aliases (engage, examine, engram, evidence, envelope, enclave)
- Update TUI sidebar tabs: "Governance" → "Engrams", "Provenance" → "Evidence"
- Update TUI HITL modal title: "GOVERNANCE INTERCEPTION" → "GOVERNANCE EXAMINATION"
- Add `STEER` severity level to event logging
- Update `engrave --help` descriptions to use Engrave vocabulary
- Accept both `[governance]` and `[engrams]` in config TOML

### Phase 2: ERL Parser + Evidence DAG — Ship Next
- Implement ERL parser for `.engram` policy files
- Support `rewrite`, `relay`, `hold` actions
- Support sub-agent conditions (`agent.depth`, `agent.parent.runner`, `agent.budget`)
- Rename provenance viewer to "Evidence DAG" in TUI
- Update evidence visualization from chain to DAG

### Phase 3: Core Type Renames — Ship When Stable
- Rename product-boundary types with `pub type` backward-compat aliases:
  - `DeclarativePolicy` → `Engram`
  - `GovernanceContext` → `EnclaveContext`
  - `PolicyDecision` → `Engraving`
  - `GovernanceEvent` → `EvidenceEvent`
  - `ProvenanceRecord` → `EvidenceRecord`
  - `GovernanceProfile` → `EnclaveProfile`
- Internal plumbing types remain unchanged (GovernanceMiddleware, SandboxEnforcer, MerkleNode, CircuitBreaker)

### Phase 4: Crate Rename — Ship at 1.0
- `interposer-core` → `engrave-core`
- `interposer-cli` → `engrave-cli`
- `interposer-governance` → `engrave-enclave`
- Binary name stays `engrave` (already correct)

---

## 9. Terms Explicitly Rejected

These appeared in the vocabulary brainstorm but are not part of the Engrave canon:

| Term | Reason for Rejection |
|------|---------------------|
| **Enragement** | Anthropomorphizes the safety system. Unprofessional in incident reports and compliance audits. Replaced by **Embargo**. |
| **Entombed** | "Your agent is entombed" — hostile. Use "locked" or "frozen." |
| **Ensnared** | Makes governance sound adversarial. Governance is protective, not punitive. |
| **Engulfed** | "System engulfed by governance" — governance should feel lightweight. |
| **Enthroned** | Excessive. Use "elevated" or "promoted." |
| **Eclipsed** | Overloaded (astronomy, IDE). Use "overridden." |
| **Verdict** | Considered for Engraving. Rejected: verdicts can be appealed. Engravings cannot. |
| **Grant** | Considered for Entitlement. Rejected: equally overloaded (SQL, OAuth). Entitlement has alliterative consistency. |
| HeM energy terms (Verve, Gumption, Patina, Elan) | HeM-specific. Don't fit Engrave's identity. |

---

## 10. Lineage Acknowledgment

The `[governance]` config key, `governance` CLI subcommand, and `provenance` CLI subcommand remain as permanent, first-class alternatives to their Engrave-vocabulary equivalents. They are not deprecated. They honor the implementation lineage from the interposer proxy through the governance engine to the Engrave product, and they provide clarity for infrastructure engineers who think in systems terms.

Engrave's vocabulary is a product layer over a governance engine. The engine doesn't pretend it isn't an engine.
