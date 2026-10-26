# Damage Conversion

QQ-0.55.0 adds `life_conversion` (生命転換) and `barrier_conversion` (防壁転換).
Both are epic, loadout cost 4, one active slot, cast 1.2s and recast 30s. Their
four-second windows and four-second rearm delays are fixed across grades; only
the conversion ratio grows: 25/35/45/55/65/75% at Grade 0-5. Unlock both at 24
victories; Arena/debug catalogs include them independently of meta unlocks.

## Damage And Lifetime

- Intercept direct combat damage after attack/vulnerability calculation but before
  shield consumption. Prevent HP damage and shield damage entirely. Convert the
  incoming amount, not an overkill-capped or shield-absorbed amount.
- Bleed and its relic expiry damage retain their existing shield/vulnerability
  bypass rules, but can be converted. Recoil can also be converted. Fatigue is
  explicitly excluded at the user's request and still consumes shield normally.
  HP payments and map/event costs are state/resource changes, not damage.
- Keep fractional conversion inside the active window, so multiple small hits
  do not lose all benefit. Discard whole overheal; do not bank it. Never revive.
- Only one conversion mode is active. Same-mode reapplication preserves the
  better ratio and fractional remainder but never extends duration. Changing
  modes resets the fraction and retains at most the old remaining duration.
  Echo therefore cannot double the window or ratio.
- The window is half-open: damage exactly at expiry is not protected. Expiry or
  removal starts rearm; reapplication is rejected until it ends. Large status
  updates split at ticks/expiries so a bleed tick before expiry stays protected.
- Timeline stop/reverse does not pause the window, rearm or natural shield decay.
  New battles reset these transient states. The common conversion status is not
  an `apply_status`/direct-heal effect: status-duration reservations and mirror/
  healing-corruption reservations do not extend or copy reactive conversion.

## Statistics And Presentation

Track nullified damage separately from shield blocking and actual HP loss. Credit
only actual HP restored/shield gained to the conversion card, without extra casts.
Attackers receive no HP/shield damage or lifesteal credit for nullified hits.
Compact events retain prevention fields, statuses retain ratio/fraction/source,
and replay frames use the same transient state. Converted bleed shows positive
numbers only, not a false damage popup. Fully prevented attacks use block feedback.

Status icons show active mode/ratio and rearm timers in hover details. Offline
developer controls deploy either 50% field or clear both sides, with ranked/online
guards intact. The lab edits grade ratios and timings; duration is bounded by 8s
and rearm by 4-12s. Definitions keep 4s/4s. Forge remains capped at Grade 3.

Art is original background Blender output: `damage_conversion.blend`, generated
by `tools/blender/build_conversion_cards.py`, registered with
`python tools/finalize_conversion_art.py`. Previous artwork is unchanged.

`DamageConversionSmoke` validates all grades/both sides, fractional hits, cap,
expiry/rearm, mode switching, bleed timing, fatigue exclusion, recoil/relic damage,
Echo, statistics, compact snapshots, replays and blocked-hit visuals. Ranked
revision `infinite-13` opens Season 10 without modifying previous results.
