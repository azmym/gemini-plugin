# gemini-plugin Documentation

A Claude Code plugin that turns Google Gemini into a second-opinion assistant layer. It validates plans, challenges destructive operations, grounds prompts in live web data, and audits completion claims.

## Quick navigation

| Section | What you'll find |
|---|---|
| [Tutorial](tutorial.md) | Install the plugin and run your first validation in under 5 minutes |
| **How-to guides** | |
| [Validate plans and claims](how-to/validate-plans.md) | Use Gemini to catch gaps in plans and "done" claims |
| [Research live data](how-to/research-live-data.md) | Ground questions in current web data with citations |
| [Configure hooks](how-to/configure-hooks.md) | Enable, disable, or customize the automatic triggers |
| **Reference** | |
| [Architecture](reference/architecture.md) | System architecture, data flow, and component diagram |
| [Skills](reference/skills.md) | All 9 skills with descriptions and MCP tool mappings |
| [Subagents](reference/subagents.md) | All 5 subagents with frontmatter, tools, and output schemas |
| [Hooks](reference/hooks.md) | All 7 hooks with event types, gates, and exit behavior |
| [Commands](reference/commands.md) | All 6 slash commands with usage examples |
| **Explanation** | |
| [Design decisions](explanation/design-decisions.md) | Why single-turn validation, why these gates, cost tradeoffs |

## At a glance

```
Plugin installs via marketplace
         |
         v
┌─────────────────────────────────────────────┐
│ gemini-plugin                               │
│                                             │
│  9 skills    - when/how to use Gemini       │
│  5 subagents - validator, challenger,       │
│                researcher, summarizer,      │
│                reviewer                     │
│  7 hooks     - auto-trigger on key events   │
│  6 commands  - manual slash invocation      │
│  1 rule      - session-level guidance       │
│                                             │
│  MCP: gemini-mcp (13 tools, pinned v0.2.0) │
└─────────────────────────────────────────────┘
```
