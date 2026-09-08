# Starter Character Batch 02

Completed scope: 2026-09-09 / QQ-0.21.0.

This batch adds six rigged starter models and replaces all seven starter
portraits with renders of their corresponding character geometry. Balanced's
existing GLB and all enemy assets stay unchanged. Cards and relics are outside
this batch; their individual-scene / transparent-object art direction remains.

| Starter | Shared body layer | Distinct equipment |
| --- | --- | --- |
| balanced | First-batch body | Existing blade and blue shield |
| tempo | Light | Swept fins, visor, rapier, buckler, twin thrusters |
| fortress | Heavy | Crenellated helm, hammer, braced tower shield, reactor |
| vanguard | Assault | Horned helm, asymmetric shoulders, greatsword, thrusters |
| aegis | Heavy | White/gold armor, crest, emblem shield, hammer, reactor |
| chrono | Arcane | Split robe panels, halo, clock staff, orb, chrono rings |
| turret | Mechanical | Goggles, antenna, shoulder gun, blaster, ammo pack |

## Sources And Reuse

- `art_src/blender/library/qq_starter_parts.blend`: 26 editable part collections,
  role-tagged materials, an 18-bone rest-space template, and Asset Browser data.
- `art_src/blender/characters/qq_starters.blend`: seven local rigged assemblies,
  linked reference collections, a portrait camera, lights, and the lineup view.
- `tools/blender/starter_character_parts.py`: body layers and equipment kit.
- `tools/blender/build_starter_batch.py`: assembly, palette, GLB export, portraits.

The generator links the library and makes local mesh copies for merging and
palette overrides. Regenerate to propagate part changes; the merged export mesh
is not a live Library Override. Bones retain the original rest transforms.
Meshes are rigidly weighted to one named bone per vertex. Five existing runtime
sockets and all 18 shared clips are reused without changing combat rules.

Each exported character has one skinned mesh, 11-14 material surfaces, and fewer
than 35,000 source triangles. Runtime body-scale profiles also apply to portrait
renders. No high-detail Blend, intermediate image, or render rig enters the PCK.

## Regenerate

Blender 5.2.1 LTS and Python with Pillow are required. From the project root:

```powershell
.\tools\build_blender_starter_batch.ps1 -RenderSize 2048
```

Use `-BlenderPath` and `-PythonPath` on another PC. The script launches isolated
`--background --factory-startup` processes, then cold-reloads the saved Blend and
registers SHA-256 provenance. Do not run two copies against the same output paths.
No Blender MCP connection, paid service, or external model download is needed.

Source renders are 2048px, portraits are 1024px, and intermediates remain under
`tools/.local/starter_batch`. Regeneration overwrites only this batch's outputs.

## Game And Verification

`data/battle_visuals.json` maps each starter to its GLB. Battle, online opponent
display, deck previews, and the existing animation lab use those same profiles.
The existing startup service caches all eight authored models, including Scout.
All seven portrait paths remain `assets/portraits/{starter_id}.png`.

Run `res://tools/StarterArtReview.tscn` to compare animated game models and their
portraits. `QQ_STARTER_REVIEW_CAPTURE` accepts an absolute PNG screenshot path.
Use the existing developer-mode Battle Animation Lab for model selection,
camera changes, ready/action playback, slow motion, and frame stepping.

Related regression scenes: `StarterArtSmoke`, `AuthoredBattleModelsSmoke`,
`BattleAnimationSystemSmoke`, `BattleAnimationLabSmoke`, `RunSetup3DPreviewSmoke`,
`BattleVisualProfilesSmoke`, `StartupCacheSmoke`, and `ArtProvenanceSmoke`.
The starter smoke checks 7 x 18 clips at four samples, five sockets, matching
portraits/hashes, one mesh per model, and stable cache reuse.
