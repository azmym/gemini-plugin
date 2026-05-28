---
description: Turn off Gemini grounding on every prompt (the plugin will only ground when prompts contain post-cutoff keywords like 'latest version of X' or 'CVE-YYYY-NNN')
allowed-tools: Bash
argument-hint: (no arguments)
---

You are running the /gemini-plugin:gemini-brainstorm-off command.

As of v0.2.0, brainstorming mode is ON by default and grounds every prompt. This command opts OUT by creating a `brainstorm.off` flag file. The plugin then only fires the grounding hook when the prompt matches narrow keyword patterns (e.g. "latest version of X", "CVE-YYYY-NNN", "changelog for X").

Run this Bash command:
```bash
DATA="${CLAUDE_PLUGIN_DATA:-$HOME/.claude/plugins/data/gemini-plugin}"
mkdir -p "$DATA"
touch "$DATA/brainstorm.off"
```

Then confirm to the user: "Brainstorming mode OFF. Gemini will only ground prompts that match post-cutoff keyword patterns."
