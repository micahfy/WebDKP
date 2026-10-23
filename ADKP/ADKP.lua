------------------------------------------------------------------------
-- WEB DKP
------------------------------------------------------------------------
-- An addon to help manage the dkp for a guild. The addon provides a 
-- list of the dkp of all players as well as an interface to add / deduct dkp 
-- points. 
-- The addon generates a log file which can then be uploaded to a companion 
-- website at https://adkp.net
--
--
-- HOW THIS ADDON IS ORGANIZED:
-- The addon is grouped into a series of files which hold code for certain
-- functions. 
-- 
-- ADKP			Code to handle start / shutdown / registering events
--					and GUI event handlers. This is the main entry point
--					of the addon and directs events to the functionality
--					in the other files
--
-- Stub function to prevent errors when ADKP_FinalTest() is called
-- This function is fully defined in final_test.lua which is not loaded by default

-- Lua 5.0 compatibility for WoW 1.12.
if not string.match then
    string.match = function(text, pattern, init)
        local startPos, endPos, cap1, cap2, cap3, cap4, cap5, cap6, cap7, cap8, cap9 = string.find(text, pattern, init)
        if not startPos then
            return nil
        end
        if cap1 ~= nil then
            return cap1, cap2, cap3, cap4, cap5, cap6, cap7, cap8, cap9
        end
        return string.sub(text, startPos, endPos)
    end
end

if not string.gmatch and string.gfind then
    string.gmatch = string.gfind
end

if not math.fmod and math.mod then
    math.fmod = math.mod
end

if not table.insert and tinsert then
    table.insert = tinsert
end

if not table.remove and tremove then
    table.remove = tremove
end

function ADKP_SaveToDisk(skipAutoBackup)
    if ADKP_RefreshBossAutoAwardLog then ADKP_RefreshBossAutoAwardLog() end
    -- WoW 1.12 writes SavedVariables on ReloadUI/logout; keep this hook safe for frequent calls.
    if not skipAutoBackup and WebDKP_Options and WebDKP_Options["AutoBackupEnabled"] and ADKP_BackupData then
        ADKP_BackupData(true)  -- 自动备份：silent 模式，只提示一句
    end
end

-- 插件版本号（升级时只需改这一处；标题、调试输出统一引用）
ADKP_VERSION = "1.97"

-- 通过id查找表格名称的统一函数
function ADKP_GetTableNameById(id)
    if not id or not WebDKP_Tables then
        return "DKP"
    end
    
    for key, entry in pairs(WebDKP_Tables) do
        if type(entry) == "table" and entry["id"] == id then
            return entry.name or key
        end
    end
    
    return "DKP"
end

-- ================================
-- 构建备份格式的 CSV 文本（与备份文件格式完全一致）
-- includeHeader=true 含表头行（备份写文件用），false 不含表头（导出窗口压缩格式用）
-- 格式：类型,日期,时间,分值,项目,玩家列表（每事件一行，按时间从新到旧排序）
-- ================================
function ADKP_BuildBackupCSV(includeHeader)
    local currentTable = ADKP_GetTableid()
    local records = {}
    if WebDKP_Log then
        for key, entry in pairs(WebDKP_Log) do
            -- 只处理当前团的记录（tableid 匹配；旧数据无 tableid 字段时归到 tableid=1）
            if key ~= "Version" and type(entry) == "table" and entry.awarded then
                local entryTable = entry.tableid or 1
                if entryTable == currentTable then
                local fullTime = entry.date or ""
                local reason = entry.reason or "未知原因"
                local points = ADKP_ROUND(tonumber(entry.points) or 0, 2)

                -- 将 "YYYY-MM-DD HH:MM:SS" 拆成日期和时间两列
                local datePart, timePart
                local _, _, dp, tp = string.find(fullTime, "^(%d+%-%d+%-%d+)%s+(%d+:%d+:%d+)$")
                if dp and tp then
                    datePart = dp
                    timePart = tp
                else
                    datePart = fullTime
                    timePart = ""
                end

                -- 转义逗号：用 ~~ 替代（逗号是 CSV 分隔符）
                local cleanReason = string.gsub(reason, ",", "~~")

                -- 整合玩家列表：名字:职业;名字:职业
                local playersStr = ""
                for playerName, playerInfo in pairs(entry.awarded) do
                    local class = "未知"
                    if type(playerInfo) == "table" and playerInfo.class then
                        class = playerInfo.class
                    elseif WebDKP_DkpTable and WebDKP_DkpTable[playerName] then
                        class = WebDKP_DkpTable[playerName].class or "未知"
                    end
                    if playersStr ~= "" then
                        playersStr = playersStr .. ";"
                    end
                    playersStr = playersStr .. playerName .. ":" .. class
                end

                -- 判断是否是装备记录
                local recordType = "D"
                if entry.foritem == "true" or entry.foritem == true then
                    recordType = "L"
                end

                local line = recordType .. "," .. datePart .. "," .. timePart .. "," .. points .. "," .. cleanReason .. "," .. playersStr
                table.insert(records, { date = fullTime, line = line })
                end  -- if entryTable == currentTable
            end
        end
    end

    -- 按时间从新到旧排序
    table.sort(records, function(a, b)
        return (a.date or "") > (b.date or "")
    end)

    local parts = {}
    if includeHeader then
        table.insert(parts, "类型,日期,时间,分值,项目,玩家列表")
    end
    for i = 1, table.getn(records) do
        table.insert(parts, records[i].line)
    end
    return table.concat(parts, "\n")
end

-- ================================
-- 备份文件名构造 helper（多团隔离：文件名用 D<N> marker 区分团队）
-- ================================
-- 把服务器名中的空格全部去掉（不再用 - 替代）
local function adkp_CleanServerName(name)
    return string.gsub(name or "", "%s", "")
end

-- 数据文件名：D-<服务器>-<角色>-D<N>-<YYYY-MM-DD-HHMMSS>
local function adkp_BuildDataFileName(serverName, charName, tableid)
    return "D-" .. serverName .. "-" .. charName .. "-D" .. tableid .. "-" .. date("%Y-%m-%d-%H%M%S")
end

-- 指针文件名：P-<服务器>-<角色>-D<N>-<YYYY-MM-DD>-<计数器>
local function adkp_BuildPointerName(serverName, charName, tableid, dateStr, counter)
    return "P-" .. serverName .. "-" .. charName .. "-D" .. tableid .. "-" .. dateStr .. "-" .. counter
end

-- 团1老格式指针文件名（无 marker，仅团1 fallback 用）：P-<服务器>-<角色>-<YYYY-MM-DD>-<计数器>
local function adkp_BuildLegacyPointerName(serverName, charName, dateStr, counter)
    return "P-" .. serverName .. "-" .. charName .. "-" .. dateStr .. "-" .. counter
end

-- 从文件名解析团 marker（D1/D2/...），用于手动导入警告。解析失败返回 nil。
local function adkp_ParseTableIdFromName(filename)
    if not filename then return nil end
    local _, _, tid = string.find(filename, "%-D(%d+)%-")
    return tid and tonumber(tid) or nil
end

-- 从 LatestBackup[charKey] 取出指定团的指针记录
-- 兼容：旧扁平结构 {Date=,...}（无团维度）→ 视为团1；新嵌套结构 [tableid]={...}
local function adkp_GetTeamBackup(latestBackup, tableid)
    if not latestBackup then return nil end
    if type(latestBackup) == "table" then
        if latestBackup[tableid] then
            return latestBackup[tableid]   -- 新嵌套结构
        elseif latestBackup.Date and not latestBackup[1] then
            return latestBackup            -- 旧扁平结构（迁移前的状态）
        end
    end
    return nil
end

-- 自动备份提示的冷却时间戳（内存变量，reload 后重置）。
-- 避免每次 SaveToDisk 都刷屏。10 分钟内不重复提示。
ADKP_AutoBackupLastNotifyTime = 0
local ADKP_AUTOBACKUP_NOTIFY_COOLDOWN = 600  -- 秒

-- ================================
-- 备份数据功能
-- silent=true 时为自动备份场景，只打印一句简短提示，不刷屏
-- silent 模式额外受 10 分钟冷却限制，避免频繁备份刷屏
-- ================================
function ADKP_BackupCharacterKey()
    local server = adkp_CleanServerName(GetRealmName() or "未知服务器")
    local player = string.gsub(UnitName("player") or "未知角色", "%s", "-")
    return server .. "-" .. player, server, player
end

local function adkp_ReadBackupFile(filename)
    if type(ImportFile) ~= "function" or type(filename) ~= "string" then return nil end
    filename = string.gsub(filename, "%.txt$", "")
    local ok, text = pcall(ImportFile, filename)
    if ok and type(text) == "string" then return text end
    ok, text = pcall(ImportFile, filename .. ".txt")
    if ok and type(text) == "string" then return text end
end

local function adkp_NormalizeBackupText(text)
    return string.gsub(string.gsub(text, "\r\n", "\n"), "\r", "\n")
end

local function adkp_BackupFields(line)
    local fields, from = {}, 1
    while true do
        local comma = string.find(line, ",", from, true)
        if not comma then table.insert(fields, string.sub(line, from)); return fields end
        table.insert(fields, string.sub(line, from, comma - 1)); from = comma + 1
    end
end

function ADKP_ValidateBackupCSV(text)
    if type(text) ~= "string" or string.len(text) > 4194304 then return false end
    text = adkp_NormalizeBackupText(text)
    local first = true
    for line in string.gfind(text, "[^\n]+") do
        if first then
            if line ~= "类型,日期,时间,分值,项目,玩家列表" then return false end
            first = false
        else
            local fields = adkp_BackupFields(line)
            local kind = fields[1]
            if kind == "D" or kind == "L" then
                local points = tonumber(fields[4])
                if table.getn(fields) ~= 6 or not points or points ~= points or math.abs(points) >= 1e308 then return false end
                local playerCount = 0
                for pair in string.gfind(fields[6], "[^;]+") do
                    if not string.find(pair, "^[^:]+:[^:]+$") then return false end
                    playerCount = playerCount + 1
                end
                if fields[6] ~= "" and playerCount == 0 then return false end
            elseif kind == "#ADKP_SHARE_BASE" then
                local points = tonumber(fields[3])
                if table.getn(fields) ~= 3 or fields[2] == "" or not points
                    or points ~= points or math.abs(points) >= 1e308 then return false end
            elseif kind == "#ADKP_SHARE" or kind == "#ADKP_SHARE_PROPOSAL" then
                if table.getn(fields) ~= 4 or fields[2] == "" or fields[3] == "" then return false end
            else return false end
        end
    end
    return not first
end

local function adkp_RegisteredBackup(tableid)
    local key = ADKP_BackupCharacterKey()
    local all = WebDKP_Options and WebDKP_Options.LatestBackup
    local record = all and all[key]
    if tableid ~= 1 and (type(record) ~= "table" or not record[tableid]) then return nil end
    return adkp_GetTeamBackup(record, tableid)
end

local function adkp_RegisterBackup(candidate)
    if not WebDKP_Options then WebDKP_Options = {} end
    if type(WebDKP_Options.LatestBackup) ~= "table" then WebDKP_Options.LatestBackup = {} end
    local all = WebDKP_Options.LatestBackup
    local old = all[candidate.CharacterKey]
    if type(old) ~= "table" then old = {} end
    if old.Date and not old[1] then old = { [1] = old } end
    all[candidate.CharacterKey] = old
    old[candidate.TableId] = { Date = candidate.Date, Counter = candidate.Counter,
        PointerFile = candidate.PointerFile, DataFile = candidate.DataFile }
end

local function adkp_WriteBackupFile(filename, text)
    local written = pcall(ExportFile, filename, text)
    local actual = adkp_ReadBackupFile(filename)
    return written and actual and adkp_NormalizeBackupText(actual) == adkp_NormalizeBackupText(text)
end

function ADKP_BackupData(silent)
    if not SUPERWOW_STRING or type(ExportFile) ~= "function" or type(ImportFile) ~= "function" then
        if not silent then ADKP_Print("错误：备份数据功能需要superwow支持且文件读写函数可用") end
        return false
    end
    local tableid = ADKP_GetTableid()
    if ADKP_BackupRecoveryCanWrite and not ADKP_BackupRecoveryCanWrite(silent, tableid) then
        if not silent then ADKP_Print("正在检查或确认备份恢复，暂不创建新备份。") end
        return false
    end
    local charKey, serverName, charName = ADKP_BackupCharacterKey()
    local currentDate, counter = date("%Y-%m-%d"), 1
    local registered = adkp_RegisteredBackup(tableid)
    if registered and registered.Date == currentDate then counter = (tonumber(registered.Counter) or 0) + 1 end
    while adkp_ReadBackupFile(adkp_BuildPointerName(serverName, charName, tableid, currentDate, counter)) ~= nil do
        counter = counter + 1
    end
    local exportText = ADKP_BuildBackupCSV(true)
    if not ADKP_ValidateBackupCSV(exportText) then
        ADKP_Print("备份内容校验失败，最后成功备份标记保持不变。")
        return false
    end
    local baseName = adkp_BuildDataFileName(serverName, charName, tableid)
    local dataFileName, suffix = baseName, counter
    -- Multiple writes within one second must not replace an older D file.
    while adkp_ReadBackupFile(dataFileName) ~= nil do
        dataFileName = baseName .. "-" .. suffix; suffix = suffix + 1
    end
    if not adkp_WriteBackupFile(dataFileName, exportText) then
        ADKP_Print("备份文件写入校验失败，最后成功备份标记保持不变。")
        return false
    end
    local pointerFileName = adkp_BuildPointerName(serverName, charName, tableid, currentDate, counter)
    if not adkp_WriteBackupFile(pointerFileName, dataFileName) then
        ADKP_Print("备份指针写入校验失败，最后成功备份标记保持不变。")
        return false
    end
    adkp_RegisterBackup({ CharacterKey = charKey, TableId = tableid, Date = currentDate,
        Counter = counter, PointerFile = pointerFileName, DataFile = dataFileName })
    if not silent and ADKP_ResumeAutoBackup then ADKP_ResumeAutoBackup(tableid) end
    if silent then
        local now = time()
        if now - ADKP_AutoBackupLastNotifyTime >= ADKP_AUTOBACKUP_NOTIFY_COOLDOWN then
            ADKP_Print("数据发生变动，已自动备份。")
            ADKP_AutoBackupLastNotifyTime = now
        end
    else
        ADKP_Print("数据已成功备份到: " .. dataFileName)
        ADKP_Print("指针文件已保存: " .. pointerFileName)
    end
    return true
end

-- Read-only lookup shared by the manual button and login's check-only call.
function ADKP_FindLatestBackup()
    if not SUPERWOW_STRING or type(ImportFile) ~= "function" then return nil end
    local charKey, serverName, charName = ADKP_BackupCharacterKey()
    local tableid = ADKP_GetTableid()
    local registered = adkp_RegisteredBackup(tableid)
    local function pointerAt(day, counter)
        local name = adkp_BuildPointerName(serverName, charName, tableid, day, counter)
        local text = adkp_ReadBackupFile(name)
        if text ~= nil then return name, text end
        if tableid == 1 then
            name = adkp_BuildLegacyPointerName(serverName, charName, day, counter)
            text = adkp_ReadBackupFile(name)
            if text ~= nil then return name, text end
        end
    end
    local function forDay(day)
        local low = registered and registered.Date == day and tonumber(registered.Counter) or 1
        if not low or low < 1 or low > 1000000000 or low ~= math.floor(low) or not pointerAt(day, low) then low = 1 end
        if not pointerAt(day, low) then return nil end
        local high = low * 2
        while pointerAt(day, high) do low = high; high = high * 2 end
        while low + 1 < high do
            local middle = math.floor((low + high) / 2)
            if pointerAt(day, middle) then low = middle else high = middle end
        end
        -- A broken newest file must not hide an older usable backup.
        for counter = low, 1, -1 do
            local name, text = pointerAt(day, counter)
            if text then
                local file = string.gsub(string.gsub(text, "[\r\n]", ""), "^%s*(.-)%s*$", "%1")
                local fileTable = adkp_ParseTableIdFromName(file)
                if file ~= "" and (fileTable == tableid or (tableid == 1 and not fileTable)) then
                    local data = adkp_ReadBackupFile(file)
                    if ADKP_ValidateBackupCSV(data) then
                        return { CharacterKey = charKey, TableId = tableid, Date = day, Counter = counter,
                            PointerFile = name, DataFile = file, Data = data }
                    end
                end
            end
        end
    end
    local checked = {}
    for offset = 0, 59 do
        local day = date("%Y-%m-%d", time() - offset * 24 * 3600)
        checked[day] = true
        local candidate = forDay(day)
        if candidate then return candidate end
    end
    if registered and type(registered.Date) == "string" and not checked[registered.Date] then
        return forDay(registered.Date)
    end
end

function ADKP_RestoreData(checkOnly, candidate)
    if not SUPERWOW_STRING or type(ImportFile) ~= "function" then
        if not checkOnly then ADKP_Print("错误：恢复数据功能需要superwow支持且ImportFile函数可用") end
        return nil
    end
    candidate = candidate or ADKP_FindLatestBackup()
    if not candidate then
        if not checkOnly then ADKP_Print("未找到任何有效备份记录（已检索近60天及SavedVariables）") end
        return nil
    end
    if checkOnly then
        local registered = adkp_RegisteredBackup(candidate.TableId)
        if registered and registered.Date == candidate.Date and tonumber(registered.Counter) == candidate.Counter
            and registered.PointerFile == candidate.PointerFile and registered.DataFile == candidate.DataFile then return nil end
        return candidate
    end
    if candidate.TableId ~= ADKP_GetTableid() or candidate.CharacterKey ~= ADKP_BackupCharacterKey() then
        ADKP_Print("当前DKP团队已变化，请切回原团队后使用恢复最新数据。")
        return false
    end
    local data = adkp_ReadBackupFile(candidate.DataFile)
    if not ADKP_ValidateBackupCSV(data) or adkp_NormalizeBackupText(data) ~= adkp_NormalizeBackupText(candidate.Data) then
        ADKP_Print("备份已变化或无法读取，请重新使用恢复最新数据。")
        return false
    end
    ADKP_Print("已找到最新备份记录，日期：" .. candidate.Date .. " 文件：" .. candidate.PointerFile)
    local ok, restored = pcall(ADKP_RestoreFromData, data, candidate.DataFile)
    if not ok or not restored then
        ADKP_Print("恢复失败，最后成功备份标记保持不变：" .. tostring(restored))
        return false
    end
    adkp_RegisterBackup(candidate)
    if ADKP_ResumeAutoBackup then ADKP_ResumeAutoBackup(candidate.TableId) end
    return true
end

-- ================================
-- 从已读取的备份数据内容恢复（ADKP_RestoreData 与 ADKP_ImportSpecificVersion 共用）
-- 合并模式：重复记录跳过，新记录加入当前数据
-- ================================
function ADKP_RestoreFromData(importData, dataFileName)
    if not ADKP_ValidateBackupCSV(importData) then
        ADKP_Print("备份格式或内容无效，未执行恢复。")
        return false
    end
    ADKP_Print("开始恢复活动数据...")
    ADKP_Print("已读取文件：" .. dataFileName)

    local lines = {}
    local function splitString(str, delimiter)
        local result = {}
        local from = 1
        local delim_from, delim_to = string.find(str, delimiter, from)
        while delim_from do
            table.insert(result, string.sub(str, from, delim_from - 1))
            from = delim_to + 1
            delim_from, delim_to = string.find(str, delimiter, from)
        end
        table.insert(result, string.sub(str, from))
        return result
    end
    
    local normalizedData = string.gsub(importData, "\r\n", "\n")
    normalizedData = string.gsub(normalizedData, "\r", "\n")
    lines = splitString(normalizedData, "\n")
    
    local dkpRecords = {}
    local lootRecords = {}
    local playerClassMap = {}  -- 职业对照表
    
    for i, line in ipairs(lines) do
        -- 跳过空行和表头
        if line ~= "" and i > 1 then
            local fields = splitString(line, ",")
            if table.getn(fields) >= 6 then
                local recordType = fields[1]
                local datePart = fields[2]
                local timePart = fields[3]
                -- 拼回完整 date 字符串："YYYY-MM-DD HH:MM:SS"
                local timeStr = datePart .. " " .. timePart
                local points = tonumber(fields[4]) or 0
                local reason = fields[5]
                -- 还原备份时被转义的逗号（备份时把 reason 里的逗号替换成了 ~~ ）
                reason = string.gsub(reason, "~~", ",")
                local playersStr = fields[6]
                
                -- 解析玩家列表 名字:职业;名字:职业
                local players = {}
                local playerList = splitString(playersStr, ";")
                for _, playerPair in ipairs(playerList) do
                    if playerPair ~= "" then
                        local pair = splitString(playerPair, ":")
                        if table.getn(pair) >= 2 then
                            local pName = pair[1]
                            local pClass = pair[2]
                            pName = string.gsub(pName, "^%s*", "")
                            pName = string.gsub(pName, "%s*$", "")
                            pClass = string.gsub(pClass, "^%s*", "")
                            pClass = string.gsub(pClass, "%s*$", "")
                            
                            if pName ~= "" then
                                table.insert(players, pName)
                                if pClass and pClass ~= "未知" and pClass ~= "" then
                                    playerClassMap[pName] = pClass
                                end
                            end
                        end
                    end
                end
                
                if recordType == "D" then
                    -- 转换为原来的 dkpRecords 结构
                    local playersConcat = ""
                    for _, p in ipairs(players) do
                        if playersConcat ~= "" then
                            playersConcat = playersConcat .. ","
                        end
                        playersConcat = playersConcat .. p
                    end
                    
                    table.insert(dkpRecords, {
                        time = timeStr,
                        reason = reason,
                        points = points,
                        players = playersConcat
                    })
                elseif recordType == "L" then
                    -- 转换为原来的 lootRecords 结构
                    for _, p in ipairs(players) do
                        table.insert(lootRecords, {
                            time = timeStr,
                            item = reason,
                            player = p,
                            points = points
                        })
                    end
                end
            end
        end
    end

    local restoredCount = 0 
    local skippedCount = 0 
    local tableid = ADKP_GetTableid()

    -- 同一秒可以存在多条同原因记录，索引值使用“分值+玩家签名”集合。
    local existingIndex = {}
    local function buildRecordSignature(points, playerSignature)
        local normalizedPoints = ADKP_ROUND(tonumber(points) or 0, 2)
        return tostring(normalizedPoints) .. "\001" .. playerSignature
    end
    local function addExistingRecord(idxKey, points, playerSignature)
        if not existingIndex[idxKey] then existingIndex[idxKey] = {} end
        existingIndex[idxKey][buildRecordSignature(points, playerSignature)] = true
    end
    local function createAvailableLogKey(baseKey)
        local key = baseKey
        local duplicateIndex = 2
        while WebDKP_Log[key] do
            key = baseKey .. " #" .. duplicateIndex
            duplicateIndex = duplicateIndex + 1
        end
        return key
    end
    if WebDKP_Log then
        for key, entry in pairs(WebDKP_Log) do
            if type(entry) == "table" and entry.awarded and (tonumber(entry.tableid) or 1) == tableid then
                local fi = entry.foritem
                local typeTag = (fi == true or fi == "true") and "L" or "D"
                local idxKey = typeTag .. "\001" .. (entry.reason or "") .. " " .. (entry.date or "")
                -- 玩家签名：把 awarded 的玩家名排序拼接，用于精确比对
                local names = {}
                for playerName, _ in pairs(entry.awarded) do
                    table.insert(names, playerName)
                end
                table.sort(names)
                local signature = table.concat(names, ",")
                addExistingRecord(idxKey, entry.points, signature)
            end
        end
    end

    -- O(1) 重复检查：DKP 记录
    local function isDuplicateDKPRecord(record, players)
        local idxKey = "D\001" .. record.reason .. " " .. record.time
        local names = {}
        for playerName, _ in pairs(players) do
            table.insert(names, playerName)
        end
        table.sort(names)
        local signature = buildRecordSignature(record.points, table.concat(names, ","))
        return existingIndex[idxKey] and existingIndex[idxKey][signature] or false
    end

    -- O(1) 重复检查：装备记录
    local function isDuplicateLootRecord(record)
        local idxKey = "L\001" .. record.item .. " " .. record.time
        local signature = buildRecordSignature(record.points, record.player)
        return existingIndex[idxKey] and existingIndex[idxKey][signature] or false
    end

    local function getPlayerClassInfo(playerName)
        local playerClass = "未知"
        if playerClassMap[playerName] then
            playerClass = playerClassMap[playerName]
        elseif WebDKP_DkpTable[playerName] then
            playerClass = WebDKP_DkpTable[playerName]["class"] or "未知"
        end
        return {
            ["name"] = playerName,
            ["class"] = playerClass,
            ["guild"] = ""
        }
    end

    -- 恢复DKP奖惩记录
    for _, record in ipairs(dkpRecords) do
        local players = {}
        local playerList = record.players
        local startPos = 1
        
        while true do
            local commaPos = string.find(playerList, ",", startPos)
            local player
            if commaPos then
                player = string.sub(playerList, startPos, commaPos - 1)
                startPos = commaPos + 1
            else
                player = string.sub(playerList, startPos)
            end
            
            player = string.gsub(player, "^%s*", "")
            player = string.gsub(player, "%s*$", "")
            
            if player and player ~= "" then
                players[player] = getPlayerClassInfo(player)
            end
            if not commaPos then
                break
            end
        end
        
        if not isDuplicateDKPRecord(record, players) then
            local newLogEntry = {
                ["reason"] = record.reason,
                ["points"] = record.points,
                ["awarded"] = players,
                ["date"] = record.time,
                ["foritem"] = "false",
                ["tableid"] = tableid,
                ["zone"] = GetZoneText(),
                ["awardedby"] = UnitName("player")
            }

            if not WebDKP_Log then
                WebDKP_Log = {}
            end
            local key = createAvailableLogKey(record.reason .. " " .. record.time)
            newLogEntry.uniqueId = key
            WebDKP_Log[key] = newLogEntry

            -- 同步更新索引表，防止同一备份文件内的重复记录被二次导入
            local names = {}
            for playerName, _ in pairs(players) do
                table.insert(names, playerName)
            end
            table.sort(names)
            addExistingRecord("D\001" .. record.reason .. " " .. record.time, record.points, table.concat(names, ","))
            
            for playerName, playerInfo in pairs(players) do
                if not WebDKP_DkpTable[playerName] then
                    WebDKP_DkpTable[playerName] = {
                        ["class"] = playerInfo["class"],
                        ["dkp_" .. tableid] = 0,
                        ["Selected"] = false,
                        ["IsSub"] = false
                    }
                end
                local dkpField = "dkp_" .. tableid
                WebDKP_DkpTable[playerName][dkpField] = ADKP_ROUND((WebDKP_DkpTable[playerName][dkpField] or 0) + record.points, 2)
            end
            restoredCount = restoredCount + 1
        else
            skippedCount = skippedCount + 1
        end
    end
    
    -- 恢复装备奖惩记录
    for _, record in ipairs(lootRecords) do
        if not isDuplicateLootRecord(record) then
            local players = { [record.player] = getPlayerClassInfo(record.player) }
            
            local newLogEntry = {
                ["reason"] = record.item,
                ["points"] = record.points,
                ["awarded"] = players,
                ["date"] = record.time,
                ["foritem"] = "true",
                ["tableid"] = tableid,
                ["zone"] = GetZoneText(),
                ["awardedby"] = UnitName("player")
            }
            
            if not WebDKP_Log then
                WebDKP_Log = {}
            end
            local key = createAvailableLogKey(record.item .. " " .. record.time)
            newLogEntry.uniqueId = key
            WebDKP_Log[key] = newLogEntry

            -- 同步更新索引表，防止同一备份文件内的重复记录被二次导入
            addExistingRecord("L\001" .. record.item .. " " .. record.time, record.points, record.player)
            
            for playerName, playerInfo in pairs(players) do
                if not WebDKP_DkpTable[playerName] then
                    WebDKP_DkpTable[playerName] = {
                        ["class"] = playerInfo["class"],
                        ["dkp_" .. tableid] = 0,
                        ["Selected"] = false,
                        ["IsSub"] = false
                    }
                end
                local dkpField = "dkp_" .. tableid
                WebDKP_DkpTable[playerName][dkpField] = ADKP_ROUND((WebDKP_DkpTable[playerName][dkpField] or 0) + record.points, 2)
            end
            restoredCount = restoredCount + 1
        else
            skippedCount = skippedCount + 1
        end
    end
    
    -- 保存数据
    if ADKP_SaveToDisk then
        -- Restoring a backup must not create another backup version.
        ADKP_SaveToDisk(true)
    end
    
    -- 刷新列表
    ADKP_UpdateTableToShow()
    ADKP_UpdateTable()
    ADKP_UpdateLootList()
    
    if ADKP_Frame then
        ADKP_Frame:Show()
    end
    
    local totalCount = restoredCount + skippedCount
    ADKP_Print("数据恢复完成。共处理" .. totalCount .. "条记录，成功恢复" .. restoredCount .. "条。")
    if skippedCount > 0 then
        ADKP_Print("跳过了" .. skippedCount .. "条重复记录。")
    end
    return true
end

-- ================================
-- 从特定版本导入（用户指定文件名，合并模式，复用 ADKP_RestoreFromData）
-- 支持数据文件(D-...)和指针文件(P-...)，自动判断
-- ================================
function ADKP_ImportSpecificVersion(filename)
    if not SUPERWOW_STRING or not ImportFile then
        ADKP_Print("错误：导入功能需要superwow支持且ImportFile函数可用")
        return
    end
    if not filename or filename == "" then
        ADKP_Print("请输入要导入的版本文件名")
        return
    end

    -- 读取用户指定的文件
    local content = adkp_ReadBackupFile(filename)
    if not content or content == "" then
        ADKP_Print("错误：无法读取文件：" .. filename)
        return
    end

    -- 团 marker 警告：文件名带 D<N> 但与当前团不符时提示（不阻断，仍写入当前团）
    local fileTableId = adkp_ParseTableIdFromName(filename)
    local currentTable = ADKP_GetTableid()
    if fileTableId and fileTableId ~= currentTable then
        ADKP_Print("警告：文件 [" .. filename .. "] 属于团 D" .. fileTableId
                   .. "，当前是团 D" .. currentTable
                   .. "。导入后将写入当前团，请确认是否继续。")
    end

    -- 判断文件类型：数据文件首行以"类型"开头；否则视为指针文件（内容是数据文件名）
    local realDataFile, dataContent = filename, content
    local _, _, firstLine = string.find(content, "^([^\r\n]*)")
    if not firstLine or not string.find(firstLine, "^类型") then
        -- 指针文件：内容是数据文件名
        realDataFile = string.gsub(content, "[\r\n]", "")
        realDataFile = string.gsub(realDataFile, "^%s*(.-)%s*$", "%1")
        if realDataFile == "" then
            ADKP_Print("错误：指针文件内容为空：" .. filename)
            return
        end
        dataContent = adkp_ReadBackupFile(realDataFile)
        if not dataContent or dataContent == "" then
            ADKP_Print("错误：无法读取数据文件：" .. realDataFile)
            return
        end
    end
    local latest = ADKP_FindLatestBackup()
    if latest and string.gsub(latest.DataFile, "%.txt$", "") == string.gsub(realDataFile, "%.txt$", "") then
        return ADKP_RestoreData(false, latest)
    end
    local ok, restored = pcall(ADKP_RestoreFromData, dataContent, realDataFile)
    if not ok or not restored then
        ADKP_Print("恢复失败，自动备份暂停状态保持不变：" .. tostring(restored))
        return false
    end
    if ADKP_ResumeAutoBackup then ADKP_ResumeAutoBackup(currentTable) end
    return true
end

-- ================================
-- 导入按钮 OnClick：读取文本框文件名，弹出确认窗
-- ================================
function ADKP_RequestImportVersion()
    local editBox = ADKP_SettingsImportEditBox
    if not editBox then
        return
    end
    local filename = editBox:GetText()
    -- 去除首尾空格
    filename = string.gsub(filename, "^%s*(.-)%s*$", "%1")
    if not filename or filename == "" then
        ADKP_Print("请先输入要导入的版本文件名")
        return
    end

    -- 动态定义确认弹窗（仿 ADKP_DELETE_PLAYER_CONFIRM）
    StaticPopupDialogs["ADKP_IMPORT_VERSION_CONFIRM"] = {
        text = "确定从版本 [" .. filename .. "] 导入数据吗？\n将与现有数据合并（重复记录跳过）。",
        button1 = "确定",
        button2 = "取消",
        OnAccept = function()
            ADKP_ImportSpecificVersion(filename)
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
    StaticPopup_Show("ADKP_IMPORT_VERSION_CONFIRM")
end

-- DKP玩家创建功能 - 职业选择下拉菜单初始化
function ADKP_CreatePlayerClassDropDown_Init()
    local dropdown = getglobal("ADKP_FiltersFrameCreatePlayerFrameClassDropDown")
    if not dropdown then return end
    
    UIDropDownMenu_Initialize(dropdown, ADKP_CreatePlayerClassDropDown_OnLoad)
    UIDropDownMenu_SetWidth(55)
    UIDropDownMenu_SetSelectedValue(dropdown, "战士")
end

-- DKP玩家创建功能 - 职业选择下拉菜单加载
function ADKP_CreatePlayerClassDropDown_OnLoad()
    local classes = {
        {text = "战士", value = "战士"},
        {text = "法师", value = "法师"},
        {text = "牧师", value = "牧师"},
        {text = "猎人", value = "猎人"},
        {text = "潜行者", value = "潜行者"},
        {text = "德鲁伊", value = "德鲁伊"},
        {text = "圣骑士", value = "圣骑士"},
        {text = "萨满祭司", value = "萨满祭司"},
        {text = "术士", value = "术士"}
    }
    
    for _, class in pairs(classes) do
        local info = UIDropDownMenu_CreateInfo()
        info.text = class.text
        info.value = class.value
        info.func = ADKP_CreatePlayerClassDropDown_OnClick
        UIDropDownMenu_AddButton(info)
    end
end

-- DKP玩家创建功能 - 职业选择下拉菜单点击事件
function ADKP_CreatePlayerClassDropDown_OnClick()
    local dropdown = getglobal("ADKP_FiltersFrameCreatePlayerFrameClassDropDown")
    if dropdown then
        UIDropDownMenu_SetSelectedValue(dropdown, this.value)
    end
end

-- DKP玩家创建功能 - 添加玩家
function ADKP_CreatePlayer()
	-- 获取输入框和下拉菜单
    local nameEditBox = getglobal("ADKP_FiltersFrameCreatePlayerFramePlayerName")
    local classDropDown = getglobal("ADKP_FiltersFrameCreatePlayerFrameClassDropDown")
    
    if not nameEditBox or not classDropDown then
        ADKP_Print("错误：无法获取创建玩家的UI组件！")
        return
    end
    
	-- 获取输入值
    local name = nameEditBox:GetText()
    local class = UIDropDownMenu_GetSelectedValue(classDropDown)
    
	-- 验证输入
    if not name or name == "" then
        ADKP_Print("错误：请输入玩家名字！")
        return
    end
    
    if not class or class == "" then
        ADKP_Print("错误：请选择职业！")
        return
    end
    
	-- 使用/adkptj命令的逻辑添加玩家，初始分默认0
    local initialDkp = 0
    
	-- 验证职业是否有效，支持中英文职业名称，以及潜行者/盗贼别名
    local validClasses = {
        {en = "Druid", zh = {"德鲁伊"}},
        {en = "Hunter", zh = {"猎人"}},
        {en = "Mage", zh = {"法师"}},
        {en = "Rogue", zh = {"盗贼", "潜行者"}},
        {en = "Shaman", zh = {"萨满祭司"}},
        {en = "Paladin", zh = {"圣骑士"}},
        {en = "Priest", zh = {"牧师"}},
        {en = "Warrior", zh = {"战士"}},
        {en = "Warlock", zh = {"术士"}}
    }
    local classValid = false
    local englishClass = ""
    
    for _, validClass in pairs(validClasses) do
        -- 检查英文职业名称
        if string.lower(class) == string.lower(validClass.en) then
            englishClass = validClass.en
            classValid = true
            break
        end
        -- 检查中文职业名称（支持多个别名）
        for _, zhClass in pairs(validClass.zh) do
            if string.lower(class) == string.lower(zhClass) then
                englishClass = validClass.en
                classValid = true
                break
            end
        end
        if classValid then break end
    end
    
    if not classValid then
        ADKP_Print("错误：无效的职业！")
        return
    end
    
	-- 检查玩家是否已存在
    if WebDKP_DkpTable[name] then
        ADKP_Print("警告：" .. name .. " 已存在于DKP列表中！")
        return
    end
    
	-- 添加新玩家到DKP表，存储中文职业名称
    WebDKP_DkpTable[name] = {
        ["class"] = class,
        ["dkp_" .. ADKP_GetTableid()] = initialDkp,
        ["Selected"] = false,
        ["IsSub"] = false
    }
    
	-- 更新显示表格
    ADKP_UpdateTableToShow()
    ADKP_UpdateTable()
    
	-- 清空输入框
    nameEditBox:SetText("")
    
    ADKP_Print("成功添加新玩家：")
    ADKP_Print("名字：" .. name)
    ADKP_Print("职业：" .. class)
    ADKP_Print("初始DKP：" .. initialDkp)
end




-- GroupFunctions	Methods the handle scanning the current group, updating
--					the dkp table to be show based on filters, sorting, 
--					and updating the gui with the current table
--
-- Announcements	Code handling announcements as they are echoed to the screen
--
-- WhisperDKP		Implementation of the Whisper DKP feature. 
--
-- Utility			Utility and helper methods. For example, methods
--					to find out a users guild or print something to the 
--					screen. 

-- AutoFill			Methods related to autofilling in item names when drops
--					Occur		
------------------------------------------------------------------------

---------------------------------------------------
-- MEMBER VARIABLES
---------------------------------------------------
-- Sets the range of dkp that defines tiers.
-- Example, 50 would be:
-- 0-50 = teir 0
-- 51-100 = teir 1, etc
ADKP_TierInterval = 50;   

-- Specify what filters are turned on and off. 1 = on, 0 = off
-- (Don't mess around with)
ADKP_Filters = {
	["Druid"] = 1,
	["Hunter"] = 1,
	["Mage"] = 1,
	["Rogue"] = 1,
	["Shaman"] = 1,
	["Paladin"] = 1,
	["Priest"] = 1,
	["Warrior"] = 1,
	["Warlock"] = 1,
	["All"] = 0
}

-- The dkp table itself (This is loaded from the saved variables file)
-- Its structure is:
-- ["playerName"] = {
--		["dkp"] = 100,
--		["class"] = "ClassName",
--		["Selected"] = true/ false if they are selected in the guid
-- }
WebDKP_DkpTable = {};

-- Holds the list of users tables on the site. This is used for those guilds
-- who have multiple dkp tables for 1 guild. 
-- When there are multiple table names in this list a drop down will appear 
-- in the addon so a user can select which table they want to award dkp to
-- Its structure is: 
-- ["tableName"] = { 
--		["id"] = 1 (this is the tableid of the table on the ADKP site)
-- }
WebDKP_Tables = {};
selectedTableid = 1;


-- The dkp table that will be shown. This is filled programmatically
-- based on running through the big dkp table applying the selected filters
ADKP_DkpTableToShow = {}; 

-- Keeps track of the current players in the group. This is filled programmatically
-- and is filled with Raid data if the player is in a raid, or party data if the
-- player is in a party. It is used to apply the 'Group' filter
ADKP_PlayersInGroup = {};

-- 替补加分数据
ADKP_SubAwardData = {
    captain = "",
    members = {},
    bossName = "",
    reason = "",
    points = 0
};

-- 初始化替补设置
-- 按团读写替补队长（captain 按 tableid 独立存储）
-- 旧格式迁移：SubSettings.captain（全局字符串）→ SubSettings.captains[tableid]（按团）
function ADKP_GetSubCaptain(tableid)
    if not tableid then tableid = ADKP_GetTableid() end
    if not WebDKP_Options or not WebDKP_Options["SubSettings"] then return "" end
    local subs = WebDKP_Options["SubSettings"]
    -- 新格式：captains[tableid]
    if subs["captains"] and subs["captains"][tableid] then
        return subs["captains"][tableid]
    end
    -- 旧格式迁移：把全局 captain 作为 tableid=1 的队长
    if tableid == 1 and subs["captain"] then
        return subs["captain"]
    end
    return ""
end

function ADKP_SetSubCaptain(tableid, captain)
    if not tableid then tableid = ADKP_GetTableid() end
    if not WebDKP_Options then WebDKP_Options = {} end
    if not WebDKP_Options["SubSettings"] then WebDKP_Options["SubSettings"] = {} end
    if not WebDKP_Options["SubSettings"]["captains"] then
        WebDKP_Options["SubSettings"]["captains"] = {}
    end
    WebDKP_Options["SubSettings"]["captains"][tableid] = captain or ""
    -- 同步运行时缓存
    if ADKP_SubAwardData then
        ADKP_SubAwardData.captain = captain or ""
    end
    -- 兼容旧字段（保留 captain 作为当前团的镜像，旧代码读取用）
    WebDKP_Options["SubSettings"]["captain"] = captain or ""
end

function ADKP_InitSubSettings()
	-- 旧版 SavedVariables 可能仍带有每日 TB 数据；不再读取或保存。
	WebDKP_DailySubRecords = nil
	-- 确保数据结构存在
    if not WebDKP_Options then
        WebDKP_Options = {}
    end
    if not WebDKP_Options["SubSettings"] then
        WebDKP_Options["SubSettings"] = {}
    end
    -- 旧格式迁移：把全局 captain 迁移到 captains[1]
    if WebDKP_Options["SubSettings"]["captain"] and WebDKP_Options["SubSettings"]["captain"] ~= "" then
        if not WebDKP_Options["SubSettings"]["captains"] then
            WebDKP_Options["SubSettings"]["captains"] = {}
        end
        if not WebDKP_Options["SubSettings"]["captains"][1] then
            WebDKP_Options["SubSettings"]["captains"][1] = WebDKP_Options["SubSettings"]["captain"]
        end
    end
    if not WebDKP_Options["SubSettings"]["captains"] then
        WebDKP_Options["SubSettings"]["captains"] = {}
    end
    if not ADKP_SubAwardData then
        ADKP_SubAwardData = {
            captain = "",
            members = {},
            bossName = "",
            reason = "",
            points = 0
        }
    end

	-- 从设置加载当前团的替补队长信息
    local captain = ADKP_GetSubCaptain(ADKP_GetTableid())
    ADKP_SubAwardData.captain = captain

    ADKP_UpdateCaptainLabel()
    

end

function ADKP_UpdateCaptainLabel()
    local captain = ADKP_SubAwardData and ADKP_SubAwardData.captain or ""
    if ADKP_AwardDKP_FrameSubCaptainLabel then
        if captain == "" then
            ADKP_AwardDKP_FrameSubCaptainLabel:SetText("替补队长: 无")
        else
            ADKP_AwardDKP_FrameSubCaptainLabel:SetText("替补队长: " .. captain)
        end
    end
end

-- Keeps track of the sorting options. 
-- Curr = current columen being sorted
-- Way = asc or desc order. 0 = desc. 1 = asc
ADKP_LogSort = {
	["curr"] = 3,
	["way"] = 1 -- Desc
};

-- Additional user options
WebDKP_Options = {
	["AutofillEnabled"] = 1, 		-- auto fill data. 0 = disabled. 1 = enabled. 
	["AutofillThreshold"] = 3, 		-- What level of items should be picked up by auto fill. -1 = Gray, 4 = Orange
	["AutoAwardEnabled"] = 1, 		-- Whether dkp awards should be recorded automatically if all data can be auto filled (user is still prompted)
	["IncludeSubCaptain"] = false, -- Whether to include sub captain when awarding subs
	["SelectedTableId"] = 1, 		-- The last table that was being looked at
	["MiniMapButtonAngle"] = 1,
	["SilentMode"] = false,			-- 静默模式，关闭团队播报功能
		["RaidDkpReply"] = true,			-- 团队频道查DKP密语自动回复
	["QuickFloatEnabled"] = true,
	["AutoBackupEnabled"] = true,
	["PassAssignToSelf"] = false,   -- 流拍是否分配给自己，默认仅记录不分配
	["SubSettings"] = {
		["captain"] = "",
		["useCheckIn"] = false
	}
}

-- User options that are syncronized with the website
WebDKP_WebOptions = {
}

---------------------------------------------------
-- INITILIZATION
---------------------------------------------------
-- ================================
-- On load setup the slash event to will toggle the gui
-- and register for some events
-- ================================
-- In WoW 1.12 Lua 5.0, use 'this' instead of function parameters

-- 注意：不再使用UnitPopup_OnClick hook，改用安全的UIDropDownMenu实现

function ADKP_TrimText(text)
	if text == nil then return "" end
	text = tostring(text)
	text = string.gsub(text, "^%s*", "")
	text = string.gsub(text, "%s*$", "")
	return text
end

function ADKP_OnLoad()
	-- 确保有正确的frame引用
	local frame =  ADKP_Frame
	if not frame then
		ADKP_Print("错误：无法获取ADKP主框架引用")
		return
	end

	-- 主界面顶部标题追加版本号（XML 里 text="ADKP系统"，这里运行时改成 "ADKP系统 vX.Y"）
	local titleFs = getglobal("ADKP_FrameTitle")
	if titleFs and ADKP_VERSION then
		titleFs:SetText("ADKP系统 v" .. ADKP_VERSION)
	end
	
	-- 衰减功能已移除
	-- ADKP_Decay_OnLoad();
	
	-- 初始化替补设置，从ADKP_Options加载
	if not WebDKP_Options then
		WebDKP_Options = {}
	end
	
	-- 确保ADKP_Options中有SubSettings表
	if not WebDKP_Options["SubSettings"] then
		WebDKP_Options["SubSettings"] = {}
	end
	
	-- 初始化ADKP_SubAwardData
	if not ADKP_SubAwardData then
		ADKP_SubAwardData = {
			captain = "",
			members = {},
			bossName = "",
			reason = "",
			points = 0
		}
	end
	
	-- 确保所有字段都存在
	if not ADKP_SubAwardData.captain then ADKP_SubAwardData.captain = "" end
	if not ADKP_SubAwardData.members then ADKP_SubAwardData.members = {} end
	if not ADKP_SubAwardData.bossName then ADKP_SubAwardData.bossName = "" end
	if not ADKP_SubAwardData.reason then ADKP_SubAwardData.reason = "" end
	if not ADKP_SubAwardData.points then ADKP_SubAwardData.points = 0 end

	-- 从设置加载当前团的替补队长信息
	ADKP_SubAwardData.captain = ADKP_GetSubCaptain(ADKP_GetTableid())

	-- 初始化装备历史记录数据结构
	if not WebDKP_LootHistory then
		WebDKP_LootHistory = {}
	end
		
	-- Register for party / raid changes so we know to update the list of players in group
	frame:RegisterEvent("PARTY_MEMBERS_CHANGED");
	frame:RegisterEvent("RAID_ROSTER_UPDATE");
	frame:RegisterEvent("CHAT_MSG_WHISPER");
	frame:RegisterEvent("ITEM_TEXT_READY");
	frame:RegisterEvent("ADDON_LOADED");
	frame:RegisterEvent("CHAT_MSG_LOOT");
	frame:RegisterEvent("CHAT_MSG_PARTY");
	frame:RegisterEvent("CHAT_MSG_RAID");
	frame:RegisterEvent("CHAT_MSG_RAID_LEADER");
	frame:RegisterEvent("CHAT_MSG_RAID_WARNING");
	frame:RegisterEvent("CHAT_MSG_SYSTEM");
	frame:RegisterEvent("CHAT_MSG_GUILD");
	frame:RegisterEvent("ADDON_ACTION_FORBIDDEN");
	frame:RegisterEvent("UI_ERROR_MESSAGE");
	frame:RegisterEvent("LOOT_OPENED");
	frame:RegisterEvent("LOOT_CLOSED");

	-- 无论是否安装了SuperWOW，都使用CHAT_MSG_COMBAT_HOSTILE_DEATH事件
	-- 这样可以直接获取死亡目标的名字，避免GUID转换的问题
	frame:RegisterEvent("CHAT_MSG_COMBAT_HOSTILE_DEATH");
	frame:RegisterEvent("CHAT_MSG_COMBAT_FACTION_CHANGE");
	frame:RegisterEvent("CHAT_MSG_COMBAT_HONOR_GAIN");
	frame:RegisterEvent("CHAT_MSG_COMBAT_MISC_INFO");
	frame:RegisterEvent("CHAT_MSG_COMBAT_XP_GAIN");
	frame:RegisterEvent("CHAT_MSG_ADDON");
    
	-- ===== 右键菜单注册 =====
	-- 使用标准的UIDropDownMenu系统，不hook系统函数以避免冲突

	ADKP_OnEnable();
	
end



-- 注册聊天命令
SLASH_ADKP1 = "/adkp"
SlashCmdList["ADKP"] = ADKP_SlashCmdHandler



-- ================================
-- Called when the addon is enabled. 
-- Takes care of basic startup tasks: hide certain forms, 
-- get the people currently in the group, register for events, 
-- etc. 
-- ================================
function ADKP_OnEnable()
	ADKP_Frame:Hide();
	
	if ADKP_AwardDKP_Frame then ADKP_AwardDKP_Frame:Show() end
	if ADKP_LootListFrame then ADKP_LootListFrame:Hide() end
	if ADKP_Options_Frame then ADKP_Options_Frame:Hide() end
	
	if ADKP_AwardAllDKP_Frame then ADKP_AwardAllDKP_Frame:Hide() end
	if ADKP_AwardItem_Frame then ADKP_AwardItem_Frame:Hide() end
	
	if ADKP_Personal_Frame then ADKP_Personal_Frame:Hide() end
	
	ADKP_Options_Init();
	ADKP_UpdateSingleAdjustLabel();
	
	ADKP_UpdatePlayersInGroup();
	ADKP_UpdateTableToShow();
	
	-- 确保ADKP_Options表存在
	if not WebDKP_Options then
		WebDKP_Options = {}
	end
	
	-- 初始化静默模式设置
	if WebDKP_Options["SilentMode"] == nil then
		WebDKP_Options["SilentMode"] = false
	end
	
	-- 初始化BOSS排除名单设置
	if WebDKP_Options["ExcludedBosses"] == nil then
		WebDKP_Options["ExcludedBosses"] = {
            	"土堆", "活性剧毒",
        }
	end
	
	-- 初始化自定义BOSS名单设置
	if WebDKP_Options["BossPatterns"] == nil then
		WebDKP_Options["BossPatterns"] = {}
	end
	
	-- place a hook on the chat frame so we can filter out our whispers
	ADKP_Register_WhisperHook();
	
		--hooksecurefunc("SetItemRef",ADKP_ItemChatClick);

-- 为游戏原生玩家右键菜单添加DKP选项
ADKP_RegisterPopupMenu = function()
	-- 确保UnitPopupButtons存在
    if not UnitPopupButtons then return end
    
	-- 检查DKP扣分按钮是否已存在
    local buttonExists = false
    for i, button in ipairs(UnitPopupButtons) do
        if button == "ADKP_DEDUCT" then
            buttonExists = true
            break
        end
    end
    
	-- 如果不存在，则添加按钮
    if not buttonExists then
        table.insert(UnitPopupButtons, "ADKP_DEDUCT")
        table.insert(UnitPopupButtons, "ADKP_AWARD")
    end
    
	-- 设置按钮属性
    UnitPopupButtons["ADKP_DEDUCT"] = {
        text = "DKP扣分",
        dist = 0,
    }
    
    UnitPopupButtons["ADKP_AWARD"] = {
        text = "DKP加分",
        dist = 0,
    }
    
	-- 将按钮添加到相关的菜单中
    local addToMenus = {
        "FRIEND", "PARTY", "RAID_PLAYER", "GUILD", "COMMUNITIES_GUILD_MEMBER",
        "TARGET", "PLAYER", "COMMUNITIES_WOW_MEMBER"
    }
    
    for _, menu in ipairs(addToMenus) do
        if UnitPopupMenus[menu] then
            -- 检查是否已添加
            local deductExists = false
            local awardExists = false
            for i, button in ipairs(UnitPopupMenus[menu]) do
                if button == "ADKP_DEDUCT" then deductExists = true end
                if button == "ADKP_AWARD" then awardExists = true end
            end
            -- 在分隔线后添加我们的选项
            for i, button in ipairs(UnitPopupMenus[menu]) do
                if button == "CANCEL" then
                    if not deductExists then
                        table.insert(UnitPopupMenus[menu], i, "ADKP_DEDUCT")
                    end
                    if not awardExists then
                        table.insert(UnitPopupMenus[menu], i+1, "ADKP_AWARD")
                    end
                    break
                end
        end
    end
    
	-- 保存原始的UnitPopup_OnClick函数
    if not ADKP_OriginalUnitPopup_OnClick then
        ADKP_OriginalUnitPopup_OnClick = UnitPopup_OnClick
        UnitPopup_OnClick = ADKP_UnitPopup_OnClick
    end
end
end
-- 处理我们添加的右键菜单项点击
ADKP_UnitPopup_OnClick = function()
    if UIDROPDOWNMENU_MENU_VALUE == "ADKP_DEDUCT" then
        local unit = UIDROPDOWNMENU_INIT_MENU.unit
        local name = unit and UnitName(unit) or UIDROPDOWNMENU_INIT_MENU.name
        if name then
            ADKP_HandleDeduction(name)
        end
        return
    elseif UIDROPDOWNMENU_MENU_VALUE == "ADKP_AWARD" then
        local unit = UIDROPDOWNMENU_INIT_MENU.unit
        local name = unit and UnitName(unit) or UIDROPDOWNMENU_INIT_MENU.name
        if name then
            ADKP_HandleAward(name)
        end
        return
    end
    
	-- 调用原始函数处理其他选项
    ADKP_OriginalUnitPopup_OnClick()
end

-- 在插件加载时注册右键菜单
ADKP_RegisterPopupMenu();
  	if ( SetItemRef ~= ADKP_ItemChatClick ) then
		-- place a hook on item shift+clicks so we can get item details
		ADKP_ItemChatClick_Original = SetItemRef;
		SetItemRef = ADKP_ItemChatClick;
  	end
 	

end

-- ================================
-- Invoked when we recieve one of the requested events. 
-- Directs that event to the appropriate part of the addon
-- ================================
function ADKP_OnEvent()
	if(event=="CHAT_MSG_WHISPER") then
		ADKP_CHAT_MSG_WHISPER();
	elseif(event=="CHAT_MSG_PARTY" or event=="CHAT_MSG_RAID" or event=="CHAT_MSG_RAID_LEADER" or event=="CHAT_MSG_RAID_WARNING") then
		ADKP_CHAT_MSG_PARTY_RAID();
	elseif(event=="CHAT_MSG_SYSTEM") then
		if ADKP_Bid_HandleRollMessage then ADKP_Bid_HandleRollMessage(arg1); end
	elseif(event=="CHAT_MSG_GUILD") then
		ADKP_AutoInvite(arg2, arg1);
	elseif(event=="PARTY_MEMBERS_CHANGED") then
		ADKP_PARTY_MEMBERS_CHANGED();
	elseif(event=="RAID_ROSTER_UPDATE") then
		ADKP_RAID_ROSTER_UPDATE();
	elseif(event=="ADDON_LOADED") then
		ADKP_ADDON_LOADED();
	elseif(event=="CHAT_MSG_LOOT") then
		ADKP_Loot_Taken();
	elseif(event=="ADDON_ACTION_FORBIDDEN") then
		ADKP_Print(arg1.."  "..arg2);
	elseif(event=="UI_ERROR_MESSAGE") then
		ADKP_HandleUIError();
	elseif(event=="LOOT_OPENED") then
		ADKP_LOOT_OPENED();
	elseif(event=="LOOT_CLOSED") then
		ADKP_LOOT_CLOSED();
	elseif(event=="CHAT_MSG_ADDON") then
		ADKP_HandleAddonMessage(arg1, arg2, arg3, arg4);
	elseif(event=="RAW_COMBATLOG") then

	elseif(event=="CHAT_MSG_COMBAT_HOSTILE_DEATH") then   
		-- 兼容原有方式，当没有安装SuperWOW时使用
		ADKP_HandleCombatHostileDeath(arg1);
	end
end

-- 处理插件间通信消息
function ADKP_HandleAddonMessage(prefix, message, channel, sender)
	-- 解析消息，处理从HARDCORE频道发送的格式
	-- 格式为: 实际消息内容:目标玩家
	-- 不再需要解析格式为"玩家:队长"的消息，直接使用原始消息内容
	if prefix == "AMB_TBQQ" then
		-- 收到替补队长查询消息
		-- 检查消息内容是否是当前玩家的名字（忽略大小写），如果是，则回复团队成员列表
		local targetName = message
		-- 将两个名字都转换为小写进行比较，确保不区分大小写
		local playerName = UnitName("player")
		local currentPlayer = playerName and string.lower(playerName) or ""
		local targetPlayer = targetName and string.lower(targetName) or ""
		if currentPlayer == targetPlayer then
			-- DEFAULT_CHAT_FRAME:AddMessage("[ADKP] 收到查询，我是替补队长，正在发送团队成员列表", 0, 1, 0)
			ADKP_SendSubMemberList(sender)
			-- 如果对方设置了响应标志，也标记自己收到了查询
			if ADKP_SubAwardData then
				ADKP_SubAwardData.receivedResponse = true
			end
		else
			-- 不是发给自己的消息，忽略
			-- DEFAULT_CHAT_FRAME:AddMessage("[ADKP] 收到查询，但不是发给我的", 0, 1, 0)
		end
	-- AMB_TBFS 已改用密语发送，此处保留以兼容旧版
	end
end

-- 发送替补队员名单给请求者
-- ===================== 替补名单同步：传输编码与状态 =====================
-- 传输格式：SUB:名,名:战;名,名:法   （按职业归组，组尾带单字职业码；无职业组不带码）
-- 职业单字码表（编解码两侧共用）
ADKP_CLASS_CODE = {
	["战士"] = "战", ["牧师"] = "牧", ["术士"] = "术", ["德鲁伊"] = "德",
	["圣骑士"] = "骑", ["猎人"] = "猎", ["潜行者"] = "贼", ["萨满祭司"] = "萨", ["法师"] = "法",
}
ADKP_CLASS_DECODE = {
	["战"] = "战士", ["牧"] = "牧师", ["术"] = "术士", ["德"] = "德鲁伊",
	["骑"] = "圣骑士", ["猎"] = "猎人", ["贼"] = "潜行者", ["萨"] = "萨满祭司", ["法"] = "法师",
}

-- 重置一次替补同步会话的状态（各查询入口发起查询时调用）
function ADKP_ResetSubSyncState()
	if not ADKP_SubAwardData then
		ADKP_SubAwardData = {}
	end
	ADKP_SubAwardData.expectedCount = nil
	ADKP_SubAwardData.receivedCount = 0
	ADKP_SubAwardData.subSyncComplete = false
	ADKP_SubAwardData.subSyncAborted = false
	ADKP_SubAwardData.captainSkipped = false
	ADKP_SubAwardData.receivedResponse = false
end

-- 统计某个队长名下已收到的替补人数（键解析方式与 ADKP_GetSubMembersForAward 保持一致）
function ADKP_CountPendingSubMembers(captainName)
	if not ADKP_PendingSubMembers or not captainName or captainName == "" then
		return 0
	end
	local targetKey = nil
	if ADKP_PendingSubMembers[captainName] ~= nil then
		targetKey = captainName
	elseif ADKP_PendingSubMembers[string.lower(captainName)] ~= nil then
		targetKey = string.lower(captainName)
	else
		local lowerName = string.lower(captainName)
		for key, _ in pairs(ADKP_PendingSubMembers) do
			if string.lower(key) == lowerName then
				targetKey = key
				break
			end
		end
	end
	if not targetKey then
		return 0
	end
	local n = 0
	for _, _ in pairs(ADKP_PendingSubMembers[targetKey]) do
		n = n + 1
	end
	return n
end

local ADKP_SUB_ROSTER_MAX_ATTEMPTS = 3
local ADKP_SUB_ROSTER_RETRY_DELAY = 0.25

local function ADKP_CollectSubRosterSnapshot()
	local members = {}
	local seen = {}
	local expectedBefore = 0
	local expectedAfter = 0
	local stable = false
	local raidMemberCount = GetNumRaidMembers()
	local partyMemberCount = GetNumPartyMembers()

	local function addMember(name, class)
		if not name or name == "" then return end
		local key = string.lower(name)
		if seen[key] then return end
		seen[key] = true
		table.insert(members, { name = name, class = class })
	end

	if raidMemberCount > 0 then
		expectedBefore = raidMemberCount
		for i = 1, raidMemberCount do
			local name, _, _, _, class = GetRaidRosterInfo(i)
			addMember(name, class)
		end
		expectedAfter = GetNumRaidMembers()
		stable = expectedBefore == expectedAfter and table.getn(members) == expectedAfter
	elseif partyMemberCount > 0 then
		expectedBefore = partyMemberCount + 1
		for i = 1, partyMemberCount do
			local unit = "party" .. i
			addMember(UnitName(unit), UnitClass(unit))
		end
		addMember(UnitName("player"), UnitClass("player"))
		expectedAfter = GetNumPartyMembers() + 1
		stable = GetNumRaidMembers() == 0
			and expectedBefore == expectedAfter
			and table.getn(members) == expectedAfter
	else
		expectedBefore = 1
		addMember(UnitName("player"), UnitClass("player"))
		expectedAfter = 1
		stable = GetNumRaidMembers() == 0
			and GetNumPartyMembers() == 0
			and table.getn(members) == 1
	end

	return members, expectedBefore, table.getn(members), stable
end

function ADKP_SendSubMemberList(toPlayer, attempt, forceWhisper)
	-- 确保toPlayer不为空
	if not toPlayer or toPlayer == "" then
		ADKP_Print("错误: 目标玩家名为空")
		return false
	end

	attempt = tonumber(attempt) or 1
	local members, expectedCount, memberCount, stable = ADKP_CollectSubRosterSnapshot()
	if not stable then
		if attempt < ADKP_SUB_ROSTER_MAX_ATTEMPTS then
			local retryFrame = CreateFrame("Frame")
			retryFrame.elapsed = 0
			retryFrame:SetScript("OnUpdate", function()
				local elapsed = tonumber(arg1) or 0
				this.elapsed = (this.elapsed or 0) + elapsed
				if this.elapsed >= ADKP_SUB_ROSTER_RETRY_DELAY then
					this:SetScript("OnUpdate", nil)
					ADKP_SendSubMemberList(toPlayer, attempt + 1, forceWhisper)
				end
			end)
			return true
		end

		ADKP_SendWhisper(toPlayer, "SUB_ERROR:ROSTER_UNSTABLE:" .. memberCount .. ":" .. expectedCount)
		ADKP_Print("替补名单仍在变化，已取消发送残缺名单（读取 " .. memberCount .. "/" .. expectedCount .. "）")
		return false
	end

	if memberCount == 0 then
		ADKP_SendWhisper(toPlayer, "SUB_EMPTY")
	else
		-- 按职业归组（识别失败/无职业的进"无职业组"，由团长端兜底补职业）
		local groups = {}
		local groupByCode = {}
		local noClassGroup = nil
		for i = 1, memberCount do
			local m = members[i]
			local cls = m.class
			if cls and ADKP_NormalizeClassName then
				cls = ADKP_NormalizeClassName(cls)
			end
			local code = nil
			if cls then
				code = ADKP_CLASS_CODE[cls]
			end
			if code then
				local g = groupByCode[code]
				if not g then
					g = { code = code, names = {} }
					groupByCode[code] = g
					table.insert(groups, g)
				end
				table.insert(g.names, m.name)
			else
				if not noClassGroup then
					noClassGroup = { code = nil, names = {} }
					table.insert(groups, noClassGroup)
				end
				table.insert(noClassGroup.names, m.name)
			end
		end

		-- 装箱：以组为原子单位，每条消息不超过 200 字节
		-- （GUILD 频道信封"目的#来源#"要占 20~40 字节，200+信封仍在 255 上限内）
		-- 单组超长时组内拆分为多个子组，重复声明职业码
		local MAXBATCH = 200
		local units = {}
		for gi = 1, table.getn(groups) do
			local g = groups[gi]
			local overhead = 0
			if g.code then
				overhead = 1 + string.len(g.code)
			end
			local n = table.getn(g.names)
			local chunkStart = 1
			local chunkLen = 0
			for ni = 1, n do
				local nmLen = string.len(g.names[ni])
				local addLen = nmLen
				if chunkLen > 0 then
					addLen = addLen + 1
				end
				if chunkLen > 0 and chunkLen + addLen + overhead > MAXBATCH then
					local s = table.concat(g.names, ",", chunkStart, ni - 1)
					if g.code then
						s = s .. ":" .. g.code
					end
					table.insert(units, s)
					chunkStart = ni
					chunkLen = nmLen
				else
					chunkLen = chunkLen + addLen
				end
			end
			if chunkStart <= n then
				local s = table.concat(g.names, ",", chunkStart, n)
				if g.code then
					s = s .. ":" .. g.code
				end
				table.insert(units, s)
			end
		end

		local batches = {}
		local current = ""
		for ui = 1, table.getn(units) do
			local s = units[ui]
			if current == "" then
				current = s
			elseif string.len(current) + 1 + string.len(s) > MAXBATCH then
				table.insert(batches, current)
				current = s
			else
				current = current .. ";" .. s
			end
		end
		if current ~= "" then
			table.insert(batches, current)
		end

		for i = 1, table.getn(batches) do
			ADKP_SendWhisper(toPlayer, "SUB:" .. batches[i])
		end
		ADKP_SendWhisper(toPlayer, "SUB_COMPLETE:" .. memberCount)
	end

	DEFAULT_CHAT_FRAME:AddMessage("[ADKP] 已发送 " .. memberCount .. " 名替补队员信息", 0, 1, 0)

	if not ADKP_SubAwardData then
		ADKP_SubAwardData = {}
	end
	ADKP_SubAwardData.receivedResponse = true

	return true
end
-- 解析密语发来的替补数据
function ADKP_HandleSubWhisperData(fromPlayer, message)
	if not message then return end

	-- 数据消息: ADKP: SUB:名,名:战;名,名:法
	-- 按职业归组的传输格式：; 分组，组内 , 分名单，组尾 :单字职业码；无职业组不带码
	local _, _, data = string.find(message, "^ADKP: SUB:(.+)$")
	if data then
		for group in string.gfind(data, "[^;]+") do
			if group ~= "" then
				-- 找组内最后一个冒号：之前是逗号分隔的名单，之后是职业码
				local namesPart = group
				local code = nil
				local colonPos = nil
				local searchPos = 1
				while true do
					local p = string.find(group, ":", searchPos)
					if not p then break end
					colonPos = p
					searchPos = p + 1
				end
				if colonPos then
					namesPart = string.sub(group, 1, colonPos - 1)
					code = string.sub(group, colonPos + 1)
				end
				local cls = nil
				if code and code ~= "" then
					cls = ADKP_CLASS_DECODE[code]
				end
				for entryName in string.gfind(namesPart, "[^,]+") do
					if entryName ~= "" then
						if cls then
							ADKP_ReceiveSubMember(fromPlayer, entryName .. ":" .. cls .. ":" .. fromPlayer)
						else
							ADKP_ReceiveSubMember(fromPlayer, entryName .. ":" .. fromPlayer)
						end
					end
				end
			end
		end
		return
	end

	-- 替补队长在短暂重试后仍无法读取完整名册，立即中止本次替补加分。
	local _, _, receivedCount, expectedCount = string.find(
		message,
		"^ADKP: SUB_ERROR:ROSTER_UNSTABLE:(%d+):(%d+)$"
	)
	if receivedCount and expectedCount then
		if not ADKP_SubAwardData then
			ADKP_SubAwardData = {}
		end
		ADKP_SubAwardData.expectedCount = tonumber(expectedCount) or 0
		ADKP_SubAwardData.receivedCount = tonumber(receivedCount) or 0
		ADKP_SubAwardData.subSyncComplete = false
		ADKP_SubAwardData.subSyncAborted = true
		ADKP_SubAwardData.receivedResponse = false
		ADKP_Print(
			"|cffff0000替补队伍名单正在变化：读取 "
			.. ADKP_SubAwardData.receivedCount .. "/" .. ADKP_SubAwardData.expectedCount
			.. "，本次不加替补分。|r"
		)
		return
	end

	-- 完成消息: ADKP: SUB_COMPLETE:5
	local _, _, count = string.find(message, "^ADKP: SUB_COMPLETE:(.+)$")
	if count then
		ADKP_ReceiveSubMember(fromPlayer, "COMPLETE:" .. UnitName("player") .. ":" .. count)
		return
	end

	-- 空消息: ADKP: SUB_EMPTY
	if string.find(message, "^ADKP: SUB_EMPTY$") then
		if ADKP_SubAwardData then
			-- 空名单是合法的完整状态：应到 0、实收 0，核对通过
			ADKP_SubAwardData.expectedCount = 0
			ADKP_SubAwardData.receivedCount = 0
			ADKP_SubAwardData.subSyncComplete = true
			ADKP_SubAwardData.receivedResponse = true
		end
		return
	end
end


-- 接收替补队员信息
function ADKP_ReceiveSubMember(fromPlayer, memberName)
	-- 检查是否是完成通知消息
	if string.find(memberName, "^COMPLETE:") then
		local _, _, target, count = string.find(memberName, "^COMPLETE:(.+):(.+)")
		local announced = 0
		local storedCount = 0
		local senderIsCaptain = false
		if target and count then
			local captainName = fromPlayer or ""
			if ADKP_SubAwardData and ADKP_SubAwardData.captain then
				if string.lower(fromPlayer) == string.lower(ADKP_SubAwardData.captain) then
					captainName = ADKP_SubAwardData.captain
				end
			end

			local memberTable = nil
			if ADKP_PendingSubMembers then
				memberTable = ADKP_PendingSubMembers[captainName]
				if not memberTable then
					memberTable = ADKP_PendingSubMembers[string.lower(captainName)]
				end
			end

			local memberNames = {}
			if memberTable then
				local seen = {}
				for name, _ in pairs(memberTable) do
					if name and not seen[name] then
						seen[name] = true
						table.insert(memberNames, name)
					end
				end
			end
			table.sort(memberNames)
			local memberCount = table.getn(memberNames)
			if memberCount == 0 then
				memberCount = tonumber(count) or 0
			end

			-- ===== 名单完整性核对 =====
			-- 队长宣布的总人数 vs 本地实收人数；人数齐了才算接收完成。
			-- 勾选"替补队长加分"关闭时队长本人不入名单，应到人数相应减 1。
			announced = tonumber(count) or 0
			storedCount = table.getn(memberNames)
			senderIsCaptain = true
			if ADKP_SubAwardData and ADKP_SubAwardData.captain and ADKP_SubAwardData.captain ~= "" then
				senderIsCaptain = (string.lower(fromPlayer or "") == string.lower(ADKP_SubAwardData.captain))
			end
			if ADKP_SubAwardData and senderIsCaptain then
				ADKP_SubAwardData.expectedCount = announced
				ADKP_SubAwardData.receivedCount = storedCount
			end

			local reason = ""
			local points = 0
			if ADKP_SubAwardData then
				reason = ADKP_SubAwardData.reason or ""
				points = ADKP_SubAwardData.points or 0
			end
			local detailMessage = "替补队员信息接收完成"
			if captainName ~= "" then
				detailMessage = detailMessage .. ": 队长 " .. captainName
			end
			if reason ~= "" then
				detailMessage = detailMessage .. "，原因 " .. reason
			end
			if points ~= 0 then
				detailMessage = detailMessage .. "，分值 " .. points
			end
			detailMessage = detailMessage .. "，人数 " .. memberCount

			if memberCount > 0 and table.getn(memberNames) > 0 then
				local maxNames = 10
				local shownNames = {}
				for i = 1, math.min(maxNames, table.getn(memberNames)) do
					table.insert(shownNames, memberNames[i])
				end
				local namesText = table.concat(shownNames, ", ")
				if table.getn(memberNames) > maxNames then
					namesText = namesText .. " 等" .. (table.getn(memberNames) - maxNames) .. "人"
				end
				detailMessage = detailMessage .. "，名单 " .. namesText
			end

			local message = "[ADKP] " .. detailMessage
			DEFAULT_CHAT_FRAME:AddMessage(message, 0, 1, 0)
		end

		-- 设置接收响应标志：仅当人数核对通过（人数不齐则继续等尾包，直至超时）
		if ADKP_SubAwardData and senderIsCaptain then
			local effectiveExpected = announced
			if ADKP_SubAwardData.captainSkipped and effectiveExpected > 0 then
				effectiveExpected = effectiveExpected - 1
			end
			if storedCount >= effectiveExpected then
				ADKP_SubAwardData.subSyncComplete = true
				ADKP_SubAwardData.receivedResponse = true
			else
				ADKP_SubAwardData.subSyncComplete = false
			end
		end
		return
	end
	
	-- 检查是否是无成员消息
	if string.find(memberName, "^NO_MEMBERS:") then
		if ADKP_SubAwardData then
			ADKP_SubAwardData.receivedResponse = true
		end
		return
	end
	
	-- 从队员名字中提取真实玩家名（提取冒号前面的部分）
	local realPlayerName = memberName
	local receivedClass = nil
	local _, _, parsedName, parsedClass = string.find(memberName, "^([^:]+):([^:]+):")
	if parsedName and parsedClass then
		realPlayerName = parsedName
		receivedClass = parsedClass
	else
		local _, _, extractedName = string.find(memberName, "^(.+):")
		if extractedName then
			realPlayerName = extractedName
		end
	end
	if receivedClass and ADKP_NormalizeClassName then
		receivedClass = ADKP_NormalizeClassName(receivedClass)
	end
	
	-- 检查是否是替补队长自己，如果是则不记录
	local isCaptainSelf = false
	if ADKP_SubAwardData and ADKP_SubAwardData.captain then
		local lowerFromPlayer = string.lower(fromPlayer)
		local lowerRealPlayerName = string.lower(realPlayerName)
		if lowerFromPlayer == lowerRealPlayerName then
			isCaptainSelf = true
		end
	end
	
	-- 如果是队长自己，则不处理（勾选"替补队长加分"时例外）
	if isCaptainSelf and not (WebDKP_Options and WebDKP_Options["IncludeSubCaptain"]) then
		-- 队长本人不入名单，核对时应到人数需减 1
		if ADKP_SubAwardData then
			ADKP_SubAwardData.captainSkipped = true
		end
		return
	end
	
	-- 初始化替补队员列表
    if not ADKP_PendingSubMembers then
        ADKP_PendingSubMembers = {}
    end
	
	-- 查找正确的队长名字键（考虑大小写）
	local targetCaptain = fromPlayer
	local captainMatched = false
	
	if ADKP_SubAwardData and ADKP_SubAwardData.captain then
		local lowerFromPlayer = string.lower(fromPlayer)
		local lowerTargetCaptain = string.lower(ADKP_SubAwardData.captain)
		
		if lowerFromPlayer == lowerTargetCaptain then
			-- 如果大小写不同但名字相同，使用目标队长的名字作为键
			targetCaptain = ADKP_SubAwardData.captain
			captainMatched = true
		end
	end
	
	-- 如果没有匹配到目标队长，尝试遍历现有的队长列表进行模糊匹配
	if not captainMatched and ADKP_PendingSubMembers then
		local lowerFromPlayer = string.lower(fromPlayer)
		for existingCaptain, _ in pairs(ADKP_PendingSubMembers) do
			if string.lower(existingCaptain) == lowerFromPlayer then
				targetCaptain = existingCaptain
				captainMatched = true
				break
			end
		end
	end
	
	-- 确保使用小写版本也能被找到，增加兼容性
	local lowerTargetCaptain = string.lower(targetCaptain)
	
	-- 记录收到的队员信息（使用真实玩家名）
	if not ADKP_PendingSubMembers[targetCaptain] then
		ADKP_PendingSubMembers[targetCaptain] = {}
	end
	
	-- 同时在小写版本下也记录，确保后续查找能成功
	if not ADKP_PendingSubMembers[lowerTargetCaptain] then
		ADKP_PendingSubMembers[lowerTargetCaptain] = {}
	end
	
	-- 存储队员信息到两个版本的队长键下
	local existingEntry = ADKP_PendingSubMembers[targetCaptain][realPlayerName]
	local isRegistered = true
	if type(existingEntry) == "table" and existingEntry.isRegistered ~= nil then
		isRegistered = existingEntry.isRegistered
	elseif type(existingEntry) == "boolean" then
		isRegistered = existingEntry
	end

	local entry = existingEntry
	if type(entry) ~= "table" then
		entry = { isRegistered = isRegistered }
	end
	if receivedClass and receivedClass ~= "" then
		entry.class = receivedClass
	end

	ADKP_PendingSubMembers[targetCaptain][realPlayerName] = entry
	ADKP_PendingSubMembers[lowerTargetCaptain][realPlayerName] = entry

	-- 尾包迟到补偿：若 SUB_COMPLETE 已处理而人数未齐，收到新队员时重新核对
	if ADKP_SubAwardData and ADKP_SubAwardData.expectedCount and not ADKP_SubAwardData.subSyncComplete then
		local stored = ADKP_CountPendingSubMembers(fromPlayer)
		ADKP_SubAwardData.receivedCount = stored
		local eff = ADKP_SubAwardData.expectedCount
		if ADKP_SubAwardData.captainSkipped and eff > 0 then
			eff = eff - 1
		end
		if stored >= eff then
			ADKP_SubAwardData.subSyncComplete = true
			ADKP_SubAwardData.receivedResponse = true
		end
	end
end

-- ================================
-- Invoked when addon finishes loading data from the saved variables file. 
-- Should parse the players options and update the gui.
-- ================================
function ADKP_ADDON_LOADED()
	if( WebDKP_DkpTable == nil) then
		WebDKP_DkpTable = {};
	end
	
	-- 确保ADKP_Options表存在
	if not WebDKP_Options then
		WebDKP_Options = {}
	end
	
	--load up the last loot table that was being viewed
	ADKP_Frame.selectedTableid = WebDKP_Options["SelectedTableId"];

	-- 确保至少有一个默认团，并验证 selectedTableid 有效
	ADKP_EnsureDefaultTable()

	ADKP_UpdateTableToShow(); --update who is in the table
	ADKP_UpdateTable();       --update the gui
	
	-- set the mini map position
	ADKP_MinimapButton_SetPositionAngle(WebDKP_Options["MiniMapButtonAngle"]);

	-- 恢复小地图图标的禁用/启用视觉状态
	ADKP_UpdateMinimapButtonState();

	-- 初始化替补设置
	ADKP_InitSubSettings();
	
	-- 快捷浮窗显示/隐藏（仅RAID且勾选开启时显示）
	if ADKP_QuickFloat_UpdateVisibility then
		ADKP_QuickFloat_UpdateVisibility()
	end
end






---------------------------------------------------
-- EVENT HANDLERS (Party changed / gui toggled / etc.)
---------------------------------------------------

-- ================================
-- Called by slash command. Toggles gui. 
-- ================================
-- ================================
-- 插件总开关（小地图图标右键切换）
-- 禁用后：击杀弹窗、密语/团队查分回复、替补同步响应、悬浮窗全部停止
-- ================================
function ADKP_IsAddonDisabled()
	return WebDKP_Options and WebDKP_Options["AddonDisabled"] == true
end

function ADKP_UpdateMinimapButtonState()
	if not ADKP_MinimapButton then return end
	if ADKP_IsAddonDisabled() then
		ADKP_MinimapButton:SetAlpha(0.35)
	else
		ADKP_MinimapButton:SetAlpha(1.0)
	end
end

-- ================================
-- 小地图图标悬停提示
-- ================================
function ADKP_MinimapButton_OnEnter()
	local button = this or ADKP_MinimapButton
	if not button or not GameTooltip then
		return
	end
	GameTooltip:SetOwner(button, "ANCHOR_LEFT")
	GameTooltip:SetText("ADKP 系统 v" .. (ADKP_VERSION or ""))
	if ADKP_IsAddonDisabled() then
		GameTooltip:AddLine("当前状态：已禁用", 1, 0.2, 0.2)
	else
		GameTooltip:AddLine("当前状态：已启用", 0.2, 1, 0.2)
	end
	GameTooltip:AddLine("左键：打开界面", 1, 1, 1)
	GameTooltip:AddLine("右键：激活/禁用插件", 1, 1, 1)
	GameTooltip:AddLine("左键按住：拖拽图标", 1, 1, 1)
	GameTooltip:Show()
end

function ADKP_MinimapButton_OnLeave()
	if GameTooltip then
		GameTooltip:Hide()
	end
end

function ADKP_ToggleAddonEnabled()
	if not WebDKP_Options then
		WebDKP_Options = {}
	end
	WebDKP_Options["AddonDisabled"] = not ADKP_IsAddonDisabled()
	if WebDKP_Options["AddonDisabled"] then
		if ADKP_Frame then
			ADKP_Frame:Hide()
		end
		if ADKP_QuickFloat_UpdateVisibility then
			ADKP_QuickFloat_UpdateVisibility()
		end
		ADKP_Print("ADKP 已禁用：击杀弹窗/查分回复/替补同步/悬浮窗已停止（右键小地图图标重新开启）")
	else
		if ADKP_QuickFloat_UpdateVisibility then
			ADKP_QuickFloat_UpdateVisibility()
		end
		ADKP_Print("ADKP 已启用")
	end
	ADKP_UpdateMinimapButtonState()
end

function ADKP_ToggleGUI()
	-- self:Print("Should toggle gui now...")
	-- ADKP_Refresh()
	if ( ADKP_Frame:IsShown() ) then
		ADKP_Frame:Hide();
	else
		ADKP_Frame:Show();	
		ADKP_Tables_DropDown_OnLoad();
		ADKP_Options_Autofill_DropDown_OnLoad();
		ADKP_Options_Autofill_DropDown_Init();
	end
	
	-- ADKP_Bid_ToggleUI();
	
end



-- ================================
-- 处理打开尸体事件
-- ================================
function ADKP_LOOT_OPENED()
	if ADKP_QuickBid_HideQualitySettings then
		ADKP_QuickBid_HideQualitySettings()
	end

	-- 检查是否有自动分配任务正在进行
	if ADKP_AutoLootData.isAssigning and GetNumLootItems() > 0 then
		-- 有可分配物品了，尝试自动分配
		if ADKP_AutoLootData.frame then
			ADKP_AutoLootData.frame.statusText:SetText("正在分配 "..ADKP_AutoLootData.currentItem.." 给 "..ADKP_AutoLootData.currentPlayer);
		end
		ADKP_TryAssignLoot();
	end

	-- 打开掉落窗口时，「拍」按钮亮红
	if GetNumLootItems and GetNumLootItems() > 0 then
		ADKP_UpdateQuickFloatBidBtn(true)
	end
end

-- 关闭掉落窗口，「拍」按钮变灰
function ADKP_LOOT_CLOSED()
	ADKP_UpdateQuickFloatBidBtn(false)
end

local ADKP_QuickBidQualityFrame = nil

function ADKP_QuickBid_HideQualitySettings()
	if ADKP_QuickBidQualityFrame then
		ADKP_QuickBidQualityFrame:Hide()
	end
end

local ADKP_QuickBidQualityOptions = {
	{ key = "legendary", label = "传说", quality = 5, color = { 1, 0.5, 0 } },
	{ key = "epic", label = "史诗", quality = 4, color = { 0.64, 0.21, 0.93 } },
	{ key = "rare", label = "精良", quality = 3, color = { 0, 0.44, 0.87 } },
	{ key = "uncommon", label = "优秀", quality = 2, color = { 0.12, 1, 0 } },
	{ key = "common", label = "一般", quality = 1, color = { 1, 1, 1 } }
}

local function ADKP_QuickBid_InitQualityFilter()
	if not WebDKP_Options then WebDKP_Options = {} end
	if not WebDKP_Options["QuickBidQualityFilter"] then
		WebDKP_Options["QuickBidQualityFilter"] = {}
	end
	local filter = WebDKP_Options["QuickBidQualityFilter"]
	for i = 1, table.getn(ADKP_QuickBidQualityOptions) do
		local key = ADKP_QuickBidQualityOptions[i].key
		if filter[key] == nil then filter[key] = true end
	end
	return filter
end

local function ADKP_QuickBid_GetQualityKey(quality)
	if quality == 0 then return "common" end
	for i = 1, table.getn(ADKP_QuickBidQualityOptions) do
		local option = ADKP_QuickBidQualityOptions[i]
		if option.quality == quality then return option.key end
	end
	return nil
end

local function ADKP_QuickBid_IsQualityEnabled(quality)
	local key = ADKP_QuickBid_GetQualityKey(quality)
	if not key then return false end
	return ADKP_QuickBid_InitQualityFilter()[key] == true
end

function ADKP_QuickBid_ShowQualitySettings()
	if ADKP_QuickBidQualityFrame and ADKP_QuickBidQualityFrame:IsShown() then
		ADKP_QuickBidQualityFrame:Hide()
		return
	end

	local filter = ADKP_QuickBid_InitQualityFilter()
	if not ADKP_QuickBidQualityFrame then
		local quickFloatFrame = getglobal("ADKP_QuickFloatFrame")
		local frame = CreateFrame("Frame", "ADKP_QuickBidQualityFrame", quickFloatFrame or UIParent)
		frame:SetWidth(300)
		frame:SetHeight(68)
		frame:SetFrameStrata("DIALOG")
		frame:SetClampedToScreen(true)
		frame:EnableMouse(true)
		frame:SetBackdrop({
			bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
			edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
			tile = true, tileSize = 32, edgeSize = 32,
			insets = { left = 11, right = 12, top = 12, bottom = 11 }
		})

		local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		title:SetPoint("TOP", frame, "TOP", 0, -12)
		title:SetText("一键拍卖品质设定")

		local closeButton = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
		closeButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -2)
		closeButton:SetScript("OnClick", function() frame:Hide() end)

		frame.checks = {}
		for i = 1, table.getn(ADKP_QuickBidQualityOptions) do
			local option = ADKP_QuickBidQualityOptions[i]
			local check = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
			check:SetWidth(22)
			check:SetHeight(22)
			check:SetPoint("TOPLEFT", frame, "TOPLEFT", 12 + (i - 1) * 56, -32)
			check.qualityKey = option.key
			check:SetScript("OnClick", function()
				ADKP_QuickBid_InitQualityFilter()[this.qualityKey] = this:GetChecked() and true or false
			end)

			local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
			label:SetPoint("LEFT", check, "RIGHT", 1, 0)
			label:SetText(option.label)
			label:SetTextColor(option.color[1], option.color[2], option.color[3])
			frame.checks[i] = check
		end

		frame:Hide()
		ADKP_QuickBidQualityFrame = frame
	end

	for i = 1, table.getn(ADKP_QuickBidQualityOptions) do
		local option = ADKP_QuickBidQualityOptions[i]
		ADKP_QuickBidQualityFrame.checks[i]:SetChecked(filter[option.key] == true)
	end
	ADKP_QuickBidQualityFrame:ClearAllPoints()
	local quickFloatFrame = getglobal("ADKP_QuickFloatFrame")
	if quickFloatFrame then
		ADKP_QuickBidQualityFrame:SetPoint("TOP", quickFloatFrame, "BOTTOM", 0, -4)
	else
		ADKP_QuickBidQualityFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	end
	ADKP_QuickBidQualityFrame:Show()
end

-- 更新「拍」按钮状态：red=true 亮红执行拍卖，false 灰色打开品质设置
function ADKP_UpdateQuickFloatBidBtn(red)
	local btn = ADKP_QuickFloatFrame and ADKP_QuickFloatFrame.bidBtn
	if not btn then return end
	local t = getglobal("ADKP_QuickFloatBidBtnText")
	if red then
		btn:SetNormalTexture("Interface\\Buttons\\UI-Panel-Button-Up")
		if t then t:SetTextColor(1, 0.82, 0) end
	else
		btn:SetNormalTexture("Interface\\Buttons\\UI-Panel-Button-Disabled")
		if t then t:SetTextColor(1, 1, 1) end
	end
end

-- 「拍」按钮：按已选择的品质把当前掉落装备加入竞拍队列
function ADKP_StartBossLootBid()
	local count = GetNumLootItems and GetNumLootItems() or 0
	if count == 0 then
		ADKP_Print("掉落列表为空")
		return
	end
	local filteredQueue = {}
	for i = 1, count do
		local link = GetLootSlotLink(i)
		local _, _, _, quality = GetLootSlotInfo(i)
		if link and ADKP_QuickBid_IsQualityEnabled(quality) then
			table.insert(filteredQueue, { item = link, time = 0 })
		end
	end
	if table.getn(filteredQueue) == 0 then
		ADKP_Print("没有符合品质筛选的可竞拍装备")
		return
	end
	ADKP_BidQueue = filteredQueue
	ADKP_Bid_ShowUI()
	local first = table.remove(ADKP_BidQueue, 1)
	ADKP_Bid_StartBid(first.item, first.time)
end

-- ================================
-- Called when the party / raid configuration changes. 
-- Causes the list of current group memebers to be refreshed
-- so that filters will be ok
-- ================================
function ADKP_PARTY_MEMBERS_CHANGED()
	-- self:Print("Party / Raid change");
	ADKP_UpdatePlayersInGroup();
	ADKP_UpdateTableToShow();
	ADKP_UpdateTable();
	if ADKP_QuickFloat_UpdateVisibility then
		ADKP_QuickFloat_UpdateVisibility()
	end
end
function ADKP_RAID_ROSTER_UPDATE()
	-- self:Print("Party / Raid change");
	ADKP_UpdatePlayersInGroup();
	ADKP_UpdateTableToShow();
	ADKP_UpdateTable();
	if ADKP_QuickFloat_UpdateVisibility then
		ADKP_QuickFloat_UpdateVisibility()
	end
end

-- ================================
-- Handles an incoming whisper. Directs it to the modules
-- who are interested in it. 
-- ================================
function ADKP_CHAT_MSG_WHISPER()
	ADKP_WhisperDKP_Event();
	ADKP_Bid_Event();
	-- 获取消息发送者名称(arg2)和消息内容(arg1)
	local name = arg2;
	local message = arg1;
	ADKP_HandleSubWhisperData(name, message);
	ADKP_AutoInvite(name, message);
end

-- ================================
-- Event handler for all party and raid
-- chat messages. 
-- ================================
function ADKP_CHAT_MSG_PARTY_RAID()
	if ADKP_Bid_HandleTransmogChat then
		ADKP_Bid_HandleTransmogChat(event, arg2, arg1);
	end
	ADKP_Bid_Event();
	ADKP_RaidDkpQuery();
end

-- 团队/小队频道查 DKP 自动回复
function ADKP_RaidDkpQuery()
	-- 插件总开关：禁用时不再响应团队/小队频道查分
	if ADKP_IsAddonDisabled() then
		return
	end

	-- 队长、助理、分配者响应
	local hasAuth = IsRaidLeader() or IsRaidOfficer()
	if not hasAuth and GetNumRaidMembers() > 0 then
		local lootMethod, _, masterLooter = GetLootMethod()
		if lootMethod == "master" and masterLooter then
			local mlName = nil
			if masterLooter == 0 then
				mlName = UnitName("player")
			else
				mlName = UnitName("raid"..masterLooter)
			end
			hasAuth = (mlName == UnitName("player"))
		end
	end
	if not hasAuth and not (GetNumRaidMembers() == 0 and IsPartyLeader()) then
		return
	end
	-- 检查开关
	if WebDKP_Options and WebDKP_Options["RaidDkpReply"] == false then
		return
	end
	local name = arg2
	local msg = arg1
	if not name or not msg then return end
	-- 严格匹配 "dkp"
	if string.lower(msg) ~= "dkp" then return end

	local tableid = ADKP_GetTableid()
	if not WebDKP_DkpTable[name] then return end

	local dkp = WebDKP_DkpTable[name]["dkp_"..tableid]
	if dkp == nil then dkp = 0 end
	ADKP_SendWhisper(name, "目前你的DKP为：  " .. dkp)
end

---------------------------------------------------
-- GUI EVENT HANDLERS
-- (Handle events raised by the gui and direct
--  events to the other parts of the addon)
---------------------------------------------------
-- ================================
-- Called by the refresh button. Refreshes the people displayed 
-- in your party. 
-- ================================
function ADKP_Refresh()
	ADKP_UpdatePlayersInGroup();
	ADKP_UpdateTableToShow();
	ADKP_UpdateTable();
end

-- ================================
-- Refreshes the roster displayed in the current list mode
-- ================================
function ADKP_RefreshCurrentMode()
	local mode = ADKP_ListMode or "raid"
	if mode == "raid" then
		ADKP_Refresh()
	elseif mode == "sub" then
		if ADKP_SubSync_RefreshRoster then
			ADKP_SubSync_RefreshRoster()
		end
	elseif mode == "out" then
		ADKP_Refresh()
	end
end

-- ================================
-- Called when a player clicks on different tabs. 
-- Causes certain frames to be hidden and the appropriate
-- frame to be displayed
-- ================================
-- In WoW 1.12 Lua 5.0, use 'this' instead of function parameters
function ADKP_Tab_OnClick()
	local button = this
	if not button then
		ADKP_Print("错误：无法获取按钮引用")
		return
	end
	
	-- 隐藏所有右侧框架
	if ADKP_AwardDKP_Frame then ADKP_AwardDKP_Frame:Hide() end
	if ADKP_LootListFrame then ADKP_LootListFrame:Hide() end
	if ADKP_Options_Frame then ADKP_Options_Frame:Hide() end
	if ADKP_ShareGroupsFrame then ADKP_ShareGroupsFrame:Hide() end
	
	-- 确保隐藏遗留的框架
	if ADKP_AwardAllDKP_Frame then ADKP_AwardAllDKP_Frame:Hide() end
	if ADKP_AwardItem_Frame then ADKP_AwardItem_Frame:Hide() end
	
	if ADKP_Personal_Frame then ADKP_Personal_Frame:Hide() end

	-- 数据列表为全宽模式：进入时隐藏左侧名单操作区，离开时恢复
	local ADKP_sideEls = { "ADKP_ClassFiltersFrame", "ADKP_SingleAdjustFrame", "ADKP_NameSearchBox", "ADKP_SearchLabel", "ADKP_FrameModeRaid", "ADKP_FrameModeSub", "ADKP_FrameModeOut", "ADKP_FrameSubRefresh" }
	local ADKP_hideSide = ( button:GetID() == 2 or button:GetID() == 4 )
	for _, elName in ipairs(ADKP_sideEls) do
		local el = getglobal(elName)
		if el then
			if ADKP_hideSide then el:Hide() else el:Show() end
		end
	end
	
	if ( button:GetID() == 1 ) then
		if ADKP_AwardDKP_Frame then ADKP_AwardDKP_Frame:Show() end
		ADKP_UpdateCaptainLabel()
	elseif ( button:GetID() == 2 ) then
		-- 确保已创建历史记录面板
		if not ADKP_LootListFrame then
			ADKP_CreateLootListFrame()
		end
		if ADKP_LootListFrame then ADKP_LootListFrame:Show() end
		ADKP_UpdateLootList()
	elseif ( button:GetID() == 3 ) then
		if ADKP_Options_Frame then ADKP_Options_Frame:Show() end
		-- 首次进入「帮助」页时懒加载创建可折叠操作说明面板
		if not ADKP_HelpPanel then
			ADKP_CreateHelpPanel()
		end
		ADKP_Options_Init()
	elseif ( button:GetID() == 4 ) then
		if ADKP_Share_CreateTab then ADKP_Share_CreateTab() end
		if ADKP_ShareGroupsFrame then ADKP_ShareGroupsFrame:Show() end
		if ADKP_Share_UpdateTab then ADKP_Share_UpdateTab() end
	end
	
	PlaySound("igCharacterInfoTab");
	
	-- 刷新左侧列表
	ADKP_UpdateTableToShow()
	ADKP_UpdateTable()
end

-- ================================
-- Called when a player clicks on a column header on the table
-- Changes the sorting options / asc&desc. 
-- Causes the table display to be refreshed afterwards
-- to player instantly sees changes
-- ================================
function WebDPK2_SortBy(id)
	if ( ADKP_LogSort["curr"] == id ) then
		ADKP_LogSort["way"] = abs(ADKP_LogSort["way"]-1);
	else
		ADKP_LogSort["curr"] = id;
		if( id == 1) then
			ADKP_LogSort["way"] = 0;
		elseif ( id == 2 ) then
			ADKP_LogSort["way"] = 0;
		elseif ( id == 3 ) then
			ADKP_LogSort["way"] = 1; --columns with numbers need to be sorted different first in order to get DESC right
		else
			ADKP_LogSort["way"] = 1; --columns with numbers need to be sorted different first in order to get DESC right
		end
		
	end
	-- update table so we can see sorting changes
	ADKP_UpdateTable();
end

-- ================================
-- Called when the user clicks on a filter checkbox. 
-- Changes the filter setting and updates table
-- ================================
function ADKP_ToggleFilter(filterName)
	ADKP_Filters[filterName] = abs(ADKP_Filters[filterName]-1);
	ADKP_UpdateTableToShow();
	ADKP_UpdateTable();
	

end

-- ================================
-- Called when user clicks on 'check all'
-- Sets all filters to on and updates table display
-- ================================
function ADKP_CheckAllFilters()
	ADKP_SetFilterState("Druid",1);
	ADKP_SetFilterState("Hunter",1);
	ADKP_SetFilterState("Mage",1);
	ADKP_SetFilterState("Rogue",1);
	ADKP_SetFilterState("Shaman",1);
	ADKP_SetFilterState("Paladin",1);
	ADKP_SetFilterState("Priest",1);
	ADKP_SetFilterState("Warrior",1);
	ADKP_SetFilterState("Warlock",1);
	ADKP_UpdateTableToShow();
	ADKP_UpdateTable();
end

-- ================================
-- Called when user clicks on 'uncheck all'
-- Sets all filters to off and updates table display
-- ================================
function ADKP_UncheckAllFilters()
	ADKP_SetFilterState("Druid",0);
	ADKP_SetFilterState("Hunter",0);
	ADKP_SetFilterState("Mage",0);
	ADKP_SetFilterState("Rogue",0);
	ADKP_SetFilterState("Shaman",0);
	ADKP_SetFilterState("Paladin",0);
	ADKP_SetFilterState("Priest",0);
	ADKP_SetFilterState("Warrior",0);
	ADKP_SetFilterState("Warlock",0);
	ADKP_UpdateTableToShow();
	ADKP_UpdateTable();
end

-- ================================
-- Small helper method for filters - updates
-- checkbox state and updates filter setting in data structure
-- ================================
function ADKP_SetFilterState(filter,newState)
	local checkBox = getglobal("ADKP_FiltersFrameClass"..filter);
	checkBox:SetChecked(newState);
	ADKP_Filters[filter] = newState;
end

-- ================================
-- Called when mouse goes over a dkp line entry. 
-- If that player is not selected causes that row
-- to become 'highlighted'
-- ================================
function ADKP_HandleMouseOver()
	local frame = arg1 or this
	if not frame then
		return
	end
	local playerName = getglobal(frame:GetName().."Name"):GetText();
	if ( not playerName or not WebDKP_DkpTable or not WebDKP_DkpTable[playerName] ) then
		    return;
	end
	if( not WebDKP_DkpTable[playerName]["Selected"] ) then
		getglobal(frame:GetName() .. "Background"):SetVertexColor(0.2, 0.2, 0.7, 0.5);
	end
end

-- ================================
-- Called when a mouse leaes a dkp line entry. 
-- If that player is not selected, causes that row
-- to return to normal (none highlighted)
-- ================================
function ADKP_HandleMouseLeave()
	local frame = this
	if not frame then
		return
	end
	local playerName = getglobal(frame:GetName().."Name"):GetText();
	if ( not playerName or not WebDKP_DkpTable or not WebDKP_DkpTable[playerName] ) then
		    return;
	end
	if( not WebDKP_DkpTable[playerName]["Selected"] ) then
		getglobal(frame:GetName() .. "Background"):SetVertexColor(0, 0, 0, 0);
	end
end

-- ================================
-- Called when the user clicks on a player entry. Causes 
-- that entry to either become selected or normal
-- and updates the dkp table with the change
-- ================================
function ADKP_SelectPlayerToggle()
	-- 检查是否是右键点击
    if arg1 == "RightButton" then
        -- 获取玩家名称
        local playerName = getglobal(this:GetName().."Name"):GetText();
        if ( not playerName or not WebDKP_DkpTable or not WebDKP_DkpTable[playerName] ) then
            return;
        end
        -- 创建右键菜单
        ADKP_PlayerRightClickMenu_Initialize(playerName, this);
        ToggleDropDownMenu(1, nil, ADKP_PlayerRightClickMenu, "cursor", 0, 0);
        return;
    end
    
	-- 左键点击的单选逻辑
	local playerName = getglobal(this:GetName().."Name"):GetText();
	if ( not playerName or not WebDKP_DkpTable or not WebDKP_DkpTable[playerName] ) then
		    return;
	end
	local wasSelected = WebDKP_DkpTable[playerName]["Selected"];
	
	
	if wasSelected then
		WebDKP_DkpTable[playerName]["Selected"] = false;
		ADKP_Frame.selectedPlayer = nil;
	else
		WebDKP_DkpTable[playerName]["Selected"] = true;
		ADKP_Frame.selectedPlayer = playerName;
	end
	
	-- 更新快速调分面板上的玩家名字标签
	ADKP_UpdateSingleAdjustLabel();
	
	-- 更新表格以重绘背景
	ADKP_UpdateTable();
end

-- ================================  
-- 玩家右键菜单初始化函数  
-- ================================
function ADKP_PlayerRightClickMenu_Initialize(playerName, parentFrame)
	-- 创建菜单框架（如果不存在）
    if not ADKP_PlayerRightClickMenu then
        ADKP_PlayerRightClickMenu = CreateFrame("Frame", "ADKP_PlayerRightClickMenu", UIParent, "UIDropDownMenuTemplate");
    end
    
	-- 保存当前玩家名称供菜单使用
    ADKP_PlayerRightClickMenu.playerName = playerName;
    
	-- 初始化菜单
    UIDropDownMenu_Initialize(ADKP_PlayerRightClickMenu, ADKP_PlayerRightClickMenu_Create);
end

-- ================================  
-- 创建右键菜单内容  
-- ================================
function ADKP_PlayerRightClickMenu_Create()
    local playerName = ADKP_PlayerRightClickMenu.playerName;
    
	-- 添加查看DKP选项
    local info = {};
    info.text = "查看DKP: "..playerName;
    info.func = function() 
        for k, v in pairs(WebDKP_DkpTable) do
            if type(v) == "table" then
                v["Selected"] = false;
            end
        end
        WebDKP_DkpTable[playerName]["Selected"] = true;
        ADKP_Frame.selectedPlayer = playerName;
        ADKP_UpdateSingleAdjustLabel();
        ADKP_Frame:Show();
        ADKP_UpdateTable();
    end;
    UIDropDownMenu_AddButton(info);
    
	-- 添加查看详细信息选项
    info = {};
    info.text = "查看详细信息";
    info.func = function() 
        ADKP_ShowPlayerDetails(playerName);
    end;
    UIDropDownMenu_AddButton(info);
    
	-- 添加查看历史记录选项
    info = {};
    info.text = "查看历史记录";
    info.func = function() 
        ADKP_ShowPlayerHistory(playerName);
    end;
    UIDropDownMenu_AddButton(info);
    
	-- 添加分隔线
    info = {};
    info.text = "";
    info.disabled = 1;
    UIDropDownMenu_AddButton(info);
    
	-- 添加扣分选项
    info = {};
    info.text = "扣分";
    info.func = function() ADKP_HandleDeduction(playerName); end;
    UIDropDownMenu_AddButton(info);
    
	-- 添加加分选项
    info = {};
    info.text = "加分";
    info.func = function() ADKP_HandleAward(playerName); end;
    UIDropDownMenu_AddButton(info);
    
	-- 添加分隔线
    info = {};
    info.text = "";
    info.disabled = 1;
    UIDropDownMenu_AddButton(info);
    
	-- 添加设为替补选项（如果在团队中）
    if GetNumRaidMembers() > 0 then
        info = {};
        info.text = "设为替补";
        info.func = function() ADKP_HandleSub(playerName); end;
        UIDropDownMenu_AddButton(info);
    end
    
	-- 添加分隔线
    info = {};
    info.text = "";
    info.disabled = 1;
    UIDropDownMenu_AddButton(info);
    
	-- 添加团队管理选项（如果在团队中）
    if GetNumRaidMembers() > 0 and (IsRaidLeader() or IsRaidOfficer()) then
        -- 取消邀请（带确认）
        info = {};
        info.text = "取消邀请";
        info.func = function() 
            StaticPopupDialogs["ADKP_UNINVITE_CONFIRM"] = {
                text = "确定要取消邀请 "..playerName.." 吗？",
                button1 = "确定",
                button2 = "取消",
                OnAccept = function()
                    UninviteByName(playerName);
                    ADKP_Print("已取消邀请 "..playerName);
                end,
                timeout = 0,
                whileDead = true,
                hideOnEscape = true,
                preferredIndex = 3,
            };
            StaticPopup_Show("ADKP_UNINVITE_CONFIRM");
        end;
        UIDropDownMenu_AddButton(info);
        
        -- 设为队长
        info = {};
        info.text = "设为队长";
        info.func = function() 
            PromoteByName(playerName);
            ADKP_Print("已将 "..playerName.." 设为队长");
        end;
        UIDropDownMenu_AddButton(info);
        
        -- 设为助理
        info = {};
        info.text = "设为助理";
        info.func = function() 
            PromoteToAssistant(playerName);
            ADKP_Print("已将 "..playerName.." 设为助理");
        end;
        UIDropDownMenu_AddButton(info);
        
        -- 降职
        info = {};
        info.text = "降职";
        info.func = function() 
            DemoteByName(playerName);
            ADKP_Print("已将 "..playerName.." 降职");
        end;
        UIDropDownMenu_AddButton(info);
    end

    -- 添加分隔线
    info = {};
    info.text = "";
    info.disabled = 1;
    UIDropDownMenu_AddButton(info);

    if ADKP_Share_ShowManager then
        info = {};
        info.text = "大小号管理";
        info.func = function()
            ADKP_Share_ShowManager(playerName);
        end;
        UIDropDownMenu_AddButton(info);

        info = {};
        info.text = "";
        info.disabled = 1;
        UIDropDownMenu_AddButton(info);
    end

    -- 添加删除该玩家选项
    info = {};
    info.text = "删除该玩家";
    info.func = function() 
        StaticPopupDialogs["ADKP_DELETE_PLAYER_CONFIRM"] = {
            text = "确定要将玩家 "..playerName.." 从 DKP 列表中删除吗？此操作不可逆！",
            button1 = "确定",
            button2 = "取消",
            OnAccept = function()
                WebDKP_DkpTable[playerName] = nil;
                ADKP_Print("已从 DKP 列表中删除玩家: "..playerName);
                if ADKP_UpdateTableToShow then ADKP_UpdateTableToShow() end
                if ADKP_UpdateTable then ADKP_UpdateTable() end
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            preferredIndex = 3,
        };
        StaticPopup_Show("ADKP_DELETE_PLAYER_CONFIRM");
    end;
    UIDropDownMenu_AddButton(info);
end

-- ================================  
-- 处理扣分操作  
-- ================================
function ADKP_HandleDeduction(playerName)
	-- 确保玩家在DKP表中
    if not WebDKP_DkpTable[playerName] then
        ADKP_Print(playerName .. " 不在DKP列表中！");
        return;
    end
    
	-- 勾选该玩家（支持多选，不取消其他玩家的选择）
    WebDKP_DkpTable[playerName]["Selected"] = true;
    
	-- 显示ADKP主窗口
    ADKP_Frame:Show();
    
	-- 切换到DKP奖惩页面（通常是第二个标签）
    getglobal("ADKP_FrameTab2"):Click();
    
	-- 刷新表格显示，确保选中状态正确显示
    ADKP_UpdateTable();
    
	-- 统计当前选中的玩家数量
    local selectedCount = 0;
    for name, data in pairs(WebDKP_DkpTable) do
        if data["Selected"] then
            selectedCount = selectedCount + 1;
        end
    end
    
	-- 提示用户已选中玩家，并说明可以继续选择其他玩家
    ADKP_Print("已选中 " .. playerName .. "，当前共选中 " .. selectedCount .. " 名玩家。可继续右键选择其他玩家进行批量扣分。");
end

-- ================================  
-- 处理加分操作  
-- ================================
function ADKP_HandleAward(playerName)
	-- 确保玩家在DKP表中
    if not WebDKP_DkpTable[playerName] then
        ADKP_Print(playerName .. " 不在DKP列表中！");
        return;
    end
    
	-- 勾选该玩家
    WebDKP_DkpTable[playerName]["Selected"] = true;
    
	-- 显示ADKP主窗口
    ADKP_Frame:Show();
    
	-- 切换到DKP奖惩页面（通常是第二个标签）
    getglobal("ADKP_FrameTab2"):Click();
    
	-- 刷新表格显示
    ADKP_UpdateTable();
    
	-- 提示用户已选中玩家
    ADKP_Print("已选中 " .. playerName .. "，请在DKP奖惩页面输入加分信息。");
end

-- ================================  
-- 显示玩家详细信息  
-- ================================
function ADKP_ShowPlayerDetails(playerName)
	-- 确保玩家在DKP表中
    if not WebDKP_DkpTable[playerName] then
        ADKP_Print(playerName .. " 不在DKP列表中！");
        return;
    end
    
    local playerData = WebDKP_DkpTable[playerName];
    local tableid = ADKP_GetTableid();
    local playerDkp = playerData["dkp_"..tableid] or 0;
    local playerClass = playerData["class"] or "未知职业";
    local playerGuild = playerData["guild"] or "未知公会";
    local playerTier = floor((playerDkp-1)/ADKP_TierInterval);
    local isSub = playerData["IsSub"] or false;
    local isSelected = playerData["Selected"] or false;
    
	-- 显示详细信息
    ADKP_Print("=== " .. playerName .. " 的详细信息 ===");
    ADKP_Print("职业: " .. playerClass);
    ADKP_Print("公会: " .. playerGuild);
    ADKP_Print("当前DKP: " .. playerDkp);
    ADKP_Print("阶层: " .. playerTier);
    ADKP_Print("替补状态: " .. (isSub and "是" or "否"));
    ADKP_Print("选中状态: " .. (isSelected and "已选中" or "未选中"));
    
	-- 显示主窗口并选中该玩家
    ADKP_Frame:Show();
    ADKP_UpdateTable();
end

-- ================================  
-- 显示玩家历史记录  
-- ================================
function ADKP_ShowPlayerHistory(playerName)
	-- 确保玩家在DKP表中
    if not WebDKP_DkpTable[playerName] then
        ADKP_Print(playerName .. " 不在DKP列表中！");
        return;
    end
    
	-- 显示ADKP主窗口并切换到日志页面
    ADKP_Frame:Show();
    getglobal("ADKP_FrameTab3"):Click(); -- 切换到日志标签
    
	-- 如果没有日志数据，提示用户
    if not WebDKP_Log or not next(WebDKP_Log) then
        ADKP_Print("没有找到 " .. playerName .. " 的历史记录。");
        return;
    end
    
	-- 筛选该玩家的相关记录
    local playerHistory = {};
    for key, entry in pairs(WebDKP_Log) do
        if type(entry) == "table" and entry.awarded and entry.awarded[playerName] then
            table.insert(playerHistory, {
                date = entry.date or "未知时间",
                reason = entry.reason or "未知原因",
                points = entry.points or 0,
                zone = entry.zone or "未知区域",
                awardedby = entry.awardedby or "未知操作者"
            });
        end
    end
    
	-- 按时间排序（最新的在前）
    table.sort(playerHistory, function(a, b)
        return (a.date or "") > (b.date or "");
    end);
    
	-- 计算历史记录数量（Lua 5.0兼容方式）
    local historyCount = 0;
    for _ in pairs(playerHistory) do
        historyCount = historyCount + 1;
    end
    
	-- 显示历史记录
    if historyCount > 0 then
        ADKP_Print("=== " .. playerName .. " 的DKP历史记录 ===");
        local count = 0;
        for _, record in ipairs(playerHistory) do
            if count < 10 then -- 只显示最近10条记录
                local pointsText = "";
                if record.points > 0 then
                    pointsText = "+" .. record.points;
                else
                    pointsText = tostring(record.points);
                end
                ADKP_Print(string.format("[%s] %s (%s) - %s 由 %s 操作", 
                    record.date, record.reason, pointsText, record.zone, record.awardedby));
                count = count + 1;
            end
        end
        if historyCount > 10 then
            ADKP_Print("... 还有 " .. (historyCount - 10) .. " 条记录");
        end
    else
        ADKP_Print("没有找到 " .. playerName .. " 的历史记录。");
    end
end

-- ================================  
-- 处理替补操作  
-- ================================
function ADKP_HandleSub(playerName)
	-- 确保玩家在DKP表中
    if not WebDKP_DkpTable[playerName] then
        ADKP_Print(playerName .. " 不在DKP列表中！");
        return;
    end
    
	-- 确保在团队中
    if GetNumRaidMembers() == 0 then
        ADKP_Print("只有在团队中才能设置替补状态！");
        return;
    end
    
	-- 切换替补状态
    if WebDKP_DkpTable[playerName]["IsSub"] then
        WebDKP_DkpTable[playerName]["IsSub"] = false;
        ADKP_Print(playerName .. " 已取消替补状态。");
    else
        WebDKP_DkpTable[playerName]["IsSub"] = true;
        ADKP_Print(playerName .. " 已设为替补。");
    end
    
	-- 刷新表格显示
    ADKP_UpdateTable();
end



-- ================================
-- Selects all players in the dkp table and updates 
-- table display
-- ================================
function ADKP_SelectAll()
	local tableid = ADKP_GetTableid();
	for k, v in pairs(WebDKP_DkpTable) do
		if ( type(v) == "table" ) then
			local playerName = k; 
			local playerClass = v["class"];
			local playerDkp = v["dkp_"..tableid];
			if ( playerDkp == nil ) then
				v["dkp_"..tableid] = 0;
				playerDkp = 0;
			end
			local playerTier = floor((playerDkp-1)/ADKP_TierInterval);
			if (ADKP_ShouldDisplay(playerName, playerClass, playerDkp, playerTier)) then
				WebDKP_DkpTable[playerName]["Selected"] = true;
			else
				WebDKP_DkpTable[playerName]["Selected"] = false;
			end
		end
	end
	ADKP_UpdateTable();
	if ADKP_UpdateSingleAdjustLabel then ADKP_UpdateSingleAdjustLabel() end
end

-- ================================
-- Deselect all players and update table display
-- ================================
function ADKP_UnselectAll()
	for k, v in pairs(WebDKP_DkpTable) do
		if ( type(v) == "table" ) then
			local playerName = k; 
			WebDKP_DkpTable[playerName]["Selected"] = false;
		end
	end
	ADKP_UpdateTable();
	if ADKP_UpdateSingleAdjustLabel then ADKP_UpdateSingleAdjustLabel() end
end

-- ================================
-- 多团管理：默认团 / 新建 / 删除 / 切换
-- WebDKP_Tables 格式与 WebDKP 站点兼容：{ [id] = { id=id, name=名字 } }
-- ================================

-- 确保至少有一个默认团（首次使用或 WebDKP_Tables 为空时调用）
function ADKP_EnsureDefaultTable()
    if not WebDKP_Tables then WebDKP_Tables = {} end
    -- 检查是否有任何团存在
    local hasTable = false
    for key, entry in pairs(WebDKP_Tables) do
        if type(entry) == "table" then hasTable = true; break end
    end
    if not hasTable then
        WebDKP_Tables[1] = { id = 1, name = "DKP" }
    end
    -- 验证 selectedTableid 指向的团是否存在，不存在则切到第一个可用团
    local curId = ADKP_Frame.selectedTableid or WebDKP_Options["SelectedTableId"] or 1
    local found = false
    for key, entry in pairs(WebDKP_Tables) do
        if type(entry) == "table" and entry.id == curId then found = true; break end
    end
    if not found then
        -- 切到第一个可用团
        for key, entry in pairs(WebDKP_Tables) do
            if type(entry) == "table" and entry.id then
                curId = entry.id
                found = true
                break
            end
        end
    end
    ADKP_Frame.selectedTableid = curId
    WebDKP_Options["SelectedTableId"] = curId
end

-- 获取当前最大的 tableid（用于新建团分配 id）
function ADKP_GetMaxTableId()
    local maxId = 0
    if WebDKP_Tables then
        for key, entry in pairs(WebDKP_Tables) do
            if type(entry) == "table" and type(entry.id) == "number" and entry.id > maxId then
                maxId = entry.id
            end
        end
    end
    return maxId
end

-- 新建团（id = 最大+1，自动切换到新团）
function ADKP_CreateTable(name)
    if not name or name == "" then
        ADKP_Print("错误：团名不能为空")
        return
    end
    name = string.gsub(name, "^%s+", "")
    name = string.gsub(name, "%s+$", "")
    if name == "" then
        ADKP_Print("错误：团名不能为空")
        return
    end
    if not WebDKP_Tables then WebDKP_Tables = {} end
    local newId = ADKP_GetMaxTableId() + 1
    WebDKP_Tables[newId] = { id = newId, name = name }
    ADKP_Print("已创建团队：" .. name .. "（id=" .. newId .. "）")
    ADKP_SelectTable(newId)
    ADKP_Tables_DropDown_OnLoad()
    return newId
end

-- 删除团（物理清理所有相关数据）
function ADKP_DeleteTable(tableid)
    if not tableid then return end
    if not WebDKP_Tables or not WebDKP_Tables[tableid] then
        ADKP_Print("错误：找不到要删除的团队")
        return
    end
    -- 防止删除最后一个团
    local count = 0
    for key, entry in pairs(WebDKP_Tables) do
        if type(entry) == "table" then count = count + 1 end
    end
    if count <= 1 then
        ADKP_Print("错误：至少需要保留一个团队，无法删除")
        return
    end

    local tableName = WebDKP_Tables[tableid].name or tableid

    -- 1. 清理 WebDKP_DkpTable 里所有玩家的 dkp_<id> 字段（兼容历史无下划线变体）
    local fieldA = "dkp_" .. tableid
    local fieldB = "dkp" .. tableid
    if WebDKP_DkpTable then
        for playerName, data in pairs(WebDKP_DkpTable) do
            if type(data) == "table" then
                data[fieldA] = nil
                data[fieldB] = nil
            end
        end
    end

    -- 2. 清理 WebDKP_Log 里属于该团的记录（先收集 key 再删，跳过 Version）
    if WebDKP_Log then
        local toDelete = {}
        for logKey, entry in pairs(WebDKP_Log) do
            if logKey ~= "Version" and type(entry) == "table" and entry.tableid == tableid then
                table.insert(toDelete, logKey)
            end
        end
        for i = 1, table.getn(toDelete) do
            WebDKP_Log[toDelete[i]] = nil
        end
    end

    -- 3. 清理替补队长设置（按团独立存储的 captains）
    if WebDKP_Options and WebDKP_Options["SubSettings"] and WebDKP_Options["SubSettings"]["captains"] then
        WebDKP_Options["SubSettings"]["captains"][tableid] = nil
    end

    -- 3.5 清理该团在 SV 里的备份指针（避免删团后残留无效指针）
    --     磁盘上的备份文件不删，保留为历史归档；用户仍可手动 ADKP_ImportSpecificVersion 取回
    if WebDKP_Options and WebDKP_Options["LatestBackup"] then
        for charKey, teamData in pairs(WebDKP_Options["LatestBackup"]) do
            if type(teamData) == "table" then
                teamData[tableid] = nil
            end
        end
    end

    -- 4. 删除团定义
    WebDKP_Tables[tableid] = nil
    ADKP_Print("已删除团队：" .. tableName .. "（含其所有 DKP 数据和日志）")

    -- 5. 若删的是当前团，切到第一个可用团
    if ADKP_Frame.selectedTableid == tableid then
        local firstId = nil
        for key, entry in pairs(WebDKP_Tables) do
            if type(entry) == "table" and entry.id then
                firstId = entry.id
                break
            end
        end
        if firstId then
            ADKP_SelectTable(firstId)
        end
    end

    ADKP_Tables_DropDown_OnLoad()
end

-- 切换团（统一入口：改 selectedTableid + 持久化 + 联动刷新）
function ADKP_SelectTable(tableid)
    if not tableid then return end
    -- 验证目标团存在
    local exists = false
    if WebDKP_Tables then
        for key, entry in pairs(WebDKP_Tables) do
            if type(entry) == "table" and entry.id == tableid then exists = true; break end
        end
    end
    if not exists then
        ADKP_Print("错误：找不到目标团队")
        return
    end
    ADKP_Frame.selectedTableid = tableid
    WebDKP_Options["SelectedTableId"] = tableid
    ADKP_Tables_DropDown_Init()
    ADKP_UpdateTableToShow()
    ADKP_UpdateTable()
    if ADKP_Share_UpdateTab then ADKP_Share_UpdateTab() end
    -- 刷新替补队长输入框（按团独立）
    if ADKP_Tab1_SyncChecks then ADKP_Tab1_SyncChecks() end
end

-- ================================
-- Invoked when the gui loads up the drop down list of
-- available dkp tables.
-- ================================
function ADKP_Tables_DropDown_OnLoad()
	UIDropDownMenu_Initialize(ADKP_Tables_DropDown, ADKP_Tables_DropDown_Init);
	-- 始终显示团切换下拉框（单团时也可操作新建/删除）
	ADKP_Tables_DropDown:Show();
end
-- ================================
-- Invoked when the drop down list of available tables
-- needs to be redrawn. Populates it with data 
-- from the tables data structure and sets up an 
-- event handler
-- ================================
-- 新建团弹窗（输入团名）
function ADKP_ShowCreateTableDialog()
    if not StaticPopupDialogs then StaticPopupDialogs = {} end
    StaticPopupDialogs["ADKP_CREATE_TABLE"] = {
        text = "请输入新团队的名称：",
        button1 = "创建",
        button2 = "取消",
        hasEditBox = 1,
        timeout = 0,
        whileDead = 1,
        hideOnEscape = 1,
        OnAccept = function()
            local editBox = getglobal(this:GetParent():GetName() .. "EditBox")
            local name = editBox and editBox:GetText() or ""
            if name and name ~= "" then
                ADKP_CreateTable(name)
            end
        end,
    }
    StaticPopup_Show("ADKP_CREATE_TABLE")
end

-- 删除团确认弹窗
function ADKP_ShowDeleteTableDialog(tableid)
    if not tableid then return end
    if not WebDKP_Tables or not WebDKP_Tables[tableid] then return end
    local tableName = WebDKP_Tables[tableid].name or tostring(tableid)
    if not StaticPopupDialogs then StaticPopupDialogs = {} end
    StaticPopupDialogs["ADKP_DELETE_TABLE"] = {
        text = "确定要删除团队「" .. tableName .. "」吗？\n该团队的所有 DKP 数据和日志将被永久删除，不可恢复！",
        button1 = "删除",
        button2 = "取消",
        timeout = 0,
        whileDead = 1,
        hideOnEscape = 1,
        OnAccept = function()
            ADKP_DeleteTable(tableid)
        end,
    }
    StaticPopup_Show("ADKP_DELETE_TABLE")
end

function ADKP_Tables_DropDown_Init()
	if( ADKP_Frame.selectedTableid == nil ) then
		ADKP_Frame.selectedTableid = 1;
	end
	local info;
	local selected = "";
	if ( WebDKP_Tables ~= nil and next(WebDKP_Tables)~=nil ) then
		for key, entry in pairs(WebDKP_Tables) do
			if ( type(entry) == "table" ) then
				info = { };
				info.text = entry.name or  key;
				info.value = entry["id"];
				info.func = ADKP_Tables_DropDown_OnClick;
				if ( entry["id"] == ADKP_Frame.selectedTableid ) then
					info.checked = ( entry["id"] == ADKP_Frame.selectedTableid );
					selected = info.text;
				end
				UIDropDownMenu_AddButton(info);
			end
		end
	end
	-- 分隔线 + 新建/删除入口
	info = { }
	info.text = "新建团队..."
	info.value = "CREATE"
	info.func = ADKP_Tables_DropDown_OnClick
	UIDropDownMenu_AddButton(info)
	info = { }
	info.text = "删除当前团队"
	info.value = "DELETE"
	info.func = ADKP_Tables_DropDown_OnClick
	UIDropDownMenu_AddButton(info)
	UIDropDownMenu_SetSelectedName(ADKP_Tables_DropDown, selected );
	UIDropDownMenu_SetWidth(120, ADKP_Tables_DropDown);
end

-- ================================
-- Called when the user switches between
-- a different dkp table.
-- ================================
-- In WoW 1.12 Lua 5.0, use 'this' instead of function parameters
function ADKP_Tables_DropDown_OnClick()
	local button = this
	if not button then
		return
	end
	-- 特殊菜单项：新建/删除
	if button.value == "CREATE" then
		ADKP_ShowCreateTableDialog()
		return
	end
	if button.value == "DELETE" then
		ADKP_ShowDeleteTableDialog(ADKP_Frame.selectedTableid)
		return
	end
	-- 普通团切换
	ADKP_SelectTable(button.value)
end


-- (ADKP_ToggleMapValidation 已移除：地图区域验证功能已删除)




-- ================================
-- MiniMap Scrolling code. 
-- Credit goes to Outfitter and WoWWiki for the know how 
-- of how to pull this off. 
-- ================================

-- ================================
-- Called when the user presses the mouse button down on the
-- mini map button. Remembers that position in case they
-- attempt to start dragging
-- ================================
function ADKP_MinimapButton_MouseDown(self)
	-- Remember where the cursor was in case the user drags
	local button = self or  ADKP_MinimapButton
	if not button then
		return
	end
	
	local	vCursorX, vCursorY = GetCursorPosition();
	
	vCursorX = vCursorX / button:GetEffectiveScale();
	vCursorY = vCursorY / button:GetEffectiveScale();
	
	ADKP_MinimapButton.CursorStartX = vCursorX;
	ADKP_MinimapButton.CursorStartY = vCursorY;
	
	local	vCenterX, vCenterY = ADKP_MinimapButton:GetCenter();
	local	vMinimapCenterX, vMinimapCenterY = Minimap:GetCenter();
	
	ADKP_MinimapButton.CenterStartX = vCenterX - vMinimapCenterX;
	ADKP_MinimapButton.CenterStartY = vCenterY - vMinimapCenterY;
end

-- ================================
-- Called when the user starts to drag. Shows a frame that is registered
-- to recieve on update signals, we can then have its event handler
-- check to see the current mouse position and update the mini map button
-- correctly
-- ================================
function ADKP_MinimapButton_DragStart()
	ADKP_MinimapButton.IsDragging = true;
	ADKP_UpdateFrame:Show();
end

-- ================================
-- Users stops dragging. Ends the timer
-- ================================
function ADKP_MinimapButton_DragEnd()
	ADKP_MinimapButton.IsDragging = false;
	ADKP_UpdateFrame:Hide();
end

-- ================================
-- Updates the position of the mini map button. Should be called
-- via the on update method of the update frame
-- ================================
function ADKP_MinimapButton_UpdateDragPosition(self)
	-- Remember where the cursor was in case the user drags
	local button = self or  ADKP_MinimapButton
	if not button then
		return
	end
	local	vCursorX, vCursorY = GetCursorPosition();
	
	vCursorX = vCursorX / button:GetEffectiveScale();
	vCursorY = vCursorY / button:GetEffectiveScale();
	
	local	vCursorDeltaX = vCursorX - ADKP_MinimapButton.CursorStartX;
	local	vCursorDeltaY = vCursorY - ADKP_MinimapButton.CursorStartY;
	
	--
	
	local	vCenterX = ADKP_MinimapButton.CenterStartX + vCursorDeltaX;
	local	vCenterY = ADKP_MinimapButton.CenterStartY + vCursorDeltaY;
	
	-- Calculate the angle
	
	local	vAngle = math.atan2(vCenterX, vCenterY);
	
	-- Set the new position
	
	ADKP_MinimapButton_SetPositionAngle(vAngle);
end

-- ================================
-- Helper method. Helps restrict a given angle from occuring within a restricted angle
-- range. Returns where the angle should be pushed to - before or after the resitricted
-- range. Used to block the minimap button from appear behind the default ui buttons
-- ================================
function ADKP_RestrictAngle(pAngle, pRestrictStart, pRestrictEnd)
	if ( pAngle == nil ) then
		return pRestrictStart;
	end
	if ( pRestrictStart == nil or pRestrictStart == nil) then
		return pAngle;
	end

	if pAngle <= pRestrictStart
	or pAngle >= pRestrictEnd then
		return pAngle;
	end
	
	local	vDistance = (pAngle - pRestrictStart) / (pRestrictEnd - pRestrictStart);
	
	if vDistance > 0.5 then
		return pRestrictEnd;
	else
		return pRestrictStart;
	end
end

-- ================================
-- Sets the position of the mini map button based on the passed angle. 
-- Restricts the button from appear over any of the default ui buttons. 
-- ================================
function ADKP_MinimapButton_SetPositionAngle(pAngle)
	local	vAngle = pAngle;
	
	-- Restrict the angle from going over the date/time icon or the zoom in/out icons
	
	local	vRestrictedStartAngle = nil;
	local	vRestrictedEndAngle = nil;
	
	if GameTimeFrame:IsVisible() then
		if MinimapZoomIn:IsVisible()
		or MinimapZoomOut:IsVisible() then
			vAngle = ADKP_RestrictAngle(vAngle, 0.4302272732931596, 2.930420793963121);
		else
			vAngle = ADKP_RestrictAngle(vAngle, 0.4302272732931596, 1.720531504573905);
		end
		
	elseif MinimapZoomIn:IsVisible()
	or MinimapZoomOut:IsVisible() then
		vAngle = ADKP_RestrictAngle(vAngle, 1.720531504573905, 2.930420793963121);
	end
	
	-- Restrict it from the tracking icon area
	
	vAngle = ADKP_RestrictAngle(vAngle, -1.290357134304173, -0.4918423429923585);
	
	--
	
	local	vRadius = 80;
	
	vCenterX = math.sin(vAngle) * vRadius;
	vCenterY = math.cos(vAngle) * vRadius;
	
	ADKP_MinimapButton:SetPoint("CENTER", "Minimap", "CENTER", vCenterX - 1, vCenterY - 1);
	
	WebDKP_Options["MiniMapButtonAngle"] = vAngle;
	--gOutfitter_Settings.Options.MinimapButtonAngle = vAngle;
end

-- ================================
-- Event handler for the update frame. Updates the minimap button
-- if it is currently being dragged. 
-- ================================
-- In WoW 1.12 Lua 5.0, OnUpdate handlers don't receive parameters directly
function ADKP_OnUpdate()
	if ADKP_MinimapButton.IsDragging then
		ADKP_MinimapButton_UpdateDragPosition();
	end
end



-- ================================
-- Helper method. Called whenever a player clicks on shift click
-- ================================
function ADKP_ItemChatClick(link, text, button)
	
	-- do a search for 'player'. If it can be found... this is a player link, not an item link. It can be ignored
	local idx = strfind(text, "player");
	
	if( idx == nil ) then
		-- check to see if the bidding frame wants to do anything with the information
		ADKP_Bid_ItemChatClick(link, text, button);
		
		-- put the item text into the award editbox as long as the table frame is visible
		if ( IsShiftKeyDown()) then
			local _,itemName,_ = ADKP_GetItemInfo(link); 
			ADKP_AwardItem_FrameItemName:SetText(itemName);
		end
	end
	ADKP_ItemChatClick_Original(link, text, button);
end

---------------------------------------------------
-- 自动分配物品功能
---------------------------------------------------

-- 全局变量
ADKP_AutoLootData = {
	isAssigning = false,
	currentPlayer = nil,
	currentItem = nil,
	currentItemLink = nil,
	currentCost = 0,
	onComplete = nil,
	pendingId = nil,
	recordRef = nil,
	awaitingResult = false,
	resultDeadline = 0,
	frame = nil
};

ADKP_AutoLootQueue = ADKP_AutoLootQueue or {}
ADKP_UnassignedLoot = ADKP_UnassignedLoot or {}
ADKP_UnassignedLootCounter = ADKP_UnassignedLootCounter or 0
ADKP_UnassignedLootPage = ADKP_UnassignedLootPage or 1
ADKP_UNASSIGNED_PAGE_SIZE = 3

local function ADKP_FindUnassignedLoot(id)
	for i = 1, table.getn(ADKP_UnassignedLoot) do
		if ADKP_UnassignedLoot[i].id == id then
			return ADKP_UnassignedLoot[i], i
		end
	end
	return nil, nil
end

function ADKP_UpdateUnassignedLootWindow()
	local frame = ADKP_UnassignedLootFrame
	if not frame then return end
	local count = table.getn(ADKP_UnassignedLoot)
	if count == 0 then
		frame:Hide()
		return
	end

	local totalPages = math.ceil(count / ADKP_UNASSIGNED_PAGE_SIZE)
	if ADKP_UnassignedLootPage > totalPages then ADKP_UnassignedLootPage = totalPages end
	if ADKP_UnassignedLootPage < 1 then ADKP_UnassignedLootPage = 1 end
	frame.summary:SetText("有 " .. count .. " 件物品未分配成功。")

	local startIndex = (ADKP_UnassignedLootPage - 1) * ADKP_UNASSIGNED_PAGE_SIZE + 1
	for rowIndex = 1, ADKP_UNASSIGNED_PAGE_SIZE do
		local row = frame.rows[rowIndex]
		local entry = ADKP_UnassignedLoot[startIndex + rowIndex - 1]
		if entry then
			row.pendingId = entry.id
			row.itemText:SetText(entry.itemLink or entry.itemName or "未知物品")
			row.detailText:SetText("分配目标：" .. (entry.assignmentPlayer or entry.player or "未知玩家") .. "    原因：" .. (entry.reason or "未知原因"))
			if entry.retrying then row.retryButton:Disable() else row.retryButton:Enable() end
			row:Show()
		else
			row.pendingId = nil
			row:Hide()
		end
	end

	frame.pageText:SetText(ADKP_UnassignedLootPage .. " / " .. totalPages)
	if ADKP_UnassignedLootPage > 1 then frame.prevButton:Enable() else frame.prevButton:Disable() end
	if ADKP_UnassignedLootPage < totalPages then frame.nextButton:Enable() else frame.nextButton:Disable() end
	frame:Show()
end

function ADKP_CreateUnassignedLootWindow()
	if ADKP_UnassignedLootFrame then return ADKP_UnassignedLootFrame end
	local frame = CreateFrame("Frame", "ADKP_UnassignedLootFrame", UIParent)
	frame:SetWidth(320)
	frame:SetHeight(320)
	-- 仅借用竞拍窗坐标定位；父级仍为 UIParent，竞拍窗关闭后本窗保持显示。
	frame:SetPoint("TOPLEFT", ADKP_BidFrame, "TOPRIGHT", 10, -205)
	frame:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		tile = true, tileSize = 32, edgeSize = 32,
		insets = { left = 11, right = 12, top = 12, bottom = 11 }
	})
	frame:SetFrameStrata("DIALOG")
	frame:EnableMouse(true)
	frame:SetMovable(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", function() this:StartMoving() end)
	frame:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)

	local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", frame, "TOPLEFT", 22, -18)
	title:SetText("未分配物品")

	local summary = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	summary:SetPoint("TOPLEFT", frame, "TOPLEFT", 22, -44)
	summary:SetWidth(270)
	summary:SetJustifyH("LEFT")
	frame.summary = summary

	local closeButton = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	closeButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -6, -6)
	closeButton:SetScript("OnClick", function() ADKP_ClearUnassignedLoot() end)

	frame.rows = {}
	for i = 1, ADKP_UNASSIGNED_PAGE_SIZE do
		local row = CreateFrame("Frame", nil, frame)
		row:SetWidth(288)
		row:SetHeight(68)
		row:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -68 - (i - 1) * 71)

		local bg = row:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints(row)
		bg:SetTexture(0.12, 0.12, 0.16, 0.8)

		local itemText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		itemText:SetPoint("TOPLEFT", row, "TOPLEFT", 8, -6)
		itemText:SetWidth(272)
		itemText:SetHeight(14)
		itemText:SetJustifyH("LEFT")
		itemText:SetNonSpaceWrap(false)
		row.itemText = itemText

		local detailText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		detailText:SetPoint("TOPLEFT", row, "TOPLEFT", 8, -22)
		detailText:SetWidth(272)
		detailText:SetHeight(14)
		detailText:SetJustifyH("LEFT")
		detailText:SetNonSpaceWrap(false)
		row.detailText = detailText

		local retryButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
		retryButton:SetWidth(65)
		retryButton:SetHeight(22)
		retryButton:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 8, 5)
		retryButton:SetText("重试分配")
		retryButton:SetScript("OnClick", function() ADKP_RetryUnassignedLoot(this:GetParent().pendingId) end)
		row.retryButton = retryButton

		local rebidButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
		rebidButton:SetWidth(65)
		rebidButton:SetHeight(22)
		rebidButton:SetPoint("LEFT", retryButton, "RIGHT", 4, 0)
		rebidButton:SetText("重新竞拍")
		rebidButton:SetScript("OnClick", function() ADKP_ConfirmReauctionUnassignedLoot(this:GetParent().pendingId) end)

		local manualButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
		manualButton:SetWidth(65)
		manualButton:SetHeight(22)
		manualButton:SetPoint("LEFT", rebidButton, "RIGHT", 4, 0)
		manualButton:SetText("手动分配")
		manualButton:SetScript("OnClick", function() ADKP_SelectUnassignedLootTarget(this:GetParent().pendingId) end)

		local cancelButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
		cancelButton:SetWidth(65)
		cancelButton:SetHeight(22)
		cancelButton:SetPoint("LEFT", manualButton, "RIGHT", 4, 0)
		cancelButton:SetText("完成")
		cancelButton:SetScript("OnClick", function() ADKP_ResolveUnassignedLootManually(this:GetParent().pendingId) end)

		row:Hide()
		frame.rows[i] = row
	end

	local prevButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	prevButton:SetWidth(60)
	prevButton:SetHeight(22)
	prevButton:SetPoint("BOTTOM", frame, "BOTTOM", -70, 18)
	prevButton:SetText("上一页")
	prevButton:SetScript("OnClick", function()
		ADKP_UnassignedLootPage = ADKP_UnassignedLootPage - 1
		ADKP_UpdateUnassignedLootWindow()
	end)
	frame.prevButton = prevButton

	local pageText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	pageText:SetPoint("BOTTOM", frame, "BOTTOM", 0, 23)
	frame.pageText = pageText

	local nextButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	nextButton:SetWidth(60)
	nextButton:SetHeight(22)
	nextButton:SetPoint("BOTTOM", frame, "BOTTOM", 70, 18)
	nextButton:SetText("下一页")
	nextButton:SetScript("OnClick", function()
		ADKP_UnassignedLootPage = ADKP_UnassignedLootPage + 1
		ADKP_UpdateUnassignedLootWindow()
	end)
	frame.nextButton = nextButton

	frame:Hide()
	ADKP_UnassignedLootFrame = frame
	return frame
end

function ADKP_AddUnassignedLoot(itemLink, playerName, reason, rawError, recordRef, pendingId)
	local entry = pendingId and ADKP_FindUnassignedLoot(pendingId) or nil
	if entry then
		entry.reason = reason or entry.reason
		entry.rawError = rawError or entry.rawError
		entry.assignmentPlayer = playerName or entry.assignmentPlayer or entry.player
		entry.retrying = false
	else
		ADKP_UnassignedLootCounter = ADKP_UnassignedLootCounter + 1
		entry = {
			id = ADKP_UnassignedLootCounter,
			itemLink = itemLink,
			itemName = string.match(itemLink or "", "%[(.+)%]") or itemLink,
			player = playerName,
			assignmentPlayer = playerName,
			reason = reason or "超距/副本外/已有该物品",
			rawError = rawError,
			recordRef = recordRef,
			retrying = false
		}
		table.insert(ADKP_UnassignedLoot, entry)
	end
	ADKP_CreateUnassignedLootWindow()
	ADKP_UpdateUnassignedLootWindow()
	return entry.id
end

function ADKP_RemoveUnassignedLoot(id)
	local _, index = ADKP_FindUnassignedLoot(id)
	if not index then return false end
	table.remove(ADKP_UnassignedLoot, index)
	ADKP_UpdateUnassignedLootWindow()
	return true
end

function ADKP_CancelAutoLootForPending(id)
	for i = table.getn(ADKP_AutoLootQueue), 1, -1 do
		if ADKP_AutoLootQueue[i].pendingId == id then table.remove(ADKP_AutoLootQueue, i) end
	end
	if ADKP_AutoLootData.isAssigning and ADKP_AutoLootData.pendingId == id then
		ADKP_StopAutoLoot(false)
	end
end

function ADKP_ClearUnassignedLoot()
	for i = 1, table.getn(ADKP_UnassignedLoot) do
		ADKP_CancelAutoLootForPending(ADKP_UnassignedLoot[i].id)
	end
	ADKP_UnassignedLoot = {}
	ADKP_UnassignedLootPage = 1
	if ADKP_UnassignedLootFrame then ADKP_UnassignedLootFrame:Hide() end
end

function ADKP_RetryUnassignedLoot(id)
	local entry = ADKP_FindUnassignedLoot(id)
	if not entry or entry.retrying then return end
	local assignmentPlayer = entry.assignmentPlayer or entry.player
	entry.retrying = true
	entry.reason = "正在重试分配..."
	ADKP_UpdateUnassignedLootWindow()
	local started = ADKP_StartAutoLoot(entry.itemLink, assignmentPlayer, 0, function(success)
		local current = ADKP_FindUnassignedLoot(id)
		if success then
			ADKP_RemoveUnassignedLoot(id)
		elseif current then
			current.retrying = false
			ADKP_UpdateUnassignedLootWindow()
		end
	end, id, entry.recordRef)
	if started == false then
		entry.retrying = false
		entry.reason = "超距/副本外/已有该物品"
		ADKP_UpdateUnassignedLootWindow()
	end
end

function ADKP_AssignUnassignedLootToPlayer(id, playerName)
	local entry = ADKP_FindUnassignedLoot(id)
	if not entry or entry.retrying or not playerName then return end
	ADKP_CancelAutoLootForPending(id)
	entry.assignmentPlayer = playerName
	ADKP_RetryUnassignedLoot(id)
end

function ADKP_SelectUnassignedLootTarget(id)
	local entry = ADKP_FindUnassignedLoot(id)
	if not entry or entry.retrying then return end
	if not ADKP_Bid_ShowAssignmentTargetMenu then
		ADKP_Print("分配目标菜单尚未加载")
		return
	end
	ADKP_Bid_ShowAssignmentTargetMenu(function(playerName)
		ADKP_AssignUnassignedLootToPlayer(id, playerName)
	end, entry.assignmentPlayer or entry.player)
end

function ADKP_ResolveUnassignedLootManually(id)
	if not ADKP_FindUnassignedLoot(id) then return end
	ADKP_CancelAutoLootForPending(id)
	ADKP_RemoveUnassignedLoot(id)
end

local function ADKP_RemoveLootHistoryByUniqueId(uniqueId)
	if not uniqueId or not WebDKP_LootHistory then return end
	for i = table.getn(WebDKP_LootHistory), 1, -1 do
		if WebDKP_LootHistory[i].uniqueId == uniqueId then table.remove(WebDKP_LootHistory, i) end
	end
end

function ADKP_RevertUnassignedLootRecord(entry)
	local recordRef = entry and entry.recordRef
	if not recordRef or not recordRef.key then
		ADKP_Print("无法定位本次装备记录，已取消重新竞拍")
		return false
	end
	local logEntry = WebDKP_Log and WebDKP_Log[recordRef.key]
	local affectedGroups = {}
	local function rememberAffectedGroups(sourceEntry)
		if not sourceEntry or not sourceEntry.awarded or not ADKP_Share_GetMain then return end
		for playerName, _ in pairs(sourceEntry.awarded) do
			local mainName = ADKP_Share_GetMain(playerName, sourceEntry.tableid or recordRef.tableid)
			if mainName then affectedGroups[mainName] = sourceEntry.tableid or recordRef.tableid end
		end
	end
	if logEntry and recordRef.uniqueId and logEntry.uniqueId ~= recordRef.uniqueId then
		ADKP_Print("装备记录已发生变化，已取消重新竞拍")
		return false
	end
	if logEntry then
		rememberAffectedGroups(logEntry)
		if not ADKP_DeleteLootRecord or not ADKP_DeleteLootRecord({
			key = recordRef.key,
			item = entry.itemName,
			player = entry.player,
			tableid = recordRef.tableid
		}) then
			ADKP_Print("撤销原装备记录失败，已取消重新竞拍")
			return false
		end
		ADKP_RemoveLootHistoryByUniqueId(recordRef.uniqueId)
	end
	if ADKP_Share_RecalculateGroup then
		for mainName, tableid in pairs(affectedGroups) do
			ADKP_Share_RecalculateGroup(mainName, tableid)
		end
	end
	if ADKP_SaveToDisk then ADKP_SaveToDisk() end
	if ADKP_UpdateTableToShow then ADKP_UpdateTableToShow() end
	if ADKP_UpdateTable then ADKP_UpdateTable() end
	if ADKP_UpdateLootList then ADKP_UpdateLootList() end
	return true
end

function ADKP_ReauctionUnassignedLoot(id)
	local entry = ADKP_FindUnassignedLoot(id)
	if not entry then return end
	ADKP_CancelAutoLootForPending(id)
	if not ADKP_RevertUnassignedLootRecord(entry) then return end
	if not ADKP_Bid_ReauctionItem or not ADKP_Bid_ReauctionItem(entry.itemLink or entry.itemName) then
		ADKP_Print("无法重新发起竞拍")
		return
	end
	ADKP_RemoveUnassignedLoot(id)
end

function ADKP_ConfirmReauctionUnassignedLoot(id)
	local entry = ADKP_FindUnassignedLoot(id)
	if not entry then return end
	if not StaticPopupDialogs["ADKP_REAUCTION_UNASSIGNED_CONFIRM"] then
		StaticPopupDialogs["ADKP_REAUCTION_UNASSIGNED_CONFIRM"] = {
			button1 = "确认重拍",
			button2 = "取消",
			timeout = 0,
			whileDead = 1,
			hideOnEscape = 1,
			OnAccept = function()
				local pendingId = StaticPopupDialogs["ADKP_REAUCTION_UNASSIGNED_CONFIRM"]._pendingId
				StaticPopupDialogs["ADKP_REAUCTION_UNASSIGNED_CONFIRM"]._pendingId = nil
				ADKP_ReauctionUnassignedLoot(pendingId)
			end,
			OnCancel = function() StaticPopupDialogs["ADKP_REAUCTION_UNASSIGNED_CONFIRM"]._pendingId = nil end
		}
	end
	local dialog = StaticPopupDialogs["ADKP_REAUCTION_UNASSIGNED_CONFIRM"]
	dialog.text = "确认撤销 " .. (entry.itemLink or entry.itemName or "该物品") .. " 的原分配记录并重新竞拍吗？"
	dialog._pendingId = id
	StaticPopup_Show("ADKP_REAUCTION_UNASSIGNED_CONFIRM")
end

-- ================================
-- 创建自动分配状态窗口
-- ================================
function ADKP_CreateAutoLootFrame()
	if ADKP_AutoLootData.frame then
		return ADKP_AutoLootData.frame;
	end
	
	local frame = CreateFrame("Frame", "ADKP_AutoLootFrame", UIParent);
	frame:SetWidth(250);
	frame:SetHeight(120);
	frame:SetPoint("CENTER", UIParent, "CENTER", 0, -200);
	frame:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		tile = true, tileSize = 32, edgeSize = 32,
		insets = { left = 11, right = 12, top = 12, bottom = 11 }
	});
	
	-- 可移动性设置
	frame:EnableMouse(true);
	frame:SetMovable(true);
	frame:RegisterForDrag("LeftButton");
	frame:SetScript("OnDragStart", function() frame:StartMoving() end);
	frame:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end);
	
	-- 标题
	frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge");
	frame.title:SetPoint("TOP", 0, -15);
	frame.title:SetText("自动分配物品");
	
	-- 状态文本
	frame.statusText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal");
	frame.statusText:SetPoint("CENTER", 0, 5);
	frame.statusText:SetText("正在分配物品...");
	
	-- 手动分配按钮
	frame.manualButton = CreateFrame("Button", nil, frame, "GameMenuButtonTemplate");
	frame.manualButton:SetPoint("BOTTOM", 0, 15);
    frame.manualButton:SetWidth(120)
    frame.manualButton:SetHeight(25)
	frame.manualButton:SetText("手动分配");
	frame.manualButton:SetScript("OnClick", function()
		if ADKP_AutoLootData.isAssigning then
			ADKP_AddUnassignedLoot(
				ADKP_AutoLootData.currentItemLink,
				ADKP_AutoLootData.currentPlayer,
				"超距/副本外/已有该物品",
				"管理员转为手动处理",
				ADKP_AutoLootData.recordRef,
				ADKP_AutoLootData.pendingId
			)
		end
		ADKP_StopAutoLoot(false);
	end);
	
	frame:Hide();
	ADKP_AutoLootData.frame = frame;
	return frame;
end

-- ================================
-- 开始自动分配物品
-- ================================
local function ADKP_CanAssignMasterLoot()
	local lootMethod, masterLooterPartyID = GetLootMethod();
	if lootMethod ~= "master" then
		ADKP_Print("错误：当前不是队长分配模式");
		return false;
	end
	if not masterLooterPartyID then
		ADKP_Print("错误：你不在团队中或无法获取分配者信息");
		return false;
	end
	local isLooter = masterLooterPartyID == 0
	if not isLooter then isLooter = UnitName("party"..masterLooterPartyID) == UnitName("player") end
	if not isLooter then
		ADKP_Print("错误：你不是分配者");
		return false;
	end
	return true
end

local function ADKP_BeginAutoLootTask(task)
	if not task then return false end
	ADKP_AutoLootData.isAssigning = true;
	ADKP_AutoLootData.currentPlayer = task.playerName;
	ADKP_AutoLootData.currentItem = string.match(task.itemLink, "%[(.+)%]") or task.itemLink;
	ADKP_AutoLootData.currentItemLink = task.itemLink;
	ADKP_AutoLootData.currentCost = task.dkpCost or 0;
	ADKP_AutoLootData.onComplete = task.onComplete;
	ADKP_AutoLootData.pendingId = task.pendingId;
	ADKP_AutoLootData.recordRef = task.recordRef;
	ADKP_AutoLootData.awaitingResult = false;
	ADKP_AutoLootData.resultDeadline = 0;
	
	local frame = ADKP_CreateAutoLootFrame();
	frame.statusText:SetText("正在分配 "..ADKP_AutoLootData.currentItem.." 给 "..task.playerName);
	frame:Show();
	if GetNumLootItems() == 0 then
		frame.statusText:SetText("等待打开尸体...");
		ADKP_Print("等待打开尸体进行自动分配");
	else
		ADKP_TryAssignLoot();
	end
	return true;
end

function ADKP_StartAutoLoot(itemLink, playerName, dkpCost, onComplete, pendingId, recordRef)
	if not itemLink or not playerName or not ADKP_CanAssignMasterLoot() then return false end
	local task = {
		itemLink = itemLink,
		playerName = playerName,
		dkpCost = dkpCost,
		onComplete = onComplete,
		pendingId = pendingId,
		recordRef = recordRef
	}
	if ADKP_AutoLootData.isAssigning then
		table.insert(ADKP_AutoLootQueue, task)
		return true
	end
	return ADKP_BeginAutoLootTask(task)
end

local function ADKP_FailCurrentAutoLoot(reason, rawError)
	if not ADKP_AutoLootData.isAssigning then return end
	ADKP_AddUnassignedLoot(
		ADKP_AutoLootData.currentItemLink,
		ADKP_AutoLootData.currentPlayer,
		reason or "超距/副本外/已有该物品",
		rawError,
		ADKP_AutoLootData.recordRef,
		ADKP_AutoLootData.pendingId
	)
	ADKP_StopAutoLoot(false)
end

local function ADKP_CheckAutoLootResultTimeout()
	if not ADKP_AutoLootData.isAssigning or not ADKP_AutoLootData.awaitingResult then return end
	if GetTime() < (ADKP_AutoLootData.resultDeadline or 0) then return end
	local itemStillPresent = false
	if GetNumLootItems and GetNumLootItems() > 0 then
		for i = 1, GetNumLootItems() do
			local link = GetLootSlotLink(i)
			local itemName = link and string.match(link, "%[(.+)%]")
			if itemName == ADKP_AutoLootData.currentItem then
				itemStillPresent = true
				break
			end
		end
	end
	if itemStillPresent or not GetNumLootItems or GetNumLootItems() == 0 then
		ADKP_FailCurrentAutoLoot("超距/副本外/已有该物品", "未收到物品分配成功回执")
	else
		ADKP_StopAutoLoot(true)
	end
end

-- ================================
-- 尝试分配物品
-- ================================
function ADKP_TryAssignLoot()
	if not ADKP_AutoLootData.isAssigning then
		return;
	end
	
	if GetNumLootItems() == 0 then
		if ADKP_AutoLootData.frame then
			ADKP_AutoLootData.frame.statusText:SetText("等待打开尸体...");
		end
		return;
	end
	
	-- 查找匹配的物品
	local foundItemSlot = nil;
	for i = 1, GetNumLootItems() do
		local link = GetLootSlotLink(i);
		if link then
			local itemName = string.match(link, "%[(.+)%]");
			if itemName == ADKP_AutoLootData.currentItem then
				foundItemSlot = i;
				break
			end
		end
	end
	
	if not foundItemSlot then
		ADKP_FailCurrentAutoLoot("超距/副本外/已有该物品", "当前掉落窗口中找不到该物品");
		return;
	end
	
	-- 查找匹配的玩家
	local foundPlayerIndex = nil;
	for j = 1, 40 do
		local candidateName = GetMasterLootCandidate(j);
		if candidateName == ADKP_AutoLootData.currentPlayer then
			foundPlayerIndex = j;
			break
		end
	end
	
	if not foundPlayerIndex then
		ADKP_FailCurrentAutoLoot("超距/副本外/已有该物品", "玩家不在当前物品的可分配名单中");
		return;
	end
	
	ADKP_AutoLootData.awaitingResult = true;
	ADKP_AutoLootData.resultDeadline = GetTime() + 5;
	if not ADKP_AutoLootMonitor then ADKP_AutoLootMonitor = CreateFrame("Frame") end
	ADKP_AutoLootMonitor:SetScript("OnUpdate", function() ADKP_CheckAutoLootResultTimeout() end)
	GiveMasterLoot(foundItemSlot, foundPlayerIndex);
end

-- ================================
-- 停止自动分配
-- ================================
function ADKP_StopAutoLoot(success)
	local onComplete = ADKP_AutoLootData.onComplete;
	ADKP_AutoLootData.isAssigning = false;
	ADKP_AutoLootData.currentPlayer = nil;
	ADKP_AutoLootData.currentItem = nil;
	ADKP_AutoLootData.currentItemLink = nil;
	ADKP_AutoLootData.currentCost = 0;
	ADKP_AutoLootData.onComplete = nil;
	ADKP_AutoLootData.pendingId = nil;
	ADKP_AutoLootData.recordRef = nil;
	ADKP_AutoLootData.awaitingResult = false;
	ADKP_AutoLootData.resultDeadline = 0;
	
	if ADKP_AutoLootData.frame then
		ADKP_AutoLootData.frame:Hide();
	end
	if ADKP_AutoLootMonitor then ADKP_AutoLootMonitor:SetScript("OnUpdate", nil) end
	if onComplete then onComplete(success == true); end
	while not ADKP_AutoLootData.isAssigning and table.getn(ADKP_AutoLootQueue) > 0 do
		local nextTask = table.remove(ADKP_AutoLootQueue, 1)
		if ADKP_CanAssignMasterLoot() then
			ADKP_BeginAutoLootTask(nextTask)
			return
		else
			ADKP_AddUnassignedLoot(nextTask.itemLink, nextTask.playerName, "超距/副本外/已有该物品", "当前无法执行队长分配", nextTask.recordRef, nextTask.pendingId)
			if nextTask.onComplete then nextTask.onComplete(false) end
		end
	end
end

-- ================================
-- 处理UI错误消息
-- ================================
function ADKP_HandleUIError()
	if not ADKP_AutoLootData.isAssigning or not ADKP_AutoLootData.awaitingResult then
		return;
	end
	
	local errorMsg = arg1;
	if not errorMsg then
		return;
	end
	
	local isBagFull = string.find(errorMsg, "物品栏已满", 1, true)
		or string.find(errorMsg, "背包已满", 1, true)
		or (ERR_LOOT_MASTER_INV_FULL and errorMsg == ERR_LOOT_MASTER_INV_FULL)
		or (ERR_INV_FULL and errorMsg == ERR_INV_FULL)
	local isAssignmentError = isBagFull
		or (ERR_ITEM_MAX_COUNT and errorMsg == ERR_ITEM_MAX_COUNT)
		or string.find(errorMsg, "无法将物品分配", 1, true)
		or string.find(errorMsg, "不能再携带", 1, true)
		or string.find(errorMsg, "不能携带更多", 1, true)
		or string.find(errorMsg, "已经拥有", 1, true)
		or string.find(errorMsg, "已有该物品", 1, true)
		or string.find(errorMsg, "唯一", 1, true)
		or string.find(errorMsg, "距离太远", 1, true)
	if not isAssignmentError then return end
	if isBagFull then
		ADKP_FailCurrentAutoLoot("背包已满", errorMsg)
	else
		ADKP_FailCurrentAutoLoot("超距/副本外/已有该物品", errorMsg)
	end
end


-- ================================
-- BOSS击杀处理函数
-- ================================

-- 全局变量用于存储BOSS击杀信息
ADKP_BossAwardData = {
    bossName = nil,
    points = 2,
    frame = nil,
    subTime = 5 -- 替补计时默认5分钟
}

-- ================================
-- 处理战斗敌对死亡事件
-- ================================
-- ================================
-- 检查指定名称的单位是否为世界BOSS
-- ================================
-- ================================
-- 处理战斗敌对死亡事件
-- @param message 死亡消息
-- 保留旧入口形参；只使用标准死亡消息，交给名单中的确认规则处理。
-- ================================
function ADKP_HandleCombatHostileDeath(message, isVerifiedBoss)
    ADKP_BossEncounter_Death(message)
end

function ADKP_ScheduleBossAwardFrame()
    ADKP_BossEncounter_Update()
end

function ADKP_ExecuteBossKillAward()
    ADKP_BossEncounter_Pump()
end

function ADKP_ExtractBossName(message)
    return ADKP_BossEncounter_ExtractName(message)
end

function ADKP_InitBossLookup()
    -- The encounter index is built once in ADKP_BossEncounters.lua.
end

function ADKP_IsBossByNamePattern(unitName)
    if not unitName or unitName == "" then
        return false
    end
    
    -- 必须在队伍或团队中才触发 DKP
    local numRaid = GetNumRaidMembers() or 0
    local numParty = GetNumPartyMembers() or 0
    if numRaid == 0 and numParty == 0 then
        return false
    end

    -- 检查是否被显式禁用
    if not ADKP_IsBossEnabled(unitName) then
        return false
    end

    -- 初始化 Boss 查找表
    ADKP_InitBossLookup()

    local nameLower = string.lower(unitName)

    local bossPatterns = WebDKP_Options["BossPatterns"] or {}
    if ADKP_GetBossDefinition(unitName) then return true end
    for _, bossName in ipairs(bossPatterns) do
        if string.lower(bossName) == nameLower then return true end
    end

    return false
end

-- ================================
-- 创建自定义BOSS名单管理界面
-- ================================
function ADKP_AddCustomBoss(bossName)
    if not bossName or bossName == "" then
        return
    end
    
    -- 确保BossPatterns是表
    if not WebDKP_Options["BossPatterns"] then
        WebDKP_Options["BossPatterns"] = {}
    end
    
    -- 检查是否已存在
    for _, name in ipairs(WebDKP_Options["BossPatterns"]) do
        if name == bossName then
            return
        end
    end
    
    -- 添加到自定义BOSS列表
    table.insert(WebDKP_Options["BossPatterns"], bossName)
end

-- ================================
-- 移除自定义BOSS
-- ================================
function ADKP_RemoveCustomBoss(index)
    if index and WebDKP_Options["BossPatterns"] and WebDKP_Options["BossPatterns"][index] then
        table.remove(WebDKP_Options["BossPatterns"], index)
    end
end

-- ================================
-- 创建BOSS名单管理界面
-- ================================
-- ==========================================
-- BOSS 启用/禁用状态管理
-- ==========================================
function ADKP_IsBossEnabled(bossName)
    if not bossName or bossName == "" then
        return true
    end
    if not WebDKP_Options then
        return true
    end
    if not WebDKP_Options["EnabledRaidBosses"] then
        return true
    end
    ADKP_InitBossPoints()
    local boss = ADKP_GetBossDefinition(bossName)
    if boss then bossName = boss.en end
    local nameLower = string.lower(bossName)
    if WebDKP_Options["EnabledRaidBosses"][nameLower] == false then
        return false
    end
    return true
end

function ADKP_SetBossEnabledState(boss, enabled)
    if not WebDKP_Options then
        WebDKP_Options = {}
    end
    if not WebDKP_Options["EnabledRaidBosses"] then
        WebDKP_Options["EnabledRaidBosses"] = {}
    end
    local val = true
    if enabled == false then
        val = false
    end
    
    if boss.en then
        WebDKP_Options["EnabledRaidBosses"][string.lower(boss.en)] = val
    end
    if boss.zh then
        WebDKP_Options["EnabledRaidBosses"][string.lower(boss.zh)] = val
    end
end

-- ==========================================
-- BOSS 分值配置（全局默认 + 差异化覆盖）
-- 存储：WebDKP_Options["BossPointsDefault"] = { raid=, sub= }（统一值，未配置为 1）
--       WebDKP_Options["BossPoints"][名字小写] = { raid=, sub= }（仅存差异化字段，nil=继承默认）
-- 内置 Boss 的 en/zh 两个键指向同一张表；自定义 Boss 用名字本身作键。
-- ==========================================
function ADKP_InitBossPoints()
    if not WebDKP_Options then WebDKP_Options = {} end
    if type(WebDKP_Options["BossPoints"]) ~= "table" then
        WebDKP_Options["BossPoints"] = {}
    end
    if type(WebDKP_Options["BossPointsDefault"]) ~= "table" then
        WebDKP_Options["BossPointsDefault"] = {}
    end
    local d = WebDKP_Options["BossPointsDefault"]
    if type(d.raid) ~= "number" then d.raid = 1 end
    if type(d.sub) ~= "number" then d.sub = 1 end
    ADKP_MigrateBossEncounterSettings()
end

-- 返回生效分值：raid, sub, raidIsOverride, subIsOverride
function ADKP_GetBossAwardPoints(bossName)
    ADKP_InitBossPoints()
    local ov = nil
    local boss = ADKP_GetBossDefinition(bossName)
    if boss then bossName = boss.en end
    if bossName and bossName ~= "" then
        ov = WebDKP_Options["BossPoints"][string.lower(bossName)]
    end
    local d = WebDKP_Options["BossPointsDefault"]
    local raidOv = (ov and type(ov.raid) == "number") or false
    local subOv = (ov and type(ov.sub) == "number") or false
    local raid = raidOv and ov.raid or d.raid
    local sub = subOv and ov.sub or d.sub
    return raid, sub, raidOv, subOv
end

-- bossTblOrName：内置 Boss 传 {en=,zh=} 表，自定义 Boss 传名字字符串
-- field: "raid" 或 "sub"；value 为数字（写覆盖）或 nil（清空该字段覆盖，恢复继承默认）
function ADKP_SetBossPointField(bossTblOrName, field, value)
    ADKP_InitBossPoints()
    if field ~= "raid" and field ~= "sub" then return end
    local keys = {}
    if type(bossTblOrName) == "string" then bossTblOrName = ADKP_GetBossDefinition(bossTblOrName) or bossTblOrName end
    if type(bossTblOrName) == "table" then
        if bossTblOrName.en and bossTblOrName.en ~= "" then
            table.insert(keys, string.lower(bossTblOrName.en))
        end
        if bossTblOrName.zh and bossTblOrName.zh ~= "" then
            table.insert(keys, string.lower(bossTblOrName.zh))
        end
    elseif bossTblOrName and bossTblOrName ~= "" then
        table.insert(keys, string.lower(bossTblOrName))
    end
    if table.getn(keys) == 0 then return end

    local store = WebDKP_Options["BossPoints"]
    local entry = store[keys[1]]
    if value == nil then
        if entry then
            entry[field] = nil
            if next(entry) == nil then
                -- 覆盖全空：把指向该表的所有键一并清掉
                for k, v in pairs(store) do
                    if v == entry then store[k] = nil end
                end
            end
        end
        return
    end
    local num = tonumber(value)
    if not num then return end
    if ADKP_ROUND then num = ADKP_ROUND(num, 2) end
    if not entry then
        entry = {}
        for _, k in ipairs(keys) do store[k] = entry end
    end
    entry[field] = num
end

-- 统一设置：写入默认分值并清空全部差异化覆盖
function ADKP_SetAllBossPoints(raid, sub)
    ADKP_InitBossPoints()
    local r = tonumber(raid)
    local s = tonumber(sub)
    if not r or not s then return false end
    if ADKP_ROUND then
        r = ADKP_ROUND(r, 2)
        s = ADKP_ROUND(s, 2)
    end
    WebDKP_Options["BossPointsDefault"] = { ["raid"] = r, ["sub"] = s }
    WebDKP_Options["BossPoints"] = {}
    return true
end

-- 按字形数截断 UTF-8 文本（中文客户端字符串为 UTF-8，避免按字节切断半个字）
function ADKP_TruncateUtf8Glyphs(s, maxGlyphs)
    s = tostring(s or "")
    local len = string.len(s)
    local count = 0
    local i = 1
    local cut = len
    while i <= len do
        count = count + 1
        if count > maxGlyphs then
            cut = i - 1
            break
        end
        local b = string.byte(s, i)
        if b >= 240 then
            i = i + 4
        elseif b >= 224 then
            i = i + 3
        elseif b >= 192 then
            i = i + 2
        else
            i = i + 1
        end
    end
    if cut < len then
        return string.sub(s, 1, cut) .. "…"
    end
    return s
end

-- 自动击杀记录的日志关联逻辑位于 ADKP_BossAutoLog.lua。

-- ================================
-- Boss 名单页：统一分值工具栏 / 行内分值输入框
-- ================================
-- 统一设置（带确认：会清空全部差异化覆盖）
function ADKP_BossListToolbar_SetAll(frame)
    if not frame or not frame.ptRaidEdit then return end
    ADKP_InitBossPoints()
    local d = WebDKP_Options["BossPointsDefault"]
    local r = tonumber(frame.ptRaidEdit:GetText())
    local s = tonumber(frame.ptSubEdit:GetText())
    if not r then r = d.raid end
    if not s then s = d.sub end
    if not StaticPopupDialogs then StaticPopupDialogs = {} end
    StaticPopupDialogs["ADKP_BOSSPOINTS_SETALL"] = {
        ["text"] = "统一设置所有 Boss 分值为 主%s 替%s ？\n（会清空全部差异化覆盖分值）",
        ["button1"] = ACCEPT or "确定",
        ["button2"] = CANCEL or "取消",
        ["OnAccept"] = function()
            if ADKP_SetAllBossPoints(r, s) then
                ADKP_Print("Boss 统一分值已设置：主" .. r .. " 替" .. s .. "（差异化覆盖已清空）")
                if frame and frame.ptRaidEdit then
                    ADKP_BossListToolbar_Sync(frame)
                    ADKP_UpdateBossListFrame(frame)
                end
            end
        end,
        ["timeout"] = 0,
        ["whileDead"] = 1,
        ["hideOnEscape"] = 1
    }
    StaticPopup_Show("ADKP_BOSSPOINTS_SETALL", tostring(r), tostring(s))
end

-- 工具栏输入框回显当前默认值
-- 注意：只在打开名单页和统一设置后调用，不在列表刷新时调用
-- （WoW 1.12 的 EditBox 没有 HasFocus 方法，无法判断正在输入）
function ADKP_BossListToolbar_Sync(frame)
    if not frame or not frame.ptRaidEdit then return end
    ADKP_InitBossPoints()
    local d = WebDKP_Options["BossPointsDefault"]
    frame.ptRaidEdit:SetText(tostring(d.raid))
    frame.ptSubEdit:SetText(tostring(d.sub))
end

-- 行内分值输入框：回填生效分值（覆盖=黄色，继承默认=灰色）
function ADKP_BossListRowPtFill(box)
    if not box or box.bossRef == nil then return end
    local name = box.bossRef
    if type(name) == "table" then
        name = box.bossRef.en or box.bossRef.zh
    end
    local raid, sub, raidOv, subOv = ADKP_GetBossAwardPoints(name)
    local val, isOv
    if box.field == "raid" then
        val, isOv = raid, raidOv
    else
        val, isOv = sub, subOv
    end
    box:SetText(tostring(val))
    if isOv then
        box:SetTextColor(1, 0.82, 0)
    else
        box:SetTextColor(0.6, 0.6, 0.6)
    end
end

-- 行内分值提交：留空 = 清除该字段覆盖（恢复继承默认）；Enter/失焦触发
function ADKP_BossListRowPtCommit(box)
    if not box or box.bossRef == nil then return end
    local txt = box:GetText() or ""
    if txt == "" then
        ADKP_SetBossPointField(box.bossRef, box.field, nil)
    else
        local num = tonumber(txt)
        if num then
            ADKP_SetBossPointField(box.bossRef, box.field, num)
        else
            ADKP_Print("分值无效：" .. txt)
        end
    end
    local mainFrame = box.mainFrame
    if mainFrame then
        ADKP_UpdateBossListFrame(mainFrame)
    end
end

-- 行内分值撤销：Esc 恢复显示为当前生效值（不保存）
function ADKP_BossListRowPtCancel(box)
    ADKP_BossListRowPtFill(box)
end

-- ================================
-- 创建BOSS名单管理界面 (新增右侧副本多选与单选首领过滤功能)
-- ================================
function ADKP_CreateExcludedBossesFrame()
    local frame = CreateFrame("Frame", "ADKP_BossListFrame", UIParent)
    frame:SetFrameStrata("DIALOG")
    frame:SetWidth(720) -- 扩展宽度以容纳右侧副本和BOSS选择器
    frame:SetHeight(480)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 }
    })
    
    -- 可移动性设置
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function() frame:StartMoving() end)
    frame:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)
    
    -- 标题
    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.title:SetPoint("TOP", 0, -15)
    frame.title:SetText("BOSS名单管理")
    
    -- 关闭按钮
    frame.closeButton = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    frame.closeButton:SetPoint("TOPRIGHT", -10, -10)
    frame.closeButton:SetScript("OnClick", function()
        frame:Hide()
    end)
    
    -- ==================== 左侧：自定义与排除名单 ====================
    -- 自定义BOSS名单区域
    frame.customAddLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.customAddLabel:SetPoint("TOPLEFT", 20, -45)
    frame.customAddLabel:SetText("添加自定义BOSS名称:")
    
    frame.customAddEditBox = CreateFrame("EditBox", "ADKP_CustomBossAddEditBox", frame, "InputBoxTemplate")
    frame.customAddEditBox:SetWidth(280)
    frame.customAddEditBox:SetHeight(20)
    frame.customAddEditBox:SetPoint("TOPLEFT", 30, -70)
    frame.customAddEditBox:SetAutoFocus(false)
    frame.customAddEditBox:SetBackdropColor(0, 0, 0, 0.8)
    frame.customAddEditBox:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
    
    frame.customAddButton = CreateFrame("Button", nil, frame, "GameMenuButtonTemplate")
    frame.customAddButton:SetWidth(80)
    frame.customAddButton:SetHeight(25)
    frame.customAddButton:SetPoint("TOPLEFT", 30, -95)
    frame.customAddButton:SetText("添加")
    frame.customAddButton:SetScript("OnClick", function()
        local bossName = frame.customAddEditBox:GetText()
        if bossName and bossName ~= "" then
            ADKP_AddCustomBoss(bossName)
            frame.customAddEditBox:SetText("")
            ADKP_UpdateBossListFrame(frame)
        end
    end)
    
    frame.customTargetButton = CreateFrame("Button", nil, frame, "GameMenuButtonTemplate")
    frame.customTargetButton:SetWidth(190)
    frame.customTargetButton:SetHeight(25)
    frame.customTargetButton:SetPoint("LEFT", frame.customAddButton, "RIGHT", 10, 0)
    frame.customTargetButton:SetText("填入当前目标名称")
    frame.customTargetButton:SetScript("OnClick", function()
        local targetName = UnitName("target")
        if targetName and targetName ~= "" then
            frame.customAddEditBox:SetText(targetName)
        else
            ADKP_Print("请先选择目标。")
        end
    end)

    -- 自定义BOSS列表框背景
    frame.customListBg = CreateFrame("Frame", nil, frame)
    frame.customListBg:SetWidth(310)
    frame.customListBg:SetHeight(120)
    frame.customListBg:SetPoint("TOPLEFT", 20, -125)
    frame.customListBg:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    frame.customListBg:SetBackdropColor(0, 0, 0, 0.8)
    frame.customListBg:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
    
    -- 自定义BOSS列表滚动框
    frame.customScrollFrame = CreateFrame("ScrollFrame", "ADKP_CustomBossScrollFrame", frame.customListBg, "UIPanelScrollFrameTemplate")
    frame.customScrollFrame:SetPoint("TOPLEFT", 4, -4)
    frame.customScrollFrame:SetPoint("BOTTOMRIGHT", -30, 4)
    
    -- 滚动内容框架
    frame.customScrollChild = CreateFrame("Frame", nil, frame.customScrollFrame)
    frame.customScrollChild:SetWidth(280)
    frame.customScrollChild:SetHeight(1)
    frame.customScrollFrame:SetScrollChild(frame.customScrollChild)
    
    -- BOSS排除名单区域
    frame.excludedAddLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.excludedAddLabel:SetPoint("TOPLEFT", 20, -255)
    frame.excludedAddLabel:SetText("添加排除BOSS名称:")
    
    frame.excludedAddEditBox = CreateFrame("EditBox", "ADKP_ExcludedBossAddEditBox", frame, "InputBoxTemplate")
    frame.excludedAddEditBox:SetWidth(280)
    frame.excludedAddEditBox:SetHeight(20)
    frame.excludedAddEditBox:SetPoint("TOPLEFT", 30, -280)
    frame.excludedAddEditBox:SetAutoFocus(false)
    frame.excludedAddEditBox:SetBackdropColor(0, 0, 0, 0.8)
    frame.excludedAddEditBox:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
    
    frame.excludedAddButton = CreateFrame("Button", nil, frame, "GameMenuButtonTemplate")
    frame.excludedAddButton:SetWidth(80)
    frame.excludedAddButton:SetHeight(25)
    frame.excludedAddButton:SetPoint("TOPLEFT", 30, -305)
    frame.excludedAddButton:SetText("添加")
    frame.excludedAddButton:SetScript("OnClick", function()
        local bossName = frame.excludedAddEditBox:GetText()
        if bossName and bossName ~= "" then
            ADKP_AddExcludedBoss(bossName)
            frame.excludedAddEditBox:SetText("")
            ADKP_UpdateBossListFrame(frame)
        end
    end)
    
    frame.excludedTargetButton = CreateFrame("Button", nil, frame, "GameMenuButtonTemplate")
    frame.excludedTargetButton:SetWidth(190)
    frame.excludedTargetButton:SetHeight(25)
    frame.excludedTargetButton:SetPoint("LEFT", frame.excludedAddButton, "RIGHT", 10, 0)
    frame.excludedTargetButton:SetText("填入当前目标名称")
    frame.excludedTargetButton:SetScript("OnClick", function()
        local targetName = UnitName("target")
        if targetName and targetName ~= "" then
            frame.excludedAddEditBox:SetText(targetName)
        else
            ADKP_Print("请先选择目标。")
        end
    end)

    -- 排除名单列表框背景
    frame.excludedListBg = CreateFrame("Frame", nil, frame)
    frame.excludedListBg:SetWidth(310)
    frame.excludedListBg:SetHeight(120)
    frame.excludedListBg:SetPoint("TOPLEFT", 20, -335)
    frame.excludedListBg:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    frame.excludedListBg:SetBackdropColor(0, 0, 0, 0.8)
    frame.excludedListBg:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
    
    -- 排除BOSS列表滚动框
    frame.excludedScrollFrame = CreateFrame("ScrollFrame", "ADKP_ExcludedBossScrollFrame", frame.excludedListBg, "UIPanelScrollFrameTemplate")
    frame.excludedScrollFrame:SetPoint("TOPLEFT", 4, -4)
    frame.excludedScrollFrame:SetPoint("BOTTOMRIGHT", -30, 4)
    
    -- 滚动内容框架
    frame.excludedScrollChild = CreateFrame("Frame", nil, frame.excludedScrollFrame)
    frame.excludedScrollChild:SetWidth(280)
    frame.excludedScrollChild:SetHeight(1)
    frame.excludedScrollFrame:SetScrollChild(frame.excludedScrollChild)
    
    -- ==================== 中间分割线 ====================
    frame.divider = frame:CreateTexture(nil, "BACKGROUND")
    frame.divider:SetTexture(0.5, 0.5, 0.5, 0.5)
    frame.divider:SetPoint("TOPLEFT", 350, -40)
    frame.divider:SetPoint("BOTTOMLEFT", 350, 40)
    frame.divider:SetWidth(1)
    
    -- ==================== 右侧：团队副本与首领选择 ====================
    frame.rightTitle = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.rightTitle:SetPoint("TOPLEFT", 370, -45)
    frame.rightTitle:SetText("团队副本与首领过滤 (勾选记录 DKP):")
    
    -- 全选按钮
    frame.selectAllBtn = CreateFrame("Button", nil, frame, "GameMenuButtonTemplate")
    frame.selectAllBtn:SetWidth(50)
    frame.selectAllBtn:SetHeight(20)
    frame.selectAllBtn:SetPoint("TOPRIGHT", -75, -42)
    frame.selectAllBtn:SetText("全选")
    frame.selectAllBtn:SetScript("OnClick", function()
        if ADKP_RaidBosses then
            for zoneKey, zoneInfo in pairs(ADKP_RaidBosses) do
                if zoneInfo.bosses then
                    for _, b in ipairs(zoneInfo.bosses) do
                        ADKP_SetBossEnabledState(b, true)
                    end
                end
            end
        end
        ADKP_UpdateBossListFrame(this:GetParent())
    end)
    
    -- 清空按钮
    frame.clearAllBtn = CreateFrame("Button", nil, frame, "GameMenuButtonTemplate")
    frame.clearAllBtn:SetWidth(50)
    frame.clearAllBtn:SetHeight(20)
    frame.clearAllBtn:SetPoint("TOPRIGHT", -20, -42)
    frame.clearAllBtn:SetText("清空")
    frame.clearAllBtn:SetScript("OnClick", function()
        if ADKP_RaidBosses then
            for zoneKey, zoneInfo in pairs(ADKP_RaidBosses) do
                if zoneInfo.bosses then
                    for _, b in ipairs(zoneInfo.bosses) do
                        ADKP_SetBossEnabledState(b, false)
                    end
                end
            end
        end
        ADKP_UpdateBossListFrame(this:GetParent())
    end)

    -- ==================== 统一分值工具栏 ====================
    frame.ptLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.ptLabel:SetPoint("TOPLEFT", 370, -63)
    frame.ptLabel:SetText("统一分值:")

    frame.ptRaidLbl = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.ptRaidLbl:SetPoint("LEFT", frame.ptLabel, "RIGHT", 8, 0)
    frame.ptRaidLbl:SetText("主")
    frame.ptRaidLbl:SetTextColor(0.8, 0.8, 0.8)

    frame.ptRaidEdit = CreateFrame("EditBox", "ADKP_BossPtRaidEdit", frame, "InputBoxTemplate")
    frame.ptRaidEdit:SetWidth(38)
    frame.ptRaidEdit:SetHeight(18)
    frame.ptRaidEdit:SetPoint("LEFT", frame.ptRaidLbl, "RIGHT", 4, 0)
    frame.ptRaidEdit:SetAutoFocus(false)
    frame.ptRaidEdit:SetFontObject("ChatFontNormal")
    frame.ptRaidEdit:SetScript("OnEscapePressed", function() this:ClearFocus() end)

    frame.ptSubLbl = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.ptSubLbl:SetPoint("LEFT", frame.ptRaidEdit, "RIGHT", 8, 0)
    frame.ptSubLbl:SetText("替")
    frame.ptSubLbl:SetTextColor(0.8, 0.8, 0.8)

    frame.ptSubEdit = CreateFrame("EditBox", "ADKP_BossPtSubEdit", frame, "InputBoxTemplate")
    frame.ptSubEdit:SetWidth(38)
    frame.ptSubEdit:SetHeight(18)
    frame.ptSubEdit:SetPoint("LEFT", frame.ptSubLbl, "RIGHT", 4, 0)
    frame.ptSubEdit:SetAutoFocus(false)
    frame.ptSubEdit:SetFontObject("ChatFontNormal")
    frame.ptSubEdit:SetScript("OnEscapePressed", function() this:ClearFocus() end)

    frame.setAllBtn = CreateFrame("Button", nil, frame, "GameMenuButtonTemplate")
    frame.setAllBtn:SetWidth(64)
    frame.setAllBtn:SetHeight(20)
    frame.setAllBtn:SetPoint("LEFT", frame.ptSubEdit, "RIGHT", 10, 0)
    frame.setAllBtn:SetText("统一设置")
    frame.setAllBtn:SetScript("OnClick", function()
        ADKP_BossListToolbar_SetAll(this:GetParent())
    end)

    -- 初始回显当前统一默认分值
    ADKP_BossListToolbar_Sync(frame)

    -- 副本列表框背景
    frame.raidListBg = CreateFrame("Frame", nil, frame)
    frame.raidListBg:SetWidth(330)
    frame.raidListBg:SetHeight(333)
    frame.raidListBg:SetPoint("TOPLEFT", 370, -92)
    frame.raidListBg:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    frame.raidListBg:SetBackdropColor(0, 0, 0, 0.8)
    frame.raidListBg:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
    
    -- 副本及BOSS列表滚动框
    frame.raidScrollFrame = CreateFrame("ScrollFrame", "ADKP_RaidBossScrollFrame", frame.raidListBg, "UIPanelScrollFrameTemplate")
    frame.raidScrollFrame:SetPoint("TOPLEFT", 4, -4)
    frame.raidScrollFrame:SetPoint("BOTTOMRIGHT", -30, 4)
    
    -- 滚动内容框架
    frame.raidScrollChild = CreateFrame("Frame", nil, frame.raidScrollFrame)
    frame.raidScrollChild:SetWidth(290)
    frame.raidScrollChild:SetHeight(1)
    frame.raidScrollFrame:SetScrollChild(frame.raidScrollChild)
    
    -- 初始化列表
    ADKP_UpdateBossListFrame(frame)
    
    return frame
end

-- ================================
-- 更新BOSS名单管理界面列表显示 (含右侧副本多选与单选首领过滤渲染)
-- ================================
function ADKP_UpdateBossListFrame(frame)
    -- 清除现有自定义BOSS列表项
    if frame.customListItems then
        for _, item in ipairs(frame.customListItems) do
            item.nameText:Hide()
            item.removeButton:Hide()
        end
    end
    frame.customListItems = {}
    
    -- 获取自定义BOSS数据
    local customBosses = WebDKP_Options["BossPatterns"] or {}
    local numCustomBosses = table.getn(customBosses)
    
    -- 计算列表项高度
    local itemHeight = 18
    
    -- 调整滚动内容框架高度
    local contentHeight = numCustomBosses * itemHeight
    frame.customScrollChild:SetHeight(contentHeight)
    
    -- 显示所有自定义BOSS（分值输入框走池化，避免列表刷新时泄漏帧）
    frame.customPtPool = frame.customPtPool or {}
    for i, bossName in ipairs(customBosses) do
        local listItem = {}
        local yOffset = (i - 1) * itemHeight

        -- BOSS名称文本
        listItem.nameText = frame.customScrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        listItem.nameText:SetPoint("TOPLEFT", 10, -yOffset)
        listItem.nameText:SetText(bossName)
        listItem.nameText:Show()

        -- 删除按钮
        listItem.removeButton = CreateFrame("Button", nil, frame.customScrollChild, "GameMenuButtonTemplate")
        listItem.removeButton:SetWidth(36)
        listItem.removeButton:SetHeight(itemHeight - 3)
        listItem.removeButton:SetPoint("TOPRIGHT", -8, -yOffset + 1)
        listItem.removeButton:SetText("删")
        listItem.removeButton.bossIndex = i
        listItem.removeButton:SetScript("OnClick", function()
            ADKP_RemoveCustomBoss(this.bossIndex)
            ADKP_UpdateBossListFrame(frame)
        end)
        listItem.removeButton:Show()

        -- 主/替分值输入框（池化复用）
        for col = 1, 2 do
            local poolIdx = (i - 1) * 2 + col
            local box = frame.customPtPool[poolIdx]
            if not box then
                local name = "ADKP_CustomBossPt_" .. poolIdx
                box = CreateFrame("EditBox", name, frame.customScrollChild, "InputBoxTemplate")
                box:SetWidth(34)
                box:SetHeight(16)
                box:SetAutoFocus(false)
                box:SetFontObject("GameFontHighlightSmall")
                box:SetJustifyH("CENTER")
                box.field = (col == 1) and "raid" or "sub"
                box:SetScript("OnEnterPressed", function()
                    ADKP_BossListRowPtCommit(this)
                    this:ClearFocus()
                end)
                box:SetScript("OnEscapePressed", function() ADKP_BossListRowPtCancel(this) end)
                box:SetScript("OnEditFocusLost", function() ADKP_BossListRowPtCommit(this) end)
                frame.customPtPool[poolIdx] = box
            end
            local x = (col == 1) and 155 or 198
            box:ClearAllPoints()
            box:SetPoint("TOPLEFT", x, -yOffset - 1)
            box.bossRef = bossName
            box.mainFrame = frame
            box:Show()
            ADKP_BossListRowPtFill(box)
            if col == 1 then
                listItem.ptRaid = box
            else
                listItem.ptSub = box
            end
        end

        table.insert(frame.customListItems, listItem)
    end

    -- 隐藏多余的自定义分值输入框（列表缩短时）
    do
        local used = numCustomBosses * 2
        local poolSize = table.getn(frame.customPtPool)
        for idx = used + 1, poolSize do
            frame.customPtPool[idx]:Hide()
        end
    end
    
    -- 排除BOSS列表处理
    -- 清除现有排除BOSS列表项
    if frame.excludedListItems then
        for _, item in ipairs(frame.excludedListItems) do
            item.nameText:Hide()
            item.removeButton:Hide()
        end
    end
    frame.excludedListItems = {}
    
    -- 获取排除BOSS数据
    local excludedBosses = WebDKP_Options["ExcludedBosses"] or {}
    local numExcludedBosses = table.getn(excludedBosses)
    
    -- 调整滚动内容框架高度
    contentHeight = numExcludedBosses * itemHeight
    frame.excludedScrollChild:SetHeight(contentHeight)
    
    -- 显示所有排除BOSS
    for i, bossName in ipairs(excludedBosses) do
        local listItem = {}
        local yOffset = (i - 1) * itemHeight
        
        -- BOSS名称文本
        listItem.nameText = frame.excludedScrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        listItem.nameText:SetPoint("TOPLEFT", 10, -yOffset)
        listItem.nameText:SetText(bossName)
        listItem.nameText:Show()
        
        -- 删除按钮
        listItem.removeButton = CreateFrame("Button", nil, frame.excludedScrollChild, "GameMenuButtonTemplate")
        listItem.removeButton:SetWidth(60)
        listItem.removeButton:SetHeight(itemHeight - 3)
        listItem.removeButton:SetPoint("TOPRIGHT", -10, -yOffset + 1)
        listItem.removeButton:SetText("删除")
        listItem.removeButton.bossIndex = i
        listItem.removeButton:SetScript("OnClick", function()
            ADKP_RemoveExcludedBoss(this.bossIndex)
            ADKP_UpdateBossListFrame(frame)
        end)
        listItem.removeButton:Show()
        
        table.insert(frame.excludedListItems, listItem)
    end

    -- ===================================
    -- 右侧：团队副本及首领列表渲染逻辑
    -- ===================================
    -- 1. 获取当前所有的可见行
    local visibleLines = {}
    local raidZoneOrder = {
        "Molten Core",
        "Onyxia's Lair",
        "Blackwing Lair",
        "Zul'Gurub",
        "Ruins of Ahn'Qiraj",
        "Temple of Ahn'Qiraj",
        "Naxxramas",
        "Lower Karazhan",
        "Upper Karazhan",
        "Emerald Sanctum",
        "Timbermaw Hold",
        "World Bosses",
    }
    
    -- 初始化展开状态 (默认全部收缩)
    if not ADKP_RaidZoneExpanded then
        ADKP_RaidZoneExpanded = {}
        for _, zoneKey in ipairs(raidZoneOrder) do
            ADKP_RaidZoneExpanded[zoneKey] = false
        end
    end
    
    for _, zoneKey in ipairs(raidZoneOrder) do
        local zoneInfo = ADKP_RaidBosses[zoneKey]
        if zoneInfo then
            table.insert(visibleLines, {
                type = "zone",
                key = zoneKey,
                name = (GetLocale() == "zhCN" or GetLocale() == "zhTW") and zoneInfo.name_zh or zoneKey,
                info = zoneInfo
            })
            if ADKP_RaidZoneExpanded[zoneKey] then
                for _, boss in ipairs(zoneInfo.bosses) do
                    table.insert(visibleLines, {
                        type = "boss",
                        zoneKey = zoneKey,
                        boss = boss,
                        name = ADKP_BossDisplayName(boss)
                    })
                end
            end
        end
    end
    
    -- 2. 清理/隐藏之前的可见项
    frame.raidListItems = frame.raidListItems or {}
    for _, item in ipairs(frame.raidListItems) do
        item:Hide()
    end
    
    -- 3. 根据 visibleLines 渲染行
    local lineGap = 20
    local totalHeight = table.getn(visibleLines) * lineGap
    frame.raidScrollChild:SetHeight(totalHeight)
    
    for i, lineData in ipairs(visibleLines) do
        local item = frame.raidListItems[i]
        if not item then
            -- 创建行 Frame
            item = CreateFrame("Frame", "ADKP_RaidBossLine_"..i, frame.raidScrollChild)
            item:EnableMouse(true)
            item:SetScript("OnEnter", ADKP_BossRule_OnEnter)
            item:SetScript("OnLeave", ADKP_BossRule_OnLeave)
            item:SetWidth(280)
            item:SetHeight(18)
            
            -- 展开/折叠按钮
            local expBtn = CreateFrame("Button", nil, item)
            expBtn:SetWidth(14)
            expBtn:SetHeight(14)
            item.expBtn = expBtn
            
            expBtn:SetScript("OnClick", function()
                local key = this.key
                local mainFrame = this:GetParent().mainFrame
                if key and mainFrame then
                    ADKP_RaidZoneExpanded[key] = not ADKP_RaidZoneExpanded[key]
                    ADKP_UpdateBossListFrame(mainFrame)
                end
            end)
            
            -- 复选框
            local chk = CreateFrame("CheckButton", "ADKP_RaidBossLineChk_"..i, item, "UICheckButtonTemplate")
            chk:SetWidth(18)
            chk:SetHeight(18)
            item.chk = chk
            
            chk:SetScript("OnClick", function()
                local isChecked = false
                if this:GetChecked() then
                    isChecked = true
                end
                local mainFrame = this:GetParent().mainFrame
                if this.type == "zone" then
                    if this.bosses then
                        for _, b in ipairs(this.bosses) do
                            ADKP_SetBossEnabledState(b, isChecked)
                        end
                    end
                elseif this.type == "boss" then
                    if this.boss then
                        ADKP_SetBossEnabledState(this.boss, isChecked)
                    end
                end
                if mainFrame then
                    ADKP_UpdateBossListFrame(mainFrame)
                end
            end)
            
            -- 文本标签
            local label = item:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            item.label = label

            -- 行内分值输入框（主/替，仅 boss 行显示；留空=继承统一默认值）
            local ptRaidLbl = item:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            ptRaidLbl:SetText("主")
            ptRaidLbl:SetTextColor(0.6, 0.6, 0.6)
            item.ptRaidLbl = ptRaidLbl

            local ptRaid = CreateFrame("EditBox", "ADKP_RaidBossLinePtRaid_"..i, item, "InputBoxTemplate")
            ptRaid:SetWidth(34)
            ptRaid:SetHeight(16)
            ptRaid:SetAutoFocus(false)
            ptRaid:SetFontObject("GameFontHighlightSmall")
            ptRaid:SetJustifyH("CENTER")
            ptRaid.field = "raid"
            ptRaid:SetScript("OnEnterPressed", function()
                ADKP_BossListRowPtCommit(this)
                this:ClearFocus()
            end)
            ptRaid:SetScript("OnEscapePressed", function() ADKP_BossListRowPtCancel(this) end)
            ptRaid:SetScript("OnEditFocusLost", function() ADKP_BossListRowPtCommit(this) end)
            item.ptRaid = ptRaid

            local ptSubLbl = item:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            ptSubLbl:SetText("替")
            ptSubLbl:SetTextColor(0.6, 0.6, 0.6)
            item.ptSubLbl = ptSubLbl

            local ptSub = CreateFrame("EditBox", "ADKP_RaidBossLinePtSub_"..i, item, "InputBoxTemplate")
            ptSub:SetWidth(34)
            ptSub:SetHeight(16)
            ptSub:SetAutoFocus(false)
            ptSub:SetFontObject("GameFontHighlightSmall")
            ptSub:SetJustifyH("CENTER")
            ptSub.field = "sub"
            ptSub:SetScript("OnEnterPressed", function()
                ADKP_BossListRowPtCommit(this)
                this:ClearFocus()
            end)
            ptSub:SetScript("OnEscapePressed", function() ADKP_BossListRowPtCancel(this) end)
            ptSub:SetScript("OnEditFocusLost", function() ADKP_BossListRowPtCommit(this) end)
            item.ptSub = ptSub

            frame.raidListItems[i] = item
        end
        
        item.mainFrame = frame
        item:ClearAllPoints()
        item:SetPoint("TOPLEFT", 0, -(i-1)*lineGap)
        item:Show()
        
        -- 根据类型设置布局与交互
        if lineData.type == "zone" then
            item.bossRef = nil
            item.chk.bossRef = nil
            item.label:SetWidth(240)
            item.label:SetHeight(16)
            -- 区域：显示展开按钮，调整缩进，大号字体
            item.expBtn.key = lineData.key
            item.expBtn:ClearAllPoints()
            item.expBtn:SetPoint("LEFT", 5, 0)
            item.expBtn:Show()
            
            if ADKP_RaidZoneExpanded[lineData.key] then
                item.expBtn:SetNormalTexture("Interface\\Buttons\\UI-MinusButton-Up")
                item.expBtn:SetPushedTexture("Interface\\Buttons\\UI-MinusButton-Down")
            else
                item.expBtn:SetNormalTexture("Interface\\Buttons\\UI-PlusButton-Up")
                item.expBtn:SetPushedTexture("Interface\\Buttons\\UI-PlusButton-Down")
            end
            item.expBtn:SetHighlightTexture("Interface\\Buttons\\UI-PlusButton-Hilight")
            
            item.chk.type = "zone"
            item.chk.bosses = lineData.info.bosses
            item.chk:ClearAllPoints()
            item.chk:SetPoint("LEFT", item.expBtn, "RIGHT", 5, 0)
            item.chk:SetWidth(20)
            item.chk:SetHeight(20)

            -- 区域行不显示分值输入框
            item.ptRaidLbl:Hide()
            item.ptRaid:Hide()
            item.ptSubLbl:Hide()
            item.ptSub:Hide()
            
            item.label:ClearAllPoints()
            item.label:SetPoint("LEFT", item.chk, "RIGHT", 5, 0)
            item.label:SetFontObject("GameFontNormal")
            item.label:SetText(lineData.name)
            
            -- 计算区域 checkbox 状态
            local allEnabled = true
            local allDisabled = true
            for _, b in ipairs(lineData.info.bosses) do
                if ADKP_IsBossEnabled(b.en) then
                    allDisabled = false
                else
                    allEnabled = false
                end
            end
            
            if allDisabled then
                item.chk:SetChecked(false)
                item.label:SetTextColor(0.6, 0.6, 0.6) -- 灰色表示全部禁用
            elseif allEnabled then
                item.chk:SetChecked(true)
                item.label:SetTextColor(1, 0.82, 0) -- 经典亮黄色
            else
                item.chk:SetChecked(true)
                item.label:SetTextColor(0.9, 0.9, 0.5) -- 浅黄色表示部分启用
            end
            
        elseif lineData.type == "boss" then
            item.bossRef = lineData.boss
            item.chk.bossRef = lineData.boss
            item.chk:SetScript("OnEnter", ADKP_BossRule_OnEnter)
            item.chk:SetScript("OnLeave", ADKP_BossRule_OnLeave)
            -- 首领：隐藏展开按钮，增加缩进，小号字体
            item.expBtn:Hide()

            item.chk.type = "boss"
            item.chk.boss = lineData.boss
            item.chk:ClearAllPoints()
            item.chk:SetPoint("LEFT", 25, 0)
            item.chk:SetWidth(16)
            item.chk:SetHeight(16)

            item.label:ClearAllPoints()
            item.label:SetPoint("LEFT", item.chk, "RIGHT", 5, 0)
            item.label:SetFontObject("GameFontHighlightSmall")
            item.label:SetText(lineData.name)
            item.label:SetWidth(128)
            item.label:SetHeight(16)
            item.label:SetJustifyH("LEFT")

            -- 首领行：显示主/替分值输入框（黄色=差异化覆盖，灰色=继承统一默认）
            item.ptRaid.bossRef = lineData.boss
            item.ptRaid.mainFrame = frame
            item.ptRaid:ClearAllPoints()
            item.ptRaid:SetPoint("LEFT", 192, 0)
            item.ptRaid:Show()
            item.ptRaidLbl:ClearAllPoints()
            item.ptRaidLbl:SetPoint("RIGHT", item.ptRaid, "LEFT", -3, 0)
            item.ptRaidLbl:Show()

            item.ptSub.bossRef = lineData.boss
            item.ptSub.mainFrame = frame
            item.ptSub:ClearAllPoints()
            item.ptSub:SetPoint("LEFT", 240, 0)
            item.ptSub:Show()
            item.ptSubLbl:ClearAllPoints()
            item.ptSubLbl:SetPoint("RIGHT", item.ptSub, "LEFT", -3, 0)
            item.ptSubLbl:Show()

            ADKP_BossListRowPtFill(item.ptRaid)
            ADKP_BossListRowPtFill(item.ptSub)
            
            local isEnabled = ADKP_IsBossEnabled(lineData.boss.en)
            item.chk:SetChecked(isEnabled)
            
            if isEnabled then
                item.label:SetTextColor(1, 1, 1) -- 亮白色
                item.label:SetFontObject("GameFontHighlightSmall")
            else
                item.label:SetTextColor(0.5, 0.5, 0.5) -- 灰色
                item.label:SetFontObject("GameFontNormalSmall")
            end
        end
    end
    
    -- 更新滚动条范围
    if frame.customScrollFrame then
        frame.customScrollFrame:UpdateScrollChildRect()
    end
    if frame.excludedScrollFrame then
        frame.excludedScrollFrame:UpdateScrollChildRect()
    end
    if frame.raidScrollFrame then
        frame.raidScrollFrame:UpdateScrollChildRect()
    end
end

-- ================================
-- 添加排除BOSS
-- ================================
function ADKP_AddExcludedBoss(bossName)
    if not bossName or bossName == "" then
        return
    end
    
    -- 确保ExcludedBosses是表
    if not WebDKP_Options["ExcludedBosses"] then
        WebDKP_Options["ExcludedBosses"] = {}
    end
    
    -- 检查是否已存在
    for _, name in ipairs(WebDKP_Options["ExcludedBosses"]) do
        if name == bossName then
            return
        end
    end
    
    -- 添加到排除列表
    table.insert(WebDKP_Options["ExcludedBosses"], bossName)
end

-- ================================
-- 移除排除BOSS
-- ================================
function ADKP_RemoveExcludedBoss(index)
    if index and WebDKP_Options["ExcludedBosses"] and WebDKP_Options["ExcludedBosses"][index] then
        table.remove(WebDKP_Options["ExcludedBosses"], index)
    end
end

-- ================================
-- 检查BOSS是否在排除名单中
-- ================================
function ADKP_IsBossExcluded(bossName)
    if not bossName or bossName == "" then
        return false
    end
    
    local excludedBosses = WebDKP_Options["ExcludedBosses"] or {}
    for _, name in ipairs(excludedBosses) do
        if bossName == name then
            return true
        end
    end
    
    return false
end

-- ================================
-- 显示BOSS排除名单管理界面
-- ================================
function ADKP_ShowExcludedBossesFrame()
    if not ADKP_ExcludedBossesFrame then
        ADKP_ExcludedBossesFrame = ADKP_CreateExcludedBossesFrame()
    end

    if ADKP_ExcludedBossesFrame then
        -- 每次打开时回显工具栏默认分值（此刻输入框必无焦点，可安全覆盖）
        ADKP_BossListToolbar_Sync(ADKP_ExcludedBossesFrame)
        ADKP_ExcludedBossesFrame:Show()
    end
    
    if ADKP_Frame then
        ADKP_Frame:Hide()
    end
end

-- ================================
-- 新版 Boss 击杀加分弹窗：主团/替补团两个分值（默认读「杀」右键设置）
-- 加分只加当前团队，reason = "击杀-Boss名"
-- ================================
function ADKP_ShowBossKillAwardFrame()
    local frame = ADKP_BossKillAwardFrame
    if not frame then
        ADKP_Print("错误：未找到 ADKP_BossKillAwardFrame 弹窗，请检查 XML 是否加载。")
        return
    end

    -- 初始化关联以和 Lua 其它逻辑保持兼容
    if not frame.raidEdit then
        frame.raidEdit = ADKP_BossKillRaidEdit
        frame.subEdit = ADKP_BossKillSubEdit
        frame.bossNameText = ADKP_BossKillAwardFrameBossNameText
    end

    -- 填充 Boss 名
    frame.bossNameText:SetText("BOSS: " .. (ADKP_BossAwardData.bossName or "未知"))

    -- 默认分值：读 Boss 分值配置（差异化覆盖 -> 全局默认，未配置为 1）
    local job = ADKP_BossEncounterState.active
    local raid, sub
    if job then raid, sub = job.raid, job.sub
    else raid, sub = ADKP_GetBossAwardPoints(ADKP_BossAwardData.bossName or "") end
    frame.raidEdit:SetText(tostring(raid))
    frame.subEdit:SetText(tostring(sub))

    frame:Show()
end

-- ================================
-- Boss击杀加分弹窗确定按钮回调
-- ================================
function ADKP_BossKillAwardFrame_OkClick()
    local frame = ADKP_BossKillAwardFrame
    if not frame or not frame:IsShown() or not frame.raidEdit or not frame.subEdit or not ADKP_BossEncounterState.active then
        return
    end
    local raidPts = tonumber(frame.raidEdit:GetText()) or nil
    local subPts = tonumber(frame.subEdit:GetText()) or nil
    if raidPts == nil and subPts == nil then
        ADKP_Print("请至少输入一个分值")
        return
    end
    if raidPts == nil then raidPts = 0 end
    if subPts == nil then subPts = 0 end
    -- 注意：弹窗里手动修改的分值只对本次加分生效，不回写 Boss 分值配置
    -- （预填永远来自 Boss 名单的分值配置，差异化请到 Boss 名单页设置）
    ADKP_BossEncounter_Submit(raidPts, subPts)
end

-- 初始化替补队员数据存储
ADKP_PendingSubMembers = ADKP_PendingSubMembers or {}



-- ================================
-- 为替补队员加分
-- ================================
-- 添加缺失的ADKP_AwardSubPoints_Event函数，解决UI按钮点击错误
-- ================================
-- 为所有团队成员加分
-- ================================
-- 添加缺失的ADKP_AwardAllDKP_Event函数，解决UI按钮点击错误
function ADKP_AwardAllDKP_Event()
	-- 优先使用ADKP_BossAwardData中的数据（击杀弹窗调用时）
    local points = ADKP_BossAwardData and ADKP_BossAwardData.points or ADKP_AwardDKP_FramePoints:GetText();
    
	-- 固定使用"击杀-boss名称"格式作为项目名称，不使用玩家填写的内容
    local reason = "";
    if ADKP_BossAwardData and ADKP_BossAwardData.bossName then
        reason = "击杀-" .. ADKP_BossAwardData.bossName;

    else
        -- 非击杀弹窗调用时，使用输入框的内容
        reason = ADKP_AwardDKP_FrameReason:GetText();
    end

    if (points == nil or points == "") then
        ADKP_Print("您必须输入DKP.");
        PlaySound("igQuestFailed");
        return;
    end
    
    points = ADKP_ROUND(points, 2);
    
	-- 确保points是有效数字
    if (type(points) ~= "number" or points ~= points) then
        ADKP_Print("DKP点数必须是有效数字.");
        PlaySound("igQuestFailed");
        return;
    end
    
	-- 获取所有团队成员
    local players = ADKP_GetAllRaidMembers();
    
    local isEmpty = true
    if players ~= nil then
        for k, v in pairs(players) do
            isEmpty = false
            break
        end
    end
    if (players == nil or isEmpty) then
        ADKP_Print("没有找到团队成员. 奖惩无效.");
        PlaySound("igQuestFailed");
    else
        ADKP_AddDKP(points, reason, "false", players);
        ADKP_AnnounceAward(points, reason);

        -- 更新表格显示
        ADKP_UpdateTableToShow();
        ADKP_UpdateTable();
        
        -- 同时更新数据列表
        if ADKP_UpdateLootList then
            ADKP_UpdateLootList();
        end
        

    end
end

-- 获取所有团队成员
function ADKP_GetAllRaidMembers()
    local players = {};
    local playerCount = 0;
    
	-- 检查是否在团队中
    if GetNumRaidMembers() > 0 then
        for i = 1, GetNumRaidMembers() do
            local name = UnitName("raid" .. i);
            if name then
                playerCount = playerCount + 1;
                players[playerCount] = {
                    name = name,
                    class = ADKP_GetPlayerClass(name) or "战士"
                };
            end
        end
    else
        -- 如果不在团队中，至少包括自己
        local playerName = UnitName("player");
        playerCount = playerCount + 1;
        players[playerCount] = {
            name = playerName,
            class = ADKP_GetPlayerClass(playerName) or "战士"
        };
    end
    
    if playerCount > 0 then
        return players;
    else
        return nil;
    end
end

-- 将英文职业名及中文别名规范化为统一中文名称（用于显示）
function ADKP_NormalizeClassName(className)
	if not className then return className end
	if className == "盗贼" then return "潜行者" end
	local lowerClass = string.lower(className)
	if string.find(lowerClass, "warrior") then
		return "战士"
	elseif string.find(lowerClass, "warlock") then
		return "术士"
	elseif string.find(lowerClass, "shaman") then
		return "萨满祭司"
	elseif string.find(lowerClass, "paladin") then
		return "圣骑士"
	elseif string.find(lowerClass, "priest") then
		return "牧师"
	elseif string.find(lowerClass, "hunter") then
		return "猎人"
	elseif string.find(lowerClass, "mage") then
		return "法师"
	elseif string.find(lowerClass, "druid") then
		return "德鲁伊"
	elseif string.find(lowerClass, "rogue") then
		return "潜行者"
	end
	return className
end

-- 获取替补玩家列表（排除已在团队中的玩家）
local function ADKP_GetSubMembersForAward()
    local subPlayers = {}
    local subCount = 0
    local captain = ""
    local includeSubCaptain = WebDKP_Options and WebDKP_Options["IncludeSubCaptain"]
    local lowerCaptain = nil

    -- 读当前团的替补队长（统一走输入框 → 缓存 → 持久化的 fallback）
    if ADKP_AwardDKP_FrameSubLeaderInput then
        captain = ADKP_AwardDKP_FrameSubLeaderInput:GetText() or ""
    end
    if captain == "" and ADKP_SubAwardData and ADKP_SubAwardData.captain then
        captain = ADKP_SubAwardData.captain or ""
    end
    if captain == "" then
        captain = ADKP_GetSubCaptain(ADKP_GetTableid())
    end
    if captain and captain ~= "" then
        captain = string.gsub(captain, "^%s*", "")
        captain = string.gsub(captain, "%s*$", "")
    end
    if not includeSubCaptain and captain ~= "" then
        lowerCaptain = string.lower(captain)
    end

    if ADKP_PendingSubMembers and captain ~= "" then
        local targetKey = nil
        local lowerCaptainKey = string.lower(captain)

        if ADKP_PendingSubMembers[captain] then
            targetKey = captain
        elseif ADKP_PendingSubMembers[lowerCaptainKey] then
            targetKey = lowerCaptainKey
        else
            for key, _ in pairs(ADKP_PendingSubMembers) do
                if string.lower(key) == lowerCaptainKey then
                    targetKey = key
                    break
                end
            end
        end

        if targetKey then
            local lowerCaptainForList = lowerCaptain
            if not includeSubCaptain and (not lowerCaptainForList or lowerCaptainForList == "") then
                lowerCaptainForList = string.lower(targetKey)
            end
            for memberName, entry in pairs(ADKP_PendingSubMembers[targetKey]) do
                if lowerCaptainForList and string.lower(memberName) == lowerCaptainForList then
                    -- skip sub captain when unchecked
                elseif not ADKP_PlayerInGroup(memberName) then
                    subCount = subCount + 1
                    local className = nil
                    if type(entry) == "table" and entry.class and entry.class ~= "" then
                        className = entry.class
                    elseif type(entry) == "string" and entry ~= "" then
                        className = entry
                    end
                    if not className then
                        className = ADKP_GetPlayerClass(memberName) or "战士"
                    end
                    subPlayers[subCount] = {
                        name = memberName,
                        class = ADKP_NormalizeClassName(className)
                    }
                end
            end
        end
    end

    if subCount == 0 then
        return nil, 0
    end

    return subPlayers, subCount
end

-- ================================
-- 获取替补队长名称（悬浮窗与加分流程共用）
-- ================================
local function ADKP_Z_GetCaptainName()
    local captain = ""
    -- 优先读输入框
    if ADKP_AwardDKP_FrameSubLeaderInput then
        captain = ADKP_AwardDKP_FrameSubLeaderInput:GetText() or ""
    end
    -- 输入框为空时读运行时缓存
    if captain == "" and ADKP_SubAwardData and ADKP_SubAwardData.captain then
        captain = ADKP_SubAwardData.captain or ""
    end
    -- 缓存为空时读当前团的持久化值
    if captain == "" then
        captain = ADKP_GetSubCaptain(ADKP_GetTableid())
    end
    captain = ADKP_TrimText(captain)
    return captain
end

-- ================================
-- 按主替独立分值执行加分（悬浮窗与加分流程共用）
-- ================================
local function ADKP_Z_ApplyAward(raidPoints, subPoints, reason, awardDate, recordCtx)
    if ADKP_UpdatePlayersInGroup then
        ADKP_UpdatePlayersInGroup()
    end

    local raidPlayers = ADKP_GetAllRaidMembers()
    local raidCount = 0
    if raidPlayers then
        for _, _ in pairs(raidPlayers) do
            raidCount = raidCount + 1
        end
    end

    local raidRecordRef, subRecordRef = nil, nil
    local awardedRaidCount = 0
    local awardedRaidPoints = 0
    if raidPlayers and raidCount > 0 then
        raidRecordRef = ADKP_AddDKP(raidPoints, reason, "false", raidPlayers, nil, awardDate)
        -- 不再单独 AnnounceAward（由末尾总结播报合并为 1 行，避免刷屏）
        awardedRaidCount = raidCount
        awardedRaidPoints = raidPoints
    end

    -- 同步被中止（队长失联/名单不完整）时跳过替补段：宁可不加，不能静默少人。
    -- 替补只使用当前队长回传的名单；未设置队长时不加替补分。
    local subSyncAborted = (ADKP_SubAwardData and ADKP_SubAwardData.subSyncAborted) and true or false
    local subPlayersAll, subCountAll = nil, 0
    if not subSyncAborted then
        subPlayersAll, subCountAll = ADKP_GetSubMembersForAward()
    end
    local awardedSubCount = 0
    local awardedSubPoints = 0
    if subPlayersAll and subCountAll > 0 then
        local subReason = reason
        if subReason == "" then
            subReason = "替补"
        else
            subReason = subReason .. "-替补"
        end
        subRecordRef = ADKP_AddDKP(subPoints, subReason, "false", subPlayersAll, nil, awardDate)
        -- 不再单独 AnnounceAward（由末尾总结播报合并为 1 行，避免刷屏）
        awardedSubCount = subCountAll
        awardedSubPoints = subPoints
    end

    ADKP_UpdateTableToShow()
    ADKP_UpdateTable()
    if ADKP_UpdateLootList then
        ADKP_UpdateLootList()
    end

    if awardedRaidCount > 0 or awardedSubCount > 0 then
        -- 精简播报：1 行包含主团/替补分值 + 人数 + 原因
        -- 格式：主团+2 (30人)，替补+1 (6人) 击杀-拉格纳罗斯
        -- 替补 0 人时保留完整格式「替补+0 (0人)」
        local function formatPoints(pts)
            local n = tonumber(pts) or 0
            if n >= 0 then return "+" .. n end
            return tostring(n)
        end
        local announceText = "主团" .. formatPoints(awardedRaidPoints) .. " (" .. awardedRaidCount .. "人)"
        if not subSyncAborted then
            -- 替补同步被中止时只播报主团（错误详情已本地红字提示，不刷团队频道）
            announceText = announceText .. "，替补" .. formatPoints(awardedSubPoints) .. " (" .. awardedSubCount .. "人)"
        end
        if reason and reason ~= "" then
            announceText = announceText .. " " .. reason
        end
        local channel = "NONE"
        if GetNumRaidMembers() > 0 then
            channel = "RAID"
        elseif GetNumPartyMembers() > 0 then
            channel = "PARTY"
        end
        if ADKP_SendAnnouncement then
            ADKP_SendAnnouncement(announceText, channel, true)
        elseif SendChatMessage then
            local isSilentMode = WebDKP_Options and WebDKP_Options["SilentMode"]
            if channel == "NONE" then
                ADKP_Print(announceText)
            elseif isSilentMode then
                ADKP_Print("[静默] " .. announceText)
            else
                SendChatMessage(announceText, channel)
            end
        end
    end

    -- 全自动加分：关联实际主团/替补日志，悬浮窗不再保存独立的分值和人数副本。
    if type(recordCtx) == "table" then
        recordCtx.raidRef = raidRecordRef
        recordCtx.subRef = subRecordRef
        recordCtx.ab = subSyncAborted and true or false
        ADKP_AppendBossAutoAwardRecord(recordCtx)
    end
end


-- ================================
-- 快捷浮窗：集 / 散 / 杀 / 奖惩
-- 说明：
-- 1) 仅在 RAID 团队中显示（GetNumRaidMembers() > 0）
-- 2) 在“自用”Tab 勾选 WebDKP_Options["QuickFloatEnabled"] 后才显示
-- 3) 左键：集/散/杀按默认分值执行；奖惩打开快速操作面板
-- 4) 右键：集/散/杀设置主队和替补分值，奖惩设置四个常用分值
-- 语义对应：
-- - 集：等同 /adkpa（原因=集合分，受排除未报名/未出勤扣分影响）
-- - 散：等同 /adkpb（原因=解散分）
-- - 杀：等同 /adkpk（原因=击杀-目标名/原因）
-- - 奖惩：打开单目标快速奖惩面板，支持成员搜索、目标跟随和最近原因
-- 注意：集/散/杀使用主队/替补独立分值；奖惩始终是单目标操作

local function ADKP_QuickFloat_InitOptions()
    if not WebDKP_Options then
        WebDKP_Options = {}
    end
    if WebDKP_Options["QuickFloatEnabled"] == nil then
        WebDKP_Options["QuickFloatEnabled"] = true
    end
	ADKP_QuickBid_InitQualityFilter()
    if not WebDKP_Options["QuickFloatSettings"] then
        WebDKP_Options["QuickFloatSettings"] = {}
    end
    local s = WebDKP_Options["QuickFloatSettings"]
    if not s["rally"] then s["rally"] = {} end
    if not s["dismiss"] then s["dismiss"] = {} end
    if not s["kill"] then s["kill"] = {} end
    if not s["adjust"] then s["adjust"] = {} end
    if s["kill"].reason == nil then s["kill"].reason = "" end
    if s["adjust"].reason == nil then s["adjust"].reason = "" end
    if s["adjust"].player == nil then s["adjust"].player = "" end
    if s["adjust"].points == nil then
        -- 兼容旧版本：之前用 raidPoints/subPoints 保存过“调”的分值
        if type(s["adjust"].raidPoints) == "number" then
            s["adjust"].points = s["adjust"].raidPoints
        elseif type(s["adjust"].subPoints) == "number" then
            s["adjust"].points = s["adjust"].subPoints
        end
    end
    if type(s["adjust"].quickPoints) ~= "table" then
        s["adjust"].quickPoints = { 1, 2, 5, 10 }
    end
    local quickDefaults = { 1, 2, 5, 10 }
    for i = 1, 4 do
        local value = tonumber(s["adjust"].quickPoints[i])
        if not value or value <= 0 then value = quickDefaults[i] end
        s["adjust"].quickPoints[i] = value
    end
    if s["adjust"].followTarget == nil then
        s["adjust"].followTarget = false
    end
    if type(s["adjust"].recentReasons) ~= "table" then
        s["adjust"].recentReasons = {}
    end
    if type(s["adjust"].position) ~= "table" then
        s["adjust"].position = nil
    end
end

local function ADKP_QuickFloat_GetSettings(key)
    ADKP_QuickFloat_InitOptions()
    local s = WebDKP_Options["QuickFloatSettings"][key]
    if not s then
        return nil, nil, ""
    end
    if key == "adjust" then
        local points = s.points
        if type(points) ~= "number" then points = nil end
        local player = s.player or ""
        local reason = s.reason or ""
        return points, player, reason
    else
        local raidPoints = s.raidPoints
        local subPoints = s.subPoints
        if type(raidPoints) ~= "number" then raidPoints = nil end
        if type(subPoints) ~= "number" then subPoints = nil end
        local reason = s.reason or ""
        return raidPoints, subPoints, reason
    end
end

local function ADKP_QuickFloat_SetSettings(key, raidPoints, subPoints, reason)
    ADKP_QuickFloat_InitOptions()
    local s = WebDKP_Options["QuickFloatSettings"][key]
    if not s then
        s = {}
        WebDKP_Options["QuickFloatSettings"][key] = s
    end
    if key == "adjust" then
        s.points = raidPoints
        s.player = subPoints or ""
        if reason ~= nil then
            s.reason = reason
        end
    else
        s.raidPoints = raidPoints
        s.subPoints = subPoints
        if reason ~= nil then
            s.reason = reason
        end
    end
end

local function ADKP_QuickFloat_GetActionLabel(key)
    if key == "rally" then return "集" end
    if key == "dismiss" then return "散" end
    if key == "kill" then return "杀" end
    if key == "adjust" then return "奖惩" end
    return "?"
end

local function ADKP_QuickFloat_GetActionName(key)
    if key == "rally" then return "集合分" end
    if key == "dismiss" then return "解散分" end
    if key == "kill" then return "击杀" end
    if key == "adjust" then return "快速奖惩" end
    return ""
end

local function ADKP_QuickFloat_ShowConfirm(text, onAccept)
    if not StaticPopupDialogs then
        StaticPopupDialogs = {}
    end
    if not StaticPopupDialogs["ADKP_QUICKFLOAT_CONFIRM"] then
        StaticPopupDialogs["ADKP_QUICKFLOAT_CONFIRM"] = {
            text = "",
            button1 = "确定",
            button2 = "取消",
            OnAccept = function()
                local dialog = StaticPopupDialogs["ADKP_QUICKFLOAT_CONFIRM"]
                if dialog and dialog._confirmCallback then
                    dialog._confirmCallback()
                end
            end,
            timeout = 0,
            whileDead = 1,
            hideOnEscape = 1
        }
    end
    StaticPopupDialogs["ADKP_QUICKFLOAT_CONFIRM"].text = text
    StaticPopupDialogs["ADKP_QUICKFLOAT_CONFIRM"]._confirmCallback = onAccept
    StaticPopup_Show("ADKP_QUICKFLOAT_CONFIRM")
end

local function ADKP_QuickFloat_SearchSubsThenRun(callback)
    -- 每次全团加分都强制向替补队长重新请求最新名单，不使用缓存。
    -- 先清一次上次同步可能遗留的中止标志（无队长直接执行的路径不能被旧状态拦住）。
    ADKP_ResetSubSyncState()
    local captain = ""
    if ADKP_Z_GetCaptainName then
        captain = ADKP_Z_GetCaptainName()
    end

    -- 没有配置替补队长：直接执行（仅主团加分）
    if captain == "" or not ADKP_SearchSubMembers_Event then
        if callback then callback() end
        return
    end

    if not ADKP_SubAwardData then
        ADKP_SubAwardData = {}
    end
    ADKP_SubAwardData.captain = captain

    -- 强制查询：保持 ForceQuery=true 直到收到真实响应或超时
    -- 防止 waitFrame 期间其他路径调用 SearchSubMembers 时命中缓存
    ADKP_SubSync_ForceQuery = true
    ADKP_SearchSubMembers_Event()

    local waitFrame = CreateFrame("Frame")
    waitFrame.startTime = GetTime()
    waitFrame:SetScript("OnUpdate", function()
        local frame = this or waitFrame
        local elapsed = GetTime() - (frame.startTime or 0)
        -- receivedResponse 仅在 SUB_COMPLETE 且人数核对通过后置位；
        -- 早到的分包不再触发加分，杜绝尾包未到就执行导致静默少人。
        local responded = ADKP_SubAwardData and ADKP_SubAwardData.receivedResponse
        local aborted = ADKP_SubAwardData and ADKP_SubAwardData.subSyncAborted
        if responded or aborted then
            frame:SetScript("OnUpdate", nil)
            ADKP_SubSync_ForceQuery = false
            if callback then callback() end
        elseif elapsed >= 3 then
            frame:SetScript("OnUpdate", nil)
            ADKP_SubSync_ForceQuery = false
            if ADKP_SubAwardData then
                ADKP_SubAwardData.subSyncAborted = true
            end
            local exp = ADKP_SubAwardData and ADKP_SubAwardData.expectedCount
            local rec = (ADKP_SubAwardData and ADKP_SubAwardData.receivedCount) or 0
            if exp then
                ADKP_Print("|cffff0000替补名单不完整：收到 "..rec.."/应到 "..exp.."，本次不加替补分。|r 可用 /subteam 刷新后手动补发。")
            else
                ADKP_Print("|cffff0000无法联系替补队长 ["..captain.."]，本次不加替补分。|r 可用 /subteam 刷新后手动补发。")
            end
            if callback then callback() end
        end
    end)
end

-- Boss and quick-float awards share the standby roster state. Serialize all of
-- these callers, not just two consecutive automatic boss awards.
local ADKP_RaidSubAwardQueue = {}
local ADKP_RaidSubAwardBusy = false
local function ADKP_RunNextRaidSubAward()
    if ADKP_RaidSubAwardBusy or table.getn(ADKP_RaidSubAwardQueue) == 0 then return end
    local job = table.remove(ADKP_RaidSubAwardQueue, 1)
    ADKP_RaidSubAwardBusy = true
    local applied = false
    ADKP_QuickFloat_SearchSubsThenRun(function()
        if applied then return end
        applied = true
        local success = true
        if job.tableid ~= ADKP_GetTableid() or (job.bossAward and not ADKP_BossEncounter_IsEnabled()) then
            ADKP_Print("加分已暂缓：DKP 团队已切换或击杀加分已关闭。")
            success = false
        else
            ADKP_Z_ApplyAward(job.raid, job.sub, job.reason, job.date, job.recordCtx)
        end
        ADKP_RaidSubAwardBusy = false
        if job.onComplete then job.onComplete(success) end
        ADKP_RunNextRaidSubAward()
    end)
end

function ADKP_RunRaidAndSubAward(raidPoints, subPoints, reason, recordCtx, onComplete, expectedTableId)
    -- Freeze one timestamp for both main-raid and standby logs before querying.
    table.insert(ADKP_RaidSubAwardQueue, {
        raid = raidPoints, sub = subPoints, reason = reason, recordCtx = recordCtx,
        date = date("%Y-%m-%d %H:%M:%S"), onComplete = onComplete,
        tableid = expectedTableId or ADKP_GetTableid(), bossAward = expectedTableId ~= nil,
    })
    ADKP_RunNextRaidSubAward()
end

local function ADKP_QuickFloat_ExecuteRaidSub(key, raidPoints, subPoints, reason)
    ADKP_QuickFloat_ShowConfirm(
        "确认执行【" .. ADKP_QuickFloat_GetActionLabel(key) .. "】吗？\n主队: " .. tostring(raidPoints) .. "\n替补: " .. tostring(subPoints) .. "\n原因: " .. reason,
        function()
            ADKP_RunRaidAndSubAward(raidPoints, subPoints, reason)
        end
    )
end

local ADKP_QuickFloatFrame = nil
local ADKP_QuickFloatSettingsFrame = nil
local ADKP_QuickFloatHelpFrame = nil

-- 由竞拍开始/结束通知刷新，隐藏竞拍窗口不会清除提醒。
function ADKP_QuickFloat_UpdateBidGlow()
    local btn = ADKP_QuickFloatFrame and ADKP_QuickFloatFrame.bidBtn
    if not btn or not btn.bidGlow then return end
    if ADKP_Bid_IsInProgress and ADKP_Bid_IsInProgress() then
        btn.bidGlow:Show()
        if btn.bidNotice then btn.bidNotice:Show() end
    else
        btn.bidGlow:Hide()
        if btn.bidNotice then btn.bidNotice:Hide() end
    end
end
local ADKP_QuickAdjustFrame = nil
local ADKP_QuickAdjustPointSettingsFrame = nil

local function ADKP_QuickFloat_UpdateTooltip(key)
    if not GameTooltip then
        return
    end
    local v1, v2, reason = ADKP_QuickFloat_GetSettings(key)
    local title = "快捷浮窗 - " .. ADKP_QuickFloat_GetActionLabel(key)
    GameTooltip:SetText(title, 1, 1, 1)
    if key == "adjust" then
        GameTooltip:AddLine("左键: 打开快速奖惩", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("右键: 设置常用分值", 0.8, 0.8, 0.8)
    else
        local raidPoints = v1
        local subPoints = v2
        if type(raidPoints) == "number" and type(subPoints) == "number" then
            GameTooltip:AddLine("主队: " .. tostring(raidPoints) .. "  替补: " .. tostring(subPoints), 0.8, 0.8, 0.8)
        else
            GameTooltip:AddLine("右键设置默认分值", 0.8, 0.8, 0.8)
        end
        if key == "kill" then
            reason = ADKP_TrimText(reason or "")
            if reason ~= "" then
                GameTooltip:AddLine("原因: " .. reason, 0.8, 0.8, 0.8)
            else
                GameTooltip:AddLine("原因: (空)", 0.8, 0.8, 0.8)
            end
        end
    end
end

local function ADKP_QuickFloat_ShowSettings(key)
    ADKP_QuickFloat_InitOptions()
    if not ADKP_QuickFloatSettingsFrame then
        local f = CreateFrame("Frame", "ADKP_QuickFloatSettingsFrame", UIParent)
        f:SetWidth(270)
        f:SetHeight(190)
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        f:SetFrameStrata("DIALOG")
        f:EnableMouse(true)
        f:SetMovable(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", function() this:StartMoving() end)
        f:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
        f:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 }
        })
        f:SetBackdropColor(0, 0, 0, 0.9)

        f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        f.title:SetPoint("TOP", f, "TOP", 0, -14)
        f.title:SetText("快捷浮窗设置")

        f.raidLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        f.raidLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -44)
        f.raidLabel:SetText("主队分数:")
        f.raidEdit = CreateFrame("EditBox", "ADKP_QuickFloatRaidEdit", f, "InputBoxTemplate")
        f.raidEdit:SetAutoFocus(false)
        f.raidEdit:SetWidth(120)
        f.raidEdit:SetHeight(22)
        f.raidEdit:SetPoint("LEFT", f.raidLabel, "RIGHT", 10, 0)
        f.raidEdit:SetFontObject("ChatFontNormal")
        f.raidEdit:SetTextInsets(4, 4, 0, 0)
        f.raidEdit:SetScript("OnEscapePressed", function() this:ClearFocus() end)

        f.subLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        f.subLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -74)
        f.subLabel:SetText("替补分数:")
        f.subEdit = CreateFrame("EditBox", "ADKP_QuickFloatSubEdit", f, "InputBoxTemplate")
        f.subEdit:SetAutoFocus(false)
        f.subEdit:SetWidth(120)
        f.subEdit:SetHeight(22)
        f.subEdit:SetPoint("LEFT", f.subLabel, "RIGHT", 10, 0)
        f.subEdit:SetFontObject("ChatFontNormal")
        f.subEdit:SetTextInsets(4, 4, 0, 0)
        f.subEdit:SetScript("OnEscapePressed", function() this:ClearFocus() end)

        f.reasonLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        f.reasonLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -104)
        f.reasonLabel:SetText("原因(可选):")
        f.reasonEdit = CreateFrame("EditBox", "ADKP_QuickFloatReasonEdit", f, "InputBoxTemplate")
        f.reasonEdit:SetAutoFocus(false)
        f.reasonEdit:SetWidth(170)
        f.reasonEdit:SetHeight(22)
        f.reasonEdit:SetPoint("LEFT", f.reasonLabel, "RIGHT", 10, 0)
        f.reasonEdit:SetFontObject("ChatFontNormal")
        f.reasonEdit:SetTextInsets(4, 4, 0, 0)
        f.reasonEdit:SetScript("OnEscapePressed", function() this:ClearFocus() end)

        f.saveBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        f.saveBtn:SetWidth(100)
        f.saveBtn:SetHeight(22)
        f.saveBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 20, 16)
        f.saveBtn:SetText("保存")

        f.cancelBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        f.cancelBtn:SetWidth(80)
        f.cancelBtn:SetHeight(22)
        f.cancelBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -20, 16)
        f.cancelBtn:SetText("取消")
        f.cancelBtn:SetScript("OnClick", function()
            f:Hide()
        end)

        f.saveBtn:SetScript("OnClick", function()
            local key = f.actionKey
            if not key or key == "" then
                f:Hide()
                return
            end
            if key == "adjust" then
                local points = tonumber(f.raidEdit:GetText() or "")
                if type(points) ~= "number" then
                    ADKP_Print("错误：分数必须是数字。")
                    return
                end
                local player = ADKP_TrimText(f.subEdit:GetText() or "")
                local reason = ADKP_TrimText(f.reasonEdit:GetText() or "")
                ADKP_QuickFloat_SetSettings(key, points, player, reason)
            else
                local raidPoints = tonumber(f.raidEdit:GetText() or "")
                local subPoints = tonumber(f.subEdit:GetText() or "")
                if type(raidPoints) ~= "number" or type(subPoints) ~= "number" then
                    ADKP_Print("错误：主队/替补分数必须是数字。")
                    return
                end
                local reason = nil
                if key == "kill" then
                    reason = ADKP_TrimText(f.reasonEdit:GetText() or "")
                end
                ADKP_QuickFloat_SetSettings(key, raidPoints, subPoints, reason)
            end
            f:Hide()
        end)

        f:Hide()
        ADKP_QuickFloatSettingsFrame = f
    end

    local f = ADKP_QuickFloatSettingsFrame
    f.actionKey = key
    local v1, v2, reason = ADKP_QuickFloat_GetSettings(key)
    f.title:SetText("快捷浮窗设置 - " .. ADKP_QuickFloat_GetActionLabel(key) .. "（" .. ADKP_QuickFloat_GetActionName(key) .. "）")
    if key == "adjust" then
        f.raidLabel:SetText("分数:")
        f.subLabel:SetText("玩家(可选):")
        f.raidEdit:SetText(type(v1) == "number" and tostring(v1) or "")
        f.subEdit:SetText(v2 or "")
        f.reasonLabel:Show()
        f.reasonEdit:Show()
        f.reasonEdit:SetText(reason or "")
    else
        f.raidLabel:SetText("主队分数:")
        f.subLabel:SetText("替补分数:")
        f.raidEdit:SetText(type(v1) == "number" and tostring(v1) or "")
        f.subEdit:SetText(type(v2) == "number" and tostring(v2) or "")
        if key == "kill" then
            f.reasonLabel:Show()
            f.reasonEdit:Show()
            f.reasonEdit:SetText(reason or "")
        else
            f.reasonLabel:Hide()
            f.reasonEdit:Hide()
        end
    end
    f:Show()
end

local ADKP_QuickAdjustClassOrder = {
    "战士", "圣骑士", "猎人", "潜行者", "牧师",
    "萨满祭司", "法师", "术士", "德鲁伊", "未知"
}
local ADKP_QuickAdjustClassMenuPlayers = {}
local ADKP_QuickAdjustClassMenu = nil

local function ADKP_QuickAdjust_GetOptions()
    ADKP_QuickFloat_InitOptions()
    return WebDKP_Options["QuickFloatSettings"]["adjust"]
end

local function ADKP_QuickAdjust_GetTargetName()
    if not UnitName or not UnitIsPlayer or not UnitIsFriend then return nil end
    if not UnitIsPlayer("target") or not UnitIsFriend("player", "target") then return nil end
    local name = UnitName("target")
    if not name or name == "" then return nil end
    return name
end

local function ADKP_QuickAdjust_GetPlayers(filterText)
    local players = {}
    local filter = string.lower(ADKP_TrimText(filterText or ""))
    local tableid = ADKP_GetTableid()
    local dkpField = "dkp_" .. tableid
    if WebDKP_DkpTable then
        for name, data in pairs(WebDKP_DkpTable) do
            if type(name) == "string" and type(data) == "table" and data[dkpField] ~= nil then
                local lowerName = string.lower(name)
                if filter == "" or string.find(lowerName, filter, 1, true) then
                    local className = data.class or "未知"
                    if ADKP_NormalizeClassName then
                        className = ADKP_NormalizeClassName(className)
                    end
                    if not ADKP_CLASS_COLORS or not ADKP_CLASS_COLORS[className] then
                        className = "未知"
                    end
                    table.insert(players, { name = name, class = className or "未知" })
                end
            end
        end
    end
    table.sort(players, function(a, b) return string.lower(a.name) < string.lower(b.name) end)
    return players
end

local function ADKP_QuickAdjust_SetMember(name)
    if not ADKP_QuickAdjustFrame or not ADKP_QuickAdjustFrame.memberEdit then return end
    local frame = ADKP_QuickAdjustFrame
    frame.suppressMemberChange = true
    frame.memberEdit:SetText(name or "")
    frame.suppressMemberChange = false
    if frame.suggestionFrame then frame.suggestionFrame:Hide() end
end

local function ADKP_QuickAdjust_UpdateSuggestions()
    local frame = ADKP_QuickAdjustFrame
    if not frame or not frame.suggestionFrame then return end
    local filter = ADKP_TrimText(frame.memberEdit:GetText() or "")
    if filter == "" or not frame.memberEditing then
        frame.suggestionFrame:Hide()
        return
    end

    local players = ADKP_QuickAdjust_GetPlayers(filter)
    local visible = math.min(table.getn(players), table.getn(frame.suggestionRows))
    if visible == 0 then
        frame.suggestionFrame:Hide()
        return
    end

    for i = 1, table.getn(frame.suggestionRows) do
        local row = frame.suggestionRows[i]
        local player = players[i]
        if player then
            row.playerName = player.name
            row.text:SetText(ADKP_GetClassColor(player.class) .. player.name .. "|r")
            row:Show()
        else
            row.playerName = nil
            row:Hide()
        end
    end
    frame.suggestionFrame:SetHeight(visible * 20 + 8)
    frame.suggestionFrame:Show()
end

local function ADKP_QuickAdjust_ResolveMember()
    local frame = ADKP_QuickAdjustFrame
    local input = frame and ADKP_TrimText(frame.memberEdit:GetText() or "") or ""
    if input == "" then
        ADKP_Print("错误：请选择或输入奖惩成员。")
        return nil
    end

    local inputLower = string.lower(input)
    local matches = ADKP_QuickAdjust_GetPlayers(input)
    for i = 1, table.getn(matches) do
        if string.lower(matches[i].name) == inputLower then
            return matches[i].name
        end
    end
    if table.getn(matches) == 1 then
        return matches[1].name
    end
    if table.getn(matches) > 1 then
        frame.memberEditing = true
        ADKP_QuickAdjust_UpdateSuggestions()
        ADKP_Print("匹配到多名成员，请从候选名单中选择。")
        return nil
    end
    return input
end

local function ADKP_QuickAdjust_AddRecentReason(reason)
    local options = ADKP_QuickAdjust_GetOptions()
    local recent = {}
    table.insert(recent, reason)
    for i = 1, table.getn(options.recentReasons) do
        local oldReason = options.recentReasons[i]
        if oldReason ~= reason and table.getn(recent) < 6 then
            table.insert(recent, oldReason)
        end
    end
    options.recentReasons = recent
end

local function ADKP_QuickAdjust_UpdateActionLabels()
    local frame = ADKP_QuickAdjustFrame
    if not frame then return end
    local points = tonumber(ADKP_TrimText(frame.pointsEdit:GetText() or ""))
    if points and points > 0 then
        frame.addBtn:SetText("加分 +" .. tostring(points))
        frame.deductBtn:SetText("扣分 -" .. tostring(points))
    else
        frame.addBtn:SetText("加分")
        frame.deductBtn:SetText("扣分")
    end
end

local function ADKP_QuickAdjust_UpdatePointButtons()
    local frame = ADKP_QuickAdjustFrame
    if not frame or not frame.pointButtons then return end
    local options = ADKP_QuickAdjust_GetOptions()
    for i = 1, 4 do
        frame.pointButtons[i].pointValue = options.quickPoints[i]
        frame.pointButtons[i]:SetText(tostring(options.quickPoints[i]))
    end
end

local function ADKP_QuickAdjust_UnlockActions()
    local frame = ADKP_QuickAdjustFrame
    if not frame then return end
    frame.actionLocked = false
    frame.addBtn:Enable()
    frame.deductBtn:Enable()
    frame:SetScript("OnUpdate", nil)
end

local function ADKP_QuickAdjust_LockActions()
    local frame = ADKP_QuickAdjustFrame
    frame.actionLocked = true
    frame.actionUnlockAt = GetTime() + 0.6
    frame.addBtn:Disable()
    frame.deductBtn:Disable()
    frame:SetScript("OnUpdate", function()
        if GetTime() >= (this.actionUnlockAt or 0) then
            ADKP_QuickAdjust_UnlockActions()
        end
    end)
end

local function ADKP_QuickAdjust_Execute(isDeduction)
    local frame = ADKP_QuickAdjustFrame
    if not frame or frame.actionLocked then return end

    local playerName = ADKP_QuickAdjust_ResolveMember()
    if not playerName then return end
    local points = tonumber(ADKP_TrimText(frame.pointsEdit:GetText() or ""))
    if not points or points <= 0 then
        ADKP_Print("错误：请输入大于0的有效分值。")
        return
    end
    if ADKP_ROUND then points = ADKP_ROUND(points, 2) end
    if isDeduction then points = -points end

    local reason = ADKP_TrimText(frame.reasonEdit:GetText() or "")
    if reason == "" then reason = "分数调整" end
    local className = ADKP_GetPlayerClass(playerName) or "未知"
    if ADKP_NormalizeClassName then className = ADKP_NormalizeClassName(className) end

    ADKP_QuickAdjust_LockActions()
    local recordRef = ADKP_AddDKP(points, reason, "false", {{ name = playerName, class = className }})
    if not recordRef then
        ADKP_QuickAdjust_UnlockActions()
        return
    end
    if ADKP_AnnounceAwardSingle then
        ADKP_AnnounceAwardSingle(points, reason, playerName)
    end
    ADKP_QuickAdjust_AddRecentReason(reason)
    ADKP_QuickAdjust_SetMember(playerName)
    ADKP_Print("已为 " .. playerName .. (isDeduction and " 扣除 " or " 增加 ") .. tostring(math.abs(points)) .. " DKP，原因：" .. reason)
end

local function ADKP_QuickAdjust_ClassMenuSelect()
    ADKP_QuickAdjust_SetMember(this.value)
end

local function ADKP_QuickAdjust_ClassMenuInitialize()
    local level = UIDROPDOWNMENU_MENU_LEVEL or 1
    if level == 1 then
        local header = {}
        header.text = "按职业选择成员"
        header.isTitle = 1
        header.notCheckable = 1
        UIDropDownMenu_AddButton(header, level)
        for i = 1, table.getn(ADKP_QuickAdjustClassOrder) do
            local className = ADKP_QuickAdjustClassOrder[i]
            local hasPlayers = false
            for j = 1, table.getn(ADKP_QuickAdjustClassMenuPlayers) do
                if ADKP_QuickAdjustClassMenuPlayers[j].class == className then
                    hasPlayers = true
                    break
                end
            end
            if hasPlayers then
                local info = {}
                info.text = ADKP_GetClassColor(className) .. className .. "|r"
                info.value = className
                info.hasArrow = 1
                info.notCheckable = 1
                UIDropDownMenu_AddButton(info, level)
            end
        end
    elseif level == 2 then
        local className = UIDROPDOWNMENU_MENU_VALUE
        for i = 1, table.getn(ADKP_QuickAdjustClassMenuPlayers) do
            local player = ADKP_QuickAdjustClassMenuPlayers[i]
            if player.class == className then
                local info = {}
                info.text = ADKP_GetClassColor(player.class) .. player.name .. "|r"
                info.value = player.name
                info.func = ADKP_QuickAdjust_ClassMenuSelect
                info.notCheckable = 1
                UIDropDownMenu_AddButton(info, level)
            end
        end
    end
end

local function ADKP_QuickAdjust_ShowClassMenu()
    if ADKP_QuickAdjustFrame and ADKP_QuickAdjustFrame.suggestionFrame then
        ADKP_QuickAdjustFrame.suggestionFrame:Hide()
    end
    ADKP_QuickAdjustClassMenuPlayers = ADKP_QuickAdjust_GetPlayers("")
    if table.getn(ADKP_QuickAdjustClassMenuPlayers) == 0 then
        ADKP_Print("当前DKP清单中没有可选择的成员。")
        return
    end
    if not ADKP_QuickAdjustClassMenu then
        ADKP_QuickAdjustClassMenu = CreateFrame("Frame", "ADKP_QuickAdjustClassMenu", UIParent, "UIDropDownMenuTemplate")
    end
    UIDropDownMenu_Initialize(ADKP_QuickAdjustClassMenu, ADKP_QuickAdjust_ClassMenuInitialize, "MENU")
    ToggleDropDownMenu(1, nil, ADKP_QuickAdjustClassMenu, "ADKP_QuickAdjustMemberDropButton", 0, 0)
end

local function ADKP_QuickAdjust_RecentMenuSelect()
    if ADKP_QuickAdjustFrame and ADKP_QuickAdjustFrame.reasonEdit then
        ADKP_QuickAdjustFrame.reasonEdit:SetText(this.value or "")
    end
end

local function ADKP_QuickAdjust_RecentMenuInitialize()
    local options = ADKP_QuickAdjust_GetOptions()
    if table.getn(options.recentReasons) == 0 then
        local info = {}
        info.text = "暂无最近原因"
        info.disabled = 1
        info.notCheckable = 1
        UIDropDownMenu_AddButton(info)
        return
    end
    for i = 1, math.min(6, table.getn(options.recentReasons)) do
        local info = {}
        info.text = options.recentReasons[i]
        info.value = options.recentReasons[i]
        info.func = ADKP_QuickAdjust_RecentMenuSelect
        info.notCheckable = 1
        UIDropDownMenu_AddButton(info)
    end
end

local function ADKP_QuickAdjust_ShowRecentMenu()
    local frame = ADKP_QuickAdjustFrame
    if frame.suggestionFrame then frame.suggestionFrame:Hide() end
    UIDropDownMenu_Initialize(frame.recentMenu, ADKP_QuickAdjust_RecentMenuInitialize, "MENU")
    ToggleDropDownMenu(1, nil, frame.recentMenu, "ADKP_QuickAdjustRecentButton", 0, 0)
end

local function ADKP_QuickAdjust_CreateFrame()
    if ADKP_QuickAdjustFrame then return ADKP_QuickAdjustFrame end
    local frame = CreateFrame("Frame", "ADKP_QuickAdjustFrame", UIParent)
    frame:SetWidth(300)
    frame:SetHeight(158)
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function() this:StartMoving() end)
    frame:SetScript("OnDragStop", function()
        this:StopMovingOrSizing()
        local left = this:GetLeft()
        local top = this:GetTop()
        if left and top then
            this:ClearAllPoints()
            this:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
            ADKP_QuickAdjust_GetOptions().position = { x = left, y = top }
            if ADKP_SaveToDisk then ADKP_SaveToDisk() end
        end
    end)
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    frame:SetBackdropColor(0, 0, 0, 0.94)

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.title:SetPoint("TOP", frame, "TOP", 0, -13)
    frame.title:SetText("快速奖惩")

    local memberLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    memberLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -42)
    memberLabel:SetText("成员")
    frame.memberEdit = CreateFrame("EditBox", "ADKP_QuickAdjustMemberEdit", frame, "InputBoxTemplate")
    frame.memberEdit:SetWidth(100)
    frame.memberEdit:SetHeight(22)
    frame.memberEdit:SetPoint("LEFT", memberLabel, "RIGHT", 12, 0)
    frame.memberEdit:SetAutoFocus(false)
    frame.memberEdit:SetFontObject("ChatFontNormal")
    frame.memberEdit:SetTextInsets(4, 4, 0, 0)

    frame.memberDropBtn = CreateFrame("Button", "ADKP_QuickAdjustMemberDropButton", frame, "UIPanelButtonTemplate")
    frame.memberDropBtn:SetWidth(24)
    frame.memberDropBtn:SetHeight(21)
    frame.memberDropBtn:SetPoint("LEFT", frame.memberEdit, "RIGHT", 4, 0)
    frame.memberDropBtn:SetText("▼")
    frame.memberDropBtn:SetScript("OnClick", ADKP_QuickAdjust_ShowClassMenu)

    frame.followCheck = CreateFrame("CheckButton", "ADKP_QuickAdjustFollowTarget", frame, "UICheckButtonTemplate")
    frame.followCheck:SetWidth(22)
    frame.followCheck:SetHeight(22)
    frame.followCheck:SetPoint("LEFT", frame.memberDropBtn, "RIGHT", 8, 0)
    frame.followText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.followText:SetPoint("LEFT", frame.followCheck, "RIGHT", 0, 1)
    frame.followText:SetText("跟随目标")
    frame.followCheck:SetScript("OnClick", function()
        local options = ADKP_QuickAdjust_GetOptions()
        options.followTarget = this:GetChecked() and true or false
        if options.followTarget then
            local targetName = ADKP_QuickAdjust_GetTargetName()
            if targetName then ADKP_QuickAdjust_SetMember(targetName) end
        end
        if ADKP_SaveToDisk then ADKP_SaveToDisk() end
    end)

    local pointsLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    pointsLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -71)
    pointsLabel:SetText("分值")
    frame.pointsEdit = CreateFrame("EditBox", "ADKP_QuickAdjustPointsEdit", frame, "InputBoxTemplate")
    frame.pointsEdit:SetWidth(52)
    frame.pointsEdit:SetHeight(22)
    frame.pointsEdit:SetPoint("LEFT", pointsLabel, "RIGHT", 12, 0)
    frame.pointsEdit:SetAutoFocus(false)
    frame.pointsEdit:SetFontObject("ChatFontNormal")
    frame.pointsEdit:SetTextInsets(4, 4, 0, 0)
    frame.pointsEdit:SetScript("OnTextChanged", ADKP_QuickAdjust_UpdateActionLabels)
    frame.pointsEdit:SetScript("OnEscapePressed", function() this:ClearFocus() end)
    frame.pointsEdit:SetScript("OnEditFocusGained", function()
        if frame.suggestionFrame then frame.suggestionFrame:Hide() end
    end)

    frame.pointButtons = {}
    for i = 1, 4 do
        local button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        button:SetWidth(40)
        button:SetHeight(21)
        button:SetPoint("LEFT", frame.pointsEdit, "RIGHT", 6 + ((i - 1) * 44), 0)
        button:SetScript("OnClick", function()
            frame.pointsEdit:SetText(tostring(this.pointValue))
            frame.pointsEdit:ClearFocus()
        end)
        frame.pointButtons[i] = button
    end

    local reasonLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    reasonLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -100)
    reasonLabel:SetText("原因")
    frame.reasonEdit = CreateFrame("EditBox", "ADKP_QuickAdjustReasonEdit", frame, "InputBoxTemplate")
    frame.reasonEdit:SetWidth(131)
    frame.reasonEdit:SetHeight(22)
    frame.reasonEdit:SetPoint("LEFT", reasonLabel, "RIGHT", 12, 0)
    frame.reasonEdit:SetAutoFocus(false)
    frame.reasonEdit:SetFontObject("ChatFontNormal")
    frame.reasonEdit:SetTextInsets(4, 4, 0, 0)
    frame.reasonEdit:SetScript("OnEscapePressed", function() this:ClearFocus() end)
    frame.reasonEdit:SetScript("OnEditFocusGained", function()
        if frame.suggestionFrame then frame.suggestionFrame:Hide() end
    end)

    frame.recentBtn = CreateFrame("Button", "ADKP_QuickAdjustRecentButton", frame, "UIPanelButtonTemplate")
    frame.recentBtn:SetWidth(82)
    frame.recentBtn:SetHeight(21)
    frame.recentBtn:SetPoint("LEFT", frame.reasonEdit, "RIGHT", 6, 0)
    frame.recentBtn:SetText("最近使用")
    frame.recentBtn:SetScript("OnClick", ADKP_QuickAdjust_ShowRecentMenu)
    frame.recentMenu = CreateFrame("Frame", "ADKP_QuickAdjustRecentMenu", UIParent, "UIDropDownMenuTemplate")

    frame.addBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.addBtn:SetWidth(88)
    frame.addBtn:SetHeight(23)
    frame.addBtn:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 14, 14)
    frame.addBtn:SetScript("OnClick", function() ADKP_QuickAdjust_Execute(false) end)
    frame.deductBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.deductBtn:SetWidth(88)
    frame.deductBtn:SetHeight(23)
    frame.deductBtn:SetPoint("LEFT", frame.addBtn, "RIGHT", 8, 0)
    frame.deductBtn:SetScript("OnClick", function() ADKP_QuickAdjust_Execute(true) end)
    frame.closeBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.closeBtn:SetWidth(62)
    frame.closeBtn:SetHeight(23)
    frame.closeBtn:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -14, 14)
    frame.closeBtn:SetText("关闭")
    frame.closeBtn:SetScript("OnClick", function() frame:Hide() end)

    frame.suggestionFrame = CreateFrame("Frame", nil, frame)
    frame.suggestionFrame:SetWidth(100)
    frame.suggestionFrame:SetHeight(28)
    frame.suggestionFrame:SetPoint("TOPLEFT", frame.memberEdit, "BOTTOMLEFT", 0, -2)
    frame.suggestionFrame:SetFrameLevel(frame:GetFrameLevel() + 20)
    frame.suggestionFrame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    frame.suggestionFrame:SetBackdropColor(0, 0, 0, 0.96)
    frame.suggestionRows = {}
    for i = 1, 6 do
        local row = CreateFrame("Button", nil, frame.suggestionFrame)
        row:SetWidth(90)
        row:SetHeight(20)
        row:SetPoint("TOPLEFT", frame.suggestionFrame, "TOPLEFT", 5, -4 - ((i - 1) * 20))
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
        row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.text:SetPoint("LEFT", row, "LEFT", 4, 0)
        row.text:SetJustifyH("LEFT")
        row:SetScript("OnClick", function()
            ADKP_QuickAdjust_SetMember(this.playerName)
            frame.memberEdit:ClearFocus()
        end)
        frame.suggestionRows[i] = row
    end
    frame.suggestionFrame:Hide()

    frame.memberEdit:SetScript("OnEditFocusGained", function()
        frame.memberEditing = true
        ADKP_QuickAdjust_UpdateSuggestions()
    end)
    frame.memberEdit:SetScript("OnEditFocusLost", function() frame.memberEditing = false end)
    frame.memberEdit:SetScript("OnTextChanged", function()
        if not frame.suppressMemberChange then ADKP_QuickAdjust_UpdateSuggestions() end
    end)
    frame.memberEdit:SetScript("OnEnterPressed", function()
        local playerName = ADKP_QuickAdjust_ResolveMember()
        if playerName then ADKP_QuickAdjust_SetMember(playerName) end
        this:ClearFocus()
    end)
    frame.memberEdit:SetScript("OnEscapePressed", function()
        frame.suggestionFrame:Hide()
        this:ClearFocus()
    end)

    frame:RegisterEvent("PLAYER_TARGET_CHANGED")
    frame:SetScript("OnEvent", function()
        if event ~= "PLAYER_TARGET_CHANGED" or not this:IsShown() then return end
        local options = ADKP_QuickAdjust_GetOptions()
        if not options.followTarget then return end
        local targetName = ADKP_QuickAdjust_GetTargetName()
        if targetName then ADKP_QuickAdjust_SetMember(targetName) end
    end)
    frame:SetScript("OnShow", function()
        local options = ADKP_QuickAdjust_GetOptions()
        this.followCheck:SetChecked(options.followTarget and 1 or nil)
        ADKP_QuickAdjust_UpdatePointButtons()
        ADKP_QuickAdjust_UpdateActionLabels()
        local targetName = ADKP_QuickAdjust_GetTargetName()
        if targetName then ADKP_QuickAdjust_SetMember(targetName) end
    end)
    frame:SetScript("OnHide", function()
        frame.memberEditing = false
        frame.suggestionFrame:Hide()
        if CloseDropDownMenus then CloseDropDownMenus() end
        if frame.actionLocked then ADKP_QuickAdjust_UnlockActions() end
    end)

    frame.pointsEdit:SetText("5")
    ADKP_QuickAdjustFrame = frame
    ADKP_QuickAdjust_UpdatePointButtons()
    ADKP_QuickAdjust_UpdateActionLabels()
    frame:Hide()
    return frame
end

local function ADKP_QuickAdjust_ShowPointSettings()
    if ADKP_QuickFloatSettingsFrame then ADKP_QuickFloatSettingsFrame:Hide() end
    if not ADKP_QuickAdjustPointSettingsFrame then
        local frame = CreateFrame("Frame", "ADKP_QuickAdjustPointSettingsFrame", UIParent)
        frame:SetWidth(280)
        frame:SetHeight(112)
        frame:SetFrameStrata("DIALOG")
        frame:SetClampedToScreen(true)
        frame:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 }
        })
        frame:SetBackdropColor(0, 0, 0, 0.94)
        frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        frame.title:SetPoint("TOP", frame, "TOP", 0, -13)
        frame.title:SetText("常用分值设置")
        frame.edits = {}
        for i = 1, 4 do
            local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            label:SetPoint("TOPLEFT", frame, "TOPLEFT", 20 + ((i - 1) * 62), -39)
            label:SetText("常用" .. i)
            local edit = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
            edit:SetWidth(48)
            edit:SetHeight(21)
            edit:SetPoint("TOPLEFT", frame, "TOPLEFT", 18 + ((i - 1) * 62), -54)
            edit:SetAutoFocus(false)
            edit:SetFontObject("ChatFontNormal")
            edit:SetTextInsets(4, 4, 0, 0)
            edit:SetScript("OnEscapePressed", function() this:ClearFocus() end)
            frame.edits[i] = edit
        end
        frame.saveBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        frame.saveBtn:SetWidth(90)
        frame.saveBtn:SetHeight(22)
        frame.saveBtn:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 34, 12)
        frame.saveBtn:SetText("保存")
        frame.cancelBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        frame.cancelBtn:SetWidth(90)
        frame.cancelBtn:SetHeight(22)
        frame.cancelBtn:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -34, 12)
        frame.cancelBtn:SetText("取消")
        frame.cancelBtn:SetScript("OnClick", function() frame:Hide() end)
        frame.saveBtn:SetScript("OnClick", function()
            local values = {}
            for i = 1, 4 do
                values[i] = tonumber(ADKP_TrimText(frame.edits[i]:GetText() or ""))
                if not values[i] or values[i] <= 0 then
                    ADKP_Print("错误：四个常用分值都必须大于0。")
                    return
                end
                if ADKP_ROUND then values[i] = ADKP_ROUND(values[i], 2) end
            end
            ADKP_QuickAdjust_GetOptions().quickPoints = values
            ADKP_QuickAdjust_UpdatePointButtons()
            if ADKP_SaveToDisk then ADKP_SaveToDisk() end
            frame:Hide()
        end)
        frame:Hide()
        ADKP_QuickAdjustPointSettingsFrame = frame
    end

    local frame = ADKP_QuickAdjustPointSettingsFrame
    if frame:IsShown() then
        frame:Hide()
        return
    end
    local options = ADKP_QuickAdjust_GetOptions()
    for i = 1, 4 do frame.edits[i]:SetText(tostring(options.quickPoints[i])) end
    frame:ClearAllPoints()
    if ADKP_QuickFloatFrame then
        frame:SetPoint("TOPLEFT", ADKP_QuickFloatFrame, "BOTTOMLEFT", 0, -4)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
    frame:Show()
end

local function ADKP_QuickAdjust_Toggle()
    local frame = ADKP_QuickAdjust_CreateFrame()
    if frame:IsShown() then
        frame:Hide()
        return
    end
    frame:ClearAllPoints()
    local position = ADKP_QuickAdjust_GetOptions().position
    if position and position.x and position.y then
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", position.x, position.y)
    elseif ADKP_QuickFloatFrame then
        frame:SetPoint("TOPLEFT", ADKP_QuickFloatFrame, "TOPRIGHT", 4, 0)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
    if ADKP_QuickAdjustPointSettingsFrame then ADKP_QuickAdjustPointSettingsFrame:Hide() end
    if ADKP_QuickFloatSettingsFrame then ADKP_QuickFloatSettingsFrame:Hide() end
    frame:Show()
end

local function ADKP_QuickFloat_OnAction(key, mouseButton)
    if key == "adjust" then
        if mouseButton == "RightButton" then
            ADKP_QuickAdjust_ShowPointSettings()
        else
            ADKP_QuickAdjust_Toggle()
        end
        return
    end
    if mouseButton == "RightButton" then
        ADKP_QuickFloat_ShowSettings(key)
        return
    end

    local v1, v2, reason = ADKP_QuickFloat_GetSettings(key)
    if key == "rally" then
        local raidPoints = v1
        local subPoints = v2
        if type(raidPoints) ~= "number" or type(subPoints) ~= "number" then
            ADKP_Print("错误：请先右键设置【集】的默认分数。")
            return
        end
        ADKP_QuickFloat_ExecuteRaidSub("rally", raidPoints, subPoints, "集合分")
        return
    end

    if key == "dismiss" then
        local raidPoints = v1
        local subPoints = v2
        if type(raidPoints) ~= "number" or type(subPoints) ~= "number" then
            ADKP_Print("错误：请先右键设置【散】的默认分数。")
            return
        end
        ADKP_QuickFloat_ExecuteRaidSub("dismiss", raidPoints, subPoints, "解散分")
        return
    end

    if key == "kill" then
        local raidPoints = v1
        local subPoints = v2
        if type(raidPoints) ~= "number" or type(subPoints) ~= "number" then
            ADKP_Print("错误：请先右键设置【杀】的默认分数。")
            return
        end
        local source = ADKP_TrimText(reason or "")
        if source == "" then
            local targetName = UnitName("target")
            if not targetName or targetName == "" then
                ADKP_Print("错误：请先选中目标，或右键设置击杀原因。")
                return
            end
            source = targetName
        end
        local reason = "击杀-" .. source
        ADKP_QuickFloat_ExecuteRaidSub("kill", raidPoints, subPoints, reason)
        return
    end

end

-- 全局封装：供主界面按钮 OnClick 处理左/右键（左键执行，右键设置分值）
function ADKP_QuickFloatAction_Mouse(key, button)
    ADKP_QuickFloat_OnAction(key, button or "LeftButton")
end

-- 主界面按钮的简洁 tooltip（标题直接用动作名，不含"快捷浮窗"前缀，自带使用说明）
function ADKP_QuickFloat_ShowMainTooltip(key)
    if not GameTooltip then return end
    local v1, v2, reason = ADKP_QuickFloat_GetSettings(key)
    GameTooltip:SetText(ADKP_QuickFloat_GetActionLabel(key), 1, 1, 1)
    local raidPoints, subPoints = v1, v2
    if type(raidPoints) == "number" and type(subPoints) == "number" then
        GameTooltip:AddLine("主队:" .. tostring(raidPoints) .. "  替补:" .. tostring(subPoints), 0.8, 0.8, 0.8)
    else
        GameTooltip:AddLine("未设置分值（右键设置）", 0.8, 0.8, 0.8)
    end
    GameTooltip:AddLine("左键:执行加分  右键:设置分值", 0.6, 0.6, 0.6)
end

-- 显示悬浮窗帮助说明（点击右上角“?”按钮触发）
local function ADKP_QuickFloat_ShowHelp()
    if ADKP_QuickFloatHelpFrame then
        if ADKP_QuickFloatHelpFrame:IsShown() then
            ADKP_QuickFloatHelpFrame:Hide()
        else
            ADKP_QuickFloatHelpFrame:Show()
        end
        return
    end

    local f = CreateFrame("Frame", "ADKP_QuickFloatHelpFrame", UIParent)
    f:SetWidth(460)
    f:SetHeight(310)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    f:SetFrameStrata("DIALOG")
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function() this:StartMoving() end)
    f:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
    f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    f:SetBackdropColor(0, 0, 0, 0.9)

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.title:SetPoint("TOP", f, "TOP", 0, -18)
    f.title:SetText("悬浮窗快捷键说明")
    f.title:SetTextColor(1, 0.82, 0)

    f.body = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.body:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -52)
    f.body:SetPoint("RIGHT", f, "RIGHT", -22, 0)
    f.body:SetHeight(210)
    f.body:SetJustifyH("LEFT")
    f.body:SetJustifyV("TOP")
    f.body:SetText(
        "集 ：手动为主团、替补团分配集合分；右键可自定义分值。\n\n" ..
        "散 ：手动为主团、替补团分配解散分；右键可自定义分值。\n\n" ..
        "杀 ：手动录入 Boss 击杀得分；右键预设分值，使用前需选中已击杀 Boss 为目标。\n\n" ..
        "奖惩 ：左键打开快速奖惩，可搜索成员、填写分值和原因后连续加分或扣分；右键设置四个常用分值。\n\n" ..
        "拍 ：灰色时左键设置一键拍卖品质；打开拾取列表后变为红色，左键将符合品质的物品加入竞拍队列。右键打开竞拍界面。"
    )
    f.body:SetTextColor(1, 1, 1)

    local close = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    close:SetWidth(70)
    close:SetHeight(22)
    close:SetPoint("BOTTOM", f, "BOTTOM", 0, 16)
    close:SetText("关闭")
    close:SetScript("OnClick", function() f:Hide() end)

    ADKP_QuickFloatHelpFrame = f
    f:Show()
end

local function ADKP_QuickFloat_GetFrame()
    if ADKP_QuickFloatFrame then
        return ADKP_QuickFloatFrame
    end

    ADKP_QuickFloat_InitOptions()

    local f = CreateFrame("Frame", "ADKP_QuickFloatFrame", UIParent)
    f:SetWidth(136)
    f:SetHeight(70)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function() this:StartMoving() end)
    f:SetScript("OnDragStop", function()
        this:StopMovingOrSizing()
        if not WebDKP_Options then
            WebDKP_Options = {}
        end
        if not WebDKP_Options["QuickFloatPos"] then
            WebDKP_Options["QuickFloatPos"] = {}
        end
        WebDKP_Options["QuickFloatPos"].x = this:GetLeft()
        WebDKP_Options["QuickFloatPos"].y = this:GetTop()
    end)
    f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    f:SetBackdropColor(0, 0, 0, 0.85)

    local pos = WebDKP_Options and WebDKP_Options["QuickFloatPos"]
    if pos and pos.x and pos.y then
        f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", pos.x, pos.y)
    else
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 140)
    end

    -- 原有两排按钮固定在底部 70 高度区域，顶部扩展记录行时不随外框中心移动。
    local buttonArea = CreateFrame("Frame", nil, f)
    buttonArea:SetWidth(136)
    buttonArea:SetHeight(70)
    buttonArea:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
    f.buttonArea = buttonArea

    local keys = {"rally", "dismiss", "kill", "adjust"}
    -- 2×3 布局：上排 集/散/杀，下排 奖惩/拍/?
    local positions = {
        { x = 10, y =  15 },  -- 集 (上排左)
        { x = 50, y =  15 },  -- 散 (上排中)
        { x = 90, y =  15 },  -- 杀 (上排右)
        { x = 10, y = -15 },  -- 奖惩 (下排左)
    }
    f.buttons = {}
    for i = 1, 4 do
        local key = keys[i]
        local p = positions[i]
        local btn = CreateFrame("Button", nil, buttonArea, "UIPanelButtonTemplate")
        btn:SetWidth(36)
        btn:SetHeight(26)
        btn:SetPoint("LEFT", buttonArea, "LEFT", p.x, p.y)
        btn:SetText(ADKP_QuickFloat_GetActionLabel(key))
        btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        btn:SetScript("OnClick", function()
            ADKP_QuickFloat_OnAction(key, arg1)
        end)
        btn:SetScript("OnEnter", function()
            if GameTooltip then
                GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
                ADKP_QuickFloat_UpdateTooltip(key)
                if key ~= "adjust" then
                    GameTooltip:AddLine("左键:执行  右键:设置分值", 0.6, 0.6, 0.6)
                end
                GameTooltip:Show()
            end
        end)
        btn:SetScript("OnLeave", function()
            if GameTooltip then
                GameTooltip:Hide()
            end
        end)
        f.buttons[key] = btn
    end

    -- 「拍」按钮：红色时按品质批量竞拍，灰色时左键设置品质
    local bidBtn = CreateFrame("Button", "ADKP_QuickFloatBidBtn", buttonArea, "UIPanelButtonTemplate")
    bidBtn:SetWidth(36)
    bidBtn:SetHeight(26)
    bidBtn:SetPoint("LEFT", buttonArea, "LEFT", 50, -15)
    bidBtn:SetText("拍")
    bidBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    bidBtn:SetNormalTexture("Interface\\Buttons\\UI-Panel-Button-Disabled")
    local bidText = getglobal("ADKP_QuickFloatBidBtnText")
    if bidText then bidText:SetTextColor(1, 1, 1) end
    bidBtn:SetScript("OnClick", function()
        if arg1 == "RightButton" then
            ADKP_Bid_ToggleUI()
        elseif GetNumLootItems and GetNumLootItems() > 0 then
            ADKP_StartBossLootBid()
		else
			ADKP_QuickBid_ShowQualitySettings()
        end
    end)
	bidBtn:SetScript("OnEnter", function()
		if not GameTooltip then return end
		GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
		GameTooltip:SetText("一键拍卖当前拾取窗口所有物品", 1, 1, 1)
		GameTooltip:AddLine("左键（灰）：设置一键拍卖物品品质", 0.8, 0.8, 0.8)
		GameTooltip:AddLine("左键（红）：按预设品质一键拍卖", 0.8, 0.8, 0.8)
		GameTooltip:AddLine("右键：打开竞拍界面", 0.8, 0.8, 0.8)
		GameTooltip:Show()
	end)
	bidBtn:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    f.bidBtn = bidBtn

    -- 使用原生动作按钮光晕，避免实色粗边的生硬轮廓。
    local bidGlow = CreateFrame("Frame", nil, bidBtn)
    bidGlow:SetAllPoints(bidBtn)
    bidGlow:SetFrameLevel(bidBtn:GetFrameLevel() + 1)
    bidGlow:EnableMouse(false)
    local glowTexture = bidGlow:CreateTexture(nil, "OVERLAY")
    glowTexture:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    glowTexture:SetBlendMode("ADD")
    glowTexture:SetVertexColor(1, 0.72, 0.18)
    glowTexture:SetWidth(64)
    glowTexture:SetHeight(46)
    glowTexture:SetPoint("CENTER", bidBtn, "CENTER", 0, 0)
    bidGlow:SetScript("OnShow", function()
        this.elapsed = 0
        this:SetAlpha(1)
    end)
    bidGlow:SetScript("OnUpdate", function()
        this.elapsed = (this.elapsed or 0) + (tonumber(arg1) or 0)
        if this.elapsed >= 1.2 then this.elapsed = 0 end
        this:SetAlpha(0.75 + 0.25 * math.abs(1 - this.elapsed / 0.6))
    end)
    bidGlow:Hide()
    bidBtn.bidGlow = bidGlow

    -- 提示独立于呼吸动画，文字保持常亮，且不拦截鼠标点击。
    local bidNotice = CreateFrame("Frame", nil, f)
    bidNotice:SetWidth(190)
    bidNotice:SetHeight(24)
    bidNotice:SetPoint("TOP", bidBtn, "BOTTOM", 0, -10)
    bidNotice:EnableMouse(false)
    bidNotice:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground" })
    bidNotice:SetBackdropColor(0, 0, 0, 0.8)
    bidNotice.text = bidNotice:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    bidNotice.text:SetPoint("CENTER", bidNotice, "CENTER", 0, 0)
    bidNotice.text:SetWidth(182)
    bidNotice.text:SetText("竞拍未结束，右键返回")
    bidNotice.text:SetTextColor(1, 0.82, 0.25)
    bidNotice.text:SetShadowColor(0, 0, 0, 1)
    bidNotice.text:SetShadowOffset(1, -1)
    bidNotice:Hide()
    bidBtn.bidNotice = bidNotice

    -- 帮助按钮（下排右）
    local helpBtn = CreateFrame("Button", "ADKP_QuickFloatHelpBtn", buttonArea, "UIPanelButtonTemplate")
    helpBtn:SetWidth(36)
    helpBtn:SetHeight(26)
    helpBtn:SetPoint("LEFT", buttonArea, "LEFT", 90, -15)
    helpBtn:SetText("?")
    helpBtn:SetScript("OnClick", function() ADKP_QuickFloat_ShowHelp() end)
    helpBtn:SetScript("OnEnter", function()
        if GameTooltip then
            GameTooltip:SetOwner(this, "ANCHOR_LEFT")
            GameTooltip:SetText("帮助", 1, 1, 1)
            GameTooltip:Show()
        end
    end)
    helpBtn:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)

    -- 自动加分记录行（BossAutoAward 开启时显示在顶部，点击向上展开全部记录）
    local logRow = CreateFrame("Button", nil, f)
    logRow:SetWidth(120)
    logRow:SetHeight(16)
    logRow:SetPoint("TOP", f, "TOP", 0, -6)
    logRow.text = logRow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    logRow.text:SetPoint("CENTER", logRow, "CENTER", 0, 0)
    logRow.text:SetText("自动加分: 暂无")
    logRow:SetScript("OnClick", function()
        ADKP_BossAutoLog_TogglePanel()
    end)
    logRow:SetScript("OnEnter", function()
        if GameTooltip then
            GameTooltip:SetOwner(this, "ANCHOR_BOTTOM")
            GameTooltip:SetText("Boss 全自动加分记录", 1, 1, 1)
            GameTooltip:AddLine("点击查看全部自动加分记录", 0.8, 0.8, 0.8)
            GameTooltip:AddLine("分值在 Boss 名单页配置", 0.6, 0.6, 0.6)
            GameTooltip:Show()
        end
    end)
    logRow:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    f.logRow = logRow

    f:Hide()
    ADKP_QuickFloatFrame = f
    ADKP_QuickFloat_UpdateBidGlow()
    return f
end

-- ================================
-- 悬浮窗自动加分记录行 / 记录面板
-- ================================
function ADKP_QuickFloat_ApplyAutoMode(f)
    if not f then return end
    local autoOn = WebDKP_Options and WebDKP_Options["BossAutoAward"] and true or false
    if autoOn then
        f:SetHeight(92)
        if f.logRow then
            f.logRow:Show()
            ADKP_QuickFloat_UpdateAutoLogRow()
        end
    else
        f:SetHeight(70)
        if f.logRow then
            f.logRow:Hide()
        end
        ADKP_BossAutoLog_HidePanel()
    end
end

function ADKP_QuickFloat_UpdateAutoLogRow()
    local f = ADKP_QuickFloatFrame
    if not f or not f.logRow then return end
    local log = ADKP_GetBossAutoAwardRecords()
    local n = table.getn(log)
    if n == 0 then
        f.logRow.text:SetText("自动加分: 暂无")
        f.logRow.text:SetTextColor(0.6, 0.6, 0.6)
    else
        local e = log[n]
        local name = ADKP_TruncateUtf8Glyphs(e.boss or "?", 6)
        f.logRow.text:SetText(name .. " 主" .. tostring(e.raid) .. "/替" .. tostring(e.sub))
        f.logRow.text:SetTextColor(1, 0.82, 0)
    end
    -- 删除最后一条日志时也要刷新已展开的面板，隐藏旧行并显示“暂无记录”。
    if ADKP_BossAutoLogFrame and ADKP_BossAutoLogFrame:IsShown() then
        ADKP_BossAutoLog_RefreshPanel(log)
    end
end

function ADKP_BossAutoLog_TogglePanel()
    if ADKP_BossAutoLogFrame then
        if ADKP_BossAutoLogFrame:IsShown() then
            ADKP_BossAutoLogFrame:Hide()
            return
        end
    end
    ADKP_BossAutoLog_ShowPanel()
end

function ADKP_BossAutoLog_HidePanel()
    if ADKP_BossAutoLogFrame then
        ADKP_BossAutoLogFrame:Hide()
    end
end

function ADKP_BossAutoLog_ShowPanel()
    local qf = ADKP_QuickFloat_GetFrame()
    local f = ADKP_BossAutoLogFrame
    if not f then
        f = CreateFrame("Frame", "ADKP_BossAutoLogFrame", UIParent)
        f:SetWidth(320)
        f:SetHeight(176)
        f:SetFrameStrata("DIALOG")
        f:SetClampedToScreen(true)
        f:EnableMouse(true)
        f:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 }
        })
        f:SetBackdropColor(0, 0, 0, 0.9)

        f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        f.title:SetPoint("TOP", 0, -10)
        f.title:SetText("自动加分记录")

        f.closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        f.closeBtn:SetPoint("TOPRIGHT", -4, -4)

        f.clearBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        f.clearBtn:SetWidth(70)
        f.clearBtn:SetHeight(18)
        f.clearBtn:SetPoint("TOPRIGHT", -28, -5)
        f.clearBtn:SetText("清空显示")
        f.clearBtn:SetScript("OnClick", function()
            ADKP_ClearBossAutoAwardRecords()
        end)
        f.clearBtn:SetScript("OnEnter", function()
            if GameTooltip then
                GameTooltip:SetOwner(this, "ANCHOR_BOTTOM")
                GameTooltip:SetText("清空当前团的自动加分显示", 1, 1, 1)
                GameTooltip:AddLine("实际 DKP 日志和分数保持不变", 0.8, 0.8, 0.8)
                GameTooltip:Show()
            end
        end)
        f.clearBtn:SetScript("OnLeave", function()
            if GameTooltip then GameTooltip:Hide() end
        end)

        f.scroll = CreateFrame("ScrollFrame", "ADKP_BossAutoLogScroll", f, "UIPanelScrollFrameTemplate")
        f.scroll:SetPoint("TOPLEFT", 8, -26)
        f.scroll:SetPoint("BOTTOMRIGHT", -30, 8)
        f.child = CreateFrame("Frame", nil, f.scroll)
        f.child:SetWidth(275)
        f.child:SetHeight(1)
        f.scroll:SetScrollChild(f.child)
        f.rows = {}

        ADKP_BossAutoLogFrame = f
    end
    -- 锚在悬浮窗正上方展开
    f:ClearAllPoints()
    f:SetPoint("BOTTOMLEFT", qf, "TOPLEFT", 0, 6)
    ADKP_BossAutoLog_RefreshPanel()
    f:Show()
end

function ADKP_BossAutoLog_RefreshPanel(records)
    local f = ADKP_BossAutoLogFrame
    if not f then return end
    local log = records or ADKP_GetBossAutoAwardRecords()
    local n = table.getn(log)
    local rowH = 18
    local function formatPoints(value)
        local points = tonumber(value) or 0
        if points >= 0 then return "+" .. tostring(points) end
        return tostring(points)
    end
    f.child:SetHeight(math.max(n, 1) * rowH)
    if n == 0 then f.scroll:SetVerticalScroll(0) end
    if f.scroll.UpdateScrollChildRect then
        f.scroll:UpdateScrollChildRect()
    end
    for i = 1, n do
        local e = log[n - i + 1] -- 最新在最上面
        local row = f.rows[i]
        if not row then
            row = f.child:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row:SetPoint("TOPLEFT", 4, -((i - 1) * rowH + 2))
            f.rows[i] = row
        end
        local dt = tostring(e.t or "")
        local short = string.sub(dt, 6, 16) -- "YYYY-MM-DD HH:MM:SS" -> "MM-DD HH:MM"
        local subTxt
        if e.ab then
            subTxt = " 替补未同步"
        else
            subTxt = " 替" .. formatPoints(e.sub) .. "(" .. tostring(e.sc or 0) .. "人)"
        end
        local name = ADKP_TruncateUtf8Glyphs(e.boss or "?", 8)
        row:SetText(short .. " " .. name .. " 主" .. formatPoints(e.raid) .. "(" .. tostring(e.rc or 0) .. "人)" .. subTxt)
        row:Show()
    end
    for i = n + 1, table.getn(f.rows) do
        f.rows[i]:Hide()
    end
    if n == 0 and not f.emptyRow then
        f.emptyRow = f.child:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        f.emptyRow:SetPoint("TOPLEFT", 4, -2)
        f.emptyRow:SetTextColor(0.6, 0.6, 0.6)
        f.emptyRow:SetText("暂无记录")
    end
    if f.emptyRow then
        if n == 0 then f.emptyRow:Show() else f.emptyRow:Hide() end
    end
end

function ADKP_QuickFloat_UpdateVisibility()
    ADKP_QuickFloat_InitOptions()
    local enabled = WebDKP_Options and WebDKP_Options["QuickFloatEnabled"]
    -- 插件总开关：禁用时强制隐藏悬浮窗
    if ADKP_IsAddonDisabled() then
        enabled = false
    end
    local inRaid = (GetNumRaidMembers and GetNumRaidMembers() or 0) > 0
    if enabled and inRaid then
        local f = ADKP_QuickFloat_GetFrame()
        ADKP_QuickFloat_ApplyAutoMode(f)
        f:Show()
        -- 显示时根据当前拾取状态重设「拍」按钮颜色（避免初始/误触导致颜色错误）
        ADKP_UpdateQuickFloatBidBtn(GetNumLootItems and GetNumLootItems() > 0)
    else
        if ADKP_QuickFloatFrame then
            ADKP_QuickFloatFrame:Hide()
        end
        ADKP_BossAutoLog_HidePanel()
        if ADKP_QuickAdjustFrame then ADKP_QuickAdjustFrame:Hide() end
        if ADKP_QuickAdjustPointSettingsFrame then ADKP_QuickAdjustPointSettingsFrame:Hide() end
    end
end

-- 击杀弹窗的替补加分按钮调用此函数


-- 搜索替补队员事件处理函数
function ADKP_SearchSubMembers_Event()
    local captain = ""
    if ADKP_SubAwardData then
        captain = ADKP_SubAwardData.captain or ""
    end
    
	-- 检查是否输入了替补队长名称
    if captain == "" then
        ADKP_Print("请输入替补队长名称")
        return
    end
    
	-- 初始化ADKP_PendingSubMembers（如果不存在）
    if not ADKP_PendingSubMembers then
        ADKP_PendingSubMembers = {}
    end

	-- 清空之前的替补队员数据（精确键与小写键都清，避免残留旧名单）
    ADKP_PendingSubMembers[captain] = {}
    ADKP_PendingSubMembers[string.lower(captain)] = nil

	-- 确保ADKP_SubAwardData存在
    if not ADKP_SubAwardData then
        ADKP_SubAwardData = {}
    end

	-- 设置当前替补队长
    ADKP_SubAwardData.captain = captain

	-- 重置同步状态（人数校验、完成标志、响应标志等）
    ADKP_ResetSubSyncState()
    
	-- 发送查询消息给替补队长
	-- 使用SendAddonMessage发送查询消息，前缀为"AMB_TBQQ"
    local success, errorMsg = pcall(SendAddonMessage, "AMB_TBQQ", captain, "GUILD")
    if not success then
        ADKP_Print("发送查询消息失败: " .. (errorMsg or "未知错误"))
    end
end

-- 获取玩家职业
function ADKP_GetPlayerClass(playerName)
	-- 首先检查DKP表中是否有职业信息
    if WebDKP_DkpTable and WebDKP_DkpTable[playerName] and WebDKP_DkpTable[playerName]["class"] then
        return WebDKP_DkpTable[playerName]["class"]
    end
    
	-- 然后尝试从团队成员中查找
    for i = 1, GetNumRaidMembers() do
        local name, _, _, _, _, class = GetRaidRosterInfo(i)
        if name == playerName then
            return class
        end
    end
    
	-- 如果团队中找不到，再尝试从公会成员中查找
    for i = 1, GetNumGuildMembers(true) do
        local name, _, _, _, _, _, _, _, online, _, class = GetGuildRosterInfo(i)
        if name == playerName then
            return class
        end
    end
    
    return nil
end

-- ================================
-- BOSS奖励窗口DKP列表下拉菜单初始化
-- ================================
function ADKP_BossAwardTableDropdown_Init()
    local info;
    local selected = "";
    
	-- 使用ADKP_Tables数据中的实际列表
    if ( WebDKP_Tables ~= nil and next(WebDKP_Tables)~=nil ) then
        for key, entry in pairs(WebDKP_Tables) do
            if ( type(entry) == "table" ) then
                info = { };
                info.text = entry.name or key;
                info.value = entry["id"]; 
                info.func = ADKP_BossAwardTableDropdown_OnClick;
                if ( entry["id"] == ADKP_BossAwardData.tableid ) then
                    info.checked = true;
                    selected = info.text;
                end
                UIDropDownMenu_AddButton(info);
            end
        end
        
        -- 设置下拉菜单显示的文本和选中状态
        if selected ~= "" then
            UIDropDownMenu_SetText(selected, ADKP_BossAwardTableDropdown);
            -- 同时设置选中的名称，确保正确显示勾选状态
            UIDropDownMenu_SetSelectedName(ADKP_BossAwardTableDropdown, selected);
        end
    end
end

-- ================================
-- BOSS奖励窗口DKP列表下拉菜单点击处理
-- ================================
-- In WoW 1.12 Lua 5.0, use 'this' instead of function parameters
function ADKP_BossAwardTableDropdown_OnClick()
	-- 安全获取按钮对象 - 兼容不同调用方式
    local button = this or  (UIDropDownMenu_GetSelectedName and UIDropDownMenu_GetSelectedName(ADKP_BossAwardTableDropdown)) or ADKP_BossAwardTableDropdown
    
    if not button or not button.value then
        -- 尝试从全局下拉菜单状态获取
        local selectedName = UIDropDownMenu_GetText(ADKP_BossAwardTableDropdown)
        if selectedName and WebDKP_Tables[selectedName] then
            ADKP_BossAwardData.tableid = WebDKP_Tables[selectedName]["id"]
            ADKP_BossAwardTableDropdown_Init()
            return
        end
        return
    end
    
    ADKP_BossAwardData.tableid = button.value;
	-- 更新下拉菜单显示的文本
    UIDropDownMenu_SetText(button:GetText(), ADKP_BossAwardTableDropdown);
	-- 直接重新初始化下拉菜单来更新选中状态，与主窗口的处理方式保持一致
    ADKP_BossAwardTableDropdown_Init();
end

-- ================================
-- 切换装备记录窗口显示/隐藏
-- ================================
function ADKP_ToggleLootList()
	-- 调用完整的装备记录显示功能（ADKP_LootList.lua 必然已加载）
    if ADKP_CreateLootListFrame and ADKP_UpdateLootList then
        local frame = ADKP_CreateLootListFrame()
        if frame:IsShown() then
            frame:Hide()
        else
            -- 立即显示框架，然后异步更新数据
            frame:Show()
            -- 使用延迟更新避免界面卡顿
            if frame.updateTimer then
                frame.updateTimer:Cancel()
            end
            frame.updateTimer = C_Timer.NewTimer(0.1, function()
                ADKP_UpdateLootList()
            end)
        end
    else
        ADKP_Print("无法显示装备记录窗口，请检查插件完整性。")
    end
end

-- ================================
-- 统一美化所有文本框底色（半透明暗色底）
-- ================================
function ADKP_StyleAllEditBoxes()
    local topFrames = {
        ADKP_Frame,
        ADKP_BidFrame,
        ADKP_AwardFrame
    }
    
    local function applyStyle(f)
        if not f then return end
        if f:GetObjectType() == "EditBox" then
            if f.SetBackdropColor then
                f:SetBackdropColor(0, 0, 0, 0.6);
                f:SetBackdropBorderColor(0.5, 0.5, 0.5, 1);
            end
        end
        local children = { f:GetChildren() };
        for _, child in ipairs(children) do
            applyStyle(child);
        end
    end
    
    for _, frame in ipairs(topFrames) do
        applyStyle(frame);
    end
end

-- 在插件加载时运行调试检查
ADKP_OnEnable = function()
    ADKP_Frame:Hide();
    getglobal("ADKP_AwardDKP_Frame"):Show();
    getglobal("ADKP_Options_Frame"):Hide();
    if ADKP_AwardAllDKP_Frame then ADKP_AwardAllDKP_Frame:Hide() end
    if ADKP_AwardItem_Frame then ADKP_AwardItem_Frame:Hide() end
    if ADKP_Personal_Frame then ADKP_Personal_Frame:Hide() end
    
    ADKP_UpdatePlayersInGroup();
    ADKP_UpdateTableToShow();
    
	-- place a hook on the chat frame so we can filter out our whispers
    ADKP_Register_WhisperHook();
    
        --hooksecurefunc("SetItemRef",ADKP_ItemChatClick);
    if ( SetItemRef ~= ADKP_ItemChatClick ) then
        -- place a hook on item shift+clicks so we can get item details
        ADKP_ItemChatClick_Original = SetItemRef;
        SetItemRef = ADKP_ItemChatClick;
    end

	-- 立即预加载数据列表框架和函数，确保首次点击即可响应
    ADKP_PreloadLootList()

    -- 统一美化所有文本框底色
    ADKP_StyleAllEditBoxes();
end

-- ================================
-- 立即预加载数据列表功能，解决重载后需要两次点击的问题
-- ================================
function ADKP_PreloadLootList()
	-- 预创建已禁用：避免在 ADKP_LootList.lua 加载前用兑底实现抢先创建并缓存独立窗口
    -- 框架将在首次点击”数据列表”标签时，由正式实现按内嵌面板方式创建
    ADKP_LootListFramePreloaded = false
end

-- ================================
-- 处理 /adkp 自定义命令
-- ================================
function ADKP_SlashCmdHandler(cmd)
	-- 确保cmd是字符串
    cmd = cmd or ""
	-- 使用string.gmatch来解析命令参数
    local args = {}
    for arg in string.gmatch(cmd, "%S+") do
        table.insert(args, arg)
    end
    
    local cmd = args[1] or ""
    local arg1 = args[2] or ""
    local arg2 = args[3] or ""
    local arg3 = args[4] or ""
    local argCount = table.getn(args)
    
	-- 将命令转换为小写以实现不区分大小写
    cmd = string.lower(cmd)
	-- 处理空命令时显示主界面
    if not cmd or cmd == "" then
        ADKP_ToggleGUI();
        return
    end   
	-- 处理help命令，显示帮助信息
		    if cmd == "help" then
	        ADKP_Print("===== ADKP 插件命令 =====")
	        ADKP_Print("/adkp - 显示主界面")
        ADKP_Print("/adkp k<分数> [原因] - 原因为「击杀-目标名/原因」，执行奖惩团队和替补")
        ADKP_Print("/adkp a<分数> - 原因为「集合分」，执行奖惩团队和替补")
        ADKP_Print("/adkp b<分数> - 原因为「解散分」，执行奖惩团队和替补")
	        ADKP_Print("/adkp c<分数> [原因] - 对当前目标单点奖惩（缺省原因：菜出天际-犯错）")
	        ADKP_Print("/adkp boss - 显示BOSS名单管理界面（自定义与排除名单）")
	        ADKP_Print("/adkp bb - 切换静默模式（关闭团队播报，仅记录分数）")
	        ADKP_Print("/adkp tc - 切换 Boss 击杀加分总开关")
	        ADKP_Print("/adkp help - 显示此帮助信息")
	        ADKP_Print("=========================")
	        return
	    end

			-- 处理bb命令，切换静默模式
	    -- /adkpk<分数> [原因] 或 /adkpk <分数> [原因]：
    -- 有原因时使用“击杀-原因”；无原因时使用“击杀-目标名”
    local autoPointsText = nil
    local autoReasonText = ""
    if cmd == "k" then
        autoPointsText = arg1 or ""
        if argCount >= 3 then
            autoReasonText = table.concat(args, " ", 3)
        end
    else
        autoPointsText = string.match(cmd, "^k([%+%-]?%d+%.?%d*)$")
        if autoPointsText ~= nil and argCount >= 2 then
            autoReasonText = table.concat(args, " ", 2)
        end
    end
    if autoPointsText ~= nil then
        if autoPointsText == "" then
            ADKP_Print("用法：/adkpk<分数> [原因] 或 /adkpk <分数> [原因]")
            return
        end

        local pointsVal = tonumber(autoPointsText)
        if not pointsVal then
            ADKP_Print("错误：分数必须是数字。用法：/adkpk<分数> [原因]")
            return
        end

        autoReasonText = string.gsub(autoReasonText or "", "^%s*", "")
        autoReasonText = string.gsub(autoReasonText, "%s*$", "")

        local reasonSource = autoReasonText
        if reasonSource == "" then
            local targetName = UnitName("target")
            if not targetName or targetName == "" then
                ADKP_Print("错误：请先选中目标，或在命令中填写原因。")
                return
            end
            reasonSource = targetName
        end

        local reasonText = "击杀-" .. reasonSource

        local restoreReason = ADKP_AwardDKP_FrameReason
        local restorePoints = ADKP_AwardDKP_FramePoints

        if ADKP_AwardDKP_FrameReason and ADKP_AwardDKP_FrameReason.SetText then
            ADKP_AwardDKP_FrameReason:SetText(reasonText)
        else
            ADKP_AwardDKP_FrameReason = { GetText = function() return reasonText end }
        end

        if ADKP_AwardDKP_FramePoints and ADKP_AwardDKP_FramePoints.SetText then
            ADKP_AwardDKP_FramePoints:SetText(tostring(pointsVal))
        else
            ADKP_AwardDKP_FramePoints = { GetText = function() return tostring(pointsVal) end }
        end

        if ADKP_AwardRaidAndSub_Event then
            ADKP_AwardRaidAndSub_Event()
        else
            ADKP_Print("错误：未找到奖惩团队和替补功能。")
        end

        if restoreReason == nil then
            ADKP_AwardDKP_FrameReason = nil
        end
        if restorePoints == nil then
            ADKP_AwardDKP_FramePoints = nil
        end
        return
    end

    -- /adkpa<分数> 或 /adkpa <分数>：原因为“集合分”，执行“奖惩团队和替补”
    -- /adkpb<分数> 或 /adkpb <分数>：原因为“解散分”，执行“奖惩团队和替补”
    local fixedPointsText = nil
    local fixedReasonText = nil
    if cmd == "a" then
        fixedPointsText = arg1 or ""
        fixedReasonText = "集合分"
    elseif cmd == "b" then
        fixedPointsText = arg1 or ""
        fixedReasonText = "解散分"
    else
        fixedPointsText = string.match(cmd, "^a([%+%-]?%d+%.?%d*)$")
        if fixedPointsText ~= nil then
            fixedReasonText = "集合分"
        else
            fixedPointsText = string.match(cmd, "^b([%+%-]?%d+%.?%d*)$")
            if fixedPointsText ~= nil then
                fixedReasonText = "解散分"
            end
        end
    end
    if fixedPointsText ~= nil then
        if fixedPointsText == "" then
        ADKP_Print("用法：/adkpa<分数> 或 /adkpb<分数>")
            return
        end

        local pointsVal = tonumber(fixedPointsText)
        if not pointsVal then
            ADKP_Print("错误：分数必须是数字。用法：/adkpa<分数> 或 /adkpb<分数>")
            return
        end

        local restoreReason = ADKP_AwardDKP_FrameReason
        local restorePoints = ADKP_AwardDKP_FramePoints

        if ADKP_AwardDKP_FrameReason and ADKP_AwardDKP_FrameReason.SetText then
            ADKP_AwardDKP_FrameReason:SetText(fixedReasonText)
        else
            ADKP_AwardDKP_FrameReason = { GetText = function() return fixedReasonText end }
        end

        if ADKP_AwardDKP_FramePoints and ADKP_AwardDKP_FramePoints.SetText then
            ADKP_AwardDKP_FramePoints:SetText(tostring(pointsVal))
        else
            ADKP_AwardDKP_FramePoints = { GetText = function() return tostring(pointsVal) end }
        end

        if ADKP_AwardRaidAndSub_Event then
            ADKP_AwardRaidAndSub_Event()
        else
            ADKP_Print("错误：未找到奖惩团队和替补功能。")
        end

        if restoreReason == nil then
            ADKP_AwardDKP_FrameReason = nil
        end
        if restorePoints == nil then
            ADKP_AwardDKP_FramePoints = nil
        end
        return
    end


    -- /adkpc<分数> [原因]：当前目标单点奖惩，原因默认“菜出天际-犯错”
    local cPointsText = nil
    local cReasonText = nil
    if cmd == "c" then
        cPointsText = arg1 or ""
        if table.getn(args) >= 3 then
            local reasonParts = {}
            for i = 3, table.getn(args) do
                table.insert(reasonParts, args[i])
            end
            cReasonText = table.concat(reasonParts, " ")
        end
    else
        cPointsText = string.match(cmd, "^c([%+%-]?%d+%.?%d*)$")
        if cPointsText ~= nil then
            if table.getn(args) >= 2 then
                local reasonParts = {}
                for i = 2, table.getn(args) do
                    table.insert(reasonParts, args[i])
                end
                cReasonText = table.concat(reasonParts, " ")
            end
        end
    end
    if cPointsText ~= nil then
        if cPointsText == "" then
            ADKP_Print("用法：/adkpc<分数> [原因]")
            return
        end

        local pointsVal = tonumber(cPointsText)
        if not pointsVal then
            ADKP_Print("错误：分数必须是数字。用法：/adkpc<分数> [原因]")
            return
        end

        local targetName = UnitName("target")
        if not targetName or targetName == "" then
            ADKP_Print("错误：请先选中目标。")
            return
        end

        if not cReasonText or cReasonText == "" then
            cReasonText = "菜出天际-犯错"
        end

        local className = ADKP_GetPlayerClass(targetName) or "战士"
        if ADKP_NormalizeClassName then
            className = ADKP_NormalizeClassName(className)
        end
        local playerTable = {{ name = targetName, class = className }}

        if not StaticPopupDialogs then
            StaticPopupDialogs = {}
        end
        if not StaticPopupDialogs["ADKP_AWARD_TARGET_CONFIRM"] then
            StaticPopupDialogs["ADKP_AWARD_TARGET_CONFIRM"] = {
                text = "",
                button1 = "确定",
                button2 = "取消",
                timeout = 0,
                whileDead = 1,
                hideOnEscape = 1,
                OnAccept = function()
                    local dialog = StaticPopupDialogs["ADKP_AWARD_TARGET_CONFIRM"]
                    if dialog and dialog._confirmCallback then
                        dialog._confirmCallback()
                    end
                end
            }
        end

        local confirmText = "确定要为目标调整DKP吗？\n目标: " .. targetName .. "\n分数: " .. tostring(pointsVal) .. "\n原因: " .. cReasonText
        StaticPopupDialogs["ADKP_AWARD_TARGET_CONFIRM"].text = confirmText
        StaticPopupDialogs["ADKP_AWARD_TARGET_CONFIRM"]._confirmCallback = function()
            ADKP_AddDKP(pointsVal, cReasonText, "false", playerTable)
            ADKP_AnnounceAwardSingle(pointsVal, cReasonText, targetName)
            ADKP_UpdateTable()
            ADKP_UpdateTableToShow()
            if ADKP_UpdateLootList then
                ADKP_UpdateLootList()
            end
        end
        StaticPopup_Show("ADKP_AWARD_TARGET_CONFIRM")
        return
    end


    if cmd == "bb" then
        if not WebDKP_Options then
            WebDKP_Options = {}
        end
        if not WebDKP_Options["SilentMode"] then
            WebDKP_Options["SilentMode"] = false
        end
        
	        WebDKP_Options["SilentMode"] = not WebDKP_Options["SilentMode"]
	        
	        if WebDKP_Options["SilentMode"] then
	            ADKP_Print("静默模式已开启 - 团队播报已关闭，仅记录分数")
	        else
	            ADKP_Print("静默模式已关闭 - 团队播报已开启")
	        end
	        
	        -- 同步自用页勾选框状态（如果已加载）
	        if ADKP_Personal_FrameSilentMode and ADKP_Personal_FrameSilentMode.SetChecked then
	            ADKP_Personal_FrameSilentMode:SetChecked(WebDKP_Options["SilentMode"] and true or false)
	        end
	        return
		end
	
	-- 处理tc命令，切换 Boss 击杀加分总开关
	if cmd == "tc" then
		if not WebDKP_Options then
			WebDKP_Options = {}
		end
		
		-- 检查配置是否存在，如果不存在则初始化为开启状态
		if WebDKP_Options["BossDeathPopup"] == nil then
			WebDKP_Options["BossDeathPopup"] = true
			ADKP_Print("Boss 击杀加分已开启")
		else
			-- 切换状态
			WebDKP_Options["BossDeathPopup"] = not WebDKP_Options["BossDeathPopup"]
			
			if WebDKP_Options["BossDeathPopup"] then
				ADKP_Print("Boss 击杀加分已开启")
			else
				ADKP_Print("Boss 击杀加分已关闭")
			end
		end
		ADKP_SyncBossAwardControls()
		return
	end
	
	-- 处理pz命令，设置物品拾取记录品质等级
	if cmd == "pz" then
		if not WebDKP_Options then
			WebDKP_Options = {}
		end
		if not WebDKP_Options["LootQualityLevel"] then
			WebDKP_Options["LootQualityLevel"] = 1
		end
		
		-- 如果没有参数，显示当前设置
		if not arg1 or arg1 == "" then
			local qualityText = ""
			if WebDKP_Options["LootQualityLevel"] == 1 then
				qualityText = "橙色、紫色品质"
			elseif WebDKP_Options["LootQualityLevel"] == 2 then
				qualityText = "橙色、紫色、蓝色品质"
			elseif WebDKP_Options["LootQualityLevel"] == 3 then
				qualityText = "橙色、紫色、蓝色、绿色品质"
			end
			ADKP_Print("当前物品拾取记录品质等级：" .. WebDKP_Options["LootQualityLevel"] .. "（" .. qualityText .. "）")
			ADKP_Print("使用 /adkppz [1-3] 来修改设置")
			return
		end
		
		-- 解析参数
		local level = tonumber(arg1)
		if not level or level < 1 or level > 3 then
			ADKP_Print("错误：品质等级必须是1-3之间的数字！")
			ADKP_Print("正确格式：/adkppz [1-3]")
			ADKP_Print("1=只记录橙色、紫色品质")
			ADKP_Print("2=记录橙色、紫色、蓝色品质") 
			ADKP_Print("3=记录橙色、紫色、蓝色、绿色品质")
			return
		end
		
		-- 更新设置
		WebDKP_Options["LootQualityLevel"] = level
		
		local qualityText = ""
		if level == 1 then
			qualityText = "橙色、紫色品质"
		elseif level == 2 then
			qualityText = "橙色、紫色、蓝色品质"
		elseif level == 3 then
			qualityText = "橙色、紫色、蓝色、绿色品质"
		end
		
		ADKP_Print("物品拾取记录品质等级已设置为：" .. level .. "（" .. qualityText .. "）")
		return
	end
	
    
    

    
	-- 处理tj命令，添加新的DKP名单
    if cmd == "tj" then
        -- 解析参数：名字 职业 [DKP初始分]，初始分可选，默认0
        local name = args[2] or ""
        local class = args[3] or ""
        local initialDkp = args[4] or "0" -- 默认初始分为0
        
        if not name or not class then
            ADKP_Print("用法：/adkptj 名字 职业 [DKP初始分]")
            ADKP_Print("例如：/adkptj 张三 战士")
            ADKP_Print("例如：/adkptj 张三 战士 100")
            return
        end
        
        -- 验证初始分是否为数字
        if not tonumber(initialDkp) then
            ADKP_Print("错误：DKP初始分必须是数字！")
            ADKP_Print("用法：/adkptj 名字 职业 [DKP初始分]")
            return
        end
        
        -- 验证职业是否有效，支持中英文职业名称
        local validClasses = {
            {en = "Druid", zh = "德鲁伊"},
            {en = "Hunter", zh = "猎人"},
            {en = "Mage", zh = "法师"},
            {en = "Rogue", zh = "盗贼"},
            {en = "Shaman", zh = "萨满祭司"},
            {en = "Paladin", zh = "圣骑士"},
            {en = "Priest", zh = "牧师"},
            {en = "Warrior", zh = "战士"},
            {en = "Warlock", zh = "术士"}
        }
        local classValid = false
        local englishClass = ""
        
        for _, validClass in pairs(validClasses) do
            if string.lower(class) == string.lower(validClass.en) or string.lower(class) == string.lower(validClass.zh) then
                englishClass = validClass.en
                classValid = true
                break
            end
        end
        
        if not classValid then
            ADKP_Print("错误：无效的职业！")
            ADKP_Print("有效职业：德鲁伊, 猎人, 法师, 盗贼, 萨满祭司, 圣骑士, 牧师, 战士, 术士")
            return
        end
        
        -- 使用英文职业名称存储
        class = englishClass
        
        -- 转换DKP为数字
        initialDkp = tonumber(initialDkp)
        
        -- 检查玩家是否已存在
        if WebDKP_DkpTable[name] then
            ADKP_Print("警告：" .. name .. " 已存在于DKP列表中！")
            ADKP_Print("当前DKP：" .. (WebDKP_DkpTable[name]["dkp_" .. ADKP_GetTableid()] or 0))
            ADKP_Print("如需修改，请使用DKP奖惩功能。")
            return
        end
        
        -- 添加新玩家到DKP表
        WebDKP_DkpTable[name] = {
            ["class"] = class,
            ["dkp_" .. ADKP_GetTableid()] = initialDkp,
            ["Selected"] = false,
            ["IsSub"] = false
        }
        
        -- 更新显示表格
        ADKP_UpdateTableToShow()
        ADKP_UpdateTable()
        
        ADKP_Print("成功添加新玩家：")
        ADKP_Print("名字：" .. name)
        ADKP_Print("职业：" .. class)
        ADKP_Print("初始DKP：" .. initialDkp)
        return
    end
    
	-- 处理list命令，显示装备获取记录
    if cmd == "list" or cmd == "loot" then
        if ADKP_ToggleLootList then
            ADKP_ToggleLootList()
        else
            ADKP_Print("无法显示装备记录，请检查插件安装是否正确。")
        end
        return
    end
    
    -- 处理boss命令，显示BOSS排除和自定义名单管理界面
    if cmd == "boss" then
        ADKP_ShowExcludedBossesFrame()
        return
    end
    
end

-- 职业颜色映射表（魔兽世界1.12版本）
ADKP_CLASS_COLORS = {
    ["战士"] = "|cffc79c6e",
    ["圣骑士"] = "|cfff58cba",
    ["猎人"] = "|cffabd473",
    ["潜行者"] = "|cfffff569",
    ["牧师"] = "|cffffffff",
    ["死亡骑士"] = "|cffc41f3b",
    ["萨满祭司"] = "|cff0070de",
    ["法师"] = "|cff69ccf0",
    ["术士"] = "|cff9482c9",
    ["德鲁伊"] = "|cffff7d0a"
}

-- 获取职业颜色的函数
function ADKP_GetClassColor(class)
    local color = ADKP_CLASS_COLORS[class]
    if color then
        return color
    else
        return "|cffffffff"  -- 默认白色
    end
end

-- 添加ADKP_AddDKP函数实现
function ADKP_AddDKP(points, reason, forItem, players, tableid, awardDate)
	-- 检查是否选择了玩家
	if not players or not next(players) then
		ADKP_Print("错误: 请选择至少一名玩家。");
		return false;
	end
	
	-- 如果没有指定tableid，使用当前选中的表格
	if not tableid then
		tableid = ADKP_GetTableid();
	end
	-- ADKP_AddDKPToTable函数内部会处理表格的检查和创建，此处无需重复处理
	
	local date = awardDate or date("%Y-%m-%d %H:%M:%S");
	local location = GetZoneText();
	local awardedBy = UnitName("player");
		
	-- 确保reason是字符串类型
	if type(reason) ~= "string" then
		reason = tostring(reason) or "未知原因";
	end
	reason = string.gsub(string.gsub(reason, ".*%[", ""), "%].*", "");
		
	if (not WebDKP_Log) then
		WebDKP_Log = {};
	end
	--next, make sure this player is in the log
	if (not WebDKP_Log[reason.." "..date]) then
		WebDKP_Log[reason.." "..date] = {};
	end
	
	WebDKP_Log["Version"] = 2;
	WebDKP_Log[reason.." "..date]["reason"] = reason;
	WebDKP_Log[reason.." "..date]["date"] = date;
	WebDKP_Log[reason.." "..date]["foritem"] = forItem;
	WebDKP_Log[reason.." "..date]["zone"] = location;
	WebDKP_Log[reason.." "..date]["tableid"] = tableid;
	WebDKP_Log[reason.." "..date]["awardedby"] = awardedBy;
	WebDKP_Log[reason.." "..date]["points"] = points;
	-- 添加唯一标识符用于记录修改
	WebDKP_Log[reason.." "..date]["uniqueId"] = reason.." "..date;
	
	if (not WebDKP_Log[reason.." "..date]["awarded"]) then
		WebDKP_Log[reason.." "..date]["awarded"] = {};
	end
	
	-- 记录本次实际传入 AddDKP 的加分名单，供公告使用；不要再依赖全局 Selected 残留。
	ADKP_LastAwardPlayers = {};
	ADKP_LastAwardPlayerCount = 0;
	
	for k, v in pairs(players) do
		local name, class
		if (type(v) == "table") then
			name = v["name"];
			class = v["class"];
		else
			name = v;
			class = ADKP_GetPlayerClass(name) or "战士";
		end
		if not class or class == "" then
			class = ADKP_GetPlayerClass(name) or "战士";
		end
		if ADKP_NormalizeClassName then
			class = ADKP_NormalizeClassName(class);
		end
		
		if name and name ~= "" then
			ADKP_LastAwardPlayerCount = ADKP_LastAwardPlayerCount + 1;
			ADKP_LastAwardPlayers[ADKP_LastAwardPlayerCount] = name;
		end

		if not WebDKP_DkpTable then
			WebDKP_DkpTable = {};
		end
		local dkpField = "dkp_"..tableid;
		if not WebDKP_DkpTable[name] then
			WebDKP_DkpTable[name] = {
				["class"] = class,
				[dkpField] = 0,
				["Selected"] = false,
				["IsSub"] = false
			};
		else
			if (WebDKP_DkpTable[name]["class"] == nil or WebDKP_DkpTable[name]["class"] == "") then
				WebDKP_DkpTable[name]["class"] = class;
			end
			if (WebDKP_DkpTable[name][dkpField] == nil) then
				WebDKP_DkpTable[name][dkpField] = 0;
			end
		end
		
		local guild = ADKP_GetGuildName(name);
		ADKP_AddDKPToTable(name, class, points);
		--add them to the log entry
		WebDKP_Log[reason.." "..date]["awarded"][name] = {};
		WebDKP_Log[reason.." "..date]["awarded"][name]["name"]=name;
		WebDKP_Log[reason.." "..date]["awarded"][name]["guild"]=guild;
		WebDKP_Log[reason.." "..date]["awarded"][name]["class"]=class;
	end
		
		-- 通知团队
		local announceMsg = "[ADKP] "..reason..": "..points.." 分"
		local tellLocation = "RAID"
		if ADKP_GetTellLocation then
			tellLocation = ADKP_GetTellLocation()
		end
		if ADKP_SendAnnouncement then
			ADKP_SendAnnouncement(announceMsg, tellLocation)
		else
			local isSilentMode = WebDKP_Options and WebDKP_Options["SilentMode"]
			if tellLocation == "NONE" then
				ADKP_Print(announceMsg)
			elseif isSilentMode then
				ADKP_Print("[静默] " .. announceMsg)
			else
				SendChatMessage(announceMsg, tellLocation)
			end
		end
		
		-- 更新UI - 移除不存在的ADKP_UpdateUI函数调用
		-- UI更新由其他机制处理
	end

-- 添加ADKP_AddDKPToTable函数实现
function ADKP_AddDKPToTable(name, class, points)
	local tableid = ADKP_GetTableid();
	
	-- 确保ADKP_Tables和相应的表结构存在
	if (not WebDKP_Tables) then
		WebDKP_Tables = {};
	end
	if (not WebDKP_Tables[tableid]) then
		-- 使用统一的函数获取表格名称
		local tableName = ADKP_GetTableNameById(tableid)
		WebDKP_Tables[tableid] = {
			name = tableName,
			id = tableid,
			players = {}
		};
	end
	
	-- 确保players表存在
	if (not WebDKP_Tables[tableid].players) then
		WebDKP_Tables[tableid].players = {};
	end
	
	-- 确保玩家在表中存在
	if (not WebDKP_Tables[tableid].players[name]) then
		WebDKP_Tables[tableid].players[name] = {};
		WebDKP_Tables[tableid].players[name]["dkp"] = 0;
		WebDKP_Tables[tableid].players[name]["earned"] = 0;
		WebDKP_Tables[tableid].players[name]["spent"] = 0;
		WebDKP_Tables[tableid].players[name]["class"] = class;
	end
	
	-- 添加DKP
	WebDKP_Tables[tableid].players[name]["dkp"] = WebDKP_Tables[tableid].players[name]["dkp"] + points;
	WebDKP_Tables[tableid].players[name]["earned"] = WebDKP_Tables[tableid].players[name]["earned"] + points;
	
	-- 如果DKP为负数，设置为0
	if (WebDKP_Tables[tableid].players[name]["dkp"] < 0) then
		WebDKP_Tables[tableid].players[name]["dkp"] = 0;
	end
end


-- 修改DKP记录分数的函数
function ADKP_EditDKPRecord(uniqueId, newPoints, newReason)
	-- 检查参数
    if not uniqueId then
        ADKP_Print("错误：缺少uniqueId参数")
        return false
    end
    
    if not newPoints then
        ADKP_Print("错误：缺少新分数参数")
        return false
    end
    
	-- 转换为数字
    newPoints = tonumber(newPoints)
    if not newPoints then
        ADKP_Print("错误：新分数必须是数字")
        return false
    end
    
	-- 先从ADKP_Log中找到要修改的记录
    local targetLogEntry = nil
    local oldPoints = 0
    local oldReason = ""
    local affectedPlayers = {}
    
    if WebDKP_Log then
        for logKey, logEntry in pairs(WebDKP_Log) do
            if type(logEntry) == "table" and logEntry.uniqueId and logEntry.uniqueId == uniqueId then
                -- 确保这是DKP记录而不是装备记录或替补记录
                local isLootRecord = logEntry.foritem == true or logEntry.foritem == "true"
                local isSubstituteRecord = logEntry.reason and string.find(logEntry.reason, "替补")
                
                if not isLootRecord and not isSubstituteRecord then
                    -- 保存旧数据和受影响的玩家
                    oldPoints = tonumber(logEntry.points) or 0
                    oldReason = logEntry.reason or ""
                    if logEntry.awarded then
                        for playerName, _ in pairs(logEntry.awarded) do
                            affectedPlayers[playerName] = true
                        end
                    end
                    targetLogEntry = logKey
                    break
                end
            end
        end
    end
    
	-- 如果没找到记录，返回失败
    if not targetLogEntry then
        ADKP_Print("错误：未找到要修改的DKP记录")
        return false
    end
    
	-- 计算分数变化量
    local pointsChange = newPoints - oldPoints
    
	-- 更新ADKP_Log中的记录
    WebDKP_Log[targetLogEntry].points = newPoints
	-- 如果提供了新原因，则更新原因字段
    if newReason and newReason ~= "" then
        WebDKP_Log[targetLogEntry].reason = newReason
    end
    
	-- 同时更新ADKP_DKPRecords中的记录
    if ADKP_DKPRecords then
        for i, record in ipairs(ADKP_DKPRecords) do
            if record.uniqueId and record.uniqueId == uniqueId then
                record.points = newPoints
                if newReason and newReason ~= "" then
                    record.reason = newReason
                end
                break
            end
        end
    end
    
	-- 更新受影响玩家的DKP分数
    if pointsChange ~= 0 and next(affectedPlayers) then
        -- 获取当前使用的tableid
        local tableid = ADKP_GetTableid()
        local dkpField = "dkp_"..tableid
        
        -- 遍历ADKP_DkpTable更新玩家分数
        if WebDKP_DkpTable then
            for playerName, playerData in pairs(WebDKP_DkpTable) do
                if type(playerData) == "table" and affectedPlayers[playerName] then
                    -- 更新玩家分数
                    local currentDKP = tonumber(playerData[dkpField]) or 0
                    playerData[dkpField] = ADKP_ROUND(currentDKP + pointsChange, 2)
                    -- ADKP_Print("已更新玩家 " .. playerName .. " 的DKP分数: " .. playerData[dkpField])
                end
            end
        end
    end
    
	-- 保存数据并刷新界面
    if ADKP_SaveToDisk then
        ADKP_SaveToDisk()
    end
    if ADKP_UpdateTable then
        ADKP_UpdateTable()
    end
    if ADKP_UpdateLootList then
        ADKP_UpdateLootList()
    end
    
	-- 根据是否修改了原因显示不同的提示信息
    if newReason and newReason ~= "" and newReason ~= oldReason then
        ADKP_Print("成功修改DKP记录: " .. oldReason .. " -> " .. newReason .. ", 分数: " .. oldPoints .. " -> " .. newPoints)
    else
        ADKP_Print("成功修改DKP记录分数: " .. oldPoints .. " -> " .. newPoints)
    end
    return true
end

-- 显示修改DKP分数对话框的函数
function ADKP_ShowEditDKPDialog(uniqueId, currentPoints)
	-- 首先查找当前记录的原因
    local currentReason = "DKP记录"
    if WebDKP_Log then
        for _, logEntry in pairs(WebDKP_Log) do
            if type(logEntry) == "table" and logEntry.uniqueId and logEntry.uniqueId == uniqueId then
                currentReason = logEntry.reason or "DKP记录"
                break
            end
        end
    end
    
	-- 使用自定义窗口代替StaticPopupDialogs
    ADKP_ShowCustomReasonDialog(uniqueId, currentPoints, currentReason)
end

-- 创建自定义的原因输入对话框
function ADKP_ShowCustomReasonDialog(uniqueId, currentPoints, currentReason)
	-- 如果对话框已存在，先隐藏
    if ADKP_ReasonDialog then
        ADKP_ReasonDialog:Hide()
    end
    
	-- 创建对话框主窗口
    local dialog = CreateFrame("Frame", "ADKP_ReasonDialog", UIParent)
    dialog:SetWidth(260)
    dialog:SetHeight(150)
    
	-- 加载保存的窗口位置，如果没有则居中显示
    if ADKP_DialogPositions and ADKP_DialogPositions["ADKP_ReasonDialog"] then
        local pos = ADKP_DialogPositions["ADKP_ReasonDialog"]
        dialog:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", pos.x, pos.y)
    else
        dialog:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
    
    dialog:SetFrameStrata("DIALOG")
    dialog:SetMovable(true)
    dialog:EnableMouse(true)
    dialog:SetScript("OnMouseDown", function()
        this:StartMoving()
    end)
    dialog:SetScript("OnMouseUp", function()
        this:StopMovingOrSizing()
        -- 保存窗口位置
        if not ADKP_DialogPositions then
            ADKP_DialogPositions = {}
        end
        local x, y = this:GetLeft(), this:GetTop()
        ADKP_DialogPositions["ADKP_ReasonDialog"] = {x = x, y = y}
    end)
    
	-- 设置窗口背景和边框
    dialog:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    dialog:SetBackdropColor(0, 0, 0, 0.8)
    
	-- 创建标题文本
    local titleText = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleText:SetPoint("TOP", dialog, "TOP", 0, -15)
    titleText:SetText("修改DKP记录")
    
	-- 创建信息文本
    local infoText = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    infoText:SetPoint("TOP", dialog, "TOP", 0, -40)
    infoText:SetWidth(dialog:GetWidth() - 40)
    infoText:SetJustifyH("LEFT")
    infoText:SetText("当前原因: " .. currentReason .. "\n当前分数: " .. tostring(currentPoints) .. "\n请输入新原因:")
    
	-- 创建编辑框
    local ReasonEditBox = CreateFrame("EditBox", "ADKP_ModifyReasonEditBox"..GetTime(), dialog, "InputBoxTemplate")
    ReasonEditBox:SetWidth(dialog:GetWidth() - 60)
    ReasonEditBox:SetHeight(24)
    ReasonEditBox:SetPoint("TOP", infoText, "BOTTOM", 0, -10)
    ReasonEditBox:SetFontObject("ChatFontNormal")
    ReasonEditBox:SetAutoFocus(true)
    ReasonEditBox:SetMaxLetters(100)
    ReasonEditBox:SetText(currentReason)
    ReasonEditBox:SetScript("OnEscapePressed", function()
        this:ClearFocus()
    end)
    ReasonEditBox:SetScript("OnEnterPressed", function()
        -- 按回车相当于点击下一步
        if ADKP_NextButton then
            ADKP_NextButton:Click()
        end
    end)
    
	-- 创建下一步按钮
    local nextButton = CreateFrame("Button", "ADKP_NextButton", dialog, "UIPanelButtonTemplate")
    nextButton:SetWidth(100)
    nextButton:SetHeight(25)
    nextButton:SetPoint("BOTTOMLEFT", dialog, "BOTTOMLEFT", 20, 10)
    nextButton:SetText("下一步")
    nextButton:SetScript("OnClick", function()
        local newReason = ReasonEditBox:GetText() or "DKP记录"
        dialog:Hide()
        -- 显示分数输入对话框
        ADKP_ShowCustomPointsDialog(uniqueId, currentPoints, newReason)
    end)
    
	-- 创建取消按钮
    local cancelButton = CreateFrame("Button", "ADKP_CancelButton", dialog, "UIPanelButtonTemplate")
    cancelButton:SetWidth(100)
    cancelButton:SetHeight(25)
    cancelButton:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -20, 10)
    cancelButton:SetText("取消")
    cancelButton:SetScript("OnClick", function()
        dialog:Hide()
    end)
    
	-- ESC键关闭对话框
    dialog:EnableKeyboard(true)
    dialog:SetScript("OnKeyDown", function()
        if arg1 == "ESCAPE" then
            if ReasonEditBox.HasFocus and ReasonEditBox:HasFocus() then
                ReasonEditBox:ClearFocus()
                dialog:EnableKeyboard(true)
            else
                dialog:Hide()
            end
        end
    end)
    
	-- 保存引用
    ADKP_ReasonDialog = dialog
    
	-- 显示对话框
    dialog:Show()
end

-- 创建自定义的分数输入对话框
function ADKP_ShowCustomPointsDialog(uniqueId, currentPoints, newReason)
	-- 如果对话框已存在，先隐藏
    if ADKP_PointsDialog then
        ADKP_PointsDialog:Hide()
    end
    
	-- 创建对话框主窗口
    local dialog = CreateFrame("Frame", "ADKP_PointsDialog", UIParent)
    dialog:SetWidth(260)
    dialog:SetHeight(150)
    
	-- 加载保存的窗口位置，如果没有则居中显示
    if ADKP_DialogPositions and ADKP_DialogPositions["ADKP_PointsDialog"] then
        local pos = ADKP_DialogPositions["ADKP_PointsDialog"]
        dialog:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", pos.x, pos.y)
    else
        dialog:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
    
    dialog:SetFrameStrata("DIALOG")
    dialog:SetMovable(true)
    dialog:EnableMouse(true)
    dialog:SetScript("OnMouseDown", function()
        this:StartMoving()
    end)
    dialog:SetScript("OnMouseUp", function()
        this:StopMovingOrSizing()
        -- 保存窗口位置
        if not ADKP_DialogPositions then
            ADKP_DialogPositions = {}
        end
        local x, y = this:GetLeft(), this:GetTop()
        ADKP_DialogPositions["ADKP_PointsDialog"] = {x = x, y = y}
    end)
    
	-- 设置窗口背景和边框
    dialog:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    dialog:SetBackdropColor(0, 0, 0, 0.8)
    
	-- 创建标题文本
    local titleText = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleText:SetPoint("TOP", dialog, "TOP", 0, -15)
    titleText:SetText("修改DKP记录")
    
	-- 创建信息文本
    local infoText = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    infoText:SetPoint("TOP", dialog, "TOP", 0, -40)
    infoText:SetWidth(dialog:GetWidth() - 40)
    infoText:SetJustifyH("LEFT")
    infoText:SetText("新原因: " .. newReason .. "\n当前分数: " .. tostring(currentPoints) .. "\n请输入新分数:")
    
	-- 创建编辑框
    local PointsEditBox = CreateFrame("EditBox", "ADKP_ModifyPointsEditBox"..GetTime(), dialog, "InputBoxTemplate")
    PointsEditBox:SetWidth(dialog:GetWidth() - 60)
    PointsEditBox:SetHeight(24)
    PointsEditBox:SetPoint("TOP", infoText, "BOTTOM", 0, -10)
    PointsEditBox:SetFontObject("ChatFontNormal")
    PointsEditBox:SetAutoFocus(true)
    PointsEditBox:SetMaxLetters(10)
    PointsEditBox:SetText(tostring(currentPoints))
    
	-- 修复ESC键退出输入状态
    PointsEditBox:SetScript("OnEscapePressed", function()
        this:ClearFocus()
        -- 确保键盘焦点回到对话框
        dialog:EnableKeyboard(true)
    end)
    
    PointsEditBox:SetScript("OnEnterPressed", function()
        -- 按回车相当于点击确定
        if ADKP_ConfirmButton then
            ADKP_ConfirmButton:Click()
        end
    end)
    
	-- 添加焦点获取事件以处理键盘事件传播
    PointsEditBox:SetScript("OnEditFocusGained", function()
        -- 当编辑框获取焦点时，暂时禁用对话框的键盘处理
        dialog:EnableKeyboard(false)
    end)
    
    PointsEditBox:SetScript("OnEditFocusLost", function()
        -- 当编辑框失去焦点时，重新启用对话框的键盘处理
        dialog:EnableKeyboard(true)
    end)
    
	-- 创建确定按钮
    local confirmButton = CreateFrame("Button", "ADKP_ConfirmButton", dialog, "UIPanelButtonTemplate")
    confirmButton:SetWidth(100)
    confirmButton:SetHeight(25)
    confirmButton:SetPoint("BOTTOMLEFT", dialog, "BOTTOMLEFT",  20, 10)
    confirmButton:SetText("确定")
    confirmButton:SetScript("OnClick", function()
        local newPoints = PointsEditBox:GetText()
        -- 执行DKP记录修改
        ADKP_EditDKPRecord(uniqueId, newPoints, newReason)
        -- 修改分数后刷新界面
        ADKP_UpdateTable()
        ADKP_Refresh()
        ADKP_UpdateLootList()
        dialog:Hide()
    end)
    
	-- 创建取消按钮
    local cancelButton = CreateFrame("Button", "ADKP_PointsCancelButton", dialog, "UIPanelButtonTemplate")
    cancelButton:SetWidth(100)
    cancelButton:SetHeight(25)
    cancelButton:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -20, 10)
    cancelButton:SetText("取消")
    cancelButton:SetScript("OnClick", function()
        dialog:Hide()
    end)
    
	-- ESC键关闭对话框
    dialog:EnableKeyboard(true)
    dialog:SetScript("OnKeyDown", function()
        if arg1 == "ESCAPE" then
            -- 如果编辑框有焦点，先清除焦点
            if PointsEditBox.HasFocus and PointsEditBox:HasFocus() then
                PointsEditBox:ClearFocus()
            else
                dialog:Hide()
            end
        end
    end)
    
	-- 保存引用
    ADKP_PointsDialog = dialog
    
	-- 显示对话框
    dialog:Show()
end

-- 编辑装备记录的函数
function ADKP_EditLootRecord(uniqueId, newItemName, newCost, passedLogKey)
	-- 检查参数
    if not uniqueId and not passedLogKey then
        ADKP_Print("错误：缺少uniqueId或logKey参数")
        return false
    end

    if not newItemName then
        ADKP_Print("错误：缺少新物品名称参数")
        return false
    end

    if not newCost then
        ADKP_Print("错误：缺少新花费参数")
        return false
    end

	-- 转换为数字并确保为负数（装备花费应为负值）
    newCost = tonumber(newCost)
    if not newCost then
        ADKP_Print("错误：新花费必须是数字")
        return false
    end

	-- 确保花费为负数（装备花费应为负值）
    if newCost > 0 then
        newCost = -newCost
    end

	-- 先从ADKP_Log中找到要修改的装备记录
    local targetLogEntry = nil
    local oldItemName = ""
    local oldPoints = 0
    local affectedPlayers = {} -- 改为存储多个玩家

    -- 局部辅助：从一条 logEntry 抽取装备记录所需的旧数据
    local function extractLootData(logEntry)
        oldItemName = logEntry.reason or ""
        oldPoints = tonumber(logEntry.points) or 0
        if logEntry.awarded then
            for playerName, playerInfo in pairs(logEntry.awarded) do
                table.insert(affectedPlayers, playerName)
            end
        elseif logEntry.player then
            table.insert(affectedPlayers, logEntry.player)
        end
    end

    if WebDKP_Log then
        -- 优先用 passedLogKey 直接定位（比 uniqueId 匹配更可靠，老数据可能缺 uniqueId）
        local found = false
        if passedLogKey and WebDKP_Log[passedLogKey] and type(WebDKP_Log[passedLogKey]) == "table" then
            local logEntry = WebDKP_Log[passedLogKey]
            local isLootRecord = logEntry.foritem == true or logEntry.foritem == "true"
            if isLootRecord then
                extractLootData(logEntry)
                targetLogEntry = passedLogKey
                found = true
            end
        end
        -- fallback：用 uniqueId 遍历匹配
        if not found then
            for logKey, logEntry in pairs(WebDKP_Log) do
                if type(logEntry) == "table" and logEntry.uniqueId and logEntry.uniqueId == uniqueId then
                    local isLootRecord = logEntry.foritem == true or logEntry.foritem == "true"
                    if isLootRecord then
                        extractLootData(logEntry)
                        targetLogEntry = logKey
                        break
                    end
                end
            end
        end
    end
    
	-- 如果没找到记录，返回失败
    if not targetLogEntry then
        ADKP_Print("错误：未找到要修改的装备记录")
        return false
    end
    
	-- 计算花费变化量
    local costChange = newCost - oldPoints
    
	-- 更新ADKP_Log中的记录 - 装备名称使用reason字段
    WebDKP_Log[targetLogEntry].reason = newItemName
    WebDKP_Log[targetLogEntry].points = newCost
    
	-- 同时更新ADKP_LootHistory中的记录
    if WebDKP_LootHistory then
        for i, loot in ipairs(WebDKP_LootHistory) do
            if loot.uniqueId and loot.uniqueId == targetUniqueId then
                loot.reason = newItemName
                loot.points = newCost
                break
            end
        end
    end
    
	-- 更新受影响玩家的DKP分数（如果花费发生变化）
    
    
    if costChange ~= 0 and next(affectedPlayers) then
        -- 获取当前使用的tableid
        local tableid = ADKP_GetTableid()
        local dkpField = "dkp_"..tableid
        
        -- ADKP_Print("使用tableid: " .. tableid .. ", dkp字段: " .. dkpField)
        
        -- 更新所有获得该装备的玩家分数
        for _, playerName in ipairs(affectedPlayers) do
            -- ADKP_Print("正在更新玩家: " .. playerName)
            if WebDKP_DkpTable and WebDKP_DkpTable[playerName] then
                local currentDKP = tonumber(WebDKP_DkpTable[playerName][dkpField]) or 0
                local currentSpent = tonumber(WebDKP_DkpTable[playerName]["spent"]) or 0
                
                -- ADKP_Print("玩家当前DKP: " .. currentDKP .. ", 当前总花费: " .. currentSpent)
                
                WebDKP_DkpTable[playerName][dkpField] = ADKP_ROUND(currentDKP + costChange, 2)
                WebDKP_DkpTable[playerName]["spent"] = currentSpent + costChange
                
                -- ADKP_Print("已更新玩家 " .. playerName .. " 的DKP分数: " .. currentDKP .. " -> " .. WebDKP_DkpTable[playerName][dkpField] .. " (变化: " .. costChange .. ")")
                -- ADKP_Print("玩家总花费更新: " .. currentSpent .. " -> " .. WebDKP_DkpTable[playerName]["spent"])
            else
                -- ADKP_Print("警告: 玩家 " .. playerName .. " 的DKP数据不存在，无法更新")
                -- ADKP_Print("可用玩家: " .. ADKP_GetTableSize(WebDKP_DkpTable))
            end
        end

    end
    
	-- 保存数据并刷新界面
    if ADKP_SaveToDisk then
        ADKP_SaveToDisk()
    end
    if ADKP_UpdateTable then
        ADKP_UpdateTable()
    end
    if ADKP_UpdateLootList then
        ADKP_UpdateLootList()
    end
    

    return true
end

-- 编辑替补记录的函数
function ADKP_EditSubstituteRecord(uniqueId, newReason, newPoints)
	-- 检查参数
    if not uniqueId then
        ADKP_Print("错误：缺少uniqueId参数")
        return false
    end
    
    if not newReason then
        ADKP_Print("错误：缺少新原因参数")
        return false
    end
    
    if not newPoints then
        ADKP_Print("错误：缺少新分数参数")
        return false
    end
    
	-- 转换为数字
    newPoints = tonumber(newPoints)
    if not newPoints then
        ADKP_Print("错误：新分数必须是数字")
        return false
    end
    
	-- 先从ADKP_Log中找到要修改的替补记录
    local targetLogEntry = nil
    local oldReason = ""
    local oldPoints = 0
    local affectedPlayers = {}
    
    if WebDKP_Log then
        for logKey, logEntry in pairs(WebDKP_Log) do
            if type(logEntry) == "table" and logEntry.uniqueId and logEntry.uniqueId == uniqueId then
                -- 确保这是替补记录
                local isSubstituteRecord = logEntry.reason and string.find(logEntry.reason, "替补")
                
                if isSubstituteRecord then
                    -- 保存旧数据 - 重要：使用oldPoints进行分数计算
                    oldReason = logEntry.reason or ""
                    oldPoints = tonumber(logEntry.points) or 0
                    if logEntry.awarded then
                        for playerName, _ in pairs(logEntry.awarded) do
                            affectedPlayers[playerName] = true
                        end
                    end
                    targetLogEntry = logKey
                    break
                end
            end
        end
    end
    
	-- 如果没找到记录，返回失败
    if not targetLogEntry then
        ADKP_Print("错误：未找到要修改的替补记录")
        return false
    end
    
	-- 计算分数变化量
    local pointsChange = newPoints - oldPoints
    
	-- 更新ADKP_Log中的记录
    WebDKP_Log[targetLogEntry].reason = newReason
    WebDKP_Log[targetLogEntry].points = newPoints
    
	-- 同时更新ADKP_SubstituteRecords中的记录
    if ADKP_SubstituteRecords then
        for i, record in ipairs(ADKP_SubstituteRecords) do
            if record.uniqueId and record.uniqueId == uniqueId then
                record.reason = newReason
                record.points = newPoints
                break
            end
        end
    end
    
	-- 更新受影响玩家的DKP分数
    if pointsChange ~= 0 and next(affectedPlayers) then
        -- 获取当前使用的tableid
        local tableid = ADKP_GetTableid()
        local dkpField = "dkp_"..tableid
        
        -- 遍历ADKP_DkpTable更新玩家分数
        if WebDKP_DkpTable then
            for playerName, playerData in pairs(WebDKP_DkpTable) do
                if type(playerData) == "table" and affectedPlayers[playerName] then
                    -- 更新玩家分数
                    local currentDKP = tonumber(playerData[dkpField]) or 0
                    playerData[dkpField] = ADKP_ROUND(currentDKP + pointsChange, 2)
                    playerData["earned"] = (tonumber(playerData["earned"]) or 0) + pointsChange
                    -- ADKP_Print("已更新玩家 " .. playerName .. " 的DKP分数: " .. playerData[dkpField])
                end
            end
        end
    end
    
	-- 保存数据并刷新界面
    if ADKP_SaveToDisk then
        ADKP_SaveToDisk()
    end
    if ADKP_UpdateTable then
        ADKP_UpdateTable()
    end
    if ADKP_UpdateLootList then
        ADKP_UpdateLootList()
    end
    
    ADKP_Print("成功修改替补记录: " .. oldReason .. " -> " .. newReason .. ", 分数: " .. oldPoints .. " -> " .. newPoints)
    return true
end

-- 显示修改装备记录对话框的函数
function ADKP_ShowEditLootDialog(uniqueId, currentItem, currentCost, logKey)
	-- 首先查找当前记录的装备名称和花费
    local logCost = currentCost -- 默认使用传入的花费
    if WebDKP_Log then
        -- 优先用 logKey 直接定位（比 uniqueId 匹配更可靠，老数据可能缺 uniqueId 字段）
        local found = false
        if logKey and WebDKP_Log[logKey] and type(WebDKP_Log[logKey]) == "table" then
            local logEntry = WebDKP_Log[logKey]
            currentItem = logEntry.reason or currentItem or "装备记录"
            logCost = tonumber(logEntry.points) or currentCost
            found = true
        end
        -- fallback：用 uniqueId 遍历匹配
        if not found then
            for _, logEntry in pairs(WebDKP_Log) do
                if type(logEntry) == "table" and logEntry.uniqueId and logEntry.uniqueId == uniqueId then
                    currentItem = logEntry.reason or "装备记录"
                    logCost = tonumber(logEntry.points) or currentCost
                    break
                end
            end
        end
    end

	-- 显示第一个对话框（输入装备名称）
    ADKP_ShowCustomLootItemDialog(uniqueId, currentItem, logCost, logKey)
end

-- 修改装备记录对话框（单页：同时编辑装备名和分值）
function ADKP_ShowCustomLootItemDialog(uniqueId, currentItem, currentCost, logKey)
	-- 如果对话框已经存在，则销毁它
    if ADKP_LootItemDialog then
        ADKP_LootItemDialog:Hide()
        ADKP_LootItemDialog = nil
    end

	-- 创建新的对话框（单页双输入框，比原来高一些）
    local dialog = CreateFrame("Frame", "ADKP_LootItemDialog", UIParent)
    dialog:SetWidth(280)
    dialog:SetHeight(200)

	-- 加载保存的窗口位置，如果没有则居中显示
    if ADKP_DialogPositions and ADKP_DialogPositions["ADKP_LootItemDialog"] then
        local pos = ADKP_DialogPositions["ADKP_LootItemDialog"]
        dialog:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", pos.x, pos.y)
    else
        dialog:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end

    dialog:SetFrameStrata("DIALOG")

	-- 设置背景和边框
    dialog:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    dialog:SetBackdropColor(0, 0, 0, 0.8)

    dialog:SetMovable(true)
    dialog:EnableMouse(true)
    dialog:SetScript("OnMouseDown", function() dialog:StartMoving() end)
    dialog:SetScript("OnMouseUp", function()
        dialog:StopMovingOrSizing()
        if not ADKP_DialogPositions then ADKP_DialogPositions = {} end
        local x, y = dialog:GetLeft(), dialog:GetTop()
        ADKP_DialogPositions["ADKP_LootItemDialog"] = {x = x, y = y}
    end)

	-- 设置标题
    dialog.title = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    dialog.title:SetPoint("TOP", dialog, "TOP", 0, -15)
    dialog.title:SetText("修改装备记录")

    -- 「装备名称」标签 + 输入框
    local itemLabel = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    itemLabel:SetPoint("TOPLEFT", dialog, "TOPLEFT", 20, -40)
    itemLabel:SetText("装备名称:")
    dialog.itemEditBox = CreateFrame("EditBox", "ADKP_LootItemEditBox"..GetTime(), dialog, "InputBoxTemplate")
    dialog.itemEditBox:SetWidth(dialog:GetWidth() - 60)
    dialog.itemEditBox:SetHeight(24)
    dialog.itemEditBox:SetPoint("TOPLEFT", itemLabel, "BOTTOMLEFT", 10, -4)
    dialog.itemEditBox:SetMaxLetters(50)
    dialog.itemEditBox:SetText(currentItem)
    dialog.itemEditBox:SetAutoFocus(false)
    dialog.itemEditBox:SetScript("OnEscapePressed", function()
        dialog.itemEditBox:ClearFocus()
    end)
    -- 在装备名输入框按 Enter → 跳到分值输入框
    dialog.itemEditBox:SetScript("OnEnterPressed", function()
        if dialog.costEditBox then dialog.costEditBox:SetFocus() end
    end)

    -- 「分值」标签 + 输入框
    local costLabel = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    costLabel:SetPoint("TOPLEFT", dialog.itemEditBox, "BOTTOMLEFT", -10, -8)
    costLabel:SetText("分值（花费，正数即可）:")
    dialog.costEditBox = CreateFrame("EditBox", "ADKP_LootCostEditBox"..GetTime(), dialog, "InputBoxTemplate")
    dialog.costEditBox:SetWidth(dialog:GetWidth() - 60)
    dialog.costEditBox:SetHeight(24)
    dialog.costEditBox:SetPoint("TOPLEFT", costLabel, "BOTTOMLEFT", 10, -4)
    dialog.costEditBox:SetMaxLetters(10)
    -- 显示绝对值（用户友好：输入正数即可，函数内部会转成负数）
    local displayCost = tostring(math.abs(tonumber(currentCost) or 0))
    dialog.costEditBox:SetText(displayCost)
    dialog.costEditBox:SetAutoFocus(false)
    dialog.costEditBox:SetScript("OnEscapePressed", function()
        dialog.costEditBox:ClearFocus()
    end)
    -- 在分值输入框按 Enter → 触发确定
    dialog.costEditBox:SetScript("OnEnterPressed", function()
        if dialog.okButton then dialog.okButton:Click() end
    end)

    -- 统一的提交逻辑
    local function commitEdit()
        local newItemName = dialog.itemEditBox:GetText()
        local newCost = dialog.costEditBox:GetText()
        if not newItemName or newItemName == "" then
            ADKP_Print("错误：装备名称不能为空")
            return
        end
        if not newCost or newCost == "" then
            ADKP_Print("错误：分值不能为空")
            return
        end
        ADKP_EditLootRecord(uniqueId, newItemName, newCost, logKey)
        ADKP_UpdateTable()
        if ADKP_Refresh then ADKP_Refresh() end
        ADKP_UpdateLootList()
        dialog:Hide()
    end

	-- 创建确定按钮
    dialog.okButton = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
    dialog.okButton:SetWidth(100)
    dialog.okButton:SetHeight(25)
    dialog.okButton:SetPoint("BOTTOMLEFT", dialog, "BOTTOMLEFT", 20, 10)
    dialog.okButton:SetText("确定")
    dialog.okButton:SetScript("OnClick", commitEdit)

	-- 创建取消按钮
    dialog.cancelButton = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
    dialog.cancelButton:SetWidth(100)
    dialog.cancelButton:SetHeight(25)
    dialog.cancelButton:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -20, 10)
    dialog.cancelButton:SetText("取消")
    dialog.cancelButton:SetScript("OnClick", function()
        dialog:Hide()
    end)

	-- 设置ESC键关闭对话框
    dialog:EnableKeyboard(true)
    dialog:SetScript("OnKeyDown", function()
        if arg1 == "ESCAPE" then
            dialog:Hide()
        end
    end)

	-- 保存到全局变量
    ADKP_LootItemDialog = dialog
    dialog:Show()

    -- 默认聚焦装备名输入框（光标定位到末尾）
    dialog.itemEditBox:SetFocus()
    dialog.itemEditBox:HighlightText()
end

-- 显示修改替补记录对话框的函数
function ADKP_ShowEditSubstituteDialog(uniqueId, currentReason, currentPoints)
	-- 首先查找当前记录的原因和分数
    local logPoints = currentPoints -- 默认使用传入的分数
    if WebDKP_Log then
        for _, logEntry in pairs(WebDKP_Log) do
            if type(logEntry) == "table" and logEntry.uniqueId and logEntry.uniqueId == uniqueId then
                currentReason = logEntry.reason or "替补记录"
                logPoints = tonumber(logEntry.points) or currentPoints -- 优先使用日志中的分数
                break
            end
        end
    end
    
	-- 显示第一个对话框（输入原因）
    ADKP_ShowCustomSubstituteReasonDialog(uniqueId, currentReason, logPoints)
end

-- 自定义替补记录原因输入对话框
function ADKP_ShowCustomSubstituteReasonDialog(uniqueId, currentReason, currentPoints)
	-- 如果对话框已经存在，则销毁它
    if ADKP_SubstituteReasonDialog then
        ADKP_SubstituteReasonDialog:Hide()
        ADKP_SubstituteReasonDialog = nil
    end
    
	-- 创建新的对话框（不使用BasicFrameTemplate）
    local dialog = CreateFrame("Frame", "ADKP_SubstituteReasonDialog", UIParent)
     dialog:SetWidth(260)
    dialog:SetHeight(150)
    
	-- 加载保存的窗口位置，如果没有则居中显示
    if ADKP_DialogPositions and ADKP_DialogPositions["ADKP_SubstituteReasonDialog"] then
        local pos = ADKP_DialogPositions["ADKP_SubstituteReasonDialog"]
        dialog:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", pos.x, pos.y)
    else
        dialog:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
    
    dialog:SetFrameStrata("DIALOG")
    
	-- 设置背景和边框
    dialog:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    dialog:SetBackdropColor(0, 0, 0, 0.8)
    
    dialog:SetMovable(true)
    dialog:EnableMouse(true)
    dialog:SetScript("OnMouseDown", function() 
        dialog:StartMoving() 
    end)
    dialog:SetScript("OnMouseUp", function() 
        dialog:StopMovingOrSizing() 
        -- 保存窗口位置
        if not ADKP_DialogPositions then
            ADKP_DialogPositions = {}
        end
        local x, y = dialog:GetLeft(), dialog:GetTop()
        ADKP_DialogPositions["ADKP_SubstituteReasonDialog"] = {x = x, y = y}
    end)
    
	-- 设置标题
    dialog.title = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    dialog.title:SetPoint("TOP", dialog, "TOP", 0, -15)
    dialog.title:SetText("修改替补记录")
    

        -- 创建信息文本
    local infoText = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    infoText:SetPoint("TOP", dialog, "TOP", 0, -40)
    infoText:SetWidth(dialog:GetWidth() - 40)
    infoText:SetJustifyH("LEFT")
    infoText:SetText("当前原因: " .. currentReason .. "\n当前分数: " .. tostring(currentPoints) .. "\n请输入新原因:")

	-- 创建输入框（带唯一名称）
    dialog.reasonEditBox = CreateFrame("EditBox", "ADKP_SubstituteReasonEditBox"..GetTime(), dialog, "InputBoxTemplate")
    dialog.reasonEditBox:SetWidth(dialog:GetWidth() - 60)
    dialog.reasonEditBox:SetHeight(24)
    dialog.reasonEditBox:SetPoint("TOPLEFT", infoText, "BOTTOMLEFT", 10, -10)
    dialog.reasonEditBox:SetMaxLetters(100)
    dialog.reasonEditBox:SetText(currentReason)
    dialog.reasonEditBox:SetAutoFocus(true)
    
	-- 修复ESC键退出输入状态
    dialog.reasonEditBox:SetScript("OnEscapePressed", function() 
        dialog.reasonEditBox:ClearFocus() 
        dialog:EnableKeyboard(true)
    end)
    
    dialog.reasonEditBox:SetScript("OnEnterPressed", function() 
        local newReason = dialog.reasonEditBox:GetText()
        if newReason and newReason ~= "" then
            -- 显示第二个对话框输入分数
            ADKP_ShowCustomSubstitutePointsDialog(uniqueId, newReason, currentPoints)
        end
    end)
    
	-- 添加焦点获取和失去事件
    dialog.reasonEditBox:SetScript("OnEditFocusGained", function() 
        dialog:EnableKeyboard(false)
    end)
    
    dialog.reasonEditBox:SetScript("OnEditFocusLost", function() 
        dialog:EnableKeyboard(true)
    end)
    
	-- 创建下一步按钮
    dialog.nextButton = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
    dialog.nextButton:SetWidth(100)
    dialog.nextButton:SetHeight(25)
    dialog.nextButton:SetPoint("BOTTOMLEFT", dialog, "BOTTOMLEFT", 20, 10)
    dialog.nextButton:SetText("下一步")
    dialog.nextButton:SetScript("OnClick", function()
        local newReason = dialog.reasonEditBox:GetText()
        if newReason and newReason ~= "" then
            -- 显示第二个对话框输入分数
            ADKP_ShowCustomSubstitutePointsDialog(uniqueId, newReason, currentPoints)
        end
    end)
    
	-- 创建取消按钮
    dialog.cancelButton = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
    dialog.cancelButton:SetWidth(100)
    dialog.cancelButton:SetHeight(25)
    dialog.cancelButton:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -20, 10)
    dialog.cancelButton:SetText("取消")
    dialog.cancelButton:SetScript("OnClick", function()
        dialog:Hide()
    end)
    
	-- 设置ESC键关闭对话框
    dialog:EnableKeyboard(true)
    dialog:SetScript("OnKeyDown", function()
        if arg1 == "ESCAPE" then
            if dialog.reasonEditBox.HasFocus and dialog.reasonEditBox:HasFocus() then
                dialog.reasonEditBox:ClearFocus()
            else
                dialog:Hide()
            end
        end
    end)
    
	-- 保存到全局变量
    ADKP_SubstituteReasonDialog = dialog
    dialog:Show()
    
	-- 防止输入框在显示时失去焦点
    dialog.reasonEditBox:SetFocus()
end

-- 自定义替补记录分数输入对话框
function ADKP_ShowCustomSubstitutePointsDialog(uniqueId, newReason, currentPoints)
	-- 如果对话框已经存在，则销毁它
    if ADKP_SubstitutePointsDialog then
        ADKP_SubstitutePointsDialog:Hide()
        ADKP_SubstitutePointsDialog = nil
    end
    
	-- 如果上一个对话框存在，隐藏它
    if ADKP_SubstituteReasonDialog then
        ADKP_SubstituteReasonDialog:Hide()
    end
    
	-- 创建新的对话框（不使用BasicFrameTemplate）
    local dialog = CreateFrame("Frame", "ADKP_SubstitutePointsDialog", UIParent)
    dialog:SetWidth(260)
    dialog:SetHeight(150)
    
	-- 加载保存的窗口位置，如果没有则居中显示
    if ADKP_DialogPositions and ADKP_DialogPositions["ADKP_SubstitutePointsDialog"] then
        local pos = ADKP_DialogPositions["ADKP_SubstitutePointsDialog"]
        dialog:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", pos.x, pos.y)
    else
        dialog:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
    
    dialog:SetFrameStrata("DIALOG")
    
	-- 设置背景和边框
    dialog:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    dialog:SetBackdropColor(0, 0, 0, 0.8)
    
    dialog:SetMovable(true)
    dialog:EnableMouse(true)
    dialog:SetScript("OnMouseDown", function() dialog:StartMoving() end)
    dialog:SetScript("OnMouseUp", function() 
        dialog:StopMovingOrSizing()
        -- 保存窗口位置
        if not ADKP_DialogPositions then
            ADKP_DialogPositions = {}
        end
        local x, y = dialog:GetLeft(), dialog:GetTop()
        ADKP_DialogPositions["ADKP_SubstitutePointsDialog"] = {x = x, y = y}
    end)
    
	-- 设置标题
    dialog.title = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    dialog.title:SetPoint("TOP", dialog, "TOP", 0, -15)
    dialog.title:SetText("修改替补记录")
    
        -- 创建信息文本
    local infoText = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    infoText:SetPoint("TOP", dialog, "TOP", 0, -40)
    infoText:SetWidth(dialog:GetWidth() - 40)
    infoText:SetJustifyH("LEFT")
    infoText:SetText("新原因: " .. newReason .. "\n当前分数: " .. tostring(currentPoints) .. "\n请输入新分数:")


	-- 创建输入框（带唯一名称）
    dialog.pointsEditBox = CreateFrame("EditBox", "ADKP_SubstitutePointsEditBox"..GetTime(), dialog, "InputBoxTemplate")
    dialog.pointsEditBox:SetWidth(dialog:GetWidth() - 60)
    dialog.pointsEditBox:SetHeight(24)
    dialog.pointsEditBox:SetPoint("TOPLEFT", infoText, "BOTTOMLEFT", 10, -10)
    dialog.pointsEditBox:SetMaxLetters(10)
    dialog.pointsEditBox:SetText(tostring(currentPoints))
    dialog.pointsEditBox:SetAutoFocus(true)
	-- 修复ESC键退出输入状态
    dialog.pointsEditBox:SetScript("OnEscapePressed", function() 
        dialog.pointsEditBox:ClearFocus() 
        dialog:EnableKeyboard(true)
    end)
    
	-- 添加焦点获取和失去事件
    dialog.pointsEditBox:SetScript("OnEditFocusGained", function() 
        dialog:EnableKeyboard(false)
    end)
    
    dialog.pointsEditBox:SetScript("OnEditFocusLost", function() 
        dialog:EnableKeyboard(true)
    end)
    dialog.pointsEditBox:SetScript("OnEnterPressed", function() 
        local newPoints = dialog.pointsEditBox:GetText()
        ADKP_EditSubstituteRecord(uniqueId, newReason, newPoints)
        -- 修改分数后刷新界面，相当于按了刷新队伍
        ADKP_UpdateTable()
        ADKP_UpdateLootList()
        dialog:Hide()
    end)
    
	-- 创建确定按钮
    dialog.okButton = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
    dialog.okButton:SetWidth(100)
    dialog.okButton:SetHeight(25)
    dialog.okButton:SetPoint("BOTTOMLEFT", dialog, "BOTTOMLEFT", 20, 10)
    dialog.okButton:SetText("确定")
    dialog.okButton:SetScript("OnClick", function()
        local newPoints = dialog.pointsEditBox:GetText()
        ADKP_EditSubstituteRecord(uniqueId, newReason, newPoints)
        -- 修改分数后刷新界面，相当于按了刷新队伍
        ADKP_UpdateTable()
        ADKP_Refresh()
        ADKP_UpdateLootList()
        dialog:Hide()
    end)
    
	-- 创建取消按钮
    dialog.cancelButton = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
    dialog.cancelButton:SetWidth(100)
    dialog.cancelButton:SetHeight(25)
    dialog.cancelButton:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -20, 10)
    dialog.cancelButton:SetText("取消")
    dialog.cancelButton:SetScript("OnClick", function()
        dialog:Hide()
    end)
    
	-- 设置ESC键关闭对话框
    dialog:EnableKeyboard(true)
    dialog:SetScript("OnKeyDown", function()
        if arg1 == "ESCAPE" then
            if dialog.pointsEditBox.HasFocus and dialog.pointsEditBox:HasFocus() then
                dialog.pointsEditBox:ClearFocus()
            else
                dialog:Hide()
            end
        end
    end)
    
	-- 保存到全局变量
    ADKP_SubstitutePointsDialog = dialog
    dialog:Show()
    
	-- 防止输入框在显示时失去焦点
    dialog.pointsEditBox:SetFocus()
end

-- =========================================================================
-- Antigravity Added Helpers and Click Handlers
-- =========================================================================

function ADKP_UpdateSingleAdjustLabel()
    local raidCount = 0
    local subCount = 0
    local otherCount = 0
    local totalCount = 0
    if WebDKP_DkpTable then
        for k, v in pairs(WebDKP_DkpTable) do
            if type(v) == "table" and v["Selected"] then
                totalCount = totalCount + 1
                if ADKP_PlayerInGroup and ADKP_PlayerInGroup(k) then
                    raidCount = raidCount + 1
                elseif ADKP_IsSubRosterMember and ADKP_IsSubRosterMember(k) then
                    subCount = subCount + 1
                else
                    otherCount = otherCount + 1
                end
            end
        end
    end

    if ADKP_SingleAdjustFrameCharName then
        if totalCount == 0 then
            ADKP_SingleAdjustFrameCharName:SetText("未选择任何玩家")
        else
            local display = "团队:" .. raidCount .. "人  替补:" .. subCount .. "人"
            if otherCount > 0 then
                display = display .. "  其他:" .. otherCount .. "人"
            end
            ADKP_SingleAdjustFrameCharName:SetText(display)
        end
    end
end

function ADKP_SingleAdjust_OnClick(mode)
    local pointsText = ""
    if ADKP_SingleAdjustFramePoints then
        pointsText = ADKP_SingleAdjustFramePoints:GetText() or ""
    end
    local points = tonumber(pointsText)
    if (not points) or (points < 0) then
        ADKP_Print("请输入有效的分数（0 或正数）！")
        return
    end
    local reason = ""
    if ADKP_SingleAdjustFrameReason then
        reason = ADKP_SingleAdjustFrameReason:GetText() or ""
    end
    if reason == "" then reason = "手动调分" end
    if mode == "minus" then points = -points end

    local fullPlayers = {}
    local fullCount = 0
    if WebDKP_DkpTable then
        for k, v in pairs(WebDKP_DkpTable) do
            if type(v) == "table" and v["Selected"] then
                fullPlayers[fullCount] = { ["name"] = k, ["class"] = v["class"] or "未知" }
                fullCount = fullCount + 1
            end
        end
    end

    if fullCount == 0 then
        ADKP_Print("错误：请先在列表中选中要调分的玩家！")
        return
    end

    ADKP_AddDKP(points, reason, "false", fullPlayers)

    if ADKP_AnnounceAward then 
        ADKP_AnnounceAward(points, reason) 
    end
    ADKP_Print("已对选中的 " .. fullCount .. " 位玩家调分: " .. tostring(points) .. " 分 / 原因: " .. reason)
    if ADKP_SingleAdjustFramePoints then 
        ADKP_SingleAdjustFramePoints:SetText("") 
    end
    if ADKP_UnselectAll then
        ADKP_UnselectAll()
    end
    if ADKP_UpdateTableToShow then ADKP_UpdateTableToShow() end
    if ADKP_UpdateTable then ADKP_UpdateTable() end
end

function ADKP_SingleAdjust_Spin(delta)
    local cur = tonumber(ADKP_SingleAdjustFramePoints:GetText()) or 0
    cur = cur + delta
    if cur < 0 then cur = 0 end
    ADKP_SingleAdjustFramePoints:SetText(tostring(cur))
end

function ADKP_UpdateModeButtons()
    local m = ADKP_ListMode or "raid"
    if ADKP_FrameModeRaid then if m == "raid" then ADKP_FrameModeRaid:Disable() else ADKP_FrameModeRaid:Enable() end end
    if ADKP_FrameModeSub then if m == "sub" then ADKP_FrameModeSub:Disable() else ADKP_FrameModeSub:Enable() end end
    if ADKP_FrameModeOut then if m == "out" then ADKP_FrameModeOut:Disable() else ADKP_FrameModeOut:Enable() end end
end

function ADKP_SetListMode(mode)
    ADKP_ListMode = mode
    ADKP_SubQueryTimeoutEmpty = nil
    if mode == "raid" or mode == "out" then
        ADKP_UpdatePlayersInGroup()
    end
    ADKP_UpdateModeButtons()
    ADKP_UpdateTableToShow()
    ADKP_UpdateTable()
end

-- 点击「替补团队」标签时自动强制刷新替补名单
-- 超时未响应则弹确认窗：「替补队长超时未响应，是否清除替补人员名单」
function ADKP_SwitchToSubMode()
    ADKP_SetListMode("sub")
    ADKP_SubQueryTimeoutEmpty = nil

    -- 获取替补队长
    local captain = ""
    if ADKP_ResolveSubCaptain then
        captain = ADKP_ResolveSubCaptain()
    else
        captain = ADKP_GetSubCaptain(ADKP_GetTableid())
    end
    if captain == "" then return end  -- 无替补队长，仅切换显示

    -- 检查是否原本有替补成员
    local hasMembers = false
    if ADKP_SubSync_Cache then
        local c = ADKP_SubSync_Cache[string.lower(captain)]
        if c and c.members then
            for _, _ in pairs(c.members) do
                hasMembers = true
                break
            end
        end
    end
    if not hasMembers and ADKP_PendingSubMembers then
        local tbl = ADKP_PendingSubMembers[captain] or ADKP_PendingSubMembers[string.lower(captain)]
        if tbl then
            for _, _ in pairs(tbl) do
                hasMembers = true
                break
            end
        end
    end

    -- 初始化 StaticPopup
    if not StaticPopupDialogs["ADKP_SUB_TIMEOUT_CONFIRM"] then
        StaticPopupDialogs["ADKP_SUB_TIMEOUT_CONFIRM"] = {
            text = "替补队长超时未响应，是否清除替补人员名单？",
            button1 = "清除",
            button2 = "保留",
            timeout = 0,
            whileDead = 1,
            hideOnEscape = 1,
            OnAccept = function()
                local dlg = StaticPopupDialogs["ADKP_SUB_TIMEOUT_CONFIRM"]
                local cap = dlg and dlg._captain or ""
                -- 清除 SubSync 缓存
                if ADKP_SubSync_Cache and cap ~= "" then
                    ADKP_SubSync_Cache[string.lower(cap)] = nil
                end
                -- 清除 PendingSubMembers
                if ADKP_PendingSubMembers and cap ~= "" then
                    ADKP_PendingSubMembers[cap] = nil
                    ADKP_PendingSubMembers[string.lower(cap)] = nil
                end
                ADKP_UpdateTableToShow()
                ADKP_UpdateTable()
                ADKP_Print("[ADKP] 替补人员名单已清除。")
            end,
        }
    end

    -- 准备查询
    if not ADKP_SubAwardData then ADKP_SubAwardData = {} end
    ADKP_SubAwardData.captain = captain
    ADKP_SubAwardData.receivedResponse = false

    -- 强制向替补队长发起实时查询
    ADKP_SubSync_ForceQuery = true
    if ADKP_SearchSubMembers_Event then
        ADKP_SearchSubMembers_Event()
    end

    local waitFrame = CreateFrame("Frame")
    waitFrame.startTime = GetTime()
    waitFrame:SetScript("OnUpdate", function()
        local frame = this or waitFrame
        local elapsed = GetTime() - (frame.startTime or 0)
        local responded = ADKP_SubAwardData and ADKP_SubAwardData.receivedResponse
        if responded then
            frame:SetScript("OnUpdate", nil)
            ADKP_SubSync_ForceQuery = false
            ADKP_SubQueryTimeoutEmpty = nil
            ADKP_UpdateTableToShow()
            ADKP_UpdateTable()
        elseif elapsed >= 2 then
            frame:SetScript("OnUpdate", nil)
            ADKP_SubSync_ForceQuery = false
            if hasMembers then
                -- 原来有替补人员：弹确认窗
                StaticPopupDialogs["ADKP_SUB_TIMEOUT_CONFIRM"]._captain = captain
                StaticPopup_Show("ADKP_SUB_TIMEOUT_CONFIRM")
            else
                -- 原来没有替补人员：不弹窗，直接在列表显示提示信息
                ADKP_SubQueryTimeoutEmpty = true
                ADKP_UpdateTableToShow()
                ADKP_UpdateTable()
            end
        end
    end)
end

function ADKP_IsSubRosterMember(name)
    local cap = ADKP_GetSubCaptain(ADKP_GetTableid())
    if cap == "" then return false end
    if not ADKP_SubSync_Cache then return false end
    local c = ADKP_SubSync_Cache[string.lower(cap)]
    if not c or not c.members then return false end
    for memberName, _ in pairs(c.members) do
        if memberName == name then return true end
    end
    return false
end

-- 同步 Boss 击杀加分总开关与二选一模式，沿用旧配置字段以保留用户设置。
function ADKP_SyncBossAwardControls()
    local enabled = not WebDKP_Options or WebDKP_Options["BossDeathPopup"] ~= false
    local autoAward = WebDKP_Options and WebDKP_Options["BossAutoAward"] and true or false
    if ADKP_AwardDKP_FrameToggleAutoAward then
        ADKP_AwardDKP_FrameToggleAutoAward:SetChecked(enabled)
    end
    local modes = {
        { frame = ADKP_AwardDKP_FrameBossAwardConfirm, checked = not autoAward },
        { frame = ADKP_AwardDKP_FrameToggleBossAutoAward, checked = autoAward }
    }
    for _, mode in ipairs(modes) do
        if mode.frame then
            mode.frame:SetChecked(mode.checked)
            if enabled then
                mode.frame:Enable()
                mode.frame:SetAlpha(1)
            else
                mode.frame:Disable()
                mode.frame:SetAlpha(0.5)
            end
        end
    end
end

-- 设置页：每次显示及切换团队时刷新控件状态。
function ADKP_Tab1_SyncChecks()
    if ADKP_SettingsAutoBackupCheck then
        ADKP_SettingsAutoBackupCheck:SetChecked(WebDKP_Options and WebDKP_Options["AutoBackupEnabled"] and true or false)
    end
    if ADKP_UpdateBackupRecoveryStatus then ADKP_UpdateBackupRecoveryStatus() end
    if ADKP_AwardDKP_FrameSubCaptainChk then
        ADKP_AwardDKP_FrameSubCaptainChk:SetChecked(WebDKP_Options and WebDKP_Options["IncludeSubCaptain"] and true or false)
    end
    if ADKP_AwardDKP_FrameSubLeaderInput then
        ADKP_AwardDKP_FrameSubLeaderInput:SetText(ADKP_GetSubCaptain(ADKP_GetTableid()))
    end
    -- 功能设置区（从系统设置迁入）勾选状态恢复
    ADKP_SyncBossAwardControls()
    if ADKP_AwardDKP_FrameToggleRaidDkpReply then
        ADKP_AwardDKP_FrameToggleRaidDkpReply:SetChecked(WebDKP_Options and WebDKP_Options["RaidDkpReply"] and true or false)
    end
    if ADKP_AwardDKP_FrameToggleSilentMode then
        ADKP_AwardDKP_FrameToggleSilentMode:SetChecked(WebDKP_Options and WebDKP_Options["SilentMode"] and true or false)
    end
    if ADKP_AwardDKP_FrameToggleKeepOnline then
        ADKP_AwardDKP_FrameToggleKeepOnline:SetChecked(WebDKP_Options and WebDKP_Options["KeepOnlineEnabled"] and true or false)
    end
    if ADKP_AwardDKP_FrameToggleAutofill then
        ADKP_AwardDKP_FrameToggleAutofill:SetChecked(WebDKP_WebOptions and WebDKP_WebOptions["AutofillEnabled"] == 1)
    end
    if ADKP_AwardDKP_FrameToggleQuickFloatEnabled then
        ADKP_AwardDKP_FrameToggleQuickFloatEnabled:SetChecked(WebDKP_Options and WebDKP_Options["QuickFloatEnabled"] and true or false)
    end
    -- 密语组人 / 自动转团 勾选状态恢复（与 Options_Init 保持一致，确保每次打开设置页都同步）
    if ADKP_AwardDKP_FrameToggleAutoInvite then
        ADKP_AwardDKP_FrameToggleAutoInvite:SetChecked(WebDKP_Options and WebDKP_Options["AutoInviteEnabled"] and true or false)
    end
    if ADKP_AwardDKP_FrameToggleAutoConvertRaid then
        ADKP_AwardDKP_FrameToggleAutoConvertRaid:SetChecked(WebDKP_Options and WebDKP_Options["AutoConvertRaid"] and true or false)
    end
    if ADKP_AwardDKP_FrameAutoInviteKeyword and WebDKP_Options then
        ADKP_AwardDKP_FrameAutoInviteKeyword:SetText(WebDKP_Options["AutoInviteKeyword"] or "9527")
    end
    -- 拍卖模式勾选状态恢复（每次打开设置页时同步）
    if WebDKP_Options and WebDKP_Options["AuctionMode"] then
        if ADKP_AwardDKP_FrameAuctionPublic then
            ADKP_AwardDKP_FrameAuctionPublic:SetChecked(WebDKP_Options["AuctionMode"] ~= "anonymous")
        end
        if ADKP_AwardDKP_FrameAuctionAnonymous then
            ADKP_AwardDKP_FrameAuctionAnonymous:SetChecked(WebDKP_Options["AuctionMode"] == "anonymous")
        end
    end
end

function ADKP_Tab1_SaveSubCaptain()
    local txt = ""
    if ADKP_AwardDKP_FrameSubLeaderInput then
        txt = ADKP_AwardDKP_FrameSubLeaderInput:GetText() or ""
    end
    txt = string.gsub(txt, "^%s+", "")
    txt = string.gsub(txt, "%s+$", "")
    -- 按当前团保存替补队长
    ADKP_SetSubCaptain(ADKP_GetTableid(), txt)
    WebDKP_Options["SubLeader"] = txt
    if ADKP_UpdateCaptainLabel then ADKP_UpdateCaptainLabel() end
    if ADKP_AwardDKP_FrameSubCaptainLabel then
        local disp = "无"
        if txt ~= "" then disp = txt end
        ADKP_AwardDKP_FrameSubCaptainLabel:SetText("替补队长: " .. disp)
    end
    if txt ~= "" then
        ADKP_Print("已设置替补队长: " .. txt)
    else
        ADKP_Print("已清空替补队长。")
    end
end

function ADKP_DoImportInitial(text)
    if not text or text == "" then
        ADKP_Print("导入内容为空！")
        return
    end

    local function proceedWithImport()
        local tableid = ADKP_GetTableid()
        local dkpField = "dkp_" .. tableid
        -- 只清当前团的数据：删除所有玩家的 dkp_<tableid> 字段
        if WebDKP_DkpTable then
            for playerName, data in pairs(WebDKP_DkpTable) do
                if type(data) == "table" then
                    data[dkpField] = nil
                    data["dkp" .. tableid] = nil  -- 兼容历史无下划线变体
                end
            end
        end
        -- 只清当前团的日志记录（tableid 匹配；旧数据无 tableid 归到 1）
        if WebDKP_Log then
            local toDelete = {}
            for logKey, entry in pairs(WebDKP_Log) do
                if logKey ~= "Version" and type(entry) == "table" then
                    local entryTable = entry.tableid or 1
                    if entryTable == tableid then
                        table.insert(toDelete, logKey)
                    end
                end
            end
            for i = 1, table.getn(toDelete) do
                WebDKP_Log[toDelete[i]] = nil
            end
        end
        if not WebDKP_DkpTable then WebDKP_DkpTable = {} end
        if not WebDKP_Log then WebDKP_Log = {} end
        local count = 0
        for line in string.gfind(text, "[^\r\n]+") do
            local ln = string.gsub(line, "^%s+", "")
            ln = string.gsub(ln, "%s+$", "")
            if ln ~= "" then
                local fields = {}
                for field in string.gfind(ln, "[^,]+") do
                    local fv = string.gsub(field, "^%s+", "")
                    fv = string.gsub(fv, "%s+$", "")
                    table.insert(fields, fv)
                end
                local name = fields[1]
                if name and name ~= "" then
                    local firstByte = string.byte(name, 1)
                    if firstByte and firstByte >= 97 and firstByte <= 122 then
                        name = string.char(firstByte - 32) .. string.sub(name, 2)
                    end
                end
                local class = fields[2] or "未知"
                local dkp = tonumber(fields[3]) or 0
                if name and name ~= "" then
                    local enClass = class
                    if ADKP_NormalizeClassName then enClass = ADKP_NormalizeClassName(class) end
                    if not WebDKP_DkpTable[name] then WebDKP_DkpTable[name] = {} end
                    WebDKP_DkpTable[name]["dkp_" .. tableid] = dkp
                    WebDKP_DkpTable[name]["class"] = enClass
                    count = count + 1
                end
            end
        end
        if ADKP_Share_ApplyWebsiteList then
            ADKP_Share_ApplyWebsiteList(text)
        end
        ADKP_Print("已导入 " .. count .. " 条初始分。")
        if ADKP_ResumeAutoBackup then ADKP_ResumeAutoBackup(tableid) end
        if ADKP_SaveToDisk then ADKP_SaveToDisk() end
        if ADKP_UpdateTableToShow then ADKP_UpdateTableToShow() end
        if ADKP_UpdateTable then ADKP_UpdateTable() end
        if ADKP_UpdateLootList then ADKP_UpdateLootList() end
        if ADKP_ImportInitialFrame then ADKP_ImportInitialFrame:Hide() end
    end

    if not StaticPopupDialogs then
        StaticPopupDialogs = {}
    end
    if not StaticPopupDialogs["ADKP_IMPORT_INITIAL_CONFIRM"] then
        StaticPopupDialogs["ADKP_IMPORT_INITIAL_CONFIRM"] = {
            text = "注意：历史数据将被全部清空并替换成导入数据！！",
            button1 = "确定",
            button2 = "取消",
            OnAccept = function()
                local dialog = StaticPopupDialogs["ADKP_IMPORT_INITIAL_CONFIRM"]
                if dialog and dialog._confirmCallback then
                    dialog._confirmCallback()
                end
            end,
            timeout = 0,
            whileDead = 1,
            hideOnEscape = 1,
            preferredIndex = 3,  -- Fix 4: 固定 slot，避免随机分配导致与其他弹窗冲突
        }
    end
    StaticPopupDialogs["ADKP_IMPORT_INITIAL_CONFIRM"].text = "注意：历史数据将被全部清空并替换成导入数据！！"
    StaticPopupDialogs["ADKP_IMPORT_INITIAL_CONFIRM"]._confirmCallback = proceedWithImport
    -- Fix 2: 弹窗显示前确保 EditBox 失去焦点，防止 Enter 键冒泡到 StaticPopup button1
    if ADKP_ImportInitialEdit then
        ADKP_ImportInitialEdit:ClearFocus()
    end
    StaticPopup_Show("ADKP_IMPORT_INITIAL_CONFIRM")
end

function ADKP_ShowImportInitial()
    if not ADKP_ImportInitialFrame then
        local f = CreateFrame("Frame", "ADKP_ImportInitialFrame", UIParent)
        f:SetWidth(420)
        f:SetHeight(380)
        f:SetPoint("CENTER", 0, 0)
        f:SetFrameStrata("DIALOG")
        f:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", tile = true, tileSize = 32, edgeSize = 32, insets = { left = 11, right = 12, top = 12, bottom = 11 } })
        f:EnableMouse(true)
        f:SetMovable(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", function() this:StartMoving() end)
        f:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
        local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOP", 0, -16)
        title:SetText("导入初始分")
        local hint = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        hint:SetPoint("TOPLEFT", 20, -40)
        hint:SetText("每行一条：角色ID,职业,初始分")
        -- 可见的"输入框"容器：背景和边框放在这个不滚动的 Frame 上，
        -- 不能放在 EditBox 上（EditBox 是 ScrollFrame 的滚动子，背景会随文本一起滚动）。
        local inputBg = CreateFrame("Frame", nil, f)
        inputBg:SetPoint("TOPLEFT", 18, -58)
        inputBg:SetPoint("BOTTOMRIGHT", -36, 48)
        inputBg:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 }
        })
        inputBg:SetBackdropColor(0, 0, 0, 0.9)
        inputBg:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
        local sf = CreateFrame("ScrollFrame", "ADKP_ImportInitialScroll", inputBg, "UIPanelScrollFrameTemplate")
        sf:SetPoint("TOPLEFT", 8, -8)
        sf:SetPoint("BOTTOMRIGHT", -28, 8)
        local eb = CreateFrame("EditBox", "ADKP_ImportInitialEdit", sf)
        eb:SetMultiLine(true)
        eb:SetAutoFocus(false)
        eb:SetMaxLetters(0)
        eb:SetFontObject(ChatFontNormal)
        eb:SetJustifyH("LEFT")
        eb:SetJustifyV("TOP")
        eb:SetTextInsets(4, 4, 4, 4)
        -- 关键：EditBox 自身必须带 Backdrop（含 bgFile），否则 WoW 1.12 的多行
        -- EditBox 只对已渲染字符的像素响应点击，空白区域无法点入编辑模式。
        -- 这里给 EditBox 一个纯 bgFile（不带 edgeFile），并把背景色设成与下层
        -- inputBg 完全一致，这样 EditBox 即便随滚动位移也和 inputBg 融为一体，
        -- 看不出边界移动；可见边框仍由不滚动的 inputBg 提供。
        eb:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            tile = true, tileSize = 16
        })
        eb:SetBackdropColor(0, 0, 0, 0.9)
        eb:SetScript("OnEscapePressed", function() this:ClearFocus() end)
        -- Fix 1: 拦截 Enter 键，插入换行而非让事件冒泡到 StaticPopup button1（"确定"）
        -- WoW 1.12 中多行 EditBox 若不处理 OnEnterPressed，Enter 键事件会继续
        -- 向上冒泡，当恰好有 StaticPopup 弹出时会立即触发"确定"按钮。
        eb:SetScript("OnEnterPressed", function()
            this:Insert("\n")
        end)
        -- Fix 3: 先 SetScrollChild，再设 EditBox 尺寸。
        -- WoW 1.12 下如果在 SetScrollChild 之前调用 SetWidth/SetHeight，
        -- ScrollFrame 无法正确感知内容尺寸，可能导致可视区域显示为空白。
        sf:SetScrollChild(eb)
        eb:SetWidth(330)
        -- 初始高度略小于 ScrollFrame 可视区（约258px），避免滚动条在空文本时立即出现
        eb:SetHeight(240)
        -- 根据换行数量动态增高 EditBox，让 ScrollFrame 在长文本粘贴时出现滚动条
        eb:SetScript("OnTextChanged", function()
            local _, lineCount = string.gsub(this:GetText() or "", "\n", "\n")
            local need = math.max(240, (lineCount + 1) * 16)
            if math.abs((this:GetHeight() or 0) - need) > 1 then
                this:SetHeight(need)
            end
        end)
        local doBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        doBtn:SetWidth(100)
        doBtn:SetHeight(24)
        doBtn:SetPoint("BOTTOMLEFT", 24, 14)
        doBtn:SetText("导入")
        doBtn:SetScript("OnClick", function() ADKP_DoImportInitial(ADKP_ImportInitialEdit:GetText()) end)
        local closeBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        closeBtn:SetWidth(100)
        closeBtn:SetHeight(24)
        closeBtn:SetPoint("BOTTOMRIGHT", -24, 14)
        closeBtn:SetText("关闭")
        closeBtn:SetScript("OnClick", function() ADKP_ImportInitialFrame:Hide() end)
    end
    ADKP_ImportInitialEdit:SetText("")
    ADKP_ImportInitialFrame:Show()
end

function ADKP_BuildExportText()
    local currentTable = ADKP_GetTableid()
    local lines = {}
    if WebDKP_Log then
        for key, entry in pairs(WebDKP_Log) do
            if type(entry) == "table" and entry.awarded then
                -- 只导出当前团的记录（旧数据无 tableid 字段时归到 tableid=1）
                local entryTable = entry.tableid or 1
                if entryTable == currentTable then
                    local pts = ADKP_ROUND(tonumber(entry.points) or 0, 2)
                    local reason = entry.reason or ""
                    local dt = entry.date or ""
                    local d = ""
                    local t = ""
                    local s1, s2, dd, tt = string.find(dt, "(%d+-%d+-%d+)%s+(%d+:%d+:%d+)")
                    if dd then d = dd end
                    if tt then t = tt end
                    for nm, info in pairs(entry.awarded) do
                        local cls = ""
                        if type(info) == "table" and info.class then cls = info.class end
                        table.insert(lines, nm .. "," .. tostring(pts) .. "," .. reason .. "," .. d .. "," .. t .. "," .. cls)
                    end
                end
            end
        end
    end
    return table.concat(lines, "\n")
end

-- 切换导出窗口的数据格式（compact=压缩格式 / full=全量格式）
function ADKP_ExportRecords_SwitchMode(mode)
    local f = ADKP_ExportRecordsFrame
    if not f then return end
    f.currentMode = mode
    local exportText
    if mode == "full" then
        exportText = ADKP_BuildExportText()
        f.btnCompact:UnlockHighlight()
        f.btnFull:LockHighlight()
    else
        exportText = ADKP_BuildBackupCSV(false)
        f.btnFull:UnlockHighlight()
        f.btnCompact:LockHighlight()
    end
    ADKP_ExportRecordsEdit:SetText(exportText)
    local activityCount = 0
    local proposalCount = 0
    for line in string.gfind(exportText or "", "[^\r\n]+") do
        if string.find(line, "^#ADKP_SHARE_PROPOSAL") then
            proposalCount = proposalCount + 1
        else
            activityCount = activityCount + 1
        end
    end
    local label = "压缩格式"
    if mode == "full" then label = "全量格式" end
    local countText = "共 " .. activityCount .. " 条活动"
    if proposalCount > 0 then
        countText = countText .. "，附带 " .. proposalCount .. " 个大小号绑定"
    end
    f.title:SetText("导出当前记录 - " .. label .. "（" .. countText .. "）")
    ADKP_ExportRecordsEdit:SetFocus()
    ADKP_ExportRecordsEdit:HighlightText()
end

function ADKP_ShowExportRecords()
    if not ADKP_ExportRecordsFrame then
        local f = CreateFrame("Frame", "ADKP_ExportRecordsFrame", UIParent)
        f:SetWidth(460)
        f:SetHeight(420)
        f:SetPoint("CENTER", 0, 0)
        f:SetFrameStrata("DIALOG")
        f:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", tile = true, tileSize = 32, edgeSize = 32, insets = { left = 11, right = 12, top = 12, bottom = 11 } })
        f:EnableMouse(true)
        f:SetMovable(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", function() this:StartMoving() end)
        f:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
        local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOP", 0, -16)
        title:SetText("导出当前记录")
        f.title = title
        -- 两个格式切换按钮（右上角并排）
        local btnFull = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        btnFull:SetWidth(78)
        btnFull:SetHeight(20)
        btnFull:SetPoint("TOPRIGHT", f, "TOPRIGHT", -24, -38)
        btnFull:SetText("全量格式")
        btnFull:SetScript("OnClick", function() ADKP_ExportRecords_SwitchMode("full") end)
        f.btnFull = btnFull
        local btnCompact = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        btnCompact:SetWidth(78)
        btnCompact:SetHeight(20)
        btnCompact:SetPoint("TOPRIGHT", f, "TOPRIGHT", -104, -38)
        btnCompact:SetText("压缩格式")
        btnCompact:SetScript("OnClick", function() ADKP_ExportRecords_SwitchMode("compact") end)
        f.btnCompact = btnCompact
        local hint = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        hint:SetPoint("TOPLEFT", 20, -42)
        hint:SetText("点全选 + Ctrl+C 复制全部数据")
        local sf = CreateFrame("ScrollFrame", "ADKP_ExportRecordsScroll", f, "UIPanelScrollFrameTemplate")
        sf:SetPoint("TOPLEFT", 18, -60)
        sf:SetPoint("BOTTOMRIGHT", -36, 48)
        local eb = CreateFrame("EditBox", "ADKP_ExportRecordsEdit", sf)
        eb:SetMultiLine(true)
        eb:SetWidth(380)
        eb:SetHeight(280)
        eb:SetAutoFocus(false)
        eb:SetMaxLetters(0)
        eb:SetFontObject(ChatFontNormal)
        eb:SetScript("OnEscapePressed", function() this:ClearFocus() end)
        sf:SetScrollChild(eb)
        local selBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        selBtn:SetWidth(100)
        selBtn:SetHeight(24)
        selBtn:SetPoint("BOTTOMLEFT", 24, 14)
        selBtn:SetText("全选")
        selBtn:SetScript("OnClick", function() ADKP_ExportRecordsEdit:SetFocus(); ADKP_ExportRecordsEdit:HighlightText() end)
        local closeBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        closeBtn:SetWidth(100)
        closeBtn:SetHeight(24)
        closeBtn:SetPoint("BOTTOMRIGHT", -24, 14)
        closeBtn:SetText("关闭")
        closeBtn:SetScript("OnClick", function() ADKP_ExportRecordsFrame:Hide() end)
    end
    -- 默认显示压缩格式
    ADKP_ExportRecords_SwitchMode("compact")
    ADKP_ExportRecordsFrame:Show()
end


function ADKP_Options_Init()
    if not WebDKP_Options then WebDKP_Options = {} end
    if not WebDKP_WebOptions then WebDKP_WebOptions = {} end

    -- 默认值初始化
    if WebDKP_Options["KeepOnlineEnabled"] == nil then WebDKP_Options["KeepOnlineEnabled"] = false end
    if WebDKP_Options["AutoInviteEnabled"] == nil then WebDKP_Options["AutoInviteEnabled"] = false end
    if WebDKP_Options["AutoConvertRaid"] == nil then WebDKP_Options["AutoConvertRaid"] = false end
    if WebDKP_Options["AutoInviteKeyword"] == nil or WebDKP_Options["AutoInviteKeyword"] == "" then
        WebDKP_Options["AutoInviteKeyword"] = "9527"
    end
    if WebDKP_Options["AuctionMode"] == nil then WebDKP_Options["AuctionMode"] = "public" end
    if WebDKP_Options["BossAutoAward"] == nil then WebDKP_Options["BossAutoAward"] = false end
    ADKP_InitBossPoints()

    -- 清理已废弃的“替补团半分”配置残留（功能已移除）
    WebDKP_Options["SubHalfPointsEnabled"] = nil
    WebDKP_Options["SubPointsMode"] = nil
    WebDKP_Options["SubPointsCustomPercent"] = nil

    -- 恢复真实存在的控件状态（UI 同步主要靠 ADKP_Tab1_SyncChecks 在每次打开设置页时刷新）
    if ADKP_AwardDKP_FrameToggleAutoInvite then
        ADKP_AwardDKP_FrameToggleAutoInvite:SetChecked(WebDKP_Options["AutoInviteEnabled"] and true or false)
    end
    if ADKP_AwardDKP_FrameToggleAutoConvertRaid then
        ADKP_AwardDKP_FrameToggleAutoConvertRaid:SetChecked(WebDKP_Options["AutoConvertRaid"] and true or false)
    end
    if ADKP_AwardDKP_FrameAutoInviteKeyword then
        ADKP_AwardDKP_FrameAutoInviteKeyword:SetText(WebDKP_Options["AutoInviteKeyword"] or "9527")
    end
    if ADKP_AwardDKP_FrameAuctionPublic then
        ADKP_AwardDKP_FrameAuctionPublic:SetChecked(WebDKP_Options["AuctionMode"] ~= "anonymous")
    end
    if ADKP_AwardDKP_FrameAuctionAnonymous then
        ADKP_AwardDKP_FrameAuctionAnonymous:SetChecked(WebDKP_Options["AuctionMode"] == "anonymous")
    end

end

function ADKP_ToggleSilentMode()
    WebDKP_Options["SilentMode"] = not WebDKP_Options["SilentMode"]
    if WebDKP_Options["SilentMode"] then
        ADKP_Print("静默模式已开启 - 团队播报已关闭")
    else
        ADKP_Print("静默模式已关闭 - 团队播报已开启")
    end
end

function ADKP_ToggleRaidDkpReply()
    WebDKP_Options["RaidDkpReply"] = not WebDKP_Options["RaidDkpReply"]
    if WebDKP_Options["RaidDkpReply"] then
        ADKP_Print("允许团队成员查询已开启")
    else
        ADKP_Print("允许团队成员查询已关闭")
    end
end

function ADKP_ToggleIncludeSubCaptain()
    WebDKP_Options["IncludeSubCaptain"] = not WebDKP_Options["IncludeSubCaptain"]
    if WebDKP_Options["IncludeSubCaptain"] then
        ADKP_Print("替补加分包含替补队长已开启")
    else
        ADKP_Print("替补加分包含替补队长已关闭")
    end
end

function ADKP_ToggleQuickFloatEnabled()
    WebDKP_Options["QuickFloatEnabled"] = not WebDKP_Options["QuickFloatEnabled"]
    if WebDKP_Options["QuickFloatEnabled"] then
        ADKP_Print("快捷悬浮窗已启用")
    else
        ADKP_Print("快捷悬浮窗已禁用")
    end
    if ADKP_QuickFloat_UpdateVisibility then
        ADKP_QuickFloat_UpdateVisibility()
    end
end

function ADKP_ToggleKeepOnline()
    WebDKP_Options["KeepOnlineEnabled"] = not WebDKP_Options["KeepOnlineEnabled"]
    if WebDKP_Options["KeepOnlineEnabled"] then
        ADKP_Print("保持在线(挂机模式)已开启")
    else
        ADKP_Print("保持在线(挂机模式)已关闭")
    end
end

function ADKP_UpdateAuctionModeControls()
    if not ADKP_BidFrameAnnounceHighButton then return end
    if ADKP_Bid_IsTransmogMode and ADKP_Bid_IsTransmogMode() then
        ADKP_BidFrameAnnounceHighButton:Hide()
        return
    end
    if ADKP_IsAnonymousAuction() then
        ADKP_BidFrameAnnounceHighButton:Show()
    else
        ADKP_BidFrameAnnounceHighButton:Hide()
    end
end

function ADKP_SelectAuctionMode(mode)
    if not WebDKP_Options then WebDKP_Options = {} end
    if mode ~= "anonymous" then mode = "public" end
    WebDKP_Options["AuctionMode"] = mode
    if ADKP_BidFrameAuctionPublic then
        ADKP_BidFrameAuctionPublic:SetChecked(mode == "public")
    end
    if ADKP_BidFrameAuctionAnonymous then
        ADKP_BidFrameAuctionAnonymous:SetChecked(mode == "anonymous")
    end
    if ADKP_AwardDKP_FrameAuctionPublic then
        ADKP_AwardDKP_FrameAuctionPublic:SetChecked(mode == "public")
    end
    if ADKP_AwardDKP_FrameAuctionAnonymous then
        ADKP_AwardDKP_FrameAuctionAnonymous:SetChecked(mode == "anonymous")
    end
    ADKP_UpdateAuctionModeControls()
    if mode == "anonymous" then
        if ADKP_Bid_StartAnonTicker then ADKP_Bid_StartAnonTicker() end
        ADKP_Print("拍卖模式已设为：匿名拍卖")
    else
        if ADKP_Bid_StopAnonTicker then ADKP_Bid_StopAnonTicker() end
        ADKP_Print("拍卖模式已设为：公开拍卖")
    end
end

function ADKP_IsAnonymousAuction()
    return WebDKP_Options and WebDKP_Options["AuctionMode"] == "anonymous"
end

------------------------------------------------------------------------
-- 密语组人（监听密语 / 公会频道，看到密码则邀请发送者）
-- 密码精确匹配、忽略大小写；可选自动转团。
------------------------------------------------------------------------

-- 切换「密语组人」开关
-- 注意：UICheckButtonTemplate 在 OnClick 触发前已自动切换视觉勾选状态，
-- 所以这里只翻转存值，不要 SetChecked（与 ADKP_ToggleRaidDkpReply 等一致）。
function ADKP_ToggleAutoInvite()
    if not WebDKP_Options then WebDKP_Options = {} end
    -- 直接读取勾选框当前状态，保证存储值与显示一致（避免与 SetChecked/OnShow 同步脱节）
    if ADKP_AwardDKP_FrameToggleAutoInvite then
        WebDKP_Options["AutoInviteEnabled"] = ADKP_AwardDKP_FrameToggleAutoInvite:GetChecked() and true or false
    else
        WebDKP_Options["AutoInviteEnabled"] = not WebDKP_Options["AutoInviteEnabled"]
    end
    if WebDKP_Options["AutoInviteEnabled"] then
        local kw = WebDKP_Options["AutoInviteKeyword"] or "9527"
        ADKP_Print("密语组人已启用，密码：" .. kw .. "（密语或公会频道发送此密码即被邀请）")
    else
        ADKP_Print("密语组人已禁用")
    end
end

-- 切换「自动转团」开关
function ADKP_ToggleAutoConvertRaid()
    if not WebDKP_Options then WebDKP_Options = {} end
    -- 直接读取勾选框当前状态，保证存储值与显示一致
    if ADKP_AwardDKP_FrameToggleAutoConvertRaid then
        WebDKP_Options["AutoConvertRaid"] = ADKP_AwardDKP_FrameToggleAutoConvertRaid:GetChecked() and true or false
    else
        WebDKP_Options["AutoConvertRaid"] = not WebDKP_Options["AutoConvertRaid"]
    end
    if WebDKP_Options["AutoConvertRaid"] then
        ADKP_Print("自动转团已启用（队长、小队满5人、未成团时，邀请前自动转为团队）")
    else
        ADKP_Print("自动转团已禁用")
    end
end

-- 保存「邀请密语」输入框的值
function ADKP_SaveAutoInviteKeyword()
    if not WebDKP_Options then WebDKP_Options = {} end
    if not ADKP_AwardDKP_FrameAutoInviteKeyword then return end
    local txt = ADKP_AwardDKP_FrameAutoInviteKeyword:GetText() or ""
    txt = string.gsub(txt, "^%s+", "")   -- 去首部空白
    txt = string.gsub(txt, "%s+$", "")   -- 去尾部空白
    WebDKP_Options["AutoInviteKeyword"] = txt
    ADKP_AwardDKP_FrameAutoInviteKeyword:SetText(txt)
    ADKP_Print("邀请密语已保存：" .. txt)
end

-- 判断当前能否邀请（单人可直接邀请；组队后必须是队长/团长）
-- 返回 true 可邀请；返回 false, reason 不可邀请
function ADKP_AutoInvite_CanInvite()
    -- 单人状态可以直接发出首次邀请，游戏会自动创建小队。
    if GetNumPartyMembers() == 0 and GetNumRaidMembers() == 0 then
        return true
    end
    -- 必须是队长/团长
    local isLeader = false
    if GetNumRaidMembers() > 0 then
        isLeader = IsRaidLeader()
    else
        isLeader = IsPartyLeader()
    end
    if not isLeader then
        return false, "你不是队长，无法邀请"
    end
    -- 团队已满40人
    if GetNumRaidMembers() > 0 and GetNumRaidMembers() >= 40 then
        return false, "团队已满"
    end
    -- 小队已满5人（且未转团）
    if GetNumRaidMembers() == 0 and GetNumPartyMembers() >= 4 then
        -- 满员但允许通过自动转团解决，视为可邀请
        return true
    end
    return true
end

-- 满足条件时自动转团：开了 AutoConvertRaid、自己是队长、小队≥4人、当前非团
function ADKP_AutoInvite_MaybeConvertRaid()
    if not WebDKP_Options["AutoConvertRaid"] then return end
    if not UnitIsPartyLeader("player") then return end
    if GetNumRaidMembers() > 0 then return end           -- 已是团
    if GetNumPartyMembers() < 4 then return end          -- 小队未满（含自己<5）
    ConvertToRaid()
    ADKP_Print("小队已满，自动转为团队")
end

-- 核心：收到一条密语/公会消息时判断是否匹配密码并邀请
function ADKP_AutoInvite(name, message)
    -- 未启用 / 无效输入 → 直接返回
    if not WebDKP_Options or not WebDKP_Options["AutoInviteEnabled"] then return end
    if not name or name == "" then return end
    if not message or message == "" then return end
    -- 跳过自己（避免自己发密码触发）
    if name == UnitName("player") then return end
    -- 密码精确匹配（忽略大小写）
    local kw = WebDKP_Options["AutoInviteKeyword"] or "9527"
    if string.lower(message) ~= string.lower(kw) then return end
    -- 判断能否邀请
    local ok, reason = ADKP_AutoInvite_CanInvite()
    if not ok then
        ADKP_Print("无法自动邀请 " .. name .. "：" .. reason)
        return
    end
    -- 满足条件先转团，再邀请
    ADKP_AutoInvite_MaybeConvertRaid()
    InviteByName(name)
    ADKP_Print("已自动邀请 " .. name)
end

function ADKP_ResolveSubCaptain()
    local tableid = ADKP_GetTableid()
    local cap = ""
    -- 优先读输入框
    if ADKP_AwardDKP_FrameSubLeaderInput then
        local t = ADKP_AwardDKP_FrameSubLeaderInput:GetText() or ""
        if t ~= "" then cap = t end
    end
    -- 输入框为空时读当前团的持久化值
    if cap == "" then
        cap = ADKP_GetSubCaptain(tableid)
    end
    cap = string.gsub(cap, "^%s+", "")
    cap = string.gsub(cap, "%s+$", "")
    if cap ~= "" then
        -- 回写到当前团（持久化 + 缓存 + 输入框）
        ADKP_SetSubCaptain(tableid, cap)
        WebDKP_Options["SubLeader"] = cap
        if ADKP_AwardDKP_FrameSubLeaderInput and (ADKP_AwardDKP_FrameSubLeaderInput:GetText() or "") ~= cap then
            ADKP_AwardDKP_FrameSubLeaderInput:SetText(cap)
        end
        if ADKP_UpdateCaptainLabel then ADKP_UpdateCaptainLabel() end
    end
    return cap
end

function ADKP_TestStandbySync_Event()
    local captain = ADKP_ResolveSubCaptain()
    if captain == "" then
        ADKP_Print("错误：请先在“分数调整”界面的“设置替补队长”处输入名字并点击“设置”按钮！")
        return
    end
    if not ADKP_SubAwardData then
        ADKP_SubAwardData = { captain = captain, members = {}, bossName = "", reason = "", points = 0 }
    end
    ADKP_Print("正在发送同步测试请求到: " .. captain .. " ...")
    if not ADKP_PendingSubMembers then
        ADKP_PendingSubMembers = {}
    end
    ADKP_PendingSubMembers[captain] = {}
    ADKP_PendingSubMembers[string.lower(captain)] = nil
    ADKP_SubAwardData.captain = captain
    ADKP_ResetSubSyncState()
    ADKP_SubSync_ForceQuery = true
    pcall(SendAddonMessage, "AMB_TBQQ", captain, "GUILD")
    ADKP_SubSync_ForceQuery = false
    
    if not ADKP_TestSyncTimerFrame then
        ADKP_TestSyncTimerFrame = CreateFrame("Frame")
    end
    
    ADKP_TestSyncTimerFrame.timeElapsed = 0
    ADKP_TestSyncTimerFrame:SetScript("OnUpdate", function()
        local elapsed = tonumber(arg1) or 0
        this.timeElapsed = this.timeElapsed + elapsed
        
        if ADKP_SubAwardData.receivedResponse then
            this:SetScript("OnUpdate", nil)
            local subList = ADKP_PendingSubMembers[captain] or {}
            local count = 0
            for _ in pairs(subList) do
                count = count + 1
            end
            ADKP_Print("|cff00ff00[ADKP] 同步测试成功！|r 替补队长 " .. captain .. " 在线，当前替补人数: " .. count)
            return
        end
        
        if this.timeElapsed >= 4.0 then
            this:SetScript("OnUpdate", nil)
            ADKP_Print("|cffff0000[ADKP] 同步测试失败！|r 无法收到 " .. captain .. " 的响应。请确保对方在线、安装了本插件且是替补队长。")
        end
    end)
end

function ADKP_AwardRaidAndSub_Event()
    local pointsText = ""
    local reason = ""

    if ADKP_AwardDKP_FramePoints then
        pointsText = ADKP_AwardDKP_FramePoints:GetText() or ""
    elseif ADKP_BossAwardData and ADKP_BossAwardData.points then
        pointsText = tostring(ADKP_BossAwardData.points)
    end

    if ADKP_AwardDKP_FrameReason then
        reason = ADKP_AwardDKP_FrameReason:GetText() or ""
    elseif ADKP_BossAwardData and ADKP_BossAwardData.bossName then
        reason = "击杀-" .. ADKP_BossAwardData.bossName
    end

    if pointsText == "" then
        ADKP_Print("错误：请输入有效的分数。")
        PlaySound("igQuestFailed")
        return
    end

    local points = nil
    if ADKP_ROUND then
        points = ADKP_ROUND(pointsText, 2)
    else
        points = tonumber(pointsText)
    end
    if type(points) ~= "number" or points ~= points then
        ADKP_Print("错误：分数必须是数字。")
        PlaySound("igQuestFailed")
        return
    end

    if reason == "" then
        reason = "未指定原因"
    end

    -- 替补团半分功能已移除：该入口（主界面/斜杠命令）替补分 = 主团分。
    -- 差异化的主/替分值请使用 Boss 名单页的分值配置或悬浮窗「集/散/杀」的显式双分值。
    local subPoints = points

    if ADKP_SubAwardData then
        ADKP_SubAwardData.reason = reason
        ADKP_SubAwardData.points = subPoints
    end

    ADKP_RunRaidAndSubAward(points, subPoints, reason)
end




