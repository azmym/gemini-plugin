#!/usr/bin/env bats

setup() {
  export CLAUDE_PLUGIN_DATA="$BATS_TMPDIR/test-data-$$"
  # Hooks now look at CLAUDE_PLUGIN_OPTION_GEMINI_API_KEY first; legacy
  # GEMINI_API_KEY is the fallback. Set the canonical one in setup.
  export CLAUDE_PLUGIN_OPTION_GEMINI_API_KEY="test-key"
  export CLAUDE_PLUGIN_GEMINI_DISABLE_HOOKS=0
  mkdir -p "$CLAUDE_PLUGIN_DATA"
}

teardown() {
  rm -rf "$CLAUDE_PLUGIN_DATA"
}

# --- session-start-risk-map ---

@test "session-start: exits 0 when no API key in any var" {
  run bash -c 'unset CLAUDE_PLUGIN_OPTION_GEMINI_API_KEY GEMINI_API_KEY; echo "{}" | ./hooks/session-start-risk-map.sh'
  [ "$status" -eq 0 ]
}

@test "session-start: exits 0 when risk map is fresh" {
  HASH=$(bash -c 'source hooks/lib/common.sh; repo_hash')
  touch "$CLAUDE_PLUGIN_DATA/risk-map-${HASH}.json"
  run bash -c 'echo "{}" | ./hooks/session-start-risk-map.sh'
  [ "$status" -eq 0 ]
}

@test "session-start: exits 0 with directive on stdout when risk map missing" {
  # SessionStart cannot block via exit 2; the supported pattern is exit 0
  # and write the directive to stdout (where Claude Code adds it as
  # additionalContext).
  run bash -c 'echo "{}" | ./hooks/session-start-risk-map.sh'
  [ "$status" -eq 0 ]
  [[ "$output" == *"gemini-summarizer"* ]]
  [[ "$output" == *"BUILD_RISK_MAP"* ]]
}

@test "session-start: writes placeholder file so next run hits TTL gate" {
  HASH=$(bash -c 'source hooks/lib/common.sh; repo_hash')
  RISK_MAP="$CLAUDE_PLUGIN_DATA/risk-map-${HASH}.json"
  # First run should write the placeholder
  run bash -c 'echo "{}" | ./hooks/session-start-risk-map.sh'
  [ "$status" -eq 0 ]
  [ -f "$RISK_MAP" ]
  jq -e '.placeholder == true' "$RISK_MAP"
  # Second run within TTL should still exit 0
  run bash -c 'echo "{}" | ./hooks/session-start-risk-map.sh'
  [ "$status" -eq 0 ]
}

@test "session-start: does not crash when CLAUDE_PLUGIN_DATA is unset" {
  # Regression test for the "Failed with non-blocking status code: No
  # stderr output" error: the script must not crash with set -u when
  # CLAUDE_PLUGIN_DATA is unset. It should fall back to ~/.claude/...
  run bash -c 'unset CLAUDE_PLUGIN_DATA; echo "{}" | ./hooks/session-start-risk-map.sh'
  [ "$status" -eq 0 ]
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
  touch "$CLAUDE_PLUGIN_DATA/brainstorm.lock"
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

@test "pre-destructive-bash: exits 0 for git pull --force (false-positive guard)" {
  run bash -c 'echo "{\"tool_input\":{\"command\":\"git pull --force\"}}" | ./hooks/pre-destructive-bash.sh'
  [ "$status" -eq 0 ]
}

# --- plan-complete (PreToolUse(ExitPlanMode)) ---

@test "plan-complete: exits 2 with validator directive (PreToolUse shape)" {
  run bash -c 'echo "{\"tool_input\":{\"plan\":\"Step 1: do X. Step 2: do Y.\"}}" | ./hooks/plan-complete.sh'
  [ "$status" -eq 2 ]
  [[ "$output" == *"gemini-validator"* ]]
  [[ "$output" == *"VALIDATE_PLAN"* ]]
}

@test "plan-complete: exits 2 with legacy .plan key for backwards-compat" {
  run bash -c 'echo "{\"plan\":\"Step 1: do X. Step 2: do Y.\"}" | ./hooks/plan-complete.sh'
  [ "$status" -eq 2 ]
}

@test "plan-complete: exits 0 when plan is empty" {
  run bash -c 'echo "{\"tool_input\":{\"plan\":\"\"}}" | ./hooks/plan-complete.sh'
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
  echo "$VERDICT" > "$CLAUDE_PLUGIN_DATA/last-verdict-gemini-validator.txt"
  run bash -c "echo '{\"agent_type\":\"gemini-validator\",\"transcript_path\":\"${TRANSCRIPT}\"}' | ./hooks/subagent-verdict-handler.sh"
  [ "$status" -eq 0 ]
}

# --- plugin disable ---

@test "all hooks exit 0 when CLAUDE_PLUGIN_GEMINI_DISABLE_HOOKS=1" {
  export CLAUDE_PLUGIN_GEMINI_DISABLE_HOOKS=1
  run bash -c 'CLAUDE_PLUGIN_GEMINI_DISABLE_HOOKS=1 echo "{\"prompt\":\"what version of react?\"}" | ./hooks/user-prompt-grounding.sh'
  [ "$status" -eq 0 ]
  run bash -c 'CLAUDE_PLUGIN_GEMINI_DISABLE_HOOKS=1 echo "{\"tool_input\":{\"command\":\"rm -rf /\"}}" | ./hooks/pre-destructive-bash.sh'
  [ "$status" -eq 0 ]
}
