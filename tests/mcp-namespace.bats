#!/usr/bin/env bats

AGENTS_DIR="agents"
SKILLS_DIR="skills"

extract_frontmatter() {
  sed -n '/^---$/,/^---$/p' "$1" | sed '1d;$d'
}

AGENTS=(gemini-validator gemini-challenger gemini-researcher gemini-summarizer gemini-reviewer)

@test "no agent frontmatter declares a tools: key (agents inherit session tools incl. MCP)" {
  for agent in "${AGENTS[@]}"; do
    FM=$(extract_frontmatter "$AGENTS_DIR/${agent}.md")
    if echo "$FM" | grep -qE "^tools:"; then
      echo "FAIL: $agent still declares tools: in frontmatter (would exclude MCP tools)"
      return 1
    fi
  done
}

@test "no agent file contains a hardcoded mcp__ full path" {
  for agent in "${AGENTS[@]}"; do
    if grep -qE "mcp__gemini__|mcp__plugin_" "$AGENTS_DIR/${agent}.md"; then
      echo "FAIL: $agent contains a hardcoded mcp__ path; use short tool names"
      return 1
    fi
  done
}

@test "no skill file contains a hardcoded mcp__ full path" {
  for f in "$SKILLS_DIR"/*/SKILL.md; do
    if grep -qE "mcp__gemini__|mcp__plugin_" "$f"; then
      echo "FAIL: $f contains a hardcoded mcp__ path; use short tool names"
      return 1
    fi
  done
}

@test "hook scripts contain no hardcoded mcp__ namespace" {
  for f in hooks/*.sh hooks/lib/*.sh; do
    [ -f "$f" ] || continue
    if grep -qE "mcp__gemini__|mcp__plugin_" "$f"; then
      echo "FAIL: $f contains a hardcoded mcp__ namespace"
      return 1
    fi
  done
}

@test "every agent documents the deferred-tool ToolSearch step" {
  # In heavy-MCP sessions the Gemini tools are deferred (schema not loaded);
  # an agent must call ToolSearch before invoking them or it stalls hunting
  # for the tool name. Each agent MUST teach this in its system prompt.
  for agent in "${AGENTS[@]}"; do
    if ! grep -q "ToolSearch" "$AGENTS_DIR/${agent}.md"; then
      echo "FAIL: $agent does not mention ToolSearch (deferred-tool path missing)"
      return 1
    fi
  done
}

@test "the deferred-tool note uses keyword queries, not a hardcoded mcp__ path" {
  # The ToolSearch guidance must rely on namespace-agnostic keyword queries so
  # it works for both the plugin and manual installs (and keeps the no-mcp__
  # rule above green).
  for agent in "${AGENTS[@]}"; do
    if grep -q "ToolSearch" "$AGENTS_DIR/${agent}.md" \
       && ! grep -qiE "keyword query" "$AGENTS_DIR/${agent}.md"; then
      echo "FAIL: $agent mentions ToolSearch but not the keyword-query approach"
      return 1
    fi
  done
}
