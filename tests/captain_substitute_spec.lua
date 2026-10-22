-- Real captain roster transport, award selection and log maintenance in Lua 5.0.
local function read(path)
    local f = assert(io.open(path, "rb")); local s = f:read("*a"); f:close(); return s
end
local function between(s, first, last)
    local a = assert(string.find(s, first, 1, true), first)
    local b = assert(string.find(s, last, a + string.len(first), true), last)
    return string.sub(s, a, b - 1)
end
local main, loot, awards = read("ADKP/ADKP.lua"), read("ADKP/ADKP_LootList.lua"), read("ADKP/Awards.lua")
local function eq(a, b, label)
    assert(a == b, (label or "value") .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end
local function client(me, sameGuild, packets)
    local e = setmetatable({}, {__index = _G}); e._G = e
    e.me = me; e.team = 1; e.frames = {}; e.messages = {}; e.announcements = {}
    e.WebDKP_Options = {SubSettings = {captains = {[1] = "CaptainB"}}, IncludeSubCaptain = false}
    e.WebDKP_DkpTable = {}; e.WebDKP_Log = {}; e.SlashCmdList = {}; e.ADKP_PendingSubMembers = {}
    e.WebDKP_DailySubRecords = {old = "discard"}
    -- An old in-memory registration must never be a fallback award source.
    e.ADKP_SubData = {subs = {Ghost = {class = "Mage"}}}
    e.ADKP_SubAwardData = {captain = "CaptainB"}
    local party = {{name="贼替补",class="盗贼"},{name="法替补",class="Mage"},{name="Main",class="Warrior"}}
    e.GetNumRaidMembers = function() return me == "CaptainA" and 1 or 0 end
    e.GetNumPartyMembers = function() return me == "CaptainB" and table.getn(party) or 0 end
    e.GetRaidRosterInfo = function() return "Main", nil, nil, nil, "战士", "WARRIOR" end
    e.UnitName = function(unit)
        if unit == "player" then return me end
        local _, _, i = string.find(unit, "^party(%d+)$")
        return i and party[tonumber(i)].name
    end
    e.UnitClass = function(unit)
        if unit == "player" then return "Warrior" end
        local _, _, i = string.find(unit, "^party(%d+)$")
        return i and party[tonumber(i)].class
    end
    e.GetGuildInfo = function() return "Guild" .. (sameGuild and "Same" or me) end
    e.GetNumGuildMembers = function() return sameGuild and 2 or 1 end
    e.GetGuildRosterInfo = function(i) if sameGuild then return i == 1 and "CaptainA" or "CaptainB" end; return me end
    e.GuildRoster = function() end
    e.GetTime = function() return 100 end
    e.time = e.GetTime
    e.date = function() return "2026-10-23 20:00:00" end
    e.GetZoneText = function() return "测试区域" end
    e.UnitIsDeadOrGhost = function() return false end
    e.ADKP_GetTableid = function() return e.team end
    e.ADKP_GetTableNameById = function() return "测试团" end
    e.ADKP_GetGuildName = function() return "Guild" end
    e.ADKP_IsAddonDisabled = function() return false end
    e.ADKP_GetPlayerClass = function(name) return name == "贼替补" and "盗贼" or "Mage" end
    e.ADKP_PlayerInGroup = function(name) return name == "Main" end
    e.ADKP_TrimText = function(s) return string.gsub(s or "", "^%s*(.-)%s*$", "%1") end
    e.ADKP_UpdateCaptainLabel = function() end
    e.ADKP_Print = function(text) table.insert(e.messages, text) end
    e.DEFAULT_CHAT_FRAME = {AddMessage = function() end}
    e.ADKP_WhisperDKP_Event = function() end
    e.ADKP_Bid_Event = function() end
    e.ADKP_AutoInvite = function() end
    e.ADKP_HandleAddonMessage = function() end
    e.ADKP_UpdatePlayersInGroup = function() end
    e.ADKP_UpdateTable = function() end
    e.ADKP_UpdateTableToShow = function() end
    e.ADKP_UpdateLootList = function() end
    e.ADKP_SaveToDisk = function() end
    e.ADKP_GetAllRaidMembers = function() return {{name="Main",class="Warrior"}} end
    e.ADKP_SendAnnouncement = function(text) table.insert(e.announcements, text) end
    e.ADKP_ROUND = function(n, digits) local k=10^digits; return math.floor(n*k+0.5)/k end
    e.ADKP_AddDKPToTable = function(name, class, points)
        local player = e.WebDKP_DkpTable[name] or {class=class}
        e.WebDKP_DkpTable[name] = player
        local key = "dkp_" .. e.team; player[key] = (player[key] or 0) + points
    end
    e.CreateFrame = function(kind, name)
        local f = {scripts = {}, events = {}}
        function f:SetScript(event, fn) self.scripts[event] = fn end
        function f:RegisterEvent(event) self.events[event] = true end
        if name then e[name] = f end
        table.insert(e.frames, f); return f
    end
    e.SendAddonMessage = function(prefix, text, channel)
        table.insert(packets, {from=me,kind="addon",prefix=prefix,text=text,channel=channel})
    end
    e.SendChatMessage = function(text, channel, language, target)
        table.insert(packets, {from=me,kind="whisper",text=text,to=target,channel=channel})
    end
    e.ADKP_SendWhisper = function(target, text) e.SendChatMessage("ADKP: " .. text, "WHISPER", nil, target) end
    local function load(code, name)
        local f = assert(loadstring(code, name)); setfenv(f, e); f()
    end
    load(between(main,"function ADKP_GetSubCaptain(","function ADKP_UpdateCaptainLabel("),"captain settings")
    load(between(main,"function ADKP_NormalizeClassName(","-- 获取替补玩家列表"),"class normalization")
    load(between(main,"ADKP_CLASS_CODE = {","function ADKP_ADDON_LOADED("),"roster transport")
    load(between(main,"function ADKP_CHAT_MSG_WHISPER(","function ADKP_CHAT_MSG_PARTY_RAID("),"whisper dispatch")
    load(between(main,"local function ADKP_GetSubMembersForAward(","local function ADKP_QuickFloat_InitOptions(") ..
        "\nTEST_GetSubs=ADKP_GetSubMembersForAward; TEST_Apply=ADKP_Z_ApplyAward", "actual award selection")
    load(between(awards,"function ADKP_AddDKP(","function ADKP_AddDKPToTable("),"actual DKP logs")
    load(between(main,"function ADKP_EditSubstituteRecord(","function ADKP_ShowEditLootDialog("),"edit substitute log")
    load(between(loot,"function ADKP_GetSubstituteRecords(","function ADKP_UpdateLootList("),"substitute records")
    local start = assert(string.find(loot,"local function adkp_RevertEntryDKP(",1,true))
    load(string.sub(loot,start),"record deletion")
    load(between(main,"function ADKP_IsSubRosterMember(","function ADKP_SyncBossAwardControls("),"roster membership")
    load(between(main,"function ADKP_SlashCmdHandler(","ADKP_CLASS_COLORS = {"),"slash commands")
    load(read("ADKP/ADKP_SubSync.lua"),"guild/whisper routing")
    e.ADKP_ResolveSubCaptain = function() return e.ADKP_GetSubCaptain(e.team) end
    e.ADKP_InitSubSettings(); eq(e.WebDKP_DailySubRecords,nil,"old daily TB data released")
    e.ADKP_SubSync_RebuildGuildSet()
    return e
end
local function flush(clients, packets)
    local count = 0
    while table.getn(packets) > 0 do
        local packet = table.remove(packets,1); count=count+1; assert(count<100)
        for _, e in ipairs(clients) do
            if packet.kind == "addon" then
                eq(packet.channel,"GUILD")
                e.ADKP_HandleAddonMessage(packet.prefix,packet.text,packet.channel,packet.from)
            elseif e.me == packet.to then
                eq(packet.channel,"WHISPER")
                e.arg1=packet.text; e.arg2=packet.from; e.ADKP_CHAT_MSG_WHISPER()
            end
        end
    end
end
assert(loadstring(between(main,"if not string.match then","function ADKP_SaveToDisk(")))()
for _, sameGuild in ipairs({true,false}) do
    local packets={}; local A=client("CaptainA",sameGuild,packets); local B=client("CaptainB",sameGuild,packets)
    A.SlashCmdList.ADKPSUBSYNC("refresh")
    eq(packets[1].kind,sameGuild and "addon" or "whisper")
    flush({A,B},packets)
    assert(A.ADKP_SubAwardData.subSyncComplete and A.ADKP_SubAwardData.receivedResponse)
    local players,count=A.TEST_GetSubs(); eq(count,2)
    local byName={}; for _,player in ipairs(players) do byName[player.name]=player.class end
    eq(byName["贼替补"],"潜行者"); eq(byName["法替补"],"法师")
    eq(byName.CaptainB,nil); eq(byName.Main,nil); eq(byName.Ghost,nil)
    eq(A.ADKP_IsSubRosterMember("贼替补"),true)
    A.WebDKP_Options.IncludeSubCaptain=true
    A.SlashCmdList.ADKPSUBSYNC("refresh"); flush({A,B},packets)
    local _,including=A.TEST_GetSubs(); eq(including,3,"include captain")
    A.WebDKP_Options.IncludeSubCaptain=false
    A.TEST_Apply(2,1,"击杀-测试首领","2026-10-23 20:00:00")
    eq(A.WebDKP_DkpTable.Main.dkp_1,2)
    eq(A.WebDKP_DkpTable["贼替补"].dkp_1,1)
    eq(A.WebDKP_DkpTable["法替补"].dkp_1,1)
    eq(A.WebDKP_DkpTable.Ghost,nil); eq(A.WebDKP_DkpTable.CaptainB,nil)
    local records=A.ADKP_GetSubstituteRecords(); eq(table.getn(records),1); eq(records[1].playerCount,2)
    assert(A.ADKP_EditSubstituteRecord(records[1].uniqueId,"击杀-测试首领-替补",3))
    eq(A.WebDKP_DkpTable["贼替补"].dkp_1,3)
    assert(A.ADKP_DeleteSubstituteRecordByItemAndTime(A.ADKP_GetSubstituteRecords()[1]))
    eq(A.WebDKP_DkpTable["贼替补"].dkp_1,0); eq(A.WebDKP_DkpTable.Main.dkp_1,2)
    eq(table.getn(A.ADKP_GetSubstituteRecords()),0)
    -- Empty / absent captain rosters cannot fall back to old TB registrations.
    A.ADKP_PendingSubMembers={}; local none,zero=A.TEST_GetSubs(); eq(none,nil); eq(zero,0)
    A.ADKP_SetSubCaptain(1,""); A.TEST_Apply(1,1,"集合分","2026-10-23 20:01:00")
    eq(A.WebDKP_DkpTable.Main.dkp_1,3); eq(A.WebDKP_DkpTable.Ghost,nil)
    local frameCount=table.getn(A.frames)
    A.ADKP_SlashCmdHandler("tb 5 1"); A.ADKP_SlashCmdHandler("md")
    A.arg1="TB"; A.arg2="Ghost"; A.ADKP_CHAT_MSG_WHISPER()
    eq(table.getn(packets),0); eq(table.getn(A.frames),frameCount); eq(A.WebDKP_DkpTable.Ghost,nil)
    -- Incomplete/error responses retain the original main-only award protection.
    A.ADKP_SetSubCaptain(1,"CaptainB"); A.ADKP_ResetSubSyncState()
    A.ADKP_HandleSubWhisperData("CaptainB","ADKP: SUB:法替补:法")
    A.ADKP_HandleSubWhisperData("CaptainB","ADKP: SUB_COMPLETE:2")
    assert(not A.ADKP_SubAwardData.subSyncComplete)
    A.ADKP_HandleSubWhisperData("CaptainB","ADKP: SUB_ERROR:ROSTER_UNSTABLE:1:2")
    assert(A.ADKP_SubAwardData.subSyncAborted)
    A.TEST_Apply(1,1,"名单不完整","2026-10-23 20:02:00")
    eq(A.WebDKP_DkpTable.Main.dkp_1,4); eq(A.WebDKP_DkpTable["法替补"].dkp_1,0)
end
local toc=read("ADKP/ADKP.toc")
assert(not string.find(toc,"WebDKP_DailySubRecords",1,true))
for _,name in ipairs({"ADKP_HandleWhisperTB","ADKP_ProcessSubstitutes","ADKP_AttemptWhoQuery","cmd == \"tb\"","cmd == \"md\""}) do
    assert(not string.find(main,name,1,true),name.." still present")
end
print("Captain substitutes PASS: same/cross-guild round trips; fresh roster; class mapping; captain/main exclusions; awards; log viewing/edit/deletion; no TB fallback/commands/timers; old daily data cleared and no longer saved")
