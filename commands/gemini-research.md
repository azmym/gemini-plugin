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
