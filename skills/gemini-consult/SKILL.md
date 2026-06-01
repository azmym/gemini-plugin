---
description: Dispatch rule for consulting the five Gemini agents. Read this when deciding whether to get a Gemini second opinion and which agent to route to (researcher, validator, challenger, summarizer, reviewer). Enforces a one-consult-per-turn cap on manual dispatches.
---

# Gemini Consult (dispatch rule)

This skill tells you (the main Claude) WHEN to consult Gemini, WHICH of the five
agents to dispatch, and the cap that keeps consults cheap. It complements
`gemini-when-to-use` (which routes among the seven capability *skills* for raw
MCP calls); this skill routes among the five *agents* for structured,
second-opinion work.

Gemini complements your reasoning. It does not replace it.

## When to consult

Dispatch a Gemini agent when ANY of these is true:

- **Uncertain about a plausibly post-cutoff fact** (library version, API shape,
  CVE, pricing, changelog). Route to gemini-researcher.
- **A specific claim needs external verification** before you rely on it. Route
  to gemini-validator.
- **Two or more valid approaches are on the table** and you want an
  outside-the-context-window opinion. Route to gemini-challenger.
- **Finalizing a diff or PR** for cross-cutting concerns (security, threading,
  version drift, doc accuracy, dead code, complexity). Route to gemini-reviewer.
- **About to compact or hand off a long session** and want the state preserved.
  Route to gemini-summarizer.

## Routing table

| Need | Agent |
|---|---|
| Live facts / citations | gemini-researcher |
| Verify a specific claim | gemini-validator |
| Challenge a decision / alternatives | gemini-challenger |
| Generalist diff / PR review | gemini-reviewer |
| Compress session / risk map | gemini-summarizer |

Agents do not call each other (subagents cannot spawn subagents). You are the
router: pick the one agent that matches and dispatch it.

## Deferred Gemini tools in heavy-MCP sessions

When many MCP servers are connected, Claude Code *defers* MCP tools: the Gemini
tool names appear in a system reminder, but their schemas are not loaded and a
direct call fails. An agent must call `ToolSearch` (keyword query such as
`gemini search grounded`) to materialize the schema before invoking the tool.
The five agents already document this step in their own "Tool availability"
section, so dispatch them normally. But if an agent's JSON comes back with
`confidence: "unavailable"` / `verdict: "unknown"` and an `error` mentioning a
missing Gemini tool, do NOT assume the server is down: first run
`/gemini-plugin:gemini-doctor`. If doctor's check 2 passes but check 3 fails,
the session is stale (restart Claude Code); if both pass, retry the dispatch.

## The one-consult-per-turn cap

At most ONE manual, rule-driven Gemini consult per turn, across all five agents.
Each consult adds latency and tokens; the value comes from being selective.

This cap counts only the consults YOU choose to dispatch from this rule. The
always-on hooks (session-start risk map, per-prompt grounding, plan validation,
destructive-op challenge, pre-compact summary, done-claim validation) are a
SEPARATE channel and are NOT counted against this cap. To quiet the automatic
channel, the user can run `/gemini-plugin:gemini-brainstorm-off`.

## Do NOT consult when

- The user said "no Gemini", "skip validation", or "just do it".
- The fact is project-internal (repo state, file contents, build output) and you
  can Read it directly.
- You already have direct evidence (a file Read, command output) that settles
  the question.
- The same question was already consulted earlier this turn.

## Disagreement protocol

If a Gemini agent contradicts your draft:

1. Do NOT silently defer.
2. Surface BOTH positions to the user with their citations.
3. The user picks. If the user has no preference, default to Gemini's position
   when its citation is concrete and recent (post-2024); default to yours when
   Gemini's citation is stale or low-quality.

## Do NOT use this skill for

- Making raw Gemini MCP calls (use the capability skills via `gemini-when-to-use`).
- Non-Gemini routing decisions.
