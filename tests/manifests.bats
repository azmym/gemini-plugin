#!/usr/bin/env bats

@test "plugin.json is valid JSON" {
  jq empty .claude-plugin/plugin.json
}

@test "plugin.json has required fields" {
  jq -e '.name' .claude-plugin/plugin.json
  jq -e '.version' .claude-plugin/plugin.json
  jq -e '.mcpServers.gemini' .claude-plugin/plugin.json
}

@test "plugin.json declares userConfig for API key" {
  jq -e '.userConfig.gemini_api_key.sensitive' .claude-plugin/plugin.json
  jq -e '.userConfig.gemini_api_key.required' .claude-plugin/plugin.json
}

@test "version follows semver" {
  VERSION=$(jq -r '.version' .claude-plugin/plugin.json)
  [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

@test "marketplace.json is not present (distributed via SynthForge)" {
  [ ! -f .claude-plugin/marketplace.json ]
}
@test "hooks.json is valid JSON" {
  jq empty hooks/hooks.json
}
@test "hooks.json declares PostToolUse(Write|Edit) -> design-review.sh" {
  jq -e '.hooks.PostToolUse[0].matcher == "Write|Edit"' hooks/hooks.json
  jq -e '.hooks.PostToolUse[0].hooks[0].command | endswith("design-review.sh")' hooks/hooks.json
}
@test "hooks.json SubagentStop matcher includes all five agents" {
  M=$(jq -r '.hooks.SubagentStop[0].matcher' hooks/hooks.json)
  for a in gemini-validator gemini-challenger gemini-researcher gemini-summarizer gemini-reviewer; do
    [[ "$M" == *"$a"* ]]
  done
}
