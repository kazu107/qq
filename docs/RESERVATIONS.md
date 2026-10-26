# Card Reservations

QQ-0.53.0 adds 18 collectible cards (`reserve_*`). Existing card/relic numbers
are unchanged. Four common cards become initial unlocks; other cards unlock at
8/15/24/35 victories using the existing progression system. Arena pools ignore
meta unlocks as before. Existing frozen campaign pools are not rewritten.

## Rules

- Pending entries live on UnitState, not the run save. Each kind holds up to
  three targets, eight total entries per unit. One matching entry of each kind
  is consumed by a successful manual resolution. Conditions skip nonmatching
  cards. Existing casts qualify; interruption preserves resolution reservations.
- Setup cards (Echo and reservation grants), auto cards and fatigue are excluded.
  No reservation can recursively amplify its own grant or automatic chain.
- Registration reservations are checked before committing resources. Failed slot
  or shield checks preserve stock. A successful registration consumes stock even
  if interrupted later. Slot penalties stop at unit capacity to avoid hard locks.
- Damage additions apply before attack-charge multiplication; damage attenuation
  scales the complete hit. Shield/heal multipliers apply per effect. Status power
  and duration are added on application, including independently snapshotted bleed.
- Echo consumes stock once, using the same modifiers for both effect pulses.
  Lifesteal uses actual direct HP damage summed across pulses, not blocked damage.
  Post-card growth, delay, recoil, copy and Guard registration occur once.
- Post-trigger copy amounts are frozen before post-effects, so copying/healing
  cannot feed itself. Healing never revives a dead unit. Guard chains stop after
  the card's one automatic guard, and do not fire after either unit has died.
- From QQ-0.54.0, healing conditions include regeneration cards. Healing Corruption
  scales regeneration power at application. Mirror Intercept copies newly applied
  layers at its power ratio and the same duration; copied ticks do not retrigger
  reservations. The status booster extends regen duration, not its power.
- Recast is existing relic-adjusted duration times the reservation multiplier,
  then fixed reservation penalties, with the normal four-second floor. The
  formula is independent of application order. Growth/wear persist only for the
  current battle and use card-ID modifiers, including same-name copies.

## Content

| Kind | Target/Condition | Base Amount | Grade 5 |
| --- | --- | --- | --- |
| Focused Command | Own next attack | Damage +8 | +18 |
| Barrier Booster | Own next shield card | x1.5 | x2 |
| Siphon Load | Own next attack | 50% HP-damage lifesteal | 75% |
| Reload Reservation | Own next card | Recast x0.5 | x0.35 |
| Status Booster | Own next status card | +6s, bleed +2 | +11s, bleed +5 |
| Chain Command | After own next card | One automatic Guard | Same |
| Growth Mark | After own next attack/shield | Damage/shield +2 | +4 |
| Tempo Theft | After own next card | Delay opposing cards 1.5s | 2.5s |
| Weakening Tag | Opponent's next attack | Damage x0.6 | x0.35 |
| Shield Interference | Opponent's next shield card | Shield x0.5 | x0.25 |
| Healing Corruption | Opponent's next heal card | Heal x0.5; owner heals 4 | x0.25; 9 HP |
| Recast Jammer | Opponent's next card | Recast +6s | +11s |
| Recoil Tag | After opponent's next card | Fixed damage 6, normal shield/vulnerability | 16 |
| Time Mine | After opponent's next card | Delay its remaining cards 2s | 3s |
| Card Wear | After opponent's next card | Battle recast +1s | +2s |
| Mirror Intercept | Opponent's next shield/heal | Copy 50% of actual gains | 75% |
| Express Cast | Own next manual registration | Cast x0.5 | x0.35 |
| Slot Jammer | Opponent's next manual registration | Slots +1, capped | Same |

All grades have explicit effect values. Cast/recast profiles retain six entries;
Forge still caps persistent upgrades at 3. Balance Lab handles numeric ratios,
seconds, secondary values and fixed single-Guard counts with matching bounds.

## UI And QA

Positive/negative pending effects have separate count icons and full tooltips.
Timeline candidates follow actual side/priority order and display a badge plus
modified numbers. Delay/reverse can change the candidate without consuming stock.
Hover-only ghosts do not consume/reserve resolution stock. Registration previews
include cast/slot modifiers. Eight simultaneous status types fit the 3D plate.

Offline Developer Panel buttons cycle reservations onto either unit or clear both.
All 18 cards also work in the existing lab/debug picker at Grade 0-5. Developer
commands remain blocked in online/ranked battles. Assets and approved SE are
preloaded through the existing caches. Background Blender creates dedicated
original meshes, 18 square card renders and two transparent status icons without
using live MCP. Recreate with `tools/blender/build_reservation_cards.py`, then
`python tools/finalize_reservation_art.py`.

`ReservedCardsSmoke` covers all 18 grants, every grade, both sides' effects,
stack/cap/filter/interrupt behavior, combined Echo/attack charge, successful/failed
registration, slot hard-lock prevention, stable recast order, snapshots and UI.
`tools/web_reservation_review.mjs` exercises real clicks, dynamic candidates,
combined buffs/hexes, bilingual status hover, three viewport sizes and developer
controls. Ranked revision `infinite-11` starts Season 8 and preserves old results.
