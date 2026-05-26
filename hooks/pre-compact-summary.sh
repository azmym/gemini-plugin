#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/prompt-builder.sh"

check_plugin_enabled
check_gemini_available
ensure_data_dir

INPUT=$(cat)
SESSION_CONTEXT=$(echo "$INPUT" | jq -r '.context // .content // empty' | tail -c 16384)

if [ -z "$SESSION_CONTEXT" ]; then
  exit 0
fi

DIRECTIVE=$(build_precompact_directive "$SESSION_CONTEXT")
echo "$DIRECTIVE" >&2
exit 2
