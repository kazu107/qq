# Card layout

Updated: 2026-09-08 / QQ-0.20.3

`CardButton` uses three non-overlapping regions:

1. Above the artwork: effect chips only.
2. Square artwork: cost at the top-left, state/timing at the top-right,
   rarity/team border, and the cooldown mask. The cost overlaps the top edge
   slightly; cast time sits below the live state on medium and large cards.
3. Below the artwork: centered card name without a type icon.

`set_tile_size(Vector2(w, w))` specifies **artwork** size. The control's full
extent is `CardButton.get_tile_extent(Vector2(w, w))`; use that for absolute
placement and clipping regions. Containers receive the full extent through
`custom_minimum_size`. `get_art_rect()` reports the artwork's local rectangle.
The layout keeps the same height across ready, cooldown, casting, and preview
states so pooled controls never move neighboring cards when their state changes.

The information bands are part of the same button and ignore mouse input as
children. Hover, right-click tooltip switching, and card selection therefore
work over the whole tile. Cooldown shading remains restricted to the artwork.
Timeline hover previews still fade the entire tile, including its information.

All consumers (battle hands, timeline, loadouts, library, rewards, facilities,
starter selection, and Web arena) use the shared control. Battle hands and
starter cards scroll vertically when additional rows exceed their available
space. Facility choices reserve the full card height. Timeline layout uses the
full extent vertically and the unchanged artwork width along its time axis.

Run `res://tools/CardLayoutPreview.tscn` for the Japanese visual preview. Set
`QQ_CARD_LAYOUT_CAPTURE` to an absolute PNG path to capture and exit. The
committed preview is `art_src/blender/previews/card_layout_v2.png`.
Run `res://tests/CardLayoutSmoke.tscn` for square artwork, overlay separation,
stable state sizes, cooldown mask clipping, and the 74px through 180px sizes.
