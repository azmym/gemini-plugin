#!/usr/bin/env bash
# PreToolUse(Bash) hook: when the user/Claude is about to run a
# destructive command, ask Claude to spawn gemini-challenger to
# propose safer alternatives before the command runs.
#
# Pattern: exit 0 + JSON. PreToolUse stdout goes to the debug log
# unless we return a JSON envelope with hookSpecificOutput. Using
# `permissionDecision: deny` blocks the tool call cleanly, while
# `additionalContext` injects the directive into Claude's context so
# it knows to spawn the challenger subagent.
set -euo pipefail
trap 'echo "[gemini-plugin] pre-destructive-bash crashed at line ${LINENO} (last command: ${BASH_COMMAND})" >&2; exit 0' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/prompt-builder.sh"

check_plugin_enabled
check_gemini_available

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

if [ -z "$COMMAND" ]; then
  exit 0
fi

if ! is_destructive_command "$COMMAND"; then
  exit 0
fi

DIRECTIVE=$(build_destructive_challenge_directive "$COMMAND")
REASON="gemini-plugin: this command matches a destructive pattern (rm -rf, force push, DROP TABLE, etc). Spawning @agent-gemini-plugin:gemini-challenger to propose safer alternatives."

jq -n --arg ctx "$DIRECTIVE" --arg reason "$REASON" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: $reason,
    additionalContext: $ctx
  }
}'
exit 0
