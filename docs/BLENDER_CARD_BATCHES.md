# Blender Card Completion: C01-C13

Completed and verified: 2026-10-10, Blender 5.2.2 LTS.

## Scope

- Owned ordinary cards: the 87 remaining IDs in `data/cards.json`.
- Additional special card: `environment_fatigue`, not inserted into the card database.
- Protected illustrations: `quick_slash`, `guard`, `delay_step`, `repair_burst`, `auto_turret`, `event_horizon`.
- Runtime path: `assets/icons/cards/<id>.png`, RGBA, 512 x 512.
- Source path: `art_src/blender/cards/<id>.blend`, individually editable scenes.
- Actual source render: 2048 x 2048 EEVEE, kept under `tools/.local/blender_card_batches/renders/`.
- Aggregate integration manifest: `art_src/blender/cards/card_batches.manifest.json`.

The existing action-scene and vertical-slice helpers are imported read-only.
No shared provenance, gameplay data, version files or tests are changed here.
The parent integration task owns provenance registration and fatigue's art-path switch.

## Art Direction

Each ID has an explicit subject/action/environment/framing recipe in
`tools/blender/card_asset_scenes.py`. These are actual modeled scenes, not
previous images pasted onto planes. No text is baked into the runtime art.

Subjects include held weapons, impacts, defensive deployment, damaged armor,
clock/rail manipulation, magazine loading, repair arms, drones, conversion
devices, phase gates and command formations. Backgrounds include ruins,
quarries, rain, citadels, forges, workshops, gardens, forests, deserts, archives,
reservoirs, ships, observatories, snow and cosmic spaces. Scenery is part of the
world, not a uniform presentation pedestal.

Materials use beveled steel, brass, ceramic, leather and controlled effect
emission. The editable sources retain individual panels, fasteners, teeth,
curved pipes, chamber ports, gauntlets, drone arms and environment meshes.
The manifest records the actual geometry count rather than claiming a fixed
polygon budget for every differently composed scene.

## Semantic Reuse Map

| Family | New ordinary cards | Shared parts | ID-specific action examples |
| --- | ---: | --- | --- |
| C01 | 11 | blade, greatsword, hammer, armored gauntlet, target plate | serrated bleed cut; polishing arm; hydraulic cleaver; three execution blades; recycling claw |
| C02 | 7 | blaster, cannon, precision sight, target plate | caught leg/tripwire; meteor impact; marking dart; shield-fed fortress cannon |
| C03 | 7 | buckler, kite/tower shield, hex field, reactor | wrist response; three-anchor barrier; reinforced gate; tracked wall; mirror slash; growing armor; cleansing prism |
| C04 | 11 | clock, gear, timeline track, directional energy | focus lens; purchase lever; dual flow switch; stasis dome; gate; reversed turbine; chain hook; eclipse; schedule-breaking hammer; ice lock |
| C05 | 5 | cartridge ports, loading cylinder, clock/gear, cell | fresh cartridge; circular return tube; multiple magazines; dual governors; manual crank |
| C06 | 5 | repair arm, armored hand, medical cross, cell | cleansing gate; two-hand patch; medical drone; phoenix repair feathers; emergency automaton |
| C07 | 5 | target plate, cell, pump, chain links | wound chain; red-to-green siphon; corrosion nozzle; double wound mark; blood moon rays |
| C08 | 5 | assembly arm, timeline track, drones, gear | blade dispatch; low-power rescue swarm; foundry exit; tactical reflection; self-returning gun |
| C09 | 7 | cells, reactor, pressure pipes, gears | adrenaline pair; piston ram; draining shield turbine; capacitor boot; heat leech; nested batteries; three-way quantum conversion |
| C10 | 4 | archive cartridges, blade, clock/gear, cell | infinity echoes; preservation casket; record-driven refinement; golden spiral/compass |
| C11 | 7 | phase gate, lance, bolt, clock, rail | gate penetration; null cascade; torn-space volley; courier zip; gravity anchor; singularity barrier; collapsing red/blue rails |
| C12 | 6 | solar core, ceramic armor, winged drone, shield | focused ray; descending judgment blade; citadel chamber; seraph formation; sanctuary; wound thorns |
| C13 | 7 | command frame, siege cannon, arsenal, drones | atlas frame; feedback furnace; twin sword/shield dispatch; lightning conductor; last fortress; two commanded knights; archive throne |
| Special | 1 | hourglass, clocks, ascending weights | neutral escalating fatigue threatens both sides |

Per-asset `semantic_reuse_map` includes the real card effects, shared part names,
family and unique action. Card gameplay numbers remain in their existing data;
the illustrations are not a replacement for dynamically rendered tooltips.

## Reproduction

System Python requires Pillow. Blender is launched in a separate background
process with `--factory-startup --python-exit-code 1 --threads 4`. Live Blender
MCP state is never used or changed.

```powershell
python tools/blender/build_card_batches.py --sample
python tools/blender/build_card_batches.py --preflight
python tools/blender/build_card_batches.py --require-complete
python tools/blender/build_card_batches.py --validate-only --require-complete
python tools/blender/build_card_batches.py --verify-sources --require-complete
```

The default batch size is 12, configurable from 10 through 16. To regenerate a
specific owned scene, use `--ids <id>`; `--force` renders even a valid entry.
The first-six ID set is refused for generation.

Resume skips only entries with matching card-definition, generator/dependency,
render-settings, editable-source, actual render and output SHA256 values.
Each completed image is downsampled with Pillow LANCZOS and atomically installed
before the next batch. An interrupted run preserves already completed assets.
An old pending manifest cannot be mistaken for a new forced render.

## Evidence And Integration

- Sample: `art_src/blender/cards/qa/sample_12.png`.
- Each batch: `art_src/blender/cards/qa/batch_*.png`.
- Complete 168px/74px sheets: `art_src/blender/cards/qa/all_cards_168.png` and `all_cards_74.png`.
- Dimensions, opacity, nonblank pixels, uniqueness, hash and source-size checks: `art_src/blender/cards/qa/validation.json`.
- Fresh background Blender source reopen, actual meshes/materials/camera, no font objects and no image-texture copying: `art_src/blender/cards/qa/source_reopen_validation.json`.
- All 88 scenes built before production: `art_src/blender/cards/qa/build_preflight.json`.
- Valid resume and rejected stale hashes/definitions: `art_src/blender/cards/qa/resume_validation.json`.

The integration manifest has `batch_id`, `generator`, `blender_version` and
`assets`. Every asset has `id`, `category=card`, `runtime_path`, `export_sha256`,
`source_path`, `source_sha256`, `presentation`, `size`, `source_render_size`,
generator/dependency hashes, render SHA256 and semantic reuse metadata.
All ordinary IDs are unchanged. The special fatigue entry uses
`id=environment_fatigue` and `assets/icons/cards/environment_fatigue.png`.

## Verified Completion

| Check | Result |
| --- | --- |
| Ordinary cards rendered/installed | 87 / 87 |
| Special fatigue illustration rendered/installed | 1 / 1 |
| Actual 2048px source renders | 88 / 88 |
| Editable sources independently reopened | 88 / 88 |
| PNG size/mode/opacity, nonblank, unique pixels and all hashes | passed, 0 errors |
| Second full run | 88 hash-valid skips, 0 renders |
| Negative resume checks | stale source/render/output/generator and changed definition rejected |
| Parent manifest normalizer | 88 entries accepted read-only |
| Protected first six | unchanged against both recorded SHA256 and Git HEAD blobs |
| Source files | 88 Blend files, 26.60 MiB total, largest 0.556 MiB |
| New runtime PNGs | 88 images, 20.52 MiB total |

All eight production sheets and the complete 74px sheet were visually reviewed.
The 12-image pilot was checked before production. Mesh-only vertex counts range
from 2,744 to 63,342 per source, with separate editable beveled curves and
7,425 named asset objects in total. These are modeled, lit scenes, not flat
texture substitutions. Card names, costs and numerical gameplay effects remain
in the existing UI rather than being baked into these illustrations.

Parent review owns native/web visual acceptance, provenance registration and
release. This card task does not commit or push, nor does it change shared data.
