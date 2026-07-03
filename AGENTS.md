# AGENTS.md

Workspace instructions for ZCode agents working on this repository.

## What this repo is

**ADKP** is a World of Warcraft addon (a fork/rebrand of WebDKP) that tracks and awards DKP (Dragon Kill Points) for guilds during raids. It targets **WoW 1.12 / Turtle WoW** (`## Interface: 11200`). The addon is written in **Lua 5.0** and uses the classic WoW XML UI framework.

The codebase still uses the `WebDKP_*` prefix for **SavedVariables** and most globals/functions, but the user-facing brand is **ADKP** (with the `ADKP_*` function prefix). Treat both prefixes as intentional.

## Layout

All source lives under `ADKP/`:

| File | Responsibility |
|------|----------------|
| `ADKP.toc` | Addon manifest. **Defines the Lua load order — every Lua file must be listed here explicitly** (see gotcha below). |
| `ADKP.lua` | Main entry point (~14k lines): init, event dispatch, addon-message sync, GUI handlers, player table, data import/export. |
| `Utility.lua` | Shared helper methods used across the addon. |
| `GroupFunctions.lua` | Raid/party roster handling. |
| `Awards.lua` | Awarding / deducting DKP. |
| `Bidding.lua` | Auction/bidding UI and logic, anonymous-auction handling, bid queue. |
| `Announcments.lua` | Raid/whisper announcements. |
| `WhisperDKP.lua` | Whisper-based DKP query response. |
| `AutoFill.lua` | Auto-fill of player data. |
| `KeepOnline.lua` | Anti-AFK / keep-online helper. |
| `ADKP_Help.lua` | Help / hover-tooltip text for the settings UI. |
| `ADKP_RaidBossData.lua` | Static boss data table. |
| `ADKP_LootList.lua` / `ADKP_SubSync.lua` | Loot list and substitute-member sync. |
| `ADKP_Frame.xml`, `ADKP_Bid_Frame.xml`, `ADKP_Award_Frame.xml` | UI frame definitions. |
| `Textures/MinimapButton.blp` | Minimap button texture. |

## Build / install / test

There is **no build step, package manager, or test suite**. The addon runs directly from source.

- To test in-game: copy the `ADKP/` folder into the WoW client's `Interface/AddOns/` directory and (re)load the UI. `DefaultState: disabled` in the `.toc` means the user must enable it at the character screen.
- "Verification" means: Lua syntax is valid (`end` balance is correct) and the `.toc` load order is consistent.

## Critical gotchas (read before editing Lua/XML)

These are the highest-impact failure modes in this codebase — most runtime bugs trace back to one of them.

1. **Every Lua file MUST be listed in `ADKP.toc` in the correct order.** WoW 1.12 / Turtle WoW does **not** reliably execute `<Script file="..."/>` tags inside XML to load external Lua files. Any Lua dependency must appear in the `.toc` **before** any XML file whose `OnLoad` handler calls into it. When you add a new `.lua` file, add it to the `.toc` too.
2. **A single Lua syntax error fails the entire file.** One orphan `end` at module level makes *every* function in that file nil. If you see a burst of "attempt to call global X (a nil value)" errors for functions from the same file on startup, suspect **one** syntax error, not missing definitions. Always check `end` balance before committing large Lua files (e.g. the 14k-line `ADKP.lua`).
3. **Lua 5.0 only.** Do **not** use the `#` length operator — use `table.getn(...)`. Avoid other Lua 5.1+ features.
4. **Don't re-encode Chinese text.** When moving/copying UI frames that contain existing Chinese (zhCN) strings, preserve the original bytes; don't introduce escape sequences or re-encode.
5. **Verify UI element names in the XML before touching anchors.** When adjusting layout, confirm the exact target element by name first to avoid moving the wrong control.

## Conventions

- **Function prefix:** new functions use the `ADKP_` prefix (e.g. `ADKP_OnLoad`, `ADKP_Bid_StartBid`). Older code and all SavedVariables use `WebDKP_` — leave those as-is.
- **SavedVariables** (declared in the `.toc`): `WebDKP_Options`, `WebDKP_Log`, `WebDKP_DkpTable`, `WebDKP_Tables`, `WebDKP_Loot`, `WebDKP_WebOptions`, `WebDKP_DailySubRecords`, `WebDKP_LootHistory`.
- **Numbers from UI text:** use `tonumber(...) or 0`, never a bare `+ 0` cast — UI text can be unrendered/blank and a bare cast will throw.
- **Anonymous auctions:** gate any detail-leaking broadcast (e.g. over-bid warnings to `RAID`) behind `if not ADKP_IsAnonymousAuction() then ... end`. Whisper-only channels are fine.
- **QuickFloat "调"** must behave exactly like the `/dkp c` single-target command. Its settings are `points` + optional `player` (fallback: current target) + optional `reason` (fallback: `菜出天际-犯错`). Do **not** implement it as main/sub dual points.
- **Option-based filtering** should read from the same data source as the operation (not just UI fields), falling back to saved settings when available.
- **Third-party addon compatibility:** if an addon (e.g. MinimapButtonBag / Bagshui) anchors a dropdown to `{FrameName}Left` and that region is missing, create a 1×1 dummy texture and register it globally via `setglobal("{FrameName}Left", tex)` in a Lua patch that loads after the frame is created.
- **Commit messages** are often in Chinese (e.g. `修复lua 数据文件`, `悬浮窗的说明`); match the surrounding style.

## Re-scoping rule

When the user says you're looking at the wrong feature/path, **stop and re-scope to the exact UI entrypoint** before continuing — don't keep going on the wrong frame/handler.

## Reference doc

`CLAUDE.md` (repo root) contains the same core gotchas; keep the two files consistent when you change these rules.
