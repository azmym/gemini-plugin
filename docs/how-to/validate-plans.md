# How to: Validate plans and claims

This guide covers using Gemini to catch gaps, hallucinations, and missed acceptance criteria in plans and "done" claims.

## Automatic validation (hooks)

Two hooks handle validation automatically:

**ExitPlanMode hook:** fires every time Claude exits plan mode. The validator reviews the plan text plus the last 3 rejected plans (to avoid re-raising addressed issues).

**Stop hook:** fires when Claude claims a task is complete (words like "done", "completed", "finished") AND a tool was used in the session. The validator checks the diff against the original ask.

Both hooks block Claude (exit 2) if the verdict is `fail`. You see the critique inline and Claude must address it before continuing.

## Manual validation

Use the slash command for ad-hoc validation of anything:

```
/gemini-plugin:gemini-validate <subject>
```

The subject can be:
- A file path: `/gemini-plugin:gemini-validate src/auth/login.ts`
- Inline text: `/gemini-plugin:gemini-validate Is this migration safe for a 50M row table?`
- A description: `/gemini-plugin:gemini-validate the authentication flow we just designed`

Or mention the agent directly:

```
@agent-gemini-plugin:gemini-validator Review the plan I just created for gaps
```

## Understanding the verdict

The validator returns structured JSON:

```json
{
  "verdict": "pass | fail",
  "gaps": ["acceptance criteria that are missing or incomplete"],
  "hallucinations": ["claims not supported by code, docs, or verification"],
  "next_actions": ["concrete, ordered fixes"]
}
```

- **verdict=pass**: all acceptance criteria met, no hallucinations found
- **verdict=fail**: at least one gap or hallucination exists; Claude must address it

## Loop guard behavior

If the validator returns the exact same fail verdict twice in a row (identical JSON), the second occurrence is downgraded to "advisory" (exit 0, non-blocking). This prevents infinite validation loops where Claude cannot satisfy the criterion.

## Disable validation hooks

To skip validation temporarily:

```bash
export CLAUDE_PLUGIN_GEMINI_DISABLE_HOOKS=1
```

Or block only the validator agent:

Add `Agent(gemini-plugin:gemini-validator)` to `permissions.deny` in your settings.

## Tips

- The validator uses Haiku for speed and cost. For complex validations, it calls `gemini_search_grounded` to verify post-cutoff claims.
- Plan history is stored in `${CLAUDE_PLUGIN_DATA_DIR}/plan-history.jsonl`. The validator references this to avoid re-raising addressed issues.
- One validation per artifact per session. The validator will not re-validate the same unchanged artifact.
