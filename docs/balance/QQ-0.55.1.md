# QQ-0.55.1 Balance And Art

Submitted file: `queuequest-balance-1793011469-d28dfa2e.json`.
Source: QQ-0.55.0, hash `d145cace740ed73c810b7f88574f9c90e32ed99d70c68064d9ec1958117f2863`.
The source hash and all 94 before values matched prior to publication. Preserve
the submission in [`balance_0_55_1.json`](../../tests/fixtures/balance_0_55_1.json).

## Values

Raw seconds/effects, before character, status and relic modifiers. Lists are Grade 0-5.

| Card | Field | Values |
| --- | --- | --- |
| Bastion Drive | Recast | 16.8 / 16.4 / 16 / 15.6 / 15.2 / 14.8 |
| Bastion Drive | Shield | 11 / 16 / 21 / 26 / 31 / 36 |
| Blood Chain | Recast | 29.6 / 29 / 28.4 / 27.8 / 27.2 / 26.6 |
| Blood Chain | Conditional bonus | 12 / 15 / 18 / 21 / 24 / 27 |
| Execution | Recast | 36.2 / 35.4 / 34.6 / 33.8 / 33 / 32.2 |
| Execution | Base damage | 25 / 31 / 38 / 45 / 52 / 59 |
| Execution | Conditional bonus | 10 / 13 / 16 / 19 / 22 / 25 |
| Fortify | Recast | 36.2 / 35.8 / 35.4 / 35 / 34.6 / 34.2 |
| Fortify | Shield | 34 / 43 / 52 / 61 / 70 / 79 |
| Over Reload | Cooldown reduction | 6 / 6.8 / 7.6 / 8.4 / 9.2 / 10 |
| Repair Burst | Recast | 14 / 13.7 / 13.4 / 13.1 / 12.8 / 12.5 |
| Repair Burst | Heal and shield, each | 4 / 6 / 8 / 10 / 12 / 14 |
| Rupture Strike | Recast | 15.4 / 15 / 14.6 / 14.2 / 13.8 / 13.4 |
| Rupture Strike | Conditional bonus | 4 / 6 / 8 / 10 / 12 / 14 |
| Stasis Field | Recast | 19.6 / 19 / 18.4 / 17.8 / 17.2 / 16.6 |
| Time Flow Control | Recast | 38 / 37 / 36 / 35 / 34 / 33 |
| Tripwire | Damage | 3 / 5 / 7 / 9 / 11 / 13 |

Only submitted fields change. Preserve casts, profiles, unmentioned effects,
the other 112 card definitions and relics. Store explicit upper-grade numbers
in grade overrides. Forge stays Grade 3, battle-only grades Grade 5. Ranked
revision `infinite-14` starts Season 11 without modifying old results.

## Card Backgrounds

Replace flat backdrops for the 28 recent reservation/regeneration/conversion
cards with semantic environments. The shared module
`tools/blender/recent_card_environments.py` authors seven scene families:
training courtyards, fortresses, workshops, infirmaries, greenhouses, clock
archives and corrupted labs. Keep original foreground subjects and readable
silhouettes, with scenery behind them and no common display plinth.

Runtime art remains 512-square PNG; background geometry stays outside the PCK.
Preserve exact status-icon PNGs and transparency. Regenerate with the three
recent Blender generators using `-- --cards-only`, then run their finalizers
with `--cards-only`. Update source/dependency provenance without changing owners.
