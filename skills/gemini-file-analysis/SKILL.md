---
description: Analyze files (PDFs, images, audio, video, large source files) via Gemini's multi-modal file analysis. Use when a file is too large for Claude's context or when the file is a non-text format requiring visual/audio understanding.
---

# Gemini File Analysis

Use this skill to send files to Gemini for multi-modal analysis. Gemini can read PDFs, interpret images, transcribe audio, understand video frames, and reason over large source files that exceed Claude's context window.

## When to use this skill

- **PDF documents:** Research papers, contracts, architecture decision records, runbooks, changelogs.
- **Images:** Screenshots with error messages, diagrams, UI mockups, charts, or photos requiring visual interpretation.
- **Audio files:** Meeting recordings, user interviews, voiceovers that need transcription or content extraction.
- **Video files:** Screen recordings, demo clips, or short videos requiring frame-level understanding.
- **Large source files:** A codebase archive, minified bundle, or log file that is too large to fit in Claude's context.
- **Binary formats:** Any file format Claude cannot read as plain text.

## MCP tools

| Tool | Purpose |
|---|---|
| `gemini_analyze_file` | Upload a file and run a prompt against its contents |

## Usage pattern

### Analyze a PDF

```json
{
  "tool": "gemini_analyze_file",
  "arguments": {
    "file_path": "/path/to/architecture-decision-record.pdf",
    "prompt": "Summarize the key architectural decisions and list any open questions."
  }
}
```

### Interpret a screenshot

```json
{
  "tool": "gemini_analyze_file",
  "arguments": {
    "file_path": "/path/to/error-screenshot.png",
    "prompt": "What error is shown and what are the most likely root causes?"
  }
}
```

### Transcribe an audio recording

```json
{
  "tool": "gemini_analyze_file",
  "arguments": {
    "file_path": "/path/to/meeting-recording.mp3",
    "prompt": "Transcribe the key action items and decisions from this meeting."
  }
}
```

### Analyze a large source file

```json
{
  "tool": "gemini_analyze_file",
  "arguments": {
    "file_path": "/path/to/large-codebase.tar.gz",
    "prompt": "Identify the main modules, entry points, and any obvious code quality issues."
  }
}
```

## Model selection guidance

- For image and text files, the default model (`gemini-3.1-pro-preview`) is sufficient.
- For faster, cheaper answers on simple files, pass `gemini-3.7-flash` via the `model` parameter.
- Files over 15MB must use a `gemini-2.5-*` model. Above that size the tool falls back to Google's Files API, and Gemini 3.x models reject Files API references with `403 PERMISSION_DENIED`. Smaller files are sent inline and work on every model.
- Files consume tokens proportional to size; avoid sending files unnecessarily.

## Tips

- Be specific in the prompt. "Summarize this PDF" is less useful than "List all API endpoints documented in this PDF and their authentication requirements."
- For images containing text (screenshots, diagrams), ask Gemini to extract the text explicitly if you need to process it further.
- Audio transcription quality depends on recording quality; mention any domain-specific terminology in the prompt to improve accuracy.
- If the file path is a URL rather than a local path, check whether `gemini_analyze_file` supports URL inputs or whether you need to download the file first.

## Do NOT use this skill for

- Files that fit comfortably within Claude's context window as plain text (just read them directly).
- Generating new images, video, or audio (use `gemini-image-gen`, `gemini-video-gen`, or `gemini-audio-tts-music`).
- Live web research (use `gemini-research-grounded`).
- Running code or doing math (use `gemini-code-exec`).
- Simple text-only questions where no file is involved (use `gemini-chat-and-reason`).
