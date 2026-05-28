---
description: Re-enable Gemini grounding on every prompt (it is on by default; this only matters if you previously turned it off)
allowed-tools: Bash
argument-hint: (no arguments)
---

You are running the /gemini-plugin:gemini-brainstorm-on command.

As of v0.2.0, brainstorming mode is ON by default. This command exists to re-enable it after a previous `/gemini-plugin:gemini-brainstorm-off` call. It removes the `brainstorm.off` opt-out file.

Run this Bash command:
```bash
DATA="${CLAUDE_PLUGIN_DATA:-$HOME/.claude/plugins/data/gemini-plugin}"
mkdir -p "$DATA"
rm -f "$DATA/brainstorm.off"
```

Then confirm to the user: "Brainstorming mode ON. Gemini will now ground every prompt with live web data."
