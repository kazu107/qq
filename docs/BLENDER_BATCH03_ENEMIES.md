# Blender batch 03: Guardian and main bosses

Five original, editable, rigid-skinned characters replace the procedural models and old portraits for:

| ID | Shared base | Distinct additions |
|---|---|---|
| guardian | Heavy armor, fortress helmet, tower shield, reactor | Hand cannon, rails, fortress vents |
| boss_timekeeper | Arcane robe, staff, orb, chrono back | Crown, clock dial, twelve hour marks, hand |
| boss_paradox_core | Mech armor, staff, orb | Crown, paired orbital rings, satellites, exposed containment core |
| boss_axiom_breaker | Assault armor, horns, greatsword, orb | Crown, segmented broken-law wings, judgment breastplate |
| boss_eternity_zero | Arcane robe, fortress head, orb | Crown, scythe, dark wing shards, bright zero halo |

Sources: `art_src/blender/characters/qq_enemies_03.blend` and its manifest. The existing `qq_starter_parts.blend` library is linked relatively and is not modified. The source retains individual editable meshes; only disposable export copies are merged.

Generator: `tools/blender/build_enemy_batch.py`. Run it in a **separate** background Blender with `--factory-startup --background --python`; it does not use MCP or modify an open interactive scene. It exports GLBs to `assets/models/battle`, matching 1024-square portraits to `assets/portraits`, and the lineup to `art_src/blender/previews/enemy_batch_03.png`.

Every character uses the established 18-bone hierarchy and animation sockets. Generator validation checks rigid vertex weights, finite clip poses, a 50,000-triangle upper bound, hashes, save state and cold reopening the blend. Godot's quality smoke additionally checks imported authored rigs and all 18 clips at four sample times for all five characters. The original starter/scout exports and library hashes remain unchanged.

Runtime model mappings are in `data/battle_visuals.json`; provenance is in `data/art_provenance.json`. When regenerating, refresh the matching model/portrait hashes in provenance from the new manifest. Startup model prewarming automatically picks up the additional mapped models.
