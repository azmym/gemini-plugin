#!/usr/bin/env bash
# Stop hook: when Claude claims completion, ask it to spawn
# gemini-validator to audit the output against the original ask.
#
# Pattern: exit 0 + JSON with `decision: block` + `reason` +
# `hookSpecificOutput.additionalContext`. The block prevents Claude
# from stopping until the validator's verdict comes back; the
# additionalContext gives Claude the directive to spawn the
# validator; the reason explains to the user what's happening.
set -euo pipefail
trap 'echo "[gemini-plugin] stop-done-claim crashed at line ${LINENO} (last command: ${BASH_COMMAND})" >&2; exit 0' ERR

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

DIFF_SUMMARY=$(build_diff_summary)
[ -z "$DIFF_SUMMARY" ] && DIFF_SUMMARY="(no git diff available)"
DIRECTIVE=$(build_done_claim_directive "$ORIGINAL_ASK" "$ASSISTANT_MESSAGE" "$DIFF_SUMMARY")
REASON="gemini-plugin: validating done-claim against the original ask before stopping. @agent-gemini-plugin:gemini-validator will return a structured verdict."

jq -n --arg ctx "$DIRECTIVE" --arg reason "$REASON" '{
  decision: "block",
  reason: $reason,
  hookSpecificOutput: {
    hookEventName: "Stop",
    additionalContext: $ctx
  }
}'
exit 0
