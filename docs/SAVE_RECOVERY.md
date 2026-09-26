# Save safety and recovery

The game writes a complete `save.json.tmp`, verifies it, and only then replaces `save.json`. New saves include an integrity checksum; older saves without the checksum remain readable. Before replacement it retains three generations: `save.json.bak1` (newest), `save.json.bak2`, and `save.json.bak3`. If the main save is missing or invalid, startup tries a complete staged save, an interrupted replacement, then the backups in newest-first order. The Hub displays a one-time recovery notice. The additional checksum is backward-compatible with the existing save data.

Files live in Godot's `user://` directory. On Windows for the `qq` project this is normally `%APPDATA%\Godot\app_userdata\qq`. Web builds use the browser's site-specific persistent storage. Keep external copies before clearing browser site data, reinstalling, or moving between PCs.

Backups are created by **future** saves; they cannot restore data already overwritten before this feature was added. The test suite uses a separate `APPDATA` profile, and `SafeSaveStoreSmoke` uses a distinct test path even inside that profile. Do not run save-mutating smoke scenes directly against the normal player profile.
