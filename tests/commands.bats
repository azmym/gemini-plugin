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
  grep -q "mcp__plugin_gemini-plugin_gemini__gemini_search_grounded" "$COMMANDS_DIR/gemini-doctor.md"
  grep -qi "stale session" "$COMMANDS_DIR/gemini-doctor.md"
}

@test "research command mentions --deep flag" {
  grep -q "\-\-deep" "$COMMANDS_DIR/gemini-research.md"
}

@test "brainstorm commands reference brainstorm.off (the v0.2.0 opt-out flag)" {
  grep -q "brainstorm.off" "$COMMANDS_DIR/gemini-brainstorm-on.md"
  grep -q "brainstorm.off" "$COMMANDS_DIR/gemini-brainstorm-off.md"
}
