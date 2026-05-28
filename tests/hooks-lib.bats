#!/usr/bin/env bats

setup() {
  export CLAUDE_PLUGIN_DATA="$BATS_TMPDIR/test-data-$$"
  mkdir -p "$CLAUDE_PLUGIN_DATA"
  source hooks/lib/common.sh
}

teardown() {
  rm -rf "$CLAUDE_PLUGIN_DATA"
}

@test "check_gemini_available exits 0 with advisory when no key in any var" {
  run bash -c 'unset CLAUDE_PLUGIN_OPTION_GEMINI_API_KEY GEMINI_API_KEY; source hooks/lib/common.sh; check_gemini_available'
  [ "$status" -eq 0 ]
  [[ "$output" == *"Gemini API key not configured"* ]]
}

@test "check_gemini_available passes when CLAUDE_PLUGIN_OPTION_GEMINI_API_KEY is set" {
  run bash -c 'unset GEMINI_API_KEY; export CLAUDE_PLUGIN_OPTION_GEMINI_API_KEY="test-key"; source hooks/lib/common.sh; check_gemini_available'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "check_gemini_available passes when only legacy GEMINI_API_KEY is set" {
  run bash -c 'unset CLAUDE_PLUGIN_OPTION_GEMINI_API_KEY; export GEMINI_API_KEY="legacy-key"; source hooks/lib/common.sh; check_gemini_available'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "check_plugin_enabled exits 0 when disabled" {
  export CLAUDE_PLUGIN_GEMINI_DISABLE_HOOKS=1
  run bash -c 'source hooks/lib/common.sh; check_plugin_enabled'
  [ "$status" -eq 0 ]
}

@test "repo_hash returns 12 char hex string" {
  run bash -c 'source hooks/lib/common.sh; repo_hash'
  [ "$status" -eq 0 ]
  [[ "${output}" =~ ^[a-f0-9]{12}$ ]]
}

@test "is_brainstorming returns 0 when lock file exists" {
  touch "$CLAUDE_PLUGIN_DATA/brainstorm.lock"
  run bash -c "source hooks/lib/common.sh; is_brainstorming"
  [ "$status" -eq 0 ]
}

@test "is_brainstorming returns 1 when no lock file" {
  run bash -c "source hooks/lib/common.sh; is_brainstorming"
  [ "$status" -eq 1 ]
}

@test "is_destructive_command matches rm -rf" {
  run bash -c 'source hooks/lib/common.sh; is_destructive_command "rm -rf /tmp/foo"'
  [ "$status" -eq 0 ]
}

@test "is_destructive_command matches git push --force" {
  run bash -c 'source hooks/lib/common.sh; is_destructive_command "git push origin main --force"'
  [ "$status" -eq 0 ]
}

@test "is_destructive_command matches DROP TABLE" {
  run bash -c 'source hooks/lib/common.sh; is_destructive_command "psql -c DROP TABLE users"'
  [ "$status" -eq 0 ]
}

@test "is_destructive_command matches git reset --hard" {
  run bash -c 'source hooks/lib/common.sh; is_destructive_command "git reset --hard HEAD~3"'
  [ "$status" -eq 0 ]
}

@test "is_destructive_command passes safe commands" {
  run bash -c 'source hooks/lib/common.sh; is_destructive_command "ls -la"'
  [ "$status" -eq 1 ]
}

@test "is_destructive_command passes git push without force" {
  run bash -c 'source hooks/lib/common.sh; is_destructive_command "git push origin main"'
  [ "$status" -eq 1 ]
}

@test "is_destructive_command passes git pull --force (false-positive guard)" {
  run bash -c 'source hooks/lib/common.sh; is_destructive_command "git pull --force"'
  [ "$status" -eq 1 ]
}

@test "is_destructive_command passes commit message containing word DROP" {
  run bash -c 'source hooks/lib/common.sh; is_destructive_command "git commit -m \"drop legacy node\""'
  [ "$status" -eq 1 ]
}

@test "get_plan_history returns empty array when no file" {
  run bash -c 'source hooks/lib/common.sh; get_plan_history "VALIDATE_PLAN"'
  [ "$status" -eq 0 ]
  [ "$output" = "[]" ]
}

@test "get_plan_history returns last N entries" {
  echo '{"task":"VALIDATE_PLAN","verdict":"fail","gaps":["gap1"]}' >> "$CLAUDE_PLUGIN_DATA/plan-history.jsonl"
  echo '{"task":"VALIDATE_PLAN","verdict":"pass","gaps":[]}' >> "$CLAUDE_PLUGIN_DATA/plan-history.jsonl"
  echo '{"task":"CHALLENGE_DESTRUCTIVE_OP","verdict":"pass"}' >> "$CLAUDE_PLUGIN_DATA/plan-history.jsonl"
  run bash -c 'source hooks/lib/common.sh; get_plan_history "VALIDATE_PLAN" 2'
  [ "$status" -eq 0 ]
  RESULT=$(echo "$output" | jq length)
  [ "$RESULT" -eq 2 ]
}
