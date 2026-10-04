# Browser display sizing

Web keeps `canvas_items` scaling and uses the `expand` aspect override. The browser canvas fills its viewport, while Godot expands the virtual design area horizontally or vertically. The original 1920 x 1080 design area remains available, UI proportions stay uniform, and there are no engine letterbox/pillarbox bands. Desktop stretch and user-selected window resolutions are unchanged. Browser settings explicitly show automatic sizing.

The battle camera preserves the original 16:9 horizontal field of view when the display becomes taller. It widens the vertical field of view rather than cropping combatants and their world-space plates. Wider windows retain the original 40-degree vertical field of view. This also updates when the cached stage is resized or reused.

Validation uses the isolated `Web Layout Review` export preset, which runs production Boot/UI with a test-only inspection bridge. The bridge and driver are excluded from production exports. Build it with `powershell -ExecutionPolicy Bypass -File tools/build_web_layout_review.ps1`, then run `node tools/web_layout_review.mjs` with Playwright available (or `QQ_NODE_MODULES` set to the bundled modules). `QQ_LAYOUT_SCREENS=battle` limits a review to battle framing.

The review records visible controls, virtual/window/canvas bounds and world-space plate corners, resizes the same running browser, and captures PNGs under `tools/.local/web-layout-review`. Scrollable offscreen content is allowed. The test sizes are 1440x900, 1280x960, 1920x800, 1280x720, 960x600, and 900x1200. The native regression scene is `tests/ResponsiveDisplaySmoke.tscn`.
