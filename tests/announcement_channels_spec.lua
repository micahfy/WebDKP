-- Real Lua 5.0 senders and announcement call sites, with chat captured locally.
local function read(path)
    local f = assert(io.open(path, "rb")); local s = f:read("*a"); f:close(); return s
end
local function between(source, first, last)
    local a = assert(string.find(source, first, 1, true))
    local b = assert(string.find(source, last, a + string.len(first), true))
    return string.sub(source, a, b - 1)
end
local function eq(a, b, label)
    assert(a == b, (label or "value") .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end
local main = read("ADKP/ADKP.lua")
local function client(role, silent)
    local e = setmetatable({}, {__index = _G}); e._G = e
    e.sent = {}; e.printed = {}; e.writes = {}; e.assigned = 0
    e.WebDKP_Options = {SilentMode = silent}; e.WebDKP_DkpTable = {}
    e.GetNumRaidMembers = function() if role == "party" or role == "solo" then return 0 end; return 40 end
    e.GetNumPartyMembers = function() return role == "party" and 4 or 0 end
    e.IsRaidLeader = function() return role == "leader" or role == "solo" end
    e.IsRaidOfficer = function() return role == "assistant" or role == "party" end
    e.GetLootMethod = function() return "master", 0, 0 end
    e.GetTime = function() return 0 end
    e.UnitName = function() return "记分员" end
    e.SendChatMessage = function(text, channel) table.insert(e.sent, {text = text, channel = channel}) end
    e.ADKP_Print = function(text) table.insert(e.printed, text) end
    e.ADKP_GetItemInfo = function(item) return 4, item, item end
    e.ADKP_AllGroupSelected = function() return e.allSelected end
    e.ADKP_GetTableSize = function(t) local n = 0; for _ in pairs(t) do n = n + 1 end; return n end
    e.ADKP_GetTableid = function() return 1 end
    e.ADKP_StartAutoLoot = function() e.assigned = e.assigned + 1; return true end
    e.ADKP_GetAllRaidMembers = function() return {{name = "主团成员"}} end
    e.GetSubs = function() return {{name = "替补成员"}}, 1 end
    e.ADKP_AddDKP = function(points, reason, forItem, players, tableid, stamp)
        table.insert(e.writes, {points = points, reason = reason, stamp = stamp})
        return {key = reason}
    end
    e.ADKP_UpdateTableToShow = function() end
    e.ADKP_UpdateTable = function() end
    e.ADKP_Bid_ShowUI = function() end
    e.ADKP_Bid_GetSelected = function() return "小明", 50 end
    local function load(source, label)
        local fn = assert(loadstring(source, label)); setfenv(fn, e); fn()
    end
    load(read("ADKP/Announcments.lua"), "announcements")
    load(read("ADKP/Bidding.lua") .. [[
        -- Replace unrelated assignment/UI operations, keeping actual message
        -- construction and the real start/end/award/pass handlers under test.
        ADKP_Bid_ValidateAssignment = function() return "[毁灭之刃]" end
        ADKP_Bid_SetTransmogUI = function() end
        ADKP_Bid_WaitForAssignment = function() end
        ADKP_Bid_FinishSpecialAssignment = function() end
        ADKP_Bid_RecordItem = function() end
        function TEST_StartTransmog()
            ADKP_Bid_BeginTransmogSelection(nil, 0, true)
        end
        function TEST_AwardTransmog()
            ADKP_Bid_AwardTransmogSelected()
        end
        function TEST_QuickTransmog()
            ADKP_TransmogMode = false
            ADKP_bidItem = "[毁灭之刃]"
            ADKP_Bid_ExecuteQuickTransmog({item=ADKP_bidItem,target="小明"})
        end
        function TEST_EndTransmog()
            ADKP_TransmogMode = true
            ADKP_bidItem = "[毁灭之刃]"
            ADKP_Bid_EndTransmogSelection()
        end
        function TEST_Pass(assign)
            if assign then ADKP_Bid_AssignPassToPlayer("小明")
            else ADKP_Bid_PassItemRecordOnly() end
        end
    ]], "bidding")
    e.ADKP_Bid_ShowUI = function() end
    e.ADKP_Bid_GetSelected = function() return "小明", 50 end
    load("local ADKP_GetSubMembersForAward = GetSubs\n" ..
        between(main, "local function ADKP_Z_ApplyAward(", "local function ADKP_QuickFloat_InitOptions(") ..
        "\nTEST_Apply = ADKP_Z_ApplyAward", "main/standby award")
    return e
end

local cases = {
    {"A01", true, function(e) e.TEST_Apply(1, 0.5, "集合分", "固定时间") end,
        {"主团+1 (1人)，替补+0.5 (1人) 集合分"}},
    {"A02", true, function(e) e.TEST_Apply(1, 0.5, "解散分", "固定时间") end,
        {"主团+1 (1人)，替补+0.5 (1人) 解散分"}},
    {"A03", true, function(e) e.TEST_Apply(1, 0.5, "击杀-拉格纳罗斯", "固定时间") end,
        {"主团+1 (1人)，替补+0.5 (1人) 击杀-拉格纳罗斯"}},
    {"A04", true, function(e) e.TEST_Apply(1, 0.5, "活动奖励", "固定时间") end,
        {"主团+1 (1人)，替补+0.5 (1人) 活动奖励"}},
    {"A05", true, function(e) e.allSelected = true; e.ADKP_AnnounceAward(2, "开荒奖励") end,
        {"2 点dkp奖励给所有团员,原因: 开荒奖励."}},
    {"A06/A07 names", true, function(e)
        e.ADKP_LastAwardPlayers = {"小明", "小红"}; e.ADKP_LastAwardPlayerCount = 2
        e.ADKP_AnnounceAward(-2, "站位错误")
    end, {"-2 点dkp奖励(惩罚)给某些团员,原因: 站位错误.", "被奖励团员: 小明, 小红"}},
    {"A07 summary", true, function(e)
        e.ADKP_LastAwardPlayers = {"甲", "乙", "丙", "丁", "戊", "己"}; e.ADKP_LastAwardPlayerCount = 6
        e.ADKP_AnnounceAward(1, "替补奖励")
    end, {"1 点dkp奖励(惩罚)给某些团员,原因: 替补奖励.", "已为这 6 名替补成员调整了 DKP。"}},
    {"A08", true, function(e) e.ADKP_AnnounceAwardSingle(-2, "站位错误", "小明") end,
        {"-2 点dkp奖励(惩罚)给 小明,原因: 站位错误."}},
    {"B01", true, function(e) e.ADKP_AnnounceBidStart("[毁灭之刃]", 30) end,
        {"---------------------", "开始竞拍 >[毁灭之刃]< 请团队出分。"}},
    {"D01", true, function(e) e.ADKP_AnnounceAwardItem(-50, "[毁灭之刃]", "小明", false, {}) end,
        {">小明< 获取装备 >[毁灭之刃]< ,花费: 50 点DKP"}},
    {"D03", true, function(e) e.TEST_StartTransmog() end,
        {"[毁灭之刃] 幻化，直接Roll点或者团队打 hh 参与"}},
    {"D05 selected", true, function(e) e.TEST_AwardTransmog() end,
        {"[毁灭之刃] 授予 小明 幻化"}},
    {"D05 quick", true, function(e) e.TEST_QuickTransmog() end,
        {"[毁灭之刃] 授予 小明 幻化"}},
    {"B02 unchanged", false, function(e) e.ADKP_AnnounceBidEnd("[毁灭之刃]", "小明", 50) end,
        {"拍分系统: >[毁灭之刃]< 拍分结束"}},
    {"D04 unchanged", false, function(e) e.TEST_EndTransmog() end,
        {"[毁灭之刃] 幻化竞拍结束"}},
    {"D06 unchanged", false, function(e) e.TEST_Pass(true) end,
        {"[毁灭之刃] 流拍，分配给 小明"}},
    {"D07 unchanged", false, function(e) e.TEST_Pass(false) end,
        {"[毁灭之刃] 流拍"}},
    {"countdown unchanged", false, function(e) e.ADKP_SendCountdownMessage("倒计时3秒") end,
        {"倒计时3秒"}},
    {"quotation unchanged", false, function(e) e.ADKP_SendChatMessage("最高有效出分：50 分", "RAID") end,
        {"最高有效出分：50 分"}, "RAID"},
    {"standby unchanged", false, function(e) e.ADKP_SendAnnouncement("替补加分完成", e.ADKP_GetTellLocation()) end,
        {"替补加分完成"}},
    {"guild unchanged", false, function(e) e.ADKP_SendAnnouncement("公会通报", "GUILD", true) end,
        {"公会通报"}, "GUILD"},
}
for _, role in ipairs({"leader", "assistant", "member", "party", "solo"}) do
    local e = client(role, false)
    for _, case in ipairs(cases) do
        e.sent = {}; e.printed = {}; e.writes = {}; e.allSelected = false
        case[3](e)
        local channel = case[5] or e.ADKP_GetTellLocation()
        if case[2] and channel == "RAID" and (role == "leader" or role == "assistant") then channel = "RAID_WARNING" end
        if channel == "NONE" then
            eq(table.getn(e.sent), 0, role .. case[1])
            if case[1] == "B01" then
                eq(table.getn(e.printed), 1)
                eq(e.printed[1], table.concat(case[4], "\n"), role .. case[1])
            else
                eq(table.getn(e.printed), table.getn(case[4]), role .. case[1])
                for i, text in ipairs(case[4]) do eq(e.printed[i], text, role .. case[1]) end
            end
        else
            eq(table.getn(e.sent), table.getn(case[4]), role .. case[1])
            for i, text in ipairs(case[4]) do
                eq(e.sent[i].text, text, role .. case[1] .. " text")
                eq(e.sent[i].channel, channel, role .. case[1] .. " channel")
            end
        end
        if string.find(case[1], "^A0[1234]$") then
            eq(table.getn(e.writes), 2)
            eq(e.writes[1].points, 1); eq(e.writes[2].points, 0.5)
            eq(e.writes[2].reason, e.writes[1].reason .. "-替补")
            eq(e.writes[1].stamp, "固定时间"); eq(e.writes[2].stamp, "固定时间")
        elseif case[1] == "D01" then eq(e.assigned, 1, "item assignment still runs") end
    end
end
local e = client("leader", true)
for _, case in ipairs(cases) do
    e.sent = {}; e.printed = {}; e.allSelected = false; case[3](e)
    eq(table.getn(e.sent), 0, case[1] .. " silent")
    assert(table.getn(e.printed) > 0, case[1] .. " silent local output")
end
print("Announcement channels PASS: selected A01-A08/B01/D01/D03/D05; unchanged end/countdown/quotes/pass/guild/standby; leader/assistant/member/master-looter/party/solo; exact text; two-line start; silent mode; award/assignment side effects")
