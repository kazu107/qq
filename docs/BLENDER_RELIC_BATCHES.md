# Blender Relic Completion (R01-R11)

## Scope

This batch replaces the 82 remaining relic icons from `data/relics.json`.
The first-batch `iron_plating`, `auxiliary_core`, `chrono_shard`, and
`salvage_magnet` images and their sources are intentionally preserved.

No gameplay data, shared provenance registry, version, tests, or release files
are edited by this batch. The parent integration step owns those updates.

## Source and Output Contract

- Editable source: `art_src/blender/relics/<relic_id>.blend`.
- Runtime: `assets/icons/relics/<relic_id>.png`, 512 x 512 RGBA.
- Actual source render: 2048 x 2048 RGBA, Blender EEVEE, 32 samples.
- Source renders and render logs: `tools/.local/blender_relic_batches/`.
- No pedestal, floor, or backdrop geometry; the render film is transparent.
- Orthographic framing fits each complete assembly, including protruding parts,
  with a deliberately reserved transparent border.
- PNG publication uses a single Lanczos downsample from 2048 to 512.
- Relic names are not baked into runtime pictures.
- Each source file is separately editable and must remain below 100 MB.

The source objects carry `relic_id` custom properties. The scene carries the
actual gameplay name, description, and effects; its collection carries its kit
and component reuse mapping. Shape and mechanism are chosen per ID rather than
recolouring one common model.

## Semantic Kits

| Kit | New relics | Reused mechanisms and individual interpretation |
| --- | ---: | --- |
| R01 | 5 | Weapon bevels, bindings, armor fittings; heat-treated blade, thrust-assisted boot pair, torn war banner, spiked crown, reinforced rib cage |
| R02 | 12 | Insulated cells, copper coils, ports, reactor rings; opening barrier petals, shield matrix, phase window, recovery cooling, heat-to-card printer, source-memory circuits |
| R03 | 14 | Dial marks, gears, hands, clappers and rails; borrowing hands, distinct four-card sequence terminals, triple idle timer, return spring, reverse-pitch turbine, debt scroll |
| R04 | 5 | Lens/bezel and bearing fittings; three-axis speed gimbal, cracked rift compass, telescope, archive map assembly, red/blue overtake signal |
| R05 | 5 | Coins, seals and chain fittings; supply chest, hooked contract, tracking bounty drone, shield-spend fund coil, carried-round price tag |
| R06 | 7 | Ampoules, valves, repair pincers and pump fittings; repair nanites, pulse injector, artificial heart, pressure foam, armor flower, threshold pacemaker, bleed-to-time pulsator |
| R07 | 14 | Card contacts, rack rails and latches; harness, occupied-slot bell, empty-slot interest, fourth reserve, single-card sheath, interrupt reservation, isolated auto slot, Grade mechanisms |
| R08 | 5 | Shield faces, gauges and pressure fittings; absorption stop, natural-decay valve, zero-pressure trigger, ruptured insurance film, compression caliper |
| R09 | 5 | Status medallions and isolated cells; slow-charge coil, four-status stop seal, delayed quarantine, status-transfer paper, final-tick pathology meter |
| R10 | 4 | Card sockets and conversion fittings; solar imprint gear with two clocks, overcharge furnace/safety valve, blade-to-shield prism, balanced three-phase terminal |
| R11 | 6 | Counters, gauges and rescue fittings; seven-step validator, hazard wave pressure, one-HP rescue line, four-slot comeback wiring, paired win/loss key, 28-tooth wear wheel |

Every entry includes the current description/effect values and the exact reused
component list in the manifest. The recipes are in
`tools/blender/relic_asset_kits.py`; rendering, export, resume and validation
are in `tools/blender/build_relic_batches.py`.

## Integration Manifest

The authoritative aggregate is
`art_src/blender/relics/relic_completion.manifest.json`.

It uses `batch_id`, `generator`, `blender_version`, `assets`, `completed_count`,
and per-asset `id`, `category`, `runtime_path`, `export_sha256`, `source_path`,
`source_sha256`, `presentation`, `size`, and `source_render_size`. Per-ID
manifests mirror entries for independently inspecting one relic; integrations
must deduplicate them or consume only the authoritative aggregate.

Each entry additionally records generator/dependency SHA256 values, semantic
input SHA256, actual 2048px render SHA256, a material-independent evaluated
geometry SHA256, object/vertex/polygon counts, camera settings and alpha QA.
The four preserved images' original hashes are checked before and after builds.

Resume skips a relic only when its source, actual 2048px render, runtime PNG,
semantic input and generator/dependency hashes all match. Changing a recipe or
an output invalidates the relevant proof rather than silently counting it done.

## Commands

Run from the project root using Python with Pillow:

```powershell
python tools/blender/build_relic_batches.py --preview
python tools/blender/build_relic_batches.py --batch-size 12
python tools/blender/build_relic_batches.py --validate-only
```

The default Blender executable is the installed Steam Blender. Override it
with `--blender <absolute-path>` if needed. Each process is explicitly launched
with `--background --factory-startup --threads 4 --python-exit-code 1`.
No live Blender/MCP session is selected or modified.

## QA Gates and Current Status

Completed and locally verified on 2026-10-10: all 82 new relics have actual
2048px renders, published 512px PNGs, separately editable sources and SHA256
evidence. Including the four preserved first-batch relics, all 86 runtime
relic icons now have Blender-authored source artwork.

Measured new-batch totals: 14.29 MiB of compressed Blend sources, largest
individual source 235.17 KiB, 9.96 MiB of runtime PNGs. Minimum measured
transparent edge padding is 52px. All 82 geometry hashes and all 82 export
hashes are distinct.

The initial 12-item preview spans all 11 kits. Both 192px and actual 48px sheets
were visually inspected before rendering the remaining items in 12-item batches.
The 48px sheets show icons on both dark and pale surfaces; sheet backgrounds
are QA-only and are not part of runtime PNGs.

Automated validation checks exact 82-ID coverage, 512px RGBA dimensions,
transparent corners, at least 22px empty edge padding, sensible alpha coverage,
48px silhouette coverage, unique geometry/export hashes, every recorded file
hash, and the per-source Git file-size limit.

The final completion count and validation result are authoritative in the
aggregate manifest. Godot UI rendering, cache warmup, centralized provenance,
PCK and public Web deployment are separate parent-integration gates, not claims
made by this asset-only builder.

Validation was rerun successfully with `--validate-only`. A full resume then
reported `requested: 82, pending: 0`, proving that valid artwork is not rendered
again. A separate factory-startup Blender process reopened all 82 saved sources
and reverified their geometry hashes, object counts, semantic properties,
2048px EEVEE RGBA settings, four-thread configuration and absence of pedestal,
floor or backdrop geometry. Evidence is in `qa/source_reopen_validation.json`.

Preview evidence:

- `art_src/blender/relics/qa/preview_12_mechanisms_192px.png`
- `art_src/blender/relics/qa/preview_12_mechanisms_48px.png`

Final sheets and machine-readable validation are emitted only after all 82
renders pass. They are `qa/all_82_relics_192px.png`,
`qa/all_82_relics_48px.png`, and `qa/validation.json` in the source directory.
All batch 192px sheets and the complete 48px dark/light sheet were visually
inspected. Thin single-weapon silhouettes and the wide bounty drone naturally
use less of the square than bulky gauges; their overall forms remain distinct
at the real 48px preview size. Final in-game hover/tooltips remain an integration
check, not a substitute for this small-icon inspection.
