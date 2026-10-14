-- Real backup/parser/ShareGroups/login hooks; only WoW and file APIs mocked.
local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}; for key, item in pairs(value) do result[key] = copy(item) end
    return result
end
local function source(path)
    local file = assert(io.open(path, "rb")); local text = file:read("*a"); file:close(); return text
end
local main = source("ADKP/ADKP.lua")
local function between(first, next)
    local a = assert(string.find(main, first, 1, true))
    local b = assert(string.find(main, next, a + string.len(first), true))
    return string.sub(main, a, b - 1)
end
local core = between("function ADKP_SaveToDisk(", "-- 导入按钮 OnClick")
local website = between("function ADKP_DoImportInitial(", "function ADKP_ShowImportInitial(")
local disk = {}
local function client(saved)
    local e = setmetatable({}, { __index = _G }); e._G = e
    e.now = os.time({year=2026,month=10,day=14,hour=20,min=0,sec=0})
    e.team = 1; e.messages = {}; e.writes = 0; e.SUPERWOW_STRING = "test"
    e.WebDKP_Options = {AutoBackupEnabled=true,SelectedTableId=1}
    e.WebDKP_DkpTable = {}; e.WebDKP_Log = {}; e.SlashCmdList = {}
    e.WebDKP_Tables = {{id=1,name="一团"},{id=2,name="二团"}}
    if saved then for key, value in pairs(saved) do e[key] = copy(value) end end
    e.UnitName = function() if not e.notReady then return "Captain" end end
    e.GetRealmName = function() if not e.notReady then return "Test Realm" end end
    e.GetZoneText = function() return "测试副本" end
    e.time = function() return e.now end
    e.date = function(format, stamp) return os.date(format, stamp or e.now) end
    e.ADKP_GetTableid = function() return e.team end
    e.ADKP_ROUND = function(n, digits) local k=10^digits; return math.floor(n*k+0.5)/k end
    e.ADKP_Print = function(text) table.insert(e.messages,text) end
    e.ADKP_UpdateTableToShow = function() end
    e.ADKP_UpdateTable = function() end
    e.ADKP_UpdateLootList = function() end
    e.ADKP_Frame = {Show=function() end}
    e.ADKP_SettingsAutoBackupLabel = {SetText=function(self,text) e.label=text end}
    e.CreateFrame = function(kind, name)
        local frame = {scripts={},events={}}
        frame.SetScript = function(self,event,fn) self.scripts[event]=fn end
        frame.RegisterEvent = function(self,event) self.events[event]=true end
        e[name]=frame; return frame
    end
    e.StaticPopupDialogs = {}
    e.StaticPopup_Show = function(name)
        e.popupAttempts=(e.popupAttempts or 0)+1
        if e.busy then return nil end
        e.popup=name; e.popupText=e.StaticPopupDialogs[name].text; return {}
    end
    e.StaticPopup_Hide = function(name) if e.popup==name then e.popup=nil end end
    e.ImportFile = function(name)
        if e.readError then error("read failure") end
        return disk[name]
    end
    e.ExportFile = function(name,text)
        if (e.failData and string.find(name,"^D%-")) or (e.failPointer and string.find(name,"^P%-")) then return end
        if e.crlf then text=string.gsub(text,"\n","\r\n") end
        disk[name]=text; e.writes=e.writes+1
    end
    local function load(text)
        local f=assert(loadstring(text));setfenv(f,e);f()
    end
    load(source("ADKP/ADKP_BackupCheck.lua"))
    load(core)
    load(source("ADKP/ADKP_ShareGroups.lua"))
    load(website)
    return e
end
local function saved(e)
    local result = {}
    for _,key in ipairs({"WebDKP_Options","WebDKP_DkpTable","WebDKP_Log","WebDKP_Tables",
        "ADKP_ShareGroups","ADKP_ShareProposals","ADKP_ShareSessionBase"}) do result[key]=copy(e[key]) end
    return result
end
local function tick(e, seconds)
    e.arg1=seconds or 1.1; e.ADKP_BackupCheckFrame.scripts.OnUpdate()
end
local function login(e)
    e.event="PLAYER_LOGIN"; e.ADKP_BackupCheckFrame.scripts.OnEvent(); tick(e)
end
local function accept(e)
    assert(e.popup=="ADKP_BACKUP_RECOVERY_CONFIRM")
    e.popup=nil; e.StaticPopupDialogs.ADKP_BACKUP_RECOVERY_CONFIRM.OnAccept()
end
local function reject(e)
    assert(e.popup=="ADKP_BACKUP_RECOVERY_CONFIRM")
    e.popup=nil; e.StaticPopupDialogs.ADKP_BACKUP_RECOVERY_CONFIRM.OnCancel()
end
local function add(e, id, points, team, players)
    e.WebDKP_Log[id]={tableid=team or e.team,date=e.date("%Y-%m-%d %H:%M:%S"),
        reason=id,points=points,foritem="false",awarded=players or {["玩家甲"]={class="战士"}}}
    for name,info in pairs(e.WebDKP_Log[id].awarded) do
        e.WebDKP_DkpTable[name]=e.WebDKP_DkpTable[name] or {class=info.class}
        local field="dkp_"..(team or e.team)
        e.WebDKP_DkpTable[name][field]=(e.WebDKP_DkpTable[name][field] or 0)+points
    end
end
local function mark(e, id)
    return e.WebDKP_Options.LatestBackup[e.ADKP_BackupCharacterKey()][id or e.team]
end
local function diskUnchanged(old)
    for name,text in pairs(old) do assert(disk[name]==text,"file changed: "..name) end
    for name in pairs(disk) do assert(old[name],"unexpected new file: "..name) end
end

-- No files/no SuperWoW: one quiet login check and no automatic writes.
local A=client(); assert(not A.ADKP_BackupData(true)); login(A)
assert(A.ADKP_BackupRecovery.finished and not A.popup and A.writes==0)
local noAPI=client(); noAPI.SUPERWOW_STRING=nil; noAPI.ImportFile=nil; noAPI.ExportFile=nil
login(noAPI); assert(not noAPI.popup and noAPI.writes==0)

-- Two backups in the same second preserve both D files and create P1/P2.
A.WebDKP_DkpTable["玩家甲"]={class="战士",dkp_1=100}
add(A,"第一条",1); assert(A.ADKP_BackupData()); local first=copy(mark(A)); local stale=saved(A)
local firstData=disk[first.DataFile]
add(A,"第二条",2); assert(A.ADKP_BackupData()); local second=copy(mark(A))
assert(second.Counter==2 and second.DataFile~=first.DataFile and disk[first.DataFile]==firstData)
local healthy=saved(A)
local clean=client(healthy); login(clean)
assert(not clean.popup and clean.writes==0 and clean.ADKP_BackupRecovery.finished)

-- Same-day stale registration is detected without modifying data or files.
local before=copy(disk); local L=client(stale)
L.ADKP_SaveToDisk(); assert(L.writes==0)
login(L)
assert(L.popupText=="检测到DKP数据差异，是否恢复最新备份数据")
assert(L.WebDKP_DkpTable["玩家甲"].dkp_1==101 and mark(L).Counter==1)
assert(L.ADKP_BackupRecovery.pending.Counter==2)
diskUnchanged(before)
accept(L)
assert(L.WebDKP_DkpTable["玩家甲"].dkp_1==103 and mark(L).Counter==2 and L.writes==0)
assert(not L.ADKP_IsAutoBackupPaused())
diskUnchanged(before)
login(L); tick(L); assert(not L.popup,"repeat login event repeated prompt")

-- Even if every log already exists, success updates the marker and never adds points twice.
local allLogs=saved(A); allLogs.WebDKP_Options=copy(stale.WebDKP_Options)
local duplicates=client(allLogs); login(duplicates); accept(duplicates)
assert(duplicates.WebDKP_DkpTable["玩家甲"].dkp_1==103 and mark(duplicates).Counter==2)

-- Both the button and explicit latest-version import resolve a declined check.
local manual=client(stale);login(manual);reject(manual)
assert(manual.ADKP_RestoreData() and mark(manual).Counter==2 and not manual.ADKP_IsAutoBackupPaused())
local specific=client(stale);login(specific);reject(specific)
assert(specific.ADKP_ImportSpecificVersion(second.PointerFile..".txt"))
assert(mark(specific).Counter==2 and specific.WebDKP_DkpTable["玩家甲"].dkp_1==103 and specific.writes==0)
assert(not specific.ADKP_IsAutoBackupPaused())
diskUnchanged(before)

-- Decline persists; scoring remains possible but automatic writes are paused.
local declined=client(stale); login(declined); reject(declined)
assert(declined.ADKP_IsAutoBackupPaused() and declined.label=="自动备份（已暂停）")
assert(declined.WebDKP_Options.AutoBackupEnabled==true)
add(declined,"取消后记分",5); declined.ADKP_SaveToDisk(); tick(declined)
assert(declined.WebDKP_DkpTable["玩家甲"].dkp_1==106 and not declined.popup)
diskUnchanged(before)
local nextLogin=client(saved(declined)); login(nextLogin)
assert(nextLogin.popup and nextLogin.ADKP_IsAutoBackupPaused()); accept(nextLogin)
assert(nextLogin.WebDKP_DkpTable["玩家甲"].dkp_1==108 and not nextLogin.ADKP_IsAutoBackupPaused())
diskUnchanged(before)

-- All SavedVariables lost: discover files without registered Date/Counter.
local lost=client(); login(lost); assert(lost.popup and lost.ADKP_BackupRecovery.pending.Counter==2)
accept(lost); assert(lost.WebDKP_DkpTable["玩家甲"].dkp_1==3 and mark(lost).Counter==2)
diskUnchanged(before)

-- A registered marker later than disk still prompts: no "older backup" exclusion.
local future=saved(A); future.WebDKP_Options.LatestBackup[A.ADKP_BackupCharacterKey()][1].Counter=999
local oldDisk=client(future); login(oldDisk); assert(oldDisk.popup); reject(oldDisk)

-- An occupied popup retries without marking a confirmation as shown prematurely.
local busy=client(stale); busy.busy=true; login(busy)
assert(busy.ADKP_BackupRecovery.pending and not busy.popup and not busy.ADKP_BackupData(true))
busy.busy=false; tick(busy); assert(busy.popup); accept(busy)

-- A team switch during confirmation cannot restore into the wrong team.
local switched=client(stale); login(switched); switched.team=2; accept(switched)
assert(not switched.WebDKP_DkpTable["玩家甲"].dkp_2 and mark(switched,1).Counter==1)
assert(switched.ADKP_IsAutoBackupPaused(1) and not switched.ADKP_IsAutoBackupPaused(2))

-- Backup failure retains registration; CRLF readback verifies correctly.
local writer=client(healthy); login(writer); local registered=copy(mark(writer))
add(writer,"未写入",4); writer.failData=true
assert(not writer.ADKP_BackupData() and mark(writer).Counter==registered.Counter)
writer.failData=false; writer.failPointer=true
assert(not writer.ADKP_BackupData() and mark(writer).DataFile==registered.DataFile)
writer.failPointer=false; writer.crlf=true
assert(writer.ADKP_BackupData() and mark(writer).Counter==3)
assert(writer.ADKP_RestoreData()==true and writer.WebDKP_DkpTable["玩家甲"].dkp_1==107)

-- Invalid newest CSV falls back; malformed rows cannot partially restore.
local third=copy(mark(writer)); local good=disk[third.DataFile]
disk[third.DataFile]="类型,日期,时间,分值,项目,玩家列表\nD,2026-10-14,20:00:00,oops,坏记录,玩家甲:战士"
assert(writer.ADKP_FindLatestBackup().Counter==2)
assert(not writer.ADKP_RestoreFromData(disk[third.DataFile],third.DataFile))
assert(writer.WebDKP_DkpTable["玩家甲"].dkp_1==107)
assert(not writer.ADKP_ValidateBackupCSV("类型,日期,时间,分值,项目,玩家列表\nD,2026-10-14,20:00:00,1,坏名单,;"))
assert(writer.ADKP_ValidateBackupCSV("类型,日期,时间,分值,项目,玩家列表\nD,2026-10-14,20:00:00,1,无人参与日志,"))
disk[third.DataFile]=good

-- Missing/changed selected file after prompting cannot update the marker.
local deleted=client(stale); login(deleted); local chosen=deleted.ADKP_BackupRecovery.pending
local selected=disk[chosen.DataFile];disk[chosen.DataFile]=nil
accept(deleted); assert(mark(deleted).Counter==1 and deleted.ADKP_IsAutoBackupPaused())
disk[chosen.DataFile]=selected

-- Cross-team duplicates must not hide the current team's missing log.
disk={};local multi=client();login(multi)
add(multi,"共同事件",1);assert(multi.ADKP_BackupData());local multiSaved=saved(multi)
multiSaved.WebDKP_Log["共同事件"].tableid=2
multiSaved.WebDKP_DkpTable["玩家甲"]={class="战士",dkp_1=0,dkp_2=222}
multiSaved.WebDKP_Options.LatestBackup={}
multi=client(multiSaved);login(multi);accept(multi)
assert(multi.WebDKP_DkpTable["玩家甲"].dkp_1==1 and multi.WebDKP_DkpTable["玩家甲"].dkp_2==222)

-- Shared-player metadata is applied before recovery is marked successful.
disk={};local shared=client();login(shared)
shared.WebDKP_DkpTable={ ["主号"]={class="战士",dkp_1=100},["小号"]={class="法师",dkp_1=100} }
shared.ADKP_ShareGroups[1]={["小号"]="主号"};shared.ADKP_ShareSessionBase[1]={["主号"]=100,["小号"]=100}
add(shared,"共享奖励",2,1,{["主号"]={class="战士"},["小号"]={class="法师"}})
assert(shared.ADKP_BackupData())
local sharedLost=client();login(sharedLost);accept(sharedLost)
assert(sharedLost.WebDKP_DkpTable["主号"].dkp_1==102 and sharedLost.WebDKP_DkpTable["小号"].dkp_1==102)
assert(sharedLost.ADKP_ShareGroups[1]["小号"]=="主号")

-- An explicit website import starts a fresh round and resolves a declined recovery.
local reset=client();login(reset);reject(reset)
reset.ADKP_DoImportInitial("新玩家,战士,88")
reset.StaticPopupDialogs.ADKP_IMPORT_INITIAL_CONFIRM.OnAccept()
assert(not reset.ADKP_IsAutoBackupPaused() and reset.WebDKP_DkpTable["新玩家"].dkp_1==88)
assert(mark(reset).Counter==2 and reset.writes>0)
local afterReset=client(saved(reset));login(afterReset);assert(not afterReset.popup)

-- Legacy pointer and prior-day lookup remain supported.
disk={};local legacy=client();login(legacy);add(legacy,"旧日志",1);assert(legacy.ADKP_BackupData())
local entry=copy(mark(legacy));local contents=disk[entry.DataFile]
disk={};disk["P-TestRealm-Captain-2026-10-14-1"]=entry.DataFile;disk[entry.DataFile]=contents
local prior=client();prior.now=prior.now+86400;login(prior)
assert(prior.popup and prior.ADKP_BackupRecovery.pending.Date=="2026-10-14");accept(prior)
assert(prior.WebDKP_DkpTable["玩家甲"].dkp_1==1 and mark(prior).Counter==1)
print("Backup/login recovery PASS: quiet check, same-day newest, missing markers, confirm/cancel, persistent pause, dedup, team isolation, shared metadata, no restore-generated backups, write failures, CRLF, invalid-file fallback, popup retry, explicit website reset, legacy/prior-day files")
