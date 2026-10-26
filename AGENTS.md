# Ranked Infinite Seasons

- A season lasts until Infinite gameplay changes, not until a calendar month ends.
- When changing Infinite balance, scoring, enemy/encounter scaling, progression,
  player/card/relic effects or other ranked gameplay, increment the numeric suffix
  in both `RankedSession.RULESET` and `server/ranking/rules.json` together.
- Ranking availability is persisted in `qq_ranked_control`. In `preparing`, do
  not create or transition seasons on page access, migrations, gameplay changes,
  worker runs or deployments. Only start a season after an explicit user request
  using the guarded maintenance command. Never automatically enable ranking.
- When ranking is active, the server closes the old season and starts the next
  numbered season once per new gameplay revision. Never reuse a gameplay revision.
- Preserve past results unless the user explicitly requests a reset. The
  2026-10-26 reset is authorized for ranking tables only: back up, verify the
  snapshot hash, reset numbering to Season 1 and leave ranking preparing. Never
  delete account, cloud-save or ordinary progress data with a ranking reset.
- UI-only changes do not start a season. Do not add rule-version filters back.
- Update the game version and history, run relevant tests, export Web and push
  to `kazu107/qq` after verification, following `docs/VERSIONING.md`.
