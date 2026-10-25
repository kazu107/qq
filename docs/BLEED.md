# Layered Bleed

Implemented in QQ-0.51.0. Ranked revision `infinite-7` starts Season 4 and retains
all earlier seasons and their recorded results.

## Rules

- A unit shares one six-second bleed clock. Applying another layer does not reset it.
- Each card application snapshots `max(1, bleed_power + floor((attack + card_damage_bonus) * 0.25))`.
- Grade 0-5 power is `1 / 2 / 3 / 4 / 5 / 6` for Bleed Cut after QQ-0.52.2
  (originally `1 / 1 / 2 / 2 / 3 / 4`). Rupture Mark, Blood Moon Protocol and
  Crown of Thorns retain `1 / 1 / 2 / 2 / 3 / 4`. Durations/direct effects stay intact.
- Grade power comes from `effects[].bleed_power` plus `upgrade_profile.bleed_power`;
  grade overrides work as usual. The Balance Lab exposes the resulting numeric fields.
- Additive card damage modifiers count once; grade's separate direct damage growth,
  attack-charge multipliers, incoming vulnerability and direct-effect multipliers do not.
- Up to three layers retain their own duration, power and source. A fourth application
  replaces the shortest remaining layer; equal timers replace the oldest layer.
- Ticks sum all active layer powers into one HP-damage event, bypassing shield.
  A layer participates in a tick exactly at its expiry boundary before it disappears.
- The status expires naturally only when the last layer expires. Cleanse removes all
  layers without a natural-expiry proc. Partial duration consumption applies to each layer.
- Suspension freezes every layer and the clock; active time after a suspension ending
  within a large update is retained. Existing single-timer statuses migrate to one layer.

## Integration

- Bleed Pulsator triggers once per unit tick, not per layer.
- Critical Pathology Meter triggers only on the last layer's natural expiry, using
  the final combined power times its existing extra-tick parameter.
- Symptom Transfer Paper preserves layer powers and scales each remaining duration;
  one cleansed status still consumes one transfer allowance. Four Symptom Seal consumes
  duration from every layer. Quarantine Buffer preserves all deferred layers.
- Status dictionaries include the layers and shared clock in network snapshots and
  visual replays. Overkill attribution is proportional to each layer source's contribution.
  The wire envelope remains compatible; the content hash and relic resolver revision 2
  prevent old/new gameplay builds from sharing a room.
- Status tooltips show total power, next tick and individual layer timers. Badges show
  multiple layers in 2D and 3D. Card chips show damage per six seconds.
- Offline developer buttons apply test layers (2/4/6 power; 12/18/24 seconds) or clear
  them. These actions are blocked in Web matches and ranked runs.

`BleedReworkSmoke` covers boundaries/frame partitioning, all grades, snapshots,
modifier freezing, shields, cleansing, related relics, codec/replay round trips,
UI badges/tooltips and developer guards.
