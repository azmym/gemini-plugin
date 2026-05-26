---
description: Disable unconditional Gemini grounding (return to keyword-gated mode)
allowed-tools: Bash
argument-hint: (no arguments)
---

You are running the /gemini-plugin:gemini-brainstorm-off command.

Remove the brainstorming lock file to return to keyword-gated grounding.

Run this Bash command:
```bash
rm -f "${CLAUDE_PLUGIN_DATA_DIR:-$HOME/.claude/plugins/data/gemini-plugin}/brainstorm.lock"
```

Then confirm to the user: "Brainstorming mode OFF. Gemini grounding will only fire on keyword-matching prompts."
