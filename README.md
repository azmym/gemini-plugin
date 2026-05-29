<div align="center">

# gemini-plugin

**Give Claude Code a second opinion.** Gemini validates your plans, challenges destructive commands, grounds answers in live web data, reviews diffs, and audits "done" claims before Claude stops working.

[![Version](https://img.shields.io/github/v/release/azmym/gemini-plugin?label=version&color=blue)](https://github.com/azmym/gemini-plugin/releases)
[![License: MIT](https://img.shields.io/badge/license-MIT-green)](LICENSE)
[![Tests](https://github.com/azmym/gemini-plugin/actions/workflows/tests.yml/badge.svg)](https://github.com/azmym/gemini-plugin/actions/workflows/tests.yml)
[![Claude Code](https://img.shields.io/badge/Claude%20Code-plugin-7C3AED)](https://code.claude.com/docs/en/plugins)
[![Marketplace: SynthForge](https://img.shields.io/badge/marketplace-SynthForge-orange)](https://github.com/azmym/SynthForge)
[![Powered by Gemini](https://img.shields.io/badge/powered%20by-Google%20Gemini-4285F4)](https://aistudio.google.com)

[Quickstart](#install) · [Why use it?](#why-use-it) · [Architecture](#architecture-at-a-glance) · [Slash commands](#slash-commands) · [Subagents](#subagents) · [Skills](#skills) · [Auto-triggers](#auto-triggers) · [Docs](#documentation)

</div>

---

## Why use it?

- **Catch mistakes before they ship.** Every plan Claude produces is reviewed by Gemini for gaps and hallucinations before you see it.
- **Stop dangerous commands before they run.** When Claude is about to execute `rm -rf`, a force-push, or a `DROP TABLE`, Gemini proposes safer alternatives and can block execution until you decide.
- **Get answers grounded in today's web.** Questions about library versions, recent CVEs, or live API docs are answered with citations, not training-data guesses.
- **Review diffs and PRs.** A dedicated reviewer agent checks changes for security, threading, version drift, doc accuracy, dead code, and complexity.
- **Keep context alive across compaction.** Before Claude compacts its context, Gemini summarizes decisions, discarded alternatives, and unresolved debt so the next session picks up cleanly.
- **Verify "done" claims.** When Claude says it's finished, Gemini checks the actual output against your original ask and blocks the stop if something was missed.

## At a glance

You ask Claude to delete a branch that was never merged. Instead of running the command immediately, the plugin intercepts it:

```
⚡ gemini-challenger (destructive command detected)

Verdict: block

Alternatives:
  1. Archive the branch instead of deleting it
     git tag archive/<branch-name> <branch-name> && git branch -d <branch-name>
     Tradeoff: takes one extra step, but the ref is recoverable
  2. Create a backup tag first, then delete
     git tag backup/<branch-name> && git branch -D <branch-name>
     Tradeoff: slightly more history noise

Objections:
  - Branch has unmerged commits (checked with git branch --no-merged)

Must address:
  - Confirm: do you have a remote copy of this branch?
```

Claude pauses and shows you the critique inline. You respond, and the session continues from there.

## Install

Distributed via the [SynthForge marketplace](https://github.com/azmym/SynthForge):

```
/plugin marketplace add azmym/SynthForge
/plugin install gemini-plugin@synthforge
```

You will be prompted for your Google AI Studio API key during installation. The key is stored securely in your system keychain (not in any settings file). Get one free at [aistudio.google.com/app/apikey](https://aistudio.google.com/app/apikey).

The plugin auto-registers the `gemini` MCP server. No separate `claude mcp add` step is needed.

> **Heads up on cost.** Brainstorming is on by default (since v0.2.0), so every prompt is grounded with a Gemini call. Combined with the subagent model tiers (Sonnet for validator, researcher, and reviewer; Opus for challenger and summarizer), this is meaningfully more expensive than keyword-only grounding. To dial it back, run `/gemini-plugin:gemini-brainstorm-off` to fall back to keyword-triggered grounding.

## What it does for you

| Situation | What fires | What you get |
|---|---|---|
| You start a session on a new repo | Risk map hook | Gemini scans for fragile zones, missing tests, and risky integrations (cached 24 h) |
| Claude finishes a plan | Plan validation hook | Gemini reviews the plan; blocks if gaps or missed acceptance criteria are found |
| Claude is about to run a destructive command | Destructive command hook | Gemini proposes alternatives; can block execution if a safer path exists |
| You ask about a library version, CVE, or live API | Prompt grounding hook | Gemini searches the web and injects citations before Claude answers |
| Claude is about to compact context | Pre-compact hook | Gemini summarizes decisions and unresolved debt so the next session starts with full context |
| Claude says it is finished | Done-claim hook | Gemini validates output against your original ask; blocks if something was missed |
| You want a second opinion right now | Slash command or consult rule | Any of the five subagents on demand, for any artifact or question |
| You are finalizing a diff or PR | gemini-reviewer (manual consult) | A generalist review for security, threading, version drift, docs, dead code, and complexity |

## Architecture at a glance

<p align="center">
  <img src="assets/infographic.png" alt="gemini-plugin architecture: three layers (hooks coordinate, subagents reason, MCP executes) connecting Claude Code to Gemini" width="900" />
</p>

Three layers do the work: **hooks** coordinate (read events, apply gates, emit directives), **subagents** reason (validator, challenger, researcher, summarizer, and reviewer, each returning a structured JSON verdict), and the **gemini-mcp** server executes (calls Gemini, Imagen, Veo, and Lyria via Google AI Studio). For the full write-up, see [docs/reference/architecture.md](docs/reference/architecture.md).

## The `/gemini-plugin:` menu

When you type `/gemini-plugin:` in Claude Code, the menu shows **two kinds of entries** under one namespace:

- **Slash commands** (5) run a fixed action immediately, often with arguments (for example `/gemini-plugin:gemini-validate src/auth.ts`).
- **Skills** (9) are capability guides. They load on demand when Claude judges them relevant, and they also appear in the menu so you can invoke one explicitly. Skills tell Claude *when* to reach for Gemini and *which* MCP tool to use.

The two are separate surfaces: commands are listed below under [Slash commands](#slash-commands); skills under [Skills](#skills). The work itself is carried out by [Subagents](#subagents) and the MCP tools they call.

## Slash commands

Six commands, all under the `/gemini-plugin:` prefix.

| Command | Arguments | What it does |
|---|---|---|
| `/gemini-plugin:gemini-validate` | `<file path, pasted text, or description>` | Get a Gemini second opinion on a plan, diff, or claim. Returns gaps, hallucinations, and next actions. Spawns `gemini-validator`. |
| `/gemini-plugin:gemini-challenge` | `<decision, approach, or architecture>` | Get Gemini to argue against the current path and propose at least two alternatives with tradeoffs. Spawns `gemini-challenger`. |
| `/gemini-plugin:gemini-research` | `<query> [--deep]` | Quick web search with citations; add `--deep` for multi-source synthesis. Spawns `gemini-researcher`. |
| `/gemini-plugin:gemini-brainstorm-off` | (none) | Opt out of grounding-on-every-prompt; fall back to narrow keyword matching. Recommended for chatty sessions to control cost. |
| `/gemini-plugin:gemini-brainstorm-on` | (none) | Re-enable grounding on every prompt after a previous opt-out (this is the default after install). |
| `/gemini-plugin:gemini-doctor` | (none) | Diagnose whether Gemini grounding works in this session. Checks the API key, the MCP server (main agent), and the subagent path; flags a stale session that needs a restart. |

There is no `gemini-review` command: diff review runs through the `gemini-consult` skill, which dispatches the `gemini-reviewer` subagent. See [Subagents](#subagents).

## Subagents

Five specialized agents do the reasoning. Each runs in its own context, calls Gemini through the MCP server, and returns a structured JSON verdict. They are spawned automatically by hooks, by a slash command, or by the `gemini-consult` dispatch rule. You can also call one directly, for example `@agent-gemini-plugin:gemini-reviewer review the staged diff`.

| Subagent | Model | Role | Usually triggered by |
|---|---|---|---|
| `gemini-validator` | Sonnet | Validates plans, diffs, and done-claims against the original ask; flags gaps and hallucinations | Plan-validation hook, done-claim hook, `/gemini-plugin:gemini-validate` |
| `gemini-challenger` | Opus | Devil's advocate: argues alternatives and objections before destructive or architectural decisions | Destructive-command hook, `/gemini-plugin:gemini-challenge` |
| `gemini-researcher` | Sonnet | Search-grounded facts with citations; never opines without a source URL | Prompt-grounding hook, `/gemini-plugin:gemini-research` |
| `gemini-summarizer` | Opus | Builds repo risk maps and compresses session state across compaction | Session-start hook, pre-compact hook |
| `gemini-reviewer` | Sonnet | Generalist diff/PR review: security, threading, version drift, doc accuracy, dead code, complexity | `gemini-consult` dispatch rule (manual, advisory) |

If a Gemini MCP tool is not available in the session, each agent **fails loud**: it returns `verdict: "unknown"` (the researcher uses `confidence: "unavailable"`) with an `error` field, rather than answering from training data. Full schemas: [docs/reference/subagents.md](docs/reference/subagents.md).

## Skills

Nine skills appear under `/gemini-plugin:` and load on demand. Two are routers (decision guides, no MCP tools of their own); seven map to specific Gemini capabilities.

| Skill | Kind | Use for |
|---|---|---|
| `gemini-when-to-use` | Router | Master router: whether a Gemini consult is warranted, and which capability skill to reach for |
| `gemini-consult` | Router | Routes a consult to the right subagent (researcher, validator, challenger, reviewer, summarizer) and enforces a one-consult-per-turn cap on manual dispatches |
| `gemini-chat-and-reason` | Capability | Second opinions, code review, design critique via `gemini_generate` / `gemini_chat` |
| `gemini-research-grounded` | Capability | Live-web research with citations via `gemini_search_grounded`; deep research via `gemini_start_research` |
| `gemini-file-analysis` | Capability | Multi-modal Q&A over PDFs, images, audio, video, and oversized source files via `gemini_analyze_file` |
| `gemini-code-exec` | Capability | Run Python in Gemini's sandbox to verify math, regex, or algorithms via `gemini_code_execute` |
| `gemini-image-gen` | Capability | Generate images (Nano Banana or Imagen 4) via `gemini_generate_image` |
| `gemini-video-gen` | Capability | Generate short clips with Veo 3.1 (start + poll) via `gemini_start_video` |
| `gemini-audio-tts-music` | Capability | Music (Lyria 3) and text-to-speech via `gemini_generate_music` / `gemini_tts` |

Full details: [docs/reference/skills.md](docs/reference/skills.md).

## Auto-triggers

These fire without any action on your part:

| Trigger | When | What you see |
|---|---|---|
| Session start | Once per project per day | A risk map of high-fragility zones in your repo |
| Prompt grounding | **On every prompt by default** (opt out with `/gemini-plugin:gemini-brainstorm-off`); after opt-out, only on prompts matching narrow patterns like "latest version of X", "CVE-YYYY-NNN", or "changelog for X" | Citations prepended to Claude's answer |
| Plan validation | When Claude exits plan mode | A pass or a list of gaps to address before proceeding |
| Destructive command | Before `rm -rf`, `--force` pushes, `DROP TABLE`, and similar | Alternatives and a block if a safer path exists |
| Pre-compact | Before context compaction | A structured summary of decisions and open work |
| Done-claim check | When Claude signals it has finished | A pass or a list of missed requirements |

## Configuration and disable knobs

**Turn off all hooks:**

```bash
export CLAUDE_PLUGIN_GEMINI_DISABLE_HOOKS=1
```

**Disable one specific agent** (for example, keep validation but not the challenger). Add the agent to `permissions.deny` in your Claude Code settings:

```json
"permissions": {
  "deny": ["Agent(gemini-plugin:gemini-challenger)"]
}
```

**Brainstorm mode (on by default).** Every prompt is grounded in live web data, which catches stale-training-data answers but adds a Gemini call (and a small latency hit) to every prompt, even trivial ones. Manage it with:

```
/gemini-plugin:gemini-brainstorm-off  # opt out: falls back to keyword-only grounding
/gemini-plugin:gemini-brainstorm-on   # re-enable after a previous opt-out
```

When opted out, the grounding hook only fires on prompts that look like questions about post-cutoff information (patterns like `latest version of X`, `CVE-YYYY-NNN`, `changelog for X`, `deprecated in X`).

## Requirements

- Claude Code with plugin support
- A Google AI Studio API key (prompted during install, stored in system keychain)
- `uv` (provides `uvx` for running the MCP server; install at [docs.astral.sh/uv](https://docs.astral.sh/uv))
- `jq` (used by hook scripts; install with `brew install jq` on macOS)

## Documentation

Full documentation is in the [`docs/`](docs/index.md) folder:

| Section | What you will find |
|---|---|
| [Tutorial](docs/tutorial.md) | Install the plugin and run your first validation in under 5 minutes |
| [Validate plans and claims](docs/how-to/validate-plans.md) | Detailed usage patterns for plan and done-claim validation |
| [Research live data](docs/how-to/research-live-data.md) | Ground questions in current web data with citations |
| [Configure hooks](docs/how-to/configure-hooks.md) | Enable, disable, or customize the automatic triggers |
| [Reference](docs/index.md) | Architecture, skills, subagents, hooks, and commands in full detail |
| [Design decisions](docs/explanation/design-decisions.md) | Why single-turn validation, why these gates, cost tradeoffs |

## License

MIT
