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
