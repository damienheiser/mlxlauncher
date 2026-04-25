# HeM → Engrave Priority Three Governance Notes — April 25, 2026

## Sources Reviewed

- `/Users/hedon/Augments/TheUserInterfacingAgent/PROMPT_NOVEL.md`
- `/Users/hedon/Augments/GovernanceFrameworkREFERENCE/docs/ENGINE-TIERS.md`
- `/Users/hedon/Augments/ABrandNewSynthaer/CLAUDE.md`
- `/Users/hedon/Augments/ABrandNewSynthaer/TASKS.md`

## Moved Into Engrave / MLX Launcher

- **Sub-Agent Launch Control**: packaged request rule plus generated runner policy requiring all spawned agents and model traffic to stay on the Engrave interposer path; runner metadata now marks all configured runners as proxy-governed.
- **Context Exhaustion Relay**: persisted per-agent context budgets with thresholds and relay model hints; generated policy instructs local/cheap agents to compact context into handoff briefs.
- **Human In The Loop Interception**: packaged rule and UI toggle for incoming/outgoing message hold/rewrite behavior.
- **Engrave UIA**: persisted UIA governance config for prompt decomposition, workflow DAG creation, sub-agent steering, and user-facing work narration.
- **Workflow Task DAG**: packaged rule and generated policy guidance for dependency-aware task DAGs.
- **Git Commit Hygiene**: packaged rule and generated `pre-commit` hook warning on broad/risky commits and missing tests.
- **Git Worktree Hygiene**: packaged rule and generated `session-close-check` hook that fails if the worktree has uncommitted changes at close.
- **TDD**: packaged rule and generated hook warning when source changes are staged without tests.
- **No Undocumented Mocks Or Stubs**: packaged response rule and generated hook warning on mocks, stubs, scaffolds, placeholders, TODOs, and fakes.

## Deliberately Left As Policy/Artifacts For Now

- Full sub-agent process supervision is represented as generated runner policy and Engrave network governance. Native per-tool lifecycle hooks differ by runner and require deeper runner-specific adapters.
- Human message rewriting is represented as policy and rule toggles. A full hold/rewrite queue needs a message broker UI and durable queue semantics.
- Automatic context compaction is represented as budget config and policy. Actual compaction requires runner adapters that can snapshot conversation state and spawn a replacement session.
- Workflow DAG editing is represented as UIA policy and rule config. A graphical editable DAG is a larger UI feature.

## Generated Files

When governance is saved, MLX Launcher writes:

- `~/.config/mlx-launcher/governance/engrave-governance-brief.md`
- `~/.config/mlx-launcher/governance/gemini-policy.md`
- `~/.config/mlx-launcher/governance/hooks/pre-commit`
- `~/.config/mlx-launcher/governance/hooks/session-close-check`

These artifacts give Claude, Codex, Gemini, Aider, and gptme launches a shared governance contract while their model requests remain routed through Engrave.
