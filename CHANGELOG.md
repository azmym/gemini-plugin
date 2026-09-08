# Changelog

All notable changes to gemini-plugin are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- **`/gemini-doctor` reported PASS and FAIL verdicts it never observed, sending users to fix things that were not broken.** The command had no way to say "this check did not run", so every check was forced into PASS or FAIL. Three separate defects followed from that, and all three fired at once in a real session: a rejected subagent spawn was reported as check 3 FAIL, which reads as "subagent grounding is broken" when grounding was in fact healthy and the check simply never executed; check 2 reported a resolved tool name of `mcp__plugin_gemini-plugin_gemini__gemini_search_grounded`, a name hardcoded in the command file that does not exist on every host, so the reported name came from the instructions rather than from the host; and check 4 read `${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json`, which silently fell back to the current directory when that variable is unset, reporting the working copy version (`0.8.1`) as the installed version while the loaded copy was `0.8.0`.

  The command now reports `PASS`, `FAIL`, or `INCONCLUSIVE`, and every check must print an `Evidence:` line quoting the raw output it saw. A verdict with no evidence is `INCONCLUSIVE` by rule. Check 2 resolves the grounded-search tool by matching the tool name suffix `gemini_search_grounded` with any prefix, instead of assuming a namespace, and reports the name verbatim from the host. Check 3 separates "the researcher ran and reported no tool" (`FAIL`) from "the spawn never completed" (`INCONCLUSIVE`), and a stale session is claimed only on a genuine `FAIL`. Check 4 searches the known plugin locations, reports each version with the path it came from, and reports `VERSION DRIFT` when two paths disagree.

- **Namespace-agnostic tool naming is now enforced in `commands/` too.** `tests/mcp-namespace.bats` already banned hardcoded `mcp__` paths in agents, skills, and hook scripts, but `commands/` was outside that ban, which is how the doctor's hardcoded namespace survived. The ban now covers command files, and a test asserts the doctor offers `INCONCLUSIVE` and requires per-check evidence. Suite is 123 tests, up from 120.

## [0.8.1] - 2026-09-06

### Fixed

- **New AI Studio `AQ.` Authorization keys were rejected; gemini-mcp pin bumped from `v0.3.0` to `v0.3.1`.** Google AI Studio now issues Authorization keys starting with `AQ.` instead of the legacy `AIza` format. The server was already format-agnostic (the key is passed through to `google-genai`, which sends it via the `x-goog-api-key` header `AQ.` keys require), but the pin and docs now state that compatibility explicitly. The only functional changes are the tag and a `google-genai` floor raise to `>=2.18.1`, the version verified against `AQ.` keys; older 2.x releases may predate them. Both the new `AQ.` format and legacy `AIza` keys work with no configuration difference.

  **Requires a fresh Claude Code session:** the MCP server is launched at session start, so an existing session keeps running the old `v0.3.0` process.

## [0.8.0] - 2026-08-14

### Fixed

- **File analysis was returning 403 on every default call; gemini-mcp pin bumped from `v0.2.2` to `v0.3.0`.** `gemini_analyze_file` routed every request through Google's Files API, and Gemini 3.x models reject Files API references with `403 PERMISSION_DENIED` ("The caller does not have permission") even for a file the same API key uploaded successfully seconds earlier. Only `gemini-2.5-*` models accept those references. Because the tool defaults to `gemini-3.1-pro-preview`, the tool failed unless a caller happened to pass a 2.5 model, which took `gemini-file-analysis` and any PDF, image, audio, or video question with it.

  The upload itself was never the problem, which is what made this read as a credentials fault: `files.upload` and `files.list` both succeed, and the same uploaded file works on `gemini-2.5-flash`. The 403 comes from `generateContent` when a file reference reaches a 3.x model, and it reproduces on `gemini-3.1-flash-lite`, `gemini-3.1-pro-preview`, `gemini-3.5-flash`, `gemini-3.6-flash`, and `gemini-3.7-flash` alike. Passing the SDK file object and passing an explicit `Part.from_uri` both fail, so the reference itself is refused rather than the way it is wrapped.

  Upstream fix (azmym/gemini-mcp#9) sends files at or under 15MB inline as bytes, the path that works on every model, and keeps the Files API as a fallback above that threshold. Responses gain an `inline` flag reporting which path served the call, with `file_uri` empty when nothing was uploaded. Verified live across text, PDF, and PNG on both `gemini-3.1-pro-preview` and `gemini-3.7-flash`: all six combinations that previously returned 403 now answer correctly.

  Files larger than 15MB still need an explicit `gemini-2.5-*` model, because the Files API fallback inherits the same 403. That one needs Google to accept file references on 3.x models.

### Changed

- **Model defaults moved to the current generation.** Grounded search and chat now default to `gemini-3.7-flash` instead of `gemini-3.5-flash`, and both image tools move off preview IDs to `gemini-3.1-flash-image` now that a GA equivalent is served (azmym/gemini-mcp#8). Every ID was called against the live API before becoming a default.

  Reasoning-tier defaults are deliberately left on `gemini-3.1-pro-preview` (`gemini_generate`, `gemini_analyze_file`, `gemini_code_execute`). Gemini 3.7 ships flash-only, with no `gemini-3.7-pro` in the served model list, so pointing those tools at a flash model would trade reasoning depth for speed rather than upgrade them. Callers who want flash on those paths can still pass `model=` or set `GEMINI_DEFAULT_MODEL`.

  This is a minor rather than a patch release because the defaults are user-visible: anyone who never pinned a model will see different behavior, latency, and cost.

  **Requires a fresh Claude Code session:** the MCP server is launched at session start, so an existing session keeps running the old `v0.2.2` process.

## [0.7.1] - 2026-08-14

### Fixed

- **Deep research was unusable; gemini-mcp pin bumped from `v0.2.1` to `v0.2.2`.** Every `deep-research-*` model returned `400 INVALID_ARGUMENT: This model only supports Interactions API`, so `gemini_start_research` could never produce a report and `/gemini-plugin:gemini-research --deep` silently degraded to whatever the caller fell back to. The defect was entirely in the pinned MCP server (azmym/gemini-mcp#7), which called `models.generate_content()` for models that are only served by the Interactions API; this repo contains no API-calling code, so the only change here is the pin. Note that `gemini_list_models` was not the culprit despite appearances: it faithfully echoes upstream metadata, which does advertise `generateContent` for these models, so the false capability signal is Google's and no check on this side could have caught it.

  Upstream fix routes deep-research IDs to `interactions.create(agent=..., background=True)`, maps the interaction status enum explicitly (a `failed` or `budget_exceeded` interaction previously read as done), returns the API's own interaction ID so a handle survives an MCP server restart, and raises the `google-genai` floor to `>=2.0.0` because the service refuses the legacy interactions schema below that. Deep research verified end to end against the live API before the pin moved.

  **Requires a fresh Claude Code session:** the MCP server is launched at session start, so an existing session keeps running the old `v0.2.1` process.

## [0.7.0] - 2026-08-11

### Changed

- **`rm` is no longer a destructive pattern.** `is_destructive_command` matched `rm -[rRf]`, which made it the highest-volume trigger in the set while almost none of its hits were the case worth guarding: scratch directories under `/tmp`, `rm -rf node_modules`, and, because the gate is a plain `grep` over the raw command string with no notion of quoting, every command that merely *named* the flags (`echo "never rm -rf the repo"`, a `grep` for the pattern, a bats fixture containing it). Since the hook answers with `permissionDecision: deny`, each hit cost a turn, and the reliable response was to reword the command until the regex stopped matching, which bought no safety and trained evasion of the gate. The narrower patterns (`git reset --hard`, force push, `DROP TABLE`/`DATABASE`/`SCHEMA`, `TRUNCATE TABLE`, `dd if=`, block-device redirect) are unchanged. The deny message no longer advertises `rm -rf`.

  **Tradeoff:** a genuinely destructive `rm -rf` on a real path now runs without a challenge. The quote-versus-execute blindness is unfixed for the remaining patterns, so a read-only `grep -r "TRUNCATE TABLE"` is still denied.

- **gemini-mcp pin bumped from `v0.2.0` to `v0.2.1`.** The plugin manifest pins the MCP server by tag rather than floating on `main`, so picking up an upstream release is an explicit change here. This bump landed in the manifest without a changelog entry, which would have shipped it undocumented; the reference docs that still quoted the old pin (`docs/index.md`, `docs/reference/architecture.md`, `docs/explanation/design-decisions.md`) now match the manifest.

### Fixed

- **The risk map was silently never built in any sizeable repo.** `session-start-risk-map.sh` piped `find` into `head -200` to cap the directory tree. `head` closes the pipe as soon as it has its 200 lines, so `find` dies of SIGPIPE (exit 141) whenever more files match; `set -o pipefail` promoted that to the pipeline's status, `set -e` fired the ERR trap, and the hook exited 0 having emitted no directive. Because the trap converted the crash into a clean skip, there was no error to notice: the risk map was simply absent, in exactly the large repos it is most useful for. Fixed by scoping `set +o pipefail` to that one pipeline, which the surrounding command substitution already isolates in a subshell. Added a bats regression test that builds a tree large enough to overflow the 64KB pipe buffer, the condition the existing session-start tests could never hit because this repo contains no matching source files.

## [0.6.1] - 2026-06-22

### Fixed

- **Done-claim validation received empty or misleading diff evidence.** `stop-done-claim.sh` summarized the work with `git diff --stat HEAD~1`, which produced nothing usable in four common cases: an unborn HEAD (the first commit not yet made), a root commit (no parent, so `HEAD~1` errors out), a multi-commit task (only the most recent commit was shown, hiding the rest of the work), and uncommitted changes (`HEAD~1` ignores the working tree entirely). In each case the gemini-validator was handed weak evidence to audit the "done" claim against. Fixed by adding `build_diff_summary()` to `hooks/lib/common.sh`: it shows staged work on an unborn HEAD, uncommitted changes against HEAD, and the whole branch since it forked from the default branch (detected as `origin/main`, `main`, or `master`), falling back to `HEAD~1` and then the single commit when no fork point exists.

## [0.6.0] - 2026-06-02

### Added

- **Automatic design-review pass.** Whenever a design/plan artifact is written (a `*-design.md` spec, a `*-plan.md`, or a file under a `specs/`/`plans/` directory) via a new `PostToolUse(Write|Edit)` hook, or when native plan mode exits, the plugin asks Claude to dispatch gemini-validator (VALIDATE_DESIGN) and gemini-challenger (CHALLENGE_DESIGN) over it. The pass is advisory (findings surface but never block), deduped by file content hash so cosmetic re-edits do not re-fire, exempt from the manual one-consult-per-turn cap (it is part of the uncounted hook channel), and silenced by the existing `CLAUDE_PLUGIN_GEMINI_DISABLE_HOOKS` / `brainstorm.off` kill switch. The artifact globs are overridable via `CLAUDE_PLUGIN_GEMINI_DESIGN_GLOBS`.

### Changed

- **Verdict handling is now per-dispatch advisory-or-blocking.** `subagent-verdict-handler.sh` reads and consumes a per-agent "pending mode" marker written by the dispatching hook. A `fail`/`block` verdict blocks (exit 2) only when the marker is `blocking` (the default when no marker exists, which preserves the plan-validator and done-claim gates); the design-review pass writes `advisory` markers so its findings never halt the flow.
- **Native plan-mode exit now also runs an advisory challenger** alongside the existing blocking plan-validator (the validator gate is unchanged).

## [0.5.1] - 2026-06-01

### Fixed

- **Agents stalled "hunting for the tool name" in sessions with many MCP servers.** When numerous MCP servers are connected, Claude Code switches MCP tools into *deferred* mode: the tool name is shown in a system reminder but its schema is not loaded, so a direct call fails until the caller materializes it via `ToolSearch`. The five agents told themselves to "use the gemini_search_grounded tool" but never mentioned `ToolSearch`, so a subagent in a heavy-MCP session could not find a directly-callable Gemini tool, burned its turn budget hunting for the name, and ended mid-investigation without emitting its JSON, after which the orchestrator fell back to plain web search. This was intermittent because a light session loads the tools directly and a capable model sometimes rediscovers `ToolSearch` unaided. Distinct from the v0.4.1 `tools:`-allowlist bug and from the stale-session case `gemini-doctor` covers. Fixed by adding a "Deferred tools (do this FIRST)" step to each agent's "Tool availability" section: call `ToolSearch` with a namespace-agnostic keyword query (e.g. `gemini search grounded`) to load the schema, then call the exact tool name returned; treat the tool as missing only after `ToolSearch` returns no match.

### Changed

- `gemini-consult` skill documents the deferred-tool path and points to `/gemini-plugin:gemini-doctor` when an agent returns `unavailable`/`unknown` with a missing-tool error.
- `tests/mcp-namespace.bats` now asserts every agent documents the `ToolSearch` deferred-tool step using a keyword query (not a hardcoded `mcp__` path).

## [0.5.0] - 2026-05-29

### Added

- **`/gemini-plugin:gemini-doctor` command.** A one-step self-diagnostic that distinguishes a real Gemini outage from a stale session. It runs four checks: (1) API key configured, (2) the MCP server is reachable from the main agent (resolves the tool under either the plugin namespace `mcp__plugin_gemini-plugin_gemini__*` or the manual-install namespace `mcp__gemini__*`, then calls it for real), (3) the subagent grounding path works by spawning `gemini-researcher` and confirming it actually sees a Gemini tool, and (4) the on-disk plugin version. When checks 1 and 2 pass but check 3 fails, it reports STALE SESSION and tells the user to restart Claude Code. This is the common cause of "grounding produced nothing" reports: the MCP server works, but a session started before a plugin update still has the outdated agent definitions loaded in memory.

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

[Unreleased]: https://github.com/azmym/gemini-plugin/compare/v0.8.1...HEAD
[0.8.1]: https://github.com/azmym/gemini-plugin/compare/v0.8.0...v0.8.1
[0.8.0]: https://github.com/azmym/gemini-plugin/compare/v0.7.1...v0.8.0
[0.7.1]: https://github.com/azmym/gemini-plugin/compare/v0.7.0...v0.7.1
[0.7.0]: https://github.com/azmym/gemini-plugin/compare/v0.6.1...v0.7.0
[0.6.1]: https://github.com/azmym/gemini-plugin/compare/v0.6.0...v0.6.1
[0.6.0]: https://github.com/azmym/gemini-plugin/compare/v0.5.1...v0.6.0
[0.5.1]: https://github.com/azmym/gemini-plugin/compare/v0.5.0...v0.5.1
[0.5.0]: https://github.com/azmym/gemini-plugin/compare/v0.4.1...v0.5.0
[0.4.1]: https://github.com/azmym/gemini-plugin/compare/v0.4.0...v0.4.1
[0.4.0]: https://github.com/azmym/gemini-plugin/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/azmym/gemini-plugin/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/azmym/gemini-plugin/compare/v0.1.3...v0.2.0
[0.1.3]: https://github.com/azmym/gemini-plugin/compare/v0.1.2...v0.1.3
[0.1.2]: https://github.com/azmym/gemini-plugin/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/azmym/gemini-plugin/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/azmym/gemini-plugin/releases/tag/v0.1.0
