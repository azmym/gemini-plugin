#!/usr/bin/env bats

setup() {
  export CLAUDE_PLUGIN_DATA_DIR="$BATS_TMPDIR/test-data-$$"
  export GEMINI_API_KEY="test-key"
  export CLAUDE_PLUGIN_GEMINI_DISABLE_HOOKS=0
  mkdir -p "$CLAUDE_PLUGIN_DATA_DIR"
}

teardown() {
  rm -rf "$CLAUDE_PLUGIN_DATA_DIR"
}

# --- session-start-risk-map ---

@test "session-start: exits 0 when GEMINI_API_KEY unset" {
  unset GEMINI_API_KEY
  run bash -c 'echo "{}" | ./hooks/session-start-risk-map.sh'
  [ "$status" -eq 0 ]
}

@test "session-start: exits 0 when risk map is fresh" {
  HASH=$(bash -c 'source hooks/lib/common.sh; repo_hash')
  touch "$CLAUDE_PLUGIN_DATA_DIR/risk-map-${HASH}.json"
  run bash -c 'echo "{}" | ./hooks/session-start-risk-map.sh'
  [ "$status" -eq 0 ]
}

@test "session-start: exits 2 when risk map missing" {
  run bash -c 'echo "{}" | ./hooks/session-start-risk-map.sh'
  [ "$status" -eq 2 ]
  [[ "$output" == *"gemini-summarizer"* ]]
  [[ "$output" == *"BUILD_RISK_MAP"* ]]
}

# --- user-prompt-grounding ---

@test "user-prompt-grounding: exits 0 when no matching keywords and not brainstorming" {
  run bash -c 'echo "{\"prompt\":\"fix this typo\"}" | ./hooks/user-prompt-grounding.sh'
  [ "$status" -eq 0 ]
}

@test "user-prompt-grounding: exits 2 when keyword matches" {
  run bash -c 'echo "{\"prompt\":\"what is the latest version of react?\"}" | ./hooks/user-prompt-grounding.sh'
  [ "$status" -eq 2 ]
  [[ "$output" == *"gemini-researcher"* ]]
}

@test "user-prompt-grounding: exits 2 unconditionally when brainstorming" {
  touch "$CLAUDE_PLUGIN_DATA_DIR/brainstorm.lock"
  run bash -c 'echo "{\"prompt\":\"fix this typo\"}" | ./hooks/user-prompt-grounding.sh'
  [ "$status" -eq 2 ]
  [[ "$output" == *"GROUND_PROMPT"* ]]
}

# --- pre-destructive-bash ---

@test "pre-destructive-bash: exits 0 for safe command" {
  run bash -c 'echo "{\"tool_input\":{\"command\":\"ls -la\"}}" | ./hooks/pre-destructive-bash.sh'
  [ "$status" -eq 0 ]
}

@test "pre-destructive-bash: exits 2 for rm -rf" {
  run bash -c 'echo "{\"tool_input\":{\"command\":\"rm -rf /tmp/foo\"}}" | ./hooks/pre-destructive-bash.sh'
  [ "$status" -eq 2 ]
  [[ "$output" == *"gemini-challenger"* ]]
  [[ "$output" == *"CHALLENGE_DESTRUCTIVE_OP"* ]]
}

@test "pre-destructive-bash: exits 2 for git push --force" {
  run bash -c 'echo "{\"tool_input\":{\"command\":\"git push origin main --force\"}}" | ./hooks/pre-destructive-bash.sh'
  [ "$status" -eq 2 ]
}

@test "pre-destructive-bash: exits 2 for DROP TABLE" {
  run bash -c 'echo "{\"tool_input\":{\"command\":\"psql -c \\\"DROP TABLE users\\\"\"}}" | ./hooks/pre-destructive-bash.sh'
  [ "$status" -eq 2 ]
}

# --- plan-complete ---

@test "plan-complete: exits 2 with validator directive" {
  run bash -c 'echo "{\"plan\":\"Step 1: do X. Step 2: do Y.\"}" | ./hooks/plan-complete.sh'
  [ "$status" -eq 2 ]
  [[ "$output" == *"gemini-validator"* ]]
  [[ "$output" == *"VALIDATE_PLAN"* ]]
}

@test "plan-complete: exits 0 when plan is empty" {
  run bash -c 'echo "{\"plan\":\"\"}" | ./hooks/plan-complete.sh'
  [ "$status" -eq 0 ]
}

# --- stop-done-claim ---

@test "stop-done-claim: exits 0 when no tool used" {
  run bash -c 'echo "{\"assistant_message\":\"Done!\",\"tool_used\":\"false\"}" | ./hooks/stop-done-claim.sh'
  [ "$status" -eq 0 ]
}

@test "stop-done-claim: exits 0 when no completion word" {
  run bash -c 'echo "{\"assistant_message\":\"Here is the code\",\"tool_used\":\"true\"}" | ./hooks/stop-done-claim.sh'
  [ "$status" -eq 0 ]
}

@test "stop-done-claim: exits 2 when tool used and completion claimed" {
  run bash -c 'echo "{\"assistant_message\":\"I have completed the task.\",\"tool_used\":\"true\",\"original_ask\":\"add a button\"}" | ./hooks/stop-done-claim.sh'
  [ "$status" -eq 2 ]
  [[ "$output" == *"VALIDATE_DONE_CLAIM"* ]]
}

# --- subagent-verdict-handler ---

@test "verdict-handler: exits 0 when no transcript" {
  run bash -c 'echo "{\"agent_type\":\"gemini-validator\",\"transcript_path\":\"\"}" | ./hooks/subagent-verdict-handler.sh'
  [ "$status" -eq 0 ]
}

@test "verdict-handler: exits 0 on pass verdict" {
  TRANSCRIPT="$BATS_TMPDIR/transcript-$$.jsonl"
  echo '{"type":"assistant","message":{"content":[{"text":"{\"verdict\":\"pass\",\"gaps\":[]}"}]}}' > "$TRANSCRIPT"
  run bash -c "echo '{\"agent_type\":\"gemini-validator\",\"transcript_path\":\"${TRANSCRIPT}\"}' | ./hooks/subagent-verdict-handler.sh"
  [ "$status" -eq 0 ]
}

@test "verdict-handler: exits 2 on fail verdict" {
  TRANSCRIPT="$BATS_TMPDIR/transcript-$$.jsonl"
  echo '{"type":"assistant","message":{"content":[{"text":"{\"verdict\":\"fail\",\"gaps\":[\"missing tests\"]}"}]}}' > "$TRANSCRIPT"
  run bash -c "echo '{\"agent_type\":\"gemini-validator\",\"transcript_path\":\"${TRANSCRIPT}\"}' | ./hooks/subagent-verdict-handler.sh"
  [ "$status" -eq 2 ]
  [[ "$output" == *"missing tests"* ]]
}

@test "verdict-handler: loop guard demotes repeat fail to advisory" {
  TRANSCRIPT="$BATS_TMPDIR/transcript-$$.jsonl"
  VERDICT='{"verdict":"fail","gaps":["same gap"]}'
  # Build valid JSON with jq to avoid quoting issues when embedding VERDICT
  jq -n --arg text "$VERDICT" '{"type":"assistant","message":{"content":[{"text":$text}]}}' > "$TRANSCRIPT"
  # Prime the last-verdict file with identical content so loop guard triggers
  echo "$VERDICT" > "$CLAUDE_PLUGIN_DATA_DIR/last-verdict-gemini-validator.txt"
  run bash -c "echo '{\"agent_type\":\"gemini-validator\",\"transcript_path\":\"${TRANSCRIPT}\"}' | ./hooks/subagent-verdict-handler.sh"
  [ "$status" -eq 0 ]
}

# --- plugin disable ---

@test "all hooks exit 0 when CLAUDE_PLUGIN_GEMINI_DISABLE_HOOKS=1" {
  export CLAUDE_PLUGIN_GEMINI_DISABLE_HOOKS=1
  run bash -c 'echo "{\"prompt\":\"what version of react?\"}" | ./hooks/user-prompt-grounding.sh'
  [ "$status" -eq 0 ]
  run bash -c 'echo "{\"tool_input\":{\"command\":\"rm -rf /\"}}" | ./hooks/pre-destructive-bash.sh'
  [ "$status" -eq 0 ]
}
