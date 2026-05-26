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
