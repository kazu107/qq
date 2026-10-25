# QQ-0.52.1 Balance

Submitted file: `queuequest-balance-1792926476-164938bd.json`.
Source: `QQ-0.52.0`, hash `a2f7118476ca4b284ce01fd4b646a8be9314589a2539bdd635e32cf976577680`.
All 87 original values and the source hash matched before publication. The exact
submission is retained in [`recast_balance_0_52_1.json`](../../tests/fixtures/recast_balance_0_52_1.json).

## Scope

- Set the base `recast_time` of each listed card to 70% of its previous value:
  84 collectible cards and all three Timekeeper-only cards.
- Exclude Quick Slash, Strike, Guard, Heavy Swing, Delay Step, Haste Focus,
  Weak Shot, Bleed Cut, Quick Guard and Reload, exactly as submitted.
- Preserve all other fields: cast, effects, grade profiles/overrides and relics.
  Grades 1-5 inherit the new base with their existing additive offsets, rather
  than multiplying each final grade value by 0.7. The four-second combat floor
  and Forge's persistent Grade 3 limit remain unchanged.
- Apply shared data to players, enemies, Arena, Web battles, library and lab.
  Existing saves use the new card definitions without changing their inventory.

Examples (raw seconds, before modifiers):

| Card | Base Before | Base After | Grade 5 After |
| --- | --- | --- | --- |
| Echo | 32 | 22.4 | 17.4 |
| Auto Turret | 26 | 18.2 | 18.2 |
| Clockwork Amplifier | 8 | 5.6 | 4 |
| Quick Slash (excluded) | 8 | 8 | 5.5 |

The Timekeeper's shorter cooldowns also affect how many amplifiers fit before
its long strike. The scripted six-second opening wait, eight-second final window
and 40-second strike cast are unchanged; its behavior tests cover the new cadence.
At Grade 0 without interference, four amplifiers now resolve before the strike
(x16 instead of x8). Delaying that strike by 12 seconds allows five (x32).

Ranked revision `infinite-9` starts Season 6, preserving all earlier records.
`RecastBalanceSmoke` validates the submission, exclusions, Grade 0-5 inheritance,
both sides' effective cards and actual resolved cooldowns. The earlier
`PublishedBalanceSmoke` still checks the first submission's unchanged fields.
