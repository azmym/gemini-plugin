# gemini-plugin v0.1.0 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Claude Code plugin at `~/workspace/gemini-plugin` that wraps gemini-mcp into 8 skills, 4 subagents, 7 hook scripts, 3 slash commands, and a marketplace manifest, all wired to block Claude on hallucination.

**Architecture:** Three layers: hooks coordinate (read stdin JSON, emit exit 2 + stderr directive), subagents reason (spawned by Claude via Agent tool, use gemini MCP tools, return structured JSON verdict), MCP executes (gemini-mcp server auto-registered by plugin manifest). State persisted in `${CLAUDE_PLUGIN_DATA_DIR}`.

**Tech Stack:** Bash (hooks), Markdown+YAML frontmatter (skills/agents/commands/rules), JSON (manifests), bats-core (tests)

---

## Task 1: Plugin scaffold and manifests

**Files:**
- Create: `.claude-plugin/plugin.json`
- Create: `.claude-plugin/marketplace.json`
- Create: `.gitignore`
- Test: `tests/manifests.bats`

- [ ] **Step 1: Create `.claude-plugin/plugin.json`**

```json
{
  "name": "gemini-plugin",
  "displayName": "Gemini Plugin",
  "version": "0.1.0",
  "description": "Wraps gemini-mcp into a Claude Code plugin so Gemini acts as a second opinion: validator/challenger/researcher/summarizer subagents, auto-trigger hooks, and 8 task-oriented skills.",
  "author": { "name": "azmym" },
  "homepage": "https://github.com/azmym/gemini-plugin",
  "repository": "https://github.com/azmym/gemini-plugin",
  "license": "MIT",
  "keywords": ["gemini", "mcp", "subagent", "hooks", "anti-hallucination", "google-ai"],
  "mcpServers": {
    "gemini": {
      "type": "stdio",
      "command": "uvx",
      "args": ["--from", "git+https://github.com/azmym/gemini-mcp", "gemini-mcp"],
      "env": { "GEMINI_API_KEY": "${GEMINI_API_KEY}" }
    }
  }
}
```

- [ ] **Step 2: Create `.claude-plugin/marketplace.json`**

```json
{
  "name": "gemini-marketplace",
  "owner": { "name": "azmym" },
  "description": "Gemini-as-second-opinion plugin for Claude Code",
  "plugins": [
    {
      "name": "gemini-plugin",
      "source": "./",
      "description": "Wraps gemini-mcp into a Claude Code plugin: validator/challenger/researcher/summarizer subagents, auto-trigger hooks, 8 skills covering text/image/video/music/TTS/research.",
      "category": "ai-assistance",
      "tags": ["gemini", "google-ai", "validation", "anti-hallucination", "second-opinion"],
      "keywords": ["gemini", "mcp", "subagent", "hooks", "validator"]
    }
  ]
}
```

- [ ] **Step 3: Create `.gitignore`**

```
# Plugin data (runtime state, not source)
plugin-data/
*.lock
!brainstorm.lock
```

- [ ] **Step 4: Write manifest validation test**

Create `tests/manifests.bats`:

```bash
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
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd ~/workspace/gemini-plugin && bats tests/manifests.bats`
Expected: 6 tests, all passing

- [ ] **Step 6: Commit**

```bash
git add .claude-plugin/ .gitignore tests/manifests.bats
git commit -m "feat: add plugin and marketplace manifests"
```

---

## Task 2: Hook library (shared helpers)

**Files:**
- Create: `hooks/lib/common.sh`
- Create: `hooks/lib/prompt-builder.sh`
- Test: `tests/hooks-lib.bats`

- [ ] **Step 1: Write `hooks/lib/common.sh`**

```bash
#!/usr/bin/env bash
# Shared helpers for all hook scripts.

# Check if GEMINI_API_KEY is available. If not, print advisory and exit 0.
check_gemini_available() {
  if [ -z "${GEMINI_API_KEY:-}" ]; then
    echo "[gemini-plugin] GEMINI_API_KEY not set; skipping Gemini consultation." >&2
    exit 0
  fi
}

# Check if plugin disable env is set.
check_plugin_enabled() {
  if [ "${CLAUDE_PLUGIN_GEMINI_DISABLE_HOOKS:-0}" = "1" ]; then
    exit 0
  fi
}

# Ensure CLAUDE_PLUGIN_DATA_DIR exists.
ensure_data_dir() {
  mkdir -p "${CLAUDE_PLUGIN_DATA_DIR:-/tmp/gemini-plugin-data}"
}

# Compute a short hash of the git repo root for cache keying.
repo_hash() {
  local root
  root=$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")
  echo -n "$root" | shasum -a 256 | cut -c1-12
}

# Detect if brainstorming session is active.
# Returns 0 (true) if brainstorming detected, 1 otherwise.
is_brainstorming() {
  local data_dir="${CLAUDE_PLUGIN_DATA_DIR:-/tmp/gemini-plugin-data}"
  # Signal 4: explicit lock file
  if [ -f "${data_dir}/brainstorm.lock" ]; then
    return 0
  fi
  # Signal from stdin context (signals 1-3 checked by caller via prompt content)
  return 1
}

# Read the last N plan-history entries for a specific task type.
get_plan_history() {
  local task_type="$1"
  local count="${2:-3}"
  local data_dir="${CLAUDE_PLUGIN_DATA_DIR:-/tmp/gemini-plugin-data}"
  local history_file="${data_dir}/plan-history.jsonl"

  if [ ! -f "$history_file" ]; then
    echo "[]"
    return
  fi

  grep "\"task\":\"${task_type}\"" "$history_file" | tail -n "$count" | jq -s '.'
}

# Matches a command string against destructive patterns.
# Returns 0 if destructive, 1 if safe.
is_destructive_command() {
  local cmd="$1"
  echo "$cmd" | grep -qE '\brm\s+(-[a-zA-Z]*f|-[a-zA-Z]*r|--force)[a-zA-Z ]*|--force|reset\s+--hard|\bDROP\b|\bTRUNCATE\b|git\s+push\s+.*--force|\bdd\s+if='
}
```

- [ ] **Step 2: Write `hooks/lib/prompt-builder.sh`**

```bash
#!/usr/bin/env bash
# Builds directive strings emitted to stderr by hook scripts.

# Build a directive for Claude to spawn a subagent.
# Usage: build_directive <agent_name> <task_type> <context_text>
build_directive() {
  local agent="$1"
  local task="$2"
  local context="$3"

  cat <<EOF
[gemini-plugin] Spawning @agent-gemini-plugin:${agent} with task=${task}.

Context for the subagent:
${context}

IMPORTANT: Block until the subagent returns its structured JSON verdict. If verdict is "fail", address the listed gaps before continuing.
EOF
}

# Build directive for risk map generation.
build_risk_map_directive() {
  local repo_root="$1"
  local tree_output="$2"

  build_directive "gemini-summarizer" "BUILD_RISK_MAP" \
    "Scan this repository and produce a risk_map.json identifying high-risk zones (legacy code, low test coverage, complex state, fragile integrations).

Repository root: ${repo_root}
Directory tree (depth 4):
${tree_output}"
}

# Build directive for prompt grounding.
build_grounding_directive() {
  local user_prompt="$1"

  build_directive "gemini-researcher" "GROUND_PROMPT" \
    "The user submitted a prompt that may reference post-training-cutoff information. Use gemini_search_grounded to find current, authoritative sources. Return answer + citations.

User prompt:
${user_prompt}"
}

# Build directive for plan validation.
build_plan_validation_directive() {
  local plan_text="$1"
  local history_summary="$2"

  build_directive "gemini-validator" "VALIDATE_PLAN" \
    "Review this plan for gaps, hallucinations, and missed acceptance criteria. Return structured JSON verdict.

Plan:
${plan_text}

Previous rejected plans (for context, do not re-raise already-addressed issues):
${history_summary}"
}

# Build directive for destructive op challenge.
build_destructive_challenge_directive() {
  local command="$1"

  build_directive "gemini-challenger" "CHALLENGE_DESTRUCTIVE_OP" \
    "The main agent is about to execute a potentially destructive command. Challenge this decision: propose at least 2 safer alternatives and 1 reason this specific command might be wrong.

Command to execute:
${command}"
}

# Build directive for session state summary.
build_precompact_directive() {
  local session_context="$1"

  build_directive "gemini-summarizer" "SUMMARIZE_SESSION_STATE" \
    "Context is about to be compacted. Summarize: (1) decisions made, (2) alternatives discarded with reasons, (3) unresolved debt. Return structured JSON.

Session context (last portion):
${session_context}"
}

# Build directive for done-claim validation.
build_done_claim_directive() {
  local original_ask="$1"
  local final_claim="$2"
  local diff_summary="$3"

  build_directive "gemini-validator" "VALIDATE_DONE_CLAIM" \
    "The main agent claims the task is complete. Validate against the original ask. Return structured JSON verdict.

Original ask:
${original_ask}

Final claim:
${final_claim}

Diff summary:
${diff_summary}"
}
```

- [ ] **Step 3: Write tests for the helpers**

Create `tests/hooks-lib.bats`:

```bash
#!/usr/bin/env bats

setup() {
  export CLAUDE_PLUGIN_DATA_DIR="$BATS_TMPDIR/test-data-$$"
  mkdir -p "$CLAUDE_PLUGIN_DATA_DIR"
  source hooks/lib/common.sh
}

teardown() {
  rm -rf "$CLAUDE_PLUGIN_DATA_DIR"
}

@test "check_gemini_available exits 0 with advisory when key unset" {
  unset GEMINI_API_KEY
  run bash -c 'source hooks/lib/common.sh; check_gemini_available'
  [ "$status" -eq 0 ]
  [[ "$output" == *"GEMINI_API_KEY not set"* ]]
}

@test "check_gemini_available passes when key is set" {
  export GEMINI_API_KEY="test-key"
  run bash -c 'source hooks/lib/common.sh; check_gemini_available'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "check_plugin_enabled exits 0 when disabled" {
  export CLAUDE_PLUGIN_GEMINI_DISABLE_HOOKS=1
  run bash -c 'source hooks/lib/common.sh; check_plugin_enabled'
  [ "$status" -eq 0 ]
}

@test "repo_hash returns 12 char hex string" {
  run bash -c 'source hooks/lib/common.sh; repo_hash'
  [ "$status" -eq 0 ]
  [[ "${output}" =~ ^[a-f0-9]{12}$ ]]
}

@test "is_brainstorming returns 0 when lock file exists" {
  touch "$CLAUDE_PLUGIN_DATA_DIR/brainstorm.lock"
  run bash -c "source hooks/lib/common.sh; is_brainstorming"
  [ "$status" -eq 0 ]
}

@test "is_brainstorming returns 1 when no lock file" {
  run bash -c "source hooks/lib/common.sh; is_brainstorming"
  [ "$status" -eq 1 ]
}

@test "is_destructive_command matches rm -rf" {
  run bash -c 'source hooks/lib/common.sh; is_destructive_command "rm -rf /tmp/foo"'
  [ "$status" -eq 0 ]
}

@test "is_destructive_command matches git push --force" {
  run bash -c 'source hooks/lib/common.sh; is_destructive_command "git push origin main --force"'
  [ "$status" -eq 0 ]
}

@test "is_destructive_command matches DROP TABLE" {
  run bash -c 'source hooks/lib/common.sh; is_destructive_command "psql -c DROP TABLE users"'
  [ "$status" -eq 0 ]
}

@test "is_destructive_command passes safe commands" {
  run bash -c 'source hooks/lib/common.sh; is_destructive_command "ls -la"'
  [ "$status" -eq 1 ]
}

@test "is_destructive_command passes git push without force" {
  run bash -c 'source hooks/lib/common.sh; is_destructive_command "git push origin main"'
  [ "$status" -eq 1 ]
}

@test "get_plan_history returns empty array when no file" {
  run bash -c 'source hooks/lib/common.sh; get_plan_history "VALIDATE_PLAN"'
  [ "$status" -eq 0 ]
  [ "$output" = "[]" ]
}

@test "get_plan_history returns last N entries" {
  echo '{"task":"VALIDATE_PLAN","verdict":"fail","gaps":["gap1"]}' >> "$CLAUDE_PLUGIN_DATA_DIR/plan-history.jsonl"
  echo '{"task":"VALIDATE_PLAN","verdict":"pass","gaps":[]}' >> "$CLAUDE_PLUGIN_DATA_DIR/plan-history.jsonl"
  echo '{"task":"CHALLENGE_DESTRUCTIVE_OP","verdict":"pass"}' >> "$CLAUDE_PLUGIN_DATA_DIR/plan-history.jsonl"
  run bash -c 'source hooks/lib/common.sh; get_plan_history "VALIDATE_PLAN" 2'
  [ "$status" -eq 0 ]
  RESULT=$(echo "$output" | jq length)
  [ "$RESULT" -eq 2 ]
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd ~/workspace/gemini-plugin && bats tests/hooks-lib.bats`
Expected: 13 tests, all passing

- [ ] **Step 5: Commit**

```bash
git add hooks/lib/ tests/hooks-lib.bats
git commit -m "feat: add hook library (common.sh + prompt-builder.sh)"
```

---

## Task 3: Hook scripts (6 triggers + verdict handler)

**Files:**
- Create: `hooks/hooks.json`
- Create: `hooks/session-start-risk-map.sh`
- Create: `hooks/user-prompt-grounding.sh`
- Create: `hooks/plan-complete.sh`
- Create: `hooks/pre-destructive-bash.sh`
- Create: `hooks/pre-compact-summary.sh`
- Create: `hooks/stop-done-claim.sh`
- Create: `hooks/subagent-verdict-handler.sh`
- Test: `tests/hooks-triggers.bats`

- [ ] **Step 1: Create `hooks/hooks.json`**

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "startup",
        "hooks": [
          { "type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/hooks/session-start-risk-map.sh", "async": false }
        ]
      }
    ],
    "UserPromptSubmit": [
      {
        "hooks": [
          { "type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/hooks/user-prompt-grounding.sh", "async": false }
        ]
      }
    ],
    "ExitPlanMode": [
      {
        "hooks": [
          { "type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/hooks/plan-complete.sh", "async": false }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/hooks/pre-destructive-bash.sh", "async": false }
        ]
      }
    ],
    "PreCompact": [
      {
        "hooks": [
          { "type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/hooks/pre-compact-summary.sh", "async": false }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          { "type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/hooks/stop-done-claim.sh", "async": false }
        ]
      }
    ],
    "SubagentStop": [
      {
        "matcher": "gemini-validator|gemini-challenger|gemini-researcher|gemini-summarizer",
        "hooks": [
          { "type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/hooks/subagent-verdict-handler.sh", "async": false }
        ]
      }
    ]
  }
}
```

- [ ] **Step 2: Create `hooks/session-start-risk-map.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/prompt-builder.sh"

check_plugin_enabled
check_gemini_available
ensure_data_dir

HASH=$(repo_hash)
RISK_MAP="${CLAUDE_PLUGIN_DATA_DIR}/risk-map-${HASH}.json"

# TTL check: skip if risk map exists and is < 24h old
if [ -f "$RISK_MAP" ]; then
  AGE=$(( $(date +%s) - $(stat -f %m "$RISK_MAP" 2>/dev/null || stat -c %Y "$RISK_MAP" 2>/dev/null || echo 0) ))
  if [ "$AGE" -lt 86400 ]; then
    exit 0
  fi
fi

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")
TREE=$(find "$REPO_ROOT" -maxdepth 4 -type f \( -name "*.go" -o -name "*.py" -o -name "*.ts" -o -name "*.js" -o -name "*.java" -o -name "*.kt" \) | head -200 | sed "s|${REPO_ROOT}/||" | sort)

DIRECTIVE=$(build_risk_map_directive "$REPO_ROOT" "$TREE")
echo "$DIRECTIVE" >&2
exit 2
```

- [ ] **Step 3: Create `hooks/user-prompt-grounding.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/prompt-builder.sh"

check_plugin_enabled
check_gemini_available
ensure_data_dir

INPUT=$(cat)
USER_PROMPT=$(echo "$INPUT" | jq -r '.prompt // empty')

if [ -z "$USER_PROMPT" ]; then
  exit 0
fi

# Gate logic: always-on during brainstorming, regex-gated otherwise
if ! is_brainstorming; then
  if ! echo "$USER_PROMPT" | grep -qiE '\b(api|cve|version|release|deprecated|library|package|sdk|framework|upgrade|migrate)\b'; then
    exit 0
  fi
fi

DIRECTIVE=$(build_grounding_directive "$USER_PROMPT")
echo "$DIRECTIVE" >&2
exit 2
```

- [ ] **Step 4: Create `hooks/plan-complete.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/prompt-builder.sh"

check_plugin_enabled
check_gemini_available
ensure_data_dir

INPUT=$(cat)
PLAN_TEXT=$(echo "$INPUT" | jq -r '.plan // .content // empty')

if [ -z "$PLAN_TEXT" ]; then
  exit 0
fi

HISTORY=$(get_plan_history "VALIDATE_PLAN" 3)
DIRECTIVE=$(build_plan_validation_directive "$PLAN_TEXT" "$HISTORY")
echo "$DIRECTIVE" >&2
exit 2
```

- [ ] **Step 5: Create `hooks/pre-destructive-bash.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/prompt-builder.sh"

check_plugin_enabled
check_gemini_available

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

if [ -z "$COMMAND" ]; then
  exit 0
fi

if ! is_destructive_command "$COMMAND"; then
  exit 0
fi

DIRECTIVE=$(build_destructive_challenge_directive "$COMMAND")
echo "$DIRECTIVE" >&2
exit 2
```

- [ ] **Step 6: Create `hooks/pre-compact-summary.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/prompt-builder.sh"

check_plugin_enabled
check_gemini_available
ensure_data_dir

INPUT=$(cat)
SESSION_CONTEXT=$(echo "$INPUT" | jq -r '.context // .content // empty' | tail -c 16384)

if [ -z "$SESSION_CONTEXT" ]; then
  exit 0
fi

DIRECTIVE=$(build_precompact_directive "$SESSION_CONTEXT")
echo "$DIRECTIVE" >&2
exit 2
```

- [ ] **Step 7: Create `hooks/stop-done-claim.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/prompt-builder.sh"

check_plugin_enabled
check_gemini_available
ensure_data_dir

INPUT=$(cat)
ASSISTANT_MESSAGE=$(echo "$INPUT" | jq -r '.assistant_message // .content // empty')
ORIGINAL_ASK=$(echo "$INPUT" | jq -r '.original_ask // empty')
TOOL_USED=$(echo "$INPUT" | jq -r '.tool_used // "false"')

# Only fire if a tool was used in this session
if [ "$TOOL_USED" != "true" ]; then
  exit 0
fi

# Claim detector: check for completion language
if ! echo "$ASSISTANT_MESSAGE" | grep -qiE '\b(done|completed|finished|ready|fixed|passing|resolved|implemented)\b'; then
  exit 0
fi

DIFF_SUMMARY=$(git diff --stat HEAD~1 2>/dev/null | tail -20 || echo "(no git diff available)")
DIRECTIVE=$(build_done_claim_directive "$ORIGINAL_ASK" "$ASSISTANT_MESSAGE" "$DIFF_SUMMARY")
echo "$DIRECTIVE" >&2
exit 2
```

- [ ] **Step 8: Create `hooks/subagent-verdict-handler.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

ensure_data_dir

INPUT=$(cat)
AGENT=$(echo "$INPUT" | jq -r '.agent_type')
TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path // empty')

if [ -z "$TRANSCRIPT" ] || [ ! -f "$TRANSCRIPT" ]; then
  exit 0
fi

# Extract the agent's final JSON message (look for structured output in last 50 lines)
VERDICT_JSON=$(tail -50 "$TRANSCRIPT" | jq -rs '
  [.[] | select(.type=="assistant")] | last
  | .message.content[0].text // empty
' 2>/dev/null | tail -c 8192)

if [ -z "$VERDICT_JSON" ]; then
  exit 0
fi

# Try to parse as JSON; if not JSON, treat as advisory
VERDICT=$(echo "$VERDICT_JSON" | jq -r '.verdict // "advisory"' 2>/dev/null || echo "advisory")
GAPS=$(echo "$VERDICT_JSON" | jq -r '.gaps // .objections // .must_address // [] | if type == "array" then join("\n- ") else . end' 2>/dev/null || echo "")

# Loop guard: identical verdict twice in a row -> downgrade to advisory
LAST_FILE="${CLAUDE_PLUGIN_DATA_DIR}/last-verdict-${AGENT}.txt"
LAST=$(cat "$LAST_FILE" 2>/dev/null || echo "")
if [ "$VERDICT" = "fail" ] && [ "$VERDICT_JSON" = "$LAST" ]; then
  VERDICT="advisory"
fi
echo "$VERDICT_JSON" > "$LAST_FILE"

# Persist for plan-history
echo "{\"task\":\"$(echo "$INPUT" | jq -r '.task // "unknown"')\",\"agent\":\"${AGENT}\",\"verdict\":\"${VERDICT}\",\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}" >> "${CLAUDE_PLUGIN_DATA_DIR}/plan-history.jsonl"

if [ "$VERDICT" = "fail" ] || [ "$VERDICT" = "block" ]; then
  cat >&2 <<EOF
[gemini-plugin] ${AGENT} verdict: ${VERDICT}
Issues to address before continuing:
- ${GAPS}
EOF
  exit 2
fi
exit 0
```

- [ ] **Step 9: Make all scripts executable**

```bash
chmod +x hooks/session-start-risk-map.sh hooks/user-prompt-grounding.sh hooks/plan-complete.sh hooks/pre-destructive-bash.sh hooks/pre-compact-summary.sh hooks/stop-done-claim.sh hooks/subagent-verdict-handler.sh
```

- [ ] **Step 10: Write trigger hook tests**

Create `tests/hooks-triggers.bats`:

```bash
#!/usr/bin/env bats

setup() {
  export CLAUDE_PLUGIN_DATA_DIR="$BATS_TMPDIR/test-data-$$"
  export GEMINI_API_KEY="test-key"
  export CLAUDE_PLUGIN_GEMINI_DISABLE_HOOKS=0
  mkdir -p "$CLAUDE_PLUGIN_DATA_DIR"
}

teardown() {
  rm -rf "$CLAUDE_PLUGIN_DATA_DIR"
}

# --- session-start-risk-map ---

@test "session-start: exits 0 when GEMINI_API_KEY unset" {
  unset GEMINI_API_KEY
  run bash -c 'echo "{}" | ./hooks/session-start-risk-map.sh'
  [ "$status" -eq 0 ]
}

@test "session-start: exits 0 when risk map is fresh" {
  HASH=$(bash -c 'source hooks/lib/common.sh; repo_hash')
  touch "$CLAUDE_PLUGIN_DATA_DIR/risk-map-${HASH}.json"
  run bash -c 'echo "{}" | ./hooks/session-start-risk-map.sh'
  [ "$status" -eq 0 ]
}

@test "session-start: exits 2 when risk map missing" {
  run bash -c 'echo "{}" | ./hooks/session-start-risk-map.sh'
  [ "$status" -eq 2 ]
  [[ "$output" == *"gemini-summarizer"* ]]
  [[ "$output" == *"BUILD_RISK_MAP"* ]]
}

# --- user-prompt-grounding ---

@test "user-prompt-grounding: exits 0 when no matching keywords and not brainstorming" {
  run bash -c 'echo "{\"prompt\":\"fix this typo\"}" | ./hooks/user-prompt-grounding.sh'
  [ "$status" -eq 0 ]
}

@test "user-prompt-grounding: exits 2 when keyword matches" {
  run bash -c 'echo "{\"prompt\":\"what is the latest version of react?\"}" | ./hooks/user-prompt-grounding.sh'
  [ "$status" -eq 2 ]
  [[ "$output" == *"gemini-researcher"* ]]
}

@test "user-prompt-grounding: exits 2 unconditionally when brainstorming" {
  touch "$CLAUDE_PLUGIN_DATA_DIR/brainstorm.lock"
  run bash -c 'echo "{\"prompt\":\"fix this typo\"}" | ./hooks/user-prompt-grounding.sh'
  [ "$status" -eq 2 ]
  [[ "$output" == *"GROUND_PROMPT"* ]]
}

# --- pre-destructive-bash ---

@test "pre-destructive-bash: exits 0 for safe command" {
  run bash -c 'echo "{\"tool_input\":{\"command\":\"ls -la\"}}" | ./hooks/pre-destructive-bash.sh'
  [ "$status" -eq 0 ]
}

@test "pre-destructive-bash: exits 2 for rm -rf" {
  run bash -c 'echo "{\"tool_input\":{\"command\":\"rm -rf /tmp/foo\"}}" | ./hooks/pre-destructive-bash.sh'
  [ "$status" -eq 2 ]
  [[ "$output" == *"gemini-challenger"* ]]
  [[ "$output" == *"CHALLENGE_DESTRUCTIVE_OP"* ]]
}

@test "pre-destructive-bash: exits 2 for git push --force" {
  run bash -c 'echo "{\"tool_input\":{\"command\":\"git push origin main --force\"}}" | ./hooks/pre-destructive-bash.sh'
  [ "$status" -eq 2 ]
}

@test "pre-destructive-bash: exits 2 for DROP TABLE" {
  run bash -c 'echo "{\"tool_input\":{\"command\":\"psql -c \\\"DROP TABLE users\\\"\"}}" | ./hooks/pre-destructive-bash.sh'
  [ "$status" -eq 2 ]
}

# --- plan-complete ---

@test "plan-complete: exits 2 with validator directive" {
  run bash -c 'echo "{\"plan\":\"Step 1: do X. Step 2: do Y.\"}" | ./hooks/plan-complete.sh'
  [ "$status" -eq 2 ]
  [[ "$output" == *"gemini-validator"* ]]
  [[ "$output" == *"VALIDATE_PLAN"* ]]
}

@test "plan-complete: exits 0 when plan is empty" {
  run bash -c 'echo "{\"plan\":\"\"}" | ./hooks/plan-complete.sh'
  [ "$status" -eq 0 ]
}

# --- stop-done-claim ---

@test "stop-done-claim: exits 0 when no tool used" {
  run bash -c 'echo "{\"assistant_message\":\"Done!\",\"tool_used\":\"false\"}" | ./hooks/stop-done-claim.sh'
  [ "$status" -eq 0 ]
}

@test "stop-done-claim: exits 0 when no completion word" {
  run bash -c 'echo "{\"assistant_message\":\"Here is the code\",\"tool_used\":\"true\"}" | ./hooks/stop-done-claim.sh'
  [ "$status" -eq 0 ]
}

@test "stop-done-claim: exits 2 when tool used and completion claimed" {
  run bash -c 'echo "{\"assistant_message\":\"I have completed the task.\",\"tool_used\":\"true\",\"original_ask\":\"add a button\"}" | ./hooks/stop-done-claim.sh'
  [ "$status" -eq 2 ]
  [[ "$output" == *"VALIDATE_DONE_CLAIM"* ]]
}

# --- subagent-verdict-handler ---

@test "verdict-handler: exits 0 when no transcript" {
  run bash -c 'echo "{\"agent_type\":\"gemini-validator\",\"transcript_path\":\"\"}" | ./hooks/subagent-verdict-handler.sh'
  [ "$status" -eq 0 ]
}

@test "verdict-handler: exits 0 on pass verdict" {
  TRANSCRIPT="$BATS_TMPDIR/transcript-$$.jsonl"
  echo '{"type":"assistant","message":{"content":[{"text":"{\"verdict\":\"pass\",\"gaps\":[]}"}]}}' > "$TRANSCRIPT"
  run bash -c "echo '{\"agent_type\":\"gemini-validator\",\"transcript_path\":\"${TRANSCRIPT}\"}' | ./hooks/subagent-verdict-handler.sh"
  [ "$status" -eq 0 ]
}

@test "verdict-handler: exits 2 on fail verdict" {
  TRANSCRIPT="$BATS_TMPDIR/transcript-$$.jsonl"
  echo '{"type":"assistant","message":{"content":[{"text":"{\"verdict\":\"fail\",\"gaps\":[\"missing tests\"]}"}]}}' > "$TRANSCRIPT"
  run bash -c "echo '{\"agent_type\":\"gemini-validator\",\"transcript_path\":\"${TRANSCRIPT}\"}' | ./hooks/subagent-verdict-handler.sh"
  [ "$status" -eq 2 ]
  [[ "$output" == *"missing tests"* ]]
}

@test "verdict-handler: loop guard demotes repeat fail to advisory" {
  TRANSCRIPT="$BATS_TMPDIR/transcript-$$.jsonl"
  VERDICT='{"verdict":"fail","gaps":["same gap"]}'
  echo "{\"type\":\"assistant\",\"message\":{\"content\":[{\"text\":\"${VERDICT}\"}]}}" > "$TRANSCRIPT"
  # First call: blocks
  echo "$VERDICT" > "$CLAUDE_PLUGIN_DATA_DIR/last-verdict-gemini-validator.txt"
  run bash -c "echo '{\"agent_type\":\"gemini-validator\",\"transcript_path\":\"${TRANSCRIPT}\"}' | ./hooks/subagent-verdict-handler.sh"
  [ "$status" -eq 0 ]
}

# --- plugin disable ---

@test "all hooks exit 0 when CLAUDE_PLUGIN_GEMINI_DISABLE_HOOKS=1" {
  export CLAUDE_PLUGIN_GEMINI_DISABLE_HOOKS=1
  run bash -c 'echo "{\"prompt\":\"what version of react?\"}" | ./hooks/user-prompt-grounding.sh'
  [ "$status" -eq 0 ]
  run bash -c 'echo "{\"tool_input\":{\"command\":\"rm -rf /\"}}" | ./hooks/pre-destructive-bash.sh'
  [ "$status" -eq 0 ]
}
```

- [ ] **Step 11: Run tests to verify they pass**

Run: `cd ~/workspace/gemini-plugin && bats tests/hooks-triggers.bats`
Expected: 17 tests, all passing

- [ ] **Step 12: Commit**

```bash
git add hooks/ tests/hooks-triggers.bats
git commit -m "feat: add hook scripts (6 triggers + verdict handler)"
```

---

## Task 4: Subagents (4 agent definitions)

**Files:**
- Create: `agents/gemini-validator.md`
- Create: `agents/gemini-challenger.md`
- Create: `agents/gemini-researcher.md`
- Create: `agents/gemini-summarizer.md`
- Test: `tests/agents.bats`

- [ ] **Step 1: Create `agents/gemini-validator.md`**

```markdown
---
name: gemini-validator
description: |
  Use proactively after a plan is finalized, after Claude claims a task is done,
  or before a destructive change. Validates the artifact against the original ask
  and flags gaps, hallucinations, and missed acceptance criteria. Returns
  structured JSON {verdict, gaps, hallucinations, next_actions}.
tools:
  - mcp__gemini__gemini_generate
  - mcp__gemini__gemini_search_grounded
  - Read
  - Grep
  - Glob
model: haiku
color: blue
maxTurns: 3
effort: medium
memory: project
skills:
  - gemini-when-to-use
---

You are gemini-validator: a precise, skeptical reviewer powered by Google Gemini.

Your job: read the artifact you were handed (a plan, a diff, a done-claim) and
return ONE structured JSON verdict. No preamble, no commentary outside the JSON.

## How to work

1. Read the artifact carefully. Identify the original ask or acceptance criteria.
2. Call `mcp__gemini__gemini_generate` with a system instruction asking Gemini to
   review the artifact for completeness, correctness, and hallucinations.
3. If any claim references a library version, API, or CVE, call
   `mcp__gemini__gemini_search_grounded` to verify.
4. Synthesize Gemini's output into the verdict schema below.

## Output schema (emit ONLY this JSON, nothing else)

```json
{
  "verdict": "pass | fail",
  "gaps": ["..."],
  "hallucinations": ["..."],
  "next_actions": ["..."]
}
```

## Rules

- verdict=pass means all acceptance criteria are met and no hallucinations found.
- verdict=fail means at least one gap or hallucination exists.
- gaps: acceptance criteria that are missing or incomplete.
- hallucinations: claims in the artifact not supported by code, docs, or Gemini's
  verification.
- next_actions: concrete, ordered fixes. Not vague ("add tests") but specific
  ("add a test for the empty-input case in validate_plan()").
- Anti-loop: if the main agent already addressed your previous critique (check
  your agent memory), emit verdict=pass with next_actions=["Previously raised
  issues are resolved."]. Do not re-raise the same objection.
```

- [ ] **Step 2: Create `agents/gemini-challenger.md`**

```markdown
---
name: gemini-challenger
description: |
  Use proactively before destructive operations, when evaluating architectural
  choices, or when the main agent appears stuck in a pattern. Devil's advocate
  that argues at least 2 alternative approaches and 1 reason the current path
  is wrong. Returns structured JSON {alternatives, objections, must_address}.
tools:
  - mcp__gemini__gemini_generate
  - mcp__gemini__gemini_chat
  - Read
model: sonnet
color: red
maxTurns: 4
effort: high
skills:
  - gemini-when-to-use
---

You are gemini-challenger: a constructive devil's advocate powered by Google Gemini.

Your job: challenge the main agent's proposed action or decision. Find the flaws,
propose alternatives, and force rigorous justification.

## How to work

1. Read the proposed action/decision/command carefully.
2. Call `mcp__gemini__gemini_generate` asking Gemini to brainstorm:
   - At least 2 concrete alternative approaches
   - At least 1 specific reason the current approach could fail or cause harm
   - For destructive commands: safer equivalent commands that achieve the same goal
3. Synthesize into the verdict schema below.

## Output schema (emit ONLY this JSON, nothing else)

```json
{
  "verdict": "pass | fail | block",
  "alternatives": [
    {"approach": "...", "tradeoff": "..."},
    {"approach": "...", "tradeoff": "..."}
  ],
  "objections": ["..."],
  "must_address": ["..."]
}
```

## Rules

- verdict=pass: the proposed action is reasonable; alternatives exist but aren't
  clearly better. Include them anyway for the user's awareness.
- verdict=fail: there are significant concerns. The main agent should address
  must_address items before proceeding.
- verdict=block: the proposed action is dangerous with a safer alternative
  available. Only use for destructive operations (rm -rf, force push, DROP, etc.).
- alternatives: always at least 2, with concrete tradeoffs.
- objections: specific failure scenarios, not vague warnings.
- must_address: the minimum set of concerns that MUST be resolved. Keep this
  short (1-3 items). If empty, verdict should be pass.
- Never be contrarian for the sake of it. If the action is clearly correct and
  safe, say so (verdict=pass) and still note the alternatives.
```

- [ ] **Step 3: Create `agents/gemini-researcher.md`**

```markdown
---
name: gemini-researcher
description: |
  Use proactively when a question involves post-training-cutoff information,
  live API docs, recent CVEs, library releases, or any claim that needs a
  primary source. Performs search-grounded research and deep research via
  Gemini. Never opines without a citation. Returns answer + citations.
tools:
  - mcp__gemini__gemini_search_grounded
  - mcp__gemini__gemini_start_research
  - mcp__gemini__gemini_get_research_report
  - Read
model: haiku
color: green
maxTurns: 6
effort: medium
background: true
skills:
  - gemini-when-to-use
---

You are gemini-researcher: a fact-finding agent powered by Google Gemini's
search-grounded and deep research capabilities.

Your job: find authoritative, cited answers to factual questions. Never assert
a fact without a URL source.

## How to work

1. Read the research question.
2. For quick factual lookups (library versions, API status, CVE details):
   - Call `mcp__gemini__gemini_search_grounded` with the question.
   - Return the answer + citations immediately.
3. For deeper synthesis (architecture comparisons, migration guides, multi-source):
   - Call `mcp__gemini__gemini_start_research` to begin a deep research job.
   - Poll with `mcp__gemini__gemini_get_research_report` until status=done.
   - Return the full report.
4. Synthesize into the output schema below.

## Output schema (emit ONLY this JSON, nothing else)

```json
{
  "answer": "...",
  "citations": [
    {"url": "...", "title": "...", "relevance": "..."}
  ],
  "freshness": "YYYY-MM-DD",
  "confidence": "high | medium | low",
  "model": "..."
}
```

## Rules

- Every factual claim must have at least one citation.
- freshness: the date the information was retrieved (today's date).
- confidence: high if multiple authoritative sources agree; medium if one source;
  low if sources conflict or are unofficial.
- If no sources are found, return confidence=low and say so explicitly.
- Never fabricate citations. If search returns nothing useful, say "no results."
- For deep research, include model field showing which research model was used.
```

- [ ] **Step 4: Create `agents/gemini-summarizer.md`**

```markdown
---
name: gemini-summarizer
description: |
  Use proactively at session start (BUILD_RISK_MAP) and before context
  compaction (SUMMARIZE_SESSION_STATE). Compresses session history into
  structured summaries preserving decisions, discarded alternatives, and
  unresolved debt. Writes risk maps for new repositories.
tools:
  - mcp__gemini__gemini_generate
  - Read
  - Glob
model: sonnet
color: purple
maxTurns: 2
effort: high
memory: project
skills:
  - gemini-when-to-use
---

You are gemini-summarizer: a structured compression agent powered by Google Gemini.

Your job: produce concise, structured summaries that preserve institutional
knowledge across context compaction boundaries.

## Tasks

### BUILD_RISK_MAP

When task=BUILD_RISK_MAP, scan the provided directory tree and produce:

```json
{
  "repo_root": "/path/to/repo",
  "generated_at": "YYYY-MM-DDTHH:MM:SSZ",
  "high_risk_zones": [
    {
      "path": "relative/path",
      "reason": "why this is high-risk",
      "suggestion": "what to watch for"
    }
  ],
  "missing_tests": ["paths with code but no corresponding test files"],
  "complex_state": ["files with high cyclomatic complexity indicators"],
  "fragile_integrations": ["external dependencies with version pins or known issues"]
}
```

Use `mcp__gemini__gemini_generate` with the directory tree to identify risk zones.
Use `Read` and `Glob` to spot-check specific patterns (e.g., files without test
counterparts, deeply nested directories).

### SUMMARIZE_SESSION_STATE

When task=SUMMARIZE_SESSION_STATE, produce:

```json
{
  "session_id": "...",
  "summarized_at": "YYYY-MM-DDTHH:MM:SSZ",
  "decisions_made": ["..."],
  "alternatives_discarded": [
    {"option": "...", "reason_rejected": "..."}
  ],
  "unresolved_debt": ["..."],
  "key_files_modified": ["..."],
  "next_steps_implied": ["..."]
}
```

Use `mcp__gemini__gemini_generate` to compress the session context into this schema.

## Rules

- Output ONLY the JSON schema for the active task. No preamble.
- Keep arrays concise: max 10 items per array, prioritized by importance.
- Decisions should be worded as "chose X over Y because Z."
- Update your agent memory with patterns you notice across sessions.
```

- [ ] **Step 5: Write agent validation tests**

Create `tests/agents.bats`:

```bash
#!/usr/bin/env bats

AGENTS_DIR="agents"

@test "all 4 agent files exist" {
  [ -f "$AGENTS_DIR/gemini-validator.md" ]
  [ -f "$AGENTS_DIR/gemini-challenger.md" ]
  [ -f "$AGENTS_DIR/gemini-researcher.md" ]
  [ -f "$AGENTS_DIR/gemini-summarizer.md" ]
}

extract_frontmatter() {
  sed -n '/^---$/,/^---$/p' "$1" | sed '1d;$d'
}

@test "gemini-validator has required frontmatter fields" {
  FM=$(extract_frontmatter "$AGENTS_DIR/gemini-validator.md")
  echo "$FM" | grep -q "^name: gemini-validator"
  echo "$FM" | grep -q "^description:"
  echo "$FM" | grep -q "^model: haiku"
  echo "$FM" | grep -q "^color: blue"
  echo "$FM" | grep -q "^maxTurns: 3"
  echo "$FM" | grep -q "mcp__gemini__gemini_generate"
}

@test "gemini-challenger has required frontmatter fields" {
  FM=$(extract_frontmatter "$AGENTS_DIR/gemini-challenger.md")
  echo "$FM" | grep -q "^name: gemini-challenger"
  echo "$FM" | grep -q "^model: sonnet"
  echo "$FM" | grep -q "^color: red"
  echo "$FM" | grep -q "^maxTurns: 4"
  echo "$FM" | grep -q "^effort: high"
}

@test "gemini-researcher has required frontmatter fields" {
  FM=$(extract_frontmatter "$AGENTS_DIR/gemini-researcher.md")
  echo "$FM" | grep -q "^name: gemini-researcher"
  echo "$FM" | grep -q "^model: haiku"
  echo "$FM" | grep -q "^color: green"
  echo "$FM" | grep -q "^maxTurns: 6"
  echo "$FM" | grep -q "^background: true"
}

@test "gemini-summarizer has required frontmatter fields" {
  FM=$(extract_frontmatter "$AGENTS_DIR/gemini-summarizer.md")
  echo "$FM" | grep -q "^name: gemini-summarizer"
  echo "$FM" | grep -q "^model: sonnet"
  echo "$FM" | grep -q "^color: purple"
  echo "$FM" | grep -q "^maxTurns: 2"
  echo "$FM" | grep -q "^memory: project"
}

@test "all agents preload gemini-when-to-use skill" {
  for agent in validator challenger researcher summarizer; do
    FM=$(extract_frontmatter "$AGENTS_DIR/gemini-${agent}.md")
    echo "$FM" | grep -q "gemini-when-to-use"
  done
}

@test "no agent uses disallowed tools" {
  for agent in validator challenger researcher summarizer; do
    FM=$(extract_frontmatter "$AGENTS_DIR/gemini-${agent}.md")
    ! echo "$FM" | grep -q "Agent"
    ! echo "$FM" | grep -q "AskUserQuestion"
    ! echo "$FM" | grep -q "EnterPlanMode"
    ! echo "$FM" | grep -q "ExitPlanMode"
  done
}

@test "agent descriptions start with 'Use proactively'" {
  for agent in validator challenger researcher summarizer; do
    FM=$(extract_frontmatter "$AGENTS_DIR/gemini-${agent}.md")
    echo "$FM" | grep -q "Use proactively"
  done
}
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `cd ~/workspace/gemini-plugin && bats tests/agents.bats`
Expected: 8 tests, all passing

- [ ] **Step 7: Commit**

```bash
git add agents/ tests/agents.bats
git commit -m "feat: add 4 subagent definitions"
```

---

## Task 5: Skills (8 SKILL.md files)

**Files:**
- Create: `skills/gemini-when-to-use/SKILL.md`
- Create: `skills/gemini-chat-and-reason/SKILL.md`
- Create: `skills/gemini-research-grounded/SKILL.md`
- Create: `skills/gemini-file-analysis/SKILL.md`
- Create: `skills/gemini-code-exec/SKILL.md`
- Create: `skills/gemini-image-gen/SKILL.md`
- Create: `skills/gemini-video-gen/SKILL.md`
- Create: `skills/gemini-audio-tts-music/SKILL.md`
- Test: `tests/skills.bats`

- [ ] **Step 1: Create `skills/gemini-when-to-use/SKILL.md`**

```markdown
---
description: Master router for the Gemini plugin. Use when uncertain whether a Gemini consult is warranted; covers cost discipline, anti-hallucination triggers, and the four subagent roles. Invoke before any other gemini-* skill.
---

# When to use Gemini

This skill tells you WHEN to reach for Gemini's capabilities, not HOW to use them (the capability skills handle that).

## Four subagent roles

| Agent | Role | Trigger |
|---|---|---|
| gemini-validator | Validates plans/diffs/done-claims | After ExitPlanMode, after claiming "done", ad-hoc via /gemini-plugin:gemini-validate |
| gemini-challenger | Devil's advocate, proposes alternatives | Before destructive ops, ad-hoc via /gemini-plugin:gemini-challenge |
| gemini-researcher | Live-web grounding with citations | Post-cutoff questions, ad-hoc via /gemini-plugin:gemini-research |
| gemini-summarizer | Session compression, risk maps | SessionStart, PreCompact (automated) |

## Always use Gemini when

- User asks for "second opinion", "what would another model say", "check this"
- A claim depends on post-training-cutoff information (library versions, recent CVEs, current pricing, current API shapes)
- You're about to run a destructive Bash command and the hook hasn't already fired (multi-line scripts, piped commands the regex misses)
- You're finishing a brainstorming session and want to validate the design

## Never use Gemini when

- The question is already answered by reading one file in context
- The task is a trivial typo fix, formatting, or one-line config change
- You've already received a Gemini verdict on the same artifact this session (re-asking burns tokens and risks echo-chamber)
- The user explicitly says "no Gemini" or "skip validation"

## Cost discipline

- Validator and researcher use haiku (fast, cheap). Challenger and summarizer use sonnet (reasoning quality matters).
- Deep research (`gemini_start_research`) is opt-in via `/gemini-plugin:gemini-research --deep` only. Never auto-trigger.
- If GEMINI_API_KEY is unset, all hooks no-op. Skills should check tool availability before calling.
- One validation per artifact per session. If the same plan/diff/claim was already validated, do not re-validate.

## Capability skills (use AFTER deciding Gemini is needed)

| Skill | When |
|---|---|
| gemini-chat-and-reason | Second opinions, code review, design critique |
| gemini-research-grounded | Post-cutoff facts, live docs, CVE lookups |
| gemini-file-analysis | PDFs, images, audio, video, large source files |
| gemini-code-exec | Verify math, test regex, run snippets in sandbox |
| gemini-image-gen | Mockups, hero images, product shots |
| gemini-video-gen | Short clips, product demos |
| gemini-audio-tts-music | Music, voiceovers, narration |
```

- [ ] **Step 2: Create `skills/gemini-chat-and-reason/SKILL.md`**

```markdown
---
description: Get a second opinion from Gemini via text generation or multi-turn chat. Use for code review, design critique, sanity-checking before commit, or when Claude wants another perspective on a complex decision.
---

# Gemini Chat and Reason

Use this skill when you want Gemini's opinion on something already in your context (code, a plan, an architectural choice).

## Which MCP tool to use

| Scenario | Tool | Why |
|---|---|---|
| One-shot review ("is this correct?") | `mcp__gemini__gemini_generate` | Stateless, cheapest, fastest |
| Multi-turn dialogue ("let's debate this") | `mcp__gemini__gemini_chat` | Retains conversational context |

## Usage pattern

1. Formulate a clear, self-contained prompt. Include the code/plan/artifact inline.
2. Set `system_instruction` to frame Gemini's role (e.g., "You are a senior Go engineer reviewing this diff for correctness bugs.")
3. Call the tool.
4. Present Gemini's response to the user with attribution: "Gemini says: ..."

## When to use gemini_chat (multi-turn)

- Only when you expect 2+ rounds of back-and-forth on the same topic.
- Use a descriptive `session_id` (e.g., `"review-auth-refactor"`) so the conversation is identifiable.
- After 3-4 exchanges, start a fresh session to avoid echo-chamber bias.

## Model selection

- Default: inherits from MCP server config (gemini-3.5-flash for chat, gemini-3.1-pro-preview for generate)
- For complex reasoning: pass `model: "gemini-3.1-pro-preview"` explicitly
- For speed: pass `model: "gemini-3.5-flash"` explicitly

## Do NOT use this skill for

- Questions that need live web data (use gemini-research-grounded instead)
- File analysis of PDFs/images/audio (use gemini-file-analysis instead)
- Math verification (use gemini-code-exec instead)
```

- [ ] **Step 3: Create `skills/gemini-research-grounded/SKILL.md`**

```markdown
---
description: Perform live-web research via Gemini's search-grounded answers or deep research synthesis. Use when a question involves post-training-cutoff information, library versions, CVEs, API docs, or any claim needing a primary source with citations.
---

# Gemini Research (Grounded)

Use this skill when the answer requires up-to-date web information that Claude's training data might not have.

## Which MCP tool to use

| Scenario | Tool | Latency | Cost |
|---|---|---|---|
| Quick factual lookup | `mcp__gemini__gemini_search_grounded` | 2-5s | Low |
| Deep multi-source synthesis | `mcp__gemini__gemini_start_research` + `mcp__gemini__gemini_get_research_report` | 30-120s | High |

## Quick research pattern

```
Tool: mcp__gemini__gemini_search_grounded
  prompt: "What is the latest stable release of fastmcp?"
```

Returns: answer + citations array + model used.

## Deep research pattern (opt-in only)

Only use when explicitly requested via `/gemini-plugin:gemini-research --deep` or when the question clearly requires multi-source synthesis (architecture comparisons, comprehensive migration guides).

```
Tool: mcp__gemini__gemini_start_research
  prompt: "Compare authentication approaches for microservices in 2026: JWT vs OAuth2 vs mTLS. Cover security, performance, and operational complexity."
```

Then poll every 15 seconds:
```
Tool: mcp__gemini__gemini_get_research_report
  job_id: <returned from start>
```

## Always include

- The citation URLs in your response to the user
- A freshness note: "As of [date], [source] says..."
- Confidence indicator: multiple agreeing sources = high, single source = medium

## Do NOT use this skill for

- Questions fully answerable from local files or conversation context
- Opinions or design preferences (use gemini-chat-and-reason)
- File analysis (use gemini-file-analysis)
```

- [ ] **Step 4: Create `skills/gemini-file-analysis/SKILL.md`**

```markdown
---
description: Analyze files (PDFs, images, audio, video, large source files) via Gemini's multi-modal file analysis. Use when a file is too large for Claude's context or when the file is a non-text format requiring visual/audio understanding.
---

# Gemini File Analysis

Use this skill when you need to understand a file that is either too large for Claude's context window or is a non-text format.

## MCP tool

`mcp__gemini__gemini_analyze_file`

## Usage pattern

```
Tool: mcp__gemini__gemini_analyze_file
  file_path: "/absolute/path/to/file.pdf"
  prompt: "Summarize the key findings in three bullet points."
  model: "gemini-3.1-pro-preview"
```

## Supported formats

- PDFs (reports, specs, contracts)
- Images (screenshots, diagrams, photos)
- Audio (recordings, podcasts)
- Video (demos, walkthroughs)
- Large source files (> 500 lines where you need a structural overview)

## When to use

- User points at a PDF or image and asks about its contents
- A source file is > 500 lines and you need a structural overview before editing
- An audio/video file needs transcription or summarization
- You need to extract structured data from a visual format (tables in images, charts)

## Tips

- Be specific in the prompt. "Summarize" is worse than "Extract all API endpoints mentioned with their HTTP methods."
- Files are uploaded via Google's Files API and expire after 48h.
- For code files: ask for "structural overview: imports, exports, main functions, dependencies" rather than full content.

## Do NOT use this skill for

- Small text files already in context (just Read them)
- Questions about file metadata (use Bash: `file`, `stat`, `exiftool`)
- Live web content (use gemini-research-grounded)
```

- [ ] **Step 5: Create `skills/gemini-code-exec/SKILL.md`**

```markdown
---
description: Run Python code in Gemini's sandboxed execution environment to verify math, test regex patterns, simulate logic, or validate algorithms without local execution. Use when you need computational verification without side effects.
---

# Gemini Code Execution

Use this skill when you need to verify a computation, test a regex, or validate logic by actually running code, but don't want to (or can't) run it locally.

## MCP tool

`mcp__gemini__gemini_code_execute`

## Usage pattern

```
Tool: mcp__gemini__gemini_code_execute
  prompt: "Calculate the 50th Fibonacci number and verify it's 12586269025"
```

Gemini writes Python code, executes it in a sandbox, and returns:
- The answer
- The generated code
- stdout output

## When to use

- Verify a mathematical calculation or formula
- Test a regex pattern against sample inputs
- Validate an algorithm's output for edge cases
- Check date/time calculations
- Simulate a state machine or finite automaton
- Verify JSON/data transformations

## Tips

- Frame the prompt as a verification task: "Calculate X and confirm it equals Y"
- For regex: provide test strings and expected matches
- The sandbox has standard Python libraries (math, re, json, datetime, itertools, etc.) but no network access or file system
- Results are deterministic: same prompt = same code = same output

## Do NOT use this skill for

- Running project test suites (use local Bash)
- Code that needs network access or file I/O
- Code that needs project-specific dependencies
- Simple arithmetic Claude can do in its head
```

- [ ] **Step 6: Create `skills/gemini-image-gen/SKILL.md`**

```markdown
---
description: Generate images using Gemini's native image generation (Nano Banana) or Imagen 4. Use for UI mockups, hero images, product shots, infographic frames, or any visual content creation task.
---

# Gemini Image Generation

Use this skill when the user needs visual content generated from a text prompt.

## Which MCP tool to use

| Scenario | Tool | Default model | Quality |
|---|---|---|---|
| Quick concepts, UI mockups, illustrations | `mcp__gemini__gemini_generate_image` | gemini-3.1-flash-image-preview | Good, fast |
| High-quality product photography, marketing | `mcp__gemini__gemini_generate_image_imagen` | imagen-4.0-ultra-generate-001 | Premium, slower |

## Usage patterns

Native Gemini image gen:
```
Tool: mcp__gemini__gemini_generate_image
  prompt: "A minimalist landing page hero image with abstract geometric shapes in blue and white"
  output_dir: "/tmp/gemini-images"
  count: 3
```

Imagen 4 (high quality):
```
Tool: mcp__gemini__gemini_generate_image_imagen
  prompt: "Professional product photo of wireless earbuds on marble surface, studio lighting"
  output_dir: "/tmp/gemini-images"
```

## Tips

- Be specific about style, composition, lighting, and mood
- For UI mockups: describe the layout, color palette, and content
- Use count > 1 for variations, then let the user pick
- Images are saved as PNG to the specified output_dir
- Default output_dir is /tmp/gemini-images if not specified

## Model selection

- `gemini-3.1-flash-image-preview`: fast, good for iteration
- `gemini-3-pro-image-preview`: higher quality native gen
- `imagen-4.0-ultra-generate-001`: highest quality (Imagen 4 Ultra)
- `imagen-4.0-generate-001`: balanced quality/speed
- `imagen-4.0-fast-generate-001`: fastest Imagen option

## Do NOT use this skill for

- Editing existing images (not supported in v0.1)
- Screenshots or browser captures (use browser tools)
- Diagrams with specific text/labels (use mermaid or plantuml)
```

- [ ] **Step 7: Create `skills/gemini-video-gen/SKILL.md`**

```markdown
---
description: Generate short video clips using Veo 3.1. Async start+poll pattern; returns an MP4 file. Use for product demos, B-roll footage, short animations, or motion design concepts.
---

# Gemini Video Generation

Use this skill to generate short video clips from text prompts using Veo.

## MCP tools (start + poll pair)

1. `mcp__gemini__gemini_start_video` - starts the generation, returns operation_id
2. `mcp__gemini__gemini_get_video` - polls until done, writes MP4

## Usage pattern

Step 1: start generation
```
Tool: mcp__gemini__gemini_start_video
  prompt: "A calm drone shot of waves meeting a sandy beach at sunset"
  aspect_ratio: "16:9"
  duration_seconds: 5
```

Step 2: poll (every 15 seconds)
```
Tool: mcp__gemini__gemini_get_video
  operation_id: "<from step 1>"
```

Possible responses:
- `{"status": "running", ...}` - keep polling
- `{"status": "done", "path": "/tmp/gemini-videos/veo-....mp4", ...}` - complete

## Tips

- Generation takes 30s to a few minutes; do other work while waiting
- Describe camera movement explicitly (pan, zoom, track, static, drone)
- Describe lighting, time of day, weather for consistency
- duration_seconds is advisory (encoded in prompt as a hint)
- Videos are saved as MP4 to /tmp/gemini-videos/ by default

## Model options

- `veo-3.1-generate-preview` (default): highest quality
- `veo-3.1-fast-generate-preview`: faster, slightly lower quality
- `veo-3.1-lite-generate-preview`: fastest, for quick previews

## Do NOT use this skill for

- Still images (use gemini-image-gen)
- Screen recordings (use browser/screen capture tools)
- Long-form video editing (not supported)
```

- [ ] **Step 8: Create `skills/gemini-audio-tts-music/SKILL.md`**

```markdown
---
description: Generate music (Lyria 3) or synthesize speech (Gemini TTS, single or multi-speaker). Use for soundtracks, voiceovers, demo narration, notification sounds, or audio branding.
---

# Gemini Audio, TTS, and Music

Use this skill for audio content generation: music creation or text-to-speech synthesis.

## Which MCP tool to use

| Scenario | Tool | Default model |
|---|---|---|
| Music, soundtracks, jingles | `mcp__gemini__gemini_generate_music` | lyria-3-pro-preview |
| Single-voice narration | `mcp__gemini__gemini_tts` | gemini-3.1-flash-tts-preview |
| Multi-speaker dialogue | `mcp__gemini__gemini_tts` (with speaker tags) | gemini-3.1-flash-tts-preview |

## Music generation

```
Tool: mcp__gemini__gemini_generate_music
  prompt: "Upbeat lo-fi hip hop track, warm vinyl crackle, mellow piano, 90 BPM"
```

Tips:
- Describe genre, mood, instruments, tempo
- duration_seconds is advisory only (hint via prompt instead)
- Output is audio file saved to output directory

## Text-to-Speech

Single voice:
```
Tool: mcp__gemini__gemini_tts
  text: "Welcome to the demo. Today we'll walk through the new feature."
  voice: "Kore"
```

Multi-speaker:
```
Tool: mcp__gemini__gemini_tts
  text: "[Speaker1] Welcome to the show. [Speaker2] Thanks for having me!"
```

## Model options

- `lyria-3-pro-preview`: full music generation (default)
- `lyria-3-clip-preview`: shorter clips, faster
- `gemini-3.1-flash-tts-preview`: TTS (default)

## Do NOT use this skill for

- Transcription of existing audio (use gemini-file-analysis)
- Audio editing or mixing (not supported)
- Live/streaming audio (not supported in MCP)
```

- [ ] **Step 9: Write skill validation tests**

Create `tests/skills.bats`:

```bash
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
```

- [ ] **Step 10: Run tests to verify they pass**

Run: `cd ~/workspace/gemini-plugin && bats tests/skills.bats`
Expected: 6 tests, all passing

- [ ] **Step 11: Commit**

```bash
git add skills/ tests/skills.bats
git commit -m "feat: add 8 task-oriented skills"
```

---

## Task 6: Slash commands (3 + 2 utility)

**Files:**
- Create: `commands/gemini-validate.md`
- Create: `commands/gemini-challenge.md`
- Create: `commands/gemini-research.md`
- Create: `commands/gemini-brainstorm-on.md`
- Create: `commands/gemini-brainstorm-off.md`
- Test: `tests/commands.bats`

- [ ] **Step 1: Create `commands/gemini-validate.md`**

```markdown
---
description: Get a Gemini second opinion on a plan, diff, or claim
allowed-tools: Read, Grep, Glob
argument-hint: <subject - file path, pasted text, or description>
---

You are running the /gemini-plugin:gemini-validate slash command.

The user wants Gemini to validate something. Spawn @agent-gemini-plugin:gemini-validator with the following task:

Task: AD_HOC_VALIDATION
Subject: $ARGUMENTS

Instructions for the validator:
1. If the subject is a file path, read it first.
2. If the subject is inline text, use it directly.
3. Validate for correctness, completeness, and hallucinations.
4. Return the structured JSON verdict.

Block until the validator returns its structured verdict, then present the verdict to the user. Format the output clearly:

- Verdict: pass/fail
- Gaps (if any): bulleted list
- Hallucinations (if any): bulleted list
- Recommended next actions: bulleted list
```

- [ ] **Step 2: Create `commands/gemini-challenge.md`**

```markdown
---
description: Get Gemini to argue against a decision or propose alternatives
allowed-tools: Read
argument-hint: <topic - architectural choice, approach, or decision to challenge>
---

You are running the /gemini-plugin:gemini-challenge slash command.

The user wants a devil's advocate perspective. Spawn @agent-gemini-plugin:gemini-challenger with the following task:

Task: AD_HOC_CHALLENGE
Topic: $ARGUMENTS

Instructions for the challenger:
1. If the topic references code or files, read them for context.
2. Argue against the current approach constructively.
3. Propose at least 2 concrete alternatives with tradeoffs.
4. Identify at least 1 specific failure scenario.
5. Return the structured JSON verdict.

Block until the challenger returns, then present:

- Verdict: pass/fail/block
- Alternatives: numbered list with tradeoffs
- Objections: bulleted list
- Must address: items requiring resolution before proceeding
```

- [ ] **Step 3: Create `commands/gemini-research.md`**

```markdown
---
description: Research a topic using Gemini's search-grounded or deep research capabilities
allowed-tools: Read
argument-hint: <query> [--deep]
---

You are running the /gemini-plugin:gemini-research slash command.

The user wants factual, cited research. Spawn @agent-gemini-plugin:gemini-researcher with the following task:

Task: AD_HOC_RESEARCH
Query: $ARGUMENTS
Mode: If $ARGUMENTS contains "--deep", use deep research (gemini_start_research + polling). Otherwise use quick grounded search.

Instructions for the researcher:
1. Parse the query (strip --deep flag if present).
2. For quick mode: call gemini_search_grounded and return immediately.
3. For deep mode: call gemini_start_research, poll with gemini_get_research_report until done.
4. Return the structured output with citations.

Block until the researcher returns, then present:

- Answer: the research findings
- Citations: numbered list with URLs
- Freshness: when this information was retrieved
- Confidence: high/medium/low based on source agreement
```

- [ ] **Step 4: Create `commands/gemini-brainstorm-on.md`**

```markdown
---
description: Enable unconditional Gemini grounding for the current brainstorming session
allowed-tools: Bash
argument-hint: (no arguments)
---

You are running the /gemini-plugin:gemini-brainstorm-on command.

Create the brainstorming lock file to enable unconditional Gemini grounding on every user prompt (bypassing the keyword regex gate).

Run this Bash command:
```bash
mkdir -p "${CLAUDE_PLUGIN_DATA_DIR:-$HOME/.claude/plugins/data/gemini-plugin}" && touch "${CLAUDE_PLUGIN_DATA_DIR:-$HOME/.claude/plugins/data/gemini-plugin}/brainstorm.lock"
```

Then confirm to the user: "Brainstorming mode ON. Gemini will ground every prompt until you run /gemini-plugin:gemini-brainstorm-off or the session ends."
```

- [ ] **Step 5: Create `commands/gemini-brainstorm-off.md`**

```markdown
---
description: Disable unconditional Gemini grounding (return to keyword-gated mode)
allowed-tools: Bash
argument-hint: (no arguments)
---

You are running the /gemini-plugin:gemini-brainstorm-off command.

Remove the brainstorming lock file to return to keyword-gated grounding.

Run this Bash command:
```bash
rm -f "${CLAUDE_PLUGIN_DATA_DIR:-$HOME/.claude/plugins/data/gemini-plugin}/brainstorm.lock"
```

Then confirm to the user: "Brainstorming mode OFF. Gemini grounding will only fire on keyword-matching prompts."
```

- [ ] **Step 6: Write command validation tests**

Create `tests/commands.bats`:

```bash
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
```

- [ ] **Step 7: Run tests to verify they pass**

Run: `cd ~/workspace/gemini-plugin && bats tests/commands.bats`
Expected: 6 tests, all passing

- [ ] **Step 8: Commit**

```bash
git add commands/ tests/commands.bats
git commit -m "feat: add 5 slash commands (3 agent + 2 utility)"
```

---

## Task 7: Rules

**Files:**
- Create: `rules/using-gemini.md`
- Test: `tests/rules.bats`

- [ ] **Step 1: Create `rules/using-gemini.md`**

```markdown
## Gemini Plugin: Session Rules

The gemini-plugin is loaded. Four subagents assist you:

| Agent | Role | Spawn via |
|---|---|---|
| gemini-validator | Validates plans, diffs, done-claims for gaps and hallucinations | Hook (ExitPlanMode, Stop) or /gemini-plugin:gemini-validate |
| gemini-challenger | Devil's advocate; proposes alternatives, challenges destructive ops | Hook (PreToolUse Bash) or /gemini-plugin:gemini-challenge |
| gemini-researcher | Search-grounded facts with citations; never opines without a URL | Hook (UserPromptSubmit) or /gemini-plugin:gemini-research |
| gemini-summarizer | Compresses session state; writes risk maps at SessionStart | Hook (SessionStart, PreCompact) |

### Always reach for Gemini when

- User says "second opinion", "check this", "what would Gemini say"
- A claim depends on post-training-cutoff info (library versions, CVEs, pricing, API shapes)
- You're about to run a destructive command the hook might miss (multi-line scripts, compound pipelines)
- You're completing a plan or claiming "done" and the hook hasn't already fired

### Never reach for Gemini when

- The question is answered by a file already in context
- The task is a trivial typo, formatting, or one-line config change
- You already received a Gemini verdict on the same artifact this session
- The user says "no Gemini", "skip validation", or "just do it"

### Cost discipline

- Validator and researcher use haiku. Challenger and summarizer use sonnet.
- Deep research is opt-in only (via /gemini-plugin:gemini-research --deep)
- One validation per artifact per session. No re-asking.
- If GEMINI_API_KEY is unset, everything gracefully no-ops.

### Disable individual components

- Env: `CLAUDE_PLUGIN_GEMINI_DISABLE_HOOKS=1` silences all hooks
- Settings: add `Agent(gemini-plugin:gemini-challenger)` to `permissions.deny` to block specific agents
- Command: `/gemini-plugin:gemini-brainstorm-off` to disable unconditional grounding
```

- [ ] **Step 2: Write rule validation tests**

Create `tests/rules.bats`:

```bash
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

@test "rule documents GEMINI_API_KEY unset behavior" {
  grep -q "GEMINI_API_KEY" rules/using-gemini.md
}
```

- [ ] **Step 3: Run tests to verify they pass**

Run: `cd ~/workspace/gemini-plugin && bats tests/rules.bats`
Expected: 4 tests, all passing

- [ ] **Step 4: Commit**

```bash
git add rules/ tests/rules.bats
git commit -m "feat: add session rules (using-gemini.md)"
```

---

## Task 8: README

**Files:**
- Create: `README.md`

- [ ] **Step 1: Create `README.md`**

```markdown
# gemini-plugin

A Claude Code plugin that makes Google Gemini your second-opinion assistant: validating plans, challenging destructive operations, grounding prompts in live web data, and auditing "done" claims to reduce hallucination and repeated work.

Built on [gemini-mcp](https://github.com/azmym/gemini-mcp) (13 MCP tools covering text, images, video, music, TTS, deep research, code execution, and search-grounded answers).

## Install

```bash
# Add the marketplace
/plugin marketplace add azmym/gemini-plugin

# Install the plugin
/plugin install gemini-plugin@gemini-marketplace

# Set your API key (get one at https://aistudio.google.com/app/apikey)
export GEMINI_API_KEY=<your-key>
```

The plugin auto-registers the `gemini` MCP server. No separate `claude mcp add` step needed.

## What you get

| Component | Count | Purpose |
|---|---|---|
| Skills | 8 | Task-oriented guidance for when/how to use Gemini capabilities |
| Subagents | 4 | Validator, Challenger, Researcher, Summarizer |
| Slash commands | 5 | Manual invocation + brainstorm toggle |
| Hooks | 7 | 6 auto-triggers + 1 verdict handler |
| Rules | 1 | Session-level guidance on when to (not) call Gemini |

## Auto-triggers (hooks)

| Event | What happens |
|---|---|
| Session start | Builds a risk map of the repo (cached 24h) |
| User prompt (gated) | Grounds post-cutoff questions via Gemini search (always-on during brainstorming) |
| Plan complete | Validates the plan for gaps and hallucinations |
| Destructive Bash command | Challenges the command; proposes safer alternatives |
| Pre-compact | Summarizes session state to survive context compaction |
| Stop ("done" claim) | Validates the output against the original ask |

All hooks block (exit 2) when Gemini finds issues. You see the critique inline and must address it before continuing.

## Subagents

| Agent | Role | Model | Color |
|---|---|---|---|
| gemini-validator | Validates plans/diffs/claims | Haiku | Blue |
| gemini-challenger | Devil's advocate | Sonnet | Red |
| gemini-researcher | Live-web grounding | Haiku | Green |
| gemini-summarizer | Session compression | Sonnet | Purple |

Invoke manually: `@agent-gemini-plugin:gemini-validator`, or via slash commands.

## Slash commands

| Command | What it does |
|---|---|
| `/gemini-plugin:gemini-validate <subject>` | Ad-hoc validation of any artifact |
| `/gemini-plugin:gemini-challenge <topic>` | Devil's advocate on any decision |
| `/gemini-plugin:gemini-research <query> [--deep]` | Grounded research (--deep for synthesis) |
| `/gemini-plugin:gemini-brainstorm-on` | Enable unconditional grounding |
| `/gemini-plugin:gemini-brainstorm-off` | Return to keyword-gated grounding |

## Disable features

| What | How |
|---|---|
| All hooks | `export CLAUDE_PLUGIN_GEMINI_DISABLE_HOOKS=1` |
| Specific agent | Add `Agent(gemini-plugin:gemini-challenger)` to `permissions.deny` in settings |
| Brainstorm mode | `/gemini-plugin:gemini-brainstorm-off` |

## Requirements

- Claude Code with plugin support
- A Google AI Studio API key (`GEMINI_API_KEY`)
- `uvx` (installed with `uv`; the MCP server is fetched automatically)
- `jq` (used by hook scripts to parse JSON)

## License

MIT
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: add README"
```

---

## Task 9: Full test suite run and final validation

**Files:**
- No new files
- Test: all `tests/*.bats`

- [ ] **Step 1: Run the full test suite**

Run: `cd ~/workspace/gemini-plugin && bats tests/`
Expected: all tests pass (manifests: 6, hooks-lib: 13, hooks-triggers: 17, agents: 8, skills: 6, commands: 6, rules: 4 = ~60 tests total)

- [ ] **Step 2: Verify the directory tree matches spec**

Run: `cd ~/workspace/gemini-plugin && find . -type f | grep -v '.git/' | grep -v 'docs/superpowers' | sort`

Confirm it matches section 4 of the design spec.

- [ ] **Step 3: Verify no files reference paths outside the plugin**

Run: `cd ~/workspace/gemini-plugin && grep -r '\.\.\/' --include='*.sh' --include='*.md' --include='*.json' . | grep -v '.git/'`
Expected: no output (no `../` paths)

- [ ] **Step 4: Verify all scripts are executable**

Run: `cd ~/workspace/gemini-plugin && find hooks/ -name '*.sh' ! -perm -u+x`
Expected: no output (all .sh files are executable)

- [ ] **Step 5: Verify hooks.json is valid JSON**

Run: `cd ~/workspace/gemini-plugin && jq empty hooks/hooks.json && echo "valid"`
Expected: "valid"

- [ ] **Step 6: Commit test infrastructure note (if any fixes were needed)**

```bash
git status
# If clean: skip
# If fixes needed: git add -A && git commit -m "fix: test suite corrections"
```

- [ ] **Step 7: Tag the release candidate**

```bash
git tag -a v0.1.0-rc1 -m "gemini-plugin v0.1.0 release candidate 1"
```

---

## Acceptance criteria cross-check (from spec section 15)

| # | Criterion | Task(s) that satisfy it |
|---|---|---|
| 1 | Plugin installs in one step from marketplace | Task 1 (manifests) |
| 2 | 8 skills discoverable | Task 5 |
| 3 | 4 subagents invocable | Task 4, Task 6 (commands) |
| 4 | 6 trigger hooks fire, verdict handler blocks on fail | Task 2, Task 3 |
| 5 | Graceful no-op when GEMINI_API_KEY unset | Task 2 (common.sh), Task 3 (tests) |
| 6 | Brainstorming detection flips grounding | Task 2 (is_brainstorming), Task 3 (user-prompt-grounding.sh), Task 6 (brainstorm commands) |
| 7 | Loop guard demotes repeat-fail | Task 3 (verdict-handler) |
| 8 | No `../` paths, fully self-contained | Task 9 (validation step 3) |
| 9 | README documents everything | Task 8 |
