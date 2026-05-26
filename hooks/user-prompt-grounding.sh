#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/prompt-builder.sh"

check_plugin_enabled
check_gemini_available
ensure_data_dir

INPUT=$(cat)
USER_PROMPT=$(echo "$INPUT" | jq -r '.prompt // empty')

if [ -z "$USER_PROMPT" ]; then
  exit 0
fi

# Gate logic: always-on during brainstorming, regex-gated otherwise
if ! is_brainstorming; then
  if ! echo "$USER_PROMPT" | grep -qiE '\b(api|cve|version|release|deprecated|library|package|sdk|framework|upgrade|migrate)\b'; then
    exit 0
  fi
fi

DIRECTIVE=$(build_grounding_directive "$USER_PROMPT")
echo "$DIRECTIVE" >&2
exit 2
