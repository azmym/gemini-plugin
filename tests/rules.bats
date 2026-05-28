#!/usr/bin/env bats

@test "rules/using-gemini.md exists" {
  [ -f "rules/using-gemini.md" ]
}

@test "rule mentions all four agents" {
  grep -q "gemini-validator" rules/using-gemini.md
  grep -q "gemini-challenger" rules/using-gemini.md
  grep -q "gemini-researcher" rules/using-gemini.md
  grep -q "gemini-summarizer" rules/using-gemini.md
}

@test "rule documents CLAUDE_PLUGIN_GEMINI_DISABLE_HOOKS" {
  grep -q "CLAUDE_PLUGIN_GEMINI_DISABLE_HOOKS" rules/using-gemini.md
}

@test "rule documents API key unavailable behavior (graceful no-op)" {
  grep -qE "API key|api key" rules/using-gemini.md
  grep -qE "no-op|gracefully" rules/using-gemini.md
}
