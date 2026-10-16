# Infinite Scoring (Rules Version 1)

Infinite mode uses a persistent award ledger, not the capped Normal/Arena
percentage score. No ordinary S-E rank, survival score, loss penalty or gold/
healing/waiting-time score applies. Normal and Arena retain their existing rules.

| Award | Base Points | Unique Key |
| --- | ---: | --- |
| Completed step, including facilities | 1000 | Step index |
| Boss victory | 2000 | Node ID |
| Elite victory | 300 | Node ID |
| All hazard waves cleared | 500 | Node ID |
| Victory efficiency | 0-100 | Node ID and wave |

Each award is frozen after rounding `base * (1 + 0.25 * (cycle - 1))` to an
integer. First-cycle step/boss points total 36000; the second cycle adds 45000,
for 81000 before challenge and efficiency bonuses. There is no gameplay cap;
storage uses Godot's integer range.

Efficiency base points are `round(100 * clamp(2 - time / par, 0, 1))`. The par
is the existing enemy-specific Normal par multiplied by the shared Infinite
enemy HP multiplier, `1.25 + 0.18 * cycle`. This is an initial tuning rule, not
a calibrated balance guarantee. Zero-time results, defeats and forced hazard
withdrawals receive no efficiency points. Successfully cleared earlier hazard
waves retain their awards after withdrawing or losing a later wave.

## Lifecycle and Persistence

- New runs initialize an empty `RunState.infinite_score` ledger.
- Battle awards are recorded on the authoritative result; hazard waves are
  captured when the battle engine is set up, before advancing cleared-wave
  counters. Repeated callbacks are rejected by that context, not the legacy
  enemy/seed/time ID (which can coincide across legitimate waves). UI refreshes
  and replay viewing never award points.
- Step points are recorded before advancing the route/adding the next cycle.
  Hazard completion is checked from its saved queue/counter, not mere withdrawal.
- The ledger stores category totals and claimed award keys in the normal run
  save, including the hub's suspended-run slot. Past awards are never recomputed
  from current HP, gold, elapsed time or the number of generated future steps.
- Personal records live in `meta_progress.infinite_record`, tagged by score
  rules version. Finalization is idempotent and does not grant Normal rank
  achievements. Highest score and deepest reached step are tracked separately.
- Reached step is the next/current encounter (`completed + 1`); full cycles
  completed is `floor(completed / 28)`. Clearing step 28 reaches cycle 2, step 1.
- Same-seed retry starts a fresh Infinite ledger, retaining the account record.

## Legacy Saves and Testing

An older run initializes its ledger once from the saved completed-step count,
identified completed nodes and route-matched battle history. Old histories lack
node/wave IDs, so only ordered matches to known saved encounters earn efficiency
points. Unidentifiable/debug entries are not guessed. Later history edits and
newly appended cycles do not change these restored awards.

Developer result previews preserve an active run in its suspended slot and mark
the synthetic result `preview`; it never updates real personal records. Use the
developer Infinite Score Preview action and Finish Score Animation to inspect
the screen. The four animated bars share the total as a visual scale, showing
contribution rather than maximum attainable points.

`InfiniteScoreSmoke` covers cycle boundaries, exact 36000/81000 examples,
duplicate awards/callbacks, hazard waves, defeat/zero-time cases, unbounded
growth, JSON and suspended saves, legacy migration, records, preview exclusion,
result UI and same-seed retry. Existing `RunScoreSmoke` protects ordinary scores.
