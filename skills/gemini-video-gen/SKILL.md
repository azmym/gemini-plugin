---
description: Generate short video clips using Veo 3.1. Async start+poll pattern; returns an MP4 file. Use for product demos, B-roll footage, short animations, or motion design concepts.
---

# Gemini Video Gen

Use this skill to generate short video clips powered by Google Veo 3.1. Video generation is asynchronous: you start a job, then poll until the MP4 is ready.

## When to use this skill

- **Product demos:** Animate a UI flow, show a feature in action, or create a walkthrough clip.
- **B-roll footage:** Generate background video for a presentation, landing page, or social media post.
- **Short animations:** Bring a concept, diagram, or illustration to life as a few-second motion clip.
- **Motion design concepts:** Prototype a logo animation, loading screen, or transition effect.
- **Marketing content:** Short social clips, teaser videos, or visual hooks.

## MCP tools

| Tool | Purpose |
|---|---|
| `gemini_start_video` | Submit a video generation request; returns a job ID |
| `gemini_get_video` | Poll for job status and retrieve the completed MP4 when done |

## Async start+poll pattern

Video generation with Veo 3.1 is not instant. The typical workflow is:

1. Call `gemini_start_video` with a prompt. Receive a `job_id`.
2. Wait a few seconds (Veo 3.1 typically takes 20-90 seconds for short clips).
3. Call `gemini_get_video` with the `job_id`. If status is `processing`, wait and retry. If status is `done`, retrieve the output file path.

Do NOT spin-poll aggressively. Wait at least 10 seconds between poll attempts.

## Usage pattern

### Step 1: Start video generation

```json
{
  "tool": "gemini_start_video",
  "arguments": {
    "prompt": "A mobile phone screen showing a recipe app. The user scrolls through a list of recipes, taps on 'Spaghetti Bolognese', and the detail screen slides in smoothly. Clean, modern UI, soft lighting.",
    "duration_seconds": 5,
    "aspect_ratio": "9:16"
  }
}
```

Response example: `{ "job_id": "veo-abc123", "status": "processing" }`

### Step 2: Poll for completion

```json
{
  "tool": "gemini_get_video",
  "arguments": {
    "job_id": "veo-abc123"
  }
}
```

Poll every 15 seconds until status is `done`. Then the response will include an output file path or URL.

## Duration and aspect ratio guidance

- `duration_seconds` is advisory: Veo 3.1 targets the requested length but may produce a clip slightly shorter or longer. Do not use this value for timing-critical applications.
- Common aspect ratios: `16:9` (landscape/desktop), `9:16` (vertical/mobile), `1:1` (square/social).
- Keep clips short (3-8 seconds) for best quality. Longer clips may exhibit drift or inconsistency.

## Prompt writing tips

- Describe camera movement if relevant: "slow pan left", "zoom in on the screen", "static shot".
- Specify the subject, setting, and action in the first sentence.
- Mention style: "cinematic", "screen recording style", "flat animation", "photorealistic".
- For UI/app demos, describe the on-screen content explicitly rather than relying on Veo to invent a UI.

## Do NOT use this skill for

- Generating still images (use `gemini-image-gen`).
- Generating audio or music without video (use `gemini-audio-tts-music`).
- Analyzing or transcribing existing videos (use `gemini-file-analysis`).
- Long-form video production (Veo 3.1 is optimized for short clips; this skill is not suitable for videos longer than ~30 seconds).
- Real-time or streaming video.
