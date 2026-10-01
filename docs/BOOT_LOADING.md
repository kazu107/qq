# Startup loading

The Web shell stays above the game from data download through Godot preparation. Its loading panel shows overall progress, the current task, and downloaded megabytes while downloading. Progress combines 65% download and 35% preparation; preparation percentages are stage estimates, not measured time remaining. Late callbacks never move the bar backwards. Unknown transfer totals retain the last known progress and show a waiting message.

Both Web and desktop reserve 100% for the rendered Hub. `SceneRouter` removes its transition cover and waits for a rendered frame before finishing startup. After a short 180 ms completion hold, the loading screen fades out over 900 ms with the live Hub underneath. Input remains blocked by the overlay until it is removed. The Web version skips the hold and animation when the browser requests reduced motion.

Desktop Boot hands its loading controls to a temporary CanvasLayer owned by SceneRouter, so scene replacement cannot destroy the fading screen. The layer is freed after the tween. Ordinary scene transitions are unchanged.

Related verification: `tests/BootLoadingSmoke.tscn`, `tests/StartupCacheSmoke.tscn`, and `node tools/web_boot_loader_review.mjs`. Browser evidence includes download, preparation, mobile portrait/landscape, mid-fade Hub, completion, old-pack compatibility, and startup failures.
