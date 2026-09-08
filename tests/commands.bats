#!/usr/bin/env bats

COMMANDS_DIR="commands"

@test "all 6 command files exist" {
  [ -f "$COMMANDS_DIR/gemini-validate.md" ]
  [ -f "$COMMANDS_DIR/gemini-challenge.md" ]
  [ -f "$COMMANDS_DIR/gemini-research.md" ]
  [ -f "$COMMANDS_DIR/gemini-brainstorm-on.md" ]
  [ -f "$COMMANDS_DIR/gemini-brainstorm-off.md" ]
  [ -f "$COMMANDS_DIR/gemini-doctor.md" ]
}

@test "all commands have description in frontmatter" {
  for cmd in gemini-validate gemini-challenge gemini-research gemini-brainstorm-on gemini-brainstorm-off gemini-doctor; do
    grep -q "^description:" "$COMMANDS_DIR/$cmd.md"
  done
}

@test "all commands have --- frontmatter delimiters" {
  for cmd in gemini-validate gemini-challenge gemini-research gemini-brainstorm-on gemini-brainstorm-off gemini-doctor; do
    HEAD=$(head -1 "$COMMANDS_DIR/$cmd.md")
    [ "$HEAD" = "---" ]
  done
}

@test "main commands reference their target agent" {
  grep -q "gemini-validator" "$COMMANDS_DIR/gemini-validate.md"
  grep -q "gemini-challenger" "$COMMANDS_DIR/gemini-challenge.md"
  grep -q "gemini-researcher" "$COMMANDS_DIR/gemini-research.md"
}

@test "doctor command checks both the MCP server and the subagent path" {
  grep -q "gemini-researcher" "$COMMANDS_DIR/gemini-doctor.md"
  # Short tool name only: the MCP prefix differs per host and per install type,
  # so the doctor resolves by name suffix instead of a hardcoded full path.
  grep -q "gemini_search_grounded" "$COMMANDS_DIR/gemini-doctor.md"
  grep -qi "stale session" "$COMMANDS_DIR/gemini-doctor.md"
}

@test "doctor command offers INCONCLUSIVE and requires evidence per check" {
  # A check that could not run must not be reported as PASS or FAIL. A rejected
  # subagent spawn was once reported as FAIL, which sent users to fix grounding
  # that was never broken.
  grep -q "INCONCLUSIVE" "$COMMANDS_DIR/gemini-doctor.md"
  grep -q "Evidence:" "$COMMANDS_DIR/gemini-doctor.md"
}

@test "doctor command does not claim a stale session on an inconclusive check" {
  grep -qi "Never claim a stale session when check 3 is INCONCLUSIVE" \
    "$COMMANDS_DIR/gemini-doctor.md"
}

@test "research command mentions --deep flag" {
  grep -q "\-\-deep" "$COMMANDS_DIR/gemini-research.md"
}

@test "brainstorm commands reference brainstorm.off (the v0.2.0 opt-out flag)" {
  grep -q "brainstorm.off" "$COMMANDS_DIR/gemini-brainstorm-on.md"
  grep -q "brainstorm.off" "$COMMANDS_DIR/gemini-brainstorm-off.md"
}
