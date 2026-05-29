# Changelog

All notable changes to gemini-plugin are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.4.1] - 2026-05-29

### Fixed

- **Agents could not call Gemini when installed as a plugin.** Plugin-registered MCP servers are namespaced under the plugin (the tool names carry a plugin prefix), but every agent's `tools:` allowlist named the bare un-prefixed form, which does not exist in a plugin session. An agent whose allowlist names only nonexistent tools gets zero Gemini tools and silently falls back to training data (observed: gemini-researcher returned empty citations, low confidence, and a wrong answer). Fixed by removing the `tools:` block from all five agents so they inherit the session's Gemini tools under whatever namespace is registered (works for both plugin and manual installs). Prose and reference docs now use namespace-agnostic short tool names.
- **Agents no longer fabricate when Gemini is unavailable.** Each agent now fails loud: if no Gemini MCP tool is present in the session, it returns `verdict: "unknown"` (researcher: `confidence: "unavailable"`) with an `error` field naming the missing tool, instead of answering from training knowledge.

### Added

- `tests/mcp-namespace.bats` regression guard: forbids a `tools:` key in agent frontmatter and any hardcoded plugin/server MCP namespace path in agents, skills, and hook scripts.

## [0.4.0] - 2026-05-29

### Added

- **`gemini-reviewer` agent (5th subagent).** A generalist third-reviewer for diffs and PRs, covering the cross-cutting concerns the other four agents do not own: security, threading correctness, library/version drift, doc accuracy, dead code, and complexity. Modeled on the `gemini-assistant` "code review" mode from the IPTV project setup. Sonnet, `maxTurns: 10`, returns structured JSON `{verdict, strengths, issues, next_actions}`. It is advisory: a `changes_requested` verdict surfaces inline but does not block, because the reviewer is dispatched manually rather than by a hook.
- **`gemini-consult` dispatch-rule skill (9th skill).** Tells the main Claude when to consult Gemini, which of the five agents to route to, and enforces a one-consult-per-turn cap on manual dispatches (the always-on hooks are a separate, uncounted channel). Ports the disagreement protocol and "what you are NOT" scope guards from the IPTV `gemini-assistant` rule.

### Changed

- `gemini-reviewer` added to the `SubagentStop` matcher so its transcript is read and persisted to plan-history.

## [0.3.0] - 2026-05-28

### Changed

- **All subagent models bumped one tier** to fix partial-response failures where the validator (and others) were exiting before delivering the final JSON verdict.

  | Agent | Before | After |
  |---|---|---|
  | gemini-validator | haiku | sonnet |
  | gemini-challenger | sonnet | opus |
  | gemini-researcher | haiku | sonnet |
  | gemini-summarizer | sonnet | opus |

- **All subagent `maxTurns` doubled** so agents have room to read inputs, call Gemini, verify, and emit JSON without running out of budget mid-response.

  | Agent | Before | After |
  |---|---|---|
  | gemini-validator | 3 | 6 |
  | gemini-challenger | 4 | 8 |
  | gemini-researcher | 6 | 12 |
  | gemini-summarizer | 2 | 4 |

- **Strengthened the "final turn must be JSON only" instruction** in every subagent's system prompt. The verdict-handler hook parses the agent's final assistant message with `jq`; any non-JSON content silently breaks the contract. The new instruction is explicit and includes a turn-budget plan that reserves the last turn exclusively for JSON emission.

### Cost note

Sonnet/Opus per call is 4-5x more expensive than Haiku/Sonnet. Combined with v0.2.0's brainstorm-on-by-default, expect roughly 5-10x higher Gemini cost per session. Use `/gemini-plugin:gemini-brainstorm-off` to reduce researcher invocations to keyword-matching prompts only.

## [0.2.0] - 2026-05-28

### Changed (BREAKING-ISH default)

- **Brainstorming mode is now ON by default.** Every `UserPromptSubmit` triggers a `gemini-researcher` consultation, regardless of whether the prompt matches the narrow keyword regex. This catches a much larger fraction of stale-training-data answers but adds a Gemini call to every prompt. Cost-conscious users can opt out with `/gemini-plugin:gemini-brainstorm-off`.
- **Inverted opt-in flag file.** The `brainstorm.lock` file from v0.1.x is replaced by `brainstorm.off`. The semantics flipped: presence of `brainstorm.off` means "skip grounding unless the prompt matches the keyword gate"; absence means "ground everything". Existing `brainstorm.lock` files are silently ignored (now a no-op since on-by-default).
- `/gemini-plugin:gemini-brainstorm-off` now creates `brainstorm.off`. `/gemini-plugin:gemini-brainstorm-on` removes it (the post-install default state).

### Migration notes

If you had `brainstorm.lock` set in v0.1.x to force grounding, you can delete it (it's a no-op now). If you want LESS grounding than the new default, run `/gemini-plugin:gemini-brainstorm-off` once.

## [0.1.3] - 2026-05-28

Hot-fix release for hook-event/exit-code mismatches found by an audit of every hook against the official Claude Code hooks documentation. The user-visible symptom in v0.1.2 was a wall-of-text "blocked by hook" message on every prompt that contained the words `release`, `app`, `api`, `version`, or several other common operational terms.

### Fixed

- **`user-prompt-grounding.sh`:** switched from `exit 2 + stderr` to `exit 0 + JSON additionalContext`. UserPromptSubmit's exit-2 path **blocks the prompt and erases it**, showing the directive to the user as the block reason. The new pattern lets the prompt proceed and adds the directive to Claude's context discreetly.
- **`user-prompt-grounding.sh`:** narrowed the keyword regex. The old gate matched bare words like `release`, `app`, `api` which fired false positives on prompts like `release="mss-cart-service"` or PromQL queries. The new regex requires **contextual phrases** that strongly imply post-cutoff questions: "latest version of X", "version of X", "CVE-YYYY-NNN", "changelog for X", "deprecated in X", "breaking change in X", "security advisory".
- **`pre-destructive-bash.sh`:** switched to `exit 0 + JSON permissionDecision: deny + additionalContext`. Per the docs, PreToolUse stdout is debug-log-only unless wrapped in JSON; the documented way to block a tool call is `permissionDecision: deny`.
- **`plan-complete.sh`:** switched to `exit 0 + JSON additionalContext`. The plan should still reach the user; only the validator runs alongside.
- **`pre-compact-summary.sh`:** switched to `exit 0 + JSON additionalContext`. The hook no longer blocks compaction; it just injects the summarizer directive.
- **`stop-done-claim.sh`:** switched to `exit 0 + JSON decision: block + additionalContext`. The block prevents Claude from stopping until the validator's verdict comes back; the user sees a clean "validating done-claim" reason.

### Added

- New regression test: `user-prompt-grounding: regression - operational prompts with release= and app= do NOT trigger`.
- New tests for CVE matching and "changelog for X" phrasing.
- All hook scripts now have a `trap ... ERR` that writes a diagnostic line to stderr instead of crashing silently.

## [0.1.2] - 2026-05-28

Hot-fix release. v0.1.1 was correct in isolation but failed on real session startup with the error `SessionStart:startup hook error: Failed with non-blocking status code: No stderr output`. Three combining bugs.

### Fixed

- **SessionStart hook crash on `set -u`:** `session-start-risk-map.sh` and `subagent-verdict-handler.sh` referenced `${CLAUDE_PLUGIN_DATA}` directly. When the env var was unset (which happened in real session-start contexts even though the docs imply it's always set), `set -u` crashed the script with "unbound variable", non-zero exit, and no stderr.
- **SessionStart wrong exit-code convention:** the hook used `exit 2` + stderr to inject its directive. Per the Claude Code hooks docs, `SessionStart` does not honor `exit 2` as a block signal; the supported way to inject context is `exit 0` with the directive on **stdout** (where it becomes `additionalContext` for the session). Even on success, users saw a misleading "hook error" line in the session UI.
- **Silent crashes:** added `trap ... ERR` handlers to both hooks so any future failure writes a diagnostic line to stderr instead of producing the cryptic "No stderr output" error.

### Added

- New `data_dir()` helper in `lib/common.sh` that returns `CLAUDE_PLUGIN_DATA` when set, falling back to `~/.claude/plugins/data/gemini-plugin` (state survives reboots and never lands in `/tmp`).
- Regression test: `session-start: does not crash when CLAUDE_PLUGIN_DATA is unset`. 70 tests total.

## [0.1.1] - 2026-05-28

First usable release. v0.1.0 was tagged but never published as a GitHub Release because a Gemini-led audit caught critical Claude Code integration bugs.

### Fixed

- **State directory env var:** renamed `CLAUDE_PLUGIN_DATA_DIR` to `CLAUDE_PLUGIN_DATA` (the actual variable Claude Code sets). Hook state now persists correctly instead of being lost in `/tmp` on every reboot.
- **API key check:** hooks now read `CLAUDE_PLUGIN_OPTION_GEMINI_API_KEY` (the variable Claude Code exports from `userConfig`), with `GEMINI_API_KEY` as a fallback for users who export it manually. Without this fix, every hook silently no-opped.
- **Plan validation hook:** moved from the invalid `ExitPlanMode` event to `PreToolUse` with `matcher: ExitPlanMode`. Plans now actually get validated.
- **Risk-map persistence:** SessionStart hook writes a placeholder file before exiting, so the 24h TTL gate fires on subsequent sessions instead of blocking every session forever.
- **Destructive-command false positives:** tightened regex so `git pull --force`, `npm install --force`, and commit messages containing the word "drop" no longer trigger the challenger.

### Added

- New bats tests for false-positive guards and the persistence behavior (69 tests total, all passing).

## [0.1.0] - 2026-05-26

### Added

- Initial release.
- Plugin manifest with `userConfig` for API key prompting at install time.
- 8 task-oriented skills (`gemini-when-to-use`, `gemini-chat-and-reason`, `gemini-research-grounded`, `gemini-file-analysis`, `gemini-code-exec`, `gemini-image-gen`, `gemini-video-gen`, `gemini-audio-tts-music`).
- 4 subagents (`gemini-validator`, `gemini-challenger`, `gemini-researcher`, `gemini-summarizer`) with structured JSON output schemas.
- 7 hooks (6 auto-triggers + 1 verdict handler).
- 5 slash commands (`/gemini-validate`, `/gemini-challenge`, `/gemini-research`, `/gemini-brainstorm-on`, `/gemini-brainstorm-off`).
- 1 session rules file.
- Full docs (Diataxis structure: tutorial, how-to, reference, explanation).

[Unreleased]: https://github.com/azmym/gemini-plugin/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/azmym/gemini-plugin/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/azmym/gemini-plugin/compare/v0.1.3...v0.2.0
[0.1.3]: https://github.com/azmym/gemini-plugin/compare/v0.1.2...v0.1.3
[0.1.2]: https://github.com/azmym/gemini-plugin/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/azmym/gemini-plugin/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/azmym/gemini-plugin/releases/tag/v0.1.0
