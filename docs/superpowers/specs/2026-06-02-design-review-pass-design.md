# Design Review Pass: auto-validate and challenge any design artifact

Date: 2026-06-02
Status: approved (brainstorming), pending spec review
Target release: 0.6.0 (minor: new always-on behavior, no breaking change)

## Problem

The plugin does not run an automatic validate-and-challenge pass over a design.
Verified against `hooks/hooks.json` and the hook scripts:

- `plan-complete.sh` (`PreToolUse(ExitPlanMode)`) spawns **gemini-validator**, but
  ONLY when a design goes through Claude Code's native plan mode. A superpowers
  brainstorming spec written to `docs/superpowers/specs/*-design.md` never calls
  `ExitPlanMode`, so it gets no validation.
- `pre-destructive-bash.sh` spawns **gemini-challenger**, but ONLY on destructive
  shell commands. No "challenge the design" trigger exists anywhere.
- `stop-done-claim.sh` validates a *done-claim*, not a design.

Net: a design produced through the brainstorming -> spec flow gets no automatic
"validate against the problem and challenge the main agent" pass. This spec adds
one.

## Decisions (from brainstorming)

1. **Trigger surface = any plan/design artifact** (Q1=D). Two trigger points feed
   one shared pass: a new `PostToolUse(Write|Edit)` hook that path-matches design
   artifacts on disk, plus the existing `PreToolUse(ExitPlanMode)` hook.
2. **Composition = validator + challenger, both, every time** (Q2=A).
3. **Firing discipline = once per design file, re-fire only on material change**
   (Q3=A), where "material change" = the file's SHA-256 differs from the last
   seen hash for that path.
4. **Behavior = advisory** (Q4=A): the pass surfaces findings but never halts the
   flow.
5. **ExitPlanMode = keep the existing blocking plan-validator unchanged, add an
   advisory challenger alongside it** (explicit follow-up choice). The new
   file-artifact pass is fully advisory (both agents).
6. **Controls = part of the automatic hook channel** (Q5=A): silenced by the
   existing `CLAUDE_PLUGIN_GEMINI_DISABLE_HOOKS` / `brainstorm.off` kill switch,
   exempt from the manual one-consult-per-turn cap (hooks are a separate,
   uncounted channel). No new toggle, no new command.
7. **Advisory-vs-blocking routing = per-agent consumed pending marker** (approved):
   the dispatching hook records the intended mode for the agent it spawns; the
   `SubagentStop` verdict-handler reads and consumes the marker to decide whether
   a `fail`/`block` verdict halts (blocking) or is printed and ignored (advisory).

## Architecture

### New component: `hooks/design-review.sh`

`PostToolUse(Write|Edit)` hook. Flow:

```
1. check_plugin_enabled        # honors CLAUDE_PLUGIN_GEMINI_DISABLE_HOOKS=1 / brainstorm.off
2. check_gemini_available      # no API key -> advisory message, exit 0
3. ensure_data_dir
4. FILE_PATH = jq -r '.tool_input.file_path // empty'  ; [ -z ] -> exit 0
5. is_design_artifact "$FILE_PATH"   || exit 0     # the common, cheap case
6. material-change check:
     PATHHASH = shasum(FILE_PATH)[0:12]
     NEWHASH  = shasum(file contents)
     SEEN     = data_dir/design-review-seen/<PATHHASH>.sha
     [ NEWHASH == contents-of-SEEN ] -> exit 0       # typo / no-op edit, dedup
7. write advisory pending markers for BOTH agents:
     data_dir/pending/gemini-validator.mode  = "advisory"
     data_dir/pending/gemini-challenger.mode = "advisory"
8. emit ONE additionalContext directive instructing Claude to dispatch BOTH
   gemini-validator (VALIDATE_DESIGN) and gemini-challenger (CHALLENGE_DESIGN)
   on this design file.
9. record NEWHASH into SEEN.
10. exit 0   (PostToolUse: advisory injection only, never denies the tool)
```

Emits the standard `hookSpecificOutput.additionalContext` JSON envelope (exit 0),
matching `plan-complete.sh`. PostToolUse cannot and must not deny anything; the
write has already happened.

### Design-artifact matcher: `is_design_artifact(path)` in `hooks/lib/common.sh`

Default globs (overridable via `CLAUDE_PLUGIN_GEMINI_DESIGN_GLOBS`, a
colon-separated list):

- `docs/superpowers/specs/*-design.md`
- `docs/superpowers/plans/*.md`
- `*-plan.md`
- `*/specs/*.md`
- `*/plans/*.md`
- `*/DESIGN.md`
- `*/PLAN.md`

Matched case-sensitively against the path as provided in `tool_input.file_path`
(absolute or relative). Implementation uses bash `case`/`[[ == glob ]]` over the
configured list; a match returns 0, no match returns 1.

### Extend `hooks/plan-complete.sh`

Unchanged: still builds and emits the **blocking** `VALIDATE_PLAN` directive for
gemini-validator. Added: write `pending/gemini-challenger.mode = "advisory"` and
append a second directive (`build_plan_challenge_directive`, task
`CHALLENGE_PLAN`) so the challenger runs advisory alongside the blocking
validator. The validator path writes no marker (or writes `"blocking"`) so its
existing gate is preserved.

### Modify `hooks/subagent-verdict-handler.sh`

Today: any `fail`/`block` verdict -> `exit 2` (blocking). Change:

```
MODE_FILE = data_dir/pending/<AGENT>.mode
MODE = cat MODE_FILE 2>/dev/null || echo "blocking"   # default preserves current behavior
rm -f MODE_FILE                                        # consume (one-shot)
...
if VERDICT in (fail, block):
    print findings to stderr
    if MODE == "advisory": exit 0
    else:                  exit 2
```

The existing loop-guard (identical verdict twice -> advisory) and plan-history
append stay as-is. Default `blocking` when no marker means the plan and
done-claim gates are untouched.

### New directives in `hooks/lib/prompt-builder.sh`

- `build_design_validation_directive(file_path, history)` -> gemini-validator,
  task `VALIDATE_DESIGN`: "Does this design solve the stated problem? Flag gaps,
  hallucinations, missed acceptance criteria. Return structured JSON verdict."
- `build_design_challenge_directive(file_path, history)` -> gemini-challenger,
  task `CHALLENGE_DESIGN`: ">=2 alternative approaches and >=1 reason this design
  is wrong. Return structured JSON."
- `build_plan_challenge_directive(plan_text)` -> gemini-challenger, task
  `CHALLENGE_PLAN` (advisory companion to the existing VALIDATE_PLAN).

Each design directive passes the design file path and the recent `plan-history`
for its task type so the agent does not re-raise already-addressed points.

## Data flow

```
Write/Edit a spec/plan file
   -> PostToolUse(Write|Edit) -> design-review.sh
        -> glob match + hash dedup
        -> pending/{validator,challenger}.mode = advisory
        -> additionalContext: "dispatch validator + challenger on <file>"
   -> main Claude dispatches both agents
        -> each finishes -> SubagentStop -> subagent-verdict-handler.sh
             -> reads+consumes pending marker (advisory)
             -> prints findings, exits 0 (never halts)

Native plan mode exit
   -> PreToolUse(ExitPlanMode) -> plan-complete.sh
        -> VALIDATE_PLAN (validator, BLOCKING, no marker/blocking marker)
        -> pending/gemini-challenger.mode = advisory
        -> CHALLENGE_PLAN (challenger, advisory)
   -> verdict-handler: validator fail -> exit 2 (blocks); challenger -> advisory
```

## Error handling

- No API key, plugin disabled, or `brainstorm.off`: every hook exits 0 silently
  (existing `check_*` helpers). Never blocks work.
- Empty/missing `file_path`: exit 0.
- Data-dir write failure: `trap ... ERR -> exit 0` (every hook already has this);
  a failed marker write degrades to default `blocking` for that agent, which is
  the safe direction (it would not silently swallow a real plan/done-claim gate).
- Marker is one-shot (deleted on read), so a crashed/never-finished agent leaves
  at most one stale marker; the next dispatch overwrites it. Acceptable.

## Testing

New `tests/design-review.bats` + additions to existing suites:

1. Non-design path (`src/foo.ts`) -> exit 0, no directive.
2. Design path, first write -> directive names BOTH gemini-validator and
   gemini-challenger.
3. Same content rewritten (same hash) -> exit 0, no re-dispatch (dedup).
4. Materially changed content -> re-fires.
5. `CLAUDE_PLUGIN_GEMINI_DISABLE_HOOKS=1` -> exit 0 silently (extend test #62).
6. verdict-handler: advisory marker + `fail` verdict -> prints findings, exit 0.
7. verdict-handler: blocking marker (or none) + `fail` -> exit 2 (no regression).
8. `manifests.bats`: assert a `PostToolUse(Write|Edit)` block exists pointing at
   `design-review.sh`.
9. `is_design_artifact` unit cases: each default glob matches; a near-miss
   (`notes.md`, `readme-plan.txt`) does not.

Target: green suite (currently 83 -> ~92).

## Files touched

| File | Change |
|---|---|
| `hooks/design-review.sh` | new: PostToolUse(Write\|Edit), glob match, hash dedup, dual dispatch |
| `hooks/hooks.json` | add PostToolUse(Write\|Edit) block |
| `hooks/plan-complete.sh` | add advisory challenger marker + CHALLENGE_PLAN directive |
| `hooks/subagent-verdict-handler.sh` | read+consume per-agent pending marker; advisory->0, blocking->2 |
| `hooks/lib/prompt-builder.sh` | build_design_validation_directive, build_design_challenge_directive, build_plan_challenge_directive |
| `hooks/lib/common.sh` | is_design_artifact(path), design-seen hash helpers, pending-marker helpers |
| `skills/gemini-consult/SKILL.md` | document the design pass (uncounted hook channel) |
| `rules/using-gemini.md` | document the design pass and its kill switch |
| `tests/design-review.bats` (new), `tests/hooks-triggers.bats`, `tests/manifests.bats` | the tests above |
| `CHANGELOG.md`, `.claude-plugin/plugin.json` | [0.6.0] Added |

## Out of scope (YAGNI)

- No new toggle/command dedicated to the design pass (Q5=A).
- No blocking behavior on the file-artifact pass (Q4=A).
- No smart risk-routing of the challenger (rejected option Q2=C).
- No combined single-agent review (rejected option Q2=D).
- No re-fire on cosmetic edits (Q3=A hash dedup).

## Release

Minor bump to 0.6.0 (new always-on behavior). After merge, tag `v0.6.0` so the
release workflow (PR #19) publishes it. A fresh session is required for the new
agent/hook wiring to load.
