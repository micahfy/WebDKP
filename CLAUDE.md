# Rules
- When the user indicates I'm looking at the wrong feature/path, stop and re-scope to the exact UI entrypoint before continuing.
- When moving or copying UI frames with existing Chinese text, preserve the original bytes and avoid re-encoding or escape sequences.
- When changing UI layout, verify the exact target elements by name in the XML before adjusting anchors to avoid moving the wrong controls.
- When implementing option-based filtering, use the same data source as the operation (not just UI fields) and fall back to saved settings when available.
- WoW 1.12 Lua 5.0 does not support the `#` length operator; use `table.getn(...)` instead.
- QuickFloat “调” must behave exactly like `/dkp c` (single-target). Its right-click settings are `points`, optional `player` (fallback: current target), optional `reason` (fallback: 菜出天际-犯错); do not implement it as main/sub dual points.
- WoW 1.12 / Turtle WoW does not reliably execute `<Script file="..."/>` tags in XML to load external Lua files. Every Lua file must be explicitly listed in the .toc in the correct load order — all Lua dependencies must appear **before** any XML file whose OnLoad handlers call those functions.
- When a third-party addon (e.g. MinimapButtonBag / Bagshui) anchors a dropdown to `{FrameName}Left` and that region is missing from the button, create a 1×1 dummy texture and register it as a global via `setglobal("{FrameName}Left", tex)` in a Lua patch file that loads after the frame is created.
