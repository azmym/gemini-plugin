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
# UserPromptSubmit hook uses exit 0 + JSON additionalContext (because
# exit 2 erases the prompt). As of v0.2.0, brainstorming is ON by
# default, so the hook fires on every prompt unless brainstorm.off
# exists. The keyword regex only matters in opt-out mode.

@test "user-prompt-grounding: by default (brainstorming on) any prompt triggers grounding" {
  run bash -c 'echo "{\"prompt\":\"fix this typo\"}" | ./hooks/user-prompt-grounding.sh'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.hookEventName == "UserPromptSubmit"'
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext | contains("GROUND_PROMPT")'
}

@test "user-prompt-grounding: opt-out file (brainstorm.off) suppresses grounding on plain prompt" {
  touch "$CLAUDE_PLUGIN_DATA/brainstorm.off"
  run bash -c 'echo "{\"prompt\":\"fix this typo\"}" | ./hooks/user-prompt-grounding.sh'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "user-prompt-grounding: opt-out + keyword still triggers grounding" {
  touch "$CLAUDE_PLUGIN_DATA/brainstorm.off"
  run bash -c 'echo "{\"prompt\":\"what is the latest version of react?\"}" | ./hooks/user-prompt-grounding.sh'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext | contains("gemini-researcher")'
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext | contains("GROUND_PROMPT")'
}

@test "user-prompt-grounding: opt-out + operational prompt (release=/app=) does NOT trigger" {
  # Real-world false positive regression: prompts with release=
  # and app= must not match the narrow keyword regex.
  touch "$CLAUDE_PLUGIN_DATA/brainstorm.off"
  PROMPT='start two agent one look for loki and one for promql to gather clients failing with \"Too late\" for PUT /v1/carts/{week} release=\"mss-cart-service\", app=\"mss-cart-service-app\" for last 24 hours'
  run bash -c "echo '{\"prompt\":\"$PROMPT\"}' | ./hooks/user-prompt-grounding.sh"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "user-prompt-grounding: opt-out + CVE reference triggers grounding" {
  touch "$CLAUDE_PLUGIN_DATA/brainstorm.off"
  run bash -c 'echo "{\"prompt\":\"is CVE-2025-1234 fixed in our deps?\"}" | ./hooks/user-prompt-grounding.sh'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext | contains("GROUND_PROMPT")'
}

@test "user-prompt-grounding: opt-out + 'changelog for X' triggers grounding" {
  touch "$CLAUDE_PLUGIN_DATA/brainstorm.off"
  run bash -c 'echo "{\"prompt\":\"show me the changelog for fastmcp\"}" | ./hooks/user-prompt-grounding.sh'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext | contains("GROUND_PROMPT")'
}

# --- pre-destructive-bash ---

@test "pre-destructive-bash: exits 0 for safe command" {
  run bash -c 'echo "{\"tool_input\":{\"command\":\"ls -la\"}}" | ./hooks/pre-destructive-bash.sh'
  [ "$status" -eq 0 ]
}

# pre-destructive-bash now uses exit 0 + JSON with permissionDecision=deny.
# Per the docs, PreToolUse stdout is debug-log-only unless we return JSON;
# permissionDecision: deny is the documented way to block a tool call
# while still being able to inject additionalContext.

@test "pre-destructive-bash: exits 0 with permissionDecision=deny for rm -rf" {
  run bash -c 'echo "{\"tool_input\":{\"command\":\"rm -rf /tmp/foo\"}}" | ./hooks/pre-destructive-bash.sh'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext | contains("gemini-challenger")'
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext | contains("CHALLENGE_DESTRUCTIVE_OP")'
}

@test "pre-destructive-bash: denies git push --force" {
  run bash -c 'echo "{\"tool_input\":{\"command\":\"git push origin main --force\"}}" | ./hooks/pre-destructive-bash.sh'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
}

@test "pre-destructive-bash: denies DROP TABLE" {
  run bash -c 'echo "{\"tool_input\":{\"command\":\"psql -c \\\"DROP TABLE users\\\"\"}}" | ./hooks/pre-destructive-bash.sh'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
}

@test "pre-destructive-bash: passes through git pull --force (false-positive guard)" {
  run bash -c 'echo "{\"tool_input\":{\"command\":\"git pull --force\"}}" | ./hooks/pre-destructive-bash.sh'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# --- plan-complete (PreToolUse(ExitPlanMode)) ---
# Uses exit 0 + JSON additionalContext (no deny — the plan should reach
# the user; the validator runs alongside).

@test "plan-complete: exits 0 with validator directive in additionalContext" {
  run bash -c 'echo "{\"tool_input\":{\"plan\":\"Step 1: do X. Step 2: do Y.\"}}" | ./hooks/plan-complete.sh'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext | contains("gemini-validator")'
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext | contains("VALIDATE_PLAN")'
}

@test "plan-complete: accepts legacy .plan key for backwards-compat" {
  run bash -c 'echo "{\"plan\":\"Step 1: do X. Step 2: do Y.\"}" | ./hooks/plan-complete.sh'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext | contains("VALIDATE_PLAN")'
}

@test "plan-complete: exits 0 silently when plan is empty" {
  run bash -c 'echo "{\"tool_input\":{\"plan\":\"\"}}" | ./hooks/plan-complete.sh'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# --- stop-done-claim ---
# Uses exit 0 + JSON with decision=block + additionalContext.

@test "stop-done-claim: exits 0 silently when no tool used" {
  run bash -c 'echo "{\"assistant_message\":\"Done!\",\"tool_used\":\"false\"}" | ./hooks/stop-done-claim.sh'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "stop-done-claim: exits 0 silently when no completion word" {
  run bash -c 'echo "{\"assistant_message\":\"Here is the code\",\"tool_used\":\"true\"}" | ./hooks/stop-done-claim.sh'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "stop-done-claim: blocks via JSON when tool used and completion claimed" {
  run bash -c 'echo "{\"assistant_message\":\"I have completed the task.\",\"tool_used\":\"true\",\"original_ask\":\"add a button\"}" | ./hooks/stop-done-claim.sh'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "block"'
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext | contains("VALIDATE_DONE_CLAIM")'
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
