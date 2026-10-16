# Permanent Stat Upgrades (QQ-0.44.0)

Meta Progress has four purchasable tracks, funded with Meta Points (not run gold).
Each purchase acquires one stage. Later stages cost more; there are no unlimited
levels. The data lives in `data/meta_stat_upgrades.json` and is loaded once by
Database. Existing Blender HP/attack/speed/equipped-card icons are reused.

| Track | Levels | Per level | Maximum purchased bonus | Costs per successive level | Total |
| --- | --- | --- | --- | --- | --- |
| Max HP | 10 | +5 | +50 | 2, 4, 7, 11, 16, 23, 32, 44, 60, 80 | 279 |
| Attack | 8 | +1 | +8 | 4, 8, 14, 22, 34, 50, 72, 100 | 304 |
| Speed | 8 | +1 | +8 | 3, 6, 10, 16, 24, 36, 52, 74 | 221 |
| Loadout cost cap | 5 | +1 | +5 | 6, 12, 22, 38, 60 | 138 |

All 31 stages cost 942 points. The cap track increases the total equip-cost limit;
it does not change individual card costs or active battle slots. Cost/bonus data
must use positive integers and exactly these four stat IDs.

## Persistence and application

`permanent_upgrade_levels` stores purchased stage counts. Old saves start these
counts at zero; points and existing `permanent_bonuses` from achievements are
preserved. Purchased bonuses are calculated from levels and added to achievement
bonuses on read. They are never folded into the old achievement-reward bucket.
This prevents an achievement claimed after a purchase from applying the purchased
bonus a second time. Saved levels are clamped to the configured track length.

Purchases validate the current price and available points, deduct once and request
a coalesced save. Invalid IDs, insufficient funds and maximum levels do not charge
anything. UI cards and progress bars update in place instead of rebuilding lists.

Effects apply only when starting a new Normal or Infinite run, together with the
existing achievement bonuses. Infinite's initial boost stacks once. An active or
suspended run keeps its stored stats; reopening or resuming never reapplies these
bonuses. Solo Arena and Web Arena are unaffected.

Developer mode provides +100 points for testing and a purchase-only reset/refund
using the configured prices. This does not reset achievement rewards. Ordinary
play has no refund button. Full meta reset clears purchased levels as well.

`MetaStatUpgradeSmoke` verifies every stage, pricing, maximum effects, failures,
legacy preservation, achievement stacking, save/load, suspended runs, mode
isolation and in-place UI updates. The browser review covers Japanese/English,
landscape/portrait, insufficient funds, maximum levels and real pointer purchases.
