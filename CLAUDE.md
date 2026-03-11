# Rules
- When the user indicates I'm looking at the wrong feature/path, stop and re-scope to the exact UI entrypoint before continuing.
- When moving or copying UI frames with existing Chinese text, preserve the original bytes and avoid re-encoding or escape sequences.
- When changing UI layout, verify the exact target elements by name in the XML before adjusting anchors to avoid moving the wrong controls.
- When implementing option-based filtering, use the same data source as the operation (not just UI fields) and fall back to saved settings when available.
- WoW 1.12 Lua 5.0 does not support the `#` length operator; use `table.getn(...)` instead.
- When changing UI layout, verify the exact target elements by name in the XML before adjusting anchors to avoid moving the wrong controls.
- QuickFloat “调” must behave exactly like `/dkp c` (single-target). Its right-click settings are `points`, optional `player` (fallback: current target), optional `reason` (fallback: 菜出天际-犯错); do not implement it as main/sub dual points.
