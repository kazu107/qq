# Echo

QQ-0.52.0 adds `echo_cast`, a rare support card unlocked at 8 cumulative victories.
Arena, ranked shared pools and developer tools include it independently of meta unlocks.
Loadout cost 3, active slot 1. Grade 0-5 cast: 2.4/2.3/2.2/2.1/2.0/1.9 seconds;
recast: 22.4/21.4/20.4/19.4/18.4/17.4 seconds after the QQ-0.52.1 balance update
(originally 32/31/30/29/28/27). The charge count stays 1 at every grade.

## Resolution

- `repeat_next_card` grants charges, capped at 3 per unit/battle. Each charge repeats
  one eligible card twice; stacking grants more targets, not 4x/8x repetition.
- Consume at successful resolution, not registration. Existing casts qualify;
  interruptions preserve charges. Fatigue, auto instances and cards containing
  `repeat_next_card` or `reserve_next_card` are ineligible. Generated auto cards do not inherit repeats.
- Resolve effects twice immediately, in order. Rebuild current card modifiers for
  the second pulse so self-empowerment and target conditions are re-evaluated.
- Pay shield/other registration costs, slots, cast, cooldown and after-resolve
  card/relic hooks once. Damage/heal/shield/bleed/auto-queue card effects run twice.
- Snapshot and consume an attack multiplier once, applying it to both pulses.
  Finish a full pulse, then skip further pulses if either combatant is dead.
- One `resolve_card` event contains aggregate metrics and up to two pulse results.
  Network compaction retains only the pulse data needed for visuals. Visual replays
  preserve charges. 3D hits/numbers are spaced visually without delaying gameplay;
  the card SE plays once on authoritative resolution.

Timeline candidates use current charges and the real chronological/priority order,
separately per side. Hover-only ghosts do not reserve charges. Unit status icons
show remaining targets without a fake duration. Offline developer buttons add/clear
charges and are blocked in Web matches and ranked runs.

## Assets And Validation

`tools/blender/build_echo_card.py` runs in factory-startup background Blender.
It writes a dedicated Blend and high-resolution renders under `tools/.local`.
Downsample the card to 512x512 and transparent status icon to 96x96 using Pillow;
`node tools/finalize_echo_art.mjs` registers their hashes without replacing other assets.
The saved Blend and PNGs are committed; source geometry is excluded from the Web PCK.
The new card reuses the approved Sequence Loader sound through an explicit alias.

`EchoRepeatSmoke` covers costs, interruption, auto recursion, attack charge,
conditional damage, bleed, self-empowerment, hooks, snapshot/replay data, dynamic
timeline candidates and per-pulse visuals/audio. Ranked revision `infinite-8`
starts Season 5 without modifying past records.
