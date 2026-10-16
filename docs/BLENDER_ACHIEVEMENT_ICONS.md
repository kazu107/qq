# Achievement Sculptures (QQ-0.43.0)

All 30 achievement groups have distinct transparent Blender-rendered icons.
The 296 claim stages reuse their group's semantic icon, rather than changing its
identity as progress increases. Existing targets, rewards and claims are unchanged.

The upper information row contains an 88px square icon on the left and the name,
description and reward on the right. The existing full-width footer remains below
both, with stage/progress numbers, progress bar and claim button.

## Artwork and Rebuilding

- Editable source: `art_src/blender/achievements/qq_achievements.blend`
- Asset Browser collections: `achievement_<achievement_id>`
- Source/render/export hashes and concepts: adjacent `.manifest.json`
- Original sculptures: `tools/blender/build_achievement_icons.py`
- PNG finalization and registry update: `tools/finalize_achievement_icons.py`
- Rebuild: `tools/build_blender_achievement_icons.ps1`
- Contact sheet: `art_src/blender/previews/achievement_icons.png`
- Runtime: `assets/icons/achievements/<achievement_id>.png`, 128px RGBA

Rendering uses an isolated factory-startup Blender process, Cycles on four CPU
threads, 1024px square masters and transparent film. The active user's Blender
document/MCP session and other source batches are not modified. Shared authored
mechanical parts and materials are reused, but every achievement gets its own
collection and composition. No downloaded or image-generation artwork is used.

Validation checks all thirty IDs, unique exports, transparent corners, unclipped
masters, 48px silhouettes, source hashes and cold reopening of the saved Blend.
The original Blend, raw masters and contact sheet are excluded from Godot by
`art_src/.gdignore`; only the small PNGs enter the PCK.

## Runtime and Verification

`AchievementIconCatalog` loads by stable achievement ID and retains textures across
scene transitions. Startup warmup includes the small icon set. Claims refresh the
existing text/bar widgets without recreating the icon. Developer Art Lab includes
the achievement category for full-size and miniature inspection.

`AchievementIconSmoke` checks coverage, image size/alpha, cache identity, left/top
alignment, footer separation and claim reuse. `web_achievement_progress_review.mjs`
checks all icon bindings and rectangles alongside stage claims in Japanese and
English, landscape and portrait viewports.
