# Blender Batch 04: Remaining Enemies and Scout Portrait

This batch completes the enemy side of the character production plan. It owns
12 new enemy GLBs and 13 portraits, including a portrait rendered from the
**unchanged** existing `scout.glb`. It does not modify prior character sources,
the starter parts library, prior GLBs, or portraits outside these 13 IDs.

## Designs

| ID | Shared Parts | Distinct Additions |
| --- | --- | --- |
| brute | Heavy body, horned helmet, hammer | Exposed thick arms, welded patches, rust damage, exhaust power pack |
| disruptor | Arcane body, antenna, staff, orb, reactor | Asymmetric induction coil and interference dish, tall antenna, signal panel |
| raider | Assault body, horns, greatsword, thrusters | Second blade, wrapped shoulder, loot cartridges and satchel, armor scratches |
| medic_drone | Blaster, orb, shared forearms | Floating medical torso, optic head, three repair arms, ampoules, hover nozzles |
| chronoguard | Heavy body, halo, staff, buckler, chrono back | Clock-knight visor, twelve-hour dial shield, ring shoulders |
| phase_stalker | Light body, horns, thrusters | Segmented black plates, luminous phase gaps, swept horns, paired hooked claws |
| void_bastion | Heavy body, fortress head, tower shield, reactor | Integrated wall shoulders, hollow void core, shield cracks, supported cannon |
| echo_revenant | Arcane body, horns, orb | Exposed ribs, torn cloak panels, echo rings, back spikes, crescent scythe |
| rift_predator | Light body | Beast skull, projecting jaw and fangs, hock armor, rift fins, claws and second blade |
| entropy_colossus | Heavy body, fortress head, hammer, tower shield, reactor | Boulder shoulders, crumbling slabs, magma seams, heat vents |
| omega_seraph | Arcane body, halo, orb | Six separate mechanical wings, gold spars, white ceramic chest, ceremonial spear |
| grave_architect | Arcane body, antenna, orb | Shoulder mausoleums, tomb inlays, drafting projector, back spires, survey scythe |
| scout | Existing first-batch GLB | Matching portrait only; no export or model modification |

## Sources and Reproduction

- Generator: `tools/blender/build_enemy_batch_04.py`.
- Editable source: `art_src/blender/characters/qq_enemies_04.blend`.
- Manifest: `art_src/blender/characters/qq_enemies_04.manifest.json`.
- Read-only relative dependency: `art_src/blender/library/qq_starter_parts.blend`.
- Models: `assets/models/battle/{id}.glb` for the 12 new IDs.
- Portraits: `assets/portraits/{id}.png` for all 13 IDs, 1024 x 1024.
- Three full-body previews: `art_src/blender/previews/enemy_batch_04_lineup_{1,2,3}.png`.

Run in a **separate background Blender**, not an interactive MCP session:

```powershell
$Blender = 'C:/Program Files (x86)/Steam/steamapps/common/Blender/blender.exe'
& $Blender --background --factory-startup --threads 4 --python-exit-code 1 --python tools/blender/build_enemy_batch_04.py
& $Blender --background --factory-startup --threads 4 art_src/blender/characters/qq_enemies_04.blend --python-exit-code 1 --python tools/blender/build_enemy_batch_04.py -- --validate
```

The default is a 2048-square EEVEE portrait render, downsampled to 1024. The
high-resolution intermediate images stay in ignored `tools/.local/enemy_batch_04`.
The saved source keeps separate editable component meshes and relative links.
Only disposable export assemblies are merged into one rigid-skinned mesh.
Every new model has 18 established bones and five named bone-parented sockets.
The ordinary-enemy triangle limit is 35,000, stricter than the 50,000 ceiling.

The manifest includes generator/source/library/dependency SHA-256 values,
all output hashes, completeness, mesh statistics, the animation catalog hash,
and a snapshot of protected previous character assets.

## Validation and Integration

The generator checks rigid skin weights, finite vertices, bone hierarchy,
all keyframes in all 18 shared clips, geometry budgets, PNG size and protected
asset hashes. It saves and reopens the source, then performs a cold validation.
A second fresh Blender process repeats this validation without rebuilding.

`tests/EnemyBatch04Smoke.tscn` loads the actual imported GLBs into `BattleActor3D`,
checks all 13 actors, 18 clips at four sample times, all five runtime sockets,
matching portraits, preserved assets and authored-model cache reuse. Local
profile overrides make this test usable before shared profile registration.

The parent integration step must add the 12 `model_scene` mappings to
`data/battle_visuals.json` and register the 12 models + 13 portraits in
`data/art_provenance.json` using this manifest. Neither shared file is edited
by this batch, and no commit/push or public Web release is performed here.
