# Changelog

All notable changes to gemini-plugin are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/azmym/gemini-plugin/compare/v0.1.1...HEAD
[0.1.1]: https://github.com/azmym/gemini-plugin/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/azmym/gemini-plugin/releases/tag/v0.1.0
