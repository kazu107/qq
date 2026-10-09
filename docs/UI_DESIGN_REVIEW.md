# UI Design Review - QQ-0.30.0

## Direction

Keep the established dark blue/gold visual language and the embedded Japanese font. Use larger page and section headings, restrained primary-action emphasis, readable muted text, and cached smooth background glows. The battle field, timeline, card meaning, and game rules remain unchanged.

## Changes

- Hub: existing SVG logo, explained mode tiles, distinct new/continue buttons, collection navigation, and a scrollable developer lab. Infinite Mode remains unlock-gated.
- Settings: centered audio/display sections, separate replay/developer tools, consistent footer actions. Saving and desktop/Web resolution behavior are unchanged.
- Card library: clear header, visible meta points, a combined rarity/type/search toolbar, matching count and empty-search notice. Search includes localized names, descriptions, effects, and tags. A short debounce, paged card creation, and scene/widget reuse avoid eager reconstruction.
- Meta progression: a compact records sidebar gives achievements more width. Names, descriptions, rewards, progress, and claim actions remain in their existing order. Missing tier descriptions fall back to the achievement description rather than an internal localization key.
- Tutorials: numbered two-column lesson grid with wrapped topics and clear start actions.
- Map/arena/facilities: stronger headings, clearer main actions, map-focused column proportions, and content-fitted choice windows with scrolling for longer lists.
- Web lobby: consistent background/inputs, a bounded connection window, room rules in three columns, participant height based on capacity, and fixed bottom actions.

## Validation

`UiPolishSmoke` checks English/Japanese achievement descriptions, added font glyphs, Hub/continued-run navigation, grouped settings, search/empty/clear states, and library widget reuse. Existing meta tests now explicitly load pages by scrolling and reacquire rows after filtering; they no longer assume that all cards are eagerly built or that filtered-out rows survive a rebuild.

Related scenes: `UiPolishSmoke`, `HubVersionSmoke`, `SettingsSmoke`, `LibraryLazySmoke`, `MetaProgressSmoke`, `MapFacilitySmoke`, `BattleTutorialSmoke`, `UiSceneCacheSmoke`, `SaveContinueSmoke`, `BattleStage3DSmoke`, `WebExportSmoke`, `LocalizationSmoke`.

`tools/web_layout_review.mjs` uses the production UI in an isolated test-only Web preset. Its default remains 14 screens x 6 window sizes. Additional Hub states are available through `QQ_LAYOUT_SCREENS=hub_continue,hub_developer,hub_infinite`; `QQ_LAYOUT_INTERACTIONS=1` additionally exercises real keyboard search and local Web room creation/capacity controls. Screenshots and JSON reports are generated under `tools/.local/web-layout-review`. Production exports exclude the test bridge.

Cached styles/background textures are shared. Card art, relic art, 3D models, persistent progression, and network protocol are not replaced by this UI pass. Small portrait browser windows still scale the desktop-oriented design rather than offering a separate phone-specific interface.
