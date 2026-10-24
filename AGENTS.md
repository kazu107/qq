# Ranked Infinite Seasons

- A season lasts until Infinite gameplay changes, not until a calendar month ends.
- When changing Infinite balance, scoring, enemy/encounter scaling, progression,
  player/card/relic effects or other ranked gameplay, increment the numeric suffix
  in both `RankedSession.RULESET` and `server/ranking/rules.json` together.
- The server closes the old season and starts the next numbered season once per
  new gameplay revision. Never reuse an old revision or modify past results.
- UI-only changes do not start a season. Do not add rule-version filters back.
- Update the game version and history, run relevant tests, export Web and push
  to `kazu107/qq` after verification, following `docs/VERSIONING.md`.
