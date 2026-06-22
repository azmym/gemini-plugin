#!/usr/bin/env bash
# Shared helpers for all hook scripts.

# Check if a Gemini API key is available in the hook's environment.
# Claude Code exposes userConfig values as CLAUDE_PLUGIN_OPTION_<KEY>; the
# legacy GEMINI_API_KEY env var is accepted as a fallback for users who
# export it manually. If neither is set, print an advisory and exit 0
# (never block work just because the key is absent).
check_gemini_available() {
  if [ -z "${CLAUDE_PLUGIN_OPTION_GEMINI_API_KEY:-${GEMINI_API_KEY:-}}" ]; then
    echo "[gemini-plugin] Gemini API key not configured; skipping consultation." >&2
    exit 0
  fi
}

# Check if plugin disable env is set.
check_plugin_enabled() {
  if [ "${CLAUDE_PLUGIN_GEMINI_DISABLE_HOOKS:-0}" = "1" ]; then
    exit 0
  fi
}

# Resolve the plugin data directory. Returns CLAUDE_PLUGIN_DATA when set
# (Claude Code provides this for plugin hooks), otherwise falls back to
# ~/.claude/plugins/data/gemini-plugin so state survives reboots and
# stays out of /tmp. The default expansion (:-) is required because hook
# scripts run with `set -u`, which crashes on unset variables.
data_dir() {
  echo "${CLAUDE_PLUGIN_DATA:-${HOME}/.claude/plugins/data/gemini-plugin}"
}

# Ensure the plugin data directory exists.
ensure_data_dir() {
  mkdir -p "$(data_dir)"
}

# Compute a short hash of the git repo root for cache keying.
repo_hash() {
  local root
  root=$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")
  echo -n "$root" | shasum -a 256 | cut -c1-12
}

# Detect if brainstorming mode is active.
#
# As of v0.2.0 brainstorming is ON by default (every UserPromptSubmit
# is grounded). Users opt OUT by creating `brainstorm.off` in the data
# directory; that file is the kill switch.
#
# Two-file convention for forwards compatibility:
#   brainstorm.off  → present means OFF (overrides everything else)
#   brainstorm.lock → legacy explicit-on flag from v0.1.x; still honored
#                     but a no-op in practice since default is now ON
#
# Returns 0 (brainstorming active) when neither file blocks it.
is_brainstorming() {
  local data
  data="$(data_dir)"
  if [ -f "${data}/brainstorm.off" ]; then
    return 1
  fi
  return 0
}

# Read the last N plan-history entries for a specific task type.
get_plan_history() {
  local task_type="$1"
  local count="${2:-3}"
  local history_file
  history_file="$(data_dir)/plan-history.jsonl"

  if [ ! -f "$history_file" ]; then
    echo "[]"
    return
  fi

  grep "\"task\":\"${task_type}\"" "$history_file" | tail -n "$count" | jq -s '.'
}

# Matches a command string against destructive patterns.
# Returns 0 if destructive, 1 if safe.
# Patterns are intentionally narrow to keep false-positive rate low.
is_destructive_command() {
  local cmd="$1"
  echo "$cmd" | grep -qE '\brm\s+-[a-zA-Z]*[rRf]|\bgit\s+reset\s+--hard\b|\bgit\s+push\s+[^|;]*--force\b|\bDROP\s+(TABLE|DATABASE|SCHEMA)\b|\bTRUNCATE\s+TABLE\b|\bdd\s+if=|>\s*/dev/sd[a-z]'
}

# Default design-artifact globs (colon-separated). Overridable via
# CLAUDE_PLUGIN_GEMINI_DESIGN_GLOBS. Most globs start with */ so they match a
# path whether it is absolute or repo-relative; the bare *-plan.md entry matches
# a file ending in -plan.md at any depth (including the repo root). A path
# matches if it matches ANY glob. In [[ $x == $glob ]], * matches across slashes.
DEFAULT_DESIGN_GLOBS="*/superpowers/specs/*-design.md:*/superpowers/plans/*.md:*-plan.md:*/specs/*.md:*/plans/*.md:*/DESIGN.md:*/PLAN.md"

is_design_artifact() {
  local path="$1"
  local globs="${CLAUDE_PLUGIN_GEMINI_DESIGN_GLOBS:-$DEFAULT_DESIGN_GLOBS}"
  local IFS=':'
  local g
  for g in $globs; do
    [ -z "$g" ] && continue
    # shellcheck disable=SC2053
    if [[ "$path" == $g ]]; then
      return 0
    fi
  done
  return 1
}

# Record the intended verdict-handling mode ("advisory"|"blocking") for an
# agent about to be dispatched. The verdict-handler consumes it on SubagentStop.
write_pending_mode() {
  local agent="$1"
  local mode="$2"
  mkdir -p "$(data_dir)/pending"
  echo "$mode" > "$(data_dir)/pending/${agent}.mode"
}

# Print and delete the pending mode for an agent. Prints "blocking" if no
# marker exists, which preserves the original blocking plan/done-claim gates.
read_consume_pending_mode() {
  local agent="$1"
  local f
  f="$(data_dir)/pending/${agent}.mode"
  if [ -f "$f" ]; then
    cat "$f"
    rm -f "$f"
  else
    echo "blocking"
  fi
}

# SHA-256 of a file's contents (first field only). Empty if unreadable.
file_content_hash() {
  shasum -a 256 "$1" 2>/dev/null | cut -d' ' -f1
}

# Build a git diff summary for done-claim evidence that survives the cases the
# old `git diff --stat HEAD~1` got wrong:
#   - unborn HEAD (first commit not yet made): show staged work
#   - root commit (no parent): HEAD~1 errors -> fall back to the commit itself
#   - multi-commit task: show the WHOLE branch since it forked from the default
#     branch, not just the last commit
#   - uncommitted work: HEAD~1 ignores the working tree entirely
# Prints "" only when there is genuinely nothing to show; callers substitute a
# placeholder. Default branch is detected as origin/main, main, or master.
build_diff_summary() {
  # No commits yet: show staged work against the empty tree.
  if ! git rev-parse --verify -q HEAD >/dev/null 2>&1; then
    git diff --cached --stat 2>/dev/null | tail -40
    return
  fi
  local uncommitted base committed
  uncommitted=$(git diff --stat HEAD 2>/dev/null | tail -40)
  # Prefer the whole branch since it forked from the default branch (captures
  # multi-commit tasks); fall back to HEAD~1, then to the single commit.
  base=$(git merge-base HEAD origin/main 2>/dev/null \
    || git merge-base HEAD main 2>/dev/null \
    || git merge-base HEAD master 2>/dev/null)
  if [ -n "$base" ] && [ "$base" != "$(git rev-parse HEAD)" ]; then
    committed=$(git diff --stat "${base}..HEAD" 2>/dev/null | tail -40)
  elif git rev-parse --verify -q HEAD~1 >/dev/null 2>&1; then
    committed=$(git diff --stat HEAD~1..HEAD 2>/dev/null | tail -40)
  else
    committed=$(git show --stat --oneline HEAD 2>/dev/null | tail -40)
  fi
  [ -n "$uncommitted" ] && printf 'Uncommitted changes (vs HEAD):\n%s\n\n' "$uncommitted"
  printf 'Committed changes on this branch:\n%s' "${committed:-(none)}"
}

# Path-keyed file storing the last-reviewed content hash for a design artifact.
design_seen_file() {
  local path="$1"
  local pathhash
  pathhash=$(echo -n "$path" | shasum -a 256 | cut -c1-12)
  echo "$(data_dir)/design-review-seen/${pathhash}.sha"
}
