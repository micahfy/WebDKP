-- Run with Lua 5.0. Exercise real bid/record/finish paths; mock WoW UI and loot APIs.
local function read(path)
    local f = assert(io.open(path, "rb")); local s = f:read("*a"); f:close(); return s
end
local function eq(a, b, label)
    assert(a == b, (label or "value") .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end
-- Load the addon's real 1.12 string.match shim before exercising chat parsing.
local mainSource = read("ADKP/ADKP.lua")
local shimStart = assert(string.find(mainSource, "if not string.match then", 1, true))
local shimEnd = assert(string.find(mainSource, "if not string.gmatch", shimStart, true))
assert(loadstring(string.sub(mainSource, shimStart, shimEnd - 1)))()
local notice = "当前不是队长分配或者没有分配权限，请竞拍完成后手动分配。"
local function client(method, master, partyName)
    local e = setmetatable({}, {__index = _G}); e._G = e
    e.method = method; e.master = master; e.partyName = partyName
    e.writes = {}; e.printed = {}; e.assignments = {}; e.pending = {}; e.frames = {}
    e.WebDKP_Options = {}; e.StaticPopupDialogs = {}; e.validItem = true
    e.tableid = 7
    e.roster = {{name = "记分员", class = "潜行者"}, {name = "收货人", class = "盗贼"}, {name = "幻化人", class = "法师"}}
    e.GetNumRaidMembers = function() return table.getn(e.roster) end
    e.GetNumPartyMembers = function() return 0 end
    e.GetRaidRosterInfo = function(i)
        local p = e.roster[i]; return p.name, 0, 1, 60, p.class
    end
    e.ADKP_GetClassColor = function() return "" end
    e.UIDropDownMenu_AddButton = function(info, level)
        e.menu[level] = e.menu[level] or {}; table.insert(e.menu[level], info)
        assert(table.getn(e.menu[level]) <= 32, "native dropdown capacity")
    end
    e.UIDropDownMenu_Initialize = function(frame, initialize)
        e.menu = {}; e.initialize = initialize; e.UIDROPDOWNMENU_MENU_LEVEL = 1; initialize()
    end
    e.ToggleDropDownMenu = function() end
    e.CloseDropDownMenus = function() e.menuClosed = true end
    e.GetLootMethod = function() return e.method, e.master end
    e.GetTime = function() return 0 end
    e.now = os.time({year = 2026, month = 10, day = 29, hour = 20, min = 0, sec = 0})
    e.time = function() return e.now end
    e.date = function(format, stamp) return os.date(format, stamp or e.now) end
    e.UnitName = function(unit) if unit == "player" then return "记分员" end; return e.partyName end
    e.ADKP_GetItemInfo = function(item)
        if not e.validItem then return nil end
        return 4, "毁灭之刃", "[毁灭之刃]"
    end
    -- Recording without assignment must not inspect the corpse or its candidates.
    e.GetNumLootItems = function() error("unexpected loot-window access") end
    e.GetMasterLootCandidate = function() error("unexpected loot-candidate access") end
    e.GiveMasterLoot = function() error("unexpected direct assignment") end
    e.ADKP_Print = function(text) table.insert(e.printed, text) end
    e.PlaySound = function() end
    e.ADKP_GetPlayerClass = function() return "潜行者" end
    e.ADKP_GetTableid = function() return e.tableid end
    e.ADKP_AddDKP = function(points, item, forItem, players, tableid, awardDate)
        local record = {points = points, item = item, player = players[0].name, tableid = tableid, date = awardDate}
        eq(forItem, "true", "item record")
        e.WebDKP_Log = e.WebDKP_Log or {}
        e.WebDKP_Log[item .. " " .. awardDate] = record
        table.insert(e.writes, record); return record
    end
    e.ADKP_AnnounceAwardItem = function(points, item, player, skipAutoLoot, record)
        eq(skipAutoLoot, true, "deferred assignment"); eq(record, e.writes[table.getn(e.writes)])
    end
    e.ADKP_StartAutoLoot = function(item, player, points, onComplete, pendingId, record)
        table.insert(e.assignments, {player = player, record = record})
        return e.assignmentResult ~= false
    end
    e.ADKP_AddUnassignedLoot = function(item, player, reason, rawError, record)
        table.insert(e.pending, {player = player, record = record})
    end
    e.ADKP_UpdateTableToShow = function() end; e.ADKP_UpdateTable = function() end
    e.ADKP_AnnounceBidStart = function() end; e.ADKP_AnnounceBidEnd = function() end
    e.ADKP_GetTellLocation = function() return "RAID" end
    e.ADKP_SendAnnouncement = function() end
    e.ADKP_IsAnonymousAuction = function() return false end
    e.StaticPopup_Show = function(key) e.popup = key end
    local function widget()
        return {SetText = function(self, text) self.text = text end, GetText = function(self) return self.text end,
            Show = function() end, Hide = function() end,
            SetScript = function(self, event, fn) self[event] = fn end,
            GetScript = function(self, event) return self[event] end}
    end
    e.CreateFrame = function(kind, name)
        local f = widget(); table.insert(e.frames, f)
        if name then e[name] = f end
        return f
    end
    e.ADKP_BidFrameBidButton = widget(); e.ADKP_BidFrameItem = widget()
    e.ADKP_BidFrameTime = widget(); e.ADKP_BidQueueLabel = widget()
    e.ADKP_Bid_UpdateFrame = widget(); e.ADKP_BidFrame_Countdown = widget()
    local fn = assert(loadstring(read("ADKP/Bidding.lua") .. [[
        ADKP_Bid_SetTransmogUI = function() end
        ADKP_Bid_OpenAssignmentMenu = function(callback) TEST_MenuCallback = callback end
        function TEST_Select(name, bid)
            ADKP_BidList = {}
            if name then ADKP_BidList[1] = {Name = name, Bid = bid, Selected = true} end
        end
        function TEST_Entries() return ADKP_BidList end
        TEST_Render = ADKP_Bid_UpdateTable
    ]], "bidding"))
    setfenv(fn, e); fn()
    e.ADKP_Bid_ShowUI = function() end; e.ADKP_Bid_HideUI = function() end
    e.ADKP_Bid_UpdateTable = function() end
    function e:submenu(level, value)
        self.UIDROPDOWNMENU_MENU_LEVEL = level; self.UIDROPDOWNMENU_MENU_VALUE = value
        self.menu[level] = {}; self.initialize(); return self.menu[level]
    end
    function e:click(entry)
        self.this = entry; assert(entry.func, "actionable menu entry"); entry.func()
    end
    function e:findPassPlayer(player)
        for _, group in ipairs(self:submenu(2, "player")) do
            for _, entry in ipairs(self:submenu(3, group.value)) do
                if entry.value == player then return entry end
            end
        end
        error("player not found: " .. player)
    end
    function e:choosePass(mode, player)
        self.ADKP_Bid_PassButtonClick("RightButton")
        if mode == "player" then self:click(self:findPassPlayer(player))
        else self:click(self.menu[1][mode == "self" and 3 or 2]) end
    end
    assert(e.ADKP_Bid_StartBid("[毁灭之刃]", 0))
    return e
end
local function finished(e, player, points, assigned, warned)
    eq(table.getn(e.writes), 1, "single record")
    eq(e.writes[1].player, player); eq(e.writes[1].points, points)
    eq(e.writes[1].tableid, 7)
    eq(table.getn(e.assignments), assigned, "assignment count")
    eq(e.ADKP_Bid_IsInProgress(), false, "bid stopped")
    eq(e.ADKP_Bid_IsTransmogMode(), false, "transmog finished")
    if warned then eq(e.printed[table.getn(e.printed)], notice)
    else eq(table.getn(e.printed), 0, "no permission warning") end
end

for _, role in ipairs({{"group", nil}, {"master", 1, "别人"}, {"master", nil},
        {"master", 0}, {"master", 2, "记分员"}}) do
    local permitted = role[1] == "master" and (role[2] == 0 or role[3] == "记分员")
    local assigned = permitted and 1 or 0
    local e = client(unpack(role))
    e.ADKP_Bid_PassButtonClick("LeftButton")
    finished(e, "记分员", 0, 0, false) -- unassigned pass only records, no assignment attempt

    e = client(unpack(role)); e.WebDKP_Options.PassAssignToSelf = true
    e.ADKP_Bid_PassButtonClick("LeftButton")
    finished(e, "记分员", 0, assigned, not permitted)

    e = client(unpack(role))
    e:choosePass("player", "收货人")
    finished(e, "收货人", 0, assigned, not permitted)

    e = client(unpack(role)); e.TEST_Select("出分人", 25)
    e.ADKP_Bid_TransmogButtonClick("LeftButton")
    eq(e.writes[1].player, "出分人"); eq(e.writes[1].points, -25)
    eq(e.ADKP_Bid_IsTransmogMode(), true)
    eq(table.getn(e.assignments), 0); eq(table.getn(e.printed), 0)
    -- Permission is checked at final award, not when starting transmog.
    e.TEST_Select("幻化人", 88); e.ADKP_Bid_TransmogButtonClick("LeftButton")
    finished(e, "出分人", -25, assigned, not permitted)

    e = client(unpack(role))
    e.ADKP_Bid_TransmogButtonClick("LeftButton"); assert(e.popup)
    e.StaticPopupDialogs[e.popup].OnAccept()
    eq(table.getn(e.writes), 0, "zero bid deferred until target selected")
    e.TEST_Select("幻化人", 88); e.ADKP_Bid_TransmogButtonClick("LeftButton")
    finished(e, "幻化人", 0, assigned, not permitted)

    for _, winner in ipairs({false, true}) do
        e = client(unpack(role))
        if winner then e.TEST_Select("出分人", 25) end
        e.ADKP_Bid_TransmogButtonClick("RightButton"); assert(e.TEST_MenuCallback)
        e.TEST_MenuCallback("幻化人"); assert(e.popup)
        e.StaticPopupDialogs[e.popup].OnAccept()
        finished(e, winner and "出分人" or "幻化人", winner and -25 or 0, assigned, not permitted)
        eq(table.getn(e.pending), 0, "no false unassigned failure")
    end
end

local e = client("master", 0)
e.TEST_Select("出分人", 25); e.ADKP_Bid_TransmogButtonClick("LeftButton")
e.method = "group" -- authority can change while transmog is in progress
e.TEST_Select("幻化人", 88); e.ADKP_Bid_TransmogButtonClick("LeftButton")
finished(e, "出分人", -25, 0, true)

e = client("master", 0); e.assignmentResult = false; e.WebDKP_Options.PassAssignToSelf = true
e.ADKP_Bid_PassButtonClick("LeftButton")
finished(e, "记分员", 0, 1, false)
eq(table.getn(e.pending), 1, "real auto-loot failure still tracked")

e = client("group", nil); e.validItem = false
e.ADKP_Bid_PassButtonClick("LeftButton")
eq(table.getn(e.writes), 0, "invalid item cannot be recorded")
eq(e.ADKP_Bid_IsInProgress(), true, "invalid item does not finish bid")

e = client("group", nil); e.WebDKP_Options.PassAssignToSelf = true
table.insert(e.ADKP_BidQueue, {item = "[下一件]", time = 0})
e.ADKP_Bid_PassButtonClick("LeftButton")
eq(e.printed[1], notice); eq(table.getn(e.assignments), 0)
assert(e.ADKP_BidQueueTimer and e.ADKP_BidQueueTimer.OnUpdate)
e.this = e.ADKP_BidQueueTimer; e.arg1 = 2; e.this.OnUpdate()
eq(e.ADKP_Bid_IsInProgress(), true, "queue continues without loot authority")

-- Menus execute only on a concrete choice, remember the last mode/person,
-- and protect against roster and auction changes before that choice.
e = client("master", 0)
e.ADKP_Bid_PassButtonClick("RightButton")
eq(table.getn(e.menu[1]), 4, "title and three top-level choices")
eq(e.menu[1][2].checked, true); eq(table.getn(e.writes), 0)
eq(e.WebDKP_Options.PassSettings, nil, "open/cancel does not change settings")
assert(not e.menu[1][4].func, "recipient header only expands")
local groups = e:submenu(2, "player")
eq(groups[1].value.class, "潜行者", "rogue aliases share their class")
eq(table.getn(e.writes), 0, "opening submenus does not record")
e:click(e:findPassPlayer("收货人"))
eq(e.WebDKP_Options.PassSettings["7"].mode, "player")
eq(e.WebDKP_Options.PassSettings["7"].player, "收货人")
e.ADKP_Bid_StartBid("[下一件]", 0); e.ADKP_Bid_PassButtonClick("LeftButton")
eq(table.getn(e.writes), 2); eq(e.writes[2].player, "收货人")
eq(table.getn(e.assignments), 2, "left click repeats remembered recipient")
e.ADKP_Bid_StartBid("[下一件]", 0); e:choosePass("self")
eq(e.writes[3].player, "记分员"); eq(e.WebDKP_Options.PassSettings["7"].player, "收货人")
e.ADKP_Bid_StartBid("[下一件]", 0); e:choosePass("record")
eq(table.getn(e.writes), 4); eq(table.getn(e.assignments), 3)
eq(e.WebDKP_Options.PassSettings["7"].mode, "record")
eq(e.WebDKP_Options.PassSettings["7"].player, "收货人", "other modes retain remembered name")
e.ADKP_Bid_StartBid("[下一件]", 0); e.ADKP_Bid_PassButtonClick("RightButton")
eq(e.menu[1][2].checked, true); eq(e.menu[1][4].text, "分配给：收货人")
local choice = e:findPassPlayer("收货人")
e.ADKP_Bid_StartBid("[下一件]", 0) -- same item name, different auction
e:click(choice)
eq(table.getn(e.writes), 4, "stale menu cannot process a new auction")
eq(e.WebDKP_Options.PassSettings["7"].mode, "record")

e = client("master", 0); e.ADKP_Bid_PassButtonClick("RightButton")
choice = e:findPassPlayer("收货人")
table.remove(e.roster, 2); e:click(choice)
eq(table.getn(e.writes), 0, "departed recipient does not create a record")
eq(table.getn(e.assignments), 0); eq(e.WebDKP_Options.PassSettings, nil)

e = client("master", 0); e:choosePass("player", "收货人")
table.remove(e.roster, 2); e.ADKP_Bid_StartBid("[下一件]", 0)
e.ADKP_Bid_PassButtonClick("LeftButton")
eq(table.getn(e.writes), 1, "remembered departed recipient is revalidated")
eq(table.getn(e.assignments), 1)

e = client("group", nil); e:choosePass("player", "收货人")
e.ADKP_Bid_StartBid("[下一件]", 0); e.tableid = 8
e.ADKP_Bid_PassButtonClick("LeftButton")
eq(e.writes[2].tableid, 8); eq(e.writes[2].player, "记分员")
eq(e.WebDKP_Options.PassSettings["8"].mode, "record", "teams have separate defaults")
e.ADKP_Bid_StartBid("[下一件]", 0); e.tableid = 7
e.ADKP_Bid_PassButtonClick("LeftButton"); eq(e.writes[3].player, "收货人")
local restored = client("group", nil); restored.WebDKP_Options = e.WebDKP_Options
restored.ADKP_Bid_PassButtonClick("LeftButton")
eq(restored.writes[1].player, "收货人", "recipient survives UI reload")

e = client("master", 0); e.ADKP_Bid_PassButtonClick("RightButton")
choice = e.menu[1][3]; e.tableid = 8; e:click(choice)
eq(table.getn(e.writes), 0, "stale menu cannot cross DKP teams")
e = client("master", 0); e.ADKP_Bid_PassButtonClick("RightButton")
choice = e.menu[1][3]; e.ADKP_Bid_StopBid(true); e:click(choice)
eq(table.getn(e.writes), 0, "stale menu cannot outlive bid stop")

e = client("master", 0); e.roster = {}
for i = 1, 40 do table.insert(e.roster, {name = "成员" .. i, class = "盗贼"}) end
e.ADKP_Bid_PassButtonClick("RightButton")
groups = e:submenu(2, "player"); eq(table.getn(groups), 2)
eq(table.getn(e:submenu(3, groups[1].value)), 30)
eq(table.getn(e:submenu(3, groups[2].value)), 10, "all 40 same-class members remain selectable")
print("Bid record permissions PASS: three-mode pass menu; recipient persistence and repeat; stale-menu and departed-player guards; team isolation; 40-member class pages; transmog; permissions; queue continuation")

-- Real chat handler: append items without resetting the active bid or its rolls.
local A = "|cffa335ee|Hitem:101:0:0:0|h[第一件 装备]|h|r"
local B = "|cffa335ee|Hitem:102:0:0:0|h[第二件装备]|h|r"
local C = "|cffa335ee|Hitem:103:0:0:0|h[第三件装备]|h|r"
local function chatClient()
    local c = client("group", nil)
    c.started, c.whispers = {}, {}
    local start = c.ADKP_Bid_StartBid
    c.ADKP_Bid_StartBid = function(item, time, singleAuction)
        table.insert(c.started, {item = item, time = time}); return start(item, time, singleAuction)
    end
    c.ADKP_SendWhisper = function(name, text) table.insert(c.whispers, text) end
    c.ADKP_AnnounceAwardItem = function(points, item, player, skipAutoLoot, record)
        eq(record, c.writes[table.getn(c.writes)])
    end
    c.ADKP_Bid_ShowUI = function() c.ADKP_UpdateBidQueueWindow() end
    function c:chat(message, sender)
        self.arg1, self.arg2 = message, sender or "记分员"; self.ADKP_Bid_Event()
    end
    function c:nextItem()
        self.this, self.arg1 = self.ADKP_BidQueueTimer, 2
        assert(self.this and self.this.OnUpdate); self.this.OnUpdate()
    end
    return c
end
e = chatClient(); e.TEST_Select("收货人", 25)
local originalText = e.ADKP_BidFrameItem:GetText()
e:chat("`" .. A .. B .. " 20")
eq(table.getn(e.started), 0); eq(e.ADKP_Bid_GetSelected(), "收货人")
eq(e.ADKP_BidFrameItem:GetText(), originalText); eq(e.ADKP_Bid_IsInProgress(), true)
eq(e.ADKP_BidQueue[1].item, A); eq(e.ADKP_BidQueue[2].item, B)
eq(e.ADKP_BidQueue[1].time, 20)
eq(e.ADKP_BidQueueLabel.text, "|cffffff00(队列还有2件)|r")
e:chat("·" .. C .. A .. " 5")
eq(e.ADKP_BidQueue[3].item, C); eq(e.ADKP_BidQueue[4].item, A)
eq(e.ADKP_BidQueue[4].time, 30, "keep legacy countdown normalization")
e:chat("`" .. B, "其他团员"); eq(table.getn(e.ADKP_BidQueue), 4)
e:chat("`   "); eq(table.getn(e.ADKP_BidQueue), 4)
eq(table.getn(e.writes), 0, "adding items never records the current item")

-- Transmog retains its participants and record; additions wait until it ends.
e = chatClient(); e.TEST_Select("出分人", 25)
e.ADKP_Bid_TransmogButtonClick("LeftButton")
e.TEST_Select("幻化人", 88); e:chat("`" .. A .. B)
eq(e.ADKP_Bid_IsTransmogMode(), true); eq(e.ADKP_Bid_GetSelected(), "幻化人")
eq(table.getn(e.writes), 1); eq(table.getn(e.started), 0)
e.ADKP_Bid_EndTransmogSelection(); e:nextItem()
eq(e.started[1].item, A); eq(e.ADKP_BidQueue[1].item, B)

-- Stopped bidding still awaits recording; additions must not replace it.
e = chatClient(); e.TEST_Select("收货人", 25); e.ADKP_Bid_StopBid(true)
e:chat("`" .. A .. B); eq(table.getn(e.started), 0)
e.ADKP_Bid_AwardSelected(); eq(table.getn(e.writes), 1)
e:nextItem(); eq(e.started[1].item, A); eq(e.ADKP_BidQueue[1].item, B)

-- Between auctions the next item is held by a timer, outside the queue table.
e = chatClient(); e:chat("`" .. A); e.ADKP_Bid_PassButtonClick("LeftButton")
eq(table.getn(e.ADKP_BidQueue), 0)
local scheduled = e.ADKP_BidQueueTimer.OnUpdate
e:chat("`" .. B .. C)
eq(e.ADKP_BidQueueTimer.OnUpdate, scheduled); eq(table.getn(e.started), 0)
e:nextItem(); eq(e.started[1].item, A)
eq(e.ADKP_BidQueue[1].item, B); eq(e.ADKP_BidQueue[2].item, C)

-- Recording a stopped bid must not dequeue twice while the next timer runs.
e = chatClient(); e.TEST_Select("收货人", 25); e:chat("`" .. A .. B)
e.ADKP_Bid_StopBid(); scheduled = e.ADKP_BidQueueTimer.OnUpdate
e.ADKP_Bid_AwardSelected(); eq(e.ADKP_BidQueueTimer.OnUpdate, scheduled)
e:nextItem(); eq(e.started[1].item, A); eq(e.ADKP_BidQueue[1].item, B)

-- Idle command still starts the first item; an existing idle queue is preserved.
e = chatClient(); e.ADKP_Bid_PassButtonClick("LeftButton")
e:chat("`  "); eq(table.getn(e.whispers), 1)
e:chat("`" .. B .. A .. " 40")
eq(e.started[1].item, B); eq(e.started[1].time, 40); eq(e.ADKP_BidQueue[1].item, A)
e = chatClient(); e.ADKP_Bid_PassButtonClick("LeftButton")
e.ADKP_BidQueue = {{item = A, time = 0}}
e:chat("`" .. B); eq(table.getn(e.started), 0); eq(e.ADKP_BidQueue[2].item, B)

-- Chat entries during the brief loot-sort wait follow that entire batch,
-- retaining input order even if their class counts would sort differently.
e = chatClient(); e.ADKP_Bid_PassButtonClick("LeftButton")
local ready = false
e.ADKP_Bid_ReadItemClasses = function(item)
    if not ready then return nil, false end
    return item == B and "职业: 战士, 法师" or nil, true
end
e.ADKP_Bid_StartSortedLootQueue({{item = A, time = 0}, {item = B, time = 0}})
e:chat("`" .. C .. A .. " 20"); ready = true
e.this, e.arg1 = e.ADKP_BidLootSortFrame, 0.1; e.this.OnUpdate()
eq(e.started[1].item, B)
eq(e.ADKP_BidQueue[1].item, A); eq(e.ADKP_BidQueue[2].item, C); eq(e.ADKP_BidQueue[3].item, A)
eq(e.ADKP_BidQueue[3].time, 20)

-- Numeric/P/sh bidding and anonymous-auction announcement gating are unchanged.
e = chatClient(); local amounts, messages = {}, {}
e.ADKP_Bid_HandleBid = function(name, amount) table.insert(amounts, amount) end
e.ADKP_GetDKP = function() return 42 end
e.ADKP_SendChatMessage = function(message) table.insert(messages, message) end
e:chat("12.5", "团员"); e:chat("20P", "团员"); e:chat("SH", "团员")
eq(amounts[1], 12.5); eq(amounts[2], 20); eq(amounts[3], 42); eq(table.getn(messages), 1)
e.ADKP_IsAnonymousAuction = function() return true end
e:chat("sh", "团员"); eq(table.getn(messages), 1)
print("Chat queue PASS: own commands only; single/multiple links; append order; active/stopped/transmog/queued/timer states; sort wait; finish continuity; bidding unchanged")

-- Multi-copy paths run the real handlers, without a client mod.
local function multiClient(copies)
    local c = chatClient()
    c.ADKP_GetDKP = function() return 25 end
    c.ADKP_SendChatMessage = function() end
    c.ADKP_BidQueue = {{item = B, time = 0}}
    for i = 2, copies do table.insert(c.ADKP_BidQueue, {item = A, time = 0}) end
    c.ADKP_Bid_StartBid(A, 0)
    c.ADKP_Bid_SetMergeEnabled(true)
    function c:bid(name, amount) self.ADKP_Bid_HandleBid(name, amount) end
    function c:select(index)
        self.this = {ADKP_BidEntry = self.TEST_Entries()[index]}
        self.ADKP_Bid_SelectPlayerToggle()
    end
    function c:hh(name) self.ADKP_Bid_HandleTransmogChat("CHAT_MSG_RAID", name, "hh") end
    function c:roll(name, amount) self.ADKP_Bid_HandleRollMessage(name .. " rolls " .. amount .. " (1-100)") end
    function c:beginNoBid()
        self.ADKP_Bid_TransmogButtonClick("LeftButton")
        self.StaticPopupDialogs[self.popup].OnAccept()
    end
    return c
end

e = multiClient(3)
eq(e.ADKP_Bid_GetBatchCount(), 3, "non-adjacent identical items")
for i = 1, 4 do e:bid("甲", 10) end
eq(table.getn(e.TEST_Entries()), 3, "duplicate bids capped by copies")
e:bid("甲", 12); e:bid("乙", 10)
e:select(1); e:select(2); e:select(3); e:select(4)
eq(e.TEST_Entries()[1].Selected, false, "FIFO replaces earliest selection")
eq(e.TEST_Entries()[2].Selected, true)
e:select(2); eq(e.TEST_Entries()[2].Selected, false, "second click deselects exact entry")
eq(e.TEST_Entries()[3].Selected, true, "equal name/price rows remain independent")
e.ADKP_Bid_SetMergeEnabled(false)
eq(e.TEST_Entries()[3].Selected, false); eq(e.TEST_Entries()[4].Selected, true)
eq(e.ADKP_Bid_GetBatchCount(), 1)
e.ADKP_Bid_SetMergeEnabled(true); e:select(5)
e.ADKP_Bid_AwardSelected()
eq(table.getn(e.writes), 2, "one record per selected row")
eq(e.writes[1].player, "甲"); eq(e.writes[1].points, -12)
eq(e.writes[2].player, "乙"); eq(e.writes[2].points, -10)
eq(table.getn(e.ADKP_BidQueue), 1, "unawarded copy remains; other item scheduled")
eq(e.ADKP_BidQueue[1].singleAuction, true)
e:nextItem(); eq(e.started[2].item, B)
e.ADKP_Bid_PassButtonClick("LeftButton"); e:nextItem()
eq(e.started[3].item, A); eq(e.ADKP_Bid_GetBatchCount(), 1, "remainder auctions singly")
e.ADKP_Bid_AwardSelected(); eq(table.getn(e.writes), 3, "no stale paid entries")

-- Aggregate overdraft does not add an award-time gate or confirmation.
e = multiClient(3); e:bid("甲", 15); e:bid("甲", 15); e:bid("甲", 20)
e:select(1); e:select(2); e:select(3); e.ADKP_Bid_AwardSelected()
eq(table.getn(e.writes), 3); eq(e.writes[1].points, -15); eq(e.writes[2].points, -15); eq(e.writes[3].points, -20)
e.ADKP_Bid_AwardSelected(); eq(table.getn(e.writes), 3, "double-click cannot record again")

e = multiClient(1)
e.ADKP_BidQueue = {{item = "|Hitem:101:0:0:1234|h[另一个译名]|h"},
    {item = "|Hitem:101:0:5:1234|h[第一件 装备]|h"}, {item = "[第一件 装备]"}}
eq(e.ADKP_Bid_GetBatchCount(), 2, "ignore unique copy ID but retain variant fields")

for _, selectBid in ipairs({false, true}) do
    e = multiClient(3); e:bid("甲", 10); if selectBid then e:select(1) end
    e.ADKP_Bid_ButtonHandler()
    eq(table.getn(e.writes), 0); eq(table.getn(e.ADKP_BidQueue), 0)
    e.ADKP_Bid_AwardSelected(); eq(table.getn(e.writes), 0, "stop cancels all copies")
    e:nextItem(); eq(e.started[2].item, B)
end

e = multiClient(3); e:bid("甲", 10); e:bid("乙", 10); e:bid("丙", 10)
e:select(1); e:select(2); e:select(3); e.ADKP_BidQueue_Cancel(2)
eq(e.ADKP_Bid_GetBatchCount(), 2); eq(e.TEST_Entries()[1].Selected, false, "queue removal contracts quota")

-- Full transmog quota; paid refs first; HH/Roll remain independent; late links wait.
e = multiClient(3); e:bid("甲", 10); e:bid("乙", 12); e:select(1); e:select(2)
e.ADKP_Bid_TransmogButtonClick("LeftButton")
eq(table.getn(e.writes), 2); eq(e.ADKP_Bid_GetBatchCount(), 3)
eq(table.getn(e.ADKP_BidQueue), 1)
e.ADKP_Bid_SetMergeEnabled(false); eq(e.WebDKP_Options.MergeIdenticalAuctions, true, "transmog locks toggle")
e:chat("`" .. A .. A); eq(e.ADKP_Bid_GetBatchCount(), 3, "late copies cannot expand locked quota")
e:hh("幻化人"); e:hh("幻化人"); e:roll("幻化人", 70); e:roll("幻化人", 90)
eq(table.getn(e.TEST_Entries()), 2); eq(e.TEST_Entries()[2].Roll, 70)
eq(table.getn(e.TEST_Entries()[2].RepeatRolls), 1)
e:select(1); e:select(2); e.ADKP_Bid_TransmogButtonClick("LeftButton")
eq(table.getn(e.writes), 2, "two paid refs reused; no additional DKP")
eq(e.ADKP_Bid_GetBatchCount(), 1); eq(table.getn(e.TEST_Entries()), 0, "fresh transmog round")
e:roll("幻化人", 95); eq(e.TEST_Entries()[1].Roll, 95, "same recipient can participate again")
e.ADKP_Bid_TransmogButtonClick("RightButton"); e.TEST_MenuCallback("幻化人")
eq(table.getn(e.writes), 3); eq(e.writes[3].points, 0); eq(e.writes[3].player, "幻化人")
eq(e.ADKP_Bid_IsTransmogMode(), false)
eq(table.getn(e.ADKP_BidQueue), 2, "late same items remain after batch")

-- Assignment refs identify each copy even when a task fails.
e = multiClient(3); e.method, e.master = "master", 0
e:bid("甲", 10); e:select(1); e.ADKP_Bid_TransmogButtonClick("LeftButton")
e.ADKP_Bid_TransmogButtonClick("RightButton"); e.TEST_MenuCallback("幻化人")
eq(e.assignments[1].record, e.writes[1]); eq(table.getn(e.writes), 1)
e.assignmentResult = false
e:hh("收货人"); e:select(1); e.ADKP_Bid_TransmogButtonClick("LeftButton")
eq(e.assignments[2].record, e.writes[2]); eq(e.writes[2].points, 0)
eq(e.pending[1].record, e.writes[2]); eq(e.ADKP_Bid_GetBatchCount(), 1)
e.ADKP_Bid_EndTransmogSelection()
eq(table.getn(e.writes), 2, "cancel never changes paid records")
eq(table.getn(e.assignments), 2, "cancel does not grant remaining copy")

e = multiClient(2); e:beginNoBid()
e.ADKP_Bid_TransmogButtonClick("RightButton"); local staleMenu = e.TEST_MenuCallback
staleMenu("甲"); eq(e.writes[1].points, 0); eq(e.ADKP_Bid_GetBatchCount(), 1)
staleMenu("乙"); eq(table.getn(e.writes), 1, "stale menu cannot grant twice")
e:hh("甲"); e:select(1); e.ADKP_Bid_TransmogButtonClick("LeftButton")
eq(table.getn(e.writes), 2); eq(e.writes[2].points, 0)

e = multiClient(3); e:bid("甲", 10); e:bid("乙", 11); e:select(1); e:select(2)
e.ADKP_Bid_TransmogButtonClick("RightButton"); e.TEST_MenuCallback("幻化人")
e.StaticPopupDialogs[e.popup].OnAccept()
eq(table.getn(e.writes), 2); eq(e.ADKP_Bid_GetBatchCount(), 2, "quick transmog grants one copy")
eq(e.ADKP_Bid_IsTransmogMode(), true)
e.ADKP_Bid_EndTransmogSelection(); eq(table.getn(e.writes), 2)

-- Actual renderer: aggregate remaining DKP and separate duplicate row identity.
e = multiClient(3); e:bid("甲", 15); e:bid("甲", 15); e:bid("乙", 10)
e:select(1); e:select(2)
local widgets = {}
local function displayWidget()
    return {Show = function() end, Hide = function() end,
        SetText = function(self, text) self.text = text end,
        SetTextColor = function(self, r, g, b) self.color = {r,g,b} end,
        SetVertexColor = function() end}
end
for i = 1, 13 do
    for _, suffix in ipairs({"", "Name", "Bid", "DKP", "Post", "Background"}) do
        widgets["ADKP_BidFrameLine" .. i .. suffix] = displayWidget()
    end
end
e.getglobal = function(name) return widgets[name] end
e.FauxScrollFrame_GetOffset = function() return 0 end
e.FauxScrollFrame_Update = function() end
e.getn, e.tinsert = table.getn, table.insert
e.TEST_Render()
local found = {}
for i = 1, 3 do
    local row = widgets["ADKP_BidFrameLine" .. i]
    local post = widgets["ADKP_BidFrameLine" .. i .. "Post"]
    if row.ADKP_BidEntry.Name == "甲" then
        eq(post.text, -5); eq(post.color[1], 1); eq(post.color[2], 0)
        assert(not found[row.ADKP_BidEntry], "unique row entry reference")
        found[row.ADKP_BidEntry] = true
    else eq(post.text, 15) end
end
eq(table.getn(e.writes), 0, "preview does not write accounting records")
local firstRow = widgets.ADKP_BidFrameLine1.ADKP_BidEntry
e.TEST_Render(); eq(widgets.ADKP_BidFrameLine1.ADKP_BidEntry, firstRow, "stable duplicate row order")

-- Timer expiry must preserve entries for allocation; explicit Stop cancels.
e = multiClient(2); e.ADKP_Bid_StartBid(A, 1)
e:bid("甲", 10); e:bid("乙", 12); e:select(1); e:select(2)
e.ADKP_SendCountdownMessage = function() end
e.this = {TimeSinceLastUpdate = 0}
for i = 1, 10 do e.ADKP_Bid_OnUpdate(1.1) end -- bids extend the last second to ten
eq(e.ADKP_Bid_IsInProgress(), false); eq(e.ADKP_Bid_GetBatchCount(), 2)
eq(table.getn(e.TEST_Entries()), 2); eq(e.ADKP_BidQueueTimer, nil)
e.ADKP_Bid_AwardSelected(); eq(table.getn(e.writes), 2)

-- Two UI controls share saved state and both lock during transmog.
e = multiClient(2)
local controls = {}
for _, name in ipairs({"ADKP_BidFrameMerge", "ADKP_QuickBidMerge"}) do
    controls[name] = {SetChecked = function(self, value) self.checked = value end,
        Enable = function(self) self.enabled = true end, Disable = function(self) self.enabled = false end}
end
e.getglobal = function(name) return controls[name] end
e.ADKP_Bid_SetMergeEnabled(false)
eq(controls.ADKP_BidFrameMerge.checked, false); eq(controls.ADKP_QuickBidMerge.checked, false)
e.ADKP_Bid_SetMergeEnabled(true); e:beginNoBid()
eq(controls.ADKP_BidFrameMerge.enabled, false); eq(controls.ADKP_QuickBidMerge.enabled, false)
e.ADKP_Bid_EndTransmogSelection()
eq(controls.ADKP_BidFrameMerge.enabled, true); eq(controls.ADKP_QuickBidMerge.enabled, true)

-- Integration: real AddDKP log keys and real announcement/auto-loot queue.
-- Identical records in the same second must not overwrite one another, and
-- finishing one loot task must advance to the next copy's recipient/ref.
e = multiClient(3); e.method, e.master = "master", 0
local function loadPart(source, first, last)
    local a = assert(string.find(source, first, 1, true))
    local b = assert(string.find(source, last, a + string.len(first), true))
    local fn = assert(loadstring(string.sub(source, a, b - 1)))
    setfenv(fn, e); fn()
end
e.GetZoneText = function() return "纳克萨玛斯" end
e.ADKP_GetGuildName = function() return "公会" end
e.ADKP_ROUND = function(value) return math.floor(value * 100 + 0.5) / 100 end
local balance, saved = 25, 0
e.ADKP_AddDKPToTable = function(name, class, points) balance = balance + points end
e.ADKP_UpdateLootList = function() end
e.ADKP_SaveToDisk = function() saved = saved + 1 end
e.ADKP_ItemAward = "$player $item $cost"
e.ADKP_AutoLootData = {}; e.ADKP_AutoLootQueue = {}
e.GetNumLootItems = function() return 0 end
e.ADKP_CreateAutoLootFrame = function()
    return {statusText = {SetText = function() end}, Show = function() end}
end
loadPart(read("ADKP/Awards.lua"), "function ADKP_AddDKP(", "function ADKP_AddDKPToTable(")
loadPart(read("ADKP/Announcments.lua"), "function ADKP_AnnounceAwardItem(", "function ADKP_AnnounceAward(")
loadPart(mainSource, "local function ADKP_CanAssignMasterLoot()", "function ADKP_HandleUIError()")
e:bid("甲", 15); e:bid("甲", 15); e:bid("乙", 20)
e:select(1); e:select(2); e:select(3); e.ADKP_Bid_AwardSelected()
eq(balance, -25); eq(saved, 3)
local logCount, websiteKeys = 0, {}
for key, record in pairs(e.WebDKP_Log) do
    if type(record) == "table" then
        logCount = logCount + 1; eq(record.uniqueId, key)
        for player in pairs(record.awarded) do
            local websiteKey = player .. "/" .. record.reason .. "/" .. record.date
            assert(not websiteKeys[websiteKey], "website dedup key must be unique")
            websiteKeys[websiteKey] = true
        end
    end
end
eq(logCount, 3, "three independently timestamped records")
eq(table.getn(e.ADKP_AutoLootQueue), 2)
local ref1 = e.ADKP_AutoLootData.recordRef
eq(ref1.date, "2026-10-29 20:00:00")
eq(e.ADKP_AutoLootData.currentPlayer, "甲")
e.ADKP_StopAutoLoot(true)
local ref2 = e.ADKP_AutoLootData.recordRef
eq(ref2.date, "2026-10-29 20:00:01")
assert(ref1.key ~= ref2.key); eq(e.ADKP_AutoLootData.currentPlayer, "甲")
e.ADKP_StopAutoLoot(false)
eq(e.ADKP_AutoLootData.currentPlayer, "乙")
eq(e.ADKP_AutoLootData.recordRef.date, "2026-10-29 20:00:02")
assert(e.ADKP_AutoLootData.recordRef.key ~= ref2.key)
e.ADKP_StopAutoLoot(true); eq(e.ADKP_AutoLootData.isAssigning, false)

-- Timestamp offsets roll over the calendar, without sleeps or timers. A later
-- award also skips seconds already occupied by the previous multi-copy grant.
e = multiClient(3)
e.now = os.time({year = 2026, month = 12, day = 31, hour = 23, min = 59, sec = 59})
e:bid("甲", 10); e:bid("甲", 10); e:bid("甲", 10)
e:select(1); e:select(2); e:select(3)
e.ADKP_Bid_AwardSelected()
eq(e.writes[1].date, "2026-12-31 23:59:59")
eq(e.writes[2].date, "2027-01-01 00:00:00")
eq(e.writes[3].date, "2027-01-01 00:00:01")
e.now = e.now + 1
e:nextItem(); e.ADKP_Bid_PassButtonClick("LeftButton")
eq(e.writes[4].date, "2027-01-01 00:00:02", "later award skips occupied timestamps")

-- Zero-point transmog copies also need distinct website import keys.
e = multiClient(2); e:beginNoBid()
e.ADKP_Bid_TransmogButtonClick("RightButton"); e.TEST_MenuCallback("甲")
e.ADKP_Bid_TransmogButtonClick("RightButton"); e.TEST_MenuCallback("甲")
eq(e.writes[1].date, "2026-10-29 20:00:00")
eq(e.writes[2].date, "2026-10-29 20:00:01")
print("Auction timestamps PASS: website dedup keys; per-copy seconds; year rollover; later awards; zero-point transmog; no assignment delay")
print("Multi-copy PASS: identity; bid cap; FIFO selection; DKP preview; toggles; partial award; cancellation; per-copy logs; locked transmog; HH/Roll; paid/zero refs; new rounds; stale menus; assignment failure")
