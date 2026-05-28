#!/usr/bin/env bash
# SessionStart hook: emits a directive asking Claude to spawn
# gemini-summarizer to build a risk map of the current repo. Cached
# 24h per repo via a placeholder file in the plugin data directory.
#
# IMPORTANT: SessionStart cannot be blocked by exit 2 (per the Claude
# Code hooks docs). For SessionStart, the supported way to inject
# context is plain stdout (additionalContext). We exit 0 in all
# success and skip paths.
set -euo pipefail

# Trap any unexpected error to write a diagnostic to stderr instead of
# exiting silently with a non-zero code. Without this, a crash inside
# `set -u` produces "Failed with non-blocking status code: No stderr".
trap 'echo "[gemini-plugin] session-start hook crashed at line ${LINENO} (last command: ${BASH_COMMAND}); skipping risk-map emission." >&2; exit 0' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/prompt-builder.sh"

check_plugin_enabled
check_gemini_available
ensure_data_dir

DATA="$(data_dir)"
HASH=$(repo_hash)
RISK_MAP="${DATA}/risk-map-${HASH}.json"

# TTL check: skip if risk map exists and is < 24h old.
# `date -r FILE +%s` works on both BSD date (macOS) and GNU date (Linux).
if [ -f "$RISK_MAP" ]; then
  MTIME=$(date -r "$RISK_MAP" +%s 2>/dev/null || echo 0)
  AGE=$(( $(date +%s) - MTIME ))
  if [ "$AGE" -lt 86400 ]; then
    exit 0
  fi
fi

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")
TREE=$(find "$REPO_ROOT" -maxdepth 4 -type f \
  \( -name "*.go" -o -name "*.py" -o -name "*.ts" -o -name "*.js" \
     -o -name "*.java" -o -name "*.kt" \) 2>/dev/null \
  | head -200 \
  | sed "s|${REPO_ROOT}/||" \
  | sort)

DIRECTIVE=$(build_risk_map_directive "$REPO_ROOT" "$TREE")

# SessionStart context goes to STDOUT, not stderr (per Claude Code docs).
# Plain stdout is appended to the session's context.
echo "$DIRECTIVE"

# Persist a TTL marker so the next session start (within 24h) skips the
# directive emission. The summarizer subagent is expected to overwrite
# this with the actual risk-map JSON; the placeholder ensures the TTL
# gate works even if the subagent never writes (denied, errored, etc).
printf '{"placeholder":true,"updated_at":"%s"}\n' \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$RISK_MAP"

exit 0
