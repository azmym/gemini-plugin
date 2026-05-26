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
