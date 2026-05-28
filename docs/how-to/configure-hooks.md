# How to: Configure hooks

This guide covers enabling, disabling, and understanding the plugin's automatic trigger hooks.

## Overview of hooks

The plugin ships 7 hooks (6 triggers + 1 verdict handler):

| Hook | Event | Fires when |
|---|---|---|
| `session-start-risk-map.sh` | SessionStart | First session in a repo (or after 24h TTL expires) |
| `user-prompt-grounding.sh` | UserPromptSubmit | Prompt contains API/version/CVE keywords, or brainstorm mode is on |
| `plan-complete.sh` | ExitPlanMode | Claude exits plan mode with a non-empty plan |
| `pre-destructive-bash.sh` | PreToolUse(Bash) | Command matches destructive patterns |
| `pre-compact-summary.sh` | PreCompact | Context is about to be compacted |
| `stop-done-claim.sh` | Stop | Claude claims completion AND a tool was used |
| `subagent-verdict-handler.sh` | SubagentStop | A gemini-* subagent finishes |

## Disable all hooks

Set the environment variable before starting Claude Code:

```bash
export CLAUDE_PLUGIN_GEMINI_DISABLE_HOOKS=1
```

Every hook checks this variable first and exits 0 (pass-through) if set.

## Disable specific agents

Add to `permissions.deny` in your Claude Code settings:

```json
{
  "permissions": {
    "deny": ["Agent(gemini-plugin:gemini-challenger)"]
  }
}
```

This prevents Claude from spawning that specific subagent. The hook still fires, but the directive is ignored because the agent is blocked.

Available agent names:
- `gemini-plugin:gemini-validator`
- `gemini-plugin:gemini-challenger`
- `gemini-plugin:gemini-researcher`
- `gemini-plugin:gemini-summarizer`

## Graceful degradation without API key

The API key is normally configured during plugin installation via the `userConfig` prompt (stored in system keychain). If for any reason the key is unavailable at runtime, every hook exits 0 with a single-line stderr advisory:

```
[gemini-plugin] GEMINI_API_KEY not set; skipping Gemini consultation.
```

No hook ever blocks when the API key is absent. To re-enter your key, use the plugin settings UI or reinstall the plugin.

## Destructive command patterns

The `pre-destructive-bash.sh` hook matches these patterns:

- `rm -rf` or `rm --force`
- `--force` flag on any command
- `reset --hard`
- `DROP` (SQL)
- `TRUNCATE` (SQL)
- `git push ... --force`
- `dd if=`

Safe commands (like `git push origin main` without `--force`) pass through without triggering.

## UserPromptSubmit keyword gate

Outside brainstorming mode, the grounding hook only fires when the user's prompt contains one of these keywords (case-insensitive):

`api`, `cve`, `version`, `release`, `deprecated`, `library`, `package`, `sdk`, `framework`, `upgrade`, `migrate`

To make it fire on every prompt, enable brainstorm mode:

```
/gemini-plugin:gemini-brainstorm-on
```

## Risk map TTL

The SessionStart hook builds a risk map once and caches it for 24 hours (keyed by a hash of the git repo root). To force a rebuild, delete the cache file:

```bash
rm ~/.claude/plugins/data/gemini-plugin/risk-map-*.json
```

The next session start will regenerate it.

## State directory

All hook state lives in `${CLAUDE_PLUGIN_DATA}`:

| File | Purpose |
|---|---|
| `risk-map-<hash>.json` | Cached repo risk analysis (24h TTL) |
| `plan-history.jsonl` | Append-only log of all verdicts |
| `session-state-<id>.json` | Pre-compact session summaries |
| `last-verdict-<agent>.txt` | Loop guard fingerprint |
| `brainstorm.off` | Opt-out flag for grounding-on-every-prompt (presence = OFF; absence = ON, the default). Toggled by `/gemini-plugin:gemini-brainstorm-on` and `/gemini-plugin:gemini-brainstorm-off`. |

## How blocking works

When a hook wants to block Claude:
1. It writes a directive to stderr (tells Claude which subagent to spawn)
2. It exits with code 2
3. Claude sees the stderr message in its next turn
4. Claude spawns the subagent and waits for its verdict
5. The SubagentStop verdict handler checks the result
6. If verdict=fail: exit 2 again (Claude must address gaps)
7. If verdict=pass: exit 0 (Claude continues normally)
