# Design Decisions

This document explains the key architectural decisions behind gemini-plugin, the tradeoffs considered, and why specific approaches were chosen.

## Why a three-layer architecture?

The plugin separates hooks (coordination), subagents (reasoning), and MCP (execution) into distinct layers.

**Alternative considered:** hooks calling MCP directly (no subagents). This would be simpler but loses:
- Structured system prompts per role (validator vs challenger vs researcher)
- Tool access control (validator can't write files; challenger can't run Bash)
- maxTurns caps and effort levels per role
- Persistent memory for validator and summarizer

**Alternative considered:** one "gemini-assistant" mega-agent that picks its own mode. This loses:
- Hook-targetable roles (can't tell the SubagentStop handler which schema to expect)
- Independent disabling (can't block the challenger without blocking the validator)
- Cost optimization (different models per role)

The three-layer design keeps each layer focused: hooks don't reason, subagents don't coordinate, MCP doesn't decide.

## Why single-turn validation instead of multi-turn chat?

Plan validation uses `gemini_generate` (stateless, single-turn) with a curated history summary, rather than `gemini_chat` (persistent multi-turn session).

**Failure modes of multi-turn validated by Gemini itself:**

| Issue | Impact |
|---|---|
| State desynchronization | If Claude backtracks or changes branches, the chat session keeps critiquing dead plans |
| Echo chamber | After 3-4 turns, Gemini agrees with its own premises, missing late regressions |
| Token bloat | Each turn appends history; a 20-line plan diff can cost 100k+ tokens in a long session |
| Latency | Same reason: 10s+ per validation in long sessions |

**The hybrid approach:** `gemini_generate` (stateless) with a plugin-curated `<history_summary>` injected into each prompt. The plan-complete hook reads the last 3 entries from `plan-history.jsonl` (rejected plan title + headline reason) and passes them to the validator. This achieves multi-turn's memory without the desync/bloat risks.

## Why block-and-surface (exit 2) instead of advisory?

When Gemini disagrees, the hook blocks Claude by exiting with code 2 and writing the critique to stderr. Claude sees the critique in its next turn and must address it.

**Alternative considered:** advisory-only (exit 0, append to context). This is cheaper and non-intrusive but easy to ignore. Claude can read the advisory and proceed anyway, which defeats the anti-hallucination goal.

**Alternative considered:** N rounds of debate (Claude and Gemini exchange 2-3 turns). Highest quality but highest token cost and slowest. Too expensive for every plan exit.

**Safeguard against infinite blocking:** the loop guard. If the verdict handler sees the exact same fail-verdict JSON twice in a row, it demotes to advisory (exit 0). This prevents the validator from trapping Claude in an unresolvable loop.

## Why keyword-gated UserPromptSubmit?

The grounding hook (search-grounded Gemini) only fires on prompts containing specific keywords (`api`, `cve`, `version`, `release`, `deprecated`, etc.) unless brainstorming mode is on.

**Alternative considered:** fire on every prompt. Too expensive, adds latency to every interaction including trivial "fix this typo" requests.

**Alternative considered:** never auto-fire, manual only. Loses the anti-hallucination value. Claude would confidently answer post-cutoff questions with stale training data.

**The brainstorming override (v0.1.x):** during active design sessions, users could create `brainstorm.lock` to ground every prompt. **As of v0.2.0 the default flipped:** brainstorming is on by default, and users opt out by creating `brainstorm.off` instead. This is where false information is most costly, so the new default catches more of it; cost-conscious users can opt out.

## Why four subagents instead of one?

Each role has fundamentally different:
- **System prompts** (skeptical reviewer vs creative challenger vs fact-finder vs compressor)
- **Tool needs** (validator needs Grep/Glob; researcher needs deep-research polling; challenger needs chat)
- **Model economics** (haiku for high-volume validation; sonnet for creative reasoning)
- **Memory needs** (validator/summarizer accumulate project knowledge; challenger/researcher stay stateless to avoid bias)
- **Blocking behavior** (validator blocks on fail; researcher runs in background for deep research)

One mega-agent would require runtime mode-switching, couldn't be independently disabled, and couldn't have different model/memory/background settings per mode.

## Why Sonnet for validator, Opus for challenger? (Updated v0.3.0)

**v0.1.0 - v0.2.0:** validator was Haiku, challenger was Sonnet, researcher was Haiku, summarizer was Sonnet. The thinking was cost optimization for high-volume validation paths.

**v0.3.0:** all four agents bumped one tier (Haiku → Sonnet, Sonnet → Opus). Reason: real-world failures where the validator subagent returned partial responses without the final JSON verdict, leaving the verdict-handler with nothing to parse. Three combining factors:

1. `maxTurns: 3` was too tight for read + Gemini call + verification + JSON emit
2. Haiku struggled with structured-output reliability on artifact validation
3. The system prompt didn't emphasize "final turn must be JSON only"

The fix doubled `maxTurns` (3→6, 4→8, 6→12, 2→4), bumped models one tier, and tightened the "final-turn-must-be-JSON" instruction. Cost per call is up roughly 4-5x but validator now actually delivers verdicts.

Original cost-optimization rationale (kept for historical context):

```
Volume x Cost matrix:

Validator: fires on every plan exit + every stop = HIGH volume
  → Haiku: fast, cheap, structured-output capable

Challenger: fires only on destructive commands = LOW volume
  → Sonnet: creative reasoning for alternatives justifies cost

Researcher: fires on keyword-matching prompts = MEDIUM volume
  → Haiku: grounded search is simple retrieval, doesn't need reasoning

Summarizer: fires on SessionStart + PreCompact = LOW volume
  → Sonnet: large input compression needs strong reasoning
```

The Claude model (Haiku/Sonnet) handles orchestration and JSON structuring. The Gemini model (accessed via MCP) handles the actual reasoning, web search, and verification.

## Why project memory for validator and summarizer?

These two roles benefit from cross-session learning:
- **Validator** remembers recurring plan gaps in this codebase (e.g., "tests are always missing for the auth module")
- **Summarizer** builds up knowledge about repo structure, risk zones, and common patterns

The challenger and researcher stay memoryless by design:
- **Challenger** must give fresh, unbiased alternatives every time. Memory would anchor it to previous critiques.
- **Researcher** returns current web data. Past research results are stale by definition.

## Why marketplace + same-repo layout?

The plugin and its marketplace catalog live in the same git repository (source: "./"). This means:
- One repo to maintain, one git remote
- Version bumps are atomic (plugin.json version = marketplace awareness)
- Users install from one URL

**Alternative considered:** separate marketplace repo pointing at the plugin repo. Cleaner separation but two repos to maintain, two PRs per release, harder to keep in sync.

**Alternative considered:** multi-plugin marketplace with plugins/ subdirectory. Would support sibling plugins later, but premature for a single plugin.

## Why pin gemini-mcp to v0.2.0?

The plugin manifest pins `gemini-mcp@v0.2.0` rather than floating on `main`.

**Rationale:** gemini-mcp is actively developed. Floating on main means a breaking change upstream silently breaks the plugin for all users. Pinning ensures stability; the gemini-plugin version bump is the explicit upgrade moment.

**Tradeoff:** users don't automatically get new gemini-mcp features (new models, new tools). This is acceptable because the plugin author controls both repos and can bump the pin deliberately.
