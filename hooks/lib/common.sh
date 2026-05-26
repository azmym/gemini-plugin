#!/usr/bin/env bash
# Shared helpers for all hook scripts.

# Check if GEMINI_API_KEY is available. If not, print advisory and exit 0.
check_gemini_available() {
  if [ -z "${GEMINI_API_KEY:-}" ]; then
    echo "[gemini-plugin] GEMINI_API_KEY not set; skipping Gemini consultation." >&2
    exit 0
  fi
}

# Check if plugin disable env is set.
check_plugin_enabled() {
  if [ "${CLAUDE_PLUGIN_GEMINI_DISABLE_HOOKS:-0}" = "1" ]; then
    exit 0
  fi
}

# Ensure CLAUDE_PLUGIN_DATA_DIR exists.
ensure_data_dir() {
  mkdir -p "${CLAUDE_PLUGIN_DATA_DIR:-/tmp/gemini-plugin-data}"
}

# Compute a short hash of the git repo root for cache keying.
repo_hash() {
  local root
  root=$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")
  echo -n "$root" | shasum -a 256 | cut -c1-12
}

# Detect if brainstorming session is active.
# Returns 0 (true) if brainstorming detected, 1 otherwise.
is_brainstorming() {
  local data_dir="${CLAUDE_PLUGIN_DATA_DIR:-/tmp/gemini-plugin-data}"
  # Signal 4: explicit lock file
  if [ -f "${data_dir}/brainstorm.lock" ]; then
    return 0
  fi
  # Signal from stdin context (signals 1-3 checked by caller via prompt content)
  return 1
}

# Read the last N plan-history entries for a specific task type.
get_plan_history() {
  local task_type="$1"
  local count="${2:-3}"
  local data_dir="${CLAUDE_PLUGIN_DATA_DIR:-/tmp/gemini-plugin-data}"
  local history_file="${data_dir}/plan-history.jsonl"

  if [ ! -f "$history_file" ]; then
    echo "[]"
    return
  fi

  grep "\"task\":\"${task_type}\"" "$history_file" | tail -n "$count" | jq -s '.'
}

# Matches a command string against destructive patterns.
# Returns 0 if destructive, 1 if safe.
is_destructive_command() {
  local cmd="$1"
  echo "$cmd" | grep -qE '\brm\s+(-[a-zA-Z]*f|-[a-zA-Z]*r|--force)[a-zA-Z ]*|--force|reset\s+--hard|\bDROP\b|\bTRUNCATE\b|git\s+push\s+.*--force|\bdd\s+if='
}
