# Skills Reference

The plugin ships 9 task-oriented skills. Skills tell Claude WHEN to reach for Gemini and WHICH MCP tool to use. They load on-demand when Claude determines a match based on the description field.

## Skill index

| Skill | MCP tools | Auto-invoked? |
|---|---|---|
| [gemini-when-to-use](#gemini-when-to-use) | (none, decision guide) | Yes (broadest description) |
| [gemini-consult](#gemini-consult) | (none, dispatch rule) | Yes (routes among the 5 agents) |
| [gemini-chat-and-reason](#gemini-chat-and-reason) | `gemini_generate`, `gemini_chat` | Yes |
| [gemini-research-grounded](#gemini-research-grounded) | `gemini_search_grounded`, `gemini_start_research`, `gemini_get_research_report` | Yes |
| [gemini-file-analysis](#gemini-file-analysis) | `gemini_analyze_file` | Yes |
| [gemini-code-exec](#gemini-code-exec) | `gemini_code_execute` | Yes |
| [gemini-image-gen](#gemini-image-gen) | `gemini_generate_image`, `gemini_generate_image_imagen` | Yes |
| [gemini-video-gen](#gemini-video-gen) | `gemini_start_video`, `gemini_get_video` | Yes |
| [gemini-audio-tts-music](#gemini-audio-tts-music) | `gemini_generate_music`, `gemini_tts` | Yes |

## gemini-when-to-use

**Description:** Master router for the Gemini plugin. Covers cost discipline, anti-hallucination triggers, and the four subagent roles.

**Purpose:** Loaded first, before any other gemini-* skill. Tells Claude:
- Which subagent to use for which situation
- When to always call Gemini (post-cutoff facts, destructive ops, second opinions)
- When to never call Gemini (trivial tasks, repeat verdicts, already-in-context answers)
- Cost discipline (Sonnet for validator/researcher and Opus for challenger/summarizer; opt-in deep research; brainstorm-off when you want to reduce per-prompt grounding)

**Invocation:** `/gemini-plugin:gemini-when-to-use` or auto-invoked when Claude is uncertain

## gemini-consult

**Description:** Dispatch rule for the five Gemini agents. Routes a consult to the right agent and enforces a one-consult-per-turn cap on manual dispatches.

**Purpose:** Complements gemini-when-to-use. Where gemini-when-to-use routes among the seven capability skills (raw MCP calls), gemini-consult routes among the five subagents (researcher, validator, challenger, reviewer, summarizer) for structured second-opinion work, and holds the per-turn cap plus the disagreement protocol.

**Invocation:** Auto-consulted when Claude is deciding whether and how to get a Gemini second opinion. No MCP tools (decision guide only).

## gemini-chat-and-reason

**Description:** Get a second opinion from Gemini via text generation or multi-turn chat.

**MCP tools:**
- `mcp__gemini__gemini_generate` (single-turn, stateless, cheapest)
- `mcp__gemini__gemini_chat` (multi-turn, retains session context)

**Use for:** Code review, design critique, sanity-checking before commit, architectural debates.

**Model defaults:** gemini-3.5-flash for chat, gemini-3.1-pro-preview for generate.

## gemini-research-grounded

**Description:** Live-web research with citations for post-training-cutoff information.

**MCP tools:**
- `mcp__gemini__gemini_search_grounded` (quick, 2-5s)
- `mcp__gemini__gemini_start_research` (deep, 30-120s)
- `mcp__gemini__gemini_get_research_report` (polls deep research)

**Use for:** Library versions, API docs, CVEs, pricing, current best practices.

**Deep research:** Only via explicit `--deep` flag. Never auto-triggered.

## gemini-file-analysis

**Description:** Multi-modal file Q&A for PDFs, images, audio, video, and large source files.

**MCP tools:**
- `mcp__gemini__gemini_analyze_file`

**Use for:** Files too large for Claude's context, non-text formats (PDFs, screenshots, audio recordings, video demos).

**Supported formats:** PDF, PNG, JPG, MP3, WAV, MP4, and any format supported by Google's Files API.

## gemini-code-exec

**Description:** Run Python in Gemini's sandbox for computational verification.

**MCP tools:**
- `mcp__gemini__gemini_code_execute`

**Use for:** Verifying math, testing regex patterns, validating algorithms, checking date calculations.

**Limitations:** No network access, no file I/O, no project-specific dependencies. Standard Python libraries only.

## gemini-image-gen

**Description:** Generate images using native Gemini generation or Imagen 4.

**MCP tools:**
- `mcp__gemini__gemini_generate_image` (Nano Banana, fast iteration)
- `mcp__gemini__gemini_generate_image_imagen` (Imagen 4, premium quality)

**Use for:** UI mockups, hero images, product shots, infographic frames.

**Output:** PNG files saved to specified output directory.

## gemini-video-gen

**Description:** Async video generation using Veo 3.1 (start + poll pattern).

**MCP tools:**
- `mcp__gemini__gemini_start_video` (returns operation_id)
- `mcp__gemini__gemini_get_video` (polls until done, returns MP4 path)

**Use for:** Product demos, B-roll, short animations. Takes 30s to a few minutes.

**Polling:** Check every 15 seconds. Claude can do other work while waiting.

## gemini-audio-tts-music

**Description:** Music generation (Lyria 3) and text-to-speech (single or multi-speaker).

**MCP tools:**
- `mcp__gemini__gemini_generate_music` (Lyria 3)
- `mcp__gemini__gemini_tts` (Gemini TTS, multi-speaker capable)

**Use for:** Soundtracks, voiceovers, narration, notification sounds, audio branding.
