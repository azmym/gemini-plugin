---
description: Get a second opinion from Gemini via text generation or multi-turn chat. Use for code review, design critique, sanity-checking before commit, or when Claude wants another perspective on a complex decision.
---

# Gemini Chat and Reason

Use this skill when you want Gemini to serve as a reasoning partner: reviewing code, critiquing a design, stress-testing a decision, or providing a second opinion on anything Claude has produced or is about to produce.

## When to use this skill

- **Code review:** You have written a non-trivial function or module and want a second set of eyes before committing.
- **Design critique:** You are proposing an architecture, API contract, or data model and want pushback.
- **Sanity check:** You are about to take an irreversible action (deploy, delete, migrate) and want confirmation the plan is sound.
- **Perspective shift:** Claude's reasoning has gone deep down one path; Gemini can surface blind spots.
- **Multi-turn dialogue:** You need to iterate on a draft or decision through several back-and-forth exchanges.

## MCP tools

| Tool | Purpose |
|---|---|
| `gemini_generate` | Single-shot text generation, best for one-off questions or reviews |
| `gemini_chat` | Multi-turn conversation, best for iterative critique or dialogue |

## Model selection guidance

- For routine second opinions and code reviews, use the default model (Gemini 2.5 Flash or equivalent); it is fast and cheap.
- For complex architectural decisions or lengthy documents requiring deep reasoning, request `gemini-2.5-pro` explicitly via the `model` parameter.
- Avoid `gemini-2.5-pro` on short, low-stakes queries; the cost uplift is not justified.

## Usage pattern

### Single-shot review with `gemini_generate`

```json
{
  "tool": "gemini_generate",
  "arguments": {
    "prompt": "Review the following Go function for correctness, error handling, and idiomatic style:\n\n```go\n<paste code here>\n```",
    "model": "gemini-2.5-flash"
  }
}
```

### Multi-turn design critique with `gemini_chat`

Start a session, then send follow-up messages in the same `session_id`:

```json
{
  "tool": "gemini_chat",
  "arguments": {
    "message": "I am designing a REST API for a payment service. Here is the proposed endpoint structure: <details>. What are the biggest risks?",
    "session_id": "payment-api-review"
  }
}
```

Follow-up turn:

```json
{
  "tool": "gemini_chat",
  "arguments": {
    "message": "Good points. If we add idempotency keys, does that address the double-charge risk?",
    "session_id": "payment-api-review"
  }
}
```

## Tips

- Include the full relevant context (code, error messages, requirements) in the first message. Gemini does not have access to the local codebase.
- Ask for a structured response (numbered issues, severity ratings) to make the review easier to act on.
- If Gemini's critique contradicts your judgment, treat it as input, not a directive. You are responsible for the final decision.

## Do NOT use this skill for

- Fetching live information from the web (use `gemini-research-grounded` instead).
- Analyzing a file that is too large to paste (use `gemini-file-analysis` instead).
- Running code or verifying calculations (use `gemini-code-exec` instead).
- Generating images, video, or audio assets.
- Tasks Claude can handle confidently without a second opinion.
