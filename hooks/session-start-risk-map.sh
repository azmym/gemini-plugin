#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/prompt-builder.sh"

check_plugin_enabled
check_gemini_available
ensure_data_dir

HASH=$(repo_hash)
RISK_MAP="${CLAUDE_PLUGIN_DATA}/risk-map-${HASH}.json"

# TTL check: skip if risk map exists and is < 24h old
if [ -f "$RISK_MAP" ]; then
  AGE=$(( $(date +%s) - $(stat -f %m "$RISK_MAP" 2>/dev/null || stat -c %Y "$RISK_MAP" 2>/dev/null || echo 0) ))
  if [ "$AGE" -lt 86400 ]; then
    exit 0
  fi
fi

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")
TREE=$(find "$REPO_ROOT" -maxdepth 4 -type f \( -name "*.go" -o -name "*.py" -o -name "*.ts" -o -name "*.js" -o -name "*.java" -o -name "*.kt" \) | head -200 | sed "s|${REPO_ROOT}/||" | sort)

DIRECTIVE=$(build_risk_map_directive "$REPO_ROOT" "$TREE")
echo "$DIRECTIVE" >&2

# Persist a TTL marker so the next session start (within 24h) skips the
# directive emission. The summarizer subagent is expected to overwrite
# this file with the actual risk-map JSON; the placeholder ensures the
# TTL gate works even if the subagent never writes (denied, errored, etc).
printf '{"placeholder":true,"updated_at":"%s"}\n' \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$RISK_MAP"

exit 2
