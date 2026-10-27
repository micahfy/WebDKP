-- Lua 5.0: exercise the real queue renderer, async reader and queue actions.
local file = assert(io.open("ADKP/Bidding.lua", "rb"))
local source = file:read("*a"); file:close()
local function part(first, last)
    local a = assert(string.find(source, first, 1, true))
    local b = assert(string.find(source, last, a, true))
    return string.sub(source, a, b - 1)
end
assert(loadstring(part("function ADKP_Bid_UpdateItemDisplay(box)", "local function ADKP_Bid_ParseItems") ..
    part("ADKP_BidQueueWindow = nil", "function ADKP_Bid_ReauctionItem")))()

local function call(f, event, argument)
    local previous, previousArg = this, arg1
    this, arg1 = f, argument
    if f.scripts[event] then f.scripts[event]() end
    this, arg1 = previous, previousArg
end
local function widget(parent)
    local f = {parent = parent, shown = true, scripts = {}, text = ""}
    function f:SetWidth(value) self.width = value end
    function f:SetHeight(value) self.height = value end
    function f:SetPoint(point, relative, relativePoint, x, y) self.x, self.y = x, y end
    function f:ClearAllPoints() self.x, self.y = nil, nil end
    function f:SetAllPoints() end
    function f:SetBackdrop() end
    function f:SetBackdropColor() end
    function f:SetTexture() end
    function f:SetJustifyH() end
    function f:SetJustifyV() end
    function f:SetNonSpaceWrap() end
    function f:SetText(value) self.text = value end
    function f:GetText() return self.text end
    function f:SetScript(event, fn) self.scripts[event] = fn end
    function f:Show() self.shown = true end
    function f:Hide() self.shown = false; call(self, "OnHide") end
    function f:IsVisible() return self.shown end
    function f:IsShown() return self.shown end
    function f:GetParent() return self.parent end
    function f:EnableMouse() end
    function f:RegisterForClicks() end
    function f:CreateFontString() return widget(self) end
    function f:CreateTexture() return widget(self) end
    return f
end
local classA = "职业: 战士, 牧师, 术士, 德鲁伊"
local classB = "职业: 圣骑士, 猎人, 盗贼, 萨满祭司, 法师"
local function link(id) return "|cffa335ee|Hitem:" .. id .. ":0:0:0|h[装备" .. id .. "]|h|r" end
local lines, scans = {}, {}
local ready = true
GetItemInfo = function() return nil end
getglobal = function(name)
    local _, _, i = string.find(name, "ADKP_BidItemClassTooltipTextLeft(%d+)")
    if i then return {GetText = function() return lines[tonumber(i)] end} end
    return _G[name]
end
CreateFrame = function(kind, name, parent, template)
    local f = widget(parent)
    if name then _G[name] = f end
    if kind == "GameTooltip" then
        function f:SetOwner() end
        function f:ClearLines() lines = {} end
        function f:NumLines() return table.getn(lines) end
        function f:SetHyperlink(item)
            scans[item] = (scans[item] or 0) + 1
            local _, _, id = string.find(item, "item:(%d+)")
            local class = ready and (id == "1" and classA or id == "2" and classB)
            lines = {"装备", "拾取后绑定"}
            if class then table.insert(lines, class) end
        end
    elseif template == "FauxScrollFrameTemplate" then
        local bar = widget(f)
        function bar:SetValue(value)
            self.value = value
            f.offset = math.floor(value / 84)
            ADKP_UpdateBidQueueWindow() -- native value changes may re-enter refresh
        end
        _G[name .. "ScrollBar"] = bar
    end
    return f
end
FauxScrollFrame_GetOffset = function(f) return f.offset or 0 end
FauxScrollFrame_Update = function(f, count, visible, height)
    f.count, f.visible, f.rowHeight = count, visible, height
end
FauxScrollFrame_OnVerticalScroll = function(height, update)
    this.offset = math.floor(arg1 / height); update()
end
UIParent = widget()
ADKP_BidFrame = widget()
ADKP_BidFrameItem = widget()
ADKP_BidFrameItem:SetText("当前物品名称")
ADKP_BidFrameItemClassesText = widget()
ADKP_Bid_RequestItemRefresh(link(1))
ADKP_BidFrameItemClassesText:SetText("主窗口信息")
ADKP_BidQueue = {}
for i = 1, 14 do ADKP_BidQueue[i] = {item = link(i == 1 and 2 or i + 1), time = 0} end
local f = ADKP_CreateBidQueueWindow()
local function tick(n)
    for i = 1, n or 100 do
        if f.shown and f.scripts.OnUpdate then call(f, "OnUpdate", 0.11) end
    end
end
ADKP_UpdateBidQueueWindow()
assert(f.width == 210 and f.height == 284 and f.scroll.visible == 4 and table.getn(f.rows) == 4)
assert(f.rows[1].number.text == "2." and f.rows[4].number.text == "5.")
assert(f.rows[1].classes.text == "", "reading must be deferred")
tick()
assert(f.curClasses.text == classA and f.rows[1].classes.text == classB)
assert(f.rows[2].classes.text == "" and not f.scripts.OnUpdate)
assert(f.height == 374 and f.rows[1].row.height == 84 and f.rows[2].row.height == 42)
assert(f.scroll.height == 210, "scrollbar follows the actual visible row heights")
assert(ADKP_BidFrameItemClassesText.text == "主窗口信息", "queue must not modify main class label")
assert(scans["item:1:0:0:0"] == 1 and scans["item:3:0:0:0"] == 4)
for i = 1, 4 do
    local r = f.rows[i]
    assert(-r.row.y + r.row.height <= f.height - 36, "rows must stay above footer")
    if r.classes.shown then
        assert(-r.classes.y + r.classes.height < -r.up.y, "classes and buttons must not overlap")
        assert(-r.classes.y + r.classes.height <= r.row.height, "class text must stay in row")
    else
        assert(r.row.height == 42 and r.up.y == -23, "collapse missing classes and raise buttons")
    end
    assert(r.text.x + r.text.width <= r.row.width and r.cancel.x + r.cancel.width <= r.row.width)
    if i > 1 then
        local previous = f.rows[i - 1].row
        assert(-r.row.y == -previous.y + previous.height, "no gaps between variable-height rows")
    end
end

-- Rebinding after reordering clears old classes; cached positives do not rescan.
ADKP_BidQueue_Down(1)
assert(f.rows[1].classes.text == "" and f.rows[2].classes.text == classB)
assert(f.rows[1].row.height == 42 and f.rows[2].row.height == 84)
tick(); assert(scans["item:2:0:0:0"] == 1)

-- Scroll beyond the old 10-row limit, and buttons use the absolute queue index.
call(f.scroll, "OnVerticalScroll", 10 * 84)
assert(f.rows[1].number.text == "12." and f.rows[4].number.text == "15.")
local removed = ADKP_BidQueue[14]
call(f.rows[4].cancel, "OnClick")
assert(table.getn(ADKP_BidQueue) == 13 and ADKP_BidQueue[13] ~= removed)
assert(f.scroll.offset == 9 and ADKP_BidQueueScrollScrollBar.value == 756)
assert(f.rows[4].number.text == "14.")

-- New jobs replace old jobs, even if a scan was waiting on unavailable data.
ready = false
f.classCache = {}
ADKP_BidQueue = {{item = link(2)}, {item = link(3)}}
ADKP_UpdateBidQueueWindow(); tick(1)
ADKP_BidQueue_Cancel(1); ready = true; tick()
assert(f.rows[1].classes.text == "" and f.curClasses.text == classA)
assert(f.height == 206 and not f.rows[2].row.shown)

-- Repeated links share one job; closing the window stops all scan work.
f.classCache = {}
ADKP_BidQueue = {{item = link(2)}, {item = link(2)}}
ADKP_UpdateBidQueueWindow()
local before = scans["item:2:0:0:0"]
tick()
assert(scans["item:2:0:0:0"] == before + 1)
assert(f.rows[1].classes.text == classB and f.rows[2].classes.text == classB)
ADKP_UpdateBidQueueWindow(); f:Hide(); assert(not f.scripts.OnUpdate)
ADKP_BidQueue = {}; ADKP_UpdateBidQueueWindow(); assert(not f.shown)

-- Switching returns the full link to the queue, not the display-only name.
local started
ADKP_Bid_StartBid = function(item) started = item end
ADKP_BidQueue = {{item = link(2)}}
ADKP_BidQueue_SwitchTo(1)
assert(started == link(2) and ADKP_BidQueue[1].item == link(1))
ADKP_BidFrameItem:SetText("")
ADKP_BidQueue = {{item = link(3)}}
ADKP_BidQueue_SwitchTo(1)
assert(started == link(3) and table.getn(ADKP_BidQueue) == 0)
ADKP_BidFrameItem:SetText(link(3)); ADKP_Bid_RequestItemRefresh(link(3))
ADKP_BidQueue = {{item = link(3)}, {item = link(4)}}
ADKP_UpdateBidQueueWindow(); tick()
assert(f.height == 200 and f.curBg.height == 40 and not f.curClasses.shown)
assert(f.rows[1].row.height == 42 and f.rows[2].row.height == 42)
print("Bid queue PASS: numbering; scroll/actions beyond 10; layout bounds; class isolation/cache/retries; stale jobs; full links")
