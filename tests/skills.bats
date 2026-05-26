#!/usr/bin/env bats

SKILLS_DIR="skills"

EXPECTED_SKILLS=(
  "gemini-when-to-use"
  "gemini-chat-and-reason"
  "gemini-research-grounded"
  "gemini-file-analysis"
  "gemini-code-exec"
  "gemini-image-gen"
  "gemini-video-gen"
  "gemini-audio-tts-music"
)

@test "all 8 skill directories exist with SKILL.md" {
  for skill in "${EXPECTED_SKILLS[@]}"; do
    [ -f "$SKILLS_DIR/$skill/SKILL.md" ]
  done
}

@test "all skills have description in frontmatter" {
  for skill in "${EXPECTED_SKILLS[@]}"; do
    grep -q "^description:" "$SKILLS_DIR/$skill/SKILL.md"
  done
}

@test "all skills have --- frontmatter delimiters" {
  for skill in "${EXPECTED_SKILLS[@]}"; do
    HEAD=$(head -1 "$SKILLS_DIR/$skill/SKILL.md")
    [ "$HEAD" = "---" ]
  done
}

@test "gemini-when-to-use has broadest description (contains 'Master router')" {
  grep -q "Master router" "$SKILLS_DIR/gemini-when-to-use/SKILL.md"
}

@test "capability skills reference specific MCP tools" {
  grep -q "mcp__gemini__gemini_generate" "$SKILLS_DIR/gemini-chat-and-reason/SKILL.md"
  grep -q "mcp__gemini__gemini_search_grounded" "$SKILLS_DIR/gemini-research-grounded/SKILL.md"
  grep -q "mcp__gemini__gemini_analyze_file" "$SKILLS_DIR/gemini-file-analysis/SKILL.md"
  grep -q "mcp__gemini__gemini_code_execute" "$SKILLS_DIR/gemini-code-exec/SKILL.md"
  grep -q "mcp__gemini__gemini_generate_image" "$SKILLS_DIR/gemini-image-gen/SKILL.md"
  grep -q "mcp__gemini__gemini_start_video" "$SKILLS_DIR/gemini-video-gen/SKILL.md"
  grep -q "mcp__gemini__gemini_generate_music" "$SKILLS_DIR/gemini-audio-tts-music/SKILL.md"
}

@test "no skill has disallowed frontmatter fields for plugin skills" {
  for skill in "${EXPECTED_SKILLS[@]}"; do
    FM=$(sed -n '/^---$/,/^---$/p' "$SKILLS_DIR/$skill/SKILL.md" | sed '1d;$d')
    ! echo "$FM" | grep -q "^hooks:"
    ! echo "$FM" | grep -q "^mcpServers:"
  done
}
