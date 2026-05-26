---
description: Generate images using Gemini's native image generation (Nano Banana) or Imagen 4. Use for UI mockups, hero images, product shots, infographic frames, or any visual content creation task.
---

# Gemini Image Gen

Use this skill to generate images via Gemini's native image generation capability or Google's Imagen 4 model. Both produce high-quality raster images suitable for UI mockups, marketing assets, and visual prototyping.

## When to use this skill

- **UI mockups:** Quickly visualize a screen layout, dashboard design, or component arrangement.
- **Hero images:** Generate a compelling banner or header image for a landing page or blog post.
- **Product shots:** Create lifestyle or conceptual product imagery.
- **Infographic frames:** Generate illustrative backgrounds or iconographic elements for data visualizations.
- **Concept illustrations:** Visualize an architectural metaphor, system diagram in artistic form, or abstract concept.
- **Avatar and icon generation:** Create custom icons, mascots, or profile images.

## MCP tools

| Tool | Purpose |
|---|---|
| `mcp__gemini__gemini_generate_image` | Gemini native image generation (Nano Banana model, fast, conversational quality) |
| `mcp__gemini__gemini_generate_image_imagen` | Imagen 4 (higher fidelity, better photorealism and typography, slightly slower) |

## Choosing between the two tools

| Need | Tool |
|---|---|
| Quick prototyping, iterative concepts, low cost | `mcp__gemini__gemini_generate_image` |
| High-fidelity output, photorealistic, sharp text in image | `mcp__gemini__gemini_generate_image_imagen` |

## Usage pattern

### Quick concept with native Gemini image generation

```json
{
  "tool": "mcp__gemini__gemini_generate_image",
  "arguments": {
    "prompt": "A minimal dashboard UI showing a line chart, three KPI cards, and a sidebar navigation. Clean, modern, dark mode, flat design.",
    "aspect_ratio": "16:9"
  }
}
```

### High-fidelity product shot with Imagen 4

```json
{
  "tool": "mcp__gemini__gemini_generate_image_imagen",
  "arguments": {
    "prompt": "A sleek mobile app screenshot showing a fitness tracking screen with a circular progress ring, step count, and heart rate graph. iOS-style, white background, soft shadows.",
    "aspect_ratio": "9:16",
    "number_of_images": 2
  }
}
```

## Prompt writing tips

- Be specific about style: "flat design", "photorealistic", "watercolor", "isometric 3D".
- Specify aspect ratio when you know the intended use (16:9 for hero banners, 1:1 for avatars, 9:16 for mobile screens).
- Describe what is NOT wanted: "no text overlay", "no gradients", "no stock photo clichés".
- For UI mockups, describe the layout structure explicitly: sidebar on the left, header at the top, main content area.
- Request multiple variants (`number_of_images: 2-4`) when exploring options.

## Output handling

- The tool returns image data (typically base64-encoded or a file path). Always present the image to the user.
- If generating for production use, note that AI-generated images may need human review before publishing.
- Generated images are not licensed for all commercial uses; check Google's usage policies for the specific model.

## Do NOT use this skill for

- Generating video (use `gemini-video-gen`).
- Generating audio or music (use `gemini-audio-tts-music`).
- Analyzing or interpreting existing images (use `gemini-file-analysis`).
- Tasks where a real photo or brand-specific asset is required (AI generation cannot reproduce specific real people, logos, or trademarks accurately).
