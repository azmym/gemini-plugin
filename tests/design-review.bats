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
  bash -c 'source hooks/lib/common.sh; write_pending_mode gemini-challenger advisory'
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
