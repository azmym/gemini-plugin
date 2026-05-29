# Commands Reference

The plugin ships 6 slash commands. Three invoke subagents for manual consultation. Two toggle brainstorming mode. One diagnoses the session.

## Command index

| Command | Agent spawned | Purpose |
|---|---|---|
| `/gemini-plugin:gemini-validate` | gemini-validator | Ad-hoc validation |
| `/gemini-plugin:gemini-challenge` | gemini-challenger | Devil's advocate |
| `/gemini-plugin:gemini-research` | gemini-researcher | Grounded research |
| `/gemini-plugin:gemini-brainstorm-on` | (none) | Enable unconditional grounding |
| `/gemini-plugin:gemini-brainstorm-off` | (none) | Disable unconditional grounding |
| `/gemini-plugin:gemini-doctor` | gemini-researcher (probe) | Diagnose the MCP server and subagent grounding path |

## gemini-validate

**Usage:**

```
/gemini-plugin:gemini-validate <subject>
```

**Arguments:**
- File path: `/gemini-plugin:gemini-validate src/auth/login.ts`
- Inline text: `/gemini-plugin:gemini-validate Is this SQL migration safe for production?`
- Description: `/gemini-plugin:gemini-validate the plan we just created`

**Behavior:** Spawns `gemini-validator` with task=AD_HOC_VALIDATION. The validator reads the subject (file or inline text), calls Gemini to review, and returns a structured verdict.

**Output presented to user:**
- Verdict: pass/fail
- Gaps (if any): bulleted list
- Hallucinations (if any): bulleted list
- Recommended next actions: bulleted list

## gemini-challenge

**Usage:**

```
/gemini-plugin:gemini-challenge <topic>
```

**Arguments:**
- Decision: `/gemini-plugin:gemini-challenge using Redis for session storage`
- Architecture: `/gemini-plugin:gemini-challenge our microservices communication pattern`
- Approach: `/gemini-plugin:gemini-challenge the migration strategy before we execute`

**Behavior:** Spawns `gemini-challenger` with task=AD_HOC_CHALLENGE. The challenger argues against the current approach, proposes alternatives, and identifies failure scenarios.

**Output presented to user:**
- Verdict: pass/fail/block
- Alternatives: numbered list with tradeoffs
- Objections: bulleted list
- Must address: items requiring resolution

## gemini-research

**Usage:**

```
/gemini-plugin:gemini-research <query> [--deep]
```

**Arguments:**
- Quick lookup: `/gemini-plugin:gemini-research latest stable Python release`
- Deep synthesis: `/gemini-plugin:gemini-research compare auth approaches for microservices --deep`

**Modes:**
- **Default (quick):** calls `gemini_search_grounded`, returns in 2-5 seconds
- **`--deep` flag:** calls `gemini_start_research` + polls `gemini_get_research_report`, takes 30-120 seconds

**Output presented to user:**
- Answer: research findings
- Citations: numbered list with URLs
- Freshness: retrieval date
- Confidence: high/medium/low

## gemini-brainstorm-on

**Usage:**

```
/gemini-plugin:gemini-brainstorm-on
```

**Arguments:** none

**Behavior:** Removes `brainstorm.off` from `${CLAUDE_PLUGIN_DATA}` (the v0.2.0+ opt-out flag). With it absent, the `UserPromptSubmit` hook fires on every prompt (the default since v0.2.0). Use this only after a previous `gemini-brainstorm-off`.

**Confirmation message:** "Brainstorming mode ON. Gemini will now ground every prompt with live web data."

## gemini-brainstorm-off

**Usage:**

```
/gemini-plugin:gemini-brainstorm-off
```

**Arguments:** none

**Behavior:** Creates `brainstorm.off` in `${CLAUDE_PLUGIN_DATA}`. While this file exists, the `UserPromptSubmit` hook only fires on prompts that match a narrow keyword regex (e.g. "latest version of X", "CVE-YYYY-NNN", "changelog for X"). Recommended for chatty sessions where you want to control cost.

**Confirmation message:** "Brainstorming mode OFF. Gemini will only ground prompts that match post-cutoff keyword patterns."

## gemini-doctor

**Usage:**

```
/gemini-plugin:gemini-doctor
```

**Arguments:** none

**Behavior:** Runs four diagnostic checks and prints a pass/fail summary:

1. **API key configured.** Confirms `CLAUDE_PLUGIN_OPTION_GEMINI_API_KEY` or `GEMINI_API_KEY` is set, without printing the key.
2. **MCP server reachable from the main agent.** Resolves the grounded-search tool under either the plugin namespace (`mcp__plugin_gemini-plugin_gemini__gemini_search_grounded`) or the manual-install namespace (`mcp__gemini__gemini_search_grounded`), then calls it once to confirm live results with citation URLs.
3. **Subagent grounding path.** Spawns `gemini-researcher` and confirms it actually sees a Gemini tool in its inventory and grounds for real. This is the check that catches the most common failure.
4. **On-disk version.** Reports the plugin version in `${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json`, which is what the next fresh session will load.

**Why it exists:** the most common "grounding produced nothing" report is a **stale session**: the MCP server works (check 2 passes), but a session started before a plugin update still has the outdated subagent definitions loaded in memory (check 3 fails). Subagent definitions are loaded at session start and are not reloaded when the plugin updates on disk. When the doctor sees check 2 pass and check 3 fail, it tells the user to restart Claude Code.

**Diagnosis output:** one line identifying the first failing condition (missing key, server unreachable, stale session, or healthy).
