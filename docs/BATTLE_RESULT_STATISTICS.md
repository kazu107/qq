# Battle Outcomes and Statistics

## Presentation

BattleScreen waits for BattleStage3D.battle_end_presentation_finished before
opening the outcome. The stage completes the final impact and then waits for
both terminal actor animations. It uses the actual clip duration, not a guessed
UI timer. A compact network snapshot missing the final event gets a synthetic
battle_end presentation; duplicate events are ignored.

The outcome contains only the outcome title and Details, Replay (when available),
and Continue buttons. Details is a separate, scrollable modal. Parallel Web
matches retain the existing all-matches-finished / all-players-acknowledged barrier
after Continue. Round updates cannot cover the collapse or the Details modal.

## Accounting

- HP damage dealt: effective HP removed by attacks, attributed bleed ticks, and
  attributed relic attacks. Statuses retain their latest applying engine side;
  self-inflicted or unattributed bleed is not credited as damage dealt.
- Shield damage dealt: shield absorbed by those attacks.
- HP damage taken: actual HP removed, including fatigue and bleed.
- Blocked damage: incoming damage absorbed by a shield, including fatigue.
- Shield gained: cumulative grants, not current shield or net changes.
- HP restored: effective healing, excluding overheal.
- Cards resolved: successful card resolutions.

Card bars group all copies and grades of the same card, by canonical engine side.
They show direct effects only, sorted descending, with each card's percentage of
that player's card total. Secondary status/relic effects and fatigue are not
assigned to cards. Shield decay and shield payment are not blocked damage.
Legacy replay totals can fall back to their recorded direct-card metrics.

HP is sampled every 0.5 seconds and at recorded combat events. Both initial and
terminal samples are retained. More than 1024 samples triggers adaptive
decimation. Analytics are attached to the final summary, not periodic network
snapshots. The HP chart shows seconds and HP; hovering displays the nearest
sample. Player-relative blue/red colors are consistent across the table and bars.

## Validation

BattleResultDetailsSmoke covers effective counters, overheal/overkill, shield
decay, bounded history/endpoints, PvE enemy IDs, network and replay round trips,
empty battles, graph selection, result/detail navigation, victory/defeat ordering,
and a guest whose final snapshot omitted battle_end. BattleStage3DSmoke,
BattleStageCacheSmoke, SpectatorBattleSmoke, ArenaTournamentSmoke, FatigueSmoke,
RelicExpansionSmoke, ReplayExportSmoke, QualityToolsSmoke, DeveloperModeSmoke,
and HazardFlowSmoke cover related regressions.

Developer mode adds Battle Details during local battles. Web clients receive
complete statistics only in the final result, so live developer inspection is
disabled there. Force Victory / Force Defeat
exercise the same collapse and outcome path instead of skipping straight to the
next screen. The test-only Web layout bridge can simulate a real battle and
inspect the result state. It is excluded from the production Web preset.

QQ-0.31.0 validation: 16 related native smoke scenes passed. The browser review
passed four viewport sizes, four contribution selectors, and navigation through
the result, details, and reward screens. WebRTC tests passed two- and four-player
rounds with a spectator, guest reconnection, parallel-match isolation, and final
analytics delivery (bounded HP history and both players' totals).
