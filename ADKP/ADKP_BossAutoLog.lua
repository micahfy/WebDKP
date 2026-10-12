-- 自动击杀记录只保存关联标记，分值、人数和时间始终从实际 DKP 日志读取。
-- Lua 5.0 / WoW 1.12；本文件只定义函数，在主模块和界面加载前载入。
ADKP_BOSS_AUTO_LOG_MAX = 30

local function ADKP_BossAutoLog_CountPlayers(entry)
    local count = 0
    if type(entry.awarded) == "table" then
        for _ in pairs(entry.awarded) do count = count + 1 end
    end
    return count
end

local function ADKP_BossAutoLog_ResolveRef(ref)
    if type(ref) ~= "table" or not WebDKP_Log then return nil end
    local entry = WebDKP_Log[ref.key]
    if type(entry) ~= "table" then return nil end
    if ref.uniqueId and entry.uniqueId ~= ref.uniqueId then return nil end
    return entry
end

local function ADKP_BossAutoLog_Link(entry, raidRef, subRef)
    local raidLog = ADKP_BossAutoLog_ResolveRef(raidRef)
    local subLog = ADKP_BossAutoLog_ResolveRef(subRef)
    if not raidLog and not subLog then return end
    local primaryRef = raidLog and raidRef or subRef
    local base = tostring(primaryRef.uniqueId or primaryRef.key) .. ":auto"
    local used = {}
    for _, logEntry in pairs(WebDKP_Log) do
        if type(logEntry) == "table" and type(logEntry.bossAutoAward) == "table" then
            used[logEntry.bossAutoAward.id or ""] = true
        end
    end
    local id = base
    local serial = 2
    while used[id] do
        id = base .. ":" .. serial
        serial = serial + 1
    end
    if raidLog then
        raidLog.bossAutoAward = {
            id = id, boss = entry.boss, role = "raid", ab = entry.ab and true or false
        }
    end
    if subLog then
        subLog.bossAutoAward = {
            id = id, boss = entry.boss, role = "sub", ab = entry.ab and true or false
        }
    end
end

local function ADKP_BossAutoLog_ParseTime(stamp)
    if type(stamp) ~= "string" or not time then return nil end
    local _, _, y, m, d, h, minute, second = string.find(stamp,
        "^(%d+)%-(%d+)%-(%d+) (%d+):(%d+):(%d+)$")
    if not y then return nil end
    local ok, value = pcall(time, {
        year = tonumber(y), month = tonumber(m), day = tonumber(d),
        hour = tonumber(h), min = tonumber(minute), sec = tonumber(second)
    })
    if ok then return value end
    return nil
end

local function ADKP_BossAutoLog_FindLegacy(reason, stamp, tableid, exactDate)
    local found = nil
    local recordedTime = ADKP_BossAutoLog_ParseTime(stamp)
    for key, logEntry in pairs(WebDKP_Log or {}) do
        if type(logEntry) == "table" and not logEntry.bossAutoAward
            and logEntry.reason == reason and type(logEntry.awarded) == "table"
            and logEntry.foritem ~= true and logEntry.foritem ~= "true"
            and (not tableid or (tonumber(logEntry.tableid) or 1) == tableid) then
            local matches = logEntry.date == (exactDate or stamp)
            if not exactDate and not matches and recordedTime then
                local logTime = ADKP_BossAutoLog_ParseTime(logEntry.date)
                -- 旧缓存记的是同步完成时间，实际日志记的是同步开始时间。
                matches = logTime and recordedTime >= logTime and recordedTime - logTime <= 5
            end
            if matches then
                -- 同一时段存在多条候选时不猜测，避免把手动记录或另一团的记录误关联。
                if found then return nil end
                found = { key = key, uniqueId = logEntry.uniqueId }
            end
        end
    end
    return found
end

function ADKP_MigrateBossAutoAwardLog()
    local legacy = WebDKP_Options and WebDKP_Options["BossAutoAwardLog"]
    if type(legacy) ~= "table" then return end
    for _, entry in ipairs(legacy) do
        if type(entry) == "table" and type(entry.boss) == "string" then
            local raidRef, subRef = nil, nil
            local tableid = tonumber(entry.tableid)
            if (tonumber(entry.rc) or 0) > 0 then
                raidRef = ADKP_BossAutoLog_FindLegacy("击杀-" .. entry.boss, entry.t, tableid)
            end
            local raidLog = ADKP_BossAutoLog_ResolveRef(raidRef)
            if (tonumber(entry.sc) or 0) > 0 then
                subRef = ADKP_BossAutoLog_FindLegacy("击杀-" .. entry.boss .. "-替补", entry.t,
                    raidLog and (tonumber(raidLog.tableid) or 1) or tableid,
                    raidLog and raidLog.date or nil)
            end
            ADKP_BossAutoLog_Link(entry, raidRef, subRef)
        end
    end
    -- 没有实际日志的旧缓存直接丢弃，不再保留独立的加分副本。
    WebDKP_Options["BossAutoAwardLog"] = nil
end

function ADKP_AppendBossAutoAwardRecord(entry)
    if type(entry) ~= "table" then return end
    ADKP_MigrateBossAutoAwardLog()
    ADKP_BossAutoLog_Link(entry, entry.raidRef, entry.subRef)
    ADKP_RefreshBossAutoAwardLog()
end

function ADKP_GetBossAutoAwardRecords()
    ADKP_MigrateBossAutoAwardLog()
    local tableid = ADKP_GetTableid and (tonumber(ADKP_GetTableid()) or 1) or 1
    local groups = {}
    for _, logEntry in pairs(WebDKP_Log or {}) do
        local info = type(logEntry) == "table" and logEntry.bossAutoAward
        if type(info) == "table" and type(info.id) == "string"
            and (info.role == "raid" or info.role == "sub")
            and (tonumber(logEntry.tableid) or 1) == tableid
            and logEntry.foritem ~= true and logEntry.foritem ~= "true"
            and type(logEntry.awarded) == "table" then
            local group = groups[info.id]
            if not group then
                group = { id = info.id, boss = info.boss, raid = 0, sub = 0,
                    rc = 0, sc = 0, ab = false, t = "", tableid = tableid }
                groups[info.id] = group
            end
            local count = ADKP_BossAutoLog_CountPlayers(logEntry)
            local points = tonumber(logEntry.points) or 0
            if info.role == "raid" then
                group.raid = points
                group.rc = count
            else
                group.sub = points
                group.sc = count
            end
            group.ab = group.ab or (info.ab and true or false)
            local stamp = tostring(logEntry.date or "")
            if stamp > group.t then group.t = stamp end
        end
    end
    local records = {}
    for _, entry in pairs(groups) do table.insert(records, entry) end
    table.sort(records, function(a, b)
        if a.t == b.t then return a.id < b.id end
        return a.t < b.t
    end)
    local recent = {}
    for i = math.max(1, table.getn(records) - ADKP_BOSS_AUTO_LOG_MAX + 1), table.getn(records) do
        table.insert(recent, records[i])
    end
    return recent
end

function ADKP_RefreshBossAutoAwardLog()
    if ADKP_QuickFloat_UpdateAutoLogRow then ADKP_QuickFloat_UpdateAutoLogRow() end
end

-- 只清空当前团的自动记录显示标记，实际 DKP 日志及分数保持不变。
function ADKP_ClearBossAutoAwardRecords()
    ADKP_MigrateBossAutoAwardLog()
    local tableid = ADKP_GetTableid and (tonumber(ADKP_GetTableid()) or 1) or 1
    for _, entry in pairs(WebDKP_Log or {}) do
        if type(entry) == "table" and (tonumber(entry.tableid) or 1) == tableid then
            entry.bossAutoAward = nil
        end
    end
    ADKP_RefreshBossAutoAwardLog()
end
