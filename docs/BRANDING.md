# QueueQuest identity

- `assets/branding/queuequest-logo.svg`: transparent horizontal logo, 900 x 240.
- `assets/branding/queuequest-mark.svg`: square application/browser icon, 256 x 256.

The gold Q card leads two blue cards toward the gold timeline marker. The wordmark uses ivory for Queue and gold for Quest. All lettering is vector geometry; the SVGs have no text/font dependencies, embedded bitmap images, scripts, or external resources.

Colors: ivory `#f4f2e9`, gold `#f5c66a`, cyan `#3ebbe5`, light cyan `#72d6f4`, navy `#0a1b28`. The horizontal logo is intended for a dark background. Keep its aspect ratio and allow clear space around it.

`tools/build_web.ps1` copies both SVGs to `build/web` so they can appear before the PCK loads. The copied assets are tracked for Heroku; update them by rebuilding after editing the source. The Godot project icon uses the square SVG, and the native Boot screen uses the horizontal SVG.

The public name is QueueQuest. The existing `QQ-MAJOR.MINOR.PATCH` version scheme remains in use. Desktop user data stays in the original `Godot/app_userdata/qq` directory (`godot/app_userdata/qq` on Linux); Web user data remains in the same IndexedDB filesystem.

The semantic `logo-*` group IDs also drive the loading animation. Regenerate the Web shell's inline SVG and native layers with `powershell -ExecutionPolicy Bypass -File tools/generate_loading_logo.ps1` after editing the artwork (the Web build also does this). Do not hand-edit generated layers or the SVG marker block. The original logo stays static outside the loading screen.
