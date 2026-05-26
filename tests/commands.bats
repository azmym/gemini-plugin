#!/usr/bin/env bats

COMMANDS_DIR="commands"

@test "all 5 command files exist" {
  [ -f "$COMMANDS_DIR/gemini-validate.md" ]
  [ -f "$COMMANDS_DIR/gemini-challenge.md" ]
  [ -f "$COMMANDS_DIR/gemini-research.md" ]
  [ -f "$COMMANDS_DIR/gemini-brainstorm-on.md" ]
  [ -f "$COMMANDS_DIR/gemini-brainstorm-off.md" ]
}

@test "all commands have description in frontmatter" {
  for cmd in gemini-validate gemini-challenge gemini-research gemini-brainstorm-on gemini-brainstorm-off; do
    grep -q "^description:" "$COMMANDS_DIR/$cmd.md"
  done
}

@test "all commands have --- frontmatter delimiters" {
  for cmd in gemini-validate gemini-challenge gemini-research gemini-brainstorm-on gemini-brainstorm-off; do
    HEAD=$(head -1 "$COMMANDS_DIR/$cmd.md")
    [ "$HEAD" = "---" ]
  done
}

@test "main commands reference their target agent" {
  grep -q "gemini-validator" "$COMMANDS_DIR/gemini-validate.md"
  grep -q "gemini-challenger" "$COMMANDS_DIR/gemini-challenge.md"
  grep -q "gemini-researcher" "$COMMANDS_DIR/gemini-research.md"
}

@test "research command mentions --deep flag" {
  grep -q "\-\-deep" "$COMMANDS_DIR/gemini-research.md"
}

@test "brainstorm commands reference brainstorm.lock" {
  grep -q "brainstorm.lock" "$COMMANDS_DIR/gemini-brainstorm-on.md"
  grep -q "brainstorm.lock" "$COMMANDS_DIR/gemini-brainstorm-off.md"
}
