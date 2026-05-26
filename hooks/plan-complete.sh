#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/prompt-builder.sh"

check_plugin_enabled
check_gemini_available
ensure_data_dir

INPUT=$(cat)
PLAN_TEXT=$(echo "$INPUT" | jq -r '.plan // .content // empty')

if [ -z "$PLAN_TEXT" ]; then
  exit 0
fi

HISTORY=$(get_plan_history "VALIDATE_PLAN" 3)
DIRECTIVE=$(build_plan_validation_directive "$PLAN_TEXT" "$HISTORY")
echo "$DIRECTIVE" >&2
exit 2
