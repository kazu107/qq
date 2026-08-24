# 3D Battle Animation

## Source of truth

`data/battle_animations.json` is the shared source for:

- Blender actions in `art_src/blender/battle_animation_library.blend`
- the generated `assets/models/battle/battle_animation_library.glb`
- runtime `Animation` resources built by `BattleAnimationCatalog`
- animation duration and release / impact / effect markers

The catalog currently defines 18 clips at 30 fps. Ready and attack clips select
guard, melee, ranged, heavy, or arcane variants from the equipped weapon and
offhand types.

## Runtime

`BattleActor3D` creates an `AnimationPlayer` and an `AnimationTree` state
machine. Every clip drives the same 18-bone paths, so procedural combatants and
authored GLB combatants use identical poses. Authored models continue to copy
the common skeleton pose, keeping local, Web, and spectator presentation equal.

Battle state remains authoritative and is never derived from animation time.
The animation markers only schedule presentation:

- `release`: projectile creation
- `impact`: target reaction, damage VFX, combat number, camera shake, card SE
- `effect`: heal, shield, or status VFX and combat number

If a marker is unavailable or an animation cannot finish, `BattleStage3D`
flushes the pending visual cue at the end of the event. Gameplay therefore
cannot stall because of a visual asset.

## Regeneration

Run Blender 5.2 LTS in background mode:

```powershell
& "C:\Program Files (x86)\Steam\steamapps\common\Blender\blender.exe" `
  --background `
  --python tools\blender\build_battle_animation_library.py
```

The generator writes a manifest containing the SHA-256 of
`data/battle_animations.json`. `BattleAnimationSystemSmoke` rejects stale
Blender or GLB outputs.

## Blender MCP coexistence

Blender MCP controls one connected GUI Blender process. Two tasks issuing MCP
commands to that same process can conflict through the active scene, selection,
mode, undo stack, or save target.

The animation generator does not use the MCP connection. It launches a separate
background process and writes only these dedicated outputs:

- `art_src/blender/battle_animation_library.blend`
- `assets/models/battle/battle_animation_library.glb`
- `assets/models/battle/battle_animation_library.manifest.json`

This can run while Blender MCP is working on a different Blend. Do not run two
background generators that write these same paths at the same time.

## Debugging

Enable developer mode and open **Animation Lab**. The lab provides:

- model, target, action, and camera selection
- pause and resume
- forward and backward one-frame stepping
- normalized-time scrubbing
- clip time, fps, and event-marker positions
- hand-forward pose validation

Automated coverage is provided by:

- `tests/BattleAnimationSystemSmoke.tscn`
- `tests/BattleAnimationLabSmoke.tscn`
- `tests/CommonBattleHumanoidSmoke.tscn`
- `tests/BattleStage3DSmoke.tscn`
- `tests/AuthoredBattleModelsSmoke.tscn`
