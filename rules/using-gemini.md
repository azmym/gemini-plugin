## Gemini Plugin: Session Rules

The gemini-plugin is loaded. Five subagents assist you:

| Agent | Role | Spawn via |
|---|---|---|
| gemini-validator | Validates plans, diffs, done-claims for gaps and hallucinations | Hook (ExitPlanMode, Stop) or /gemini-plugin:gemini-validate |
| gemini-challenger | Devil's advocate; proposes alternatives, challenges destructive ops | Hook (PreToolUse Bash) or /gemini-plugin:gemini-challenge |
| gemini-researcher | Search-grounded facts with citations; never opines without a URL | Hook (UserPromptSubmit) or /gemini-plugin:gemini-research |
| gemini-summarizer | Compresses session state; writes risk maps at SessionStart | Hook (SessionStart, PreCompact) |
| gemini-reviewer | Generalist diff/PR review: security, threading, version drift, docs, dead code | /gemini-plugin:gemini-consult rule (manual dispatch) |

### Always reach for Gemini when

- User says "second opinion", "check this", "what would Gemini say"
- A claim depends on post-training-cutoff info (library versions, CVEs, pricing, API shapes)
- You're about to run a destructive command the hook might miss (multi-line scripts, compound pipelines)
- You're completing a plan or claiming "done" and the hook hasn't already fired

### Never reach for Gemini when

- The question is answered by a file already in context
- The task is a trivial typo, formatting, or one-line config change
- You already received a Gemini verdict on the same artifact this session
- The user says "no Gemini", "skip validation", or "just do it"

### Cost discipline

- Validator and researcher use sonnet; challenger and summarizer use opus. Per-prompt grounding now defaults on, so this is a real cost; opt out with /gemini-plugin:gemini-brainstorm-off if needed.
- Manual consults (researcher, validator, challenger, reviewer, summarizer via the gemini-consult rule) are capped at one per turn. The always-on hooks are a separate channel, not counted against that cap.
- Deep research is opt-in only (via /gemini-plugin:gemini-research --deep)
- One validation per artifact per session. No re-asking.
- API key is configured at install time (stored in keychain). If unavailable, everything gracefully no-ops.

### Disable individual components

- Env: `CLAUDE_PLUGIN_GEMINI_DISABLE_HOOKS=1` silences all hooks
- Settings: add `Agent(gemini-plugin:gemini-challenger)` to `permissions.deny` to block specific agents
- Command: `/gemini-plugin:gemini-brainstorm-off` to disable unconditional grounding
