# Contributing to gemini-plugin

Thanks for your interest. This document covers how to propose a change, report a bug, or suggest a feature.

## Reporting bugs

Open a [bug report](https://github.com/azmym/gemini-plugin/issues/new?template=bug_report.md) with:

- What you ran and what happened
- What you expected to happen
- Claude Code version (`claude --version`)
- gemini-plugin version (`/plugin list` in Claude Code)
- Relevant hook output, if any (look in `${CLAUDE_PLUGIN_DATA}/plan-history.jsonl`)

## Suggesting features

Open a [feature request](https://github.com/azmym/gemini-plugin/issues/new?template=feature_request.md) describing:

- The problem you're trying to solve
- Why the existing 4 subagents and 6 hooks don't already cover it
- What the user-visible behavior would look like

## Submitting code changes

The `main` branch is protected; all changes go through pull requests.

1. **Fork and branch.** Create a feature branch from `main`: `git checkout -b feat/<topic>` or `fix/<topic>`.
2. **Make your change.** Keep PRs focused on one concern. If you're touching hook scripts, follow the existing `set -euo pipefail` and library-sourcing pattern.
3. **Run the tests.** `bats tests/` from the repo root. All tests must pass. Add tests for any new behavior.
4. **Update docs.** If you add or change a subagent, hook, or command, update the matching file under `docs/reference/`.
5. **Update CHANGELOG.md** under the `[Unreleased]` heading.
6. **Open a PR** with a clear title (`feat:`, `fix:`, `docs:`, `chore:`, `refactor:`, `test:`) and a Summary + Test plan section.

## Releasing

Releases are cut by pushing a version tag. The `Release` workflow (`.github/workflows/release.yml`) does the rest.

1. **Land the version bump.** A merged PR should already have bumped `.claude-plugin/plugin.json` to the new `X.Y.Z` and moved its CHANGELOG entries from `[Unreleased]` into a `## [X.Y.Z] - <date>` section. Follow [SemVer](https://semver.org): MINOR for new backward-compatible features, PATCH for fixes.
2. **Tag `main` and push the tag:**
   ```bash
   git checkout main && git pull
   git tag -a vX.Y.Z -m "vX.Y.Z - <summary>"
   git push origin vX.Y.Z
   ```
3. **The workflow takes over.** On a `v*.*.*` tag push it: verifies the tag matches `plugin.json` (fails loudly if not), extracts the `## [X.Y.Z]` section from `CHANGELOG.md` as the release notes, and creates the GitHub release marked `--latest`.

A merged PR alone does NOT publish a release: the marketplace serves released versions, so an untagged bump never reaches installs. Always push the tag.

## Local development

Install dependencies (macOS):

```bash
brew install bats-core jq uv
```

Clone and run tests:

```bash
git clone https://github.com/azmym/gemini-plugin
cd gemini-plugin
bats tests/
```

## Coding standards

- **Hook scripts** start with `set -euo pipefail`, source `lib/common.sh` and `lib/prompt-builder.sh`, and call `check_plugin_enabled` and `check_gemini_available` early.
- **Tests** follow the existing fixture-based pattern: feed JSON to stdin, assert exit code and stderr content.
- **Docs** follow [Diataxis](https://diataxis.fr/): tutorial for learning, how-to for tasks, reference for facts, explanation for context.
- **No em-dashes or en-dashes** in any output. Use commas, parentheses, or colons.
- **No emojis** in code, docs, or commit messages unless the user explicitly requests them.

## Code of Conduct

This project follows the [Contributor Covenant](https://www.contributor-covenant.org/version/2/1/code_of_conduct/). Be respectful, help newcomers, and assume good faith.

## License

By contributing, you agree that your contributions will be licensed under the [MIT License](LICENSE).
