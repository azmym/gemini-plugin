#!/usr/bin/env bash
set -euo pipefail
trap 'echo "[gemini-plugin] subagent-verdict-handler crashed at line ${LINENO} (last command: ${BASH_COMMAND})" >&2; exit 0' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

ensure_data_dir
DATA="$(data_dir)"

INPUT=$(cat)
AGENT=$(echo "$INPUT" | jq -r '.agent_type')
MODE=$(read_consume_pending_mode "$AGENT")
TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path // empty')

if [ -z "$TRANSCRIPT" ] || [ ! -f "$TRANSCRIPT" ]; then
  exit 0
fi

# Extract the agent's final JSON message (look for structured output in last 50 lines)
VERDICT_JSON=$(tail -50 "$TRANSCRIPT" | jq -rs '
  [.[] | select(.type=="assistant")] | last
  | .message.content[0].text // empty
' 2>/dev/null | tail -c 8192)

if [ -z "$VERDICT_JSON" ]; then
  exit 0
fi

# Try to parse as JSON; if not JSON, treat as advisory
VERDICT=$(echo "$VERDICT_JSON" | jq -r '.verdict // "advisory"' 2>/dev/null || echo "advisory")
GAPS=$(echo "$VERDICT_JSON" | jq -r '.gaps // .objections // .must_address // [] | if type == "array" then join("\n- ") else . end' 2>/dev/null || echo "")

# Loop guard: identical verdict twice in a row -> downgrade to advisory
LAST_FILE="${DATA}/last-verdict-${AGENT}.txt"
LAST=$(cat "$LAST_FILE" 2>/dev/null || echo "")
if [ "$VERDICT" = "fail" ] && [ "$VERDICT_JSON" = "$LAST" ]; then
  VERDICT="advisory"
fi
echo "$VERDICT_JSON" > "$LAST_FILE"

# Persist for plan-history
echo "{\"task\":\"$(echo "$INPUT" | jq -r '.task // "unknown"')\",\"agent\":\"${AGENT}\",\"verdict\":\"${VERDICT}\",\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}" >> "${DATA}/plan-history.jsonl"

if [ "$VERDICT" = "fail" ] || [ "$VERDICT" = "block" ]; then
  cat >&2 <<EOF
[gemini-plugin] ${AGENT} verdict: ${VERDICT} (${MODE})
Issues to address before continuing:
- ${GAPS}
EOF
  if [ "$MODE" = "advisory" ]; then
    exit 0
  fi
  exit 2
fi
exit 0
