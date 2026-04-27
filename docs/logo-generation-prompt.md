# Engrave Logo / App Icon — Generation Prompt

> Use this prompt with Gemini (Imagen) and ChatGPT (DALL-E) to generate the Engrave app icon.
> Copy the full prompt below into the image generation tool.

---

## Prompt

```
Design a macOS application icon for "Engrave" — a governance-aware AI agent orchestration platform for Apple Silicon. The icon must work as a macOS .icns app icon and be immediately recognizable in the Dock at 64px and on Retina displays at 1024px.

CONCEPT:
The icon represents an engraving tool carving precise, controlled paths — a metaphor for governance over AI agent traffic. It should evoke precision, control, authority, and craftsmanship. Think: a burin (engraving tool) or stylus making deliberate marks, combined with subtle references to routing/networking (paths, nodes, connections).

VISUAL DIRECTION:
- A shield or rounded-square shape as the base (macOS convention)
- Central element: a stylized engraving burin/stylus tip pointing downward, mid-stroke, with fine lines radiating from the contact point suggesting engraved paths or circuit traces
- The engraved lines should subtly form a network/routing pattern (nodes connected by paths) — representing the interposer routing traffic between AI agents and model providers
- Clean, geometric, minimal detail — must read clearly at 64px
- NO text, NO letters, NO wordmarks in the icon itself

COLOR PALETTE (Synthaer Indigo Cream theme):
- Background gradient: deep indigo #1a1525 to warm purple #2c1540
- Primary mark: warm cream #f5e6d3 to bright cream #fff1e0
- Accent highlights: hot pink #ff6b9d (small, sparingly — a glow or reflection)
- Secondary accents: teal #4ec9b0 or lime #b8e986 (for the network trace lines)
- The overall feel should be dark, premium, warm — like polished obsidian with gold/cream engraving

STYLE:
- Flat/semi-flat with subtle depth (soft inner shadow, slight 3D lift on the burin)
- macOS Big Sur / Sequoia icon language: rounded super-ellipse (squircle) shape
- NOT skeuomorphic, NOT photorealistic
- Clean vector aesthetic with fine line details
- Professional, developer-tool quality — similar to the quality level of Xcode, iTerm2, or Tower icons
- The icon should feel like it belongs next to native Apple apps in the Dock

TECHNICAL SPECIFICATIONS:
- Output as a single square image, 1024x1024 pixels
- The icon content should be centered within the squircle with appropriate padding (macOS icons have ~10% padding from edges)
- Background should be the gradient, NOT transparent (macOS convention)
- Corners: macOS squircle radius (continuous curvature, approximately 22% corner radius)
- Must be legible and recognizable when scaled down to 16x16, 32x32, 64x64, 128x128, 256x256, 512x512

DO NOT include:
- Text or letters
- Literal AI/robot imagery
- Generic shield with a checkmark (too generic)
- Gears or cogs (overused)
- Brain imagery
- Locks or padlocks
```

---

## Alternate Prompt (simpler, for tools that prefer shorter prompts)

```
macOS app icon, 1024x1024, squircle shape. Dark indigo-to-purple gradient background (#1a1525 to #2c1540). Center: a stylized engraving burin/stylus in warm cream (#f5e6d3), tip pointing down, with fine teal (#4ec9b0) circuit-trace lines radiating from the contact point forming a subtle network routing pattern. Small hot pink (#ff6b9d) glow at the tip. Flat vector style, clean and minimal, professional developer tool aesthetic. No text. macOS Big Sur icon language.
```

---

## After Generation

Once you have a 1024x1024 PNG, convert it to an .icns file for macOS:

```bash
# Create iconset directory with all required sizes
mkdir Engrave.iconset
sips -z 16 16     icon_1024.png --out Engrave.iconset/icon_16x16.png
sips -z 32 32     icon_1024.png --out Engrave.iconset/icon_16x16@2x.png
sips -z 32 32     icon_1024.png --out Engrave.iconset/icon_32x32.png
sips -z 64 64     icon_1024.png --out Engrave.iconset/icon_32x32@2x.png
sips -z 128 128   icon_1024.png --out Engrave.iconset/icon_128x128.png
sips -z 256 256   icon_1024.png --out Engrave.iconset/icon_128x128@2x.png
sips -z 256 256   icon_1024.png --out Engrave.iconset/icon_256x256.png
sips -z 512 512   icon_1024.png --out Engrave.iconset/icon_256x256@2x.png
sips -z 512 512   icon_1024.png --out Engrave.iconset/icon_512x512.png
sips -z 1024 1024 icon_1024.png --out Engrave.iconset/icon_512x512@2x.png

# Convert to .icns
iconutil -c icns Engrave.iconset -o AppIcon.icns

# Install into the app bundle
cp AppIcon.icns /path/to/Engrave.app/Contents/Resources/AppIcon.icns
```

## Brand Reference

| Element | Hex | Usage |
|---------|-----|-------|
| Deep indigo | `#1a1525` | Background base |
| Card dark | `#231e30` | Mid-tone |
| Hover purple | `#2c2540` | Background highlight |
| Cream | `#f5e6d3` | Primary text / marks |
| Cream bold | `#fff1e0` | Bright highlights |
| Cream dim | `#a89585` | Secondary / muted |
| Hot pink accent | `#ff6b9d` | Primary accent (sparingly) |
| Lime accent | `#b8e986` | Success / active |
| Blue accent | `#7ec8e3` | Info / links |
| Magenta accent | `#e17bed` | Special |
| Teal | `#4ec9b0` | Code / technical |
| Green | `#6abf69` | Status OK |
| Red | `#f44747` | Error / danger |
