-- Run from the repository root with Lua 5.0: lua tests/sync_spec.lua
local clock, day = 0, "2026-10-13"
local clients, disk, packets = {}, {}, {}
local dropped, wireBytes, doneDelay = false, 0, 0
local function read(path)
    local f = assert(io.open(path, "rb")); local text = f:read("*a"); f:close(); return text
end
local main = read("ADKP/ADKP.lua")
local importStart = assert(string.find(main, "function ADKP_DoImportInitial(", 1, true))
local importEnd = assert(string.find(main, "function ADKP_ShowImportInitial(", importStart, true))
local importCode = string.sub(main, importStart, importEnd - 1)
local awardStart = assert(string.find(main, "local function ADKP_Z_ApplyAwardBody(", 1, true))
local awardEnd = assert(string.find(main, "local function ADKP_QuickFloat_InitOptions(", awardStart, true))
local awardCode = string.sub(main, awardStart, awardEnd - 1) .. "\nADKP_TestApply = ADKP_Z_ApplyAward"
local editStart = assert(string.find(main, "function ADKP_EditDKPRecord(", 1, true))
local editEnd = assert(string.find(main, "function ADKP_ShowEditDKPDialog(", editStart, true))
local editCode = string.sub(main, editStart, editEnd - 1)
local groups = read("ADKP/GroupFunctions.lua")
local displayStart = assert(string.find(groups, "function ADKP_UpdateTableToShow(", 1, true))
local displayEnd = assert(string.find(groups, "function ADKP_UpdatePlayersInGroup(", displayStart, true))
local displayCode = string.sub(groups, displayStart, displayEnd - 1)
local function client(name, variables, throttleOrder)
    local e = setmetatable({}, { __index = _G })
    disk[name] = disk[name] or {}
    e._G = e
    e.messages, e.popup, e.backups = {}, nil, 0
    e.WebDKP_Options = { SubSettings = { captains = {} }, BossAutoAward = true, BossDeathPopup = true, AutoBackupEnabled = true }
    e.WebDKP_DkpTable, e.WebDKP_Log = {}, {}
    e.WebDKP_Tables = { [1] = { id = 1, name = "主团" } }
    e.WebDKP_DailySubRecords, e.WebDKP_LootHistory, e.WebDKP_Loot, e.WebDKP_WebOptions = {}, {}, {}, {}
    e.ADKP_Frame = { selectedTableid = 1 }
    e.floor, e.tinsert, e.ADKP_TierInterval = math.floor, table.insert, 5
    e.strlen, e.getn, e.tremove = string.len, table.getn, table.remove
    e.min, e.max, e.format = math.min, math.max, string.format
    e.GetFramerate = function() return 60 end
    e.SendChatMessage = function() end
    e.ADKP_PlayersInGroup = {}
    e.ADKP_ShouldDisplay = function() return true end
    e.ADKP_GetAllRaidMembers = function() return {{name="玩家甲",class="战士"},{name="新成员",class="德鲁伊"}} end
    e.ADKP_GetSubMembersForAward = function() return {{name="替补甲",class="牧师"}}, 1 end
    e.ADKP_SendAnnouncement = function() end
    e.SlashCmdList, e.StaticPopupDialogs = {}, {}
    e.SUPERWOW_STRING = "test"
    e.getglobal = function(key) return e[key] end
    e.setglobal = function(key, value) e[key] = value end
    e.UnitName = function() return name end
    e.GetRealmName = function() return "TestRealm" end
    e.GetGuildInfo = function() return "Guild" end
    e.GetZoneText = function() return "Raid" end
    e.GetNumRaidMembers = function() return 40 end
    e.GetNumPartyMembers = function() return 0 end
    e.GetTime = function() return clock end
    e.time = function() return 1800000000 + math.floor(clock) end
    e.date = function(format)
        if format == "%Y-%m-%d" then return day end
        return day .. " 12:" .. string.format("%02d:%02d", math.mod(math.floor(clock / 60), 60), math.mod(math.floor(clock), 60))
    end
    e.ADKP_GetTableid = function() return e.ADKP_Frame.selectedTableid end
    e.ADKP_GetGuildName = function() return "Guild" end
    e.ADKP_GetDKP = function(who) return e.WebDKP_DkpTable[who] and e.WebDKP_DkpTable[who].dkp_1 or 0 end
    e.ADKP_GetSubCaptain = function(id) return e.WebDKP_Options.SubSettings.captains[id or 1] or "" end
    e.ADKP_SetSubCaptain = function(id, who) e.WebDKP_Options.SubSettings.captains[id] = who end
    e.ADKP_Print = function(text) table.insert(e.messages, text) end
    e.ADKP_ROUND = function(value, decimals) return tonumber(string.format("%." .. decimals .. "f", tonumber(value))) end
    e.ADKP_UpdateTable, e.ADKP_UpdateTableToShow, e.ADKP_UpdateLootList = function() end, function() end, function() end
    e.ADKP_SaveToDisk = function(skip) if not skip then e.backups = e.backups + 1 end end
    e.ExportFile = function(file, text) disk[name][file] = text end
    e.ImportFile = function(file) return disk[name][file] end
    e.StaticPopup_Show = function(key, text1, text2)
        if e.popupBusy or e.cinematic then
            local dialog = e.StaticPopupDialogs[key]
            if dialog.OnCancel then dialog.OnCancel() end
            return nil
        end
        e.popup = key
        e.popupText = string.format(e.StaticPopupDialogs[key].text, text1, text2)
        return { which = key }
    end
    e.InCinematic = function() return e.cinematic end
    e.StaticPopup_Hide = function(key) if e.popup == key then e.popup = nil end end
    e.StaticPopup_Visible = function(key) return e.popup == key end
    e.CreateFrame = function(kind, key)
        local f = { scripts = {} }
        f.SetScript = function(self, event, callback) self.scripts[event] = callback end
        f.RegisterEvent = function() end
        f.SetWidth = function(self, width) self.width = width end
        f.SetHeight = function(self, height) self.height = height end
        f.SetPoint = function(self, ...) self.anchor = arg end
        f.SetText = function(self, text) self.text = text end
        f.SetChecked = function(self, checked) self.checked = checked end
        f.GetChecked = function(self) return self.checked end
        f.CreateFontString = function() return e.CreateFrame("FontString") end
        setmetatable(f, { __index = function() return function() end end })
        if key then e[key] = f end
        return f
    end
    e.SendAddonMessage = function(prefix, text, channel)
        assert(not string.find(prefix .. text, "|", 1, true), "Invalid escape code in chat message")
        assert(channel == "GUILD", "non-guild communication")
        assert(string.len(prefix) + string.len(text) <= 254, "oversize packet")
        assert(not string.find(text, "[%z\128-\255]"), "wire must be ASCII")
        wireBytes = wireBytes + string.len(text) + string.len(prefix)
        local _, _, id = string.find(text, "^[MTN]#[^#]+#([%w%-]+)")
        local tx = e.ADKP_DataSync and e.ADKP_DataSync.tx[id]
        table.insert(packets, { sender = name, prefix = prefix, text = text, kind = tx and tx.kind })
    end
    e.ADKP_AwardDKP_Frame = e.CreateFrame("Frame")
    e.ADKP_AwardDKP_Frame:SetWidth(405)
    for _, file in ipairs({ "ADKP_SyncCodec.lua", "ADKP_SyncData.lua", "ADKP_BossAutoLog.lua", "Awards.lua", "ADKP_ShareGroups.lua", "ADKP_LootList.lua" }) do
        local f = assert(loadfile("ADKP/" .. file)); setfenv(f, e); f()
    end
    local f = assert(loadstring(importCode)); setfenv(f, e); f()
    f = assert(loadstring(displayCode)); setfenv(f, e); f()
    f = assert(loadstring(awardCode)); setfenv(f, e); f()
    f = assert(loadstring(editCode)); setfenv(f, e); f()
    if variables then for key, value in pairs(variables) do e[key] = value end end
    local function loadThrottle()
        local ctl = assert(loadfile("aux-addon/libs/ChatThrottleLib.lua")); setfenv(ctl, e); ctl()
    end
    if throttleOrder == "before" then loadThrottle() end
    if throttleOrder then
        local subs = assert(loadfile("ADKP/ADKP_SubSync.lua")); setfenv(subs, e); subs()
    end
    f = assert(loadfile("ADKP/ADKP_Backup.lua")); setfenv(f, e); f()
    f = assert(loadfile("ADKP/ADKP_DataSync.lua")); setfenv(f, e); f()
    e.ADKP_DataSyncInitialize()
    if throttleOrder == "after" then loadThrottle() end
    clients[name] = e
    return e
end
local function run(seconds, dropOne)
    for step = 1, math.ceil(seconds * 10) do
        clock = clock + 0.1
        for _, e in pairs(clients) do
            e.arg1 = 0.1
            e.ADKP_DataSyncEventFrame.scripts.OnUpdate()
        end
        local incoming = packets; packets = {}
        for _, packet in ipairs(incoming) do
            if doneDelay > 0 and packet.kind == "DONE" and not packet.ready then packet.ready = clock + doneDelay end
            local waiting = packet.ready and clock < packet.ready
            local drop = dropOne and not dropped and string.find(packet.text, "^M#")
                and string.find(packet.text, "#2#", 1, true)
            if waiting then table.insert(packets, packet)
            elseif drop then dropped = true
            else
                for who, e in pairs(clients) do
                    if who ~= packet.sender then
                        e.event, e.arg1, e.arg2, e.arg3, e.arg4 = "CHAT_MSG_ADDON", packet.prefix, packet.text, "GUILD", packet.sender
                        e.ADKP_DataSyncEventFrame.scripts.OnEvent()
                    end
                end
            end
        end
    end
end
local function accept(e)
    assert(e.popup == "ADKP_DATA_SYNC_CONFIRM", "missing sync confirmation: " .. tostring(e.popup))
    e.popup = nil
    e.StaticPopupDialogs.ADKP_DATA_SYNC_CONFIRM.OnAccept()
end
local function website(e, text)
    e.ADKP_DoImportInitial(text)
    assert(e.popup == "ADKP_IMPORT_INITIAL_CONFIRM", "missing import confirmation")
    e.popup = nil
    e.StaticPopupDialogs.ADKP_IMPORT_INITIAL_CONFIRM.OnAccept()
end
local function same(a, b)
    assert(a.ADKP_SyncData.Equal(a.ADKP_SyncData.State().meta, b.ADKP_SyncData.State().meta), "versions differ")
    assert(a.ADKP_SyncCodec.Pack(a.ADKP_SyncData.State().snapshot) == b.ADKP_SyncCodec.Pack(b.ADKP_SyncData.State().snapshot), "snapshots differ")
end

local A, B = client("大团队长"), client("替补队长")
assert(A.ADKP_DataSyncDiscoverButton.anchor[4] + A.ADKP_DataSyncDiscoverButton.width <= 405, "sync control outside panel")
local C = A.ADKP_SyncCodec
local sample = { [3] = false, foo = { "中文名字", "中文名字", 1.25 }, bar = "\000|%#" }
assert(C.Pack(C.Unpack(C.Pack(sample))) == C.Pack(sample), "codec round trip")
assert(C.Unescape(C.Escape("中文\000|%#")) == "中文\000|%#")
assert(not string.find(C.Escape("#|%"), "[#|]"), "unsafe field separator")
assert(not pcall(C.Unpack, "t999999999:"))
assert(not pcall(C.Unpack, "s20:short"))
assert(not pcall(C.Unpack, "p1:", {}))
local csv = "玩家甲,战士,100\n玩家乙,法师,200\n替补甲,牧师,50"
website(A, csv)
A.ADKP_AddDKP(2, "Before pairing", "false", {{name="玩家甲",class="战士"}})
assert(A.ADKP_SyncData.State().meta.seq == 2, "pre-pair operation not retained")
A.ADKP_SetSubCaptain(1, "替补队长")
B.popupBusy = true
A.ADKP_DataSyncEnable(true)
run(20)
assert(not B.popup, "busy popup unexpectedly visible")
assert(B.ADKP_DataSync.activePrompt and not A.ADKP_DataSync.rejected, "popup contention treated as user rejection")
assert(not B.ADKP_SyncData.State().enabled and not next(B.WebDKP_DkpTable), "unaccepted request changed data")
assert(A.ADKP_DataSync.offer.response == "waiting", "offer receipt feedback missing")
B.popupBusy = false
run(2)
accept(B)
run(70, true)
assert(dropped, "packet drop scenario did not execute")
same(A, B)
assert(B.WebDKP_DkpTable["玩家甲"].dkp_1 == 102, "initial score missing")
assert(not B.ADKP_DataSyncCanWrite(true), "replica writable")
local seq = A.ADKP_SyncData.State().meta.seq
A.ADKP_SaveToDisk()
run(3)
assert(A.ADKP_SyncData.State().meta.seq == seq, "ordinary save increments revision")
local ctx = {boss="Boss"}
A.ADKP_TestApply(5, 2, "Boss", A.date("%Y-%m-%d %H:%M:%S"), ctx)
local mainRef = ctx.raidRef
assert(A.ADKP_SyncData.State().meta.seq == seq + 1, "compound operation not atomic")
run(50)
same(A, B)
assert(B.WebDKP_Log[mainRef.key].bossAutoAward.boss == "Boss", "boss metadata missing")
assert(B.WebDKP_DkpTable["新成员"].dkp_1 == 5, "new player dictionary missing")
local denied = B.ADKP_AddDKP(99, "Unauthorized", "false", {{name="玩家甲",class="战士"}})
assert(denied == nil and B.WebDKP_DkpTable["玩家甲"].dkp_1 == 107)
B.ADKP_PlayersInGroup = {{name="不属于主团", class="战士"}}
B.ADKP_UpdateTableToShow()
assert(not B.WebDKP_DkpTable["不属于主团"], "replica UI created local player")
day = "2026-10-14"
A.ADKP_AddDKP(1, "After midnight", "false", {{name="玩家甲",class="战士"}})
run(40)
same(A, B)
assert(B.ADKP_SyncData.State().meta.day == day and B.ADKP_SyncData.State().meta.seq == 1)
assert(B.WebDKP_Log[mainRef.key], "previous-day record removed")

-- New full reset needs fresh consent and leaves the old replica intact until acceptance.
website(A, "玩家甲,战士,300\n玩家丙,猎人,20")
run(20)
assert(B.popup == "ADKP_DATA_SYNC_CONFIRM", "reset did not require consent")
assert(B.WebDKP_DkpTable["玩家甲"].dkp_1 == 108, "reset applied before consent")
A.ADKP_AddDKP(3, "During reset confirmation", "false", {{name="玩家丙",class="猎人"}})
accept(B); run(70); same(A, B)
assert(not B.WebDKP_DkpTable["玩家乙"] and B.WebDKP_DkpTable["玩家丙"].dkp_1 == 23,
    "reset players: old=" .. tostring(B.WebDKP_DkpTable["玩家乙"]) .. " new=" .. tostring(B.WebDKP_DkpTable["玩家丙"].dkp_1))

-- B loses SavedVariables and all business data; its independent files restore consent and replica.
clients["替补队长"] = nil
A.ADKP_AddDKP(4, "While B offline", "false", {{name="玩家甲",class="战士"}})
run(15)
B = client("替补队长")
run(70); same(A, B)
assert(B.WebDKP_DkpTable["玩家甲"].dkp_1 == 304)

-- A loses everything: user confirms discovery, matching local file avoids a full download.
clients["大团队长"] = nil
A = client("大团队长")
run(20)
assert(A.popup == "ADKP_DATA_SYNC_CONFIRM", "master recovery prompt missing")
local before = wireBytes
accept(A); run(20); same(A, B)
assert(A.WebDKP_DkpTable["玩家甲"].dkp_1 == 304, "master recovery incomplete")
assert(wireBytes - before < 2000, "matching local snapshot caused full transfer")
assert(A.ADKP_DataSyncCanWrite(true))

-- No local file: restore every previous-day record from the peer after explicit confirmation.
clients["大团队长"] = nil; disk["大团队长"] = {}
A = client("大团队长")
run(20); accept(A); run(70); same(A, B)
assert(A.WebDKP_DkpTable["玩家甲"].dkp_1 == 304)
assert(A.ADKP_SyncData.State().role == "master")

-- Unrelated guild members cannot directly reset an established replica.
local attacker = client("陌生人")
website(attacker, "恶意角色,战士,999")
attacker.ADKP_SetSubCaptain(1, "替补队长")
attacker.ADKP_DataSyncEnable(true)
run(20)
assert(B.WebDKP_DkpTable["玩家甲"].dkp_1 == 304 and not B.WebDKP_DkpTable["恶意角色"])
assert(B.ADKP_SyncData.State().peer == "大团队长", "binding silently replaced")
clients["陌生人"] = nil

-- Record edits/deletions propagate their score changes, including dictionaries after a player leaves.
local ref = A.ADKP_AddDKP(7, "Delete me", "false", {{name="玩家甲", class="战士"}})
run(30)
assert(B.WebDKP_Log[ref.key])
assert(A.ADKP_EditDKPRecord(ref.uniqueId, 10, "Edited reason"))
run(30); same(A, B)
assert(B.WebDKP_Log[ref.key].points == 10 and B.WebDKP_DkpTable["玩家甲"].dkp_1 == 314)
assert(A.ADKP_RemovePlayerFromDKPRecord({key=ref.key}, "玩家甲"))
run(30); same(A, B)
assert(not B.WebDKP_Log[ref.key].awarded["玩家甲"])
assert(A.ADKP_AddPlayerToDKPRecord({key=ref.key}, "玩家甲"))
run(30); same(A, B)
assert(A.ADKP_DeleteDKPRecordByItemAndTime({key=ref.key,item="Delete me"}))
run(30); same(A, B)
assert(not B.WebDKP_Log[ref.key] and B.WebDKP_DkpTable["玩家甲"].dkp_1 == 304)
A.WebDKP_Options.QuickFloatSettings = {adjust={points=2,position={x=10,y=20}}}
A.ADKP_DataSyncDirty(); run(20)
local positionVersion = A.ADKP_SyncData.State().meta.seq
A.WebDKP_Options.QuickFloatSettings.adjust.position.x = 30
A.ADKP_SaveToDisk(); run(3)
assert(A.ADKP_SyncData.State().meta.seq == positionVersion, "window position synchronized")

-- B without any files requires manual identification of the main before rebuilding its link.
clients["替补队长"] = nil; disk["替补队长"] = {}
B = client("替补队长")
run(20)
assert(B.popup == "ADKP_DATA_SYNC_CONFIRM", "lost replica binding silently trusted")
accept(B); run(50); same(A, B)

-- A reset while B is offline cannot be resumed under the previous reset's consent.
clients["替补队长"] = nil
website(A, "玩家甲,战士,800")
run(15)
B = client("替补队长")
run(20)
assert(B.popup == "ADKP_DATA_SYNC_CONFIRM", "offline reset bypassed consent")
assert(B.WebDKP_DkpTable["玩家甲"].dkp_1 == 304)
local obsolete = B.ADKP_DataSync.popupAccept
website(A, "玩家甲,战士,900")
run(20)
obsolete()
assert(B.WebDKP_DkpTable["玩家甲"].dkp_1 == 304, "obsolete reset consent applied")
accept(B); run(60); same(A, B)
assert(B.WebDKP_DkpTable["玩家甲"].dkp_1 == 900)

-- Snapshot file replacement is checked by reading it back. A failed write retains the last good file.
local saved = A.ADKP_SyncData.ReadFiles()
for _, text in pairs(disk["大团队长"]) do assert(not string.find(text, "[%z\001-\031\127-\255]"), "checkpoint text-mode unsafe") end
local originalExport = A.ExportFile
A.ExportFile = function() end
A.ADKP_AddDKP(2, "Write failure", "false", {{name="玩家甲",class="战士"}})
assert(not A.ADKP_DataSync.fileSaved, "failed file write reported success")
assert(A.ADKP_SyncData.ReadFiles().fileSerial == saved.fileSerial)
A.ExportFile = originalExport
run(40); same(A, B)

-- Date rollback is rejected before modifying authoritative scores.
day = "2026-10-13"
assert(A.ADKP_AddDKP(9, "Bad clock", "false", {{name="玩家甲",class="战士"}}) == nil)
assert(A.WebDKP_DkpTable["玩家甲"].dkp_1 == 902)
day = "2026-10-14"

-- Full transfer can run longer than the nominal timeout if it is making progress.
local largeNames = {}
for i=1,40 do table.insert(largeNames, "成员" .. i .. ",战士,100") end
website(A, table.concat(largeNames, "\n"))
local roster = {}
for i=1,40 do roster[i]={name="成员"..i,class="战士"} end
for i=1,80 do A.ADKP_AddDKP(1, "Event "..i, "false", roster) end
run(25); accept(B)
run(700)
same(A, B)
assert(B.WebDKP_DkpTable["成员40"].dkp_1 == 180)
-- Recovery does not mutate existing business data if a complete payload is invalid.
local invalid = A.ADKP_SyncCodec.Copy(A.ADKP_SyncData.State().snapshot)
invalid.settings.SubSettings = true
local badMeta = A.ADKP_SyncCodec.Copy(A.ADKP_SyncData.State().meta)
badMeta.hash = A.ADKP_SyncCodec.Hash(A.ADKP_SyncCodec.Pack(invalid))
assert(not pcall(A.ADKP_SyncData.Apply, invalid, badMeta, "master"))
assert(A.WebDKP_DkpTable["成员40"].dkp_1 == 180)

-- Local-only recovery remains available when B is offline and no guild connection exists.
clients = {}
A = client("大团队长")
A.GetGuildInfo = function() return nil end
run(14)
assert(A.popup == "ADKP_DATA_SYNC_CONFIRM", "offline local recovery missing")
accept(A)
assert(A.WebDKP_DkpTable["成员40"].dkp_1 == 180 and A.ADKP_DataSyncCanWrite(true))
-- Cinematic suppression must retain the offer without automatic rejection.
clients = {}
local P, Q = client("申请队长"), client("确认队长")
P.WebDKP_Tables[1].name = "进度100%主团"
website(P, csv)
P.ADKP_SetSubCaptain(1, "确认队长")
Q.cinematic = true
P.ADKP_DataSyncEnable(true)
run(20)
assert(Q.ADKP_DataSync.activePrompt and not Q.popup and not P.ADKP_DataSync.rejected)
Q.cinematic = false
run(2)
assert(string.find(Q.popupText, "进度100%主团", 1, true), "popup formatting damaged literal percent")
Q.StaticPopup_Hide("ADKP_DATA_SYNC_CONFIRM")
run(3)
assert(Q.popup == "ADKP_DATA_SYNC_CONFIRM", "externally hidden confirmation not reopened")
Q.StaticPopupDialogs.ADKP_DATA_SYNC_CONFIRM.OnCancel(nil, "clicked")
run(8)
assert(P.ADKP_DataSync.rejected and not Q.ADKP_SyncData.State().enabled, "explicit cancel not respected")
-- Vanilla hides the clicked dialog after OnCancel; queued requests wait a tick.
clients = {}
local First, Second, Receiver = client("第一申请人"), client("第二申请人"), client("排队接收人")
website(First, csv); website(Second, csv)
First.ADKP_SetSubCaptain(1, "排队接收人"); First.ADKP_DataSyncEnable(true)
Second.ADKP_SetSubCaptain(1, "排队接收人"); Second.ADKP_DataSyncEnable(true)
run(20)
assert(table.getn(Receiver.ADKP_DataSync.promptQueue) == 1)
Receiver.StaticPopupDialogs.ADKP_DATA_SYNC_CONFIRM.OnCancel(nil, "clicked")
Receiver.StaticPopup_Hide("ADKP_DATA_SYNC_CONFIRM")
run(3)
assert(Receiver.popup == "ADKP_DATA_SYNC_CONFIRM", "queued request hidden by prior click")
accept(Receiver)
run(65)
assert(Receiver.ADKP_SyncData.State().enabled)
-- A B configured accidentally as a sending master gets explicit feedback.
clients = {}
P, Q = client("冲突申请人"), client("冲突接收人")
website(P, csv); website(Q, csv)
Q.ADKP_SetSubCaptain(1, "离线队长"); Q.ADKP_DataSyncEnable(true)
P.ADKP_SetSubCaptain(1, "冲突接收人"); P.ADKP_DataSyncEnable(true)
run(20)
assert(P.ADKP_DataSync.offer.response == "master", "master-role conflict silent")
assert(not Q.popup and Q.ADKP_SyncData.State().role == "master", "active master overwritten")
Q.ADKP_DataSyncEnable(false)
P.ADKP_DataSyncEnable(true)
run(20)
accept(Q)
run(65)
same(P, Q)
P.SlashCmdList.ADKPDATASYNC(); Q.SlashCmdList.ADKPDATASYNC()
assert(P.ADKP_DataSync.sentPackets > 0 and Q.ADKP_DataSync.receivedPackets > 0)
-- Load the exact user-provided aux CTL and ADKP substitute wrapper in both
-- orders. No native bypass: traffic must still be counted by ChatThrottleLib.
local ctlFile = io.open("aux-addon/libs/ChatThrottleLib.lua", "rb")
if ctlFile then
    ctlFile:close()
    clients = {}
    local HookA = client("限流主团", nil, "before")
    local HookB = client("限流替补", nil, "after")
    local ok, err = pcall(HookA.SendAddonMessage, "ADKPSYN1", "M|*|abc-1|1|1|old", "GUILD")
    assert(not ok and string.find(tostring(err), "Invalid escape code", 1, true), "old pipe failure not reproduced through CTL")
    website(HookA, csv)
    HookA.ADKP_SetSubCaptain(1, "限流替补"); HookA.ADKP_DataSyncEnable(true)
    run(20)
    assert(not HookA.ADKP_DataSync.lastSendError and not HookB.ADKP_DataSync.lastSendError, "CTL send failed")
    accept(HookB); run(70); same(HookA, HookB)
    dropped = false
    HookA.ADKP_AddDKP(3, "第#1次 |cffff0000有色原因|r 100%", "false", {{name="玩家甲",class="战士"}})
    run(70, true); same(HookA, HookB)
    assert(dropped and HookB.WebDKP_DkpTable["玩家甲"].dkp_1 == 103)
    assert(HookA.ChatThrottleLib.nBypass > 0 and HookB.ChatThrottleLib.nBypass > 0, "CTL accounting bypassed")
    print("aux ChatThrottleLib v14 / ADKP SubSync both hook orders PASS")
else
    print("aux fixture absent; native chat escape validation still covered")
end
-- Complete send errors are retained for diagnostics beyond the clipped UI line.
clients = {}
local ErrorClient = client("发送故障")
ErrorClient.SendAddonMessage = function() error("aux-addon/libs/ChatThrottleLib.lua:273: native send failure details") end
ErrorClient.ADKP_DataSyncCheckRecovery(); run(3)
assert(string.find(ErrorClient.ADKP_DataSync.lastSendError, "native send failure details", 1, true))
ErrorClient.SlashCmdList.ADKPDATASYNC()
assert(string.find(ErrorClient.messages[table.getn(ErrorClient.messages)], "native send failure details", 1, true))
-- Bounded compression, byte-for-byte round trips and strict malformed decoding.
local Codec = ErrorClient.ADKP_SyncCodec
local vectors = {{"",""},{"f","Zg=="},{"fo","Zm8="},{"foo","Zm9v"},{"foobar","Zm9vYmFy"}}
for _,v in ipairs(vectors) do
    assert(Codec.Base64Encode(v[1]) == v[2] and Codec.Base64Decode(v[2]) == v[1])
end
assert(not pcall(Codec.Base64Decode,"Zh=="))
assert(not pcall(Codec.Base64Decode,"AA=A"))
assert(not pcall(Codec.Base64Decode,"AA==AAAA"))
assert(not pcall(Codec.Base64Decode,"!!!!"))
assert(not pcall(Codec.Decompress,string.char(0,0)))
assert(not pcall(Codec.Decompress,string.char(255,240)))
assert(not pcall(Codec.Decompress,Codec.Compress(string.rep("abc",1000)),100))
local samples={"", "中文 # |cffff0000物品|r 100%", string.rep("甲乙丙abc",10000)}
math.randomseed(1200)
local arbitrary={}
for i=1,100000 do arbitrary[i]=string.char(math.random(0,255)) end
samples[table.getn(samples)+1]=table.concat(arbitrary)
for case=1,50 do
    local bytes={}
    for i=1,math.random(0,4000) do bytes[i]=string.char(math.random(0,255)) end
    samples[table.getn(samples)+1]=table.concat(bytes)
end
for _,sample in ipairs(samples) do
    assert(Codec.Decompress(Codec.Compress(sample)) == sample, "compression round trip")
    local wire=Codec.WireEncode(sample)
    assert(not string.find(wire,"[|#%z\128-\255]"), "unsafe wire byte")
    assert(Codec.WireDecode(wire) == sample, "wire round trip")
    assert(string.len(wire)<=string.len(Codec.Escape(sample))+1, "wire encoding expanded unnecessarily")
end
-- Same 100-player initial snapshot used for the before/after measurement.
clients = {}
local PerfA,PerfB=client("测试主团队长"),client("测试替补队长")
local csv100={}
for i=1,100 do csv100[i]="成员"..i..",战士,"..(100+i) end
website(PerfA,table.concat(csv100,"\n"))
PerfA.ADKP_SetSubCaptain(1,"测试替补队长"); PerfA.ADKP_DataSyncEnable(true)
run(20); accept(PerfB)
local start,bytes=clock,wireBytes
while not PerfA.ADKP_SyncData.Equal(PerfA.ADKP_SyncData.State().meta,PerfB.ADKP_SyncData.State().meta) and clock-start<50 do run(0.1) end
assert(clock-start<12 and wireBytes-bytes<6500, "100-player transfer performance regression")
print("100-player initial sync: "..string.format("%.1f",clock-start).." simulated seconds / "..(wireBytes-bytes).." wire bytes")
run(5); same(PerfA,PerfB)
-- Large transfers wait for business DONE from receipt, not from first packet.
-- Delay DONE eight seconds beyond the transport receipt; no second FULL may
-- start during that wait even when the actual transmission exceeded 30 sec.
clients = {}
local LongA,LongB=client("长传主团"),client("长传替补")
website(LongA,table.concat(csv100,"\n"))
for _,player in pairs(LongA.WebDKP_DkpTable) do
    local text={}
    for i=1,500 do text[i]=string.char(math.random(65,122)) end
    player.note=table.concat(text)
end
LongA.ADKP_DataSyncCommit(true)
LongA.ADKP_SetSubCaptain(1,"长传替补"); LongA.ADKP_DataSyncEnable(true)
run(20); doneDelay=8; accept(LongB)
start=clock
while not LongA.ADKP_SyncData.Equal(LongA.ADKP_SyncData.State().remoteAck,LongA.ADKP_SyncData.State().meta) and clock-start<400 do run(0.1) end
assert(clock-start>30 and clock-start<400, "long-transfer delayed confirmation scenario did not complete")
assert(LongA.ADKP_DataSync.fullTransfers==1, "long transfer started redundant full snapshot")
same(LongA,LongB)
doneDelay=0
print("Compression / ASCII wire / delayed business confirmation PASS")
print("Sync regression PASS: Lua 5.0 codec/packet limits, initial website baseline + ordered pre-pair operations, explicit reset consent, stale confirmations, packet loss, atomic real main/sub award, dictionary changes, read-only UI, midnight, complete A/B crash recovery, local-file fast path, sender isolation, deletion, file write failure, clock rollback, long 40-player transfer")
