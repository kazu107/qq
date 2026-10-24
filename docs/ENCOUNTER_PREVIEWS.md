# Enemy Intel and Encounter Series

Battle nodes open a modal with an animated enemy model, HP, attack, speed, active
slots and the actual enemy loadout. Card tooltips include enemy attack and
Infinite-mode grade/modifier scaling. Viewing or closing an unselected battle
node does not select the route. Confirming selects it and enters battle.

Hazard nodes retain their existing selected-facility flow and withdrawal option.
Enemy Intel opens automatically on entering the facility, including after each
intermediate reward. Closing it allows withdrawal; the Continue choice reopens
it. Rewards are still granted after each fight, not by the preview.

Generated normal nodes use one enemy on steps 1-14, two on 15-28, three on
29-42, and one more per subsequent 14-step block. This uses the absolute run
step, not the step within an Infinite cycle. The selected map enemy stays first;
later opponents cycle through the area's normal enemy pool. Elite and boss nodes
remain single encounters. To author a custom chain, add:

```json
"encounter_queue": ["scout", "guardian"]
```

`encounters_cleared` is the per-node completed-fight count (not the run's total).
The original `enemy_id` remains the fallback for old/single-enemy nodes. Hazards
retain `hazard_queue` and `hazard_cleared_waves` for save compatibility. The
`EncounterSeries` helper resolves both representations without migrating saves.

After intermediate normal-chain rewards, return to the same map step with Enemy
Intel already open. The toolbar's intel button reopens it after closing, allowing
loadout edits and suspension to Hub. The route advances only after the final
reward. Resume preserves the active node, queue, counter and pending rewards.
Final-step bosses finish the run only after their final encounter.

Scoring counts all configured battles in the route-efficiency denominator.
Infinite battle-result keys include a chain index; single-enemy legacy keys stay
unchanged. Step and node challenge awards remain once per node.

Infinite hazards keep their original two/three enemies in cycle one. From step
29 onward they grow every seven steps: 4 on 29-35, 5 on 36-42, 6 on 43-49,
and so on without resetting each cycle. Extend the existing area-specific enemy
pattern cyclically. Normal-mode hazards remain unchanged. Generated queues are
prepared with the map, so previews and planned battle weights see the full count
before entry. Per-wave reward metadata is filled on entry without replacing the
saved queue or counter.

Maps store `encounter_growth_version=1`. Old saves upgrade unstarted nodes once;
completed, active and explicitly queued encounters are preserved. Rewards,
cleared counters and authored queues are never reset by this migration.

Developer mode on the map offers normal/hazard chain fixtures with at least
two/three enemies, increasing to the current step's count when higher. They
replace an available node only when explicitly requested. Use the rewardless
route-advance action to inspect later steps and cycles.

Verification: `EncounterPreviewSmoke` covers cancellation, model/card display,
single and chained progression, hazard rewards, save/resume, stat/grade parity and
Infinite result deduplication. `tools/web_encounter_preview_review.mjs` exercises
the same modal using browser input at landscape and portrait viewport sizes.
`EncounterGrowthSmoke` covers growth boundaries, four-cycle deterministic maps,
legacy migrations, save/load, per-fight rewards and scoring. The corresponding
`tools/web_encounter_growth_review.mjs` exercises generated 2/3/4/5-enemy chains
with actual browser clicks in landscape and portrait layouts.
