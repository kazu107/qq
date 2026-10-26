# HP Regeneration

QQ-0.54.0 adds eight cards and the positive `regen` status. Prior card/relic
numbers and original artwork remain unchanged; the previous 18 reservation
cards were already authored in Blender. New artwork has a separate Blender
source, generation script and provenance entries.

## Cards

Values below are Grade 0 before character/relic/battle modifiers. All eight
cards have explicit Grade 1-5 effects and six-entry timing profiles in cards.json.

| Card | Loadout | Cast | Recast | Effect |
| --- | --- | --- | --- | --- |
| ナノ再生 / Nano Regeneration | 2 | 2.4s | 18s | Regen 2 HP/3s for 12s |
| 応急ジェル / First Aid Gel | 2 | 2.4s | 18s | Heal 4, regen 1 HP/3s for 9s |
| 再生バリア / Regenerative Barrier | 3 | 4.8s | 24s | Shield 6, regen 2 HP/3s for 15s |
| 緊急ナノ修復 / Emergency Nanites | 3 | 2.4s | 22s | Regen 2 HP/3s for 12s; +2 power at HP <=40% |
| 吸血包帯 / Blood Wrap | 3 | 4.2s | 22s | Damage 6, regen 1 HP/3s for 12s |
| 集中再生 / Focused Renewal | 3 | 3s | 22s | Regen 5 HP/3s for 6s |
| 浄化の泉 / Cleansing Spring | 3 | 3.6s | 24s | Remove bleed, regen 2 HP/3s for 12s |
| 再生タンク / Regeneration Tank | 4 | 6s | 32s | Regen 1 + floor(maxHP * 1%) HP/3s for 24s |

The two common cards are initial unlocks. Barrier/Emergency unlock at 8 victories,
Blood Wrap/Spring at 15 and Burst/Tank at 24. Arena and developer lab retain
their full catalogs. Existing frozen campaign reward pools are not rewritten.

## Timing And Attribution

- A unit shares one three-second clock across at most three layers. Reapplication
  does not reset it; a fourth layer replaces the shortest remaining layer, ties
  replacing the oldest. Each layer retains its own power, duration and source card.
- Resolve a final tick exactly at a layer's expiry before removing it. Suspension
  retains active time after overshoot. Duration edits affect all layers.
- Low-HP and max-HP bonuses are fixed on application. Later attack/HP/status changes
  do not alter existing layers. Direct damage growth does not become regeneration;
  explicit healing modifiers do. Tick power is at least one HP.
- Mixed bleed/regeneration events resolve chronologically even for large updates.
  At the same boundary, bleed damage precedes healing. Dead units cannot heal or
  revive. Units without regen retain the existing status-event order.
- Attribute only actual healing, never overheal, to source cards. Proportionally
  distribute capped ticks across sources with deterministic remainder assignment.
  Tick credits add healing to analysis rows without adding card-use counts.
- Ticks do not interact with shield, consume reservations, trigger automatic card
  chains or consume next-attack multipliers. Timeline stop/reverse does not stop
  regeneration's clock. Battle preparation/tutorial engine pauses do stop it.

## Integration

Echo applies two independent layers (cap three). Healing Corruption scales the
new layer's power once and grants its normal one-time counter-heal. Mirror
Intercept copies only newly applied layers, with the same duration and scaled
power; copied layers cannot recursively copy themselves. Status Booster extends
duration but its bleed-power bonus does not affect regeneration.

3D status plates support nine status types, show layer count and remaining time,
and provide live next-tick/per-layer tooltips. Heal ticks use green floating
numbers and a restrained ring without resetting casting animation. Audio reuses
approved healing sounds at lower volume. Network snapshots and visual replays
retain layer source IDs, clock and duration. Startup caches preload the new art.

Offline Developer Panel can add three test layers or clear both sides; online
and ranked guards remain enforced. Balance Lab exposes regen power, duration,
low-HP thresholds/bonuses and max-HP ratio at each grade. Forge remains Grade 3.

Recreate images in a factory-startup background Blender using
`tools/blender/build_regeneration_cards.py`, then run
`python tools/finalize_regeneration_art.py`. Do not use the live MCP session.

`RegenerationSmoke` covers all grades/both sides, tick boundaries and partitioning,
mixed bleed/death ordering, cap/refresh, actual healing/statistics, conditional
snapshots, reservations/Echo, networking, replays and UI. Ranked revision
`infinite-12` starts Season 9 while preserving all previous records.
