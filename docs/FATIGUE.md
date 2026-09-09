# Timeline Fatigue

Added in QQ-0.22.0. Applies to normal runs, hazards, solo arena, and each
host-authoritative Web arena battle independently.

## Rules

- Simulation time starts only after battle start. Waiting/countdowns/pause do
  not advance fatigue; slow mode slows its clock too.
- At 90 seconds, then every 10 seconds, queue an environment card with a
  5-second cast. First impact is therefore at 95 seconds without time effects.
- Base damage is 10 times the wave number: 10, 20, 30, ... with no gameplay cap.
  Each queued card retains its own damage; later waves grow even while earlier
  ones are stopped. Timing is based on battle time, not prior resolutions.
- Apply the same base damage to both units, using the normal incoming damage
  pipeline (including shields and vulnerability), without either unit's attack
  stat or offensive card/relic bonuses. Both damage applications and existing
  lethal-protection effects finish before checking victory. Simultaneous deaths
  produce a draw.
- Whole-timeline stop/reverse effects include environment cards. Effects limited
  to player/enemy-owned cards do not. Environment cards have no loadout, runtime
  cooldown, slot cost, or interruptible owner and are not collectible.
- No hard timeout, damage cap, or delay cap is imposed. Permanent whole-timeline
  control can still prevent resolution; ending every possible build is NOT
  guaranteed by this rule.

## Implementation

Tune `src/core/battle/FatigueRules.gd`: `START_TIME`, `INTERVAL`, `CAST_TIME`, and
`DAMAGE_STEP`. Keep localized explanations consistent when changing constants.
`RealtimeBattleEngine` owns wave scheduling and resolution. `BattleStateCodec`
carries the next queue time, wave count, per-card damage, and both HP/shield
deltas. Protocol 10 / snapshot 4 rejects incompatible older clients.

The timeline horizon stays fixed from battle setup, now including the 5-second
environment cast alongside both loadouts. Copper borders and an hourglass SVG
identify fatigue from either viewing side. Artwork is warmed at startup;
environment tooltip definitions have a bounded cache and stay outside Database.

## Testing

- `res://tests/FatigueSmoke.tscn`: start gate, scheduling, escalation, independent
  waves during stop, constant reverse movement, owner filters, attack exclusion,
  shields/vulnerability, simultaneous death, no timeout, debug command, compact
  JSON snapshot, guest timeline tooltip/art, cache stability, and both 3D effects.
- `res://tools/FatigueReview.tscn`: actual Battle screen captures to
  `build/fatigue_timeline.png`, `fatigue_tooltip.png`, and `fatigue_impact.png`.
- Developer Battle panel: queue the next fatigue in one simulation second.
  Does not skip the start gate or alter other timers. In Web games this is
  host-only, disabled for spectators, and changes only the host's current pair.

## Validation (2026-09-10)

- Passed FatigueSmoke, CardUiSmoke, LocalizationSmoke, StartupCacheSmoke,
  SpectatorBattleSmoke, BattleEngineSmoke, SpecialCardEffectsSmoke,
  LanMultiplayerSmoke (protocol/codec), WebMultiplayerSmoke, WebExportSmoke,
  BattleStage3DSmoke, and HubVersionSmoke.
- Headless editor import and Web release export passed. Native Battle screen
  captures and the local Chrome Web build show the environment card, timing,
  Japanese labels, and developer shortcut. Timeline centers now align with the
  rounded time labels, including during delay/reverse animation.
- The older BattleEngineSmoke, SpecialCardEffectsSmoke, and LanMultiplayerSmoke
  harnesses pass their assertions but report retained resources at process exit.
  FatigueSmoke disposes its engines and exits without those warnings.
- Separate simulated matches and compact JSON snapshots are covered. A live
  multi-browser WebRTC fatigue match has not been exercised in this change.
