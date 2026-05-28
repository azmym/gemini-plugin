#!/usr/bin/env bash
# PreToolUse(ExitPlanMode) hook: when Claude exits plan mode, ask it
# to spawn gemini-validator to review the plan for gaps and
# hallucinations before the user sees it.
#
# Pattern: exit 0 + JSON with hookSpecificOutput.additionalContext.
# We do NOT deny the ExitPlanMode tool call (the plan should still
# reach the user); we just inject the directive so Claude spawns the
# validator alongside.
set -euo pipefail
trap 'echo "[gemini-plugin] plan-complete crashed at line ${LINENO} (last command: ${BASH_COMMAND})" >&2; exit 0' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/prompt-builder.sh"

check_plugin_enabled
check_gemini_available
ensure_data_dir

INPUT=$(cat)
# PreToolUse(ExitPlanMode) puts the plan text in tool_input.plan;
# accept legacy .plan / .content keys for direct invocation in tests.
PLAN_TEXT=$(echo "$INPUT" | jq -r '.tool_input.plan // .plan // .content // empty')

if [ -z "$PLAN_TEXT" ]; then
  exit 0
fi

HISTORY=$(get_plan_history "VALIDATE_PLAN" 3)
DIRECTIVE=$(build_plan_validation_directive "$PLAN_TEXT" "$HISTORY")

jq -n --arg ctx "$DIRECTIVE" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    additionalContext: $ctx
  }
}'
exit 0
