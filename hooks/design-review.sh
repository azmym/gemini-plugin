#!/usr/bin/env bash
# PostToolUse(Write|Edit) hook: when a design/plan artifact is written, ask
# Claude to dispatch BOTH gemini-validator (VALIDATE_DESIGN) and
# gemini-challenger (CHALLENGE_DESIGN) as an ADVISORY pass. Deduped by content
# hash so cosmetic re-writes do not re-fire.
#
# Pattern: exit 0 + JSON hookSpecificOutput.additionalContext. PostToolUse runs
# after the write has happened, so it never denies; it only injects context.
set -euo pipefail
trap 'echo "[gemini-plugin] design-review crashed at line ${LINENO} (last command: ${BASH_COMMAND})" >&2; exit 0' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/prompt-builder.sh"

check_plugin_enabled
check_gemini_available
ensure_data_dir

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

[ -z "$FILE_PATH" ] && exit 0
is_design_artifact "$FILE_PATH" || exit 0

# Material-change dedup: skip if content hash matches the last reviewed hash.
SEEN_FILE=$(design_seen_file "$FILE_PATH")
NEW_HASH=$(file_content_hash "$FILE_PATH")
[ -z "$NEW_HASH" ] && exit 0
if [ -f "$SEEN_FILE" ] && [ "$(cat "$SEEN_FILE")" = "$NEW_HASH" ]; then
  exit 0
fi

HISTORY=$(get_plan_history "VALIDATE_DESIGN" 3)
write_pending_mode "gemini-validator" "advisory"
write_pending_mode "gemini-challenger" "advisory"
DIRECTIVE=$(build_design_review_directive "$FILE_PATH" "$HISTORY")

mkdir -p "$(dirname "$SEEN_FILE")"
echo "$NEW_HASH" > "$SEEN_FILE"

jq -n --arg ctx "$DIRECTIVE" '{
  hookSpecificOutput: {
    hookEventName: "PostToolUse",
    additionalContext: $ctx
  }
}'
exit 0
