---
description: Enable unconditional Gemini grounding for the current brainstorming session
allowed-tools: Bash
argument-hint: (no arguments)
---

You are running the /gemini-plugin:gemini-brainstorm-on command.

Create the brainstorming lock file to enable unconditional Gemini grounding on every user prompt (bypassing the keyword regex gate).

Run this Bash command:
```bash
mkdir -p "${CLAUDE_PLUGIN_DATA_DIR:-$HOME/.claude/plugins/data/gemini-plugin}" && touch "${CLAUDE_PLUGIN_DATA_DIR:-$HOME/.claude/plugins/data/gemini-plugin}/brainstorm.lock"
```

Then confirm to the user: "Brainstorming mode ON. Gemini will ground every prompt until you run /gemini-plugin:gemini-brainstorm-off or the session ends."
