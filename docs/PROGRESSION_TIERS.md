# Progression Tiers

Run length is controlled by `meta_progress.unlocked_step_tier`.

| Tier | Steps | Status | Unlock source |
| --- | --- | --- | --- |
| 1 | 1-7 | Implemented | Default |
| 2 | 8-14 | Implemented | Claim the Tier 1 S-rank achievement |
| 3 | 15-21 | Future | Use an `unlock_step_tier` reward with `tier: 3` |
| 4 | 22-28 | Future | Use an `unlock_step_tier` reward with `tier: 4` |
| Infinite | 29+ | Future | Use an `unlock_infinite_mode` reward after the Tier 4 S-rank achievement |

`MapGenerator.generate_run()` appends the implemented seven-step blocks for the unlocked tier. Rank achievement statistics use `rank_b_tier_N`, `rank_a_tier_N`, and `rank_s_tier_N`. S rank also advances the A and B statistics for the same tier.

The score remains normalized to 10,000 points regardless of run length. Progress distributes 4,200 points across all pre-boss steps and reserves 1,800 points for the final boss.
