# Automatic Content Unlocks and Seals

## Rules

- Normal and Infinite runs use the account's unlocked pool, minus seals.
- Each battle victory awards one unlock XP, including Arena and Hazard waves.
  Losses, entering screens, loading saves, and claiming achievements award no XP.
- XP is cumulative and cannot be spent. Stages are granted automatically, with
  no claim button and no individual card/relic purchases.
- All common cards and Iron Plating / Reactive Barrier form the base pool.
- Ten stages unlock at 3, 8, 15, 24, 35, 48, 63, 80, 100, and 125 XP.
  Every collectible card and relic is assigned exactly once to the base or a
  stage. Boss-only cards are never included.
- Starter purchases and achievement rewards continue to use existing points.

## Seals

- Card & Relic Library provides both seal toggles in separate Cards/Relics tabs.
- Meta Progress retains achievements, starters and automatic unlock progress;
  it no longer builds a duplicate relic list.
- Only unlocked content can be sealed. Unsealing is always available.
- At most five cards and two relics may be sealed, also capped at 25 percent of
  each unlocked catalog (rounded down). At least twelve cards and two relics
  must remain. At least one card of every unlocked rarity must remain.
- Seals affect random acquisitions, not the starting deck or already held items.
- Battle rewards, rerolls, shops, events, and random relic grants share the same
  eligible IDs. Existing rarity weights and unowned-card preferences remain.
- Arena keeps the full common catalog for all accounts and ignores seals.
  Network Arena also remains independent of account unlocks.
- Limits and the unlock schedule live in `data/content_progression.json`.
  These are initial tuning values, not a claim of balanced win rates.

## Run Snapshots and Save Compatibility

- New runs store a `content_pool` snapshot in RunState. Account unlocks and
  seal changes only affect subsequent runs, including after suspend/resume.
- The snapshot includes version, mode, eligible card/relic IDs, and sealed IDs.
- Legacy active and suspended runs freeze their old unlocked pool before
  migration grants new content. Existing shop offers, event choices, held
  items, and reward options are not regenerated.
- Account migration preserves existing unlocked items, adds the common base,
  and grants stages corresponding to the existing `victories` statistic.
  That statistic already includes Arena wins; do not add `arena_victories`.
- Historical purchase costs were not saved. Migration grants a one-time
  current-catalog-cost credit for existing valid non-base unlocks and stores
  `legacy_unlock_credit` and `content_progression_version`. It is compensation,
  not reconstruction of actual purchase history. New profiles receive none.
- An omitted optional pool (`null`) means unrestricted. An explicit empty pool
  means no candidate. Rarity fallback never escapes the supplied pool.

## Implementation and Validation

- `MetaProgressService`: migration, XP, staged unlocks, and seal validation.
- `ContentPoolService`: shared candidate filtering and weighted card pools.
- `Game`: victory integration, run snapshots, and calls into random sources.
- `RunState`: snapshot persistence and typed round-trip normalization.
- `ContentProgressionSmoke`: catalog coverage, thresholds, migration/credit,
  random-source exclusion, empty pools, modes, save/resume, and UI toggles.
- `CardRelicLibrarySmoke`: tab switches, deferred relic pages, independent search
  and rarity/type filters, tooltips, locked states, seals and full catalog loading.
- Both catalog tabs reuse their rows across switching and cached scene visits;
  the Relics tab builds no item rows until first selected. Save IDs and the
  `library` scene hint are unchanged, so no save migration is required.
- `tools/web_card_relic_library_review.mjs` checks Japanese/English at three
  viewport sizes with real tab/filter/search input, tooltip hover, seal toggles,
  all 86 relics loaded by scrolling, and cache identity after scene revisits.
- `tools/test_quality.ps1`: regression suite, including the new smoke test.
- `tests/validate_project.ps1`: standard validation also runs the new smoke.
- `tools/web_content_progression_review.mjs`: nine Web viewport/XP layouts,
  pointer-operated seal toggles, viewport bounds, and runtime error checks.
  Use the `Web Layout Review` export, not the production build, for this driver.

Automatic stages prevent choosing only favorable individual unlocks, but do
not eliminate pool dilution or the incentive to retain an early account.
Strict account-independent comparisons would require a common-pool ruleset;
the existing Arena mode already uses such a pool. This change does not add a
ranked normal-run mode or claim to equalize all metaprogression bonuses.
