#!/usr/bin/env bash
# PreCompact hook: before context is compacted, ask Claude to spawn
# gemini-summarizer to produce a structured session summary that
# survives the compaction.
#
# Pattern: exit 0 + JSON with hookSpecificOutput.additionalContext.
# We do NOT block compaction (compaction is needed; we just want a
# summary written first). The directive lands in Claude's context.
set -euo pipefail
trap 'echo "[gemini-plugin] pre-compact-summary crashed at line ${LINENO} (last command: ${BASH_COMMAND})" >&2; exit 0' ERR

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

jq -n --arg ctx "$DIRECTIVE" '{
  hookSpecificOutput: {
    hookEventName: "PreCompact",
    additionalContext: $ctx
  }
}'
exit 0
