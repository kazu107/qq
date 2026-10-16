# Enemy Intel and Encounter Series

Battle nodes open a modal with an animated enemy model, HP, attack, speed, active
slots and the actual enemy loadout. Card tooltips include enemy attack and
Infinite-mode grade/modifier scaling. Viewing or closing an unselected battle
node does not select the route. Confirming selects it and enters battle.

Hazard nodes retain their existing selected-facility flow and withdrawal option.
Enemy Intel opens automatically on entering the facility, including after each
intermediate reward. Closing it allows withdrawal; the Continue choice reopens
it. Rewards are still granted after each fight, not by the preview.

Normal, elite and boss nodes use one enemy by default. To configure a chain, add:

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

Developer mode on the map offers two-enemy normal and three-enemy hazard fixtures.
They replace an available node only when explicitly requested. Normal generated
maps are not rebalanced to chains in this release.

Verification: `EncounterPreviewSmoke` covers cancellation, model/card display,
single and chained progression, hazard rewards, save/resume, stat/grade parity and
Infinite result deduplication. `tools/web_encounter_preview_review.mjs` exercises
the same modal using browser input at landscape and portrait viewport sizes.
