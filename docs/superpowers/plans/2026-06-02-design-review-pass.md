# Design Review Pass Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Automatically run an advisory validate+challenge pass over any design/plan artifact (spec files on disk and native plan-mode plans), without regressing the existing blocking plan and done-claim gates.

**Architecture:** A new `PostToolUse(Write|Edit)` hook (`design-review.sh`) path-matches design artifacts, dedups by content hash, and asks the main agent to dispatch gemini-validator + gemini-challenger as an advisory pass. The existing `plan-complete.sh` keeps its blocking validator and gains an advisory challenger. Advisory-vs-blocking is routed through a per-agent "pending mode" marker file that `subagent-verdict-handler.sh` reads and consumes on `SubagentStop`.

**Tech Stack:** Bash hook scripts (`set -euo pipefail`, `trap ... ERR -> exit 0`), `jq` for JSON, `shasum` for hashing, bats-core for tests.

---

## Spec

Source spec: `docs/superpowers/specs/2026-06-02-design-review-pass-design.md`. Read it before starting.

## Conventions (match existing code)

- Every hook: `set -euo pipefail`; first line after shebang-block is a `trap '... exit 0' ERR`; source `lib/common.sh` (+ `lib/prompt-builder.sh` if it emits directives); call `check_plugin_enabled`, `check_gemini_available`, `ensure_data_dir` in that order.
- Read stdin once: `INPUT=$(cat)`. Parse with `jq -r`.
- Data dir is `data_dir()` (honors `CLAUDE_PLUGIN_DATA`, falls back to `~/.claude/plugins/data/gemini-plugin`).
- Tests source helpers via `bash -c 'source hooks/lib/common.sh; ...'` and rely on `setup()` exporting `CLAUDE_PLUGIN_DATA`, `CLAUDE_PLUGIN_OPTION_GEMINI_API_KEY=test-key`, `CLAUDE_PLUGIN_GEMINI_DISABLE_HOOKS=0`.
- Run a single bats file with: `bats tests/<file>.bats`. Run all with: `bats tests/`.

## File structure

| File | Responsibility |
|---|---|
| `hooks/lib/common.sh` | + `is_design_artifact`, design seen-hash helpers, pending-mode helpers |
| `hooks/lib/prompt-builder.sh` | + `build_design_review_directive`, `build_plan_challenge_directive` |
| `hooks/design-review.sh` | NEW: PostToolUse(Write\|Edit) entrypoint |
| `hooks/plan-complete.sh` | + advisory challenger + pending markers |
| `hooks/subagent-verdict-handler.sh` | + read/consume pending-mode marker to choose exit 0 vs 2 |
| `hooks/hooks.json` | + PostToolUse(Write\|Edit) block |
| `tests/design-review.bats` | NEW: helpers + design-review.sh |
| `tests/hooks-triggers.bats` | + verdict-handler marker cases, plan-complete challenger cases |
| `tests/manifests.bats` | + hooks.json structure assertions |
| `skills/gemini-consult/SKILL.md`, `rules/using-gemini.md` | document the pass |
| `.claude-plugin/plugin.json`, `CHANGELOG.md` | 0.6.0 bump |

---

### Task 1: `is_design_artifact` helper

**Files:**
- Modify: `hooks/lib/common.sh` (append helper)
- Test: `tests/design-review.bats` (new)

- [ ] **Step 1: Write the failing tests**

Create `tests/design-review.bats`:

```bash
#!/usr/bin/env bats

setup() {
  export CLAUDE_PLUGIN_DATA="$BATS_TMPDIR/test-data-$$"
  export CLAUDE_PLUGIN_OPTION_GEMINI_API_KEY="test-key"
  export CLAUDE_PLUGIN_GEMINI_DISABLE_HOOKS=0
  mkdir -p "$CLAUDE_PLUGIN_DATA"
}

teardown() {
  rm -rf "$CLAUDE_PLUGIN_DATA"
}

# --- is_design_artifact ---

@test "is_design_artifact: matches superpowers spec (relative)" {
  run bash -c 'source hooks/lib/common.sh; is_design_artifact "docs/superpowers/specs/2026-06-02-foo-design.md"'
  [ "$status" -eq 0 ]
}

@test "is_design_artifact: matches absolute spec path" {
  run bash -c 'source hooks/lib/common.sh; is_design_artifact "/Users/me/proj/docs/superpowers/specs/x-design.md"'
  [ "$status" -eq 0 ]
}

@test "is_design_artifact: matches a *-plan.md" {
  run bash -c 'source hooks/lib/common.sh; is_design_artifact "docs/superpowers/plans/2026-06-02-foo-plan.md"'
  [ "$status" -eq 0 ]
}

@test "is_design_artifact: matches generic specs/ dir" {
  run bash -c 'source hooks/lib/common.sh; is_design_artifact "myproj/specs/auth.md"'
  [ "$status" -eq 0 ]
}

@test "is_design_artifact: matches DESIGN.md" {
  run bash -c 'source hooks/lib/common.sh; is_design_artifact "subsystem/DESIGN.md"'
  [ "$status" -eq 0 ]
}

@test "is_design_artifact: rejects a non-design markdown" {
  run bash -c 'source hooks/lib/common.sh; is_design_artifact "docs/notes.md"'
  [ "$status" -ne 0 ]
}

@test "is_design_artifact: rejects a source file" {
  run bash -c 'source hooks/lib/common.sh; is_design_artifact "src/foo.ts"'
  [ "$status" -ne 0 ]
}

@test "is_design_artifact: respects CLAUDE_PLUGIN_GEMINI_DESIGN_GLOBS override" {
  run bash -c 'source hooks/lib/common.sh; CLAUDE_PLUGIN_GEMINI_DESIGN_GLOBS="*/rfc/*.md" is_design_artifact "x/rfc/1.md"'
  [ "$status" -eq 0 ]
  run bash -c 'source hooks/lib/common.sh; CLAUDE_PLUGIN_GEMINI_DESIGN_GLOBS="*/rfc/*.md" is_design_artifact "docs/superpowers/specs/x-design.md"'
  [ "$status" -ne 0 ]
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bats tests/design-review.bats`
Expected: FAIL (`is_design_artifact: command not found`)

- [ ] **Step 3: Implement `is_design_artifact` in `hooks/lib/common.sh`**

Append to `hooks/lib/common.sh` (after `is_destructive_command`):

```bash
# Default design-artifact globs (colon-separated). Overridable via
# CLAUDE_PLUGIN_GEMINI_DESIGN_GLOBS. Globs use a leading */ so they match a
# path whether it is absolute or repo-relative. A path matches if it matches
# ANY glob. In [[ $x == $glob ]], * matches across slashes.
DEFAULT_DESIGN_GLOBS="*/superpowers/specs/*-design.md:*/superpowers/plans/*.md:*-plan.md:*/specs/*.md:*/plans/*.md:*/DESIGN.md:*/PLAN.md"

is_design_artifact() {
  local path="$1"
  local globs="${CLAUDE_PLUGIN_GEMINI_DESIGN_GLOBS:-$DEFAULT_DESIGN_GLOBS}"
  local IFS=':'
  local g
  for g in $globs; do
    [ -z "$g" ] && continue
    # shellcheck disable=SC2053
    if [[ "$path" == $g ]]; then
      return 0
    fi
  done
  return 1
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bats tests/design-review.bats`
Expected: PASS (8 tests)

- [ ] **Step 5: Commit**

```bash
git add hooks/lib/common.sh tests/design-review.bats
git commit -m "feat(hooks): add is_design_artifact glob matcher"
```

---

### Task 2: pending-mode marker helpers

**Files:**
- Modify: `hooks/lib/common.sh` (append helpers)
- Test: `tests/design-review.bats`

- [ ] **Step 1: Write the failing tests**

Append to `tests/design-review.bats`:

```bash
# --- pending-mode markers ---

@test "pending mode: write creates a marker file" {
  bash -c 'source hooks/lib/common.sh; write_pending_mode gemini-challenger advisory'
  [ -f "$CLAUDE_PLUGIN_DATA/pending/gemini-challenger.mode" ]
  [ "$(cat "$CLAUDE_PLUGIN_DATA/pending/gemini-challenger.mode")" = "advisory" ]
}

@test "pending mode: read returns the mode and consumes the marker" {
  bash -c 'source hooks/lib/common.sh; write_pending_mode gemini-validator advisory'
  run bash -c 'source hooks/lib/common.sh; read_consume_pending_mode gemini-validator'
  [ "$status" -eq 0 ]
  [ "$output" = "advisory" ]
  [ ! -f "$CLAUDE_PLUGIN_DATA/pending/gemini-validator.mode" ]
}

@test "pending mode: default is blocking when no marker exists" {
  run bash -c 'source hooks/lib/common.sh; read_consume_pending_mode gemini-validator'
  [ "$output" = "blocking" ]
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bats tests/design-review.bats`
Expected: FAIL (`write_pending_mode: command not found`)

- [ ] **Step 3: Implement the helpers in `hooks/lib/common.sh`**

Append to `hooks/lib/common.sh`:

```bash
# Record the intended verdict-handling mode ("advisory"|"blocking") for an
# agent about to be dispatched. The verdict-handler consumes it on SubagentStop.
write_pending_mode() {
  local agent="$1"
  local mode="$2"
  mkdir -p "$(data_dir)/pending"
  echo "$mode" > "$(data_dir)/pending/${agent}.mode"
}

# Print and delete the pending mode for an agent. Prints "blocking" if no
# marker exists, which preserves the original blocking plan/done-claim gates.
read_consume_pending_mode() {
  local agent="$1"
  local f
  f="$(data_dir)/pending/${agent}.mode"
  if [ -f "$f" ]; then
    cat "$f"
    rm -f "$f"
  else
    echo "blocking"
  fi
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bats tests/design-review.bats`
Expected: PASS (11 tests total in this file now)

- [ ] **Step 5: Commit**

```bash
git add hooks/lib/common.sh tests/design-review.bats
git commit -m "feat(hooks): add pending-mode marker helpers"
```

---

### Task 3: design seen-hash helpers

**Files:**
- Modify: `hooks/lib/common.sh` (append helpers)
- Test: `tests/design-review.bats`

- [ ] **Step 1: Write the failing tests**

Append to `tests/design-review.bats`:

```bash
# --- design seen-hash ---

@test "file_content_hash: returns a hash for an existing file" {
  F="$BATS_TMPDIR/h-$$.txt"
  echo "hello" > "$F"
  run bash -c "source hooks/lib/common.sh; file_content_hash '$F'"
  [ "$status" -eq 0 ]
  [ -n "$output" ]
}

@test "file_content_hash: differs when content changes" {
  F="$BATS_TMPDIR/h2-$$.txt"
  echo "v1" > "$F"
  H1=$(bash -c "source hooks/lib/common.sh; file_content_hash '$F'")
  echo "v2" > "$F"
  H2=$(bash -c "source hooks/lib/common.sh; file_content_hash '$F'")
  [ "$H1" != "$H2" ]
}

@test "design_seen_file: path-keyed, stable for same path" {
  S1=$(bash -c 'source hooks/lib/common.sh; design_seen_file "docs/superpowers/specs/x-design.md"')
  S2=$(bash -c 'source hooks/lib/common.sh; design_seen_file "docs/superpowers/specs/x-design.md"')
  [ "$S1" = "$S2" ]
  [[ "$S1" == *"/design-review-seen/"* ]]
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bats tests/design-review.bats`
Expected: FAIL (`file_content_hash: command not found`)

- [ ] **Step 3: Implement the helpers in `hooks/lib/common.sh`**

Append to `hooks/lib/common.sh`:

```bash
# SHA-256 of a file's contents (first field only). Empty if unreadable.
file_content_hash() {
  shasum -a 256 "$1" 2>/dev/null | cut -d' ' -f1
}

# Path-keyed file storing the last-reviewed content hash for a design artifact.
design_seen_file() {
  local path="$1"
  local pathhash
  pathhash=$(echo -n "$path" | shasum -a 256 | cut -c1-12)
  echo "$(data_dir)/design-review-seen/${pathhash}.sha"
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bats tests/design-review.bats`
Expected: PASS (14 tests total in this file now)

- [ ] **Step 5: Commit**

```bash
git add hooks/lib/common.sh tests/design-review.bats
git commit -m "feat(hooks): add design seen-hash helpers"
```

---

### Task 4: prompt-builder directives

**Files:**
- Modify: `hooks/lib/prompt-builder.sh` (append two builders)
- Test: `tests/design-review.bats`

- [ ] **Step 1: Write the failing tests**

Append to `tests/design-review.bats`:

```bash
# --- directives ---

@test "build_design_review_directive: names both agents and both tasks" {
  run bash -c 'source hooks/lib/common.sh; source hooks/lib/prompt-builder.sh; build_design_review_directive "docs/superpowers/specs/x-design.md" "[]"'
  [ "$status" -eq 0 ]
  [[ "$output" == *"gemini-validator"* ]]
  [[ "$output" == *"VALIDATE_DESIGN"* ]]
  [[ "$output" == *"gemini-challenger"* ]]
  [[ "$output" == *"CHALLENGE_DESIGN"* ]]
  [[ "$output" == *"docs/superpowers/specs/x-design.md"* ]]
  [[ "$output" == *"ADVISORY"* ]]
}

@test "build_plan_challenge_directive: challenger + CHALLENGE_PLAN" {
  run bash -c 'source hooks/lib/common.sh; source hooks/lib/prompt-builder.sh; build_plan_challenge_directive "Step 1: do X."'
  [ "$status" -eq 0 ]
  [[ "$output" == *"gemini-challenger"* ]]
  [[ "$output" == *"CHALLENGE_PLAN"* ]]
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bats tests/design-review.bats`
Expected: FAIL (`build_design_review_directive: command not found`)

- [ ] **Step 3: Implement the builders in `hooks/lib/prompt-builder.sh`**

Append to `hooks/lib/prompt-builder.sh`:

```bash
# Build a combined directive asking Claude to dispatch BOTH the validator and
# the challenger on a design artifact as an ADVISORY pass.
build_design_review_directive() {
  local file_path="$1"
  local history="$2"

  cat <<EOF
[gemini-plugin] A design/plan artifact was written: ${file_path}
Dispatch BOTH of these Gemini agents as an ADVISORY design-review pass:

1. @agent-gemini-plugin:gemini-validator with task=VALIDATE_DESIGN
   Validate this design against the problem it claims to solve. Flag gaps,
   hallucinations, and missed acceptance criteria. Return structured JSON.

2. @agent-gemini-plugin:gemini-challenger with task=CHALLENGE_DESIGN
   Challenge this design: propose at least 2 alternative approaches and at
   least 1 reason this design may be wrong. Return structured JSON.

Design file to review: ${file_path}
Recent design-review history (do not re-raise already-addressed points):
${history}

This pass is ADVISORY: surface the findings to the user; it does not block.
EOF
}

# Build an advisory challenger directive to run alongside the blocking plan
# validator at ExitPlanMode.
build_plan_challenge_directive() {
  local plan_text="$1"

  build_directive "gemini-challenger" "CHALLENGE_PLAN" \
    "Challenge this plan (ADVISORY, non-blocking): propose at least 2 alternative approaches and at least 1 reason this plan may be wrong.

Plan:
${plan_text}"
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bats tests/design-review.bats`
Expected: PASS (16 tests total in this file now)

- [ ] **Step 5: Commit**

```bash
git add hooks/lib/prompt-builder.sh tests/design-review.bats
git commit -m "feat(hooks): add design-review and plan-challenge directives"
```

---

### Task 5: `design-review.sh` hook

**Files:**
- Create: `hooks/design-review.sh`
- Test: `tests/design-review.bats`

- [ ] **Step 1: Write the failing tests**

Append to `tests/design-review.bats`:

```bash
# --- design-review.sh hook ---

@test "design-review: non-design path exits 0 with no output" {
  run bash -c 'echo "{\"tool_input\":{\"file_path\":\"src/foo.ts\"}}" | ./hooks/design-review.sh'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "design-review: empty file_path exits 0 with no output" {
  run bash -c 'echo "{\"tool_input\":{\"file_path\":\"\"}}" | ./hooks/design-review.sh'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "design-review: first write of a design file dispatches both agents" {
  SPEC="$BATS_TMPDIR/sd1-$$/docs/superpowers/specs/x-design.md"
  mkdir -p "$(dirname "$SPEC")"
  echo "# design v1" > "$SPEC"
  run bash -c "echo '{\"tool_input\":{\"file_path\":\"${SPEC}\"}}' | ./hooks/design-review.sh"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.hookEventName == "PostToolUse"'
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext | contains("gemini-validator")'
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext | contains("VALIDATE_DESIGN")'
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext | contains("gemini-challenger")'
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext | contains("CHALLENGE_DESIGN")'
}

@test "design-review: writes advisory pending markers for both agents" {
  SPEC="$BATS_TMPDIR/sd2-$$/docs/superpowers/specs/y-design.md"
  mkdir -p "$(dirname "$SPEC")"
  echo "# design" > "$SPEC"
  run bash -c "echo '{\"tool_input\":{\"file_path\":\"${SPEC}\"}}' | ./hooks/design-review.sh"
  [ "$status" -eq 0 ]
  [ "$(cat "$CLAUDE_PLUGIN_DATA/pending/gemini-validator.mode")" = "advisory" ]
  [ "$(cat "$CLAUDE_PLUGIN_DATA/pending/gemini-challenger.mode")" = "advisory" ]
}

@test "design-review: unchanged content does not re-fire (hash dedup)" {
  SPEC="$BATS_TMPDIR/sd3-$$/docs/superpowers/specs/z-design.md"
  mkdir -p "$(dirname "$SPEC")"
  echo "# stable design" > "$SPEC"
  run bash -c "echo '{\"tool_input\":{\"file_path\":\"${SPEC}\"}}' | ./hooks/design-review.sh"
  [ "$status" -eq 0 ]
  [ -n "$output" ]
  run bash -c "echo '{\"tool_input\":{\"file_path\":\"${SPEC}\"}}' | ./hooks/design-review.sh"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "design-review: materially changed content re-fires" {
  SPEC="$BATS_TMPDIR/sd4-$$/docs/superpowers/specs/w-design.md"
  mkdir -p "$(dirname "$SPEC")"
  echo "# v1" > "$SPEC"
  run bash -c "echo '{\"tool_input\":{\"file_path\":\"${SPEC}\"}}' | ./hooks/design-review.sh"
  [ -n "$output" ]
  echo "# v2 substantially different content here" > "$SPEC"
  run bash -c "echo '{\"tool_input\":{\"file_path\":\"${SPEC}\"}}' | ./hooks/design-review.sh"
  [ -n "$output" ]
}

@test "design-review: exits 0 silently when disabled" {
  export CLAUDE_PLUGIN_GEMINI_DISABLE_HOOKS=1
  SPEC="$BATS_TMPDIR/sd5-$$/docs/superpowers/specs/d-design.md"
  mkdir -p "$(dirname "$SPEC")"
  echo "# design" > "$SPEC"
  run bash -c "echo '{\"tool_input\":{\"file_path\":\"${SPEC}\"}}' | ./hooks/design-review.sh"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bats tests/design-review.bats`
Expected: FAIL (`./hooks/design-review.sh: No such file or directory`)

- [ ] **Step 3: Create `hooks/design-review.sh`**

```bash
#!/usr/bin/env bash
# PostToolUse(Write|Edit) hook: when a design/plan artifact is written, ask
# Claude to dispatch BOTH gemini-validator (VALIDATE_DESIGN) and
# gemini-challenger (CHALLENGE_DESIGN) as an ADVISORY pass. Deduped by content
# hash so cosmetic re-writes do not re-fire.
#
# Pattern: exit 0 + JSON hookSpecificOutput.additionalContext. PostToolUse runs
# after the write has happened, so it never denies; it only injects context.
set -euo pipefail
trap 'echo "[gemini-plugin] design-review crashed at line ${LINENO} (last command: ${BASH_COMMAND})" >&2; exit 0' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/prompt-builder.sh"

check_plugin_enabled
check_gemini_available
ensure_data_dir

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

[ -z "$FILE_PATH" ] && exit 0
is_design_artifact "$FILE_PATH" || exit 0

# Material-change dedup: skip if content hash matches the last reviewed hash.
SEEN_FILE=$(design_seen_file "$FILE_PATH")
NEW_HASH=$(file_content_hash "$FILE_PATH")
[ -z "$NEW_HASH" ] && exit 0
if [ -f "$SEEN_FILE" ] && [ "$(cat "$SEEN_FILE")" = "$NEW_HASH" ]; then
  exit 0
fi

HISTORY=$(get_plan_history "VALIDATE_DESIGN" 3)
write_pending_mode "gemini-validator" "advisory"
write_pending_mode "gemini-challenger" "advisory"
DIRECTIVE=$(build_design_review_directive "$FILE_PATH" "$HISTORY")

mkdir -p "$(dirname "$SEEN_FILE")"
echo "$NEW_HASH" > "$SEEN_FILE"

jq -n --arg ctx "$DIRECTIVE" '{
  hookSpecificOutput: {
    hookEventName: "PostToolUse",
    additionalContext: $ctx
  }
}'
exit 0
```

- [ ] **Step 4: Make it executable**

Run: `chmod +x hooks/design-review.sh`

- [ ] **Step 5: Run tests to verify they pass**

Run: `bats tests/design-review.bats`
Expected: PASS (23 tests total in this file now)

- [ ] **Step 6: Commit**

```bash
git add hooks/design-review.sh tests/design-review.bats
git commit -m "feat(hooks): add design-review.sh PostToolUse hook"
```

---

### Task 6: verdict-handler marker routing

**Files:**
- Modify: `hooks/subagent-verdict-handler.sh:11-12,44-51`
- Test: `tests/hooks-triggers.bats` (append after the existing verdict-handler tests, before `# --- plugin disable ---`)

- [ ] **Step 1: Write the failing tests**

Append to `tests/hooks-triggers.bats` after the `verdict-handler: reviewer changes_requested` test (line ~234):

```bash
@test "verdict-handler: advisory marker demotes fail to non-blocking (exit 0)" {
  TRANSCRIPT="$BATS_TMPDIR/transcript-adv-$$.jsonl"
  echo '{"type":"assistant","message":{"content":[{"text":"{\"verdict\":\"fail\",\"gaps\":[\"a gap\"]}"}]}}' > "$TRANSCRIPT"
  mkdir -p "$CLAUDE_PLUGIN_DATA/pending"
  echo "advisory" > "$CLAUDE_PLUGIN_DATA/pending/gemini-validator.mode"
  run bash -c "echo '{\"agent_type\":\"gemini-validator\",\"transcript_path\":\"${TRANSCRIPT}\"}' | ./hooks/subagent-verdict-handler.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"a gap"* ]]
  [ ! -f "$CLAUDE_PLUGIN_DATA/pending/gemini-validator.mode" ]
}

@test "verdict-handler: blocking marker keeps fail blocking (exit 2)" {
  TRANSCRIPT="$BATS_TMPDIR/transcript-blk-$$.jsonl"
  echo '{"type":"assistant","message":{"content":[{"text":"{\"verdict\":\"fail\",\"gaps\":[\"a gap\"]}"}]}}' > "$TRANSCRIPT"
  mkdir -p "$CLAUDE_PLUGIN_DATA/pending"
  echo "blocking" > "$CLAUDE_PLUGIN_DATA/pending/gemini-validator.mode"
  run bash -c "echo '{\"agent_type\":\"gemini-validator\",\"transcript_path\":\"${TRANSCRIPT}\"}' | ./hooks/subagent-verdict-handler.sh"
  [ "$status" -eq 2 ]
}

@test "verdict-handler: no marker defaults to blocking (exit 2), no regression" {
  TRANSCRIPT="$BATS_TMPDIR/transcript-def-$$.jsonl"
  echo '{"type":"assistant","message":{"content":[{"text":"{\"verdict\":\"fail\",\"gaps\":[\"a gap\"]}"}]}}' > "$TRANSCRIPT"
  run bash -c "echo '{\"agent_type\":\"gemini-validator\",\"transcript_path\":\"${TRANSCRIPT}\"}' | ./hooks/subagent-verdict-handler.sh"
  [ "$status" -eq 2 ]
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bats tests/hooks-triggers.bats`
Expected: the advisory test FAILS (exits 2 today instead of 0); the two blocking tests pass.

- [ ] **Step 3: Modify `hooks/subagent-verdict-handler.sh`**

Add the marker read right after `AGENT` is parsed. Change lines 11-12 from:

```bash
INPUT=$(cat)
AGENT=$(echo "$INPUT" | jq -r '.agent_type')
```

to:

```bash
INPUT=$(cat)
AGENT=$(echo "$INPUT" | jq -r '.agent_type')
MODE=$(read_consume_pending_mode "$AGENT")
```

Then change the final block (lines 44-51) from:

```bash
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

to:

```bash
if [ "$VERDICT" = "fail" ] || [ "$VERDICT" = "block" ]; then
  cat >&2 <<EOF
[gemini-plugin] ${AGENT} verdict: ${VERDICT} (${MODE})
Issues to address before continuing:
- ${GAPS}
EOF
  if [ "$MODE" = "advisory" ]; then
    exit 0
  fi
  exit 2
fi
exit 0
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bats tests/hooks-triggers.bats`
Expected: PASS (all, including the 3 new tests and the pre-existing #210 fail→exit 2 and #229 reviewer→exit 0)

- [ ] **Step 5: Commit**

```bash
git add hooks/subagent-verdict-handler.sh tests/hooks-triggers.bats
git commit -m "feat(hooks): route verdict blocking vs advisory via pending marker"
```

---

### Task 7: advisory challenger at ExitPlanMode

**Files:**
- Modify: `hooks/plan-complete.sh:30-38`
- Test: `tests/hooks-triggers.bats` (append after the existing plan-complete tests, before `# --- stop-done-claim ---`)

- [ ] **Step 1: Write the failing tests**

Append to `tests/hooks-triggers.bats` after the `plan-complete: exits 0 silently when plan is empty` test (line ~172):

```bash
@test "plan-complete: also dispatches advisory challenger alongside blocking validator" {
  run bash -c 'echo "{\"tool_input\":{\"plan\":\"Step 1: do X.\"}}" | ./hooks/plan-complete.sh'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext | contains("VALIDATE_PLAN")'
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext | contains("gemini-challenger")'
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext | contains("CHALLENGE_PLAN")'
}

@test "plan-complete: marks challenger advisory and validator blocking" {
  run bash -c 'echo "{\"tool_input\":{\"plan\":\"Step 1: do X.\"}}" | ./hooks/plan-complete.sh'
  [ "$status" -eq 0 ]
  [ "$(cat "$CLAUDE_PLUGIN_DATA/pending/gemini-challenger.mode")" = "advisory" ]
  [ "$(cat "$CLAUDE_PLUGIN_DATA/pending/gemini-validator.mode")" = "blocking" ]
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bats tests/hooks-triggers.bats`
Expected: FAIL (no CHALLENGE_PLAN in output; no marker files)

- [ ] **Step 3: Modify `hooks/plan-complete.sh`**

Replace lines 30-38 (from `HISTORY=...` through the closing `jq -n ... }'`) with:

```bash
HISTORY=$(get_plan_history "VALIDATE_PLAN" 3)
DIRECTIVE=$(build_plan_validation_directive "$PLAN_TEXT" "$HISTORY")
CHALLENGE=$(build_plan_challenge_directive "$PLAN_TEXT")

# Validator keeps its blocking gate; challenger runs advisory alongside it.
write_pending_mode "gemini-validator" "blocking"
write_pending_mode "gemini-challenger" "advisory"

COMBINED="${DIRECTIVE}

${CHALLENGE}"

jq -n --arg ctx "$COMBINED" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    additionalContext: $ctx
  }
}'
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bats tests/hooks-triggers.bats`
Expected: PASS (including the pre-existing plan-complete tests #155-172, which still find VALIDATE_PLAN)

- [ ] **Step 5: Commit**

```bash
git add hooks/plan-complete.sh tests/hooks-triggers.bats
git commit -m "feat(hooks): add advisory challenger at ExitPlanMode"
```

---

### Task 8: register the PostToolUse hook + manifest tests

**Files:**
- Modify: `hooks/hooks.json:17-31` (insert PostToolUse block)
- Test: `tests/manifests.bats` (append)

- [ ] **Step 1: Write the failing tests**

Append to `tests/manifests.bats`:

```bash
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bats tests/manifests.bats`
Expected: FAIL (`.hooks.PostToolUse` is null)

- [ ] **Step 3: Modify `hooks/hooks.json`**

Insert a `PostToolUse` block after the `PreToolUse` array closes (after the `]` on line 31, before `"PreCompact"`). The `PreToolUse` block stays unchanged. Add:

```json
    "PostToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [
          { "type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/hooks/design-review.sh", "async": false }
        ]
      }
    ],
```

(Ensure a comma separates it from the preceding `PreToolUse` array and the following `PreCompact` array. Validate with `jq empty hooks/hooks.json`.)

- [ ] **Step 4: Run tests to verify they pass**

Run: `bats tests/manifests.bats`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add hooks/hooks.json tests/manifests.bats
git commit -m "feat(hooks): register PostToolUse(Write|Edit) design-review hook"
```

---

### Task 9: document the design-review pass

**Files:**
- Modify: `skills/gemini-consult/SKILL.md` (after the "Deferred Gemini tools" section)
- Modify: `rules/using-gemini.md` (add the design pass to the hook list)

- [ ] **Step 1: Add a section to `skills/gemini-consult/SKILL.md`**

After the `## Deferred Gemini tools in heavy-MCP sessions` section, insert:

```markdown
## The automatic design-review pass

Separately from the manual consults this rule governs, the plugin runs an
AUTOMATIC, advisory design-review pass via hooks: whenever a design/plan
artifact is written (a `*-design.md` spec, a `*-plan.md`, or a file under a
`specs/`/`plans/` dir) or native plan mode exits, the plugin asks you to
dispatch gemini-validator and gemini-challenger over it. That pass is part of
the uncounted hook channel: it does NOT count against the one-consult-per-turn
cap, and it is advisory (findings surface but never block). It is silenced by
the same `CLAUDE_PLUGIN_GEMINI_DISABLE_HOOKS=1` / `brainstorm.off` kill switch
as every other hook. The blocking validator at native plan-mode exit is
unchanged; only the added challenger and the file-artifact pass are advisory.
```

- [ ] **Step 2: Add the design pass to `rules/using-gemini.md`**

Read `rules/using-gemini.md`, find the list/description of the always-on hooks, and add one bullet matching the existing style:

```markdown
- **Design-review pass** (advisory): when a design/plan artifact is written or
  native plan mode exits, gemini-validator + gemini-challenger review it.
  Advisory only; silenced by `CLAUDE_PLUGIN_GEMINI_DISABLE_HOOKS=1`.
```

- [ ] **Step 3: Verify docs tests still pass**

Run: `bats tests/skills.bats tests/rules.bats`
Expected: PASS (these check frontmatter/structure, which is unchanged)

- [ ] **Step 4: Commit**

```bash
git add skills/gemini-consult/SKILL.md rules/using-gemini.md
git commit -m "docs: document the automatic design-review pass"
```

---

### Task 10: version bump, changelog, full suite, branch + PR

**Files:**
- Modify: `.claude-plugin/plugin.json:4`
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Create the feature branch FIRST**

`main` is PR-only. Before committing Task 1, the executor should have branched. If still on `main`, create the branch now and the per-task commits move with it:

```bash
git checkout origin/main -b feat/design-review-pass
```

(If tasks were committed on `main` locally, move them: `git branch feat/design-review-pass && git reset --hard origin/main` is NOT needed if you branched first. Branch before Task 1.)

- [ ] **Step 2: Bump version in `.claude-plugin/plugin.json`**

Change line 4 from `"version": "0.5.1",` to `"version": "0.6.0",`.

- [ ] **Step 3: Add the CHANGELOG entry**

In `CHANGELOG.md`, under `## [Unreleased]`, add a new section:

```markdown
## [0.6.0] - 2026-06-02

### Added

- **Automatic design-review pass.** Whenever a design/plan artifact is written (a `*-design.md` spec, a `*-plan.md`, or a file under a `specs/`/`plans/` directory) via a new `PostToolUse(Write|Edit)` hook, or when native plan mode exits, the plugin asks Claude to dispatch gemini-validator (VALIDATE_DESIGN) and gemini-challenger (CHALLENGE_DESIGN) over it. The pass is advisory (findings surface but never block), deduped by file content hash so cosmetic re-edits do not re-fire, exempt from the manual one-consult-per-turn cap (it is part of the uncounted hook channel), and silenced by the existing `CLAUDE_PLUGIN_GEMINI_DISABLE_HOOKS` / `brainstorm.off` kill switch. The artifact globs are overridable via `CLAUDE_PLUGIN_GEMINI_DESIGN_GLOBS`.

### Changed

- **Verdict handling is now per-dispatch advisory-or-blocking.** `subagent-verdict-handler.sh` reads and consumes a per-agent "pending mode" marker written by the dispatching hook. A `fail`/`block` verdict blocks (exit 2) only when the marker is `blocking` (the default when no marker exists, which preserves the plan-validator and done-claim gates); the design-review pass writes `advisory` markers so its findings never halt the flow.
- **Native plan-mode exit now also runs an advisory challenger** alongside the existing blocking plan-validator (the validator gate is unchanged).
```

- [ ] **Step 4: Run the FULL suite and confirm green + no dashes**

Run:
```bash
bats tests/
```
Expected: all tests pass (≈83 prior + ≈25 new ≈ 108), 0 failures.

Then confirm no em/en dashes in the diff:
```bash
git diff origin/main --name-only | while read f; do grep -nP '[\x{2013}\x{2014}]' "$f" && echo "DASH in $f"; done
```
Expected: no output.

- [ ] **Step 5: Commit and push**

```bash
git add .claude-plugin/plugin.json CHANGELOG.md
git commit -m "chore: bump to 0.6.0 for design-review pass"
git push -u origin feat/design-review-pass
```

- [ ] **Step 6: Open the PR (labeled, no attribution)**

```bash
gh pr create --label Claude_Code \
  --title "feat: automatic advisory design-review pass (validator + challenger)" \
  --body "Implements docs/superpowers/specs/2026-06-02-design-review-pass-design.md. New PostToolUse(Write|Edit) hook validates+challenges any design/plan artifact (advisory, hash-deduped). Native plan-mode exit keeps the blocking validator and gains an advisory challenger. Advisory-vs-blocking routed through a consumed per-agent pending marker; existing gates unchanged. Full suite green."
```

- [ ] **Step 7: After merge, tag the release**

Once the PR is merged to `main` (check `gh pr view <n> --json state` first; if merged, do NOT push to the branch again):

```bash
git checkout main && git pull origin main
git tag -a v0.6.0 -m "v0.6.0: automatic advisory design-review pass"
git push origin v0.6.0
```

The release workflow (PR #19) publishes it. A fresh Claude Code session is required to load the new hook + agent wiring.

---

## Self-Review

**Spec coverage:**
- Trigger surface = any plan/design artifact (Q1=D) → Task 1 (`is_design_artifact` globs incl. specs/plans/DESIGN/PLAN), Task 5 (PostToolUse hook), Task 7 (ExitPlanMode). ✅
- Validator + challenger both (Q2=A) → Task 4 directive names both; Task 5 dispatches both. ✅
- Hash dedup once per material change (Q3=A) → Task 3 helpers + Task 5 dedup logic + tests. ✅
- Advisory (Q4=A) → Task 6 marker routing + Task 5 writes advisory markers. ✅
- Keep plan-validator blocking, add advisory challenger → Task 7 writes validator=blocking, challenger=advisory. ✅
- Uncounted hook channel, no new toggle (Q5=A) → Task 9 docs; reuses `check_plugin_enabled`. ✅
- Pending-marker routing → Task 2 helpers + Task 6 consume. ✅

**Placeholder scan:** No TBD/TODO; every code step shows full code; every test step shows full test + exact `bats` command + expected result. ✅

**Type/name consistency:** Helper names used consistently across tasks: `is_design_artifact`, `write_pending_mode`, `read_consume_pending_mode`, `file_content_hash`, `design_seen_file`, `build_design_review_directive`, `build_plan_challenge_directive`. Task labels `VALIDATE_DESIGN`/`CHALLENGE_DESIGN`/`CHALLENGE_PLAN` match between builders (Task 4) and assertions (Tasks 5, 7). Marker values `advisory`/`blocking` consistent across Tasks 2, 5, 6, 7. ✅
