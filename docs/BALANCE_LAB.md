# Balance Lab

Open **Balance Lab** from the Developer Panel while outside battle and offline
from multiplayer. Production Web access retains the account developer allowlist.

## Editing

- Cards include collectible and boss cards. Relics include all 86 definitions.
- Search by localized name, ID or tag; filter rarity/type or changed entries.
- The editor has Base/+1/+2/+3/+4/+5 tabs. Base edits feed the shared starting
  definition; upper tabs edit the resolved numbers for that grade only. Unedited
  upper values inherit base/profile changes. Explicit grade values are serialized
  under `grade_overrides.<grade>.*` and applied after the profile calculation.
- Numeric typing updates previews immediately, including decimal input; Enter
  is not required. Incomplete/invalid intermediate text retains the prior value.
- The per-grade reset clears that grade's overrides (and migrated profile edits)
  without erasing other grades or the shared base.
- Compare the original/current card at the selected grade and inspect every
  grade's effect summary with the chosen attack/speed.
- Legacy relic constants are represented under `parameters.*`. Modern relics
  use their existing `effects.*` paths. The relic's original description is
  explicitly labeled; the numeric comparison below it is the edited source.
- Combat-connected relic fields are generated from the actual parameter
  consumers by `tools/generate_balance_catalog.mjs`. Overworld/structural or
  unconnected fields are marked **export only / fixed in battle tests**.
  In particular, one-shot limits, fixed grade sequences and map/shop effects are
  not generalized into new mechanics by this initial editor release.
- Bulk editing affects visible filtered entries only. It previews multiply/add/
  set operations, rounds integer fields and skips missing/out-of-range fields.
- The bulk dialog freezes that initial filtered scope. Uncheck individual icon
  rows to exclude them; include/exclude-all applies to the entire dialog scope.
  Its name/ID search only filters the displayed rows, never their selection.
  Incompatible fields are disabled. The preview shows only this operation's
  actual changes; existing edits on excluded items are preserved, not removed.
  Exclusions remain separate for cards/relics while the lab is open, including
  after Cancel, and are not numeric draft changes or part of exported JSON.

## Drafts And Export

Drafts autosave to `user://balance_lab_draft.json`, independently of SaveManager,
account profiles and cloud saves. An incompatible draft is copied aside before
new edits can overwrite it; a failed backup blocks autosave.

Export writes `user://balance_lab_exports/queuequest-balance-<time>.json` and
downloads it in Web browsers. Attach that file to request publication. It holds
stable IDs/paths, before/after values, source hash and game version. Importing an
incompatible or tampered document is rejected atomically by the draft model.
The editor does not rewrite `res://data`, source code or live save files.
The v2 diff format supports grade-specific overrides. Legacy v1 drafts can migrate
only when every original field value still matches; the original file is backed
up before migration. Other incompatible drafts remain preserved without applying.

## Sandbox

Choose a starter, enemy, base HP/attack/speed, uniform grade, mode/cycle, test deck
and relic set. Editing a card/relic adds it to the test set where capacity allows;
the add/remove button changes the set explicitly. Deck edits are for experiments
and do not enforce the campaign loadout budget. Card definitions change for both
sides; only the player's selected relics get relic overrides.

Manual battles use a separate engine, 3D field, timeline and clickable cards.
They start via the Start button or first card, do not complete a Game battle and
grant no rewards. A/B comparison freezes the starting draft, repeats identical
configurations/seeds/phases, budgets work over frames and supports cancellation.
Reports show bot win rate, unresolved runs, mean duration/damage/shield/healing.
These are bot estimates, not measured human balance.
Existing combat floors (including the minimum 4-second recast) still apply;
the editor changes base values, not these global rules. Sandbox-only safeguards
stop at 256 simultaneous auto instances or 256 resolutions in one update, marking
the test unresolved rather than allowing a zero-time infinite chain to freeze UI.

Overrides are per-engine. Published Database objects never change. Networked,
ranked replay and ordinary engine setup do not enable them. The Game completion
handler ignores sandbox-tagged results as an additional isolation barrier.
Permission revocation closes the lab/cancels tests.

The initial lab feature did not start a season because gameplay stayed unchanged.
The Grade 5 extension adds six-entry profiles for every card and a battle-only
`empower_card` stat `grade`/`tier`, capped at 5 and discarded after battle. Forge,
normal reward/event upgrades, automatic enemy scaling and network starting
profiles retain the persistent cap of 3. Grades 4/5 are available for lab/debug
tests and runtime effects, not new forge purchases. This gameplay revision starts
the next ranked season. When applying an exported gameplay change, follow `AGENTS.md`: review
the diff/source hash, update data/code and descriptions, run affected tests, bump
the internal RankedSession revision, publish once and start the next season.

The first published v2 submission is recorded in
[`balance/QQ-0.50.2.md`](balance/QQ-0.50.2.md). Its original source hash and all
91 requested edits are retained in `tests/fixtures/published_balance.json`.
`PublishedBalanceSmoke` checks every published value and all six grades on both
combatants against the lab baseline. Its `--validate-import` user argument is a
read-only, pre-publication check against the submitted source hash/original values;
it deliberately rejects that old-source submission once it has been published.

The second submission is recorded in [`balance/QQ-0.52.1.md`](balance/QQ-0.52.1.md).
Its 87 base-recast changes are retained separately in
`tests/fixtures/recast_balance_0_52_1.json`. `RecastBalanceSmoke --validate-import`
validates the source before publication; the normal smoke checks every new value,
the ten excluded cards, all grades on both combatants and resolved cooldowns.
