# Subagents Reference

The plugin ships 5 specialized subagents. Each has a focused role, restricted tools, and a structured JSON output schema. They are spawned by Claude via the Agent tool (triggered by hooks or slash commands).

## Subagent summary

| Agent | Model | Effort | Max turns | Memory | Color | Background |
|---|---|---|---|---|---|---|
| gemini-validator | sonnet | medium | 6 | project | blue | false |
| gemini-challenger | opus | high | 8 | (none) | red | false |
| gemini-researcher | sonnet | medium | 12 | (none) | green | true |
| gemini-summarizer | opus | high | 4 | project | purple | false |
| gemini-reviewer | sonnet | medium | 10 | (none) | cyan | false |

Subagents do not declare a `tools:` allowlist; they inherit the session's tools, including the Gemini MCP tools, under whatever namespace the install registers (the manual-install namespace or the plugin-install namespace). If no Gemini tool is present, each agent fails loud (verdict `unknown` or, for the researcher, confidence `unavailable`) with an `error` field, rather than answering from training data.

All subagents preload the `gemini-when-to-use` skill via the `skills:` frontmatter field.

## gemini-validator

**Role:** Validates plans, diffs, and "done" claims against the original ask. Flags gaps, hallucinations, and missed acceptance criteria.

**Tools:**
- `gemini_generate`
- `gemini_search_grounded`
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
- `gemini_generate`
- `gemini_chat`
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
- `gemini_search_grounded`
- `gemini_start_research`
- `gemini_get_research_report`
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
- `gemini_generate`
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

## gemini-reviewer

**Role:** Generalist third-reviewer for diffs/PRs: security, threading correctness, library/version drift, doc accuracy, dead code, complexity. Covers concerns the other four agents do not own.

**Tools:**
- `gemini_chat`
- `gemini_search_grounded`
- Read, Grep, Glob, Bash

**Output schema:**

```json
{
  "verdict": "approved | changes_requested | unknown",
  "strengths": ["what the change does well"],
  "issues": {"critical": [], "important": [], "minor": []},
  "next_actions": ["concrete fixes with file:line where possible"]
}
```

**Triggered by:**
- the `/gemini-plugin:gemini-consult` dispatch rule (manual). Not wired to any trigger hook.

**Advisory note:** `changes_requested` surfaces inline but does not block (the verdict handler only blocks on fail/block).

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
