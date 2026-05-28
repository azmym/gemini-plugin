# Architecture Reference

This document describes the system architecture of gemini-plugin: how the components interact, how data flows through hooks and subagents, and how the MCP layer connects everything to Google AI Studio.

## System overview

```mermaid
graph TB
    subgraph "Claude Code Session"
        User[User] --> Claude[Main Claude Agent]
        Claude --> Skills[8 Skills]
        Claude --> Commands[5 Slash Commands]
    end

    subgraph "gemini-plugin (hooks layer)"
        H1[SessionStart] --> |exit 2| Claude
        H2[UserPromptSubmit] --> |exit 2| Claude
        H3[PreToolUse Bash] --> |exit 2| Claude
        H4[PreToolUse ExitPlanMode] --> |exit 2| Claude
        H5[PreCompact] --> |exit 2| Claude
        H6[Stop] --> |exit 2| Claude
    end

    subgraph "Subagents (reasoning layer)"
        Claude --> |Agent tool| Validator[gemini-validator]
        Claude --> |Agent tool| Challenger[gemini-challenger]
        Claude --> |Agent tool| Researcher[gemini-researcher]
        Claude --> |Agent tool| Summarizer[gemini-summarizer]
    end

    subgraph "MCP (execution layer)"
        Validator --> MCP[gemini-mcp server]
        Challenger --> MCP
        Researcher --> MCP
        Summarizer --> MCP
    end

    subgraph "Google AI Studio"
        MCP --> Gemini[Gemini 3.x]
        MCP --> Imagen[Imagen 4]
        MCP --> Veo[Veo 3.1]
        MCP --> Lyria[Lyria 3]
    end

    H7[SubagentStop] --> |verdict check| Claude
```

## Three-layer architecture

The plugin separates concerns into three layers:

```
┌─────────────────────────────────────────────────────┐
│ Layer 1: COORDINATION (hooks)                       │
│                                                     │
│ - Read event JSON from stdin                        │
│ - Apply gate logic (regex, TTL, brainstorm flag)    │
│ - Emit directive to stderr                          │
│ - Exit 2 to block, exit 0 to pass                  │
│ - Never call MCP directly                           │
└─────────────────────────────┬───────────────────────┘
                              │ spawns via Agent tool
┌─────────────────────────────▼───────────────────────┐
│ Layer 2: REASONING (subagents)                      │
│                                                     │
│ - Focused system prompt per role                    │
│ - Limited tool access (read-only + MCP)             │
│ - Structured JSON output (verdict schema)           │
│ - Anti-loop rules prevent re-raising same issues    │
│ - maxTurns cap prevents runaway                     │
└─────────────────────────────┬───────────────────────┘
                              │ calls MCP tools
┌─────────────────────────────▼───────────────────────┐
│ Layer 3: EXECUTION (gemini-mcp)                     │
│                                                     │
│ - 13 MCP tools (text, image, video, music, etc.)    │
│ - google-genai SDK → Google AI Studio               │
│ - Stateless per-call (no persistent state)          │
│ - Model selection per tool call                     │
└─────────────────────────────────────────────────────┘
```

## Hook execution flow

```mermaid
sequenceDiagram
    participant E as Event (Claude Code)
    participant H as Hook Script
    participant C as Main Claude
    participant S as Subagent
    participant M as gemini-mcp
    participant G as Google AI Studio

    E->>H: Event JSON (stdin)
    H->>H: check_plugin_enabled()
    H->>H: check_gemini_available()
    H->>H: Apply gate logic

    alt Gate passes
        H-->>C: Directive (stderr, exit 2)
        C->>S: Spawn subagent via Agent tool
        S->>M: Call MCP tool (e.g. gemini_generate)
        M->>G: API request
        G-->>M: Response
        M-->>S: Tool result
        S-->>C: Structured JSON verdict
        Note over C: SubagentStop hook fires
        C->>C: Verdict handler checks pass/fail
        alt verdict = fail
            C->>C: Address gaps before continuing
        else verdict = pass
            C->>C: Continue normally
        end
    else Gate fails
        H-->>E: Exit 0 (pass-through)
    end
```

## Component inventory

| Component | Count | Location | Purpose |
|---|---|---|---|
| Plugin manifest | 1 | `.claude-plugin/plugin.json` | Metadata, userConfig prompt, MCP server registration |
| Skills | 8 | `skills/*/SKILL.md` | When/how to use Gemini capabilities |
| Subagents | 4 | `agents/*.md` | Role-specific reasoning with structured output |
| Commands | 5 | `commands/*.md` | User-invoked slash commands |
| Hooks | 7 | `hooks/hooks.json` + `hooks/*.sh` | 6 triggers + 1 verdict handler |
| Shared library | 2 | `hooks/lib/*.sh` | JSON helpers, gates, prompt builders |
| Rules | 1 | `rules/using-gemini.md` | Session-level usage guidance |
| Marketplace | external | [SynthForge](https://github.com/azmym/SynthForge) | Distribution catalog |

## API key configuration

The plugin uses `userConfig` to prompt for the API key at install time:

```json
{
  "userConfig": {
    "gemini_api_key": {
      "type": "string",
      "title": "Gemini API Key",
      "description": "Google AI Studio API key",
      "sensitive": true,
      "required": true
    }
  }
}
```

The key is stored in the system keychain (`sensitive: true`) and injected at runtime via `${user_config.gemini_api_key}`. Users never need to export environment variables manually.

## MCP server registration

The plugin manifest auto-registers the gemini MCP server on install:

```json
{
  "mcpServers": {
    "gemini": {
      "type": "stdio",
      "command": "uvx",
      "args": ["--from", "git+https://github.com/azmym/gemini-mcp@v0.2.0", "gemini-mcp"],
      "env": { "GEMINI_API_KEY": "${user_config.gemini_api_key}" }
    }
  }
}
```

All 4 subagents inherit this MCP connection from the parent session (plugin subagents cannot define their own `mcpServers` in frontmatter).

## State management

```mermaid
graph LR
    subgraph "CLAUDE_PLUGIN_DATA"
        RM[risk-map-hash.json]
        PH[plan-history.jsonl]
        SS[session-state-id.json]
        LV[last-verdict-agent.txt]
        BL[brainstorm.lock]
    end

    H1[session-start hook] --> |writes| RM
    H3[plan-complete hook] --> |reads| PH
    VH[verdict-handler] --> |appends| PH
    VH --> |writes| LV
    H5[pre-compact hook] --> |writes| SS
    BC[brainstorm-on cmd] --> |touches| BL
    H2[user-prompt hook] --> |reads| BL
```

State is local, session-scoped, and disposable. Deleting the data directory resets all state (risk maps rebuild on next session, verdicts start fresh).

## Model allocation

| Subagent | Model | Rationale |
|---|---|---|
| gemini-validator | Sonnet | Reliable structured-output for JSON verdicts; bumped from Haiku in v0.3.0 after partial-response failures |
| gemini-challenger | Opus | Hardest reasoning task (creative alternatives + objections); bumped from Sonnet in v0.3.0 |
| gemini-researcher | Sonnet | Multi-source synthesis and citation discipline; bumped from Haiku in v0.3.0 |
| gemini-summarizer | Opus | Large-input compression with structured output; bumped from Sonnet in v0.3.0 |

All subagents call Gemini models via MCP (default: `gemini-3.5-flash` for chat/search, `gemini-3.1-pro-preview` for generate). The Claude model handles orchestration and JSON structuring; the Gemini model handles reasoning and web access. The Claude-side model bumps in v0.3.0 fixed a class of partial-response failures where validator and other agents were exiting before producing the final JSON verdict.
