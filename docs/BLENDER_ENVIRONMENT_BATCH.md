# Blender Environment Batch

## Scope

This batch owns the editable meadow/ruin environment, two background renders,
and an optional transparent 3D QueueQuest emblem. It does not change GDScript,
themes, project settings, version files, or centralized art provenance.

The existing QueueQuest SVG wordmark, square SVG mark, and animated loading
layers remain authoritative and unchanged. The new raster emblem is a companion
asset, not a replacement for those SVGs.

## Outputs

| Path | Purpose |
| --- | --- |
| `tools/blender/build_environment_batch.py` | Independent reproducible Blender authoring/export/render script |
| `art_src/blender/environment/qq_battlefield.blend` | Editable original parts, semantic groups, cameras, lights, and emblem |
| `art_src/blender/environment/qq_battlefield.manifest.json` | Aggregate hashes, dimensions, mesh budgets, reuse metadata, and asset records |
| `assets/models/environment/qq_battlefield.glb` | Consolidated static field, identity root, Y-up glTF |
| `assets/backgrounds/hub.png` | 1920 x 1080 daylight field; UI-safe dark center |
| `assets/backgrounds/run_result.png` | 1920 x 1080 amber-dusk field; UI-safe dark center |
| `assets/branding/queuequest-emblem-3d.png` | 256 x 256 transparent three-card/Q/timeline emblem |
| `art_src/blender/previews/environment_batch.png` | Overview of the actual authored field |
| `art_src/blender/previews/environment_battle_camera.png` | Field through the current battle camera, without actors/UI |
| `art_src/blender/previews/environment_emblem_sizes.png` | 16 / 32 / 64 px emblem images enlarged with nearest-neighbor pixels |

Both backgrounds are rendered from the same saved 3D scene at 2560 x 1440 before
downsampling. The emblem is rendered at 1024 x 1024 before downsampling. These
high-resolution intermediates are kept under
`tools/.local/blender_environment_batch`, outside the Web PCK. The saved `.blend`
and generator are sufficient to reproduce them on another PC.

## Combat Layout Contract

- Root: `QueueQuestBattlefield`, identity translation/rotation/scale.
- Grid: 7 columns x 5 rows.
- Tile dimensions: Godot `Vector3(1.61, 0.105, 1.29)`.
- Column/row spacing: 1.76 / 1.44.
- Foreground meadow: 17.8 x 11.8, height 0.42, center `(0, -0.38, -0.1)`.
- World ground: 42 x 38, height 0.55, center `(0, -0.66, -8)`.
- Source conversion: Godot `(x, y, z)` becomes Blender `(x, -z, y)`.
- glTF export restores Y-up; no extra rotation or scaling is needed in Godot.
- Battle camera, actor positions, lane positions, and existing HUD are not moved.
- No cameras, lights, characters, rig, animation clips, or image textures are
  exported in the field GLB.

The camera review uses the existing location `(0, 6.75, 10.35)` and target
`(0, 0.78, -0.42)`. Live environment lighting/sky and UI remain the responsibility
of `BattleStage3D`; the Blender lights are render rigs only.

## Semantic Groups

The runtime GLB retains these 19 named mesh groups:

`BattleWorldGround`, `BattleMeadow`, `ArenaBase`, `ArenaTiles`, `ArenaBorders`,
`ArenaLaneLines`, `ArenaCrates`, `ArenaBarrels`, `BattleGrass`, `BattleRocks`,
`BattleFlowers`, `BattleRuinClusterLeft`, `BattleRuinClusterRight`,
`BattleDistantHills`, `BattleDistantRidges`, `BattleDistantTreeTrunks`,
`BattleDistantTreeCanopies`, `BattleDistantRuinLeft`, `BattleDistantRuinRight`.

Each group combines disposable copies of evaluated source meshes while keeping
surfaces separate by material. The source file is saved **before consolidation**,
so bevels, masonry, staves, rails, rivets, roots, and other individual parts stay
editable. Grass is thin, double-sided geometry rather than duplicated coplanar
faces or alpha textures.

## Detail Counts

The following `detail_counts` dictionary is present in the source scene,
manifest, environment asset entry, runtime statistics, and GLB root extras:

```json
{
  "grass": 112,
  "rocks": 18,
  "flowers": 16,
  "ruin_clusters": 2,
  "barrels": 2,
  "crates": 4,
  "distant_hills": 5,
  "distant_trees": 18,
  "distant_ruins": 2
}
```

Details include 22 curved blades per grass clump, rock moss, stems/leaves/petals,
beveled alternating tiles, tile hairlines and corner chronometer engravings,
segmented ruin masonry, fluted pillars, clock dials, fallen stones, separate
curved barrel staves, iron hoops/rivets, crate planks/diagonal braces/nails,
tree bark ridges, branches, exposed roots, layered canopies, and distant gates.

The field has **1,234 editable mesh parts**, plus 17 editable emblem mesh parts.
The runtime field has **69,284 triangles, 19 meshes, 53 material surfaces,
26 basic materials, and a 3,943,796-byte GLB**. It is below the 150,000-triangle
and 80-surface export budgets. Per-group breakdowns are in the manifest.
Materials use basic Principled base colors, metallic/roughness, and restrained
emission. There are no runtime procedural shaders, texture dependencies, or
optional glTF extensions.

## Rebuild and Validate

The generator always starts from an empty factory scene and fixes render threads
at four. It must run in a separate background process, not a live Blender MCP
session. Other batches may run concurrently because no files are shared.

```powershell
& "C:\Program Files (x86)\Steam\steamapps\common\Blender\blender.exe" `
  --background --factory-startup --threads 4 --python-exit-code 1 `
  --python tools/blender/build_environment_batch.py

& "C:\Program Files (x86)\Steam\steamapps\common\Blender\blender.exe" `
  --background --factory-startup --threads 4 --python-exit-code 1 `
  --python tools/blender/build_environment_batch.py -- --validate-only
```

Use `--review-only` to regenerate the small-icon QA sheet and refresh its
manifest evidence without changing or rerendering any runtime asset. Use
`--emblem-only` when intentionally revising the emblem: it loads the saved
original, rebuilds only the emblem parts, and preserves completed field,
background, and field-preview output bytes. It updates source hashes because
the emblem and field share the same editable source file.

Build validation checks instance counts, tile placement, editable source parts,
simple materials, actual exported GLB primitives/triangles, semantic names, and
transparent icon alpha. The second command opens the saved source in a fresh
Blender process and checks source/generator/runtime/preview hashes and image
dimensions. It then imports the GLB into another empty factory scene and checks
all 19 semantic names, root detail metadata, and the world-ground bounds.

Blender 5.2.2 LTS build, detached cold source reload, detached GLB import, and
16 / 32 / 64 / 256 px alpha/coverage checks passed. The actual backgrounds,
field previews, and emblem were visually inspected. The emblem uses a larger
front card, thick Q, and dark inset so the identity survives 16 px reduction;
there is no floor or baked solid background.

## Parent Integration

The aggregate manifest contains `assets` records with these collision-safe IDs:

| ID | Category | Visual ID |
| --- | --- | --- |
| `environment_field` | `environment` | `qq_battlefield` |
| `background_hub` | `background` | `hub` |
| `background_run_result` | `background` | `run_result` |
| `branding_queuequest_emblem_3d` | `branding` | `queuequest-emblem-3d` |

Each record includes `runtime_path`, `export_sha256`, `source_path`,
`source_sha256`, `presentation`, and reuse metadata. Image records also include
runtime `size`, actual `source_render_size`, and the high-resolution render hash.

The parent should cache/preload the GLB, instantiate it instead of the procedural
`_build_arena()` path, preserve the current fallback, and populate runtime detail
counts from the metadata/manifest. It should retain the existing sky/lights and
disable shadows on the merged grass/flowers/distant geometry if needed for Web
performance. Background and optional emblem UI use are parent integration work.

No source file in `art_src` or high-resolution intermediate should enter the PCK.
Godot import and live native/Web layout verification are separate integration
gates and are not implied by successful Blender authoring/export validation.
