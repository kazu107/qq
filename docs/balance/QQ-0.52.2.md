# QQ-0.52.2 Balance

Submitted file: `queuequest-balance-1792932830-32b47f01.json`.
Source: `QQ-0.52.1`, hash `3710a019a6ca4813f89d28cab03e1e9a395c643a0b1dd22362294c4fff4cfd75`.
The source hash and all 46 original field values matched before publication.
The submission is retained in [`grade_balance_0_52_2.json`](../../tests/fixtures/grade_balance_0_52_2.json).

## Values

Raw seconds/amounts, before character, status or relic modifiers. Columns are Grade 0-5.

| Card | Field | Grade 0 / 1 / 2 / 3 / 4 / 5 |
| --- | --- | --- |
| Assault | Damage | 10 / 14 / 18 / 22 / 26 / 40 |
| Assault | Recast | 16.8 / 16.4 / 16 / 15.6 / 15.2 / 14.8 |
| Barrier Deploy | Cast | 9 / 8.9 / 8.8 / 6.8 / 6.25 / 5.85 |
| Barrier Deploy | Recast | 25.2 / 24.8 / 22 / 21.6 / 20.2 / 18.9 |
| Barrier Deploy | Shield | 18 / 24 / 26 / 28 / 31 / 34 |
| Bleed Cut | Bleed Power | 1 / 2 / 3 / 4 / 5 / 6 |
| Reload | Recast | 28 / 26 / 24 / 22 / 20 / 18 |
| Reload | Cooldown Reduction | 6 / 9 / 12 / 15 / 18 / 21 |
| Time Buy | Recast | 22.4 / 21.4 / 20.4 / 19.4 / 18.4 / 17.4 |

Only Reload's base recast and the 45 named upper-grade fields change. Preserve
all upgrade profiles and unspecified values, including Bleed Cut damage/duration
and Time Buy delay amounts. Store upper-grade values as explicit overrides, not
new shared profile deltas. All remaining 92 card definitions and relics stay unchanged.

Shared definitions apply to both players/enemies, including Arena/Web matches,
tooltips, library and lab. Forge stays capped at Grade 3; Grades 4/5 remain for
runtime effects and developer tests. Previous publication fixtures are immutable;
later explicit fields supersede only their matching earlier expectations.

Ranked revision `infinite-10` starts Season 7 without deleting previous records.
`GradeBalanceSmoke` checks all 46 fields, all 30 card/grade combinations, both
combatants' actual effects/cooldowns and the unchanged Forge cap.
