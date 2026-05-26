---
description: Generate music (Lyria 3) or synthesize speech (Gemini TTS, single or multi-speaker). Use for soundtracks, voiceovers, demo narration, notification sounds, or audio branding.
---

# Gemini Audio TTS Music

Use this skill to generate audio assets: background music via Lyria 3 or synthesized speech via Gemini TTS. TTS supports both single-speaker and multi-speaker dialogue.

## When to use this skill

- **Soundtracks and background music:** Generate ambient tracks, loopable background music, or short jingles for demos and presentations.
- **Voiceovers:** Create narration for product walkthroughs, tutorial videos, or demo recordings.
- **Demo narration:** Produce a spoken explanation to accompany a screen recording or slide deck.
- **Notification sounds:** Generate short audio cues, chimes, or alert tones.
- **Audio branding:** Prototype a sonic logo or brand earcon.
- **Multi-speaker dialogue:** Generate a simulated conversation between two or more voices, useful for podcast demos or UX testing of conversational UI.

## MCP tools

| Tool | Purpose |
|---|---|
| `mcp__gemini__gemini_generate_music` | Generate music using Lyria 3 |
| `mcp__gemini__gemini_tts` | Synthesize speech (single or multi-speaker) using Gemini TTS |

## Choosing between music and TTS

| Need | Tool |
|---|---|
| Background music, jingle, ambient track, sound effect | `mcp__gemini__gemini_generate_music` |
| Narration, voiceover, spoken explanation, dialogue | `mcp__gemini__gemini_tts` |

## Usage pattern

### Generate background music with Lyria 3

```json
{
  "tool": "mcp__gemini__gemini_generate_music",
  "arguments": {
    "prompt": "Upbeat, modern corporate background music. Light percussion, synthesizer melody, energetic but not distracting. Suitable for a product demo video.",
    "duration_seconds": 30
  }
}
```

### Single-speaker voiceover with Gemini TTS

```json
{
  "tool": "mcp__gemini__gemini_tts",
  "arguments": {
    "text": "Welcome to the Gemini plugin for Claude Code. This tool gives Claude the ability to consult Google's Gemini models for research, code review, image generation, and more.",
    "voice": "en-US-Standard-D",
    "speed": 1.0
  }
}
```

### Multi-speaker dialogue with Gemini TTS

```json
{
  "tool": "mcp__gemini__gemini_tts",
  "arguments": {
    "turns": [
      { "speaker": "Host", "voice": "en-US-Standard-F", "text": "So, what makes this plugin different from just calling the Gemini API directly?" },
      { "speaker": "Guest", "voice": "en-US-Standard-D", "text": "The main difference is that it integrates Gemini into your Claude Code workflow without any extra setup. You just ask Claude, and it handles the routing." }
    ]
  }
}
```

## Music prompt tips

- Specify genre, tempo, and mood: "slow jazz", "120 BPM electronic", "melancholic acoustic".
- Mention the intended context: "background for a product demo", "loopable office ambience", "30-second intro sting".
- Specify instruments if relevant: "piano and strings only", "no vocals".
- Duration is advisory for Lyria 3; the actual output may vary slightly.

## TTS tips

- Choose voices that match the content register: formal narration vs. conversational dialogue.
- For multi-speaker use, keep each turn to a natural sentence length; very long turns may sound unnatural.
- Adjust `speed` between 0.8 (slower, clearer) and 1.2 (faster) depending on pacing needs.
- Review generated audio for pronunciation of technical terms; you may need to use phonetic spelling for unusual words.

## Do NOT use this skill for

- Transcribing or analyzing existing audio files (use `gemini-file-analysis`).
- Generating video (use `gemini-video-gen`).
- Generating images (use `gemini-image-gen`).
- Text-to-speech outside of a demo or asset creation context (e.g., do not use this for accessibility features in a deployed application; use a production TTS service instead).
