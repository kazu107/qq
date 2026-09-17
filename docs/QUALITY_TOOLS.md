# Quality tools (QQ-0.23.0)

## In-game entry points

- Enable developer mode in Settings. Every developer panel has **Network diagnostics** and **Automated battle lab**. The lab is unavailable during an active online session; diagnostics does not pause it.
- Save a named deck in the Map or Arena loadout panel, or the Hub's custom battle lab. Names are limited to 32 characters and 20 presets. Saving the same name replaces it; Delete removes the selected preset. Settings/save data persist the presets on desktop and in the browser.
- Applying a preset changes only equipped card IDs, never ownership, grades, gold, or relics. Missing copies and excessive effective loadout cost reject the entire operation. Relic discounts and permitted overage are included. Online application is an atomic host-validated `apply_deck` preparation action and is rejected after Ready or while rewards are pending.
- The Hub debug lab accepts presets up to its six slots. It does not grant that composition to a real run. Grades remain the independently selected debug grades.

## Automated battle lab

Choose a starter, an enemy and optionally a saved deck, then set the number of matches, seed and simulation-only duration cap. The player-side bot varies its initial thinking phase from the seeded RNG. The normal enemy AI, battle engine, relic/status rules and fatigue rules remain in use.

Each run uses a fresh clone. No progression, live loadout or rewards change. Results show wins, draws, unresolved battles, win/unresolved percentages, mean elapsed time (including capped samples) and aggregate direct card metrics. A capped sample has an empty winner and is **not** converted to a gameplay timeout verdict. These bot results are not estimates of human PvP win rates.

Work is budgeted to approximately 5 ms per render frame, with Cancel and progress updates. Replay last battle exports and opens the last completed simulation. The seed and loadout must match to reproduce a result; card data/version changes can change it.

## Analysis and replay

New local battle exports use replay format 2. The existing event inspector and retry path remain usable with older format 1 files. New exports contain 3D/timeline visual frames and support pause, 0.25/0.5/1/2x speed, scrubbing and next-resolution stepping (including fatigue). Scrubbing clears old effects and restores queued-card stances. Exact animation poses between two frame samples are not recorded video frames; effects are re-presented by the animation system.

Analysis counts resolved cards, actual HP removed (excluding overkill), shield absorption, shield granted and actual healing. These are **direct card effects**; subsequent status ticks or relic-triggered damage are not attributed to the initiating card. Fatigue counts and damage to both combatants are reported separately. Old event files use net snapshot differences instead.

Visual frames sample at 4 Hz and at card queue/resolution events. At 3,000 frames the recorder downsamples older frames while preserving the initial and latest states. The event stream is separate. Full per-card cooldown arrays are stored only in the initial visual frame; live card modifiers are retained. Visual frames are omitted from ordinary autosaves and all network packets. Replay files remain separate under `user://replays`.

Visual playback currently covers **local normal/arena battles and the automated lab**. Online matches retain compact final analysis but do not export a complete synchronized visual replay. No new online replay traffic or per-match visual frame buffers are introduced.

## Network diagnostics and real browser tests

The diagnostic window shows FPS, existing ping, state, snapshot age, send/receive rates, rejected old snapshots and sequence gaps. Rates are a bounded five-second average of application snapshot bytes, not transport bandwidth or packet loss. A host's local snapshots are not counted as receive traffic. Sequence gaps can include reordering; a new match has its own sequence tracker.

Build the separate validation preset, then run the browser harness:

```powershell
New-Item -ItemType Directory -Force build/web-validation
& $Godot --headless --path . --export-debug "Web Validation" build/web-validation/index.html
node tools/web_multiplayer_e2e.mjs
```

The runner needs Playwright and installed Chrome. Set `QQ_NODE_MODULES` to an existing Node dependency directory containing Playwright, or provide Playwright in the local Node environment. It starts its own localhost signaling/static server and closes only its own browser contexts/server. The validation-only main scene is selected using the `qq_validation` export feature; production exports exclude `tests/*`. Never deploy `build/web-validation`.

The harness uses five isolated browser contexts: 2 players + spectator, then 4 players + spectator. It checks lobby/arena readiness, countdown, parallel match IDs and independent HP, fatigue simultaneous death, all-match result barrier, spectator exclusion from runs/standings, continuation, host disconnect responsiveness, and joining a fresh room. Reports go to `tools/.local/web-multiplayer/report.json`.

This is real localhost WebRTC, not an Internet/NAT/TURN test. Web transport currently ends a session on host disconnect; LAN's old automatic reconnect routine does not apply. Do not describe a new-room rejoin as mid-match reconnection.

## Checks

`tools/test_quality.ps1` runs the related Godot smoke tests and restores the existing save file afterward. `tools/QualityReview.tscn` captures native replay, analysis and lab screenshots while preserving the save. `npm test` covers signaling and R2 deployment/retention logic. Test logs and screenshots are local artifacts, not bundled game data.

QQ-0.23.0 validation: eleven related Godot smoke tests, 15 Node tests, the 2/4-player browser harness, native rendered screens, and a production Web startup capture passed. Older network/replay smoke drivers still report resource-cleanup warnings at process exit; the new quality smoke disposes its engines and rigs. External-network conditions, low-end/mobile devices, and long-duration multiplayer soak tests remain separate checks.
