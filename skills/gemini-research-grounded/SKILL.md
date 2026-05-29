---
description: Perform live-web research via Gemini's search-grounded answers or deep research synthesis. Use when a question involves post-training-cutoff information, library versions, CVEs, API docs, or any claim needing a primary source with citations.
---

# Gemini Research Grounded

Use this skill whenever the answer depends on information that may have changed since Claude's training cutoff, or whenever you need primary sources and citations rather than recalled knowledge.

## When to use this skill

- **Library/framework versions:** "What is the latest stable version of X?" or "Is feature Y available in version Z?"
- **CVE and security advisories:** Patch status, CVSS scores, affected versions, mitigations.
- **API documentation:** Endpoint signatures, authentication schemes, response shapes that may have evolved.
- **Living standards and specs:** RFC status, W3C spec updates, OpenAPI changes.
- **Current events affecting engineering:** Cloud provider incidents, deprecation announcements, EOL dates.
- **Factual claims requiring a citation:** Any assertion that should be backed by a URL.
- **Deep research synthesis:** Multi-source synthesis on a technical topic, competitive landscape, or best-practice survey.

## MCP tools

| Tool | Purpose |
|---|---|
| `gemini_search_grounded` | Fast, single-shot search-grounded answer with citations |
| `gemini_start_research` | Kick off an async deep research job (returns a job ID) |
| `gemini_get_research_report` | Poll for and retrieve the completed deep research report |

## Choosing between fast search and deep research

| Scenario | Tool |
|---|---|
| A single fact, version, or advisory | `gemini_search_grounded` |
| A broad technical survey or multi-source synthesis | `gemini_start_research` + `gemini_get_research_report` |

Deep research is asynchronous and may take 30-120 seconds. Use it only when breadth and synthesis matter more than speed.

## Usage pattern

### Fast grounded search

```json
{
  "tool": "gemini_search_grounded",
  "arguments": {
    "query": "Latest stable release of Kubernetes and its release date",
    "model": "gemini-2.5-flash"
  }
}
```

The response includes cited sources. Always surface the citations to the user.

### Async deep research

Step 1: start the job.

```json
{
  "tool": "gemini_start_research",
  "arguments": {
    "topic": "Best practices for zero-downtime database migrations in PostgreSQL 16",
    "depth": "comprehensive"
  }
}
```

Step 2: retrieve the report once the job is complete (poll until status is `done`).

```json
{
  "tool": "gemini_get_research_report",
  "arguments": {
    "job_id": "<job_id from step 1>"
  }
}
```

## Tips

- Always pass the cited URLs back to the user so they can verify claims.
- For CVE lookups, include the CVE ID in the query for precision (e.g., `CVE-2024-12345 patch status`).
- Deep research results are verbose; summarize key findings before presenting to the user.
- If the grounded answer is uncertain or says "I could not find", try rephrasing the query or switching to deep research.

## Do NOT use this skill for

- Tasks where Claude's training knowledge is sufficient and freshness is not required.
- Generating images, video, or audio.
- Running code or doing math (use `gemini-code-exec`).
- Analyzing uploaded files (use `gemini-file-analysis`).
- Simple second opinions where no web search is needed (use `gemini-chat-and-reason`).
