Just shipped three open-source Swift libraries and a macOS app that solve a problem I've been dealing with for months.

**The problem:** Every AI coding assistant speaks a different API. Claude Code uses Anthropic's Messages API. Codex uses OpenAI Chat Completions. Gemini CLI uses Google's format. If you're running a local model on Apple Silicon with MLX, you need a translation layer. And if you're letting AI agents run tools on your machine, you need guardrails.

**What I built:**

**MLX Launcher** - A native macOS app that discovers your local MLX models, manages the inference server, and launches any AI coding assistant (Claude Code, Codex, Gemini CLI, Aider, gptme) with a single click. No config files, no environment variable juggling.

**Engrave Interposer** (`libengrave-ai-interposer-swift`) - A Swift library that translates between Anthropic, OpenAI, and Gemini APIs in real time, including full streaming SSE translation with tool call mapping. One port, any client, any backend.

**Engrave Governance Engine** (`libengrave-ai-governance-swift`) - This is the one I'm most excited about. It's a policy engine that sits in the request path and evaluates every request, every tool call, and every streaming response against declarative rules. Sandbox levels control what tools can do. Regex pattern matching catches dangerous operations before they execute. A full condition evaluator lets you write rules like `tokens_used > budget * 0.8 && sandbox_level != "full"`.

Everything is native Swift, zero external dependencies, built on Foundation and Network frameworks. The libraries are MIT licensed. The interposer has been tested end-to-end: Anthropic Messages API request goes in, gets translated through a canonical intermediate representation, forwarded to an MLX backend as Chat Completions, and the streaming response comes back translated into proper Anthropic SSE events.

This is the first public release of the Engrave governance engine. I've been running a Rust version of the interposer internally for a while, but the Swift rewrite is cleaner, faster to build on, and designed from the start to be embeddable.

Links:
- https://github.com/damienheiser/mlxlauncher
- https://github.com/damienheiser/libengrave-ai-interposer-swift
- https://github.com/damienheiser/libengrave-ai-governance-swift
