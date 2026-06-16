MyItemTracker
=============

Retail World of Warcraft addon to track item counts by item ID and show progress in a small popout frame, config window, and item tooltips.

Features
--------
- Track items by numeric item ID.
- Show current count, goal, notes, and known sources.
- Search tracked items in the config window.
- Add per-item goals and notes.
- Add tooltip lines for tracked items.
- Detect likely item sources from loot, vendor, quest, bag, and crafting events.

Slash Commands
--------------
- `/mit config` opens or closes the config window.
- `/mit show` opens or closes the popout tracker.
- `/mit add <id>` starts tracking an item.
- `/mit remove <id>` stops tracking an item.

Files
-----
- `MyItemTracker.toc` defines addon metadata and load order.
- `MyItemTracker.lua` contains the addon logic and UI.
- `MyItemTracker.xml` is intentionally minimal because the UI is built in Lua.

Development Checks
------------------
- `xmllint --noout MyItemTracker.xml`
- `luac -p MyItemTracker.lua`

If your Lua compiler is not on the terminal `PATH`, run the Lua syntax check from the compiler location or add it to `PATH`.
