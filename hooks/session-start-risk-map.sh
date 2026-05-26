#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/prompt-builder.sh"

check_plugin_enabled
check_gemini_available
ensure_data_dir

HASH=$(repo_hash)
RISK_MAP="${CLAUDE_PLUGIN_DATA_DIR}/risk-map-${HASH}.json"

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
exit 2
