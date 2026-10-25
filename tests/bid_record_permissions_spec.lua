-- Run with Lua 5.0. Exercise real bid/record/finish paths; mock WoW UI and loot APIs.
local function read(path)
    local f = assert(io.open(path, "rb")); local s = f:read("*a"); f:close(); return s
end
local function eq(a, b, label)
    assert(a == b, (label or "value") .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end
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
    e.ADKP_AddDKP = function(points, item, forItem, players, tableid)
        local record = {points = points, item = item, player = players[0].name, tableid = tableid}
        eq(forItem, "true", "item record")
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
        return {SetText = function() end, Show = function() end, Hide = function() end,
            SetScript = function(self, event, fn) self[event] = fn end}
    end
    e.CreateFrame = function() local f = widget(); table.insert(e.frames, f); return f end
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
