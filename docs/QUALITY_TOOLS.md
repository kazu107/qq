# Quality tools (QQ-0.24.0)

## In-game entry points

- Enable developer mode in Settings. Every developer panel has **Network diagnostics** and **Automated battle lab**. The lab is unavailable during an active online session; diagnostics does not pause it.
- Save a named deck in the Map or Arena loadout panel, or the Hub's custom battle lab. Names are limited to 32 characters and 20 presets. Saving the same name replaces it; Delete removes the selected preset. Settings/save data persist the presets on desktop and in the browser.
- Applying a preset changes only equipped card IDs, never ownership, grades, gold, or relics. Missing copies and excessive effective loadout cost reject the entire operation. Relic discounts and permitted overage are included. Online application is an atomic host-validated `apply_deck` preparation action and is rejected after Ready or while rewards are pending.
- The Hub debug lab accepts presets up to its six slots. It does not grant that composition to a real run. Grades remain the independently selected debug grades.

## Automated battle lab

Choose a starter, an enemy and optionally a saved deck, then set the number of matches, seed and simulation-only duration cap. Enable A/B comparison to choose a second starter, enemy and deck. Both configurations receive the same seeded bot-phase sequence, and the final block reports win-rate and mean-duration deltas. The normal enemy AI, battle engine, relic/status rules and fatigue rules remain in use.

Each run uses a fresh clone. No progression, live loadout or rewards change. Results show wins, draws, unresolved battles, win/unresolved percentages, mean elapsed time (including capped samples) and aggregate direct card metrics. A capped sample has an empty winner and is **not** converted to a gameplay timeout verdict. These bot results are not estimates of human PvP win rates.

Work is budgeted to approximately 5 ms per render frame, with Cancel and progress updates. Replay last battle exports and opens the last completed simulation. The seed and loadout must match to reproduce a result; card data/version changes can change it.

## Analysis and replay

New local battle exports use replay format 2. The existing event inspector and retry path remain usable with older format 1 files. New exports contain 3D/timeline visual frames and support pause, 0.25/0.5/1/2x speed, scrubbing and next-resolution stepping (including fatigue). Scrubbing clears old effects and restores queued-card stances. Exact animation poses between two frame samples are not recorded video frames; effects are re-presented by the animation system.

Analysis counts resolved cards, actual HP removed (excluding overkill), shield absorption, shield granted and actual healing. These are **direct card effects**; subsequent status ticks or relic-triggered damage are not attributed to the initiating card. Fatigue counts and damage to both combatants are reported separately. Old event files use net snapshot differences instead.

Visual frames sample at 4 Hz and at card queue/resolution events. At 3,000 frames the recorder downsamples older frames while preserving the initial and latest states. The event stream is separate. Full per-card cooldown arrays are stored only in the initial visual frame; live card modifiers are retained. Visual frames are omitted from ordinary autosaves and all network packets. Replay files remain separate under `user://replays`.

Visual playback covers **local normal/arena battles, the automated lab and completed Web arena matches**. Web hosts retain 4 Hz visual frames in memory during the match. After resolution, the replay is compressed, split into bounded reliable chunks and exported separately on each viewer; visual frames are still excluded from live snapshots and ordinary saves. A replay that exceeds the 512-chunk/16 MiB safety limits is skipped rather than affecting the session.

Every normal battle now opens a result-analysis modal before progression. It compares direct damage, shield and healing totals and lists the six highest-impact cards. Web competitors see the same local-match report before the all-match result barrier; spectators go directly to the barrier.

## Practical tutorial

The Hub's **Battle Tutorial** opens an isolated battle that never changes run or meta progression. It uses the production engine, cards and timeline, and guides Quick Slash, Guard, Delay Step and an accelerated neutral Fatigue card. It can be repeated at any time outside an active network session.

## Network diagnostics and real browser tests

The diagnostic window shows FPS, existing ping, state, snapshot age, send/receive rates, rejected old snapshots and sequence gaps. Rates are a bounded five-second average of application snapshot bytes, not transport bandwidth or packet loss. A host's local snapshots are not counted as receive traffic. Sequence gaps can include reordering; a new match has its own sequence tracker.

Build the separate validation preset, then run the browser harness:

```powershell
New-Item -ItemType Directory -Force build/web-validation
& $Godot --headless --path . --export-debug "Web Validation" build/web-validation/index.html
node tools/web_multiplayer_e2e.mjs
```

The runner needs Playwright and installed Chrome. Set `QQ_NODE_MODULES` to an existing Node dependency directory containing Playwright, or provide Playwright in the local Node environment. It starts its own localhost signaling/static server and closes only its own browser contexts/server. The validation-only main scene is selected using the `qq_validation` export feature; production exports exclude `tests/*`. Never deploy `build/web-validation`.

The harness uses five isolated browser contexts: 2 players + spectator, then 4 players + spectator. It checks lobby/arena readiness, countdown, same-match guest reconnection, parallel match IDs and independent HP, fatigue simultaneous death, all-match result barrier, spectator exclusion from runs/standings, continuation and host-disconnect responsiveness. Reports go to `tools/.local/web-multiplayer/report.json`.

This is real localhost WebRTC, not an Internet/NAT/TURN test. A Web guest has 15 seconds to reconnect with its private token and receives the same signaling peer ID, payload, snapshot and countdown state. During a parallel round only that pairing pauses; timeout awards the opponent a forfeit. The host remains authoritative, so a host disconnect still closes the room and cannot restore the in-memory match without a dedicated server or host migration.

## Checks

`tools/test_quality.ps1` runs the related Godot smoke tests with a dedicated `tools/.local/quality-tests/appdata` profile, leaving the normal player save untouched. Run tests that call `Game.start_new_run` or `Game.start_arena_run` through this script rather than launching their scenes directly. `tools/QualityReview.tscn` captures native replay, analysis and lab screenshots while preserving the save. `npm test` covers signaling and R2 deployment/retention logic. Test logs and screenshots are local artifacts, not bundled game data.

`tools/BattleLoadProfile.tscn` prints scene load, construction and first-frame timings. Set `QQ_PROFILE_WARM=1` to measure after startup warmup. `tests/BattleStageCacheSmoke.tscn` verifies that one 3D stage is reused and disabled between battles. `tools/web_battle_load_review.mjs` captures first and repeated battle entry in the production Web build.

`tools/SceneLoadProfile.tscn` measures raw screen construction and content completion for the Hub, Run Setup, Map, Meta Progress, Card Library, Settings, and Arena. It deliberately instantiates fresh screens rather than using the router cache, so it is a cold-construction baseline. `tests/UiSceneCacheSmoke.tscn` follows real navigation to verify that completed Meta Progress and Card Library screens are reused, refresh on entry, and are invalidated when the language changes. Desktop prebuilds both screens on the boot loading screen; Web prebuilds only Meta Progress to avoid decoding every library card image at startup.

`tools/web_load_metrics_review.mjs` runs the production Web build locally, records actual boot and scene transition timings in `tools/.local/web-load-metrics/report.json`, and checks that Card Library starts with only the visible page before adding cards on scroll. The game's `window.qqLoadMetrics` array retains the most recent 128 metrics, including Godot object count. The browser report also samples page-memory estimates where supported; JS heap alone is not total WebAssembly/GPU memory. These measurements are local-browser timings, not public CDN/network timings. `tests/SafeSaveStoreSmoke.tscn` verifies backup rotation and recovery from damaged/interrupted files; `tests/LibraryLazySmoke.tscn` verifies incremental library rendering and filters. See `docs/SAVE_RECOVERY.md` for save behavior.

The scene profiler creates a temporary run, so run it only with an isolated save profile, for example PowerShell: `$env:APPDATA = Join-Path (Get-Location) 'tools/.local/quality-tests/appdata'; $env:QQ_PROFILE_ISOLATED = '1'` before launching the profile scene. It refuses to run without the guard variable.

QQ-0.24.0 validation covers eleven related Godot smoke tests, 16 Node tests, a direct tutorial-scene boot and the 2/4-player browser harness. External-network guest recovery, host migration, low-end/mobile devices and long-duration multiplayer soak tests remain separate checks.
