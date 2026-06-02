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
# CLAUDE_PLUGIN_GEMINI_DESIGN_GLOBS. Globs use a leading */ so they match a
# path whether it is absolute or repo-relative. A path matches if it matches
# ANY glob. In [[ $x == $glob ]], * matches across slashes.
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
