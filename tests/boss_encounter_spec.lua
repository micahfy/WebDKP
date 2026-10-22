-- Real Lua 5.0 encounter engine, main popup/settings/award handlers and DKP logs.
local function source(path)
    local f = assert(io.open(path, "rb")); local s = f:read("*a"); f:close(); return s
end
local main = source("ADKP/ADKP.lua")
local awards = source("ADKP/Awards.lua")
local function between(s, first, last)
    local a = assert(string.find(s, first, 1, true), first)
    local b = assert(string.find(s, last, a + string.len(first), true), last)
    return string.sub(s, a, b - 1)
end
local recognition = between(main, "ADKP_BossAwardData = {", "function ADKP_AddCustomBoss(")
local settings = between(main, "function ADKP_IsBossEnabled(", "function ADKP_BossListToolbar_SetAll(")
local popup = between(main, "function ADKP_ShowBossKillAwardFrame(", "ADKP_PendingSubMembers = ")
local apply = between(main, "local function ADKP_Z_ApplyAward(", "local function ADKP_QuickFloat_InitOptions(")
local run = between(main, "local ADKP_RaidSubAwardQueue = ", "local function ADKP_QuickFloat_ExecuteRaidSub(")
local addDkp = between(awards, "function ADKP_AddDKP(", "function ADKP_AddDKPToTable(")
local function eq(actual, expected, why)
    assert(actual == expected, (why or "value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function client(locale, auto, options)
    local e = setmetatable({}, { __index = _G }); e._G = e
    e.now = 0; e.team = 1; e.zone = "Molten Core"; e.raidCombat = true; e.combat = true
    e.raidSize = 2; e.playerPoints = {}; e.logCalls = {}; e.messages = {}; e.announcements = {}; e.frames = {}
    e.WebDKP_Options = options or { BossDeathPopup = true, BossAutoAward = auto }
    e.WebDKP_Log = {}; e.UNITDIESOTHER = locale == "enUS" and "%s dies." or "%s死亡了。"
    e.GetLocale = function() return locale or "zhCN" end
    e.GetTime = function() return e.now end
    e.GetNumRaidMembers = function() return e.raidSize end
    e.GetNumPartyMembers = function() return 0 end
    e.GetZoneText = function() return e.zone end
    e.GetRealZoneText = e.GetZoneText
    e.GetSubZoneText = function() return e.subzone or "" end
    e.UnitAffectingCombat = function(unit) return unit == "player" and e.combat or unit ~= "player" and e.raidCombat end
    e.UnitIsDeadOrGhost = function(unit) return unit == "player" and e.dead or false end
    e.UnitName = function(unit) return unit == "player" and "Captain" or unit end
    e.ADKP_GetTableid = function() return e.team end
    e.ADKP_IsAddonDisabled = function() return e.WebDKP_Options.AddonDisabled end
    e.ADKP_IsBossExcluded = function(name)
        for _, n in ipairs(e.WebDKP_Options.ExcludedBosses or {}) do if n == name then return true end end
        return false
    end
    e.ADKP_Print = function(text) table.insert(e.messages, text) end
    e.ADKP_SendAnnouncement = function(text, channel) table.insert(e.announcements, {text=text,channel=channel}) end
    e.ADKP_ROUND = function(n, p) local k=10^p; return math.floor(n*k+0.5)/k end
    e.date = function(format) return os.date(format, 1792240000 + e.now) end
    e.ADKP_GetGuildName = function() return "TestGuild" end
    e.ADKP_AddDKPToTable = function(name, class, points)
        local key = e.team .. ":" .. name
        e.playerPoints[key] = (e.playerPoints[key] or 0) + points
    end
    e.ADKP_GetAllRaidMembers = function() return {{name="Main",class="Warrior"}} end
    e.ADKP_UpdatePlayersInGroup = function() end
    e.ADKP_SaveToDisk = function() end
    e.ADKP_UpdateLootList = function() end
    e.ADKP_UpdateTable = function() end
    e.ADKP_UpdateTableToShow = function() end
    e.GetSubMembers = function() return {{name="Standby",class="Mage"}}, 1 end
    e.SearchSubs = function(callback)
        if e.async then assert(not e.pendingSync, "overlapping standby synchronization"); e.pendingSync = callback
        else callback() end
    end
    e.getglobal = function(name) return e[name] end
    local function field()
        return {SetText=function(self,t) self.text=t end, GetText=function(self) return self.text or "" end}
    end
    e.CreateFrame = function(kind, name)
        local f = {scripts={}, events={}, shown=false}
        function f:SetScript(event, fn) self.scripts[event] = fn end
        function f:RegisterEvent(event) self.events[event] = true end
        function f:IsShown() return self.shown end
        function f:Show() self.shown = true end
        function f:Hide()
            local shown = self.shown; self.shown = false
            if shown and self.scripts.OnHide then self.scripts.OnHide() end
        end
        if name then e[name] = f end
        table.insert(e.frames, f)
        return f
    end
    e.ADKP_BossKillRaidEdit = field(); e.ADKP_BossKillSubEdit = field(); e.ADKP_BossKillAwardFrameBossNameText = field()
    e.ADKP_BossKillAwardFrame = e.CreateFrame("Frame", "ADKP_BossKillAwardFrame")
    local function chunk(text, name) local fn = assert(loadstring(text, name)); setfenv(fn,e); fn() end
    chunk(source("ADKP/ADKP_RaidBossData.lua"), "boss data")
    chunk(source("ADKP/ADKP_BossEncounters.lua"), "encounter engine")
    chunk(source("ADKP/ADKP_BossAutoLog.lua"), "linked automatic logs")
    chunk(recognition .. settings .. popup .. addDkp, "real main handlers")
    chunk("local ADKP_GetSubMembersForAward = GetSubMembers\n" .. apply .. "\nlocal ADKP_QuickFloat_SearchSubsThenRun = SearchSubs\n" .. run, "real award pipeline")
    e.ADKP_BossKillAwardFrame:SetScript("OnHide", e.ADKP_BossEncounter_PopupHidden)
    function e:tick(seconds)
        for i=1,math.ceil((seconds or 0.2)/0.2) do
            self.now=self.now+0.2; self.arg1=0.2
            self.ADKP_BossEncounterFrame.scripts.OnUpdate()
        end
    end
    function e:death(name, language)
        self.ADKP_HandleCombatHostileDeath(name .. (language == "enUS" and " dies." or "死亡了。"))
    end
    function e:out() self.combat=false; self.raidCombat=false; self:tick() end
    function e:start()
        self.combat=true; self.raidCombat=true; self.event="PLAYER_REGEN_DISABLED"
        self.ADKP_BossEncounterFrame.scripts.OnEvent()
    end
    function e:finishSync()
        local callback=assert(self.pendingSync); self.pendingSync=nil; callback()
    end
    function e:logCount()
        local count=0; for key,entry in pairs(self.WebDKP_Log) do if type(entry)=="table" then count=count+1 end end
        return count
    end
    return e
end

-- The user's list: 101 selectable encounters, 95 of them ordinary deaths.
local e=client("zhCN",true)
local sizes={ ["Molten Core"]=13,["Onyxia's Lair"]=2,["Blackwing Lair"]=9,["Zul'Gurub"]=13,
    ["Ruins of Ahn'Qiraj"]=6,["Temple of Ahn'Qiraj"]=9,["Naxxramas"]=15,["Lower Karazhan"]=6,
    ["Upper Karazhan"]=9,["Emerald Sanctum"]=2,["Timbermaw Hold"]=10,["World Bosses"]=7 }
local total,ordinary=0,0
for zone,info in pairs(e.ADKP_RaidBosses) do
    eq(table.getn(info.bosses),sizes[zone],zone)
    for _,boss in ipairs(info.bosses) do
        total=total+1
        if not boss.rule then ordinary=ordinary+1 end
    end
end
eq(total,101); eq(ordinary,95)
eq(e.ADKP_GetBossDefinition("Lord Victor Nefarius"),nil)
eq(e.ADKP_GetBossDefinition("Feugen"),nil); eq(e.ADKP_GetBossDefinition("Stalagg"),nil)
eq(e.ADKP_GetBossDefinition("无疤者奥斯里安").en,"Ossirian the Unscarred")
eq(e.ADKP_GetBossDefinition("黑女巫法琳娜").zh,"黑女巫法琳娜")
eq(e.ADKP_GetBossDefinition("教官拉苏维奥斯").zh,"教官拉苏维奥斯")
eq(e.ADKP_GetBossDefinition("大领主莫格莱尼").zh,"天启四骑士")
eq(e.ADKP_GetBossDefinition("维姆").zh,"安其拉三宝")

-- Every ordinary CN/EN name in both modes, including the three explicitly
-- requested ordinary rules. Check actual DKP totals, reasons and auto log links.
for _,info in pairs(e.ADKP_RaidBosses) do
    for _,boss in ipairs(info.bosses) do
        if not boss.rule then
            for _,locale in ipairs({"zhCN","enUS"}) do
                for _,auto in ipairs({false,true}) do
                    local c=client(locale,auto)
                    local name=locale=="zhCN" and boss.zh or boss.en
                    c:death(name,locale)
                    eq(c:logCount(),0,"no award during combat: "..name)
                    assert(not c.ADKP_BossKillAwardFrame:IsShown(),name)
                    c:out()
                    if not auto then
                        assert(c.ADKP_BossKillAwardFrame:IsShown(),name)
                        eq(c:logCount(),0)
                        eq(c.ADKP_BossKillRaidEdit:GetText(),"1")
                        c.ADKP_BossKillAwardFrame_OkClick()
                    end
                    eq(c.playerPoints["1:Main"],1,name)
                    eq(c.playerPoints["1:Standby"],1,name)
                    eq(c:logCount(),2,name)
                    eq(table.getn(c.announcements),1,name)
                    eq(table.getn(c.ADKP_GetBossAutoAwardRecords()),auto and 1 or 0,name)
                    c:death(name,locale); c:tick(); eq(c:logCount(),2,"duplicate "..name)
                end
            end
        end
    end
end

-- Cross-language messages, localized native format and slain variants.
e=client("enUS",true); e:death("拉格纳罗斯"); e:out(); eq(e:logCount(),2)
e=client("zhCN",true); e:death("Ragnaros","enUS"); e:out(); eq(e:logCount(),2)
e=client("enUS",true); e.ADKP_HandleCombatHostileDeath("You have slain Ragnaros!"); e:out(); eq(e:logCount(),2)
e=client("zhCN",true); e.ADKP_HandleCombatHostileDeath("你杀死了拉格纳罗斯！"); e:out(); eq(e:logCount(),2)
e=client("enUS",true); e.UNITDIESOTHER="[%s] has died!"; e.ADKP_HandleCombatHostileDeath("[Ragnaros] has died!"); e:out(); eq(e:logCount(),2)
e=client("zhCN",false); e.dead=true; e:death("拉格纳罗斯"); e:out(); assert(e.ADKP_BossKillAwardFrame:IsShown())

-- Shared-life pairs: either member suffices, both messages still award once.
for _,pair in ipairs({{"Smoldaris","Basalthar","双子傀儡"},{"Emperor Vek'lor","Emperor Vek'nilash","双子皇帝"}}) do
    for first=1,2 do
        e=client("zhCN",true)
        e:death(pair[first],"enUS"); eq(e:logCount(),0)
        e:death(pair[3-first],"enUS"); e:out(); eq(e:logCount(),2)
        eq(e.ADKP_GetBossAutoAwardRecords()[1].boss,pair[3])
        e:death(pair[first],"enUS"); eq(e:logCount(),2)
    end
end

local function permutations(list, callback, index)
    index=index or 1
    if index>table.getn(list) then callback(list); return end
    for i=index,table.getn(list) do
        list[index],list[i]=list[i],list[index]
        permutations(list,callback,index+1)
        list[index],list[i]=list[i],list[index]
    end
end
local horsemen={"Highlord Mograine","Thane Korth'azz","Lady Blaumeux","Sir Zeliek"}
local bugs={"Vem","Lord Kri","Princess Yauj"}
for _,members in ipairs({horsemen,bugs}) do
    permutations(members,function(order)
        local c=client("zhCN",true)
        for i,name in ipairs(order) do
            c:death(name,"enUS"); c:death(name,"enUS"); eq(c:logCount(),0)
        end
        c:out(); eq(c:logCount(),2)
    end)
end

-- One member's death/feign/out-of-combat does not reset the group's progress.
e=client("zhCN",true); e:death(horsemen[1],"enUS"); e.combat=false; e:tick(5)
for i=2,4 do e:death(horsemen[i],"enUS") end
e:tick(); eq(e:logCount(),2)
-- A genuine wipe clears incomplete counts, so the next pull cannot borrow kills.
e=client("zhCN",true); e:death(horsemen[1],"enUS"); e:out(); e:tick(4); e:start()
for i=2,4 do e:death(horsemen[i],"enUS") end
e:out(); eq(e:logCount(),0)
e:death(horsemen[1],"enUS"); e:tick(); eq(e:logCount(),2)

-- Majordomo's same-named adds are counts, not a set of unique names.
e=client("zhCN",true)
for i=1,4 do e:death("烈焰行者精英") end
for i=1,3 do e:death("Flamewaker Healer","enUS") end
e:out(); eq(e:logCount(),0)
e:death("烈焰行者医师"); e:tick(); eq(e:logCount(),2)
eq(e.ADKP_GetBossAutoAwardRecords()[1].boss,"管理者埃克索图斯")
e=client("zhCN",true); e.zone="Naxxramas"
for i=1,4 do e:death("烈焰行者精英"); e:death("烈焰行者医师") end
e:out(); eq(e:logCount(),0)

-- Rupturan: sender + zone + literal victory substring, then personal OOC.
for _,case in ipairs({{"化为尘土！","破碎者鲁普图兰"},{"Perished... To dust","Rupturan the Broken"}}) do
    e=client("zhCN",true); e.zone="荒芜巨岩"
    e.ADKP_BossEncounter_Yell(case[1],"Other NPC"); eq(next(e.ADKP_BossEncounterState.states),nil)
    e.ADKP_BossEncounter_Yell(case[1],case[2]); eq(e:logCount(),0)
    e.ADKP_BossEncounter_Yell(case[1],case[2]); e:out(); eq(e:logCount(),2)
    e.ADKP_BossEncounter_Yell(case[1],case[2]); e:tick(); eq(e:logCount(),2)
end
e=client("zhCN",true); e.zone="Molten Core"
e.ADKP_BossEncounter_Yell("化为尘土","破碎者鲁普图兰"); e:out(); eq(e:logCount(),0)
e=client("zhCN",true); e:death("破碎者鲁普图兰"); e:out(); eq(e:logCount(),0)

-- Ordinary kills in one battle merge into its last qualifying boss, in both modes.
for _,auto in ipairs({false,true}) do
    e=client("zhCN",auto)
    e.ADKP_SetBossPointField("Ragnaros","raid",3)
    e.ADKP_SetBossPointField("Onyxia","raid",7)
    e.ADKP_SetBossPointField("Onyxia","sub",0.5)
    e:death("Ragnaros","enUS"); e:death("Onyxia","enUS")
    e.ADKP_SetBossPointField("Onyxia","raid",9)
    e:tick(); eq(e:logCount(),0); assert(not e.ADKP_BossKillAwardFrame:IsShown())
    e:out()
    if not auto then
        eq(e.ADKP_BossAwardData.bossName,"奥妮克希亚")
        eq(e.ADKP_BossKillRaidEdit:GetText(),"7")
        e.ADKP_BossKillAwardFrame_OkClick()
    end
    eq(e.playerPoints["1:Main"],7); eq(e.playerPoints["1:Standby"],0.5)
    eq(e:logCount(),2); eq(table.getn(e.announcements),1)
    -- New/different death messages after settlement cannot add another reward.
    e:death("Nefarian","enUS"); e:tick(5); eq(e:logCount(),2)
end

-- Completed special and ordinary encounters share the same battle limit.
for _,specialLast in ipairs({false,true}) do
    e=client("zhCN",true)
    if not specialLast then e:death("Smoldaris","enUS") end
    e:death("Ragnaros","enUS")
    if specialLast then e:death("Smoldaris","enUS") end
    e:out(); eq(e:logCount(),2)
    eq(e.ADKP_GetBossAutoAwardRecords()[1].boss,specialLast and "双子傀儡" or "拉格纳罗斯")
    e:death("Basalthar","enUS"); e:tick(); eq(e:logCount(),2)
end
e=client("zhCN",true); e.zone="荒芜巨岩"
e:death("Ragnaros","enUS"); e.ADKP_BossEncounter_Yell("化为尘土","破碎者鲁普图兰")
e:out(); eq(e:logCount(),2); eq(e.ADKP_GetBossAutoAwardRecords()[1].boss,"破碎者鲁普图兰")
e:death("Nefarian","enUS"); e:tick(); eq(e:logCount(),2)
e=client("zhCN",true)
e:death("Smoldaris","enUS"); e:death("Emperor Vek'lor","enUS")
for _,name in ipairs(horsemen) do e:death(name,"enUS") end
e:out(); eq(e:logCount(),2); eq(e.ADKP_GetBossAutoAwardRecords()[1].boss,"天启四骑士")
-- Incomplete groups never override a completed ordinary boss.
e=client("zhCN",true); e:death("Ragnaros","enUS"); e:death(horsemen[1],"enUS")
e:out(); eq(e:logCount(),2); eq(e.ADKP_GetBossAutoAwardRecords()[1].boss,"拉格纳罗斯")

-- Personal OOC/re-entry while the raid keeps fighting is still the same battle.
e=client("zhCN",true); e:death("Ragnaros","enUS"); e.combat=false; e:tick()
eq(e:logCount(),2); e:start(); e:death("Onyxia","enUS"); e:out(); eq(e:logCount(),2)
-- A genuinely new pull awards once again, even with a short interval or same boss.
e:start(); e:death("Ragnaros","enUS"); e:out(); eq(e:logCount(),4)
e:start(); e:death("Ragnaros","enUS"); e:out(); eq(e:logCount(),6)
-- Even a short OOC interval clears incomplete combination counts for a new pull.
e=client("zhCN",true); e:death(horsemen[1],"enUS"); e:out(); e:start()
for i=2,4 do e:death(horsemen[i],"enUS") end
e:out(); eq(e:logCount(),0)
-- Regen events separate pulls even if there was no OnUpdate between them.
e=client("zhCN",true); e:death("Ragnaros","enUS")
e.combat=false; e.raidCombat=false; e.event="PLAYER_REGEN_ENABLED"
e.ADKP_BossEncounterFrame.scripts.OnEvent()
e:start(); e:death("Onyxia","enUS"); e:out(); eq(e:logCount(),2)
e:tick(); eq(e:logCount(),4)
-- A dead/OOC scorer may get no personal enter-combat event on the next pull.
e=client("zhCN",true); e:death("Ragnaros","enUS"); e:out()
e.dead=true; e.combat=false; e.raidCombat=true
e:death("Onyxia","enUS"); e:tick(); eq(e:logCount(),4)
e:death("Nefarian","enUS"); e:tick(); eq(e:logCount(),4)

-- Popup queue between separate battles: close skips one, double-click is harmless.
e=client("zhCN",false); e.ADKP_SetBossPointField("Ragnaros","raid",3)
e:death("Ragnaros","enUS"); e:out(); e:start(); e:death("Onyxia","enUS"); e:out()
eq(e.ADKP_BossAwardData.bossName,"拉格纳罗斯")
e.ADKP_BossKillRaidEdit:SetText("5"); e.ADKP_BossKillAwardFrame_OkClick()
e.ADKP_BossKillAwardFrame_OkClick(); eq(e:logCount(),2,"double click cannot confirm next boss")
eq(e.playerPoints["1:Main"],5); e:tick()
eq(e.ADKP_BossAwardData.bossName,"奥妮克希亚")
e.ADKP_BossKillAwardFrame:Hide(); e:tick(); eq(e:logCount(),2); eq(e.ADKP_BossEncounterState.active,nil)
e:death("Nefarian","enUS"); e:tick(); eq(e:logCount(),2,"dismissal keeps battle settled")
e=client("zhCN",false); e.async=true; e:death("Ragnaros","enUS"); e:out()
e.ADKP_BossKillAwardFrame_OkClick(); e.ADKP_BossKillAwardFrame_OkClick()
e:finishSync(); eq(e:logCount(),2)

-- Automatic mode serializes the actual asynchronous standby query pipeline.
e=client("zhCN",true); e.async=true
e:death("Ragnaros","enUS"); e:out()
e:death("Onyxia","enUS"); e:tick(); e:finishSync(); e:tick()
eq(e:logCount(),2); eq(e.pendingSync,nil,"same battle cannot schedule a second roster query")
e=client("zhCN",true); e.async=true
e:death("Ragnaros","enUS"); e:out(); e:start(); e:death("Onyxia","enUS"); e:out(); eq(e:logCount(),0)
e:finishSync(); eq(e:logCount(),2); e:tick(); assert(e.pendingSync)
e:finishSync(); eq(e:logCount(),4); eq(table.getn(e.ADKP_GetBossAutoAwardRecords()),2)
-- A manual quick-float award cannot reset an in-flight boss roster query.
e=client("zhCN",true); e.async=true; e:death("Ragnaros","enUS"); e:out()
e.ADKP_RunRaidAndSubAward(2,0.5,"Manual")
e:finishSync(); eq(e:logCount(),2); assert(e.pendingSync)
e:finishSync(); eq(e:logCount(),4); eq(e.playerPoints["1:Main"],3); eq(e.playerPoints["1:Standby"],1.5)
e=client("zhCN",true)
e.ADKP_SetBossPointField("双子皇帝","raid",3.25); e.ADKP_SetBossPointField("维克洛尔大帝","sub",0.5)
e:death("维克尼拉斯大帝"); e:out()
eq(e.playerPoints["1:Main"],3.25); eq(e.playerPoints["1:Standby"],0.5)
-- A team change while awaiting a roster must never write into the new team.
e=client("zhCN",true); e.async=true; e:death("Ragnaros","enUS"); e:out(); e.team=2
e:finishSync(); eq(e:logCount(),0); e.team=1; e:tick(); assert(e.ADKP_BossKillAwardFrame:IsShown())
e.ADKP_BossKillAwardFrame_OkClick(); e:finishSync(); eq(e.playerPoints["1:Main"],1); eq(e.playerPoints["2:Main"],nil)

-- Settings: bilingual/member names resolve to a single group configuration.
local options={BossDeathPopup=true,BossAutoAward=true,BossPointsDefault={raid=1,sub=1},
    BossPoints={ ["highlord mograine"]={raid=2},["thane korth'azz"]={raid=2},["lady blaumeux"]={raid=2},["sir zeliek"]={raid=2} },
    EnabledRaidBosses={ ["lady blaumeux"]=false }}
e=client("zhCN",true,options); eq(e.ADKP_GetBossAwardPoints("天启四骑士"),2)
eq(e.ADKP_IsBossEnabled("Highlord Mograine"),false)
e.ADKP_SetBossEnabledState(e.ADKP_GetBossDefinition("天启四骑士"),true)
eq(e.ADKP_IsBossEnabled("Lady Blaumeux"),true)
e.ADKP_SetBossPointField("大领主莫格莱尼","raid",4)
eq(e.ADKP_GetBossAwardPoints("The Four Horsemen"),4)
e.ADKP_SetBossPointField("天启四骑士","raid",nil); eq(e.ADKP_GetBossAwardPoints("Sir Zeliek"),1)
options={BossPointsDefault={raid=1,sub=1},BossPoints={ ["vem"]={raid=3},["lord kri"]={raid=2},["princess yauj"]={raid=2} }}
e=client("zhCN",false,options); eq(e.ADKP_GetBossAwardPoints("安其拉三宝"),1)
assert(e.WebDKP_Options.BossEncounterMergeConflicts["the bug trio"].raid)
assert(table.getn(e.messages)>0)
-- Ordinary renamed settings and Solnius/King aliases keep their old values.
e=client("zhCN",false,{BossPoints={ ["solnius the awakener"]={raid=7},["无伤者奥西里安"]={raid=6},["king (chess fight)"]={raid=8} }})
eq(e.ADKP_GetBossAwardPoints("Solnius"),7); eq(e.ADKP_GetBossAwardPoints("无疤者奥斯里安"),6); eq(e.ADKP_GetBossAwardPoints("King"),8)

-- Feature/individual switches, exclusions, custom bosses and removed entries.
e=client("zhCN",true); e.WebDKP_Options.BossDeathPopup=false; e:death("Ragnaros","enUS"); eq(e:logCount(),0)
e.WebDKP_Options.BossDeathPopup=true; e.WebDKP_Options.AddonDisabled=true; e:death("Ragnaros","enUS"); eq(e:logCount(),0)
e=client("zhCN",true); e.ADKP_SetBossEnabledState(e.ADKP_GetBossDefinition("双子皇帝"),false)
e:death("Vek'lor","enUS"); e:out(); eq(e:logCount(),0)
e=client("zhCN",true); e.WebDKP_Options.ExcludedBosses={"拉格纳罗斯"}; e:death("拉格纳罗斯"); eq(e:logCount(),0)
e=client("zhCN",true); e.WebDKP_Options.ExcludedBosses={"Lord Kri"}
for _,name in ipairs({"维姆","克里勋爵","亚尔基公主"}) do e:death(name) end
e:out(); eq(e:logCount(),0,"excluded member maps to the same bilingual encounter")
e=client("zhCN",true); e.raidSize=0; e:death("Ragnaros","enUS"); eq(e:logCount(),0)
e=client("zhCN",true); e.WebDKP_Options.BossPatterns={"Test Boss","破碎者鲁普图兰","天启四骑士"}
e:death("天启四骑士"); e:death("破碎者鲁普图兰"); eq(e:logCount(),0)
e:death("Test Boss","enUS"); e:out(); eq(e:logCount(),2)
e=client("zhCN",true); e:death("Lord Victor Nefarius","enUS"); e:death("Feugen","enUS"); eq(e:logCount(),0)
e=client("zhCN",true); e:death("Emperor Vek'lor","enUS"); e.WebDKP_Options.BossDeathPopup=false; e:tick()
e.WebDKP_Options.BossDeathPopup=true; e:out(); eq(e:logCount(),0)

print("Boss encounter PASS: all 101 entries; CN/EN and both modes; one award per battle with last qualifying boss; mixed death/group/yell rules; new pulls and personal combat re-entry; shared pairs; all 24/6 group orders; wipe reset; 4+4 counters; popup/async queues; real DKP logs, points, announcements and auto-log links; settings migration and gates")
