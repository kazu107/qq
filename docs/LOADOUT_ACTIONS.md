# Loadout Actions - QQ-0.31.1

Equipped map/arena cards use a lazily created top-right close button. The callback
reads the card's current ID, so cached widgets and duplicate copies work correctly.
It removes one equipped copy without changing inventory ownership. The existing
one-card minimum remains in force. Web readiness/reconnection locks hide the close
buttons and also guard the callback.

Inventory rows contain equip and sell only. HoverActionReveal reserves the action
row dimensions and checks the current GUI hover target each frame. Child buttons
remain part of the same hover area; clipped, scrolled, obscured, unfocused, and
hidden rows are cleared without depending on a mouse_exited signal.

LoadoutHoverSmoke, MapFacilitySmoke, ArenaFlowSmoke, ArenaTournamentSmoke,
CardLayoutSmoke, UiPolishSmoke, UiSceneCacheSmoke, SaveContinueSmoke,
BattleResultDetailsSmoke, HubVersionSmoke, and LocalizationSmoke passed.
web_loadout_hover_review.mjs exercises real cursor motion, button jitter,
unequip/re-equip, frame dimensions, and scrolling in map and arena screens.

CardUiSmoke has a pre-existing failure at its hard-coded 120-pixel status-tooltip
height check (line 762). It also fails with the unchanged QQ-0.31.0 production PCK;
the status tooltip is outside this change. Baseline evidence is in
tools/.local/loadout-hover-tests/CardUiBaseline.log (local, not tracked).
