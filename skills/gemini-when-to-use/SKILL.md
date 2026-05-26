---
description: Master router for the Gemini plugin. Use when uncertain whether a Gemini consult is warranted; covers cost discipline, anti-hallucination triggers, and the four subagent roles. Invoke before any other gemini-* skill.
---

# Gemini When To Use

This is the master routing skill for the Gemini plugin. Before invoking any other `gemini-*` skill, consult this guide to decide whether a Gemini consult is warranted and which capability to reach for.

## When to invoke this skill

- You are uncertain whether the task justifies a Gemini call at all.
- The task touches multiple Gemini capabilities and you need to pick the right one.
- You want to avoid hallucination on a fact, version number, CVE, or post-training claim.
- A user asks "use Gemini" without specifying which capability.

## Cost discipline rules

1. **Do not call Gemini for tasks Claude can handle confidently.** Simple string manipulation, well-known algorithms, boilerplate generation, and in-context refactors do not need a second opinion.
2. **One Gemini call per sub-task.** Do not fan out multiple parallel Gemini calls unless each covers a distinct, independent concern.
3. **Prefer cheaper tools first.** Use `gemini_generate` (chat/reason) before reaching for `gemini_search_grounded` or deep research unless freshness is required.
4. **File analysis is expensive.** Upload files to Gemini only when the file is genuinely too large for Claude's context or is a non-text format (PDF, image, audio, video).

## Anti-hallucination triggers

Invoke a Gemini skill whenever the response would otherwise rely on:
- A library version, API endpoint, or config key that may have changed since training cutoff.
- A CVE, security advisory, or patch status.
- A claim about a living document (spec, RFC, standard) that may have been updated.
- An assertion about the current state of a third-party service or cloud provider.

## The four subagent roles (agents/ directory)

These are pre-built agent configurations for common Gemini workflows. Prefer them over raw MCP calls for structured tasks:

| Subagent | File | Best for |
|---|---|---|
| Researcher | `agents/gemini-researcher.md` | Deep research synthesis, primary sources with citations |
| Summarizer | `agents/gemini-summarizer.md` | Condensing long documents, transcripts, or codebases |
| Validator | `agents/gemini-validator.md` | Fact-checking claims, verifying logic, sanity-checking before commit |
| Challenger | `agents/gemini-challenger.md` | Devil's advocate critique, stress-testing designs or decisions |

## The seven capability skills

After consulting this routing guide, invoke exactly one of:

| Skill | Use for |
|---|---|
| `gemini-chat-and-reason` | Second opinions, code review, design critique |
| `gemini-research-grounded` | Live-web search, post-cutoff facts, citations |
| `gemini-file-analysis` | PDFs, images, audio, video, oversized source files |
| `gemini-code-exec` | Computational verification, math, regex testing |
| `gemini-image-gen` | UI mockups, hero images, product shots |
| `gemini-video-gen` | Short clips, demos, B-roll, motion concepts |
| `gemini-audio-tts-music` | Music, voiceover, narration, audio branding |

## Decision flowchart

1. Is the task purely generative text within Claude's knowledge? → No Gemini needed.
2. Does it require freshness or a primary source? → `gemini-research-grounded`
3. Is there a file that is too large or non-text? → `gemini-file-analysis`
4. Do you need code execution or math verification? → `gemini-code-exec`
5. Do you need an image, video, or audio asset? → `gemini-image-gen`, `gemini-video-gen`, or `gemini-audio-tts-music`
6. Do you want a second opinion or critique? → `gemini-chat-and-reason`

## Do NOT use this skill for

- Actually making any Gemini API calls (this skill has no MCP tools; it is a decision guide only).
- Tasks where you already know which Gemini capability to use.
- Non-Gemini decisions.
