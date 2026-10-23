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
    e.ADKP_GetTableid = function() return 7 end
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
    e.ADKP_Bid_PassButtonClick("RightButton"); assert(e.TEST_MenuCallback)
    e.TEST_MenuCallback("收货人")
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
print("Bid record permissions PASS: pass/self/menu; transmog with/without bidder and quick menu; real records; permission loss; valid looter unchanged; queue continuation")
