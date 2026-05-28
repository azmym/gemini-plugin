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
