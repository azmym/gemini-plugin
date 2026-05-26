# Commands Reference

The plugin ships 5 slash commands. Three invoke subagents for manual consultation. Two toggle brainstorming mode.

## Command index

| Command | Agent spawned | Purpose |
|---|---|---|
| `/gemini-plugin:gemini-validate` | gemini-validator | Ad-hoc validation |
| `/gemini-plugin:gemini-challenge` | gemini-challenger | Devil's advocate |
| `/gemini-plugin:gemini-research` | gemini-researcher | Grounded research |
| `/gemini-plugin:gemini-brainstorm-on` | (none) | Enable unconditional grounding |
| `/gemini-plugin:gemini-brainstorm-off` | (none) | Disable unconditional grounding |

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

**Behavior:** Creates `brainstorm.lock` in `${CLAUDE_PLUGIN_DATA_DIR}`. While this file exists, the `UserPromptSubmit` hook fires on EVERY prompt (bypassing the keyword regex gate).

**Confirmation message:** "Brainstorming mode ON. Gemini will ground every prompt until you run /gemini-plugin:gemini-brainstorm-off or the session ends."

## gemini-brainstorm-off

**Usage:**

```
/gemini-plugin:gemini-brainstorm-off
```

**Arguments:** none

**Behavior:** Removes `brainstorm.lock` from `${CLAUDE_PLUGIN_DATA_DIR}`. The `UserPromptSubmit` hook returns to keyword-gated mode.

**Confirmation message:** "Brainstorming mode OFF. Gemini grounding will only fire on keyword-matching prompts."
