#!/usr/bin/env bats

@test "plugin.json is valid JSON" {
  jq empty .claude-plugin/plugin.json
}

@test "plugin.json has required fields" {
  jq -e '.name' .claude-plugin/plugin.json
  jq -e '.version' .claude-plugin/plugin.json
  jq -e '.mcpServers.gemini' .claude-plugin/plugin.json
}

@test "marketplace.json is valid JSON" {
  jq empty .claude-plugin/marketplace.json
}

@test "marketplace.json has required fields" {
  jq -e '.name' .claude-plugin/marketplace.json
  jq -e '.owner.name' .claude-plugin/marketplace.json
  jq -e '.plugins[0].name' .claude-plugin/marketplace.json
  jq -e '.plugins[0].source' .claude-plugin/marketplace.json
}

@test "plugin name matches between manifest and marketplace" {
  PLUGIN_NAME=$(jq -r '.name' .claude-plugin/plugin.json)
  MARKETPLACE_NAME=$(jq -r '.plugins[0].name' .claude-plugin/marketplace.json)
  [ "$PLUGIN_NAME" = "$MARKETPLACE_NAME" ]
}

@test "version follows semver" {
  VERSION=$(jq -r '.version' .claude-plugin/plugin.json)
  [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
}
