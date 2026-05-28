#!/usr/bin/env bash
# UserPromptSubmit hook: when the user's prompt looks like it depends on
# post-training-cutoff information, inject a directive asking Claude to
# spawn gemini-researcher for live-web grounding.
#
# IMPORTANT: per the Claude Code hooks docs, UserPromptSubmit's
# exit 2 + stderr path BLOCKS the prompt and erases it from context,
# showing the stderr text to the user as a "blocked by hook" message.
# That's the wrong UX for context injection. The correct pattern is
# exit 0 + stdout (additionalContext), which lets the prompt proceed
# AND adds the directive to Claude's context.
set -euo pipefail
trap 'echo "[gemini-plugin] user-prompt-grounding crashed at line ${LINENO} (last command: ${BASH_COMMAND})" >&2; exit 0' ERR

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

# Gate logic. Two changes from earlier versions:
# 1. Brainstorming-mode check stays unconditional.
# 2. The keyword regex is much narrower. The earlier version matched
#    bare words like \brelease\b and \bapp\b which fired on prompts
#    like `release="mss-cart-service-app"`, producing false positives
#    for any operational/observability work. We now require keyword
#    *contexts* that strongly imply a question about live web data:
#    "X version", "version of X", "latest X", "CVE-..", or "X release"
#    where X is a library/framework/SDK name.
if ! is_brainstorming; then
  if ! echo "$USER_PROMPT" | grep -qiE '\b(latest|newest|current|recent)\s+(version|release|stable)\b|\bversion\s+of\b|\bCVE-\d{4}-\d+\b|\bsemver\b|\bchangelog\s+for\b|\bdeprecated\s+in\b|\bbreaking\s+change\s+in\b|\bsecurity\s+advisory\b'; then
    exit 0
  fi
fi

DIRECTIVE=$(build_grounding_directive "$USER_PROMPT")

# Emit JSON with hookSpecificOutput.additionalContext so the directive is
# added to Claude's context discreetly, not shown to the user as the
# "blocked by hook" message. Exit 0 lets the prompt proceed.
jq -n --arg ctx "$DIRECTIVE" '{
  hookSpecificOutput: {
    hookEventName: "UserPromptSubmit",
    additionalContext: $ctx
  }
}'
exit 0
