# gemini-plugin

A Claude Code plugin that makes Google Gemini your second-opinion assistant: validating plans, challenging destructive operations, grounding prompts in live web data, and auditing "done" claims to reduce hallucination and repeated work.

Built on [gemini-mcp](https://github.com/azmym/gemini-mcp) (13 MCP tools covering text, images, video, music, TTS, deep research, code execution, and search-grounded answers).

## Install

Distributed via the [SynthForge marketplace](https://github.com/azmym/SynthForge):

```bash
/plugin marketplace add azmym/SynthForge
/plugin install gemini-plugin@synthforge
```

During installation, Claude Code prompts you for your Google AI Studio API key. The key is stored securely in your system keychain (not in plain text). Get a key at [aistudio.google.com/app/apikey](https://aistudio.google.com/app/apikey).

The plugin auto-registers the `gemini` MCP server. No separate `claude mcp add` or `export` step needed.

## What you get

| Component | Count | Purpose |
|---|---|---|
| Skills | 8 | Task-oriented guidance for when/how to use Gemini capabilities |
| Subagents | 4 | Validator, Challenger, Researcher, Summarizer |
| Slash commands | 5 | Manual invocation + brainstorm toggle |
| Hooks | 7 | 6 auto-triggers + 1 verdict handler |
| Rules | 1 | Session-level guidance on when to (not) call Gemini |

## Auto-triggers (hooks)

| Event | What happens |
|---|---|
| Session start | Builds a risk map of the repo (cached 24h) |
| User prompt (gated) | Grounds post-cutoff questions via Gemini search (always-on during brainstorming) |
| Plan complete | Validates the plan for gaps and hallucinations |
| Destructive Bash command | Challenges the command; proposes safer alternatives |
| Pre-compact | Summarizes session state to survive context compaction |
| Stop ("done" claim) | Validates the output against the original ask |

All hooks block (exit 2) when Gemini finds issues. You see the critique inline and must address it before continuing.

## Subagents

| Agent | Role | Model | Color |
|---|---|---|---|
| gemini-validator | Validates plans/diffs/claims | Haiku | Blue |
| gemini-challenger | Devil's advocate | Sonnet | Red |
| gemini-researcher | Live-web grounding | Haiku | Green |
| gemini-summarizer | Session compression | Sonnet | Purple |

Invoke manually: `@agent-gemini-plugin:gemini-validator`, or via slash commands.

## Slash commands

| Command | What it does |
|---|---|
| `/gemini-plugin:gemini-validate <subject>` | Ad-hoc validation of any artifact |
| `/gemini-plugin:gemini-challenge <topic>` | Devil's advocate on any decision |
| `/gemini-plugin:gemini-research <query> [--deep]` | Grounded research (--deep for synthesis) |
| `/gemini-plugin:gemini-brainstorm-on` | Enable unconditional grounding |
| `/gemini-plugin:gemini-brainstorm-off` | Return to keyword-gated grounding |

## Disable features

| What | How |
|---|---|
| All hooks | `export CLAUDE_PLUGIN_GEMINI_DISABLE_HOOKS=1` |
| Specific agent | Add `Agent(gemini-plugin:gemini-challenger)` to `permissions.deny` in settings |
| Brainstorm mode | `/gemini-plugin:gemini-brainstorm-off` |

## Requirements

- Claude Code with plugin support
- A Google AI Studio API key (prompted during install, stored in system keychain)
- `uvx` (installed with `uv`; the MCP server is fetched automatically)
- `jq` (used by hook scripts to parse JSON)

## License

MIT
