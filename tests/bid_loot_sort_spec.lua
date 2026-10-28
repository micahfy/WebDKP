-- Lua 5.0: real tooltip reader, loot-button entry point and bounded batch sort.
local function read(path)
    local f = assert(io.open(path, "rb")); local s = f:read("*a"); f:close(); return s
end
local source = read("ADKP/Bidding.lua")
local a = assert(string.find(source, "function ADKP_Bid_UpdateItemDisplay(box)", 1, true))
local b = assert(string.find(source, "local function ADKP_Bid_ParseItems", a, true))
assert(loadstring("local ADKP_Bid_ActionRevision = 0\n" .. string.sub(source, a, b - 1) ..
    "\nfunction TEST_NewAction() ADKP_Bid_ActionRevision = ADKP_Bid_ActionRevision + 1 end"))()
source = read("ADKP/ADKP.lua")
a = assert(string.find(source, "function ADKP_StartBossLootBid()", 1, true))
b = assert(string.find(source, "-- ================================", a, true))
assert(loadstring(string.sub(source, a, b - 1)))()

local function link(id) return "|cffa335ee|Hitem:" .. id .. ":0:0:0|h[装备" .. id .. "]|h|r" end
local function idOf(item)
    local _, _, id = string.find(item, "item:(%d+)"); return tonumber(id)
end
local definitions = {
    [1] = {},
    [2] = {classes = "职业: 战士, 牧师, 术士, 德鲁伊"},
    [3] = {classes = "职业: 圣骑士, 猎人, 盗贼, 萨满祭司, 法师"},
    [4] = {classes = "Classes: Warrior, Rogue"},
    [5] = {classes = "職業：法師"},
    [6] = {},
    [7] = {classes = "职业：|cffff0000战士|r，牧师、术士, 德鲁伊"},
    [8] = {classes = "职业: 法师, 法师"},
    [9] = {classes = "Classes: Death Knight, Demon Hunter, Warrior"},
}
local loot, lines, scans, starts, notices, phase, now, disabled
UIParent = {}
ITEM_CLASSES_ALLOWED = "职业: %s"
GetItemInfo = function() return nil end
GetNumLootItems = function() return table.getn(loot) end
GetLootSlotLink = function(i) return link(loot[i].id) end
GetLootSlotInfo = function(i) return nil, "装备", 1, loot[i].quality or 4 end
ADKP_QuickBid_IsQualityEnabled = function(quality) return quality == 4 end
ADKP_IsAddonDisabled = function() return disabled end
ADKP_Bid_GetPhase = function() return phase end
ADKP_Bid_ShowUI = function() end
ADKP_Print = function(text) table.insert(notices, text) end
ADKP_Bid_StartBid = function(item, time)
    table.insert(starts, {id = idOf(item), time = time, at = now})
    TEST_NewAction(); phase = "bidding"
end
getglobal = function(name)
    local _, _, i = string.find(name, "ADKP_BidItemClassTooltipTextLeft(%d+)")
    if i then return {GetText = function() return lines[tonumber(i)] end} end
    return _G[name]
end
local function scan(id)
    scans[id] = (scans[id] or 0) + 1
    local data = definitions[id]
    if data.available and now < data.available then lines = {"装备"}; return end
    lines = {"装备", "拾取后绑定"}
    if data.classes then table.insert(lines, data.classes) end
end
CreateFrame = function(kind, name)
    local f = {scripts = {}, shown = true}
    function f:SetScript(event, fn) self.scripts[event] = fn end
    function f:Show() self.shown = true end
    function f:Hide() self.shown = false end
    if kind == "GameTooltip" then
        function f:SetOwner() end
        function f:ClearLines() lines = {} end
        function f:SetLootItem(i) scan(loot[i].id) end
        function f:SetHyperlink(item) scan(idOf(item)) end
        function f:NumLines() return table.getn(lines) end
    end
    if name then _G[name] = f end
    return f
end
local function reset(ids)
    loot, lines, scans, starts, notices = {}, {}, {}, {}, {}
    now, phase, disabled = 0, nil, false
    ADKP_BidQueue = {}
    for _, data in pairs(definitions) do data.available = nil end
    for i = 1, table.getn(ids) do loot[i] = {id = ids[i]} end
end
local function tick(dt)
    now = now + dt
    local f = ADKP_BidLootSortFrame
    if f and f.shown and f.scripts.OnUpdate then this = f; arg1 = dt; f.scripts.OnUpdate() end
end
local function expect(ids)
    assert(table.getn(starts) == 1, "exactly one auction starts")
    assert(starts[1].id == ids[1], "first item must already be sorted")
    assert(table.getn(ADKP_BidQueue) == table.getn(ids) - 1)
    for i = 1, table.getn(ADKP_BidQueue) do
        assert(idOf(ADKP_BidQueue[i].item) == ids[i + 1], "queue order mismatch at " .. i)
    end
    local f = ADKP_BidLootSortFrame
    assert(not f or not f.shown and not f.scripts.OnUpdate, "no polling after sorting")
end

-- Known loot, including unrestricted items, starts synchronously. Equal counts
-- preserve loot order; duplicate links share reads and retain separate entries.
reset({1, 2, 4, 3, 7, 6, 5, 8, 9, 3})
ADKP_StartBossLootBid()
expect({3, 3, 2, 7, 9, 4, 5, 8, 1, 6})
assert(starts[1].at == 0 and scans[3] == 1 and scans[1] == 1)
local line, ready = ADKP_Bid_ReadItemClasses(link(1))
assert(line == nil and ready, "unrestricted is distinguishable from missing data")

-- Existing quality filtering and empty-loot notices remain effective.
reset({3, 1, 2}); loot[1].quality = 2
ADKP_StartBossLootBid(); expect({2, 1}); assert(scans[3] == nil)
reset({1}); loot[1].quality = 2
ADKP_StartBossLootBid(); assert(table.getn(starts) == 0 and table.getn(notices) == 1)
reset({}); ADKP_StartBossLootBid(); assert(table.getn(notices) == 1)

-- Retry only missing data; the first completed round starts the sorted batch.
reset({1, 3, 2}); definitions[3].available = 0.15
ADKP_StartBossLootBid(); assert(table.getn(starts) == 0)
tick(0.1); assert(table.getn(starts) == 0)
tick(0.1); expect({3, 2, 1})
assert(starts[1].at == 0.2 and scans[1] == 1 and scans[2] == 1 and scans[3] == 3)

-- One shared deadline, not 0.3 seconds per item. Unknown items stay at the end
-- alongside unrestricted items in their original relative order.
reset({3, 1, 2, 4}); definitions[3].available = 10; definitions[4].available = 10
ADKP_StartBossLootBid(); tick(0.1); tick(0.1); tick(0.1001)
expect({2, 3, 1, 4}); assert(starts[1].at < 0.31)
local queue = ADKP_BidQueue
queue[1], queue[3] = queue[3], queue[1] -- manual order must not be changed later
tick(10); assert(ADKP_BidQueue == queue and idOf(queue[1].item) == 4)

-- Repeated clicks replace pending work; stale callbacks cannot start an old batch.
reset({3}); definitions[3].available = 10; ADKP_StartBossLootBid()
loot = {{id = 2}}; ADKP_StartBossLootBid(); expect({2}); tick(1)
assert(table.getn(starts) == 1)
reset({3}); definitions[3].available = 10; ADKP_StartBossLootBid()
TEST_NewAction(); tick(0.1); assert(table.getn(starts) == 0)
reset({3}); definitions[3].available = 10; ADKP_StartBossLootBid()
ADKP_BidQueue = {{item = link(4)}}; tick(0.1)
assert(table.getn(starts) == 0 and idOf(ADKP_BidQueue[1].item) == 4)
reset({3}); definitions[3].available = 10; ADKP_StartBossLootBid()
disabled = true; tick(0.1); assert(table.getn(starts) == 0)
reset({3}); phase = "transmog"; ADKP_StartBossLootBid()
assert(table.getn(starts) == 0 and next(scans) == nil)

-- Closing the loot window during the short wait can use the saved full link.
reset({3, 2}); definitions[3].available = 0.1
ADKP_StartBossLootBid(); loot = {}; tick(0.1); expect({3, 2})
print("Loot sort PASS: actual tooltip counts; stable descending order; no-class last; quality filter; immediate start; shared 0.3s deadline; duplicate reads; stale requests; manual order")
