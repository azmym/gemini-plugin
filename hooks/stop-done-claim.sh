#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/prompt-builder.sh"

check_plugin_enabled
check_gemini_available
ensure_data_dir

INPUT=$(cat)
ASSISTANT_MESSAGE=$(echo "$INPUT" | jq -r '.assistant_message // .content // empty')
ORIGINAL_ASK=$(echo "$INPUT" | jq -r '.original_ask // empty')
TOOL_USED=$(echo "$INPUT" | jq -r '.tool_used // "false"')

# Only fire if a tool was used in this session
if [ "$TOOL_USED" != "true" ]; then
  exit 0
fi

# Claim detector: check for completion language
if ! echo "$ASSISTANT_MESSAGE" | grep -qiE '\b(done|completed|finished|ready|fixed|passing|resolved|implemented)\b'; then
  exit 0
fi

DIFF_SUMMARY=$(git diff --stat HEAD~1 2>/dev/null | tail -20 || echo "(no git diff available)")
DIRECTIVE=$(build_done_claim_directive "$ORIGINAL_ASK" "$ASSISTANT_MESSAGE" "$DIFF_SUMMARY")
echo "$DIRECTIVE" >&2
exit 2
