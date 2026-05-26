# How to: Research live data

This guide covers using Gemini's search-grounded capabilities to answer questions that depend on current web information.

## When to use grounded research

Use grounded research when:
- The question involves library versions, API shapes, or pricing that may have changed after Claude's training cutoff
- You need CVE details or security advisories
- You want citations to authoritative sources
- You need to verify a claim against current documentation

## Automatic grounding (UserPromptSubmit hook)

The `UserPromptSubmit` hook automatically grounds prompts that contain keywords like: `api`, `cve`, `version`, `release`, `deprecated`, `library`, `package`, `sdk`, `framework`, `upgrade`, `migrate`.

In brainstorming mode (`/gemini-plugin:gemini-brainstorm-on`), every prompt is grounded regardless of keywords.

The hook spawns `gemini-researcher` which calls `gemini_search_grounded` and returns answer + citations.

## Manual quick research

For a one-off grounded lookup:

```
/gemini-plugin:gemini-research What is the latest stable version of React?
```

Returns:
- Answer with factual content
- Citations (URLs with titles)
- Freshness date
- Confidence level (high/medium/low)

## Deep research

For complex questions requiring multi-source synthesis (architecture comparisons, migration guides, comprehensive overviews):

```
/gemini-plugin:gemini-research Compare JWT vs OAuth2 vs mTLS for microservices auth in 2026 --deep
```

Deep research uses `gemini_start_research` + `gemini_get_research_report` (polling). It takes 30-120 seconds but produces a comprehensive report with multiple sources.

Deep research is opt-in only (the `--deep` flag). It never fires automatically.

## Understanding the output

The researcher returns:

```json
{
  "answer": "The detailed answer...",
  "citations": [
    {"url": "https://...", "title": "...", "relevance": "..."}
  ],
  "freshness": "2026-05-26",
  "confidence": "high | medium | low",
  "model": "gemini-3.5-flash"
}
```

Confidence levels:
- **high**: multiple authoritative sources agree
- **medium**: single source or limited corroboration
- **low**: sources conflict, unofficial sources, or no results found

## Brainstorming mode

Enable unconditional grounding for design sessions:

```
/gemini-plugin:gemini-brainstorm-on
```

Every prompt is now grounded, regardless of keywords. This is valuable during brainstorming where many decisions depend on current state of libraries, APIs, and best practices.

Disable when done:

```
/gemini-plugin:gemini-brainstorm-off
```

## Tips

- The researcher uses Haiku by default for quick lookups (fast, cheap)
- Deep research escalates to `deep-research-max-preview` (slower, comprehensive)
- Citations are always included; if no sources are found, the researcher says so explicitly (never fabricates)
- The grounding hook only blocks (exit 2) when it fires; the researcher spawns and Claude waits for citations before answering
