# Blender-authored game art

## Static art vertical slice

`art_vertical_slice.blend` contains the first authored card, relic, status, and
UI vertical slice. The source collection names preserve category and data ID,
while `art_vertical_slice.manifest.json` records the renderer and source-render
hashes.

Regenerate the Blend, render all 12 source images at 1024x1024, import the
runtime sizes, and rebuild the three contact sheets with:

```powershell
.\tools\build_blender_art_vertical_slice.ps1 -RenderSize 1024
```

The batch currently owns these runtime assets:

- Cards: `quick_slash`, `guard`, `delay_step`, `repair_burst`, `auto_turret`, `event_horizon`
- Relics: `iron_plating`, `auxiliary_core`, `chrono_shard`, `salvage_magnet`
- Status: `bleed`
- UI: `attack`

High-resolution intermediates are written beneath
`tools/.local/blender_art_vertical_slice` and remain ignored. Godot receives
only 512px card/relic PNGs, the 96px status PNG, and the 64px UI PNG.

## Battle character sources

`battle_vertical_slice.blend` contains the authored Balanced and Scout vertical
slice. Godot does not import this directory because `art_src/.gdignore` keeps
editable source files and preview renders out of the runtime PCK.

The game loads these generated files:

- `assets/models/battle/balanced.glb`
- `assets/models/battle/scout.glb`

Regenerate the Blend source, preview, and both GLBs with Blender 5.2 LTS:

```powershell
& "C:\Program Files (x86)\Steam\steamapps\common\Blender\blender.exe" `
  --background `
  --python tools\blender\build_battle_vertical_slice.py
```

The script recreates the file from an empty scene and is the source of truth for
this vertical slice. It also writes `battle_vertical_slice.manifest.json` with
geometry counts and output hashes. Manual changes made only in the Blend or
generated GLBs are overwritten on the next run.

## Shared battle animations

`battle_animation_library.blend` contains the shared 18-bone clips used by the
runtime `AnimationPlayer` and `AnimationTree`. The source of truth is
`data/battle_animations.json`; the same definitions generate both the Blender
actions and Godot animation resources.

Generate the dedicated Blend and GLB without taking over the Blender MCP scene:

```powershell
& "C:\Program Files (x86)\Steam\steamapps\common\Blender\blender.exe" `
  --background `
  --python tools\blender\build_battle_animation_library.py
```

Because this launches a separate background Blender process and writes a
dedicated Blend file, it can run while Blender MCP is being used for another
scene. Do not run two generators that write the same output files concurrently.
