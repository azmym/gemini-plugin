# gemini-plugin design spec

**Date:** 2026-05-26
**Status:** approved (brainstorming complete, awaiting user spec review)
**Target version:** v0.1.0
**Repo (planned):** `~/workspace/gemini-plugin` (single-plugin marketplace, publish to GitHub as `azmym/gemini-plugin`)

## 1. Goal

Build a Claude Code plugin that turns the existing [gemini-mcp](https://github.com/azmym/gemini-mcp) FastMCP server into a first-class assistance layer for the main Claude agent. Gemini acts as a second opinion that validates plans, challenges destructive operations, grounds prompts in live web data, summarizes session state, and audits "done" claims, all to reduce hallucination and break repeated work.

The plugin is designed for eventual publication on a Claude Code marketplace.

## 2. Non-goals

- Replacing Claude as the primary agent. Gemini is consultative.
- Ephemeral coding tasks. The plugin must stay quiet on trivial typo fixes, formatting, and one-line changes.
- Wrapping every gemini-mcp tool 1:1. Skills are task-oriented, not tool-oriented.
- Per-tool subagents. The four subagents are role-oriented (validate, challenge, research, summarize), not capability-oriented.

## 3. Architecture

Three layers. Hooks coordinate, subagents reason, MCP executes.

```
┌──────────────────────────────────────────────────────────────┐
│ Main Claude (orchestrator)                                   │
│                                                              │
│   ▼ skills (8): when-to-use + 7 capability skills            │
│   ▼ slash commands (3): /gemini-validate, /challenge, ...    │
│   ▼ hooks (6 triggers + 1 verdict handler)                   │
│       │                                                      │
│       ▼ Agent tool spawns named subagent                     │
│           (gemini-validator | -challenger |                  │
│            -researcher | -summarizer)                        │
│           │                                                  │
│           ▼ MCP tools (gemini_generate, _search_grounded,    │
│              _start_research, _analyze_file, _chat, ...)     │
│           │                                                  │
│           ▼ google-genai SDK → Google AI Studio              │
└──────────────────────────────────────────────────────────────┘
```

## 4. Final directory tree

```
gemini-plugin/                            ← single git repo, marketplace + plugin
├── .claude-plugin/
│   ├── plugin.json                       ← plugin manifest
│   └── marketplace.json                  ← marketplace catalog (source: "./")
├── README.md
├── skills/
│   ├── gemini-when-to-use/SKILL.md
│   ├── gemini-chat-and-reason/SKILL.md
│   ├── gemini-research-grounded/SKILL.md
│   ├── gemini-image-gen/SKILL.md
│   ├── gemini-video-gen/SKILL.md
│   ├── gemini-audio-tts-music/SKILL.md
│   ├── gemini-file-analysis/SKILL.md
│   └── gemini-code-exec/SKILL.md
├── agents/
│   ├── gemini-validator.md
│   ├── gemini-challenger.md
│   ├── gemini-researcher.md
│   └── gemini-summarizer.md
├── commands/
│   ├── gemini-validate.md
│   ├── gemini-challenge.md
│   └── gemini-research.md
├── hooks/
│   ├── hooks.json
│   ├── session-start-risk-map.sh
│   ├── user-prompt-grounding.sh
│   ├── plan-complete.sh
│   ├── pre-destructive-bash.sh
│   ├── pre-compact-summary.sh
│   ├── stop-done-claim.sh
│   ├── subagent-verdict-handler.sh
│   └── lib/
│       ├── common.sh                     ← JSON helpers, brainstorm-detect, MCP availability
│       └── prompt-builder.sh             ← directive strings emitted to stderr
├── rules/
│   └── using-gemini.md
└── docs/
    └── superpowers/
        ├── specs/                        ← this file
        └── plans/                        ← implementation plan (next step)
```

No `../` paths anywhere. The plugin is fully self-contained for the cache-copy install path.

## 5. Plugin manifest (`.claude-plugin/plugin.json`)

```json
{
  "name": "gemini-plugin",
  "displayName": "Gemini Plugin",
  "version": "0.1.0",
  "description": "Wraps gemini-mcp into a Claude Code plugin so Gemini acts as a second opinion: validator/challenger/researcher/summarizer subagents, auto-trigger hooks, and 8 task-oriented skills.",
  "author": { "name": "azmym" },
  "homepage": "https://github.com/azmym/gemini-plugin",
  "repository": "https://github.com/azmym/gemini-plugin",
  "license": "MIT",
  "keywords": ["gemini", "mcp", "subagent", "hooks", "anti-hallucination", "google-ai"],
  "mcpServers": {
    "gemini": {
      "type": "stdio",
      "command": "uvx",
      "args": ["--from", "git+https://github.com/azmym/gemini-mcp", "gemini-mcp"],
      "env": { "GEMINI_API_KEY": "${GEMINI_API_KEY}" }
    }
  }
}
```

**Key decision:** `version` is set explicitly. Bump on every release; users only receive updates when this string changes.

## 6. Marketplace catalog (`.claude-plugin/marketplace.json`)

```json
{
  "name": "gemini-marketplace",
  "owner": { "name": "azmym" },
  "description": "Gemini-as-second-opinion plugin for Claude Code",
  "plugins": [
    {
      "name": "gemini-plugin",
      "source": "./",
      "description": "Wraps gemini-mcp into a Claude Code plugin: validator/challenger/researcher/summarizer subagents, auto-trigger hooks, 8 skills covering text/image/video/music/TTS/research.",
      "category": "ai-assistance",
      "tags": ["gemini", "google-ai", "validation", "anti-hallucination", "second-opinion"],
      "keywords": ["gemini", "mcp", "subagent", "hooks", "validator"]
    }
  ]
}
```

**Install flow once published:**

```bash
/plugin marketplace add azmym/gemini-plugin
/plugin install gemini-plugin@gemini-marketplace
export GEMINI_API_KEY=<key>
```

The `mcpServers` block in `plugin.json` auto-registers `gemini-mcp` on install. No separate `claude mcp add` step.

## 7. Skills (8 files in `skills/`)

| # | Skill | When to invoke | Primary MCP tool |
|---|-------|----------------|------------------|
| 1 | `gemini-when-to-use` | First, before any other gemini-* skill. Read once per session. Master router covering cost discipline, anti-hallucination triggers, and the four subagent roles. | (decision guide only) |
| 2 | `gemini-chat-and-reason` | Second opinions, code review, design critique, sanity-check before commit. | `gemini_generate`, `gemini_chat` |
| 3 | `gemini-research-grounded` | Live-web research, API releases, CVEs, library docs, current events. Anything past Claude's training cutoff. | `gemini_search_grounded`, `gemini_start_research`, `gemini_get_research_report` |
| 4 | `gemini-file-analysis` | Multi-modal Q&A on PDFs/images/audio/video or large source files. | `gemini_analyze_file` |
| 5 | `gemini-code-exec` | Verify math, simulate logic, test snippets without local exec. | `gemini_code_execute` |
| 6 | `gemini-image-gen` | Mockups, hero images, product shots, infographic frames. | `gemini_generate_image`, `gemini_generate_image_imagen` |
| 7 | `gemini-video-gen` | Short clips, product demos, B-roll. Async start+poll. | `gemini_start_video`, `gemini_get_video` |
| 8 | `gemini-audio-tts-music` | Soundtracks, voiceovers, narration. | `gemini_generate_music`, `gemini_tts` |

**Design rules:**
- `gemini-when-to-use` has the broadest description (auto-loads); the other seven have narrow descriptions to avoid accidental invocation on cheap tasks.
- No skill per subagent. Capabilities are skills; roles are subagents.

## 8. Subagents (4 files in `agents/`)

Per the [subagents docs](https://code.claude.com/docs/en/sub-agents), plugin subagents:
- ignore `hooks`, `mcpServers`, and `permissionMode` in frontmatter
- inherit MCP from the parent (so the plugin's `mcpServers` registration covers all four)
- cannot spawn other subagents
- cannot use `Agent`, `AskUserQuestion`, `EnterPlanMode`, `ExitPlanMode`, `ScheduleWakeup`, `WaitForMcpServers`

### 8.1 Roles, models, tools

| Agent | Role | Model | `effort` | `memory` | `maxTurns` | `color` | `background` | Allowed tools |
|---|---|---|---|---|---|---|---|---|
| `gemini-validator` | Validates plans/diffs/done-claims against original ask. Outputs `{verdict, gaps, hallucinations, next_actions}`. | haiku | medium | project | 3 | blue | false | `mcp__gemini__gemini_generate`, `mcp__gemini__gemini_search_grounded`, Read, Grep, Glob |
| `gemini-challenger` | Devil's advocate. Argues 2+ alternatives + 1 reason current path is wrong. Outputs `{alternatives, objections, must_address}`. | sonnet | high | none | 4 | red | false | `mcp__gemini__gemini_generate`, `mcp__gemini__gemini_chat`, Read |
| `gemini-researcher` | Live-web grounding + deep research with citations. Never opines without citations. | haiku (escalates to deep-research model on `--deep`) | medium | none | 6 | green | true (for deep) | `mcp__gemini__gemini_search_grounded`, `mcp__gemini__gemini_start_research`, `mcp__gemini__gemini_get_research_report`, Read |
| `gemini-summarizer` | Compresses session history, writes risk maps. | sonnet | high | project | 2 | purple | false | `mcp__gemini__gemini_generate`, Read, Glob |

All four preload `gemini-when-to-use` via the `skills:` field. All four use the recommended "Use proactively when …" description style.

### 8.2 System prompt skeleton (template applies to all four)

```markdown
---
name: gemini-validator
description: |
  Use proactively after a plan is finalized, after Claude claims a task is done,
  or before a destructive change. Validates the artifact against the original ask
  and flags gaps, hallucinations, and missed acceptance criteria. Returns
  structured JSON {verdict, gaps, hallucinations, next_actions}.
tools:
  - mcp__gemini__gemini_generate
  - mcp__gemini__gemini_search_grounded
  - Read
  - Grep
  - Glob
model: haiku
color: blue
maxTurns: 3
effort: medium
memory: project
skills:
  - gemini-when-to-use
---

You are gemini-validator: a precise, skeptical reviewer powered by Google Gemini.

Your job: read the artifact you were handed (a plan, a diff, a done-claim) and
return ONE structured JSON verdict. No preamble, no commentary outside the JSON.

Output schema:
{
  "verdict": "pass" | "fail",
  "gaps": ["..."],            // missed acceptance criteria
  "hallucinations": ["..."],  // claims unsupported by the artifact
  "next_actions": ["..."]     // concrete fixes ordered by priority
}

Anti-loop rule: If the main agent already addressed your previous critique,
say so explicitly in next_actions and emit verdict=pass. Do not re-raise the
same objection twice in a row.
```

(Other three agents follow the same template with role-specific schemas.)

## 9. Hooks (`hooks/hooks.json` + 7 scripts)

### 9.1 Pattern

All hooks live in `hooks/hooks.json`. Frontmatter hooks are ignored for plugin subagents, so this is the only valid location. The pattern:

1. Trigger hook reads event JSON from stdin.
2. Builds a curated prompt and writes a directive to stderr (e.g., "Spawn `@agent-gemini-plugin:gemini-challenger` ...").
3. Exits **2** to block Claude. Claude sees the stderr in its next turn and spawns the subagent via the `Agent` tool.
4. `SubagentStop` verdict handler inspects the subagent's structured JSON output and exits 0 (allow) or 2 (block-and-surface).

### 9.2 `hooks.json` (full)

```json
{
  "hooks": {
    "SessionStart": [
      { "matcher": "startup",
        "hooks": [{ "type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/hooks/session-start-risk-map.sh", "async": false }] }
    ],
    "UserPromptSubmit": [
      { "hooks": [{ "type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/hooks/user-prompt-grounding.sh", "async": false }] }
    ],
    "ExitPlanMode": [
      { "hooks": [{ "type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/hooks/plan-complete.sh", "async": false }] }
    ],
    "PreToolUse": [
      { "matcher": "Bash",
        "hooks": [{ "type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/hooks/pre-destructive-bash.sh", "async": false }] }
    ],
    "PreCompact": [
      { "hooks": [{ "type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/hooks/pre-compact-summary.sh", "async": false }] }
    ],
    "Stop": [
      { "hooks": [{ "type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/hooks/stop-done-claim.sh", "async": false }] }
    ],
    "SubagentStop": [
      { "matcher": "gemini-validator|gemini-challenger|gemini-researcher|gemini-summarizer",
        "hooks": [{ "type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/hooks/subagent-verdict-handler.sh", "async": false }] }
    ]
  }
}
```

### 9.3 Trigger hooks (6)

| Hook | Event | Gate | Subagent | Directive |
|---|---|---|---|---|
| `session-start-risk-map.sh` | `SessionStart(startup)` | run only if `<plugin-data>/risk-map-<repo-hash>.json` is missing or older than 24h | `gemini-summarizer` | "Spawn gemini-summarizer with task=BUILD_RISK_MAP." |
| `user-prompt-grounding.sh` | `UserPromptSubmit` | **always-on** if brainstorming session detected; else regex gate (`api`, `cve`, `version`, `release`, `deprecated`, library names) | `gemini-researcher` | "Before answering, spawn gemini-researcher with task=GROUND_PROMPT." |
| `plan-complete.sh` | `ExitPlanMode` | always | `gemini-validator` | "Plan ready. Spawn gemini-validator with task=VALIDATE_PLAN. Pass plan + last-3-rejected-plans summary from `<plugin-data>/plan-history.jsonl`. Block presenting until verdict returns." |
| `pre-destructive-bash.sh` | `PreToolUse(Bash)` | regex: `\brm -rf\b`, `--force`, `\bDROP\b`, `\bTRUNCATE\b`, `reset --hard`, `git push.*--force`, `dd if=` | `gemini-challenger` | "Spawn gemini-challenger with task=CHALLENGE_DESTRUCTIVE_OP. Do not execute Bash until verdict returns." |
| `pre-compact-summary.sh` | `PreCompact` | always | `gemini-summarizer` | "Spawn gemini-summarizer with task=SUMMARIZE_SESSION_STATE. Append output to `<plugin-data>/session-state-<sessionId>.json`." |
| `stop-done-claim.sh` | `Stop` | claim detector: last assistant message contains `done`, `completed`, `finished`, `ready`, `fixed`, `passing` AND a tool was used in this session | `gemini-validator` | "Spawn gemini-validator with task=VALIDATE_DONE_CLAIM. If verdict=fail, do not stop — address gaps." |

### 9.4 Verdict handler (`subagent-verdict-handler.sh`)

```bash
#!/usr/bin/env bash
set -euo pipefail
INPUT=$(cat)
AGENT=$(echo "$INPUT" | jq -r '.agent_type')
TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path')

VERDICT_JSON=$(tail -50 "$TRANSCRIPT" | jq -rs '
  [.[] | select(.type=="assistant")] | last
  | .message.content[0].text // empty
' | tail -c 8192)

VERDICT=$(echo "$VERDICT_JSON" | jq -r '.verdict // "advisory"')
GAPS=$(echo "$VERDICT_JSON" | jq -r '.gaps // .objections // .must_address // []')

# Loop guard: identical verdict twice in a row → downgrade to advisory
LAST_FILE="${CLAUDE_PLUGIN_DATA_DIR}/last-verdict-${AGENT}.txt"
LAST=$(cat "$LAST_FILE" 2>/dev/null || echo "")
if [ "$VERDICT" = "fail" ] && [ "$VERDICT_JSON" = "$LAST" ]; then
  VERDICT="advisory"
fi
echo "$VERDICT_JSON" > "$LAST_FILE"
echo "$VERDICT_JSON" >> "${CLAUDE_PLUGIN_DATA_DIR}/plan-history.jsonl"

if [ "$VERDICT" = "fail" ] || [ "$VERDICT" = "block" ]; then
  cat >&2 <<EOF
[gemini-plugin] $AGENT verdict: $VERDICT
Issues to address before continuing:
$GAPS
EOF
  exit 2
fi
exit 0
```

### 9.5 Brainstorming detection

`user-prompt-grounding.sh` is unconditional during brainstorming, regex-gated otherwise. Detection signals (any one is sufficient):

1. `superpowers:brainstorming` skill content present in current turn.
2. Active TaskList contains tasks created by the brainstorming flow ("Ask clarifying questions", "Propose 2-3 approaches", "Present full design").
3. Last assistant turn invoked `Skill` with name `brainstorming` or `superpowers:brainstorming`.
4. Plugin-level flag file `<plugin-data>/brainstorm.lock` (toggled by `/gemini-brainstorm-on` and `/gemini-brainstorm-off`).

### 9.6 State directory: `${CLAUDE_PLUGIN_DATA_DIR}`

Holds:
- `risk-map-<repo-hash>.json` — boot-time repo summary (24h TTL)
- `plan-history.jsonl` — append-only verdict log; feeds `plan-complete.sh` history summary
- `session-state-<sessionId>.json` — pre-compact summaries
- `last-verdict-<agent>.txt` — loop-guard fingerprint
- `brainstorm.lock` — manual override flag

## 10. Slash commands (3 files in `commands/`)

| File | Slash form | Behavior |
|---|---|---|
| `gemini-validate.md` | `/gemini-plugin:gemini-validate <subject>` | Spawns `gemini-validator` ad-hoc on a plan, diff, function name, or pasted text. |
| `gemini-challenge.md` | `/gemini-plugin:gemini-challenge <topic>` | Devil's advocate on architectural choices, before-merge checks. |
| `gemini-research.md` | `/gemini-plugin:gemini-research <query> [--deep]` | Default: grounded search; `--deep`: deep-research polling pair. |

Plus two utility slashes (single-file, no subagent):
- `/gemini-plugin:gemini-brainstorm-on` — touches `brainstorm.lock`
- `/gemini-plugin:gemini-brainstorm-off` — removes `brainstorm.lock`

## 11. Rules (`rules/using-gemini.md`)

Auto-loaded into the main session. Defines:
- The four subagent roles and when to reach for each.
- Always-call triggers: "second opinion" requests, post-cutoff facts, multi-line destructive scripts the regex hook would miss.
- Never-call triggers: trivial typos, formatting, single-file Q&A already in context, repeat verdicts on the same artifact.
- Cost discipline: prefer haiku, opt-in deep research, graceful no-op when `GEMINI_API_KEY` is unset.

## 12. Plan validation strategy

Per Gemini's own self-review (in conversation), `gemini_chat` (multi-turn) is **not** strictly better than `gemini_generate` (single-turn) for plan validation. Failure modes of multi-turn: state desync after backtracking, echo-chamber agreement after 3-4 turns, exponential token bloat, latency spikes.

**Decision: single-turn `gemini_generate` + plugin-curated `<history_summary>`.**

`plan-complete.sh` reads the last 3 entries from `plan-history.jsonl` (filtered to plan-validation verdicts), curates a short summary (rejected plan title + headline reason for rejection), and injects that into the validator's prompt. This gives multi-turn's contextual memory without the desync, echo-chamber, or token-bloat risks.

## 13. Anti-loop and cost safeguards

| Concern | Mechanism |
|---|---|
| MCP missing or `GEMINI_API_KEY` unset | hook scripts gracefully `exit 0` with stderr note; never block work |
| Long Gemini latency on every prompt | only `UserPromptSubmit` runs per-prompt, gated by regex (or brainstorm flag) |
| Hook on hook recursion | `SubagentStop` matcher only fires for `gemini-*` agents — never re-enters |
| Cost runaway | `maxTurns` per agent; loop-guard demotes repeats to advisory |
| Stale risk map | 24h TTL check |
| Repeat verdicts on same artifact | rule + verdict-handler dedupe via `last-verdict-<agent>.txt` |
| Subagents spawning subagents | docs prevent it; main Claude orchestrates any chains |

## 14. Out of scope for v0.1

- **Large-file outline interceptor** (PreToolUse on Read/Edit > 100KB → `gemini_analyze_file` outline). Highest-risk feature: a wrong outline causes blind edits. Deferred to v0.2 with a fallback path that reads the file fully if the outline misses the target line range.
- **PostToolUse(Bash) on test failure** with auto-diagnostic hint. Deferred; no clear consent for v0.1.
- **`gemini_chat` multi-turn for plan validation.** Replaced by single-turn + history summary.
- **Per-tool subagents** (gemini-text, gemini-image, ...). Roles, not capabilities.

## 15. Acceptance criteria for v0.1

1. Plugin installs in one step from a marketplace add: `/plugin marketplace add azmym/gemini-plugin && /plugin install gemini-plugin@gemini-marketplace`.
2. With `GEMINI_API_KEY` set, all 8 skills are discoverable via `/<plugin-name>:<skill>` and the `Skill` tool.
3. All 4 subagents are invocable via `@agent-gemini-plugin:<name>` and via the 3 slash commands.
4. All 6 trigger hooks fire on the documented events; the verdict handler blocks on `verdict=fail` and surfaces gaps to Claude.
5. With `GEMINI_API_KEY` unset, every hook gracefully no-ops with a single-line stderr note. No false blocks.
6. Brainstorming detection flips `UserPromptSubmit` grounding from regex-gated to always-on.
7. Loop guard demotes a repeat-fail verdict to advisory.
8. The plugin contains no `../` paths and is fully self-contained for cache-copy install.
9. README documents install, the 6 hook triggers, the 4 subagents, the 3 slash commands, the disable env var, and the brainstorming flag.

## 16. Open questions / risks

- **Brainstorming detection accuracy.** Signal #1 (skill content in current turn) is the most reliable but only works if the brainstorming skill has fired this turn. May need a longer-window detector (e.g., last N turns).
- **Cost on long sessions.** PreCompact runs once per compaction event; on long brainstorming sessions, that could be 3-4 invocations. Monitor in v0.1 and consider rate-limiting in v0.2.
- **`risk-map.json` schema.** Not pinned in this spec; the implementation plan must define it before writing `session-start-risk-map.sh`.
- **Brainstorming detection in subagents.** Subagents have isolated context, so signal #1 only works in the main session. Hook scripts run in the main session — confirmed safe.
