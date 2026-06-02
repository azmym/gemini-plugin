#!/usr/bin/env bats

setup() {
  export CLAUDE_PLUGIN_DATA="$BATS_TMPDIR/test-data-$$"
  export CLAUDE_PLUGIN_OPTION_GEMINI_API_KEY="test-key"
  export CLAUDE_PLUGIN_GEMINI_DISABLE_HOOKS=0
  mkdir -p "$CLAUDE_PLUGIN_DATA"
}
teardown() {
  rm -rf "$CLAUDE_PLUGIN_DATA"
}

# --- is_design_artifact ---
@test "is_design_artifact: matches superpowers spec (relative)" {
  run bash -c 'source hooks/lib/common.sh; is_design_artifact "docs/superpowers/specs/2026-06-02-foo-design.md"'
  [ "$status" -eq 0 ]
}
@test "is_design_artifact: matches absolute spec path" {
  run bash -c 'source hooks/lib/common.sh; is_design_artifact "/Users/me/proj/docs/superpowers/specs/x-design.md"'
  [ "$status" -eq 0 ]
}
@test "is_design_artifact: matches a *-plan.md" {
  run bash -c 'source hooks/lib/common.sh; is_design_artifact "docs/superpowers/plans/2026-06-02-foo-plan.md"'
  [ "$status" -eq 0 ]
}
@test "is_design_artifact: matches a bare *-plan.md at any depth" {
  run bash -c 'source hooks/lib/common.sh; is_design_artifact "subdir/my-plan.md"'
  [ "$status" -eq 0 ]
}
@test "is_design_artifact: matches generic specs/ dir" {
  run bash -c 'source hooks/lib/common.sh; is_design_artifact "myproj/specs/auth.md"'
  [ "$status" -eq 0 ]
}
@test "is_design_artifact: matches DESIGN.md" {
  run bash -c 'source hooks/lib/common.sh; is_design_artifact "subsystem/DESIGN.md"'
  [ "$status" -eq 0 ]
}
@test "is_design_artifact: rejects a non-design markdown" {
  run bash -c 'source hooks/lib/common.sh; is_design_artifact "docs/notes.md"'
  [ "$status" -ne 0 ]
}
@test "is_design_artifact: rejects a source file" {
  run bash -c 'source hooks/lib/common.sh; is_design_artifact "src/foo.ts"'
  [ "$status" -ne 0 ]
}
@test "is_design_artifact: respects CLAUDE_PLUGIN_GEMINI_DESIGN_GLOBS override" {
  run bash -c 'source hooks/lib/common.sh; CLAUDE_PLUGIN_GEMINI_DESIGN_GLOBS="*/rfc/*.md" is_design_artifact "x/rfc/1.md"'
  [ "$status" -eq 0 ]
  run bash -c 'source hooks/lib/common.sh; CLAUDE_PLUGIN_GEMINI_DESIGN_GLOBS="*/rfc/*.md" is_design_artifact "docs/superpowers/specs/x-design.md"'
  [ "$status" -ne 0 ]
}

# --- pending-mode markers ---
@test "pending mode: write creates a marker file" {
  run bash -c 'source hooks/lib/common.sh; write_pending_mode gemini-challenger advisory'
  [ "$status" -eq 0 ]
  [ -f "$CLAUDE_PLUGIN_DATA/pending/gemini-challenger.mode" ]
  [ "$(cat "$CLAUDE_PLUGIN_DATA/pending/gemini-challenger.mode")" = "advisory" ]
}
@test "pending mode: read returns the mode and consumes the marker" {
  bash -c 'source hooks/lib/common.sh; write_pending_mode gemini-validator advisory'
  run bash -c 'source hooks/lib/common.sh; read_consume_pending_mode gemini-validator'
  [ "$status" -eq 0 ]
  [ "$output" = "advisory" ]
  [ ! -f "$CLAUDE_PLUGIN_DATA/pending/gemini-validator.mode" ]
}
@test "pending mode: default is blocking when no marker exists" {
  run bash -c 'source hooks/lib/common.sh; read_consume_pending_mode gemini-validator'
  [ "$output" = "blocking" ]
}

# --- design seen-hash ---
@test "file_content_hash: returns a hash for an existing file" {
  F="$BATS_TMPDIR/h-$$.txt"
  echo "hello" > "$F"
  run bash -c "source hooks/lib/common.sh; file_content_hash '$F'"
  [ "$status" -eq 0 ]
  [ -n "$output" ]
}
@test "file_content_hash: differs when content changes" {
  F="$BATS_TMPDIR/h2-$$.txt"
  echo "v1" > "$F"
  H1=$(bash -c "source hooks/lib/common.sh; file_content_hash '$F'")
  echo "v2" > "$F"
  H2=$(bash -c "source hooks/lib/common.sh; file_content_hash '$F'")
  [ "$H1" != "$H2" ]
}
@test "design_seen_file: path-keyed, stable for same path" {
  S1=$(bash -c 'source hooks/lib/common.sh; design_seen_file "docs/superpowers/specs/x-design.md"')
  S2=$(bash -c 'source hooks/lib/common.sh; design_seen_file "docs/superpowers/specs/x-design.md"')
  [ "$S1" = "$S2" ]
  [[ "$S1" == *"/design-review-seen/"* ]]
}
@test "design_seen_file: distinct paths produce distinct seen files" {
  S1=$(bash -c 'source hooks/lib/common.sh; design_seen_file "docs/superpowers/specs/a-design.md"')
  S2=$(bash -c 'source hooks/lib/common.sh; design_seen_file "docs/superpowers/specs/b-design.md"')
  [ "$S1" != "$S2" ]
}

# --- directives ---
@test "build_design_review_directive: names both agents and both tasks" {
  run bash -c 'source hooks/lib/common.sh; source hooks/lib/prompt-builder.sh; build_design_review_directive "docs/superpowers/specs/x-design.md" "[]"'
  [ "$status" -eq 0 ]
  [[ "$output" == *"gemini-validator"* ]]
  [[ "$output" == *"VALIDATE_DESIGN"* ]]
  [[ "$output" == *"gemini-challenger"* ]]
  [[ "$output" == *"CHALLENGE_DESIGN"* ]]
  [[ "$output" == *"docs/superpowers/specs/x-design.md"* ]]
  [[ "$output" == *"ADVISORY"* ]]
}
@test "build_plan_challenge_directive: challenger + CHALLENGE_PLAN" {
  run bash -c 'source hooks/lib/common.sh; source hooks/lib/prompt-builder.sh; build_plan_challenge_directive "Step 1: do X."'
  [ "$status" -eq 0 ]
  [[ "$output" == *"gemini-challenger"* ]]
  [[ "$output" == *"CHALLENGE_PLAN"* ]]
}
