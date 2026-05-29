#!/usr/bin/env bats

AGENTS_DIR="agents"

@test "all 5 agent files exist" {
  [ -f "$AGENTS_DIR/gemini-validator.md" ]
  [ -f "$AGENTS_DIR/gemini-challenger.md" ]
  [ -f "$AGENTS_DIR/gemini-researcher.md" ]
  [ -f "$AGENTS_DIR/gemini-summarizer.md" ]
  [ -f "$AGENTS_DIR/gemini-reviewer.md" ]
}

extract_frontmatter() {
  sed -n '/^---$/,/^---$/p' "$1" | sed '1d;$d'
}

@test "gemini-validator has required frontmatter fields" {
  FM=$(extract_frontmatter "$AGENTS_DIR/gemini-validator.md")
  echo "$FM" | grep -q "^name: gemini-validator"
  echo "$FM" | grep -q "^description:"
  echo "$FM" | grep -q "^model: sonnet"
  echo "$FM" | grep -q "^color: blue"
  echo "$FM" | grep -q "^maxTurns: 6"
}

@test "gemini-challenger has required frontmatter fields" {
  FM=$(extract_frontmatter "$AGENTS_DIR/gemini-challenger.md")
  echo "$FM" | grep -q "^name: gemini-challenger"
  echo "$FM" | grep -q "^model: opus"
  echo "$FM" | grep -q "^color: red"
  echo "$FM" | grep -q "^maxTurns: 8"
  echo "$FM" | grep -q "^effort: high"
}

@test "gemini-researcher has required frontmatter fields" {
  FM=$(extract_frontmatter "$AGENTS_DIR/gemini-researcher.md")
  echo "$FM" | grep -q "^name: gemini-researcher"
  echo "$FM" | grep -q "^model: sonnet"
  echo "$FM" | grep -q "^color: green"
  echo "$FM" | grep -q "^maxTurns: 12"
  echo "$FM" | grep -q "^background: true"
}

@test "gemini-summarizer has required frontmatter fields" {
  FM=$(extract_frontmatter "$AGENTS_DIR/gemini-summarizer.md")
  echo "$FM" | grep -q "^name: gemini-summarizer"
  echo "$FM" | grep -q "^model: opus"
  echo "$FM" | grep -q "^color: purple"
  echo "$FM" | grep -q "^maxTurns: 4"
  echo "$FM" | grep -q "^memory: project"
}

@test "gemini-reviewer has required frontmatter fields" {
  FM=$(extract_frontmatter "$AGENTS_DIR/gemini-reviewer.md")
  echo "$FM" | grep -q "^name: gemini-reviewer"
  echo "$FM" | grep -q "^model: sonnet"
  echo "$FM" | grep -q "^color: cyan"
  echo "$FM" | grep -q "^maxTurns: 10"
}

@test "all agents preload gemini-when-to-use skill" {
  for agent in validator challenger researcher summarizer reviewer; do
    FM=$(extract_frontmatter "$AGENTS_DIR/gemini-${agent}.md")
    echo "$FM" | grep -q "gemini-when-to-use"
  done
}

@test "no agent uses disallowed tools" {
  for agent in validator challenger researcher summarizer reviewer; do
    FM=$(extract_frontmatter "$AGENTS_DIR/gemini-${agent}.md")
    ! echo "$FM" | grep -q "Agent"
    ! echo "$FM" | grep -q "AskUserQuestion"
    ! echo "$FM" | grep -q "EnterPlanMode"
    ! echo "$FM" | grep -q "ExitPlanMode"
  done
}

@test "agent descriptions start with 'Use proactively'" {
  for agent in validator challenger researcher summarizer reviewer; do
    FM=$(extract_frontmatter "$AGENTS_DIR/gemini-${agent}.md")
    echo "$FM" | grep -q "Use proactively"
  done
}
