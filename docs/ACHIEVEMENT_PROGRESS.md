# Achievement Progress (QQ-0.42.0)

The catalog contains 30 groups and 296 stages (previously 26 / 114). Twenty-two
existing groups gain 134 appended stages; four new groups contribute 48 stages.
Finite collection/route-depth groups retain their existing reachable maxima.
No old target, reward, legacy ID or claimed stage is reordered. Extension rewards
are Meta Points, not additional permanent attack/HP/slot upgrades. Rank groups
retain their four route-length gates, then track repeated 28-step clears.

## New groups

| Group | Targets | Unit |
| --- | --- | --- |
| Infinite score | 1k, 5k, 10k, 25k, 50k, 100k, 250k, 500k, 1m, 2.5m, 5m, 10m | Points across runs |
| Card delay | 10, 30, 60, 180, 600, 1800, 3600, 10000, 30000, 100000, 300000, 1000000 | Actual seconds |
| Card advance | Same as delay | Actual seconds |
| Interruptions | 1, 5, 15, 50, 100, 250, 500, 1000, 2500, 5000, 10000, 25000 | Successful cards |

## Counting rules

BattleAnalysis accumulates metrics separately for each canonical side, outside
the bounded event/log windows. Each affected card contributes its actual schedule
change. Advancing beyond NOW counts only the remaining cast time. Stop/reverse
count their added schedule time, and can include neutral fatigue cards. Relic
changes to already registered cards count; initial cast/grade/cooldown reductions
and ordinary clock passage do not. Unattributed debug shifts do not count.

Successful interruption events count once per removed active card. Failed
attempts and uninterruptible targets do not count. Lifetime battle metrics commit
at battle completion, including defeats. Tutorials, simulations and replays do not
commit to Game; viewing analytics is read-only.

The integer achievement store uses milliseconds for timeline durations, rounded
once per battle. UI progress converts these to seconds with one decimal place;
bars and thresholds retain the full millisecond value. Displayed current seconds
are truncated, not rounded up, so 9.999s never appears to have reached a 10s target.

Web results carry both sides' analytics. NetworkManager chooses the local side
using the authoritative result's peer IDs, not the currently watched side. Room
spectators and players viewing another pair receive no progress. Web match IDs
and random offline receipt IDs suppress duplicate completion delivery; the last
512 receipts are persisted to keep save size bounded. Metrics are not streamed
or saved every frame.

Infinite points commit after battle/step awards. A per-run credited-score watermark
prevents double credit on load, suspension, result reopening and defeat. A fresh
run, even with the same seed, earns independent points. Developer score previews
are excluded. An existing saved run can contribute its reconstructable score
once; unknown scores from older discarded runs and old delay/interruption totals
cannot be reconstructed and are not guessed from the high score.

## Save compatibility and testing

New stats default to zero. Explicit claim counts stay unchanged. Historical
completed-ID-only saves use each group's original legacy tier count, never the
expanded total. The four finite groups keep their old completion semantics.

Meta Progress developer actions add Infinite score +1000, delay +10s, advance
+10s and interruptions +1. `AchievementExpansionSmoke` covers all tier data,
threshold claims, old completion markers, actual shifts, stop/reverse, relic
interruptions, local Web result ownership, deduplication, persistence and UI.
