"""Reproduce the supplied 12-player raid using the actual Lua 5.0 addon paths."""
import argparse
import json
from pathlib import Path
import subprocess
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument('--lua', required=True, help='Lua 5.0 interpreter')
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
output = root / 'docs/simulations/12-player-raid-compact'
output.mkdir(parents=True, exist_ok=True)
(output / 'imports').mkdir(exist_ok=True)
(output / 'import.csv').write_bytes((root / 'docs/simulations/12-player-raid/import.csv').read_bytes())
fixture = (root / 'tests/sync_spec.lua').read_text(encoding='utf-8')
fixture = fixture[:fixture.index('local A, B = client(')]
injection = '''
    -- Install actual CSV builder/restore before ShareGroups captures them.
    local function mainFunction(first, following)
        local a = assert(string.find(main, first, 1, true))
        local b = assert(string.find(main, following, a, true))
        local f = assert(loadstring(string.sub(main, a, b - 1)))
        setfenv(f, e); f()
    end
    mainFunction("function ADKP_BuildBackupCSV(", "-- 完整本地备份及恢复入口")
    mainFunction("function ADKP_NormalizeClassName(", "local function ADKP_GetSubMembersForAward(")
    e.ADKP_Frame.Show = function() end
'''
needle = '    for _, file in ipairs({ "ADKP_SyncCodec.lua"'
assert fixture.count(needle) == 1
fixture = fixture.replace(needle, injection + needle, 1)

scenario = r'''
day = "2026-10-14"
local folder = "docs/simulations/12-player-raid-compact/"
local function write(name, content)
    local f = assert(io.open(folder .. name, "wb")); f:write(content); f:close()
end
local function quoted(value)
    local parts = { string.char(34) }
    for i = 1, string.len(value) do
        local byte = string.byte(value, i)
        if byte == 34 or byte == 92 then table.insert(parts, string.char(92, byte))
        elseif byte < 32 then table.insert(parts, string.char(92) .. string.format("u%04x", byte))
        else table.insert(parts, string.char(byte)) end
    end
    table.insert(parts, string.char(34))
    return table.concat(parts)
end
assert(quoted(string.char(34)) == string.char(34,92,34,34))
assert(quoted(string.char(92)) == string.char(34,92,92,34))
assert(quoted(string.char(10)) == '"' .. string.char(92) .. 'u000a"')
local function json(value)
    if type(value) == "string" then return quoted(value) end
    if type(value) == "number" then return string.format("%.17g", value) end
    if type(value) == "boolean" then return value and "true" or "false" end
    if value == nil then return "null" end
    local keys, array = ADKP_SyncCodec and ADKP_SyncCodec.Keys(value), true
    -- Codec is isolated inside clients; deterministic keys can use A's codec.
    if not keys then
        keys = {}; for key in pairs(value) do table.insert(keys, key) end
        table.sort(keys, function(a,b)
            if type(a) ~= type(b) then return type(a) == "number" end
            return a < b
        end)
    end
    for i,key in ipairs(keys) do if key ~= i then array = false end end
    if table.getn(keys) == 0 then array = false end
    local parts = {}
    for _,key in ipairs(keys) do
        table.insert(parts, (array and "" or quoted(tostring(key)) .. ":") .. json(value[key]))
    end
    return (array and "[" or "{") .. table.concat(parts, ",") .. (array and "]" or "}")
end
local A,B=client("模拟记分员"),client("模拟替补队长")
A.WebDKP_Tables[1].name="模拟主团"
A.GetZoneText=function() return "熔火之心（模拟）" end
A.ADKP_GetGuildName=function() return "模拟公会" end
local input=read(folder .. "import.csv")
website(A,input)
local C=A.ADKP_SyncCodec
write("initial-snapshot.json",json(A.ADKP_SyncData.State().snapshot))
local roster={}
for line in string.gfind(input,"[^\r\n]+") do
    local _,_,name,class=string.find(line,"^([^,]+),([^,]+),")
    table.insert(roster,{name=name,class=class})
end
A.ADKP_GetAllRaidMembers=function() return roster end
A.ADKP_GetSubMembersForAward=function() return {},0 end
A.GetNumRaidMembers=function() return 12 end
A.ADKP_SetSubCaptain(1,"模拟替补队长")
A.ADKP_DataSyncEnable(true)
run(20);accept(B);run(30);same(A,B)
local bosses={"鲁西弗隆","玛格曼达","基赫纳斯","加尔","迦顿男爵",
    "沙斯拉尔","因辛迪斯","萨弗隆先驱者","焚化者古雷曼格","拉格纳罗斯"}
local operations={}
local function allocate(buyer,item,cost,date)
    local class=A.WebDKP_DkpTable[buyer].class
    A.ADKP_AddDKP(-cost,item,"true",{{name=buyer,class=class}},nil,date)
    table.insert(operations,{kind="loot",date=date,item=item,buyer=buyer,points=-cost})
end
for i,boss in ipairs(bosses) do
    local date="2026-10-14 20:" .. string.format("%02d",i*4) .. ":00"
    A.ADKP_TestApply(1,0,"击杀-"..boss,date,{boss=boss})
    table.insert(operations,{kind="boss",date=date,boss=boss,points=1,players=12})
    if i==3 then allocate("Xinian","模拟物品-匕首",15,"2026-10-14 20:13:00") end
    if i==5 then allocate("认养一头母牛","模拟物品-治疗饰品",10,"2026-10-14 20:21:00") end
    if i==8 then allocate("大头沙皮狗","模拟物品-盾牌",8,"2026-10-14 20:33:00") end
    run(8);same(A,B)
end
run(10);same(A,B)
local expected={
    ["年年有术"]=64.85,["Xinian"]=64.85,["大头沙皮狗"]=66.81,
    ["牛团"]=74.80,["雨爷"]=73.90,["何惕手"]=70.92,["Deepsleepy"]=70.24,
    ["追到你就惨了"]=59.39,["晚上吃肘子"]=59.39,["认养一头母牛"]=59.39,
    ["泰兰徳羽月"]=68.43,["凶甚"]=67.32}
for name,points in pairs(expected) do assert(A.WebDKP_DkpTable[name].dkp_1==points,name.." score differs") end
local logCount=0
for _,entry in pairs(A.ADKP_SyncData.State().snapshot.logs) do logCount=logCount+1 end
assert(logCount==13 and table.getn(A.ADKP_GetBossAutoAwardRecords())==10)
local backup=A.ADKP_BuildBackupCSV(true)
assert(string.find(backup,"#ADKP_SHARE_BASE,牛团,64.8",1,true))
write("activity-export.csv",backup)
local originalDate=A.date
A.date=function(format)
    if format=="%Y-%m-%d-%H%M%S" then return "2026-10-14-204000" end
    return originalDate(format)
end
A.ADKP_BackupData(false)
write("operations.json",json(operations))
write("final-snapshot.json",json(A.ADKP_SyncData.State().snapshot))
write("boss-auto-records.json",json(A.ADKP_GetBossAutoAwardRecords()))
-- Exercise the real logout checkpoint: SavedVariables are deliberately absent.
A.event="PLAYER_LOGOUT";A.ADKP_DataSyncEventFrame.scripts.OnEvent()
local checkpoint=A.ADKP_SyncData.ReadFiles()
assert(checkpoint and checkpoint.snapshot.players["牛团"].dkp==74.8)
write("decoded-checkpoint.json",json(checkpoint))
write("exported-files.json",json(disk["模拟记分员"]))
local names,reverse=A.ADKP_SyncData.Dictionary(checkpoint.snapshot,checkpoint.names)
local packed=C.Pack({kind="FULL",request="",meta=checkpoint.meta,names=names,body=C.Pack(checkpoint.snapshot,reverse)})
local wire=C.WireEncode(packed)
write("full-message-wire.txt",wire)
local measure={snapshotBytes=string.len(C.Pack(checkpoint.snapshot)),messageBytes=string.len(packed),
    oldEscapedBytes=string.len(C.Escape(packed)),wireBytes=string.len(wire),encoding=string.sub(wire,1,1),
    checkpointSerial=checkpoint.fileSerial,version=checkpoint.meta.day.."/"..checkpoint.meta.seq}
local localFile=A.ADKP_Backup.ReadLatest(1)
local oldPayload=C.Copy(localFile);oldPayload.file=nil
oldPayload.sync=C.Copy(A.ADKP_SyncData.State());oldPayload.sync.journal={}
local oldText="ADKP-BACKUP2:"..C.Escape(C.Pack({payload=oldPayload,checksum=C.Hash(C.Pack(oldPayload))}))
measure.oldBackupBytes=string.len(oldText)
measure.backupBytes=string.len(disk["模拟记分员"][localFile.file])
measure.backupFile=localFile.file
-- Wipe A's live database and restore through discovery + exact local checkpoint.
clients["模拟记分员"]=nil
A=client("模拟记分员");run(15);accept(A);run(12);same(A,B)
for name,points in pairs(expected) do assert(A.WebDKP_DkpTable[name].dkp_1==points,"checkpoint restore "..name) end
write("full-restore-snapshot.json",json(A.ADKP_SyncData.State().snapshot))
-- A current D file independently restores the complete database, without a peer.
local fullBackup=A.ADKP_Backup.ReadLatest(1)
assert(fullBackup and fullBackup.data.bases["牛团"]==64.8)
local Local=client("模拟记分员")
assert(Local.ADKP_Backup.Apply(fullBackup))
local comparison={}
for name,points in pairs(expected) do
    comparison[name]={expected=points,full=A.WebDKP_DkpTable[name].dkp_1,
        localBackup=Local.WebDKP_DkpTable[name].dkp_1,base=checkpoint.snapshot.bases[name]}
    assert(comparison[name].localBackup==points)
end
write("restore-comparison.json",json(comparison))
write("metrics.json",json(measure))
print("12-player simulation PASS: 10 Boss awards, 3 item deductions, shared balances, complete file recovery")
print("New D backup independently restored every current score and original base")
'''
with tempfile.TemporaryDirectory(prefix='adkp-raid-example-') as directory:
    lua_file = Path(directory) / 'simulate.lua'
    lua_file.write_text(fixture + scenario, encoding='utf-8')
    subprocess.run([args.lua, str(lua_file)], cwd=root, check=True)

for path in output.glob('*.json'):
    data = json.loads(path.read_text(encoding='utf-8'))
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
exported = json.loads((output / 'exported-files.json').read_text(encoding='utf-8'))
for name, content in exported.items():
    (output / 'imports' / (name + '.txt')).write_bytes(content.encode('utf-8'))
initial = json.loads((output / 'initial-snapshot.json').read_text(encoding='utf-8'))
final = json.loads((output / 'final-snapshot.json').read_text(encoding='utf-8'))
comparison = json.loads((output / 'restore-comparison.json').read_text(encoding='utf-8'))
metrics = json.loads((output / 'metrics.json').read_text(encoding='utf-8'))
operations = json.loads((output / 'operations.json').read_text(encoding='utf-8'))
names = [line.split(',')[0] for line in (output / 'import.csv').read_text(encoding='utf-8').splitlines()]
report = ['# 12 人 DKP 活动数据模拟', '',
          '使用用户提供的四列网站数据，运行当前插件的真实网站导入、大小号共享、Boss 奖分、装备扣分、通讯和恢复函数。客户端事件、界面、时间和 SuperWoW 文件 API 使用测试模拟；没有读写真实游戏目录。', '',
          '模拟条件：12 人均在主团，替补名单为空；10 个 Boss 各加 1 分；Xinian 购买匕首扣 15 分，认养一头母牛购买治疗饰品扣 10 分，大头沙皮狗购买盾牌扣 8 分。物品名称和日期为模拟设定，第四列账户归属沿用输入。', '',
          '## 分数结果', '', '| 玩家 | 导入底分 | Boss 加分 | 共享账户装备扣分 | 最终 DKP |', '| --- | ---: | ---: | ---: | ---: |']
for name in names:
    base = initial['bases'][name]
    current = final['players'][name]['dkp']
    deduction = round(current - base - 10, 2)
    if deduction == 0:
        deduction = 0.0
    report.append(f'| {name} | {base:.2f} | +10.00 | {deduction:.2f} | {current:.2f} |')
report += ['', '年年有术与 Xinian 共用同一账户；追到你就惨了、晚上吃肘子、认养一头母牛共用同一账户。因此同场 Boss 奖分每个共享账户只算一次，装备扣分会反映到该组所有角色。网站已经共享的底分不会重复相加。', '',
           '## 活动顺序', '', '| 时间 | 类型 | 内容 | 分值 |', '| --- | --- | --- | ---: |']
for event in operations:
    content = event['boss'] if event['kind'] == 'boss' else event['item'] + ' → ' + event['buyer']
    report.append(f"| {event['date']} | {'Boss' if event['kind']=='boss' else '物品'} | {content} | {event['points']:+.2f} |")
report += ['', '## 生成的数据', '',
           '- [导入原文](import.csv)', '- [导入完成时完整业务数据](initial-snapshot.json)',
           '- [13 次操作后的完整业务数据](final-snapshot.json)',
           '- [本地文件解码后的完整状态](decoded-checkpoint.json)',
           '- [CSV 文本导出（不用于恢复）](activity-export.csv)',
           '- [Boss 自动加分记录](boss-auto-records.json)',
           '- [恢复结果对比](restore-comparison.json)',
           '- [完整消息编码内容](full-message-wire.txt)', '',
           f"快照业务版本为 `{metrics['version']}`。修订号包含导入、同步对象配置和 13 次活动操作，不等于活动记录条数。", '',
           f"完整业务数据打包为 {metrics['snapshotBytes']} 字节；完整通讯消息为 {metrics['messageBytes']} 字节。旧百分号转义为 {metrics['oldEscapedBytes']} 字节，当前最短编码为 {metrics['wireBytes']} 字节（{metrics['encoding']}），未包括分片包头和确认消息。", '',
           f"同一份数据按原完整备份格式保存为 {metrics['oldBackupBytes']} 字节；当前独立 D 文件为 {metrics['backupBytes']} 字节，减少 {100 * (1 - metrics['backupBytes'] / metrics['oldBackupBytes']):.1f}%。每个 D 文件均能独立恢复，不依赖此前文件。", '',
           '原始 `D-…txt` 与 `ADKP-SYNC-…-0/1.txt` 是实际调用插件保存函数生成的模拟 SuperWoW 文件，使用可逆压缩保存身份、版本、完整快照、同步关系和校验值。首次同步尚未确认时保留初始基准；对端已确认完整当前版本后不再重复保存旧基准。文件中的操作队列为空，但活动日志完整保存在 snapshot.logs 中。身份是 TestRealm 的模拟角色，不能用于真实角色直接恢复。JSON 为解码后供人阅读的展示文件。', '']
for path in sorted((output / 'imports').glob('*.txt')):
    report.append(f'- [{path.name}](imports/{path.name})：{path.stat().st_size} 字节')
report += ['', '## 实际恢复验证', '',
           '完整快照：清空记分员客户端的业务数据与 SavedVariables，保留独立本地文件，经过恢复确认后，全部 12 人分数、13 条日志、原始底分及大小号关系一致。', '',
           '新版 D 文件包含全量快照，验证从空数据库独立恢复所有玩家总分、网站底分、大小号关系、日志和记分设置。旧 CSV 不再作为恢复格式。', '',
           '| 玩家 | 正确最终分 | 同步快照恢复 | 新版 D 文件恢复 |', '| --- | ---: | ---: | ---: |']
for name in names:
    c = comparison[name]
    report.append(f"| {name} | {c['expected']:.2f} | {c['full']:.2f} | {c['localBackup']:.2f} |")
report += ['', '两种完整快照均恢复正确，不通过重放活动日志计算总分。', '',
           '## 关键数据片段', '', '完整业务数据同时保存当前总分与原始底分：', '', '```json',
           json.dumps({'players': {'牛团': final['players']['牛团']}, 'bases': {'牛团': final['bases']['牛团']}, 'groups': final['groups']}, ensure_ascii=False, indent=2),
           '```', '', '一条 Boss 日志保留本次参与者和自动加分标记；一条装备日志只保留实际获得物品的角色：', '', '```json',
           json.dumps({'boss_example': next(v for v in final['logs'].values() if v.get('bossAutoAward')),
                       'loot_example': next(v for v in final['logs'].values() if v.get('foritem') == 'true')}, ensure_ascii=False, indent=2),
           '```', '', '## 复现', '', '```text', 'python tests/simulate_raid_example.py --lua <Lua 5.0 解释器路径>', '```', '']
(output / 'REPORT.md').write_text('\n'.join(report), encoding='utf-8')
print(f"Generated example: {output / 'REPORT.md'}")
