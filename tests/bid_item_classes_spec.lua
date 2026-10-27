-- Lua 5.0: real item presentation helpers and XML handlers, including delayed
-- OnTextChanged, focus re-entry, pending queue switches and late item data.
local function read(path)
    local f = assert(io.open(path, "rb")); local text = f:read("*a"); f:close(); return text
end
local source = read("ADKP/Bidding.lua")
local first = assert(string.find(source, "function ADKP_Bid_UpdateItemDisplay(box)", 1, true))
local last = assert(string.find(source, "local function ADKP_Bid_ParseItems", first, true))
assert(loadstring(string.sub(source, first, last - 1)))()
local xml = read("ADKP/ADKP_Bid_Frame.xml")
local inputStart = assert(string.find(xml, '<EditBox name="$parentItem"', 1, true))
local inputEnd = assert(string.find(xml, '</EditBox>', inputStart, true))
local input = string.sub(xml, inputStart, inputEnd)
local function handler(event)
    local _, _, code = string.find(input, '<' .. event .. '>(.-)</' .. event .. '>')
    return assert(loadstring(assert(code)))
end
local textChanged = handler("OnTextChanged")
local focusGained = handler("OnEditFocusGained")
local focusLost = handler("OnEditFocusLost")

local function frame()
    return {
        shown = true, scripts = {},
        Show = function(self) self.shown = true end,
        Hide = function(self) self.shown = false end,
        IsShown = function(self) return self.shown end,
        SetScript = function(self, event, fn) self.scripts[event] = fn end,
    }
end
local displayed, displayName = "", ""
local value, focused = "", false
ADKP_BidFrame = frame()
ADKP_BidFrameItem = frame()
ADKP_BidFrameItem.GetText = function() return value end
local function fire(fn) this = ADKP_BidFrameItem; fn() end
ADKP_BidFrameItem.SetFocus = function() focused = true; fire(focusGained) end
ADKP_BidFrameItem.ClearFocus = function()
    if focused then focused = false; fire(focusLost) end
end
ADKP_BidFrameItemDisplay = frame()
ADKP_BidFrameItemDisplayText = {SetText = function(self, text) displayName = text end}
ADKP_BidFrameItemClassesText = {SetText = function(self, text) displayed = text end}
UIParent = {}
ITEM_CLASSES_ALLOWED = "职业: %s"
GetItemInfo = function() return nil end -- Name lookup is unavailable; preserve raw links.
local tokenA = "|cffa335ee|Hitem:123:0:0:0|h[破碎征服之冠]|h|r"
local tokenB = "|cffa335ee|Hitem:456:0:0:0|h[纳斯雷兹姆欺诈护胸]|h|r"
local classA = "职业: 战士, 牧师, 术士, 德鲁伊"
local classB = "职业: 圣骑士, 猎人, 盗贼, 萨满祭司, 法师"
local data = {
    ["123"] = {"破碎征服之冠", "拾取后绑定", classA},
    ["456"] = {"纳斯雷兹姆欺诈护胸", "拾取后绑定", classB},
    ["789"] = {"普通物品", "拾取后绑定"},
}
local lines, scanned, failures = {}, {}, 0
local function scan(item)
    table.insert(scanned, item)
    if failures > 0 then failures = failures - 1; error("item data not ready") end
    local _, _, id = string.find(item, "item:(%d+)")
    lines = assert(data[id], "unexpected item")
end
getglobal = function(name)
    local _, _, index = string.find(name, "^ADKP_BidItemClassTooltipTextLeft(%d+)$")
    if index then return {GetText = function() return lines[tonumber(index)] end} end
    return _G[name]
end
CreateFrame = function(kind, name)
    local f = frame(); _G[name] = f
    if kind == "GameTooltip" then
        f.SetOwner = function() end
        f.ClearLines = function() lines = {} end
        f.SetHyperlink = function(self, item) scan(item) end
        f.NumLines = function() return table.getn(lines) end
    end
    return f
end
local function tick(elapsed)
    local f = ADKP_BidItemRefreshFrame
    if f and f.shown then this = f; arg1 = elapsed or 0.11; f.scripts.OnUpdate() end
end
local function startItem(link, text)
    value = text or link
    ADKP_Bid_ShowItemDisplay()
    ADKP_Bid_RequestItemRefresh(link)
end
local function onlyDisplay()
    assert(not ADKP_BidFrameItem.shown and ADKP_BidFrameItemDisplay.shown, "input and display must not overlap")
end

-- Late OnTextChanged must not erase classes or lose a queue item's original link.
startItem(tokenA, "破碎征服之冠"); fire(textChanged)
assert(table.getn(scanned) == 0, "defer work until text events settle")
tick(); assert(displayed == classA); onlyDisplay()
assert(not ADKP_BidItemRefreshFrame.shown, "stop polling after a successful read")
fire(textChanged); assert(displayed == classA); tick(); assert(displayed == classA)
assert(scanned[table.getn(scanned)] == "item:123:0:0:0")

-- Editing and focus loss switch the actual widgets, not a covering texture.
ADKP_Bid_EditItem()
assert(ADKP_BidFrameItem.shown and not ADKP_BidFrameItemDisplay.shown and focused)
ADKP_BidFrameItem:ClearFocus(); onlyDisplay(); tick(); assert(displayed == classA)
ADKP_Bid_EditItem(); startItem(tokenB); onlyDisplay(); assert(not focused)
assert(value == tokenB, "read-only rendering must preserve the raw auction value")
assert(displayName == "|cffa335ee纳斯雷兹姆欺诈护胸|r")
fire(textChanged); tick(); assert(displayed == classB)

-- A newer queue item supersedes pending work for the previous one.
startItem(tokenA); startItem(tokenB); fire(textChanged)
tick(); assert(displayed == classB and scanned[table.getn(scanned)] == "item:456:0:0:0")

-- Retry briefly when data is unavailable, without needing a click/focus change.
failures = 1; startItem(tokenA); fire(textChanged)
tick(); assert(displayed == "" and ADKP_BidItemRefreshFrame.shown)
tick(0.31); assert(displayed == classA and not ADKP_BidItemRefreshFrame.shown)

-- No class restriction: clear the old item, then stop after a bounded number of attempts.
local count = table.getn(scanned)
startItem("item:789:0:0:0"); assert(displayed == "")
for i = 1, 10 do tick(0.31) end
assert(displayed == "" and not ADKP_BidItemRefreshFrame.shown)
assert(table.getn(scanned) == count + 4, "bounded retries")

-- Closed auction UI suspends scans; reopening schedules the latest value again.
startItem(tokenB); count = table.getn(scanned); ADKP_BidFrame:Hide(); tick()
assert(table.getn(scanned) == count and not ADKP_BidItemRefreshFrame.shown)
ADKP_BidFrame:Show(); ADKP_Bid_RequestItemRefresh(); tick(); assert(displayed == classB)

-- Match the actual loot slot and never operate on the loot itself.
GetNumLootItems = function() return 2 end
GetLootSlotLink = function(i) return i == 1 and tokenA or tokenB end
local usedLoot
ADKP_BidItemClassTooltip.SetLootItem = function(self, i) usedLoot = i; scan(GetLootSlotLink(i)) end
startItem(tokenB); tick(); assert(usedLoot == 2 and displayed == classB)
print("Bid item presentation PASS: exclusive input/display; deferred text events; raw links; queue switches; bounded retries; loot tooltips")
