-- Appended to the shared Lua 5.0 client fixture by run_backup_tests.py.
local C
local function variables(e)
    local result = {}
    for _, key in ipairs({"WebDKP_Options", "WebDKP_DkpTable", "WebDKP_Log", "WebDKP_Tables",
        "WebDKP_DailySubRecords", "WebDKP_LootHistory", "WebDKP_Loot", "WebDKP_WebOptions",
        "ADKP_ShareGroups", "ADKP_ShareProposals", "ADKP_ShareSessionBase", "ADKP_SyncStore", "ADKP_BackupStore"}) do
        result[key] = C.Copy(e[key])
    end
    return result
end
local function reject(e)
    assert(e.popup == "ADKP_DATA_SYNC_CONFIRM", "missing recovery prompt")
    e.popup = nil; e.StaticPopupDialogs.ADKP_DATA_SYNC_CONFIRM.OnCancel()
end
local function countData(name)
    local count = 0
    for file in pairs(disk[name]) do if string.find(file, "^D%-") then count = count + 1 end end
    return count
end
local A = client("本地记分员")
C = A.ADKP_SyncCodec
website(A, "底分玩家,战士,100\n无活动玩家,牧师,77.5\n主号,盗贼,50,主号\n小号,法师,50,主号")
run(15)
assert(A.ADKP_BackupData())
local original = A.ADKP_Backup.ReadLatest(1)
assert(original, "latest full backup not readable")
assert(original.data.players["无活动玩家"] and original.data.players["无活动玩家"].dkp == 77.5, "idle player omitted")
assert(original.data.bases["底分玩家"] == 100, "initial base omitted: " .. tostring(original.data.bases["底分玩家"]))
assert(next(original.data.logs) == nil, "website-only backup requires logs")
-- New files carry one compressed full snapshot, plus an outstanding baseline.
local compressed = disk["本地记分员"][original.file]
assert(string.sub(compressed,1,13)=="ADKP-BACKUP3:")
local compact = C.Unpack(C.WireDecode(string.sub(compressed,14)))
assert(compact.payload.schema==3 and compact.payload.sync.snapshot==nil)
assert(compact.payload.sync.baseline and compact.payload.sync.pendingReset,
    "unsynchronized website baseline was discarded")
assert(C.Pack(original.sync.snapshot)==C.Pack(original.data), "disk snapshot was not rehydrated")
local legacyPayload=C.Copy(original); legacyPayload.file=nil
local legacy="ADKP-BACKUP2:"..C.Escape(C.Pack({payload=legacyPayload,checksum=C.Hash(C.Pack(legacyPayload))}))
assert(A.ADKP_Backup.Decode(legacy,1), "previous complete backups no longer readable")
assert(string.len(compressed)<string.len(legacy), "compression did not reduce backup size")
local bad=C.Copy(compact); bad.payload.data.players["底分玩家"].dkp=999
assert(not A.ADKP_Backup.Decode("ADKP-BACKUP3:"..C.WireEncode(C.Pack(bad)),1), "bad checksum accepted")
bad.checksum=C.Hash(C.Pack(bad.payload))
assert(not A.ADKP_Backup.Decode("ADKP-BACKUP3:"..C.WireEncode(C.Pack(bad)),1), "bad business hash accepted")
assert(not A.ADKP_Backup.Decode("ADKP-BACKUP3:Z!",1), "malformed compression accepted")
-- No index, checkpoint, peer, or preceding file is needed for version restore.
local allFiles=disk["本地记分员"]
disk["本地记分员"]={[original.file]=compressed}
A.WebDKP_DkpTable["底分玩家"].dkp_1=0
assert(A.ADKP_ImportSpecificVersion(original.file))
assert(A.WebDKP_DkpTable["底分玩家"].dkp_1==100)
disk["本地记分员"]=allFiles
local firstReset = original.meta.reset
local healthy = variables(A)
clients = {}; A = client("本地记分员", healthy); run(15)
assert(not A.popup and A.ADKP_DataSyncCanWrite(true), "healthy login offered recovery")

-- Corrupt live data while retaining its old version, including an unrelated team.
healthy.WebDKP_DkpTable["底分玩家"].dkp_1 = 0
healthy.WebDKP_Tables[2] = {id=2,name="其他团"}
healthy.WebDKP_DkpTable["其他团玩家"] = {class="战士",dkp_2=222}
healthy.WebDKP_DkpTable["底分玩家"].dkp_2 = 333
healthy.WebDKP_Log.other = {tableid=2,date="2026-10-13 12:00:00",points=5,awarded={},uniqueId="other"}
healthy.WebDKP_DailySubRecords[day] = {{tableid=2,name="其他替补",points=5,uniqueId="other"}}
healthy.WebDKP_LootHistory = {{tableid=2,reason="其他团装备",uniqueId="other"}}
healthy.ADKP_ShareGroups[2] = { ["其他小号"]="其他主号" }
healthy.WebDKP_Options.QuickFloatSettings = { position={x=321,y=123} }
clients = {}; A = client("本地记分员", healthy); run(14)
assert(A.popupText == "检测到DKP记录异常，是否恢复自动备份的数据")
assert(A.StaticPopupDialogs.ADKP_DATA_SYNC_CONFIRM.button1=="是" and A.StaticPopupDialogs.ADKP_DATA_SYNC_CONFIRM.button2=="否")
assert(not A.ADKP_DataSyncCanWrite(true))
local beforeFiles = C.Pack(disk["本地记分员"])
reject(A)
assert(A.ADKP_DataSyncCanWrite(true) and A.ADKP_Backup.IsSuspended())
A.ADKP_AddDKP(3,"拒绝后继续记分","false",{{name="底分玩家",class="战士"}})
A.ADKP_SaveToDisk(); run(20)
assert(A.WebDKP_DkpTable["底分玩家"].dkp_1 == 3)
assert(C.Pack(disk["本地记分员"]) == beforeFiles, "declined recovery overwrote protected files")
assert(not A.popup, "same recovery repeated")
local afterDecline = variables(A)
clients = {}; A = client("本地记分员", afterDecline); run(14)
assert(A.ADKP_Backup.IsSuspended() and A.popup, "protection did not persist across login")
local beforeRestore = countData("本地记分员")
accept(A); run(15)
assert(A.WebDKP_DkpTable["底分玩家"].dkp_1 == 100 and A.WebDKP_DkpTable["无活动玩家"].dkp_1 == 77.5)
assert(A.WebDKP_DkpTable["底分玩家"].dkp_2 == 333 and A.WebDKP_DkpTable["其他团玩家"].dkp_2 == 222)
assert(A.WebDKP_Log.other and A.WebDKP_DailySubRecords[day][1].name == "其他替补")
assert(A.WebDKP_LootHistory[1].reason == "其他团装备" and A.ADKP_ShareGroups[2]["其他小号"] == "其他主号")
assert(A.WebDKP_Options.QuickFloatSettings.position.x == 321, "appearance overwritten")
assert(not A.ADKP_Backup.IsSuspended() and countData("本地记分员") == beforeRestore, "restore produced a new backup")

-- Manual version restore replaces extra players/logs; it never replays awards.
A.ADKP_AddDKP(5,"后续活动","false",{{name="底分玩家",class="战士"}}); run(2)
A.WebDKP_DkpTable["额外成员"]={class="牧师",dkp_1=9}
assert(A.ADKP_ImportSpecificVersion(original.file))
assert(A.WebDKP_DkpTable["底分玩家"].dkp_1==100 and not A.WebDKP_DkpTable["额外成员"].dkp_1)
assert(next(A.ADKP_SyncData.Capture(1).logs)==nil, "old logs merged instead of replaced")
local live = C.Pack(A.ADKP_SyncData.Capture(1))
assert(not A.ADKP_ImportSpecificVersion("missing"))
assert(not A.ADKP_RestoreFromData("类型,日期,时间,分值,项目,玩家列表\nD,x,x,999,x,底分玩家:战士"))
assert(live == C.Pack(A.ADKP_SyncData.Capture(1)), "old or bad file changed live database")

-- Failed snapshot writes do not publish a new pointer; corrupt latest falls back.
local valid = A.ADKP_Backup.ReadLatest(1)
local pointerBefore = {}
for file,text in pairs(disk["本地记分员"]) do if string.find(file,"^P%-") then pointerBefore[file]=text end end
local export = A.ExportFile
A.ExportFile=function(file,text) if not string.find(file,"^D%-") then export(file,text) end end
A.WebDKP_DkpTable["底分玩家"].dkp_1=111
assert(not A.ADKP_BackupData())
for file,text in pairs(pointerBefore) do assert(disk["本地记分员"][file]==text, "failed snapshot published pointer") end
A.ExportFile=export
assert(A.ADKP_BackupData())
local latest = A.ADKP_Backup.ReadLatest(1)
disk["本地记分员"][latest.file]="ADKP-BACKUP3:broken"
assert(A.ADKP_Backup.ReadLatest(1).serial == valid.serial, "bad latest did not use previous slot")

-- Deliberate website import advances the round and re-enables backup.
A.ADKP_Backup.Decline(1)
website(A,"新活动玩家,战士,200"); run(3)
assert(not A.ADKP_Backup.IsSuspended() and not A.popup)
latest = A.ADKP_Backup.ReadLatest(1)
assert(latest and latest.meta.reset ~= firstReset and latest.data.players["新活动玩家"].dkp==200)
assert(A.WebDKP_Log.other and A.WebDKP_DailySubRecords[day][1].name=="其他替补", "website reset erased another team")
assert(A.ADKP_ImportSpecificVersion(latest.file .. ".txt"), "txt suffix not accepted")

-- Offline, no-guild login still checks and restores the full initial roster.
clients = {}; A = client("本地记分员"); A.GetGuildInfo=function() return nil end
A.popupBusy=true; run(14); assert(not A.popup and A.ADKP_DataSync.activePrompt)
A.popupBusy=false; run(2)
assert(A.popupText == "检测到DKP记录异常，是否恢复自动备份的数据")
accept(A); assert(A.WebDKP_DkpTable["新活动玩家"].dkp_1==200)

-- Peer has a newer valid version: one peer prompt, no prior local popup.
clients = {}; local P, Q = client("优先团长"), client("优先替补")
website(P,"玩家甲,战士,100"); P.ADKP_SetSubCaptain(1,"优先替补"); P.ADKP_DataSyncEnable(true)
run(20); accept(Q); run(30)
local oldDisk = C.Copy(disk["优先团长"])
P.ADKP_AddDKP(7,"最新活动","false",{{name="玩家甲",class="战士"}}); run(15)
disk["优先团长"]=oldDisk; clients["优先团长"]=nil
P=client("优先团长"); run(20)
assert(string.find(P.popupText,"是否从替补队长",1,true), "newer peer lost to older local backup")
accept(P); run(40)
assert(P.WebDKP_DkpTable["玩家甲"].dkp_1==107 and not P.popup)

-- Same version can recover from local storage without downloading a full message.
clients["优先团长"]=nil; P=client("优先团长"); run(20)
assert(P.popupText=="检测到DKP记录异常，是否恢复自动备份的数据")
beforeFiles = wireBytes; accept(P); run(20)
assert(P.WebDKP_DkpTable["玩家甲"].dkp_1==107 and wireBytes-beforeFiles<2000)

-- A later peer response after decline still needs consent and can then complete.
clients["优先团长"]=nil; P=client("优先团长"); run(20); reject(P)
P.ADKP_AddDKP(3,"拒绝后的本地操作","false",{{name="玩家甲",class="战士"}})
local protected = C.Pack(disk["优先团长"])
Q.WebDKP_DkpTable["玩家甲"].dkp_1=109
local replica = Q.ADKP_SyncData.State()
replica.snapshot = C.Copy(replica.snapshot); replica.snapshot.players["玩家甲"].dkp=109
replica.meta = C.Copy(replica.meta); replica.meta.seq=replica.meta.seq+1
replica.meta.hash=C.Hash(C.Pack(replica.snapshot))
Q.ADKP_SyncData.WriteFile(replica)
run(75)
assert(P.popup and P.WebDKP_DkpTable["玩家甲"].dkp_1==3, "late peer silently replaced new scoring")
assert(C.Pack(disk["优先团长"])==protected, "declined peer recovery changed files")
accept(P); run(30)
assert(P.WebDKP_DkpTable["玩家甲"].dkp_1==109, "explicit late recovery did not complete")

-- Equal revision but different content is an anomaly, not a local fast path.
clients["优先团长"]=nil
Q.WebDKP_DkpTable["玩家甲"].dkp_1=110
replica.snapshot=C.Copy(replica.snapshot); replica.snapshot.players["玩家甲"].dkp=110
replica.meta=C.Copy(replica.meta); replica.meta.hash=C.Hash(C.Pack(replica.snapshot))
Q.ADKP_SyncData.WriteFile(replica)
P=client("优先团长"); run(20)
assert(string.find(P.popupText,"是否从替补队长",1,true), "same revision content mismatch was ignored")
accept(P); run(30); assert(P.WebDKP_DkpTable["玩家甲"].dkp_1==110)

-- Re-pairing after solo changes must offer the current full database, not an old baseline.
P.ADKP_DataSyncEnable(false); run(3)
P.ADKP_AddDKP(2,"断开后记分","false",{{name="玩家甲",class="战士"}}); run(2)
P.ADKP_DataSyncEnable(true); run(20); accept(Q); run(30)
assert(Q.WebDKP_DkpTable["玩家甲"].dkp_1==112, "re-pair used a stale baseline")
assert(Q.ADKP_BackupData())
local replicaBackup = Q.ADKP_Backup.ReadLatest(1)
assert(replicaBackup.meta.master=="优先团长" and replicaBackup.sync.role=="slave" and replicaBackup.sync.peer=="优先团长",
    "replica-local settings promoted a backup to master")
clients["优先替补"]=nil
local qkey=string.gsub(C.Hash("TestRealm:优先替补"),":","-")
disk["优先替补"]["ADKP-SYNC-"..qkey.."-0"]=nil
disk["优先替补"]["ADKP-SYNC-"..qkey.."-1"]=nil
Q=client("优先替补"); run(15)
assert(Q.ADKP_SyncData.State().role=="slave" and Q.WebDKP_DkpTable["玩家甲"].dkp_1==112,
    "replica D file lost its role or business data")
P.ADKP_DataSyncEnable(false)
P.ADKP_AddDKP(4,"退出前最后一条","false",{{name="玩家甲",class="战士"}})
P.event="PLAYER_LOGOUT"; P.ADKP_DataSyncEventFrame.scripts.OnEvent()
assert(P.ADKP_Backup.ReadLatest(1).data.players["玩家甲"].dkp==116, "logout did not flush the final solo operation")
local normalExit=variables(P); clients["优先团长"]=nil
P=client("优先团长",normalExit); run(15)
assert(not P.popup and P.WebDKP_DkpTable["玩家甲"].dkp_1==116, "normal exit misdetected as corruption")

-- Compaction must retain a baseline until the complete current state is ACKed.
local S=P.ADKP_SyncData; local state=C.Copy(S.State())
state.baseline={data=C.Copy(state.snapshot),meta=C.Copy(state.meta)}
state.pendingReset=false; state.remoteAccepted=state.meta.reset
state.remoteAck=C.Copy(state.meta); state.remoteAck.seq=state.meta.seq-1
assert(S.CompactFileState(state).baseline and state.baseline)
state.remoteAck=C.Copy(state.meta)
assert(not S.CompactFileState(state).baseline and state.baseline,
    "finished baseline not trimmed, or live state mutated")
assert(S.WriteFile(state))
local newState=S.ReadFiles()
assert(newState and not newState.baseline and S.Equal(newState.meta,state.meta))
local key=string.gsub(C.Hash(S.Identity()),":","-")
local newText=disk["优先团长"]["ADKP-SYNC-"..key.."-"..math.mod(state.fileSerial,2)]
assert(string.sub(newText,1,11)=="ADKP-SYNC2:")
local previous=C.Copy(newState); previous.fileSerial=previous.fileSerial+1
local oldSync="ADKP-SYNC1:"..C.Escape(C.Pack({state=previous,checksum=C.Hash(C.Pack(previous))}))
disk["优先团长"]["ADKP-SYNC-"..key.."-"..math.mod(previous.fileSerial,2)]=oldSync
assert(S.ReadFiles().fileSerial==previous.fileSerial, "previous checkpoint format not readable")

-- Even the list of teams can be lost; the independent catalog finds team 2.
clients = {}; local T = client("二团记分员")
T.WebDKP_Tables[2]={id=2,name="第二团"}; T.ADKP_Frame.selectedTableid=2
website(T,"二团玩家,牧师,88"); run(15); assert(T.ADKP_BackupData())
clients={}; disk["二团记分员"]["ADKP-SYNC-"..string.gsub(C.Hash("TestRealm:二团记分员"),":","-").."-0"]=nil
disk["二团记分员"]["ADKP-SYNC-"..string.gsub(C.Hash("TestRealm:二团记分员"),":","-").."-1"]=nil
T=client("二团记分员"); run(14)
assert(T.popup and string.find(T.popupText,"第二团",1,true), "lost team catalog not recovered")
accept(T)
assert(T.ADKP_GetTableid()==2 and T.WebDKP_DkpTable["二团玩家"].dkp_2==88)
clients={}; local Sparse=client("稀疏记录测试")
website(Sparse,"测试玩家,战士,10"); run(15)
Sparse.WebDKP_DailySubRecords[day]={
    [2]={tableid=1,name="稀疏替补",points=1},
    ["姓名键"]={tableid=1,points=2}
}
assert(Sparse.ADKP_BackupData())
local sparseFile=Sparse.ADKP_Backup.ReadLatest(1)
assert(table.getn(sparseFile.data.daily[day])==2 and sparseFile.data.daily[day][2].name=="姓名键",
    "sparse or name-keyed daily records omitted")
Sparse.WebDKP_DailySubRecords={}
assert(Sparse.ADKP_Backup.Apply(sparseFile) and table.getn(Sparse.WebDKP_DailySubRecords[day])==2)
print("Backup regression PASS: complete initial bases/idle players, replacement, team isolation, version/checksum, failed writes, local/peer priority, decline persistence, offline recovery, no recovery-generated backup")
