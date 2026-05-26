# Tutorial: Getting started with gemini-plugin

This tutorial walks you through installing the plugin, running your first validation, and seeing the auto-trigger hooks in action. By the end, you will have Gemini actively reviewing your work inside Claude Code.

## Prerequisites

- Claude Code installed and running
- A Google AI Studio API key (free at [aistudio.google.com/app/apikey](https://aistudio.google.com/app/apikey))
- `uv` installed (provides `uvx` for running the MCP server)
- `jq` installed (used by hook scripts)

## Step 1: Install the plugin

Open Claude Code and run:

```
/plugin marketplace add azmym/gemini-plugin
/plugin install gemini-plugin@gemini-marketplace
```

## Step 2: Enter your API key

During installation, Claude Code prompts you for your Google AI Studio API key:

```
Gemini API Key: ________
```

The input is masked and the key is stored securely in your system keychain (not in settings files or plain text). You only enter this once; it persists across sessions.

If you don't have a key yet, get one free at [aistudio.google.com/app/apikey](https://aistudio.google.com/app/apikey).

## Step 3: Verify the installation

Start a new Claude Code session. You should see the `gemini` MCP server connected:

```
claude mcp list
# Expected: gemini: ... - Connected
```

Check that skills are available:

```
/gemini-plugin:gemini-validate
```

You should see the slash command auto-complete.

## Step 4: Run your first validation

Ask Claude to create a plan for any task:

```
Plan how to add a login page to this project
```

When Claude finishes the plan and exits plan mode, the `ExitPlanMode` hook fires automatically. Gemini's validator reviews the plan and either approves it (you proceed normally) or blocks with specific gaps to address.

## Step 5: Try manual validation

You can validate anything on demand:

```
/gemini-plugin:gemini-validate Is my authentication flow handling token refresh correctly?
```

The validator spawns, calls Gemini, and returns a structured verdict with gaps, hallucinations (if any), and recommended next actions.

## Step 6: Try grounded research

Ask a question that benefits from live web data:

```
/gemini-plugin:gemini-research What is the latest stable version of Next.js?
```

The researcher returns an answer with citations and a freshness timestamp.

## Step 7: Enable brainstorming mode (optional)

If you're in a design session and want every prompt grounded automatically:

```
/gemini-plugin:gemini-brainstorm-on
```

Now every prompt you type gets search-grounded by Gemini before Claude answers. Turn it off when done:

```
/gemini-plugin:gemini-brainstorm-off
```

## What happens next

With the plugin active, six hooks fire automatically at key moments:

1. **Session start** builds a risk map of your repo
2. **User prompt** grounds post-cutoff questions (keyword-gated, or always-on in brainstorm mode)
3. **Plan complete** validates plans before you see them
4. **Destructive Bash** challenges dangerous commands before execution
5. **Pre-compact** preserves session state before context compaction
6. **Stop** audits "done" claims before Claude stops working

All of these block Claude when Gemini finds issues, surfacing the critique inline so you never miss it.

## Next steps

- [How to validate plans and claims](how-to/validate-plans.md) for detailed usage patterns
- [How to configure hooks](how-to/configure-hooks.md) to disable or customize triggers
- [Architecture reference](reference/architecture.md) for understanding the full system
