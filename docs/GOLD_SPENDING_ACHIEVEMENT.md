# Lifetime Gold Spending

`big_spender` remains a single repeat-claim achievement in Meta Progress.
Thresholds are cumulative across runs and are never reset by a tier claim.

| Total Gold Spent | Meta Points |
| ---: | ---: |
| 25 | 1 |
| 100 | 2 |
| 300 | 3 |
| 750 | 5 |
| 1,500 | 6 |
| 3,000 | 8 |
| 6,000 | 10 |
| 10,000 | 12 |

- Count card/relic purchases, reward/shop rerolls, and paid facility/event choices.
- Count the actual gold paid, after discounts, not the base price or net balance
  after gold-granting relics/effects. Free actions add zero. Failed purchases,
  sales, gold rewards and starting gold do not increase or subtract progress.
- Normal, Infinite and solo Arena use the existing persistent account statistic.
  Web Arena records accepted local purchase/reroll receipts on each human client.
  Host simulations of guests/bots and preparation-state broadcasts do not count.
- Existing `gold_spent` is retained. Previously undercounted spending cannot be
  reconstructed from old balances, so this release does not invent retroactive totals.
- Keep the first four thresholds/rewards unchanged. `legacy_claim_tier_count: 4`
  prevents old completed saves from treating new tiers as already received.
- Developer Meta Progress adds a clearly marked +100 test action, not real spending.

Validation: `GoldSpendingSmoke` covers all thresholds, one-time tier rewards,
old-save claims with/without counters, gross payments and gold grants, solo/Web
receipts, persistence and the Japanese UI/developer action.

`tools/web_gold_spending_review.mjs` checks six Web layouts/claim states at
1440x900 and 960x600 with real pointer input. The network review uses the
separate Web Validation export and three isolated browser clients: host spending
22, guest spending 57 (including a 50-gold relic that grants 35 back), observer
zero. It also checks rejected repeat purchases and deferred local saves.
