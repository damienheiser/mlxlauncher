I just open-sourced a governance engine for AI agents.

If you're running AI coding assistants like Claude Code or Codex on your machine, those agents can execute bash commands, write files, and access your filesystem. That's powerful, but it's also a lot of trust.

Engrave is a set of Swift libraries that give you control:

- **Policy rules** that block dangerous operations before they execute (regex pattern matching on tool calls, configurable severity levels)
- **Sandbox enforcement** with four tiers from "jailed" (nothing runs) to "full" (unrestricted)
- **Tool interception** that classifies every tool call by risk level
- **Condition evaluation** so rules can reference session state like token budgets

I also built an API translation proxy that lets any AI assistant work with any model backend. Claude Code talks Anthropic API, your local MLX model talks OpenAI Chat Completions. The proxy handles the translation, including streaming and tool calls.

And there's a macOS app (MLX Launcher) that ties it all together: model discovery, server management, one-click runner launch, and the governance engine wired into the UI.

All MIT licensed, pure Swift, no external dependencies.

First release. Lots more coming.

Links:
- https://github.com/damienheiser/mlxlauncher
- https://github.com/damienheiser/libengrave-ai-interposer-swift
- https://github.com/damienheiser/libengrave-ai-governance-swift
