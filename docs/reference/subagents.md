# Subagents Reference

The plugin ships 4 specialized subagents. Each has a focused role, restricted tools, and a structured JSON output schema. They are spawned by Claude via the Agent tool (triggered by hooks or slash commands).

## Subagent summary

| Agent | Model | Effort | Max turns | Memory | Color | Background |
|---|---|---|---|---|---|---|
| gemini-validator | haiku | medium | 3 | project | blue | false |
| gemini-challenger | sonnet | high | 4 | (none) | red | false |
| gemini-researcher | haiku | medium | 6 | (none) | green | true |
| gemini-summarizer | sonnet | high | 2 | project | purple | false |

All subagents preload the `gemini-when-to-use` skill via the `skills:` frontmatter field.

## gemini-validator

**Role:** Validates plans, diffs, and "done" claims against the original ask. Flags gaps, hallucinations, and missed acceptance criteria.

**Tools:**
- `mcp__gemini__gemini_generate`
- `mcp__gemini__gemini_search_grounded`
- Read, Grep, Glob

**Output schema:**

```json
{
  "verdict": "pass | fail",
  "gaps": ["acceptance criteria that are missing or incomplete"],
  "hallucinations": ["claims unsupported by code, docs, or verification"],
  "next_actions": ["concrete fixes ordered by priority"]
}
```

**Triggered by:**
- `ExitPlanMode` hook (plan validation)
- `Stop` hook (done-claim validation)
- `/gemini-plugin:gemini-validate` command

**Anti-loop rule:** If the main agent already addressed the previous critique, emits verdict=pass. Does not re-raise the same objection twice.

## gemini-challenger

**Role:** Devil's advocate. Argues at least 2 alternative approaches and 1 reason the current path is wrong.

**Tools:**
- `mcp__gemini__gemini_generate`
- `mcp__gemini__gemini_chat`
- Read

**Output schema:**

```json
{
  "verdict": "pass | fail | block",
  "alternatives": [
    {"approach": "description", "tradeoff": "cost/benefit"}
  ],
  "objections": ["specific failure scenarios"],
  "must_address": ["minimum concerns to resolve before proceeding"]
}
```

**Verdict semantics:**
- `pass`: proposed action is reasonable; alternatives exist but aren't clearly better
- `fail`: significant concerns; must_address items need resolution
- `block`: dangerous operation with a safer alternative available (destructive ops only)

**Triggered by:**
- `PreToolUse(Bash)` hook on destructive commands
- `/gemini-plugin:gemini-challenge` command

## gemini-researcher

**Role:** Fact-finding with citations. Never asserts a fact without a URL source.

**Tools:**
- `mcp__gemini__gemini_search_grounded`
- `mcp__gemini__gemini_start_research`
- `mcp__gemini__gemini_get_research_report`
- Read

**Output schema:**

```json
{
  "answer": "factual content with inline citations",
  "citations": [
    {"url": "https://...", "title": "...", "relevance": "..."}
  ],
  "freshness": "YYYY-MM-DD",
  "confidence": "high | medium | low",
  "model": "model used"
}
```

**Confidence levels:**
- **high**: multiple authoritative sources agree
- **medium**: single source or limited corroboration
- **low**: sources conflict, unofficial, or no results found

**Triggered by:**
- `UserPromptSubmit` hook (keyword-gated or brainstorm mode)
- `/gemini-plugin:gemini-research` command

**Background:** runs as a background subagent for deep research (non-blocking for long polls).

## gemini-summarizer

**Role:** Compresses session state and writes risk maps. Two task modes.

**Tools:**
- `mcp__gemini__gemini_generate`
- Read, Glob

**Task: BUILD_RISK_MAP**

Output schema:
```json
{
  "repo_root": "/path/to/repo",
  "generated_at": "ISO-8601",
  "high_risk_zones": [
    {"path": "relative/path", "reason": "why risky", "suggestion": "what to watch for"}
  ],
  "missing_tests": ["paths without test counterparts"],
  "complex_state": ["files with high complexity indicators"],
  "fragile_integrations": ["external deps with known issues"]
}
```

**Task: SUMMARIZE_SESSION_STATE**

Output schema:
```json
{
  "session_id": "...",
  "summarized_at": "ISO-8601",
  "decisions_made": ["chose X over Y because Z"],
  "alternatives_discarded": [
    {"option": "...", "reason_rejected": "..."}
  ],
  "unresolved_debt": ["items deferred or unresolved"],
  "key_files_modified": ["paths touched"],
  "next_steps_implied": ["logical continuations"]
}
```

**Triggered by:**
- `SessionStart` hook (BUILD_RISK_MAP, 24h TTL)
- `PreCompact` hook (SUMMARIZE_SESSION_STATE)

**Memory:** project-scoped. Accumulates knowledge about the codebase across sessions.

## Plugin subagent constraints

Per Claude Code documentation, plugin subagents:
- Cannot use: `Agent`, `AskUserQuestion`, `EnterPlanMode`, `ExitPlanMode`, `ScheduleWakeup`
- Cannot define `hooks`, `mcpServers`, or `permissionMode` in frontmatter (ignored)
- Cannot spawn other subagents
- Inherit MCP from the parent session (plugin manifest handles registration)

## Invocation patterns

**Via hooks (automatic):**
Hook script exits 2 with a directive on stderr. Claude reads the directive and spawns the named subagent.

**Via slash command (manual):**
User runs `/gemini-plugin:gemini-validate <subject>`. The command instructs Claude to spawn the matching subagent.

**Via @-mention (manual):**
User types `@agent-gemini-plugin:gemini-validator` in their prompt. Claude spawns it directly.
