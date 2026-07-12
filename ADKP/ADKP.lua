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

function ADKP_SaveToDisk()
    -- WoW 1.12 writes SavedVariables on ReloadUI/logout; keep this hook safe for frequent calls.
    if WebDKP_Options and WebDKP_Options["AutoBackupEnabled"] and ADKP_BackupData then
        ADKP_BackupData()
    end
end

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
-- 备份数据功能  
-- ================================
function ADKP_BackupData()  
    -- 检查是否支持superwow
    if not SUPERWOW_STRING or not ExportFile then
        ADKP_Print("错误：备份数据功能需要superwow支持且ExportFile函数可用")
        return
    end

    -- 获取服务器和玩家信息
    local serverName = GetRealmName() or "未知服务器"
    local charName = UnitName("player") or "未知角色"
    
    -- 将服务器和玩家角色名称中的空格替换为横线
    serverName = string.gsub(serverName, "%s", "-")
    charName = string.gsub(charName, "%s", "-")
    
    local currentDate = date("%Y-%m-%d")
    local currentDateTime = date("%Y-%m-%d-%H%M%S")
    
    -- a. 备份的数据文件名称：D-服务器-玩家角色名称-当前日期和时间
    local dataFileName = "D-" .. serverName .. "-" .. charName .. "-" .. currentDateTime
    
    -- 数据文件内容格式：“类型,时间,分值,项目,玩家列表”
    -- 类型可以是: D (加分记录), L (装备记录)
    -- 玩家列表格式为: 名字:职业;名字:职业...
    local exportText = "类型,时间,分值,项目,玩家列表\n"
    
    if WebDKP_Log then
        -- 先收集记录到数组，便于按时间排序（pairs 遍历顺序无序）
        local records = {}
        for key, entry in pairs(WebDKP_Log) do
            if key ~= "Version" and type(entry) == "table" and entry.awarded then
                local time = entry.date or ""
                local reason = entry.reason or "未知原因"
                local points = entry.points or 0

                -- 转义逗号，防止CSV格式错乱（逗号是CSV分隔符）
                -- 用双波浪号 ~~ 替代逗号：该组合在实际 reason 文本中几乎不可能出现
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

                -- 判断是否是装备记录 (entry.foritem 为 true)
                local recordType = "D"
                if entry.foritem == "true" or entry.foritem == true then
                    recordType = "L"
                end

                local line = recordType .. "," .. time .. "," .. points .. "," .. cleanReason .. "," .. playersStr .. "\n"
                table.insert(records, { date = time, line = line })
            end
        end

        -- 按时间从新到旧排序（date 格式 "YYYY-MM-DD HH:MM:SS"，字典序即时间序；空值排最后）
        table.sort(records, function(a, b)
            return (a.date or "") > (b.date or "")
        end)
        for i = 1, table.getn(records) do
            exportText = exportText .. records[i].line
        end
    end

    -- 1. 导出备份的数据文件
    ExportFile(dataFileName, exportText)
    
    -- 2. 确定计数器的起始值
    local counter = 1
    if not WebDKP_Options then
        WebDKP_Options = {}
    end
    if not WebDKP_Options["LatestBackup"] then
        WebDKP_Options["LatestBackup"] = {}
    end
    local charKey = serverName .. "-" .. charName
    
    -- 优先从内存/SavedVariables获取今日已用过的计数
    if WebDKP_Options["LatestBackup"][charKey] then
        local lastBackup = WebDKP_Options["LatestBackup"][charKey]
        if lastBackup.Date == currentDate and lastBackup.Counter then
            counter = lastBackup.Counter + 1
        end
    end
    
    -- 检查磁盘上已存在的文件（用于处理在之前游戏会话中保存的文件）
    while true do
        local checkPointerName = "P-" .. serverName .. "-" .. charName .. "-" .. currentDate .. "-" .. counter
        if ImportFile(checkPointerName) or ImportFile(checkPointerName .. ".txt") then
            counter = counter + 1
        else
            break
        end
    end
    
    -- 3. 导出指针文件
    local pointerFileName = "P-" .. serverName .. "-" .. charName .. "-" .. currentDate .. "-" .. counter
    ExportFile(pointerFileName, dataFileName)
    
    -- 4. 成功写入，更新内存和配置文件
    WebDKP_Options["LatestBackup"][charKey] = {
        ["Date"] = currentDate,
        ["Counter"] = counter,
        ["PointerFile"] = pointerFileName,
        ["DataFile"] = dataFileName
    }
    
    ADKP_Print("数据已成功备份到: " .. dataFileName)
    ADKP_Print("指针文件已保存: " .. pointerFileName)
end

-- ================================
-- 恢复数据功能  
-- ================================
function ADKP_RestoreData()  
    -- 检查是否支持superwow
    if not SUPERWOW_STRING or not ImportFile then
        ADKP_Print("错误：恢复数据功能需要superwow支持且ImportFile函数可用")
        return
    end

    local serverName = GetRealmName() or "未知服务器"
    local charName = UnitName("player") or "未知角色"
    
    -- 将服务器和玩家角色名称中的空格替换为横线
    serverName = string.gsub(serverName, "%s", "-")
    charName = string.gsub(charName, "%s", "-")
    
    local currentDate = date("%Y-%m-%d")
    
    local latestPointerFileName = nil
    local foundDate = nil
    local charKey = serverName .. "-" .. charName

    -- 1. 首先检查 SavedVariables 中的记录是否有效且存在于磁盘
    local svPointer = nil
    local svDate = nil
    if WebDKP_Options and WebDKP_Options["LatestBackup"] and WebDKP_Options["LatestBackup"][charKey] then
        local lastBackup = WebDKP_Options["LatestBackup"][charKey]
        if lastBackup.PointerFile then
            -- 检查此文件是否真的存在并可读
            local checkContent = ImportFile(lastBackup.PointerFile) or ImportFile(lastBackup.PointerFile .. ".txt")
            if checkContent and checkContent ~= "" then
                svPointer = lastBackup.PointerFile
                svDate = lastBackup.Date
            end
        end
    end

    -- 2. 开始逐日倒退查找最新记录，限制在 60 天内
    -- 辅助函数：校验某个计数文件是否存在
    local function FileExists(sName, cName, dStr, cnt)
        local pointerFileName = "P-" .. sName .. "-" .. cName .. "-" .. dStr .. "-" .. cnt
        if ImportFile(pointerFileName) or ImportFile(pointerFileName .. ".txt") then
            return true, pointerFileName
        end
        return false, nil
    end

    -- 辅助二分查找函数
    local function FindMaxCounterForDate(sName, cName, dStr)
        local exists, _ = FileExists(sName, cName, dStr, 1)
        if not exists then
            return 0, nil
        end
        
        local low = 1
        local high = 256
        
        local exists256, _ = FileExists(sName, cName, dStr, 256)
        if exists256 then
            low = 256
            local exists2048, _ = FileExists(sName, cName, dStr, 2048)
            if exists2048 then
                low = 2048
                local step = 4096
                while true do
                    local existsStep, _ = FileExists(sName, cName, dStr, step)
                    if existsStep then
                        low = step
                        step = step * 2
                    else
                        high = step
                        break
                    end
                end
            else
                high = 2048
            end
        else
            high = 256
        end
        
        while low + 1 < high do
            local mid = math.floor((low + high) / 2)
            local existsMid, _ = FileExists(sName, cName, dStr, mid)
            if existsMid then
                low = mid
            else
                high = mid
            end
        end
        
        local _, finalPointerName = FileExists(sName, cName, dStr, low)
        return low, finalPointerName
    end

    for i = 0, 59 do
        local checkTime = time() - i * 24 * 3600
        local checkDate = date("%Y-%m-%d", checkTime)

        -- 如果 checkDate 等于已验证的 svDate，且之前没有找到更新的备份
        if svDate and checkDate == svDate then
            latestPointerFileName = svPointer
            foundDate = svDate
            break
        end

        -- 检查 checkDate 这一天是否存在 counter=1 的文件
        if FileExists(serverName, charName, checkDate, 1) then
            local maxCounter, pointerName = FindMaxCounterForDate(serverName, charName, checkDate)
            if pointerName then
                latestPointerFileName = pointerName
                foundDate = checkDate
                break
            end
        end
    end

    -- 如果没有找到任何记录
    if not latestPointerFileName then
        ADKP_Print("未找到任何备份记录（已检索近60天及SavedVariables）")
        return
    end

    ADKP_Print("已找到最新备份记录，日期：" .. foundDate .. " 文件：" .. latestPointerFileName)

    -- 3. 读取指针文件里的数据文件名
    local dataFileName = ImportFile(latestPointerFileName)
    if not dataFileName or dataFileName == "" then
        ADKP_Print("错误：指针文件内容为空，无法读取数据文件名")
        return
    end

    -- 去除换行符和首尾多余空格
    dataFileName = string.gsub(dataFileName, "[\r\n]", "")
    dataFileName = string.gsub(dataFileName, "^%s*(.-)%s*$", "%1")

    -- 4. 导入数据文件
    local importData = ImportFile(dataFileName) or ImportFile(dataFileName .. ".txt")
    if not importData or importData == "" then
        ADKP_Print("错误：无法读取备份数据文件：" .. dataFileName)
        return
    end

    -- 5. 调用共享的解析恢复函数
    ADKP_RestoreFromData(importData, dataFileName)
end

-- ================================
-- 从已读取的备份数据内容恢复（ADKP_RestoreData 与 ADKP_ImportSpecificVersion 共用）
-- 合并模式：重复记录跳过，新记录加入当前数据
-- ================================
function ADKP_RestoreFromData(importData, dataFileName)
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
            if table.getn(fields) >= 5 then
                local recordType = fields[1]
                local timeStr = fields[2]
                local points = tonumber(fields[3]) or 0
                local reason = fields[4]
                -- 还原备份时被转义的逗号（备份时把 reason 里的逗号替换成了 ~~ ）
                reason = string.gsub(reason, "~~", ",")
                local playersStr = fields[5]
                
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

    -- 构建已存在记录的索引表，用于 O(1) 重复检查（替代原来遍历整个 WebDKP_Log 的暴力匹配）
    -- 索引 key = foritem标记 .. "\001" .. reason .. " " .. date，值为 points + 玩家签名
    local existingIndex = {}
    if WebDKP_Log then
        for key, entry in pairs(WebDKP_Log) do
            if type(entry) == "table" and entry.awarded then
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
                existingIndex[idxKey] = {
                    points = entry.points or 0,
                    signature = signature
                }
            end
        end
    end

    -- O(1) 重复检查：DKP 记录
    local function isDuplicateDKPRecord(record, players)
        local idxKey = "D\001" .. record.reason .. " " .. record.time
        local existing = existingIndex[idxKey]
        if not existing then return false end
        if existing.points ~= record.points then return false end
        -- 比对玩家签名
        local names = {}
        for playerName, _ in pairs(players) do
            table.insert(names, playerName)
        end
        table.sort(names)
        return table.concat(names, ",") == existing.signature
    end

    -- O(1) 重复检查：装备记录
    local function isDuplicateLootRecord(record)
        local idxKey = "L\001" .. record.item .. " " .. record.time
        local existing = existingIndex[idxKey]
        if not existing then return false end
        if existing.points ~= record.points then return false end
        -- 装备记录只发给一个玩家，检查该玩家是否在签名中
        -- 签名是排序后的逗号分隔名单，用模式匹配检查
        return string.find("," .. existing.signature .. ",", "," .. record.player .. ",", 1, true) ~= nil
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
                ["awardedby"] = UnitName("player"),
                ["uniqueId"] = record.reason .. " " .. record.time
            }

            if not WebDKP_Log then
                WebDKP_Log = {}
            end
            local key = record.reason .. " " .. record.time
            WebDKP_Log[key] = newLogEntry

            -- 同步更新索引表，防止同一备份文件内的重复记录被二次导入
            local names = {}
            for playerName, _ in pairs(players) do
                table.insert(names, playerName)
            end
            table.sort(names)
            existingIndex["D\001" .. record.reason .. " " .. record.time] = {
                points = record.points,
                signature = table.concat(names, ",")
            }
            
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
                WebDKP_DkpTable[playerName][dkpField] = (WebDKP_DkpTable[playerName][dkpField] or 0) + record.points
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
                ["awardedby"] = UnitName("player"),
                ["uniqueId"] = record.item .. " " .. record.time
            }
            
            if not WebDKP_Log then
                WebDKP_Log = {}
            end
            local key = record.item .. " " .. record.time
            WebDKP_Log[key] = newLogEntry

            -- 同步更新索引表，防止同一备份文件内的重复记录被二次导入
            existingIndex["L\001" .. record.item .. " " .. record.time] = {
                points = record.points,
                signature = record.player
            }
            
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
                WebDKP_DkpTable[playerName][dkpField] = (WebDKP_DkpTable[playerName][dkpField] or 0) + record.points
            end
            restoredCount = restoredCount + 1
        else
            skippedCount = skippedCount + 1
        end
    end
    
    -- 保存数据
    if ADKP_SaveToDisk then
        ADKP_SaveToDisk()
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
    local content = ImportFile(filename) or ImportFile(filename .. ".txt")
    if not content or content == "" then
        ADKP_Print("错误：无法读取文件：" .. filename)
        return
    end

    -- 判断文件类型：数据文件首行以"类型"开头；否则视为指针文件（内容是数据文件名）
    local _, _, firstLine = string.find(content, "^([^\r\n]*)")
    if firstLine and string.find(firstLine, "^类型") then
        -- 数据文件，直接恢复
        ADKP_RestoreFromData(content, filename)
    else
        -- 指针文件：内容是数据文件名
        local realDataFile = string.gsub(content, "[\r\n]", "")
        realDataFile = string.gsub(realDataFile, "^%s*(.-)%s*$", "%1")
        if realDataFile == "" then
            ADKP_Print("错误：指针文件内容为空：" .. filename)
            return
        end
        local dataContent = ImportFile(realDataFile) or ImportFile(realDataFile .. ".txt")
        if not dataContent or dataContent == "" then
            ADKP_Print("错误：无法读取数据文件：" .. realDataFile)
            return
        end
        ADKP_RestoreFromData(dataContent, realDataFile)
    end
end

-- ================================
-- 导入按钮 OnClick：读取文本框文件名，弹出确认窗
-- ================================
function ADKP_RequestImportVersion()
    local editBox = ADKP_LootListImportEditBox
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
        ["dkp" .. ADKP_GetTableid()] = initialDkp,
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

-- 替补数据
ADKP_SubData = {
    isActive = false,
    startTime = 0,
    endTime = 0,
    minutes = 5,
    points = 0,
    bossName = "",
    reason = "",
    substituteList = {},
    raidMembers = {},
    timerFrame = nil
};

-- 替补加分数据
ADKP_SubAwardData = {
    captain = "",
    members = {},
    bossName = "",
    reason = "",
    points = 0
};

-- 初始化替补设置
function ADKP_InitSubSettings()
	-- 确保数据结构存在
    if not WebDKP_Options then
        WebDKP_Options = {}
    end
    if not WebDKP_Options["SubSettings"] then
        WebDKP_Options["SubSettings"] = {
            captain = ""
        }
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
    
	-- 从设置加载替补队长信息
    local captain = WebDKP_Options["SubSettings"]["captain"] or ""
    ADKP_SubAwardData.captain = captain
    
    ADKP_UpdateCaptainLabel()
    
	-- 初始化ADKP_SubData
    if not ADKP_SubData then
        ADKP_SubData = {
            isActive = false,
            startTime = 0,
            endTime = 0,
            minutes = 5,
            points = 0,
            bossName = "",
            reason = "",
            substituteList = {},
            raidMembers = {},
            timerFrame = nil
        }
    end
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

-- 每日替补记录
WebDKP_DailySubRecords = {};

-- 当前团队成员缓存
ADKP_CurrentRaidMembers = {};

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
	["SubHalfPointsEnabled"] = false, -- Whether to award half points to substitutes
	["IncludeSubCaptain"] = false, -- Whether to include sub captain when awarding subs
	["SelectedTableId"] = 1, 		-- The last table that was being looked at
	["MiniMapButtonAngle"] = 1,
	["SilentMode"] = false,			-- 静默模式，关闭团队播报功能
		["RaidDkpReply"] = true,			-- 团队频道查DKP密语自动回复
	["QuickFloatEnabled"] = true,
	["AutoBackupEnabled"] = true,
	["SubSettings"] = {
		["captain"] = "",
		["useCheckIn"] = false
	}
}

-- User options that are syncronized with the website
WebDKP_WebOptions = {			
	["ZeroSumEnabled"] = 0,			-- Whether or not to use ZeroSum DKP settings
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

function ADKP_Contain(value, table)
    if not table then return false end
    for _, v in ipairs(table) do
        if v == value then
            return true
        end
    end
    return false
end

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
	
	-- 从设置加载替补队长信息
	ADKP_SubAwardData.captain = WebDKP_Options["SubSettings"].captain or ""
	
	-- 初始化ADKP_SubData
	if not ADKP_SubData then
		ADKP_SubData = {
			isActive = false,
			startTime = 0,
			endTime = 0,
			minutes = 5,
			points = 0,
			bossName = "",
			reason = "",
			substituteList = {},
			raidMembers = {},
			timerFrame = nil
		}
	end
	
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

-- 定时器函数，用于延迟执行某个函数
function ADKP_ScheduleTimer(func, delay)
    local timerFrame = CreateFrame("Frame")
    timerFrame:SetScript("OnUpdate", function()
        local frame = this or timerFrame  -- 兼容不同版本
        if not frame.startTime then
            frame.startTime = GetTime()
        end
        
        local currentTime = GetTime()
        if currentTime - frame.startTime >= delay then
            -- 执行传入的函数
            func()
            -- 销毁定时器
            frame:SetScript("OnUpdate", nil)
        end
    end)
    
    return timerFrame
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
		WebDKP_Options["BossPatterns"] = {
			"拉格纳罗斯", "奥妮克希亚",
		}
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
function ADKP_SendSubMemberList(toPlayer)
	-- 详细调试信息
	-- ADKP_Print("=== ADKP_SendSubMemberList 开始 ===")
	-- ADKP_Print("目标玩家: " .. toPlayer)
	-- DEFAULT_CHAT_FRAME:AddMessage("[ADKP] 开始发送替补队员列表给: " .. toPlayer, 0, 1, 0)
	
	-- 确保toPlayer不为空
	if not toPlayer or toPlayer == "" then
		ADKP_Print("错误: 目标玩家名为空")
		return false
	end
	
	-- 收集所有成员并打包通过密语发送
	local members = {}
	local raidMemberCount = GetNumRaidMembers()
	local partyMemberCount = GetNumPartyMembers()

	-- 收集团队成员
	if raidMemberCount > 0 then
		for i = 1, raidMemberCount do
			local name, _, _, _, _, class = GetRaidRosterInfo(i)
			if name then
				if class and class ~= "" then
					table.insert(members, name .. ":" .. class)
				else
					table.insert(members, name)
				end
			end
		end
	elseif partyMemberCount > 0 then
		for i = 1, partyMemberCount do
			local unit = "party" .. i
			local name = UnitName(unit)
			local class = UnitClass(unit)
			if name then
				if class and class ~= "" then
					table.insert(members, name .. ":" .. class)
				else
					table.insert(members, name)
				end
			end
		end
		-- 添加自己
		local playerName = UnitName("player")
		if playerName then
			local playerClass = UnitClass("player")
			if playerClass and playerClass ~= "" then
				table.insert(members, playerName .. ":" .. playerClass)
			else
				table.insert(members, playerName)
			end
		end
	else
		-- 只发送自己的信息
		local playerName = UnitName("player")
		if playerName then
			local playerClass = UnitClass("player")
			if playerClass and playerClass ~= "" then
				table.insert(members, playerName .. ":" .. playerClass)
			else
				table.insert(members, playerName)
			end
		end
	end

	local memberCount = table.getn(members)

	if memberCount == 0 then
		ADKP_SendWhisper(toPlayer, "SUB_EMPTY")
	else
		-- 打包发送，每条消息控制在240字节以内
		local batches = {}
		local current = ""
		for i = 1, memberCount do
			local entry = members[i]
			local sep = ""
			if current ~= "" then sep = ";" end
			if string.len(current) + string.len(sep) + string.len(entry) > 240 then
				table.insert(batches, current)
				current = entry
			else
				current = current .. sep .. entry
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

	-- 数据消息: ADKP: SUB:张三:Warrior;李四:Mage
	local _, _, data = string.find(message, "^ADKP: SUB:(.+)$")
	if data then
		for entry in string.gfind(data, "[^;]+") do
			local _, _, name, class = string.find(entry, "^([^:]+):([^:]+)$")
			if name then
				ADKP_ReceiveSubMember(fromPlayer, name .. ":" .. class .. ":" .. fromPlayer)
			else
				ADKP_ReceiveSubMember(fromPlayer, entry .. ":" .. fromPlayer)
			end
		end
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

			local reason = ""
			local points = 0
			if ADKP_SubAwardData then
				reason = ADKP_SubAwardData.reason or ""
				points = ADKP_SubAwardData.points or 0
			end
			if ADKP_AwardDKP_FrameSubReason then
				local reasonText = ADKP_AwardDKP_FrameSubReason:GetText() or ""
				if reasonText ~= "" then
					reason = reasonText
				end
			end
			if ADKP_AwardDKP_FrameSubPoints then
				local pointsText = ADKP_AwardDKP_FrameSubPoints:GetText() or ""
				local pointsValue = tonumber(pointsText)
				if pointsValue and pointsValue ~= 0 then
					points = pointsValue
				end
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
		
		-- 设置接收响应标志
		if ADKP_SubAwardData then
			ADKP_SubAwardData.receivedResponse = true
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
    
	-- 设置响应标志，通知定时器已收到信息
	if ADKP_SubAwardData then
		ADKP_SubAwardData.receivedResponse = true
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
	
	-- 初始化每日替补记录变量
	if( WebDKP_DailySubRecords == nil) then
		WebDKP_DailySubRecords = {};
	end
	
	-- 确保ADKP_Options表存在
	if not WebDKP_Options then
		WebDKP_Options = {}
	end
	
	--load up the last loot table that was being viewed
	ADKP_Frame.selectedTableid = WebDKP_Options["SelectedTableId"];
	--ADKP_Options_Autofill_DropDown_Init();
	
	-- load the options from saved variables and update the settings on the 
	if ( WebDKP_Options["AutofillEnabled"] == 1 ) then
		if ADKP_Options_FrameToggleAutofill then
			ADKP_Options_FrameToggleAutofill:SetChecked(1);
		end
		if ADKP_Options_FrameAutofillDropDown then
			ADKP_Options_FrameAutofillDropDown:Show();
		end
		if ADKP_Options_FrameToggleAutoAward then
			ADKP_Options_FrameToggleAutoAward:Show();
		end
	else
		if ADKP_Options_FrameToggleAutofill then
			ADKP_Options_FrameToggleAutofill:SetChecked(0);
		end
		if ADKP_Options_FrameAutofillDropDown then
			ADKP_Options_FrameAutofillDropDown:Hide();
		end
		if ADKP_Options_FrameToggleAutoAward then
			ADKP_Options_FrameToggleAutoAward:Hide();
		end
	end

	if ADKP_Options_FrameToggleAutoAward then
		ADKP_Options_FrameToggleAutoAward:SetChecked(WebDKP_Options["AutoAwardEnabled"]);
	end
	if ADKP_Options_FrameToggleZeroSum then
		ADKP_Options_FrameToggleZeroSum:SetChecked(WebDKP_WebOptions["ZeroSumEnabled"]);
	end
	
	
	ADKP_UpdateTableToShow(); --update who is in the table
	ADKP_UpdateTable();       --update the gui
	
	-- set the mini map position
	ADKP_MinimapButton_SetPositionAngle(WebDKP_Options["MiniMapButtonAngle"]);

	-- 初始化替补设置
	ADKP_InitSubSettings();
	
	-- 快捷浮窗显示/隐藏（仅RAID且勾选开启时显示）
	if ADKP_QuickFloat_UpdateVisibility then
		ADKP_QuickFloat_UpdateVisibility()
	end
end





-- ================================
-- Called on shutdown. Does nothing
-- ================================
function ADKP_OnDisable()
    
end


---------------------------------------------------
-- EVENT HANDLERS (Party changed / gui toggled / etc.)
---------------------------------------------------

-- ================================
-- Called by slash command. Toggles gui. 
-- ================================
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
-- Handles the master loot list being opened 
-- ================================
function ADKP_OPEN_MASTER_LOOT_LIST()
    
end

-- ================================
-- 处理打开尸体事件
-- ================================
function ADKP_LOOT_OPENED()
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

-- 更新「拍」按钮状态：red=true 亮红可点，false 灰色不可点
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

-- 「拍」按钮：把当前掉落窗口的全部装备按顺序竞拍（time=0 不限时，手动停）
function ADKP_StartBossLootBid()
	local count = GetNumLootItems and GetNumLootItems() or 0
	if count == 0 then
		ADKP_Print("掉落列表为空")
		return
	end
	ADKP_BidQueue = {}
	for i = 1, count do
		local link = GetLootSlotLink(i)
		if link then
			table.insert(ADKP_BidQueue, { item = link, time = 0 })
		end
	end
	if table.getn(ADKP_BidQueue) == 0 then
		ADKP_Print("没有可竞拍的装备")
		return
	end
	ADKP_UpdateQuickFloatBidBtn(false)
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
	ADKP_HandleWhisperTB(name, message);
	ADKP_HandleSubWhisperData(name, message);
	ADKP_AutoInvite(name, message);
end

-- ================================
-- Event handler for all party and raid
-- chat messages. 
-- ================================
function ADKP_CHAT_MSG_PARTY_RAID()
	ADKP_Bid_Event();
	ADKP_RaidDkpQuery();
end

-- 团队/小队频道查 DKP 自动回复
function ADKP_RaidDkpQuery()
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
	
	-- 确保隐藏遗留的框架
	if ADKP_AwardAllDKP_Frame then ADKP_AwardAllDKP_Frame:Hide() end
	if ADKP_AwardItem_Frame then ADKP_AwardItem_Frame:Hide() end
	
	if ADKP_Personal_Frame then ADKP_Personal_Frame:Hide() end

	-- 数据列表为全宽模式：进入时隐藏左侧名单操作区，离开时恢复
	local ADKP_sideEls = { "ADKP_ClassFiltersFrame", "ADKP_SingleAdjustFrame", "ADKP_NameSearchBox", "ADKP_SearchLabel", "ADKP_FrameModeRaid", "ADKP_FrameModeSub", "ADKP_FrameModeOut", "ADKP_FrameSubRefresh" }
	local ADKP_hideSide = ( button:GetID() == 2 )
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
    local playerDkp = playerData["dkp"..tableid] or 0;
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
			local playerDkp = v["dkp"..tableid];
			if ( playerDkp == nil ) then 
				v["dkp"..tableid] = 0;
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
-- Invoked when the gui loads up the drop down list of 
-- available dkp tables. 
-- ================================
function ADKP_Tables_DropDown_OnLoad()
	UIDropDownMenu_Initialize(ADKP_Tables_DropDown, ADKP_Tables_DropDown_Init);
	
	local numTables = ADKP_GetTableSize(WebDKP_Tables)
	if ( WebDKP_Tables == nil or numTables==0 or numTables==1) then
		ADKP_Tables_DropDown:Hide();
	else
		ADKP_Tables_DropDown:Show();
	end
end
-- ================================
-- Invoked when the drop down list of available tables
-- needs to be redrawn. Populates it with data 
-- from the tables data structure and sets up an 
-- event handler
-- ================================
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
	UIDropDownMenu_SetSelectedName(ADKP_Tables_DropDown, selected );
	UIDropDownMenu_SetWidth(200, ADKP_Tables_DropDown);
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
	ADKP_Frame.selectedTableid = button.value;
	WebDKP_Options["SelectedTableId"] = button.value; 
	ADKP_Tables_DropDown_Init();
	ADKP_UpdateTableToShow(); --update who is in the table
	ADKP_UpdateTable();       --update the gui
end


-- ================================
-- Toggles zero sum support
-- ================================
function ADKP_ToggleZeroSum()
	-- is enabled, disable it
	if ( WebDKP_WebOptions["ZeroSumEnabled"] == 1 ) then
		WebDKP_WebOptions["ZeroSumEnabled"] = 0;
	-- is disabled, enable it
	else
		WebDKP_WebOptions["ZeroSumEnabled"] = 1;
	end
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
-- Initializes the minimap drop down
-- ================================
-- In WoW 1.12 Lua 5.0, use 'this' instead of function parameters
function ADKP_MinimapDropDown_OnLoad()
	local dropdown = this
	if not dropdown then
		return
	end
	UIDropDownMenu_SetAnchor(-2, -20, dropdown, "TOPRIGHT", dropdown:GetName(), "TOPLEFT");
	UIDropDownMenu_Initialize(dropdown, ADKP_MinimapDropDown_Initialize);
end

-- ================================
-- Adds buttons to the minimap drop down
-- ================================
function ADKP_MinimapDropDown_Initialize()
	-- 数据列表框架已在插件加载时预加载，这里直接添加菜单项
	ADKP_Add_MinimapDropDownItem("DKP 列表",ADKP_ToggleGUI);
	
	--ADKP_Add_MinimapDropDownItem("Help",ADKP_ToggleGUI);
end

-- ================================
-- Helper method that adds individual entries into the minimap drop down
-- menu.
-- ================================
function ADKP_Add_MinimapDropDownItem(text, eventHandler)
	local info = { };
	info.text = text;
	info.value = text; 
	info.owner = UIDROPDOWNMENU_OPEN_MENU;
	info.func = eventHandler; -- ADKP_Tables_DropDown_OnClick;
	UIDropDownMenu_AddButton(info);
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
	retryCount = 0,
	maxRetries = 10,
	frame = nil
};

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
		ADKP_StopAutoLoot(false);
	end);
	
	frame:Hide();
	ADKP_AutoLootData.frame = frame;
	return frame;
end

-- ================================
-- 开始自动分配物品
-- ================================
function ADKP_StartAutoLoot(itemLink, playerName, dkpCost)
	-- 检查是否有分配权限
	local lootMethod, masterLooterPartyID = GetLootMethod();
	if lootMethod ~= "master" then
		ADKP_Print("错误：当前不是队长分配模式");
		return;
	end
	
	-- 检查是否是分配者
	local isLooter = false;
	-- 检查是否在团队中且masterLooterPartyID不为nil
	if not masterLooterPartyID then
		ADKP_Print("错误：你不在团队中或无法获取分配者信息");
		return;
	end
	
	if masterLooterPartyID == 0 then
		isLooter = true;
	else
		local masterLooterName = UnitName("party"..masterLooterPartyID);
		if masterLooterName == UnitName("player") then
			isLooter = true;
		end
	end
	
	if not isLooter then
		ADKP_Print("错误：你不是分配者");
		return;
	end
	
	-- 初始化分配数据
	ADKP_AutoLootData.isAssigning = true;
	ADKP_AutoLootData.currentPlayer = playerName;
	ADKP_AutoLootData.currentItem = string.match(itemLink, "%[(.+)%]") or itemLink;
	ADKP_AutoLootData.currentItemLink = itemLink;
	ADKP_AutoLootData.currentCost = dkpCost or 0;
	ADKP_AutoLootData.retryCount = 0;
	
	-- 创建并显示状态窗口
	local frame = ADKP_CreateAutoLootFrame();
	frame.statusText:SetText("正在分配 "..ADKP_AutoLootData.currentItem.." 给 "..playerName);
	frame:Show();
	
	-- 检查是否有可分配物品
	if GetNumLootItems() == 0 then
		frame.statusText:SetText("等待打开尸体...");
		ADKP_Print("等待打开尸体进行自动分配");
		-- 不返回，保持自动分配状态
	else
		-- 尝试分配物品
		ADKP_TryAssignLoot();
	end
end

-- ================================
-- 尝试分配物品
-- ================================
function ADKP_TryAssignLoot()
	if not ADKP_AutoLootData.isAssigning then
		return;
	end
	
	-- 检查重试次数
	ADKP_AutoLootData.retryCount = ADKP_AutoLootData.retryCount + 1;
	if ADKP_AutoLootData.retryCount > ADKP_AutoLootData.maxRetries then
		ADKP_StopAutoLoot(false);
		ADKP_Print("自动分配失败：重试次数过多");
		return;
	end
	
	-- 检查是否还有可分配物品
	if GetNumLootItems() == 0 then
		-- 没有可分配物品时，不停止自动分配，而是等待
		if ADKP_AutoLootData.frame then
			ADKP_AutoLootData.frame.statusText:SetText("等待打开尸体...");
		end
		-- 重置重试计数，因为这不是真正的失败
		ADKP_AutoLootData.retryCount = ADKP_AutoLootData.retryCount - 1;
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
				break;
			end
		end
	end
	
	if not foundItemSlot then
		ADKP_StopAutoLoot(false);
		ADKP_Print("错误：物品不匹配或已被分配");
		return;
	end
	
	-- 查找匹配的玩家
	local foundPlayerIndex = nil;
	for j = 1, 40 do
		local candidateName = GetMasterLootCandidate(j);
		if candidateName == ADKP_AutoLootData.currentPlayer then
			foundPlayerIndex = j;
			break;
		end
	end
	
	if not foundPlayerIndex then
		local playerName = ADKP_AutoLootData.currentPlayer or "未知1玩家";
		
		-- 检查是否是给自己分配
		if ADKP_AutoLootData.currentPlayer == UnitName("player") then
			-- 检查自己是否在团队中
			local inRaid = false;
			for i = 1, GetNumRaidMembers() do
				if UnitName("raid"..i) == UnitName("player") then
					inRaid = true;
					break;
				end
			end
			
			if inRaid then
				-- 在团队中但没找到，可能是团队信息还没同步，等待重试
				if ADKP_AutoLootData.frame then
					ADKP_AutoLootData.frame.statusText:SetText("等待团队信息同步...");
				end
				-- 重置重试计数
				ADKP_AutoLootData.retryCount = ADKP_AutoLootData.retryCount - 1;
				-- 延迟重试
					local retryTimer = CreateFrame("Frame");
					retryTimer.timeLeft = 1; -- 等待1秒后重试
					retryTimer:SetScript("OnUpdate", function()
						-- In WoW 1.12 Lua 5.0, use 'this' and 'arg1'
						local frame =  retryTimer -- 使用this或显式引用
						local elapsed = tonumber(arg1) or 0;
						frame.timeLeft = frame.timeLeft - elapsed;
						if frame.timeLeft <= 0 then
							frame:SetScript("OnUpdate", nil);
							ADKP_TryAssignLoot();
						end
					end);
				return;
			else
				-- 不在团队中，直接停止
				ADKP_StopAutoLoot(false);
				ADKP_Print("错误：你不在团队中");
				return;
			end
		end
		
		-- 其他玩家不在拾取队列，继续自动分配模式
		if ADKP_AutoLootData.frame then
			ADKP_AutoLootData.frame.statusText:SetText("玩家不在拾取范围，等待返回...");
		end
		local tellLocation = ADKP_GetTellLocation();
		ADKP_SendAnnouncement(playerName.." 不在副本内 无法分配 请迅速返回", tellLocation);
		if ADKP_AutoLootData.currentPlayer then
			SendChatMessage(playerName.." 不在副本内 无法分配 请迅速返回", "WHISPER", nil, ADKP_AutoLootData.currentPlayer);
		end
		-- 重置重试计数，因为这不是真正的失败
		ADKP_AutoLootData.retryCount = ADKP_AutoLootData.retryCount - 1;
		-- 延迟重试
		local retryTimer = CreateFrame("Frame");
		retryTimer.timeLeft = 5; -- 等待5秒后重试
		retryTimer:SetScript("OnUpdate", function()
			-- In WoW 1.12 Lua 5.0, use 'this' and 'arg1'
			local frame =  retryTimer -- 使用this或显式引用
			local elapsed = tonumber(arg1) or 0;
			frame.timeLeft = frame.timeLeft - elapsed;
			if frame.timeLeft <= 0 then
				frame:SetScript("OnUpdate", nil);
				ADKP_TryAssignLoot();
			end
		end);
		return;
	end
	
	-- 执行分配
	GiveMasterLoot(foundItemSlot, foundPlayerIndex);
	

end

-- ================================
-- 停止自动分配
-- ================================
function ADKP_StopAutoLoot(success)
	ADKP_AutoLootData.isAssigning = false;
	ADKP_AutoLootData.currentPlayer = nil;
	ADKP_AutoLootData.currentItem = nil;
	ADKP_AutoLootData.currentItemLink = nil;
	ADKP_AutoLootData.currentCost = 0;
	ADKP_AutoLootData.retryCount = 0;
	
	if ADKP_AutoLootData.frame then
		ADKP_AutoLootData.frame:Hide();
	end
end

-- ================================
-- 处理UI错误消息
-- ================================
function ADKP_HandleUIError()
	if not ADKP_AutoLootData.isAssigning then
		return;
	end
	
	local errorMsg = arg1;
	if not errorMsg then
		return;
	end
	
	-- 确保currentPlayer不为nil
	local playerName = ADKP_AutoLootData.currentPlayer or "未知2玩家";
	
	if string.find(errorMsg, "该玩家的物品栏已满") then
		-- 背包已满，继续自动分配模式
		if ADKP_AutoLootData.frame then
			ADKP_AutoLootData.frame.statusText:SetText("背包已满，等待清理背包...");
		end
		local tellLocation = ADKP_GetTellLocation();
		ADKP_SendAnnouncement(playerName.." 背包已满 请清理背包", tellLocation);
		if ADKP_AutoLootData.currentPlayer then
			SendChatMessage(playerName.." 背包已满 请清理背包", "WHISPER", nil, ADKP_AutoLootData.currentPlayer);
		end
		-- 延迟重试
		local retryTimer = CreateFrame("Frame");
		retryTimer.timeLeft = 3; -- 等待3秒后重试
		retryTimer:SetScript("OnUpdate", function()
			-- In WoW 1.12 Lua 5.0, use 'this' and 'arg1'
			local frame =  retryTimer -- 使用this或显式引用
			local elapsed = tonumber(arg1) or 0;
			frame.timeLeft = frame.timeLeft - elapsed;
			if frame.timeLeft <= 0 then
				frame:SetScript("OnUpdate", nil);
				ADKP_TryAssignLoot();
			end
		end);
	elseif string.find(errorMsg, "无法将物品分配给该玩家") then
		-- 玩家不在副本内，继续自动分配模式
		if ADKP_AutoLootData.frame then
			ADKP_AutoLootData.frame.statusText:SetText("玩家不在副本，等待返回...");
		end
		local tellLocation = ADKP_GetTellLocation();
		ADKP_SendAnnouncement(playerName.." 不在副本内 无法分配 请迅速返回", tellLocation);
		if ADKP_AutoLootData.currentPlayer then
			SendChatMessage(playerName.." 不在副本内 无法分配 请迅速返回", "WHISPER", nil, ADKP_AutoLootData.currentPlayer);
		end
		-- 延迟重试
		local retryTimer = CreateFrame("Frame");
		retryTimer.timeLeft = 5; -- 等待5秒后重试
		retryTimer:SetScript("OnUpdate", function()
			-- In WoW 1.12 Lua 5.0, use 'this' and 'arg1'
			local frame =  retryTimer -- 使用this或显式引用
			local elapsed = tonumber(arg1) or 0;
			frame.timeLeft = frame.timeLeft - elapsed;
			if frame.timeLeft <= 0 then
				frame:SetScript("OnUpdate", nil);
				ADKP_TryAssignLoot();
			end
		end);
	else
		-- 其他错误，重试
		if ADKP_AutoLootData.frame then
			ADKP_AutoLootData.frame.statusText:SetText("分配失败，正在重试...（"..ADKP_AutoLootData.retryCount.."/"..ADKP_AutoLootData.maxRetries.."）");
		end
		-- 延迟重试
		local retryTimer = CreateFrame("Frame");
		retryTimer.timeLeft = 1;
		retryTimer:SetScript("OnUpdate", function()
			-- In WoW 1.12 Lua 5.0, use 'this' and 'arg1'
			local frame = retryTimer;
			local elapsed = tonumber(arg1) or 0;
			frame.timeLeft = frame.timeLeft - elapsed;
			if frame.timeLeft <= 0 then
				frame:SetScript("OnUpdate", nil);
				ADKP_TryAssignLoot();
			end
		end);
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

-- 初始化Boss奖励数据，从ADKP_Options加载保存的设置
function ADKP_InitBossAwardData()
	-- 确保ADKP_Options存在
    if not WebDKP_Options then
        WebDKP_Options = {}
    end
    
	-- 确保SubSettings存在
    if not WebDKP_Options["SubSettings"] then
        WebDKP_Options["SubSettings"] = {
            captain = ""
        }
    end
end

-- ================================
-- 处理战斗敌对死亡事件
-- ================================
-- ================================
-- 检查指定名称的单位是否为世界BOSS
-- ================================
-- ================================
-- 处理战斗敌对死亡事件
-- @param message 死亡消息
-- @param isVerifiedBoss 是否已经验证为BOSS（来自SuperWOW RAW_COMBATLOG）
-- ================================
function ADKP_HandleCombatHostileDeath(message, isVerifiedBoss)
    -- 解析消息，提取被杀死的目标名称
    local killedUnitName = ADKP_ExtractBossName(message)

    if killedUnitName then
        -- 如果已经通过SuperWOW验证为BOSS，直接处理，跳过再次验证
        local isBoss = isVerifiedBoss or false

        -- 如果没有验证过，使用传统方式验证
        if not isBoss then
            isBoss = ADKP_IsBossByNamePattern(killedUnitName)
        end

        if isBoss then
            -- 检查BOSS是否在排除名单中
            if ADKP_IsBossExcluded(killedUnitName) then
                return
            end

            -- 检查BOSS死亡弹窗开关
            local isBossPopupEnabled = true
            if WebDKP_Options and WebDKP_Options["BossDeathPopup"] ~= nil then
                isBossPopupEnabled = WebDKP_Options["BossDeathPopup"]
            end

            -- 如果弹窗被关闭，则直接返回，不显示弹窗
            if not isBossPopupEnabled then
                return
            end

            -- 确保ADKP_BossAwardData有killedBoss标志
            if not ADKP_BossAwardData then
                ADKP_BossAwardData = {}
            end

            -- 只要检测到BOSS死亡，就设置标志并记录BOSS名称
            ADKP_BossAwardData.killedBoss = true
            ADKP_BossAwardData.bossName = killedUnitName

            -- 检查玩家是否死亡
            local isPlayerDead = UnitIsDeadOrGhost("player")

            -- 检查玩家是否在战斗中（WoW 1.12兼容方式）
            if isPlayerDead or UnitAffectingCombat("player") then
                -- 玩家死亡或在战斗中，延迟显示弹窗，直到脱战
                ADKP_ScheduleBossAwardFrame()
            else
                -- 玩家未死亡且不在战斗中，立即显示弹窗
                ADKP_ShowBossAwardFrame()
            end
        end
    end
end

-- ================================
-- 安排BOSS奖励窗口在脱战后显示
-- ================================
function ADKP_ScheduleBossAwardFrame()
    -- 创建定时器来检测脱战状态
    if not ADKP_BossAwardData.combatCheckTimer then
        ADKP_BossAwardData.combatCheckTimer = CreateFrame("Frame")
    end
    
    -- 设置定时器脚本（WoW 1.12兼容方式）
    ADKP_BossAwardData.combatCheckTimer:SetScript("OnUpdate", function()
        -- 检查是否已脱战且有BOSS名称
        if not UnitAffectingCombat("player") and ADKP_BossAwardData.bossName and ADKP_BossAwardData.bossName ~= "" then
            -- 检查玩家是否已经复活（如果之前死亡）
            if not UnitIsDeadOrGhost("player") then
                -- 已脱战且已复活，清除定时器
                local frame =  ADKP_BossAwardData.combatCheckTimer
                frame:SetScript("OnUpdate", nil)
                -- 显示弹窗
                ADKP_ShowBossAwardFrame()
            end
        end
    end)
end

-- ================================
-- 从消息中提取BOSS名称
-- ================================
function ADKP_ExtractBossName(message)
    -- 匹配BOSS死亡消息格式，如："拉格纳罗斯死亡了。"
    local patterns = {
        "(.+)死亡了。",
        "(.+)被击败了。",
        "(.+)被消灭了。",
        "(.+)被击杀。",
        "(.+)倒下了。",
        "(.+)死亡了！"
    }

    for _, pattern in ipairs(patterns) do
        local bossName = string.match(message, pattern)
        if bossName then
            -- 只清理首尾空格，不清理其他字符以避免编码问题
            bossName = string.gsub(bossName, "^%s+", "")
            bossName = string.gsub(bossName, "%s+$", "")
            return bossName
        end
    end

    -- 如果没有匹配到任何模式，尝试提取被击杀 of unit
    local killPatterns = {
        "你杀死了(.+)",
        "(.+)被你杀死了",
		"(.+)被.+干掉了",
        "(.+)被.+杀死了"
    }

    for _, pattern in ipairs(killPatterns) do
        local bossName = string.match(message, pattern)
        if bossName then
            -- 只清理首尾空格，不清理其他字符以避免编码问题
            bossName = string.gsub(bossName, "^%s+", "")
            bossName = string.gsub(bossName, "%s+$", "")
            return bossName
        end
    end

    return nil
end

-- ================================
-- 判断是否为BOSS（综合验证）
-- ================================
function ADKP_IsBoss(unitName)
    if not unitName or unitName == "" then
        return false
    end
    
    -- 直接使用名称模式识别BOSS，不再依赖UnitClassification
    return ADKP_IsBossByNamePattern(unitName)
end

-- ================================
-- 使用内嵌多语言BOSS名单，同时保留自定义BOSS名单作为补充
local ADKP_BossLookup = nil

function ADKP_InitBossLookup()
    if ADKP_BossLookup then return end
    ADKP_BossLookup = {}
    
    if not ADKP_RaidBosses then return end
    
    -- 把内嵌的英文和中文Boss名加入查找表
    for zoneKey, zoneInfo in pairs(ADKP_RaidBosses) do
        if zoneInfo.bosses then
            for _, boss in ipairs(zoneInfo.bosses) do
                if boss.en then
                    ADKP_BossLookup[string.lower(boss.en)] = true
                end
                if boss.zh then
                    ADKP_BossLookup[string.lower(boss.zh)] = true
                end
            end
        end
    end
end

-- ================================
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

    -- 1. 优先检查自定义BOSS名单（自定义的无论在不在副本都允许触发）
    local bossPatterns = WebDKP_Options["BossPatterns"] or {}
    for _, bossName in ipairs(bossPatterns) do
        if string.lower(bossName) == nameLower then
            return true
        end
    end

    -- 2. 检查内嵌的团队副本 Boss 名单 (包含多语言)
    if ADKP_BossLookup[nameLower] then
        return true
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
        WebDKP_Options["BossPatterns"] = {
            "拉格纳罗斯", "奥妮克希亚",
        }
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
        ADKP_BossAwardData.bossName = ""
        ADKP_BossAwardData.killedBoss = false
    end)
    
    -- ==================== 左侧：自定义与排除名单 ====================
    -- 自定义BOSS名单区域
    frame.customAddLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.customAddLabel:SetPoint("TOPLEFT", 20, -45)
    frame.customAddLabel:SetText("添加自定义BOSS名称:")
    
    frame.customAddEditBox = CreateFrame("EditBox", "ADKP_CustomBossAddEditBox", frame, "InputBoxTemplate")
    frame.customAddEditBox:SetWidth(200)
    frame.customAddEditBox:SetHeight(20)
    frame.customAddEditBox:SetPoint("TOPLEFT", 30, -70)
    frame.customAddEditBox:SetAutoFocus(false)
    frame.customAddEditBox:SetBackdropColor(0, 0, 0, 0.8)
    frame.customAddEditBox:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
    
    frame.customAddButton = CreateFrame("Button", nil, frame, "GameMenuButtonTemplate")
    frame.customAddButton:SetWidth(80)
    frame.customAddButton:SetHeight(25)
    frame.customAddButton:SetPoint("LEFT", frame.customAddEditBox, "RIGHT", 10, 0)
    frame.customAddButton:SetText("添加")
    frame.customAddButton:SetScript("OnClick", function()
        local bossName = frame.customAddEditBox:GetText()
        if bossName and bossName ~= "" then
            ADKP_AddCustomBoss(bossName)
            frame.customAddEditBox:SetText("")
            ADKP_UpdateBossListFrame(frame)
        end
    end)
    
    -- 自定义BOSS列表框背景
    frame.customListBg = CreateFrame("Frame", nil, frame)
    frame.customListBg:SetWidth(310)
    frame.customListBg:SetHeight(150)
    frame.customListBg:SetPoint("TOPLEFT", 20, -100)
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
    frame.excludedAddEditBox:SetWidth(200)
    frame.excludedAddEditBox:SetHeight(20)
    frame.excludedAddEditBox:SetPoint("TOPLEFT", 30, -280)
    frame.excludedAddEditBox:SetAutoFocus(false)
    frame.excludedAddEditBox:SetBackdropColor(0, 0, 0, 0.8)
    frame.excludedAddEditBox:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
    
    frame.excludedAddButton = CreateFrame("Button", nil, frame, "GameMenuButtonTemplate")
    frame.excludedAddButton:SetWidth(80)
    frame.excludedAddButton:SetHeight(25)
    frame.excludedAddButton:SetPoint("LEFT", frame.excludedAddEditBox, "RIGHT", 10, 0)
    frame.excludedAddButton:SetText("添加")
    frame.excludedAddButton:SetScript("OnClick", function()
        local bossName = frame.excludedAddEditBox:GetText()
        if bossName and bossName ~= "" then
            ADKP_AddExcludedBoss(bossName)
            frame.excludedAddEditBox:SetText("")
            ADKP_UpdateBossListFrame(frame)
        end
    end)
    
    -- 排除名单列表框背景
    frame.excludedListBg = CreateFrame("Frame", nil, frame)
    frame.excludedListBg:SetWidth(310)
    frame.excludedListBg:SetHeight(150)
    frame.excludedListBg:SetPoint("TOPLEFT", 20, -305)
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
    
    -- 副本列表框背景
    frame.raidListBg = CreateFrame("Frame", nil, frame)
    frame.raidListBg:SetWidth(330)
    frame.raidListBg:SetHeight(355)
    frame.raidListBg:SetPoint("TOPLEFT", 370, -70)
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
    
    -- 显示所有自定义BOSS
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
        listItem.removeButton:SetWidth(60)
        listItem.removeButton:SetHeight(itemHeight - 3)
        listItem.removeButton:SetPoint("TOPRIGHT", -10, -yOffset + 1)
        listItem.removeButton:SetText("删除")
        listItem.removeButton.bossIndex = i
        listItem.removeButton:SetScript("OnClick", function()
            ADKP_RemoveCustomBoss(this.bossIndex)
            ADKP_UpdateBossListFrame(frame)
        end)
        listItem.removeButton:Show()
        
        table.insert(frame.customListItems, listItem)
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
                name = zoneInfo.name_zh,
                info = zoneInfo
            })
            if ADKP_RaidZoneExpanded[zoneKey] then
                for _, boss in ipairs(zoneInfo.bosses) do
                    table.insert(visibleLines, {
                        type = "boss",
                        zoneKey = zoneKey,
                        boss = boss,
                        name = boss.zh
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
            
            frame.raidListItems[i] = item
        end
        
        item.mainFrame = frame
        item:ClearAllPoints()
        item:SetPoint("TOPLEFT", 0, -(i-1)*lineGap)
        item:Show()
        
        -- 根据类型设置布局与交互
        if lineData.type == "zone" then
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
        ADKP_ExcludedBossesFrame:Show()
    end
    
    if ADKP_Frame then
        ADKP_Frame:Hide()
    end
end

-- ================================
-- 显示BOSS奖励窗口
-- ================================
function ADKP_ShowBossAwardFrame()
    if not ADKP_BossAwardData.frame then
        ADKP_CreateBossAwardFrame()
    end
    
    local frame = ADKP_BossAwardData.frame
    if frame then
        -- 设置BOSS名称
        frame.bossNameText:SetText("BOSS: " .. (ADKP_BossAwardData.bossName or "未知"))
        -- 设置默认分数
        frame.pointsEditBox:SetText(ADKP_BossAwardData.points)
        

        
        -- 显示窗口
        frame:Show()
    end
end

-- ================================
-- 创建BOSS奖励窗口
-- ================================
function ADKP_CreateBossAwardFrame()
    local frame = CreateFrame("Frame", "ADKP_BossAwardFrame", UIParent)
    frame:SetWidth(300)
    frame:SetHeight(160) -- 增加高度以容纳打卡复选框
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 300)
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
    frame.title:SetText("BOSS击杀奖励")
    
	-- 关闭按钮
    frame.closeButton = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    frame.closeButton:SetPoint("TOPRIGHT", -10, -10)
    frame.closeButton:SetScript("OnClick", function()
        frame:Hide()
    end)
    
	-- BOSS名称显示
    frame.bossNameText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.bossNameText:SetPoint("TOP", 0, -40)
    frame.bossNameText:SetText("BOSS: " .. (ADKP_BossAwardData.bossName or "未知"))
    

    
	-- 分数输入框
    frame.pointsLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.pointsLabel:SetPoint("TOPLEFT", 20, -70)
    frame.pointsLabel:SetText("分数:")
    
    frame.pointsEditBox = CreateFrame("EditBox", "ADKP_BossAwardPointsEditBox", frame, "InputBoxTemplate")
    frame.pointsEditBox:SetWidth(60)
    frame.pointsEditBox:SetHeight(20)
    frame.pointsEditBox:SetPoint("LEFT", frame.pointsLabel, "RIGHT", 10, 0)
    frame.pointsEditBox:SetAutoFocus(false)
    frame.pointsEditBox:SetNumeric(true)
    frame.pointsEditBox:SetText(ADKP_BossAwardData.points)
    
	-- 设置背景
    frame.pointsEditBox:SetBackdropColor(0, 0, 0, 0.8)
    frame.pointsEditBox:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
    
	-- 设置文字居中显示
    frame.pointsEditBox:SetJustifyH("CENTER")
    frame.pointsEditBox:SetJustifyV("MIDDLE")

    frame.pointsEditBox:SetScript("OnTextChanged", function()
        local points = tonumber(frame.pointsEditBox:GetText())
        if points then
            ADKP_BossAwardData.points = points
        end
    end)
    
	-- DKP列表下拉框（移到分数右边）
    frame.tableLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.tableLabel:SetPoint("LEFT", frame.pointsEditBox, "RIGHT", 10, 0)
    frame.tableLabel:SetText("列表:")
    
    frame.tableDropdown = CreateFrame("Frame", "ADKP_BossAwardTableDropdown", frame, "UIDropDownMenuTemplate")
    frame.tableDropdown:SetPoint("LEFT", frame.tableLabel, "RIGHT", -10, 0)
    frame.tableDropdown:SetWidth(90)
    
	-- 初始化下拉菜单
    UIDropDownMenu_Initialize(frame.tableDropdown, ADKP_BossAwardTableDropdown_Init)
    
	-- 设置默认选择
    ADKP_BossAwardData.tableid = ADKP_BossAwardData.tableid or 1
	-- 延迟设置下拉菜单选择，避免在初始化过程中访问未设置的frame字段
    frame:SetScript("OnShow", function()
        UIDropDownMenu_SetSelectedID(frame.tableDropdown, ADKP_BossAwardData.tableid)
        -- 使用UIDropDownMenu_SetWidth来正确设置下拉框宽度
        UIDropDownMenu_SetWidth(90, frame.tableDropdown)
        
        -- 获取并设置当前选中的表名称作为下拉菜单显示文本
        if WebDKP_Tables then
            for name, tableData in pairs(WebDKP_Tables) do
                if tableData["id"] == ADKP_BossAwardData.tableid then
                    UIDropDownMenu_SetText(name, frame.tableDropdown)
                    break
                end
            end
        end
        

    end)
    
    local function BossAwardRunRaidAndSub()
        local pointsText = frame.pointsEditBox:GetText() or ""
        if pointsText == "" then
            ADKP_Print("请输入分数")
            return
        end
        local reason = "击杀-" .. (ADKP_BossAwardData.bossName or "未知BOSS")
        -- 临时设置原因和分数，复用统一的大团+替补奖惩入口。
        local prevReason = ADKP_AwardDKP_FrameReason
        local prevPoints = ADKP_AwardDKP_FramePoints
        ADKP_AwardDKP_FrameReason = { GetText = function() return reason end }
        ADKP_AwardDKP_FramePoints = { GetText = function() return pointsText end }
        ADKP_AwardRaidAndSub_Event()
        ADKP_AwardDKP_FrameReason = prevReason
        ADKP_AwardDKP_FramePoints = prevPoints
        frame:Hide()
    end

	-- 全员加分按钮
    frame.awardAllButton = CreateFrame("Button", nil, frame, "GameMenuButtonTemplate")
    frame.awardAllButton:SetWidth(100)
    frame.awardAllButton:SetHeight(25)
    frame.awardAllButton:SetPoint("BOTTOMLEFT", 30, 45)
    frame.awardAllButton:SetText("全员加分")
    frame.awardAllButton:SetScript("OnClick", BossAwardRunRaidAndSub)
    
	-- 替补计时分钟输入框
    frame.subTimeLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.subTimeLabel:SetPoint("LEFT", frame.awardAllButton, "RIGHT", 30, 0)
    frame.subTimeLabel:SetText("分钟:")
    
    frame.subTimeEditBox = CreateFrame("EditBox", "ADKP_BossAwardSubTimeEditBox", frame, "InputBoxTemplate")
    frame.subTimeEditBox:SetWidth(60)
    frame.subTimeEditBox:SetHeight(20)
    frame.subTimeEditBox:SetPoint("LEFT", frame.subTimeLabel, "RIGHT", 10, 0)
    frame.subTimeEditBox:SetAutoFocus(false)
    frame.subTimeEditBox:SetNumeric(true)
    frame.subTimeEditBox:SetText(ADKP_BossAwardData.subTime) -- 默认5分钟
    

    frame.subTimeEditBox:SetBackdropColor(0, 0, 0, 0.8)
    frame.subTimeEditBox:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
    
	-- 设置文字居中显示
    frame.subTimeEditBox:SetJustifyH("CENTER")
    frame.subTimeEditBox:SetJustifyV("MIDDLE")

    
    frame.subTimeEditBox:SetScript("OnTextChanged", function()
        local time = tonumber(frame.subTimeEditBox:GetText())
        if time and time > 0 then
            ADKP_BossAwardData.subTime = time
        end
    end)
    
	-- 全员加分 + 替补按钮（直接执行，无二次弹窗）
    frame.awardAllWithSubButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.awardAllWithSubButton:SetWidth(140)
    frame.awardAllWithSubButton:SetHeight(28)
    frame.awardAllWithSubButton:SetPoint("BOTTOMRIGHT", -30, 20)
    frame.awardAllWithSubButton:SetText("|cff00ff00全员加分+替补|r")
    frame.awardAllWithSubButton:SetScript("OnClick", BossAwardRunRaidAndSub)
    
	-- 手动按钮
    frame.manualButton = CreateFrame("Button", nil, frame, "GameMenuButtonTemplate")
    frame.manualButton:SetWidth(100)
    frame.manualButton:SetHeight(25)
    frame.manualButton:SetPoint("BOTTOMLEFT", 30, 20)
    frame.manualButton:SetText("手动")
    frame.manualButton:SetScript("OnClick", function()
        frame:Hide()
        -- 打开主窗口的奖惩DKP页
        ADKP_Frame:Show()
        -- 设置主窗口的DKP列表选择
        ADKP_Frame.selectedTableid = ADKP_BossAwardData.tableid
        -- 切换到奖惩DKP页（通常是第二个标签）
        getglobal("ADKP_FrameTab2"):Click()
        -- 填充原因字段
        ADKP_AwardDKP_FrameReason:SetText("击杀-" .. (ADKP_BossAwardData.bossName or "未知BOSS"))
        -- 填充分数字段
        ADKP_AwardDKP_FramePoints:SetText(ADKP_BossAwardData.points)
        -- 刷新主界面的列表显示
        ADKP_Tables_DropDown_Init()
        -- 确保DKP列表下拉框正确显示/隐藏
        ADKP_Tables_DropDown_OnLoad()
    end)
    
    frame:Hide()
    ADKP_BossAwardData.frame = frame
    return frame
end

-- ================================
-- 创建替补加分面板
-- ================================
function ADKP_CreateSubAwardFrame()
    if not ADKP_SubAwardData then
        ADKP_SubAwardData = {
            active = false,
            captain = "",
            reason = "",
            points = 0,
            bossName = ""
        }
    end
    
    local frame = CreateFrame("Frame", "ADKP_SubAwardFrame", UIParent)
    frame:SetWidth(320)
    frame:SetHeight(200)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 250)
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
    frame.title:SetText("替补加分")
    
	-- 关闭按钮
    frame.closeButton = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    frame.closeButton:SetPoint("TOPRIGHT", -10, -10)
    frame.closeButton:SetScript("OnClick", function()
        ADKP_SubAwardData.active = false
        frame:Hide()
    end)
    
	-- BOSS名称显示
    frame.bossNameText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.bossNameText:SetPoint("TOP", 0, -50)
    frame.bossNameText:SetText("BOSS: " .. (ADKP_SubAwardData.bossName or "未知"))
    
	-- 替补队队长输入框
    frame.captainLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.captainLabel:SetPoint("TOPLEFT", 20, -70)
    frame.captainLabel:SetText("替补队队长:")
    
    frame.captainEditBox = CreateFrame("EditBox", "ADKP_SubAwardCaptainEditBox", frame, "InputBoxTemplate")
    frame.captainEditBox:SetWidth(150)
    frame.captainEditBox:SetHeight(20)
    frame.captainEditBox:SetPoint("LEFT", frame.captainLabel, "RIGHT", 10, 0)
    frame.captainEditBox:SetAutoFocus(false)
    frame.captainEditBox:SetText(ADKP_SubAwardData.captain)
    frame.captainEditBox:SetBackdropColor(0, 0, 0, 0.8)
    frame.captainEditBox:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
    frame.captainEditBox:SetJustifyH("LEFT")
    frame.captainEditBox:SetJustifyV("MIDDLE")
    
    frame.captainEditBox:SetScript("OnTextChanged", function()
			ADKP_SubAwardData.captain = frame.captainEditBox:GetText()
			-- 保存到ADKP_Options，确保设置持久化
			if WebDKP_Options and WebDKP_Options["SubSettings"] then
				WebDKP_Options["SubSettings"].captain = ADKP_SubAwardData.captain
			end
    end)
    
	-- 原因输入框
    frame.reasonLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.reasonLabel:SetPoint("TOPLEFT", 20, -100)
    frame.reasonLabel:SetText("原因:")
    
    frame.reasonEditBox = CreateFrame("EditBox", "ADKP_SubAwardReasonEditBox", frame, "InputBoxTemplate")
    frame.reasonEditBox:SetWidth(230)
    frame.reasonEditBox:SetHeight(20)
    frame.reasonEditBox:SetPoint("LEFT", frame.reasonLabel, "RIGHT", 10, 0)
    frame.reasonEditBox:SetAutoFocus(false)
    frame.reasonEditBox:SetText(ADKP_SubAwardData.reason)
    frame.reasonEditBox:SetBackdropColor(0, 0, 0, 0.8)
    frame.reasonEditBox:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
    frame.reasonEditBox:SetJustifyH("LEFT")
    frame.reasonEditBox:SetJustifyV("MIDDLE")
    
    frame.reasonEditBox:SetScript("OnTextChanged", function()
        ADKP_SubAwardData.reason = frame.reasonEditBox:GetText()
    end)
    
	-- 分数输入框
    frame.pointsLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.pointsLabel:SetPoint("TOPLEFT", 20, -130)
    frame.pointsLabel:SetText("分数:")
   
    frame.pointsEditBox = CreateFrame("EditBox", "ADKP_SubAwardPointsEditBox", frame, "InputBoxTemplate")
    frame.pointsEditBox:SetWidth(60)
    frame.pointsEditBox:SetHeight(20)
    frame.pointsEditBox:SetPoint("LEFT", frame.pointsLabel, "RIGHT", 10, 0)
    frame.pointsEditBox:SetAutoFocus(false)
    frame.pointsEditBox:SetNumeric(true)
    frame.pointsEditBox:SetText(points or "")
    frame.pointsEditBox:SetBackdropColor(0, 0, 0, 0.8)
    frame.pointsEditBox:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
    frame.pointsEditBox:SetJustifyH("CENTER")
    frame.pointsEditBox:SetJustifyV("MIDDLE")
    local points = frame.pointsEditBox:GetText() or ADKP_SubAwardData.points
    frame.pointsEditBox:SetScript("OnTextChanged", function()
        local points = tonumber(frame.pointsEditBox:GetText())
        if points then
            ADKP_SubAwardData.points = points
        end
    end)
    
	-- 搜索替补队员按钮
    frame.searchButton = CreateFrame("Button", nil, frame, "GameMenuButtonTemplate")
    frame.searchButton:SetWidth(120)
    frame.searchButton:SetHeight(25)
    frame.searchButton:SetPoint("LEFT", frame.pointsEditBox, "RIGHT", 20, 0)
    frame.searchButton:SetText("搜索替补队员")
    frame.searchButton:SetScript("OnClick", function()
        ADKP_SearchSubMembers()
    end)

    
	-- 加分按钮
    frame.awardButton = CreateFrame("Button", nil, frame, "GameMenuButtonTemplate")
    frame.awardButton:SetWidth(100)
    frame.awardButton:SetHeight(25)
    frame.awardButton:SetPoint("BOTTOMRIGHT", -30, 20)
    frame.awardButton:SetText("加分")
    frame.awardButton:SetScript("OnClick", function()
        -- 确保ADKP_SubAwardData存在并包含所有必要字段
        if not ADKP_SubAwardData then
            ADKP_SubAwardData = {
                captain = "",
                reason = "",
                points = 0,
                bossName = ""
            }
            ADKP_Print("警告: ADKP_SubAwardData 未初始化，已创建默认对象")
        end
        
        -- 同步UI输入到ADKP_SubAwardData
        ADKP_SubAwardData.captain = ADKP_SubAwardData.points or frame.captainEditBox:GetText() or ""
        ADKP_SubAwardData.reason = frame.reasonEditBox:GetText() or ""
        local pointsText = frame.pointsEditBox:GetText() or "0"
        ADKP_SubAwardData.points = tonumber(pointsText) or 0
        
        -- 调试信息
        -- ADKP_Print("加分按钮点击: captain='" .. ADKP_SubAwardData.captain .. "', reason='" .. ADKP_SubAwardData.reason .. "', points='" .. ADKP_SubAwardData.points .. "'")
        
        -- 只检查队长名称，其他验证在ADKP_AwardSubPoints中处理
        if ADKP_SubAwardData.captain == "" then
            ADKP_Print("请输入替补队队长名称")
            frame.captainEditBox:SetFocus()
            frame.captainEditBox:HighlightText()
            PlaySound("igQuestFailed")
            return
        end
        
        -- 直接调用ADKP_AwardSubPoints函数，让它处理其他验证和自动设置默认值
        ADKP_AwardSubPoints()
    end)
    
	-- 取消按钮
    frame.cancelButton = CreateFrame("Button", nil, frame, "GameMenuButtonTemplate")
    frame.cancelButton:SetWidth(100)
    frame.cancelButton:SetHeight(25)
    frame.cancelButton:SetPoint("BOTTOMLEFT", 30, 20)
    frame.cancelButton:SetText("取消")
    frame.cancelButton:SetScript("OnClick", function()
        ADKP_SubAwardData.active = false
        frame:Hide()
    end)
    
	-- 初始化
        ADKP_SubAwardData.frame = frame
        frame:Hide()
        return frame
    end

-- 初始化替补队员数据存储
ADKP_PendingSubMembers = ADKP_PendingSubMembers or {}

-- ================================
-- 显示替补加分面板
-- ================================
function ADKP_ShowSubAwardFrame(requireCaptainSetup)
    if not ADKP_SubAwardData then
        ADKP_SubAwardData = {
            active = false,
            captain = "",
            reason = "",
            points = 0,
            bossName = ""
        }
        ADKP_Print("ADKP_SubAwardData 已初始化")
    end
    
	-- 复制BOSS奖励数据
    ADKP_SubAwardData.bossName = ADKP_BossAwardData.bossName or ""
    
    ADKP_SubAwardData.points = ADKP_BossAwardData.points or 0
    
	-- 调试信息
	-- ADKP_Print("ADKP_ShowSubAwardFrame调试: bossName='" .. (ADKP_SubAwardData.bossName or "nil") .. "', points='" .. (ADKP_SubAwardData.points or "nil") .. "'")
    
	-- 保留bossName-替补格式，但处理空值情况
    if ADKP_SubAwardData.bossName and ADKP_SubAwardData.bossName ~= "" then
        ADKP_SubAwardData.reason = ADKP_SubAwardData.bossName .. "-替补"
        ADKP_Print("设置默认原因: " .. ADKP_SubAwardData.reason)
    else
        ADKP_SubAwardData.reason = "替补" -- 当bossName为空时使用默认值
        ADKP_Print("设置默认原因(空bossName): " .. ADKP_SubAwardData.reason)
    end
    

    
    if not ADKP_SubAwardData.frame then
        ADKP_CreateSubAwardFrame()
    end
    
    local frame = ADKP_SubAwardData.frame
    if frame then
        -- 更新UI显示
        frame.bossNameText:SetText("BOSS: " .. ADKP_SubAwardData.bossName)
        frame.captainEditBox:SetText(ADKP_SubAwardData.captain)
        frame.reasonEditBox:SetText(ADKP_SubAwardData.reason)
        frame.pointsEditBox:SetText(ADKP_SubAwardData.points)
        

        
        -- 如果需要设置替补队长，显示提示消息
        if requireCaptainSetup then
            if not ADKP_SubAwardData.setupNotice then
                ADKP_SubAwardData.setupNotice = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                ADKP_SubAwardData.setupNotice:SetPoint("TOP", 0, -35)
                ADKP_SubAwardData.setupNotice:SetTextColor(1, 0.5, 0) -- 橙色文字
            end
            ADKP_SubAwardData.setupNotice:SetText("请设置替补队长后再进行操作")
            ADKP_SubAwardData.setupNotice:Show()
        else
            -- 隐藏提示消息
            if ADKP_SubAwardData.setupNotice then
                ADKP_SubAwardData.setupNotice:Hide()
            end
        end
        
        -- 清空之前的队员列表
        if ADKP_PendingSubMembers then
            ADKP_PendingSubMembers = {}
        end
        
        -- 激活状态
        ADKP_SubAwardData.active = true
        
        -- 显示窗口
        frame:Show()
        
        -- 隐藏BOSS奖励窗口
        if ADKP_BossAwardData.frame then
            ADKP_BossAwardData.frame:Hide()
        end
    end
end

-- ================================
-- 搜索替补队员
-- ================================
function ADKP_SearchSubMembers()
	-- 确保ADKP_SubAwardData对象存在并包含所有必要字段
    if not ADKP_SubAwardData then
        ADKP_SubAwardData = {
            active = false,
            captain = "",
            reason = "",
            points = 0,
            bossName = ""
        }
        ADKP_Print("警告: ADKP_SubAwardData 未初始化，已创建默认对象")
    end
   
	-- 确保所有必要字段都有默认值
    ADKP_SubAwardData.captain =  ADKP_SubAwardData.captain or ""
    ADKP_SubAwardData.reason = ADKP_SubAwardData.reason or ""
    ADKP_SubAwardData.points =  ADKP_SubAwardData.points or 0
    ADKP_SubAwardData.bossName = ADKP_SubAwardData.bossName or ""
    
	-- 从UI获取最新的队长名称 - 修复从正确的UI元素获取数据
    if ADKP_AwardDKP_FrameSubLeader then
        ADKP_SubAwardData.captain = ADKP_AwardDKP_FrameSubLeader:GetText()
    elseif ADKP_SubAwardData.frame and ADKP_SubAwardData.frame.captainEditBox then
        ADKP_SubAwardData.captain = ADKP_SubAwardData.frame.captainEditBox:GetText()
    end
    
    local captain = ""
    if ADKP_SubAwardFrame and ADKP_SubAwardFrame.captainEditBox then
        captain = ADKP_SubAwardFrame.captainEditBox:GetText() or ""
    end
    captain = captain or ADKP_SubAwardData.captain
    if not captain or captain == "" then
        ADKP_Print("请输入替补队队长名称")
        return
    end
    
	-- 初始化或清空替补队员列表
    if not ADKP_PendingSubMembers then
        ADKP_PendingSubMembers = {}
    end
    
	-- 清空之前可能存在的该队长的队员信息
    ADKP_PendingSubMembers[string.lower(captain)] = nil
    ADKP_PendingSubMembers[captain] = nil
    
	-- 直接向队长发送耳语消息，不再检查是否在团队中
    ADKP_Print("搜索替补队员: " .. captain)
    
	-- 发送通信指令 - 修复为使用与boss击杀弹窗相同的通信方式
    local lowercaseCaptain = string.lower(captain)
    local message = lowercaseCaptain
    
	-- 1. 首先使用RAID频道尝试发送（如果在团队中）
    if GetNumRaidMembers() > 0 then
        pcall(SendAddonMessage, "AMB_TBQQ", message, "RAID")
    end
    
	-- 2. 使用guild频道发送消息（主要方式）
    pcall(SendAddonMessage, "AMB_TBQQ", message, "GUILD")
    
	-- 3. 同时尝试使用whisper频道发送消息（最可靠的点对点方式）
    pcall(SendAddonMessage, "AMB_TBQQ", message, "WHISPER", captain)
    
	-- 4. 也尝试使用PARTY频道（如果在队伍中）
    if GetNumPartyMembers() > 0 and GetNumRaidMembers() == 0 then
        pcall(SendAddonMessage, "AMB_TBQQ", message, "PARTY")
    end
    
	-- 设置定时器等待响应
    if not ADKP_SubAwardData.timer then
        ADKP_SubAwardData.timer = CreateFrame("Frame")
    end
    
	-- 重置响应标志
    ADKP_SubAwardData.receivedResponse = false
    

end



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

-- 将英文职业名规范化为中文（用于显示）
function ADKP_NormalizeClassName(className)
	if not className then return className end
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

    if ADKP_AwardDKP_FrameSubLeader then
        captain = ADKP_AwardDKP_FrameSubLeader:GetText() or ""
    end
    if captain == "" and ADKP_SubAwardData and ADKP_SubAwardData.captain then
        captain = ADKP_SubAwardData.captain or ""
    end
    if captain == "" and WebDKP_Options and WebDKP_Options["SubSettings"] and WebDKP_Options["SubSettings"].captain then
        captain = WebDKP_Options["SubSettings"].captain or ""
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

    if subCount == 0 and ADKP_SubData and ADKP_SubData.subs then
        for memberName, info in pairs(ADKP_SubData.subs) do
            if lowerCaptain and string.lower(memberName) == lowerCaptain then
                -- skip sub captain when unchecked
            elseif not ADKP_PlayerInGroup(memberName) then
                subCount = subCount + 1
                local className = (info and info.class) or ADKP_GetPlayerClass(memberName) or "战士"
                subPlayers[subCount] = {
                    name = memberName,
                    class = ADKP_NormalizeClassName(className)
                }
            end
        end
    end

    if subCount == 0 then
        return nil, 0
    end

    return subPlayers, subCount
end

function ADKP_AwardRaidAndSub_Event_LegacyUnused()
    local pointsText = ""
    local reason = ""

    if ADKP_AwardDKP_FramePoints then
        pointsText = ADKP_AwardDKP_FramePoints:GetText() or ""
    end
    if ADKP_AwardDKP_FrameReason then
        reason = ADKP_AwardDKP_FrameReason:GetText() or ""
    end

    if pointsText == "" then
        ADKP_Print("您必须输入DKP.");
        PlaySound("igQuestFailed");
        return
    end

    local points = ADKP_ROUND(pointsText, 2)
    if (type(points) ~= "number" or points ~= points) then
        ADKP_Print("DKP点数必须是有效数字");
        PlaySound("igQuestFailed");
        return
    end

    local function beginAward()
        local captain = ""
        if ADKP_AwardDKP_FrameSubLeader then
            captain = ADKP_AwardDKP_FrameSubLeader:GetText() or ""
        end

        -- Update subs from captain if provided.
        if captain ~= "" and ADKP_SearchSubMembers_Event then
            ADKP_SearchSubMembers_Event()
        end

        local function doAward()
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

            local awardedRaidCount = 0
            if raidCount > 0 then
                ADKP_AddDKP(points, reason, "false", raidPlayers)
                ADKP_AnnounceAward(points, reason)
                awardedRaidCount = raidCount
            end

            local subPlayers, subCount = ADKP_GetSubMembersForAward()
            local awardedSubCount = 0
            if not subPlayers then
                ADKP_Print("未找到替补队员名单，请先点击搜索替补队员。")
                subCount = 0
            else
                local useHalf = false
                if ADKP_AwardDKP_FrameSubHalfPoints then
                    useHalf = ADKP_AwardDKP_FrameSubHalfPoints:GetChecked() and true or false
                elseif WebDKP_Options then
                    useHalf = WebDKP_Options["SubHalfPointsEnabled"] and true or false
                end

                local sameReason = false

                local subPoints = points
                if useHalf then
                    subPoints = ADKP_ROUND(points / 2, 2)
                end

                local subReason = reason
                if not sameReason then
                    if subReason == "" then
                        subReason = "替补"
                    else
                        subReason = subReason .. "-替补"
                    end
                end

                ADKP_AddDKP(subPoints, subReason, "false", subPlayers)
                ADKP_AnnounceAward(subPoints, subReason)
                ADKP_Print("已为 " .. subCount .. " 名替补加分: " .. subPoints)
                awardedSubCount = subCount
            end

            ADKP_UpdateTableToShow()
            ADKP_UpdateTable()
            if ADKP_UpdateLootList then
                ADKP_UpdateLootList()
            end

            if awardedRaidCount > 0 or awardedSubCount > 0 then
                local announceText = "已为团队" .. awardedRaidCount .. "和替补" .. awardedSubCount .. "调整DKP " .. points
                local channel = "NONE"
                if GetNumRaidMembers() > 0 then
                    channel = "RAID"
                elseif GetNumPartyMembers() > 0 then
                    channel = "PARTY"
                end
	                if ADKP_SendAnnouncement then
	                    ADKP_SendAnnouncement(announceText, channel)
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
        end

        if captain == "" then
            doAward()
            return
        end

        if not ADKP_SubAwardData then
            ADKP_SubAwardData = {}
        end
        ADKP_SubAwardData.receivedResponse = false

        local waitFrame = CreateFrame("Frame")
        waitFrame.startTime = GetTime()
        waitFrame:SetScript("OnUpdate", function()
            local frame = this or waitFrame
            local elapsed = GetTime() - (frame.startTime or 0)
            local responded = ADKP_SubAwardData and ADKP_SubAwardData.receivedResponse
            if responded or elapsed >= 2 then
                frame:SetScript("OnUpdate", nil)
                doAward()
            end
        end)
    end

    if not StaticPopupDialogs then
        StaticPopupDialogs = {}
    end
    if not StaticPopupDialogs["ADKP_AWARD_RAID_SUB_CONFIRM"] then
        StaticPopupDialogs["ADKP_AWARD_RAID_SUB_CONFIRM"] = {
            text = "",
            button1 = "确定",
            button2 = "取消",
            OnAccept = function()
                local dialog = StaticPopupDialogs["ADKP_AWARD_RAID_SUB_CONFIRM"]
                if dialog and dialog._confirmCallback then
                    dialog._confirmCallback()
                end
            end,
            timeout = 0,
            whileDead = 1,
            hideOnEscape = 1
        }
    end

    local reasonText = reason
    if reasonText == "" then
        reasonText = "无"
    end
    StaticPopupDialogs["ADKP_AWARD_RAID_SUB_CONFIRM"].text = "确定要为团队和替补调整DKP吗？\n分数: " .. points .. "\n原因: " .. reasonText
    StaticPopupDialogs["ADKP_AWARD_RAID_SUB_CONFIRM"]._confirmCallback = beginAward
    StaticPopup_Show("ADKP_AWARD_RAID_SUB_CONFIRM")
end

-- ================================
-- 获取替补队长名称（悬浮窗与加分流程共用）
-- ================================
local function ADKP_Z_GetCaptainName()
    local captain = ""
    if ADKP_Options_FrameSubLeader then
        captain = ADKP_Options_FrameSubLeader:GetText() or ""
    end
    if captain == "" and ADKP_AwardDKP_FrameSubLeader then
        captain = ADKP_AwardDKP_FrameSubLeader:GetText() or ""
    end
    if captain == "" and ADKP_SubAwardData and ADKP_SubAwardData.captain then
        captain = ADKP_SubAwardData.captain or ""
    end
    if captain == "" and WebDKP_Options and WebDKP_Options["SubSettings"] and WebDKP_Options["SubSettings"].captain then
        captain = WebDKP_Options["SubSettings"].captain or ""
    end
    captain = ADKP_TrimText(captain)
    return captain
end

-- ================================
-- 按主替独立分值执行加分（悬浮窗与加分流程共用）
-- ================================
local function ADKP_Z_ApplyAward(raidPoints, subPoints, reason)
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

    local awardedRaidCount = 0
    if raidPlayers and raidCount > 0 then
        ADKP_AddDKP(raidPoints, reason, "false", raidPlayers)
        ADKP_AnnounceAward(raidPoints, reason)
        awardedRaidCount = raidCount
    end

    local subPlayersAll, subCountAll = ADKP_GetSubMembersForAward()
    local awardedSubCount = 0
    if subPlayersAll and subCountAll > 0 then
        local subReason = reason
        if subReason == "" then
            subReason = "替补"
        else
            subReason = subReason .. "-替补"
        end
        ADKP_AddDKP(subPoints, subReason, "false", subPlayersAll)
        ADKP_AnnounceAward(subPoints, subReason)
        awardedSubCount = subCountAll
    end

    ADKP_UpdateTableToShow()
    ADKP_UpdateTable()
    if ADKP_UpdateLootList then
        ADKP_UpdateLootList()
    end

    if awardedRaidCount > 0 or awardedSubCount > 0 then
        local announceText = "已按主替独立分值调整DKP，主团" .. awardedRaidCount .. "，替补" .. awardedSubCount
        local channel = "NONE"
        if GetNumRaidMembers() > 0 then
            channel = "RAID"
        elseif GetNumPartyMembers() > 0 then
            channel = "PARTY"
        end
        if ADKP_SendAnnouncement then
            ADKP_SendAnnouncement(announceText, channel)
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
end


-- ================================
-- 快捷浮窗：集 / 散 / 杀 / 调
-- 说明：
-- 1) 仅在 RAID 团队中显示（GetNumRaidMembers() > 0）
-- 2) 在“自用”Tab 勾选 WebDKP_Options["QuickFloatEnabled"] 后才显示
-- 3) 左键：按已保存的默认分值执行（带确认）
-- 4) 右键：弹出设置小窗；集/散/杀设置主队和替补分值，调设置分数/玩家/原因
-- 语义对应：
-- - 集：等同 /adkpa（原因=集合分，受排除未报名/未出勤扣分影响）
-- - 散：等同 /adkpb（原因=解散分）
-- - 杀：等同 /adkpk（原因=击杀-目标名/原因）
-- - 调：等同 /adkpc（单目标奖惩；玩家可选，缺省当前目标；原因可选，缺省=菜出天际-犯错）
-- 注意：集/散/杀使用主队/替补独立分值；调始终是单目标奖惩

local function ADKP_QuickFloat_InitOptions()
    if not WebDKP_Options then
        WebDKP_Options = {}
    end
    if WebDKP_Options["QuickFloatEnabled"] == nil then
        WebDKP_Options["QuickFloatEnabled"] = true
    end
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
    if key == "adjust" then return "调" end
    return "?"
end

local function ADKP_QuickFloat_GetActionName(key)
    if key == "rally" then return "集合分" end
    if key == "dismiss" then return "解散分" end
    if key == "kill" then return "击杀" end
    if key == "adjust" then return "分数调整" end
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
    local captain = ""
    if ADKP_Z_GetCaptainName then
        captain = ADKP_Z_GetCaptainName()
    end

    -- 没有配置替补队长：直接执行（仅主团加分）
    if captain == "" or not ADKP_SearchSubMembers_Event then
        if callback then callback() end
        return
    end

    if ADKP_AwardDKP_FrameSubLeader then
        ADKP_AwardDKP_FrameSubLeader:SetText(captain)
    end
    if not ADKP_SubAwardData then
        ADKP_SubAwardData = {}
    end
    ADKP_SubAwardData.captain = captain
    ADKP_SubAwardData.receivedResponse = false

    -- 强制查询：保持 ForceQuery=true 直到收到真实响应或超时
    -- 防止 waitFrame 期间其他路径调用 SearchSubMembers 时命中缓存
    ADKP_SubSync_ForceQuery = true
    ADKP_SearchSubMembers_Event()

    local waitFrame = CreateFrame("Frame")
    waitFrame.startTime = GetTime()
    waitFrame:SetScript("OnUpdate", function()
        local frame = this or waitFrame
        local elapsed = GetTime() - (frame.startTime or 0)
        local responded = ADKP_SubAwardData and ADKP_SubAwardData.receivedResponse
        if responded then
            frame:SetScript("OnUpdate", nil)
            ADKP_SubSync_ForceQuery = false
            if callback then callback() end
        elseif elapsed >= 2 then
            frame:SetScript("OnUpdate", nil)
            ADKP_SubSync_ForceQuery = false
            ADKP_Print("[ADKP] 警告：无法联系替补队长 [" .. captain .. "]，将使用本地缓存的替补数据执行。")
            if callback then callback() end
        end
    end)
end

local function ADKP_RunRaidAndSubAward(raidPoints, subPoints, reason)
    ADKP_QuickFloat_SearchSubsThenRun(function()
        ADKP_Z_ApplyAward(raidPoints, subPoints, reason)
    end)
end

local function ADKP_QuickFloat_IsSubMember(name)
    if not name or name == "" then
        return false
    end
    local lowerName = string.lower(name)
    if ADKP_SubData and ADKP_SubData.subs then
        for memberName, _ in pairs(ADKP_SubData.subs) do
            if memberName and string.lower(memberName) == lowerName then
                return true
            end
        end
    end
    if ADKP_SubAwardData and ADKP_SubAwardData.members then
        local members = ADKP_SubAwardData.members
        local n = table.getn(members)
        for i = 1, n do
            local info = members[i]
            if info and info.name and string.lower(info.name) == lowerName then
                return true
            end
        end
    end
    return false
end

local function ADKP_QuickFloat_ExecuteRaidSub(key, raidPoints, subPoints, reason)
    ADKP_QuickFloat_ShowConfirm(
        "确认执行【" .. ADKP_QuickFloat_GetActionLabel(key) .. "】吗？\n主队: " .. tostring(raidPoints) .. "\n替补: " .. tostring(subPoints) .. "\n原因: " .. reason,
        function()
            ADKP_RunRaidAndSubAward(raidPoints, subPoints, reason)
        end
    )
end

local function ADKP_QuickFloat_ExecuteAdjust(points, playerName, reason)
    -- 完全按 /adkpc 逻辑：对单个玩家执行（默认当前目标），原因可选
    local targetName = ADKP_TrimText(playerName or "")
    if targetName == "" then
        targetName = UnitName("target") or ""
        targetName = ADKP_TrimText(targetName)
    end
    if targetName == "" then
        ADKP_Print("错误：请先选中目标，或在右键设置中填写玩家。")
        return
    end

    if type(points) ~= "number" then
        ADKP_Print("错误：请先右键设置【调】的分数。")
        return
    end

    local finalReason = ADKP_TrimText(reason or "")
    if finalReason == "" then
        finalReason = "菜出天际-犯错"
    end

    local className = ADKP_GetPlayerClass(targetName) or "战士"
    if ADKP_NormalizeClassName then
        className = ADKP_NormalizeClassName(className)
    end
    local playerTable = {{ name = targetName, class = className }}

    ADKP_QuickFloat_ShowConfirm(
        "确认对目标执行【调】吗？\n目标: " .. targetName .. "\n分数: " .. tostring(points) .. "\n原因: " .. finalReason,
        function()
            ADKP_AddDKP(points, finalReason, "false", playerTable)
            ADKP_AnnounceAwardSingle(points, finalReason, targetName)
            ADKP_UpdateTable()
            ADKP_UpdateTableToShow()
            if ADKP_UpdateLootList then
                ADKP_UpdateLootList()
            end
        end
    )
end

local ADKP_QuickFloatFrame = nil
local ADKP_QuickFloatSettingsFrame = nil
local ADKP_QuickFloatHelpFrame = nil

local function ADKP_QuickFloat_UpdateTooltip(key)
    if not GameTooltip then
        return
    end
    local v1, v2, reason = ADKP_QuickFloat_GetSettings(key)
    local title = "快捷浮窗 - " .. ADKP_QuickFloat_GetActionLabel(key)
    GameTooltip:SetText(title, 1, 1, 1)
    if key == "adjust" then
        local points = v1
        local player = ADKP_TrimText(v2 or "")
        if type(points) == "number" then
            GameTooltip:AddLine("分数: " .. tostring(points), 0.8, 0.8, 0.8)
        else
            GameTooltip:AddLine("右键设置分数", 0.8, 0.8, 0.8)
        end
        if player ~= "" then
            GameTooltip:AddLine("玩家: " .. player, 0.8, 0.8, 0.8)
        end
        reason = ADKP_TrimText(reason or "")
        if reason ~= "" then
            GameTooltip:AddLine("原因: " .. reason, 0.8, 0.8, 0.8)
        end
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

local function ADKP_QuickFloat_OnAction(key, mouseButton)
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

    if key == "adjust" then
        local points = v1
        local player = v2
        if type(points) ~= "number" then
            ADKP_Print("错误：请先右键设置【调】的默认分数。")
            return
        end
        ADKP_QuickFloat_ExecuteAdjust(points, player or "", reason or "")
        return
    end
end

-- 全局封装：供主界面按钮 OnClick 调用（等价悬浮窗左键）
function ADKP_QuickFloatAction(key)
    ADKP_QuickFloat_OnAction(key, "LeftButton")
end

-- 全局封装：供主界面按钮 OnClick 处理左/右键（左键执行，右键设置分值）
function ADKP_QuickFloatAction_Mouse(key, button)
    ADKP_QuickFloat_OnAction(key, button or "LeftButton")
end

-- 全局封装：供主界面按钮 OnEnter 显示 tooltip
function ADKP_QuickFloat_ShowTooltip(key)
    ADKP_QuickFloat_UpdateTooltip(key)
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
        "调 ：调整选中玩家的分数：右键设置调整数值，正数加分、负数扣分；未填写调整原因时，默认备注为「犯错」。\n\n" ..
        "拍 ：打开拾取列表后点击，将本次所有拾取物品批量提交至竞拍队列，按顺序开展竞拍。"
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

    local keys = {"rally", "dismiss", "kill", "adjust"}
    -- 2×3 布局：上排 集/散/杀，下排 调/拍/?
    local positions = {
        { x = 10, y =  15 },  -- 集 (上排左)
        { x = 50, y =  15 },  -- 散 (上排中)
        { x = 90, y =  15 },  -- 杀 (上排右)
        { x = 10, y = -15 },  -- 调 (下排左)
    }
    f.buttons = {}
    for i = 1, 4 do
        local key = keys[i]
        local p = positions[i]
        local btn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        btn:SetWidth(36)
        btn:SetHeight(26)
        btn:SetPoint("LEFT", f, "LEFT", p.x, p.y)
        btn:SetText(ADKP_QuickFloat_GetActionLabel(key))
        btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        btn:SetScript("OnClick", function()
            ADKP_QuickFloat_OnAction(key, arg1)
        end)
        btn:SetScript("OnEnter", function()
            if GameTooltip then
                GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
                ADKP_QuickFloat_UpdateTooltip(key)
                GameTooltip:AddLine("左键:执行  右键:设置分值", 0.6, 0.6, 0.6)
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

    -- 「拍」按钮：打开掉落窗口时亮红，点击批量竞拍全部掉落装备
    local bidBtn = CreateFrame("Button", "ADKP_QuickFloatBidBtn", f, "UIPanelButtonTemplate")
    bidBtn:SetWidth(36)
    bidBtn:SetHeight(26)
    bidBtn:SetPoint("LEFT", f, "LEFT", 50, -15)
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
        end
    end)
    f.bidBtn = bidBtn

    -- 帮助按钮（下排右）
    local helpBtn = CreateFrame("Button", "ADKP_QuickFloatHelpBtn", f, "UIPanelButtonTemplate")
    helpBtn:SetWidth(36)
    helpBtn:SetHeight(26)
    helpBtn:SetPoint("LEFT", f, "LEFT", 90, -15)
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

    f:Hide()
    ADKP_QuickFloatFrame = f
    return f
end

function ADKP_QuickFloat_UpdateVisibility()
    ADKP_QuickFloat_InitOptions()
    local enabled = WebDKP_Options and WebDKP_Options["QuickFloatEnabled"]
    local inRaid = (GetNumRaidMembers and GetNumRaidMembers() or 0) > 0
    if enabled and inRaid then
        ADKP_QuickFloat_GetFrame():Show()
        -- 显示时根据当前拾取状态重设「拍」按钮颜色（避免初始/误触导致颜色错误）
        ADKP_UpdateQuickFloatBidBtn(GetNumLootItems and GetNumLootItems() > 0)
    else
        if ADKP_QuickFloatFrame then
            ADKP_QuickFloatFrame:Hide()
        end
    end
end

function ADKP_AwardSubPoints_Event()
	-- 奖惩DKP界面的替补加分按钮调用此函数
	-- 优先加载替补队队长输入框内容，确保输入框的值优先级最高
	-- 确保ADKP_SubAwardData存在
    if not ADKP_SubAwardData then
        ADKP_SubAwardData = {}
    end
    
	-- 从UI元素获取最新值
	-- 特别注意：替补队队长输入框的值优先级最高，无论何时都优先使用
    local captain = ""
    local reason = ""
    local points = 0
    
	-- 1. 首先获取替补队队长输入框的内容（最高优先级）
    if ADKP_AwardDKP_FrameSubLeader then
        captain = ADKP_AwardDKP_FrameSubLeader:GetText() or ""
        -- 直接将队长输入框的值设置到ADKP_SubAwardData，确保优先级
        ADKP_SubAwardData.captain = captain
    end
    
	-- 2. 获取其他输入框的值
    if ADKP_AwardDKP_FrameSubReason then
        reason = ADKP_AwardDKP_FrameSubReason:GetText() or ""
        ADKP_SubAwardData.reason = reason
    end
    if ADKP_AwardDKP_FrameSubPoints then
        local pointsText = ADKP_AwardDKP_FrameSubPoints:GetText() or ""
        points = tonumber(pointsText) or 0
        ADKP_SubAwardData.points = points
    end
    

    
	-- 然后调用ADKP_AwardSubPoints处理加分
    ADKP_AwardSubPoints()
end

-- 击杀弹窗的替补加分按钮调用此函数


-- 搜索替补队员事件处理函数
function ADKP_SearchSubMembers_Event()
    local captain = ""
    if ADKP_Options_FrameSubLeader then
        captain = ADKP_Options_FrameSubLeader:GetText() or ""
    elseif ADKP_SubAwardData then
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
    
	-- 清空之前的替补队员数据
    ADKP_PendingSubMembers[captain] = {}
    
	-- 确保ADKP_SubAwardData存在
    if not ADKP_SubAwardData then
        ADKP_SubAwardData = {}
    end
    
	-- 设置当前替补队长
    ADKP_SubAwardData.captain = captain
    
	-- 重置响应标志
    ADKP_SubAwardData.receivedResponse = false
    
	-- 发送查询消息给替补队长
	-- 使用SendAddonMessage发送查询消息，前缀为"AMB_TBQQ"
    local success, errorMsg = pcall(SendAddonMessage, "AMB_TBQQ", captain, "GUILD")
    if not success then
        ADKP_Print("发送查询消息失败: " .. (errorMsg or "未知错误"))
    end
end

function ADKP_AwardSubPoints()
	-- 确保ADKP_SubAwardData对象存在并包含必要字段
    if not ADKP_SubAwardData then
        ADKP_SubAwardData = {
            captain = "",
            reason = "",
            points = 0,
            bossName = "",
            receivedResponse = false
        }
    end
    
	-- 确保所有必要字段都有默认值
    ADKP_SubAwardData.captain = ADKP_SubAwardData.captain or ""
    ADKP_SubAwardData.reason = ADKP_SubAwardData.reason or ""
    ADKP_SubAwardData.bossName = ADKP_SubAwardData.bossName or ""
	-- 安全地获取分数值，避免访问不存在的框架
    local pointsText = ""
    if ADKP_SubAwardFrame and ADKP_SubAwardFrame.pointsEditBox then
        pointsText = ADKP_SubAwardFrame.pointsEditBox:GetText() or ""
    elseif ADKP_AwardDKP_FrameSubPoints then
        pointsText = ADKP_AwardDKP_FrameSubPoints:GetText() or ""
    end
    ADKP_SubAwardData.points = tonumber(pointsText) or ADKP_SubAwardData.points or 0
    ADKP_SubAwardData.receivedResponse = ADKP_SubAwardData.receivedResponse or false
    
	-- 从UI元素获取数据，特别是替补队队长输入框的内容
    local captain = ""
    local reason = ""
    local points = 0
    
	-- 1. 优先获取替补队队长输入框的内容（最高优先级）
    if ADKP_AwardDKP_FrameSubLeader then
        captain = WebDKP_Options["SubSettings"].captain or ADKP_AwardDKP_FrameSubLeader:GetText() or ""
        -- 确保队长输入框的值直接设置到ADKP_SubAwardData
        ADKP_SubAwardData.captain = captain
    end
    
	-- 2. 获取其他输入框的值
    if ADKP_AwardDKP_FrameSubReason then
        reason = ADKP_AwardDKP_FrameSubReason:GetText() or ""
    end
    if ADKP_AwardDKP_FrameSubPoints then
        local pointsText = ADKP_AwardDKP_FrameSubPoints:GetText() or ""
        points = tonumber(pointsText) or 0
    end
    
	-- 3. 如果队长输入框为空，才回退到ADKP_SubAwardData中的值
	-- 强调：队长输入框的值优先级最高，只要不为空就使用它
    if captain == "" and ADKP_SubAwardData then
        captain = ADKP_SubAwardData.captain or ""
    end
	-- 对于原因和分数，可以回退到ADKP_SubAwardData中的值
    if reason == "" then
        reason = ADKP_SubAwardData.reason or ""
    end
    if points == 0 then
        -- 安全地获取分数值，避免访问不存在的框架
        if ADKP_SubAwardFrame and ADKP_SubAwardFrame.pointsEditBox then
            points = tonumber(ADKP_SubAwardFrame.pointsEditBox:GetText()) or ADKP_SubAwardData.points or 0
        elseif ADKP_AwardDKP_FrameSubPoints then
            points = tonumber(ADKP_AwardDKP_FrameSubPoints:GetText()) or ADKP_AwardDKP_FrameSubPoints or 0
        else
            points = ADKP_SubAwardData.points or 0
        end
    end
    
	-- 3. 更新ADKP_SubAwardData，保持数据同步
    ADKP_SubAwardData.captain = captain
    ADKP_SubAwardData.reason = reason
    ADKP_SubAwardData.points = points
    
    if captain == "" then
        ADKP_Print("请输入替补队队长名称")
        return
    else
        ADKP_SubAwardData.captain = captain
    end
    
	-- 自动为空白原因设置默认值
    if reason == "" then
        -- 优先使用ADKP_BossAwardData中的bossName
        if ADKP_BossAwardData and ADKP_BossAwardData.bossName and ADKP_BossAwardData.bossName ~= "" then
            reason = ADKP_BossAwardData.bossName .. "-替补"
            ADKP_SubAwardData.bossName = ADKP_BossAwardData.bossName
        -- 其次使用ADKP_SubAwardData中的bossName
        elseif ADKP_SubAwardData.bossName and ADKP_SubAwardData.bossName ~= "" then
            reason = ADKP_SubAwardData.bossName .. "-替补"
        else
            reason = "替补"
        end
        ADKP_SubAwardData.reason = reason
    else
        -- 如果原因不为空，检查是否需要更新为boss名字-替补格式
        local needsUpdate = false
        local newReason = reason
        
        -- 检查当前原因是否已经是boss名字-替补格式
        if not string.find(reason, "-替补$") then
            -- 优先使用ADKP_BossAwardData中的bossName
            if ADKP_BossAwardData and ADKP_BossAwardData.bossName and ADKP_BossAwardData.bossName ~= "" then
                newReason = ADKP_BossAwardData.bossName .. "-替补"
                ADKP_SubAwardData.bossName = ADKP_BossAwardData.bossName
                needsUpdate = true
            -- 其次使用ADKP_SubAwardData中的bossName
            elseif ADKP_SubAwardData.bossName and ADKP_SubAwardData.bossName ~= "" then
                newReason = ADKP_SubAwardData.bossName .. "-替补"
                needsUpdate = true
            end
        end
        
        if needsUpdate then
            reason = newReason
            ADKP_SubAwardData.reason = reason
        end
    end
    
	-- 确保points是数字类型并检查有效性
    local pointsNum = tonumber(points) or 0
    if pointsNum < 0 then
        ADKP_Print("请输入有效的分数")
        return
    end
	-- 更新为有效的数字值
    points = pointsNum
    ADKP_SubAwardData.points = pointsNum
    
	-- 确保ADKP_PendingSubMembers已初始化
    if not ADKP_PendingSubMembers then
        ADKP_PendingSubMembers = {}
    end
    
	-- 检查是否有替补队员信息，不区分大小写查找
    local targetCaptainKey = nil
    local lowerCaptain = string.lower(captain)
    
	-- 1. 直接匹配原始队长名
    if ADKP_PendingSubMembers[captain] then
        targetCaptainKey = captain
    end
    
	-- 2. 如果直接匹配失败，尝试小写匹配
    if not targetCaptainKey and ADKP_PendingSubMembers[lowerCaptain] then
        targetCaptainKey = lowerCaptain
    end
    
	-- 3. 如果前两种都失败，遍历所有键进行不区分大小写匹配
    if not targetCaptainKey then
        for key, _ in pairs(ADKP_PendingSubMembers) do
            if string.lower(key) == lowerCaptain then
                targetCaptainKey = key
                break
            end
        end
    end
    
    if targetCaptainKey then
        local registeredPlayers = {}
        local registeredCount = 0
        local subNames = ""
        
        -- 处理所有替补队员
		for memberName, entry in pairs(ADKP_PendingSubMembers[targetCaptainKey]) do
			local entryClass = nil
			if type(entry) == "table" then
				entryClass = entry.class
			end
 
			if entryClass and ADKP_NormalizeClassName then
				entryClass = ADKP_NormalizeClassName(entryClass)
			end
 
			local playerClass = entryClass or ADKP_GetPlayerClass(memberName) or "战士"
 
            if subNames == "" then
                subNames = memberName
            else
                subNames = subNames .. ", " .. memberName
            end
 
            registeredCount = registeredCount + 1
            registeredPlayers[registeredCount] = {
                name = memberName,
                class = playerClass
            }
		end
 
		local subReason = reason
        
        -- 给替补队员加分
        if registeredCount > 0 then
            ADKP_AddDKP(points, subReason, "false", registeredPlayers, ADKP_BossAwardData.tableid)
            ADKP_Print("已成功为 " .. registeredCount .. " 名替补队员加 " .. points .. " 分 (" .. subReason .. ")")
        end
        
        if registeredCount > 0 then
            ADKP_Print("总计处理替补队员: " .. registeredCount .. " 名")
 
            local announceCaptain = targetCaptainKey or captain or ""
            if announceCaptain == "" and ADKP_SubAwardData then
                announceCaptain = ADKP_SubAwardData.captain or ""
            end
 
            local message = "替补加分完成: " .. subNames .. " (+" .. points .. " DKP)"
            if subReason and subReason ~= "" then
                message = message .. ", 原因: " .. subReason
            end
            message = message .. ")"
            if announceCaptain ~= "" then
                message = "替补队长" .. announceCaptain .. " 提示: " .. message
            end
 
            local tellLocation = ADKP_GetTellLocation()
            if ADKP_SendAnnouncement then
                ADKP_SendAnnouncement(message, tellLocation)
            elseif SendChatMessage then
                local isSilentMode = WebDKP_Options and WebDKP_Options["SilentMode"]
                if isSilentMode then
                    ADKP_Print("[静默] " .. message)
                elseif tellLocation == "RAID" then
                    SendChatMessage(message, "RAID")
                elseif tellLocation == "PARTY" then
                    SendChatMessage(message, "PARTY")
                end
            end
            
            -- 关闭窗口
            ADKP_SubAwardData.active = false
            if ADKP_SubAwardData.frame then
                ADKP_SubAwardData.frame:Hide()
            end
        end
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

-- 使用打卡模式的替补加分事件处理


-- 替补加分系统测试函数
function ADKP_TestSubAwardSystem()
	-- 1. 检查关键对象是否存在
    ADKP_Print("开始替补加分系统测试")
	-- 1. 检查关键对象是否存在
    ADKP_Print("开始替补加分系统测试")
    
	-- 确保ADKP_SubAwardData已初始化
    if not ADKP_SubAwardData then
        ADKP_SubAwardData = {
            captain = "",
            reason = "",
            points = 0,
            bossName = "",
            receivedResponse = false
        }
    end
    
	-- 确保ADKP_PendingSubMembers已初始化
    if not ADKP_PendingSubMembers then
        ADKP_PendingSubMembers = {}
    end
    
	-- 2. 检查UI元素是否存在
    ADKP_Print("检查UI元素状态")
    
	-- 3. 测试通信功能
    ADKP_Print("通信功能测试")
    
	-- 测试SendAddonMessage函数是否可用
    local canSendAddonMessage = pcall(SendAddonMessage, "AMB_TBQQ", "TEST", "GUILD")
    
	-- 4. 测试事件注册
    ADKP_Print("事件注册检查")
    
	-- 5. 提供使用说明
    ADKP_Print("测试完成")
    ADKP_Print("使用说明: 1.设置替补队长名称和加分信息 2.点击搜索替补队员按钮发起通信 3.等待替补队长响应后点击替补加分")
    
	-- 自动调用搜索替补队员函数进行测试
    if ADKP_SearchSubMembers then
        ADKP_SearchSubMembers()
    end
end

-- ================================
-- BOSS奖励事件处理
-- ================================
function ADKP_BossAward_Event()
    local frame = ADKP_BossAwardData.frame
    if not frame then
        return
    end
    
    local points = ADKP_BossAwardData.points
    local bossName = ADKP_BossAwardData.bossName
    local reason = "击杀-" .. (bossName or "未知BOSS")
    
	-- 更新团队玩家信息
    ADKP_UpdatePlayersInGroup()
    
	-- 获取当前团队中的所有玩家
    local players = {}
    if GetNumRaidMembers() > 0 then
        -- 在团队中
        for i = 1, GetNumRaidMembers() do
            local name = UnitName("raid" .. i)
            if name then
                table.insert(players, {name = name, unitId = "raid"..i})
            end
        end
    elseif GetNumPartyMembers() > 0 then
        -- 在队伍中
        for i = 1, GetNumPartyMembers() do
            local name = UnitName("party" .. i)
            if name then
                table.insert(players, {name = name, unitId = "party"..i})
            end
        end
        -- 包括自己
        table.insert(players, {name = UnitName("player"), unitId = "player"})
    else
        -- 单人
        table.insert(players, {name = UnitName("player"), unitId = "player"})
    end
    
	-- 获取当前玩家所在地图信息
    local currentZone = GetRealZoneText()
    local isInInstance, instanceType = IsInInstance()
    
	-- 创建玩家信息表，只包含符合条件的玩家
    local playerTable = {}
    local skippedPlayers = {}
    local playerIndex = 1
    
    for _, player in ipairs(players) do
        local playerName = player.name
        local unitId = player.unitId
        
        -- 验证玩家状态 - 使用WoW 1.12兼容的API
        local isConnected = UnitIsConnected(unitId)
        local isDead = UnitIsDeadOrGhost(unitId) -- 使用UnitIsDeadOrGhost代替UnitIsDead以检测灵魂状态
        local canAward = false
        local skipReason = ""
        
        -- 地图区域验证已移除：总是为所有玩家加分
        if true then -- 永真，else 地图验证分支永不执行（保留结构以维持 end 配对）
            canAward = true
        else
            -- 判断是否符合加分条件（启用地图验证时）
            if isConnected then
                if isInInstance then
                    canAward = true
                else
                    -- 不在副本中时，检查目标所在地图是否与玩家相同
                    if unitId == "player" then
                        canAward = true
                    else
                        -- 在WoW 1.12中，我们需要通过鼠标提示来获取其他玩家的地图信息
                        -- 首先检查UnitPosition是否有效（可以作为同一地图的快速判断）
                        local x2, y2 = UnitPosition(unitId)
                        
                        if x2 and y2 then
                            -- 如果UnitPosition返回有效值，说明目标在同一地图或附近
                            canAward = true
                        else
                            -- 尝试从鼠标提示中提取地图信息
                            -- 在WoW 1.12中，程序化获取其他玩家地图信息很困难
                            
                            -- 获取当前玩家的地图名称
                            local playerZone = GetZoneText()
                            
                            -- 使用GameTooltip获取详细信息
                            GameTooltip:ClearLines()
                            GameTooltip:SetOwner(WorldFrame, "ANCHOR_CURSOR")
                            GameTooltip:SetUnit(unitId)
                            GameTooltip:Show()
                            
                            -- 在WoW 1.12中，GameTooltip没有GetUnit()或UpdateTooltip()方法
                            -- 提示内容应该已经在SetUnit和Show后填充
                            
                            -- 记录所有可能的提示行用于调试
                            local allTooltipLines = ""
                            local tooltipText = nil
                            for i = 1, GameTooltip:NumLines() do
                                local textLine = getglobal("GameTooltipTextLeft"..i)
                                if textLine then
                                    local text = textLine:GetText()
                                    if text then
                                        allTooltipLines = allTooltipLines .. "Line "..i..": "..text.."\n"
                                        if i >= 2 and (string.find(text, playerZone) or string.find(text, "|c")) then
                                            tooltipText = text
                                        end
                                    end
                                end
                            end
                            
                            GameTooltip:Hide()
                            
                            -- 如果无法获取地图信息，使用默认规则
                            if tooltipText and string.find(tooltipText, playerZone) then
                                canAward = true
                            else
                                -- 无法确定是否在同一地图，默认不予加分
                                skipReason = "没在副本"
                            end
                        end
                    end
                end
            elseif isDead then
                -- 死亡/灵魂状态的玩家也视为符合条件（可能在跑尸）
                canAward = true
            else
                -- 既不在线也不是死亡/灵魂状态的玩家不予加分
                skipReason = "没有在线"
            end
        end
        
        if canAward then
            -- 从ADKP_DkpTable中获取玩家职业信息
            local playerClass = "未知"
            if WebDKP_DkpTable[playerName] and WebDKP_DkpTable[playerName]["class"] then
                playerClass = WebDKP_DkpTable[playerName]["class"]
            end
            
            playerTable[playerIndex] = {
                ["name"] = playerName,
                ["class"] = playerClass
            }
            playerIndex = playerIndex + 1
            
            -- 设置玩家为选择状态
            if WebDKP_DkpTable[playerName] then
                WebDKP_DkpTable[playerName]["Selected"] = true
            else
                -- 如果玩家不在DKP表中，先创建记录
                WebDKP_DkpTable[playerName] = {
                    ["dkp_"..ADKP_BossAwardData.tableid] = 0,
                    ["class"] = playerClass,
                    ["Selected"] = true
                }
            end
        else
            -- 记录未加分的玩家及其原因
            table.insert(skippedPlayers, {name = playerName, reason = skipReason})
        end
    end
    
	-- 保存当前选择的DKP列表
    local originalTableid = ADKP_Frame.selectedTableid
    
	-- 临时设置为BOSS奖励选择的DKP列表
    ADKP_Frame.selectedTableid = ADKP_BossAwardData.tableid
    
	-- ADKP_AddDKP函数内部会处理表格的检查和创建，此处无需重复处理
    
	-- 为符合条件的玩家加分
    local awardSuccess = false
    if next(playerTable) then
        awardSuccess = ADKP_AddDKP(points, reason, "false", playerTable, ADKP_BossAwardData.tableid)
        
        -- 恢复播报加分情况，确保boss击杀时有同步信息发送
        ADKP_AnnounceAward(points, "击杀-" .. (ADKP_BossAwardData.bossName or "未知BOSS"))
    else
        ADKP_Print("没有玩家符合加分条件，加分操作已取消。")
    end
    
	-- 只有当加分成功时才播报信息
    if awardSuccess then
        -- 获取播报位置
        local tellLocation = ADKP_GetTellLocation()
        
        -- 播报奖励信息
        local awardedCount = 0
        for _, selected in pairs(playerTable) do
            if selected then
                awardedCount = awardedCount + 1
            end
        end
        
        if awardedCount > 0 then
            local rewardMessage = points .. "点dkp奖励给" .. awardedCount .. "名团员,原因: " .. reason
            ADKP_SendAnnouncement(rewardMessage, tellLocation)
        end
        
        -- 播报未加分的玩家名单及原因
        if next(skippedPlayers) then
            local announceText = "未获得加分的玩家："
            for _, player in ipairs(skippedPlayers) do
                announceText = announceText .. player.name .. "(" .. player.reason .. ")、"
            end
            -- 移除最后一个顿号
            announceText = string.sub(announceText, 1, -4)
            
            -- 播报信息
            ADKP_SendAnnouncement(announceText, tellLocation)
        end
    end
    
	-- 恢复原来的DKP列表选择
    ADKP_Frame.selectedTableid = originalTableid
    
	-- 刷新主界面的显示，确保分数正确更新
    ADKP_UpdateTableToShow()
    ADKP_UpdateTable()
    
	-- 清除所有玩家的选择状态，避免影响后续操作
    for k, v in pairs(WebDKP_DkpTable) do
        if type(v) == "table" then
            v["Selected"] = false
        end
    end
    
	-- 备份数据
    ADKP_BackupData()
    
	-- 隐藏窗口
    frame:Hide()
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

-- 全局变量：存储当前的替补活动信息
ADKP_SubData = ADKP_SubData or {}
-- 确保subs子表已初始化
ADKP_SubData.subs = ADKP_SubData.subs or {}
-- 全局变量：存储当天的替补记录
WebDKP_DailySubRecords = WebDKP_DailySubRecords or {}
-- 全局变量：存储当前活动的团队成员列表
ADKP_CurrentRaidMembers = {}

-- ================================
-- BOSS奖励+替补事件处理
-- ================================
function ADKP_BossAwardWithSub_Event()
    local frame = ADKP_BossAwardData.frame
    if not frame then
        return
    end
    
	-- 确保ADKP_SubData已初始化
    ADKP_SubData = {
        active = true,
        points = ADKP_BossAwardData.points,
        bossName = ADKP_BossAwardData.bossName,
        reason = "击杀-" .. (ADKP_BossAwardData.bossName or "未知BOSS"),
        subReason = "击杀-" .. (ADKP_BossAwardData.bossName or "未知BOSS") .. " 替补分",
        tableid = ADKP_BossAwardData.tableid,
        startTime = GetTime(),
        endTime = 0,
        subs = {},
        raidMembers = {},
        timerFrame = nil
    }
    
	-- 同时更新ADKP_SubAwardData，确保bossName字段同步
    ADKP_SubAwardData.bossName = ADKP_BossAwardData.bossName
    ADKP_SubAwardData.reason = (ADKP_BossAwardData.bossName or "未知BOSS") .. "-替补"
    ADKP_SubAwardData.points = ADKP_BossAwardData.points
    
	-- 从UI输入框获取替补队长名称
    local captainName = ""
    if frame and frame.subCaptainEditBox then
        captainName = frame.subCaptainEditBox:GetText() or ""
    end
    
	-- 如果UI中没有输入，尝试从已保存的设置中获取
    if captainName == "" then
        if WebDKP_Options and WebDKP_Options["SubSettings"] and WebDKP_Options["SubSettings"]["captain"] then
            captainName = WebDKP_Options["SubSettings"]["captain"]
        elseif ADKP_SubAwardData.captain and ADKP_SubAwardData.captain ~= "" then
            captainName = ADKP_SubAwardData.captain
        end
    end
    
	-- 如果仍然为空，使用默认值
    if captainName == "" then
        captainName = "系统"
    end
    
	-- 更新ADKP_SubAwardData和UI中的值
    ADKP_SubAwardData.captain = captainName
    if frame and frame.subCaptainEditBox then
        frame.subCaptainEditBox:SetText(captainName)
    end
    
    ADKP_SubAwardData.receivedResponse = true
    
	-- 确保ADKP_BossAwardData有正确的数据
    if not ADKP_BossAwardData.points or ADKP_BossAwardData.points == "" then
        ADKP_BossAwardData.points = ADKP_SubData.points
    end
    
	-- 调用全员加分函数
    ADKP_AwardAllDKP_Event()
    
    ADKP_Print("全员加分执行完成")
    DEFAULT_CHAT_FRAME:AddMessage("[ADKP] 全员加分执行完成", 0, 1, 0)
    
	-- 确保ADKP_SubData.points有正确的值
    if not ADKP_SubData.points or ADKP_SubData.points <= 0 then
        ADKP_SubData.points = ADKP_BossAwardData.points
    end
    
	-- 获取替补计时分钟数
    local subTimeMinutes = tonumber(frame.subTimeEditBox:GetText()) or 5
    ADKP_SubData.endTime = ADKP_SubData.startTime + (subTimeMinutes * 60)
    
	-- 保存当前团队成员列表到ADKP_CurrentRaidMembers
    ADKP_CurrentRaidMembers = {}
    if GetNumRaidMembers() > 0 then
        for i = 1, GetNumRaidMembers() do
            local name = UnitName("raid" .. i)
            if name then
                ADKP_CurrentRaidMembers[name] = true
            end
        end
    elseif GetNumPartyMembers() > 0 then
        for i = 1, GetNumPartyMembers() do
            local name = UnitName("party" .. i)
            if name then
                ADKP_CurrentRaidMembers[name] = true
            end
        end
        local playerName = UnitName("player")
        ADKP_CurrentRaidMembers[playerName] = true
    else
        local playerName = UnitName("player")
        ADKP_CurrentRaidMembers[playerName] = true
    end
    
    ADKP_SubData.raidMembers = ADKP_CurrentRaidMembers
    
    local subMessage = "手动替补加分活动开始！替补成员在" .. subTimeMinutes .. "分钟内私聊我 'TB' 报数进行记录，过期不候！"
    local isSilentMode = WebDKP_Options and WebDKP_Options["SilentMode"]
    if isSilentMode then
        ADKP_Print("[静默] " .. subMessage)
    else
        SendChatMessage(subMessage, "GUILD", nil, nil)
    end
    
	-- 设置计时器，计时结束后处理替补加分
    ADKP_SubData.timerFrame = CreateFrame("Frame")
    ADKP_SubData.timerFrame:SetScript("OnUpdate", function()
        if GetTime() >= ADKP_SubData.endTime then
            local frame =  ADKP_SubData.timerFrame
            frame:SetScript("OnUpdate", nil)
            ADKP_ProcessSubstitutes()
        end
    end)
    
	-- 隐藏窗口
    frame:Hide()
    
	-- 显示倒计时信息
    ADKP_Print("替补加分活动已开始，将在" .. subTimeMinutes .. "分钟后结束。")
end

-- ================================
-- 处理替补加分
-- ================================
function ADKP_ProcessSubstitutes()
    if not ADKP_SubData or not ADKP_SubData.active then
        return
    end
    
	-- 优先使用ADKP_SubAwardData.points（用户输入的分数），如果没有则使用ADKP_SubData.points
    local points = ADKP_SubData.points
    if ADKP_SubAwardData and ADKP_SubAwardData.points then
        points = ADKP_SubAwardData.points
    end
    local reason = ADKP_SubData.subReason
    local tableid = ADKP_SubData.tableid
    local bossName = ADKP_SubData.bossName
    
	-- 创建替补玩家信息表
    local subPlayerTable = {}
    local subIndex = 1
    local subNames = ""
    local subDetails = {}
    
    if next(ADKP_SubData.subs) then
        -- 保存当前选择 of DKP list
        local originalTableid = ADKP_Frame.selectedTableid
        
        -- 临时设置为BOSS奖励选择 of DKP list
        ADKP_Frame.selectedTableid = tableid
        
        for name, playerInfo in pairs(ADKP_SubData.subs) do
            -- 检查玩家是否在团队/队伍中，如果在则跳过（使用小写名称进行比较）
            if ADKP_SubData and ADKP_SubData.raidMembers and ADKP_SubData.raidMembers[string.lower(name)] then
                ADKP_Print(name .. " 已经在团队中，跳过替补加分")
                -- 从ADKP_SubData.subs中移除该玩家
                ADKP_SubData.subs[name] = nil
            else
                local class = playerInfo.class or "Unknown"
                local location = playerInfo.location or "未知"
                
                local playerReason = reason
                
                -- 记录到玩家信息表
                subPlayerTable[subIndex] = {
                    ["name"] = name,
                    ["class"] = class
                }
                
                local playerPoints = points
                
                -- 确保所有在ADKP_SubData.subs中的玩家都能获得加分
                ADKP_AddDKP(playerPoints, playerReason, "false", {{name = name, class = class}})
                
                -- 为替补记录添加uniqueId字段
                local currentTime = date("%H:%M:%S")
                local uniqueId = "sub_" .. subIndex .. "_" .. name .. "_" .. currentTime
                
                -- 查找并更新刚添加的替补记录 of uniqueId
                if WebDKP_Log then
                    for logKey, logEntry in pairs(WebDKP_Log) do
                        if type(logEntry) == "table" and logEntry.reason == playerReason and logEntry.points == points and logEntry.awarded and logEntry.awarded[name] and not logEntry.uniqueId then
                            logEntry.uniqueId = uniqueId
                            logEntry.item = playerReason
                            ADKP_Print("为替补记录添加uniqueId: " .. uniqueId)
                            break
                        end
                    end
                end
                
                -- 记录替补信息
                subDetails[subIndex] = {
                    name = name,
                    class = class,
                    location = location
                }
                
                subIndex = subIndex + 1
                if subNames == "" then
                    subNames = name
                else
                    subNames = subNames .. ", " .. name
                end
                
                -- 保存替补记录
                local today = date("%Y-%m-%d")
                if not WebDKP_DailySubRecords[today] then
                    WebDKP_DailySubRecords[today] = {}
                end
                
                table.insert(WebDKP_DailySubRecords[today], {
                    name = name,
                    class = class,
                    location = location,
                    time = date("%Y-%m-%d %H:%M:%S"),
                    reason = playerReason,
                    points = playerPoints,
                    bossName = bossName,
                    uniqueId = uniqueId
                })
            end
        end
        
        -- 恢复原来的DKP列表选择
        ADKP_Frame.selectedTableid = originalTableid
        
        -- 播报替补加分信息
        if subNames ~= "" then
            local message = "替补加分完成: " .. subNames .. " (+" .. points .. " DKP)"

            local captainName = ""
            if ADKP_SubAwardData then
                captainName = ADKP_SubAwardData.captain or ""
                if captainName ~= "" and tonumber(captainName) then
                    captainName = ""
                end
            end
            if captainName ~= "" then
                message = "替补队长" .. captainName .. " 提示: " .. message
            end
            
            DEFAULT_CHAT_FRAME:AddMessage("[ADKP] " .. message, 0, 1, 0)
            
            local tellLocation = ADKP_GetTellLocation()
            
            if ADKP_SendAnnouncement then
                ADKP_SendAnnouncement(message, tellLocation)
            elseif SendChatMessage then
                local isSilentMode = WebDKP_Options and WebDKP_Options["SilentMode"]
                if isSilentMode then
                    ADKP_Print("[静默] " .. message)
                elseif tellLocation == "RAID" then
                    SendChatMessage(message, "RAID")
                elseif tellLocation == "PARTY" then
                    SendChatMessage(message, "PARTY")
                end
            end
        end
    else
        DEFAULT_CHAT_FRAME:AddMessage("[ADKP] 没有替补玩家需要加分", 1, 0.7, 0)
    end
    
    ADKP_SubData.active = false
    ADKP_SubData.subs = {}
    
    if ADKP_SubAwardData then
        ADKP_SubAwardData = {}
    end
    
    if ADKP_PendingSubMembers then
        ADKP_PendingSubMembers = {}
    end
end

-- ================================
-- 处理私密消息中的TB命令
-- ================================
-- 全局变量用于跟踪最后一次查询时间
ADKP_LastWhoQueryTime = ADKP_LastWhoQueryTime or 0
ADKP_WhoQueryCooldown = 5 -- 5秒查询冷却

-- 根据名字获取公会成员信息
function ADKP_GetGuildMemberInfoByName(name)
    if not IsInGuild() then
        return nil, nil
    end
    
	-- 提取基础名字（移除服务器名部分）
    local baseName = string.match(name, "^([^%-]+)") or name
    baseName = string.lower(baseName)
    
	-- 使用GetNumGuildMembers(false)只统计在线成员
    local memberCount = GetNumGuildMembers(false)
    
	-- 遍历公会在线成员
    for i = 1, memberCount do
        local guildName, _, _, level, class, zone, _, _, online = GetGuildRosterInfo(i)
        
        if guildName then
            -- 提取公会成员的基础名字
            local baseGuildName = string.match(guildName, "^([^%-]+)") or guildName
            baseGuildName = string.lower(baseGuildName)
            
            -- 忽略大小写比较名字
            if baseGuildName == baseName then
                -- 返回职业和地点信息，即使是"未知"的也要返回
                return class or "未知", zone or "未知"
            end
        end
    end
    
	-- 如果在在线成员中没找到，再尝试遍历所有成员（包括离线）
    local allMemberCount = GetNumGuildMembers(true)
    for i = 1, allMemberCount do
        local guildName, _, _, level, class, zone, _, _, online = GetGuildRosterInfo(i)
        
        if guildName then
            local baseGuildName = match(guildName, "^([^%-]+)") or guildName
            baseGuildName = string.lower(baseGuildName)
            
            if baseGuildName == baseName then
                return class or "未知", zone or "未知"
            end
        end
    end
    
    return nil, nil
end

function ADKP_HandleWhisperTB(name, message)
    local lowerMsg = string.lower(message)
    local isTBCommand = lowerMsg == "tb"
    local points = nil
    
    if not isTBCommand then
        local cmd, pointsStr = string.match(lowerMsg, "^(tb)%s+(%d+)$")
        if cmd and pointsStr then
            isTBCommand = true
            points = tonumber(pointsStr)
        end
    end
    
	-- 检查是否有活跃的替补活动
    if not ADKP_SubData or not ADKP_SubData.active then
        return false
    end
    
    if isTBCommand then
        -- 检查玩家是否已在团队中（已获得全员加分）
        if ADKP_SubData.raidMembers and ADKP_SubData.raidMembers[name] then
            local isSilentMode = WebDKP_Options and WebDKP_Options["SilentMode"]
            if not isSilentMode then
                SendChatMessage("你已经在团队中，无需申请替补。", "WHISPER", nil, name)
            else
                ADKP_Print("[静默] " .. name .. " 已获得全员加分，无需申请替补")
            end
            return true
        end
        
        -- 检查玩家是否已经提交过申请
        if ADKP_SubData.subs[name] then
            local isSilentMode = WebDKP_Options and WebDKP_Options["SilentMode"]
            if not isSilentMode then
                SendChatMessage("你的申请已经收录，请勿重复提交。", "WHISPER", nil, name)
            else
                ADKP_Print("[静默] " .. name .. " 的申请已收录，请勿重复提交")
            end
            return true
        end
        
        -- 首先尝试从公会成员信息中获取玩家所在地
        local className, location = ADKP_GetGuildMemberInfoByName(name)
        
        if className then
            local finalClass = className or "战士"
            
            ADKP_SubData.subs[name] = {
                class = finalClass,
                location = location or "未知地点",
                locationNeedsConfirmation = true
            }
            
            -- 检查玩家是否在DKP列表中，如果不在则创建新记录
            if not WebDKP_DkpTable[name] then
                local tableid = ADKP_SubData.tableid or WebDKP_Options.SelectedTableId or 1
                WebDKP_DkpTable[name] = {
                    ["dkp_"..tableid] = 0,
                    ["class"] = finalClass
                }
            end
            
            -- 回复玩家
            local isSilentMode = WebDKP_Options and WebDKP_Options["SilentMode"]
            local responseMsg = "申请替补成功！你已记录为替补队员。"
            
            if not isSilentMode then
                SendChatMessage(responseMsg, "WHISPER", nil, name)
            else
                ADKP_Print("[静默] 替补队员 " .. name .. " 已打卡成功")
            end
            ADKP_Print("替补队员 " .. name .. " 已记录")
            return true
        end
    end
    return false
end

-- ================================
-- 扩展CHAT_MSG_WHISPER事件处理已整合到原始函数中
-- ================================

-- ================================
-- 尝试使用SendWho查询玩家信息
-- ================================
function ADKP_AttemptWhoQuery(name)
	-- 记录玩家是否已发送确认消息
    if not ADKP_SubData.whisperedPlayers then
        ADKP_SubData.whisperedPlayers = {}
    end
    
	-- 初始化玩家数据，先使用默认值
    local finalClass = "战士" -- 默认职业
    local location = nil -- 初始化所在地变量
    local playerName = name -- 提前定义playerName变量，确保在所有代码路径中都有定义
    
	-- 检查玩家是否在报名列表中
    local isRegistered = false
    if ADKP_SubData.registeredPlayers then
        for _, regName in ipairs(ADKP_SubData.registeredPlayers) do
            if string.lower(name) == string.lower(regName) then
                isRegistered = true
                break
            end
        end
    end
    
	-- 尝试从DKP表中获取职业信息
    if WebDKP_DkpTable and WebDKP_DkpTable[name] then
        finalClass = WebDKP_DkpTable[name]["class"] or "战士"
    else
        -- 尝试从公会花名册中获取职业和所在地信息
        local foundInGuild = false
        local numGuildMembers = GetNumGuildMembers(true)
        for i = 1, numGuildMembers do
            -- 获取公会成员信息，包括职业和在线状态
            local guildName, _, _, _, _, guildClass, _, online, zone = GetGuildRosterInfo(i)
            if guildName and string.lower(guildName) == string.lower(name) then
                finalClass = guildClass or "战士"
                -- 如果玩家在线，使用zone作为所在地信息
                if online and zone and string.len(zone) > 0 then
                    location = zone
                end
                foundInGuild = true
                break
            end
        end
    end
    
	-- 确保location值被正确设置
    local finalLocation = location
    if not finalLocation or type(finalLocation) ~= "string" or string.len(finalLocation) == 0 or string.find(finalLocation, "^%s*$" ) then
        finalLocation = "未知地点"
    end
    
	-- 先保存玩家数据，即使地点是未知的
    ADKP_SubData.subs[playerName] = {
        class = finalClass,
        location = finalLocation,
        isRegistered = isRegistered  -- 添加标记，记录是否已报名
    }
    
	-- 检查玩家是否在DKP列表中，如果不在则创建新记录
    if not WebDKP_DkpTable[playerName] then
        -- 获取当前使用的DKP列表ID
        local tableid = ADKP_SubData.tableid or WebDKP_Options.SelectedTableId or 1
        
        -- 创建新的DKP记录，初始分数为0
        WebDKP_DkpTable[playerName] = {
            ["dkp_"..tableid] = 0,
            ["class"] = finalClass
        }
    end
    
	-- 只发送一次确认消息
    if not ADKP_SubData.whisperedPlayers[name] then
        -- 静默模式下不发送私聊，仅本地记录
        local isSilentMode = WebDKP_Options and WebDKP_Options["SilentMode"]
        if not isSilentMode then
            SendChatMessage("已收录为本次替补。", "WHISPER", nil, name)
        else
            ADKP_Print("[静默] 已收录 " .. name .. " 为本次替补")
        end
        ADKP_SubData.whisperedPlayers[name] = true
    end
    
	-- 检查30秒冷却时间，如果可以查询且地点未知，则尝试获取位置信息
    local currentTime = GetTime()
    ADKP_LastWhoQueryTime = ADKP_LastWhoQueryTime or 0
    
    if (currentTime - ADKP_LastWhoQueryTime >= 30) and finalLocation == "未知地点" then
        -- 更新最后查询时间
        ADKP_LastWhoQueryTime = currentTime
        
        -- 使用SendWho获取玩家信息
        SendWho(name)
        
        -- 延迟一小段时间以确保GetWhoInfo能够获取到数据
        local whoFrame = CreateFrame("Frame")
        whoFrame.playerName = name
        whoFrame:SetScript("OnUpdate", function()
            local frame = this -- 使用this引用当前帧
            local elapsed = tonumber(arg1) or 0
            frame.timer = (frame.timer or 0) + elapsed
            if frame.timer > 1 then -- 1秒后尝试获取信息
                frame:SetScript("OnUpdate", nil)
                
                -- 使用GetWhoInfo(1)获取玩家信息
                local whoPlayerName, guildName, level, race, className, whoLocation = GetWhoInfo(1)
                
                -- 确保正确解析返回值
                if whoPlayerName and string.len(whoPlayerName) > 0 then
                    -- 提取基础名字
                    local baseName = string.match(whoPlayerName, "^([^%-]+)") or whoPlayerName
                    local baseOriginalName = string.match(frame.playerName, "^([^%-]+)") or frame.playerName
                    
                    -- 忽略大小写比较名字
                    if string.lower(baseName) == string.lower(baseOriginalName) then
                        -- 名字匹配，更新地点信息
                        if whoLocation and type(whoLocation) == "string" and string.len(whoLocation) > 0 and not string.find(whoLocation, "^%s*$") then
                            -- 更新替补数据中的地点信息，使用更精确的SendWho查询结果
                            if ADKP_SubData.subs[frame.playerName] then
                                ADKP_SubData.subs[frame.playerName].location = whoLocation
                                -- 标记位置信息已确认
                                ADKP_SubData.subs[frame.playerName].locationNeedsConfirmation = false
                            end
                        end
                    end
                end
            end
        end)
    elseif finalLocation == "未知地点" then
        -- 如果在冷却时间内且地点未知，设置10秒后再次尝试
        local retryFrame = CreateFrame("Frame")
        retryFrame.playerName = name
        retryFrame:SetScript("OnUpdate", function()
            local frame = this
            local elapsed = tonumber(arg1) or 0
            frame.timer = (frame.timer or 0) + elapsed
            if frame.timer > 10 then -- 10秒后重试
                frame:SetScript("OnUpdate", nil)
                -- 再次尝试获取位置信息
                ADKP_AttemptWhoQuery(frame.playerName)
            end
        end)
    end
            

end

-- 获取玩家当天最后一次替补活动的时间
function ADKP_GetPlayerLastSubActivityTime(playerName, todayDate)
    local lastActivityTime = nil   
    if WebDKP_Log and WebDKP_Log.Version then
        for key, entry in pairs(WebDKP_Log) do
            if type(entry) == "table" and entry.date and string.find(entry.date, todayDate) and 
               string.find(entry.reason or "", "替补分") and entry.awarded and entry.awarded[playerName] then
                -- 找到了当天该玩家的替补活动记录
                local entryTime = entry.date
                if not lastActivityTime or entryTime > lastActivityTime then
                    lastActivityTime = entryTime
                end
            end
        end
    end   
    return lastActivityTime
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
-- 处理自定义命令：/替补 和 /名单
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
	        ADKP_Print("/adkp tc - 切换BOSS死亡弹窗开关")
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
	
	-- 处理tc命令，切换BOSS死亡弹窗开关
	if cmd == "tc" then
		if not WebDKP_Options then
			WebDKP_Options = {}
		end
		
		-- 检查配置是否存在，如果不存在则初始化为开启状态
		if WebDKP_Options["BossDeathPopup"] == nil then
			WebDKP_Options["BossDeathPopup"] = true
			ADKP_Print("BOSS死亡弹窗已开启")
		else
			-- 切换状态
			WebDKP_Options["BossDeathPopup"] = not WebDKP_Options["BossDeathPopup"]
			
			if WebDKP_Options["BossDeathPopup"] then
				ADKP_Print("BOSS死亡弹窗已开启")
			else
				ADKP_Print("BOSS死亡弹窗已关闭")
			end
		end
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
            ["dkp" .. ADKP_GetTableid()] = initialDkp,
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
    
    if cmd == "tb" then
        -- 解析参数，分数必填
        if not arg1 or arg1 == "" then
            ADKP_Print("错误：/adkptb 命令需要分数参数！")
            ADKP_Print("正确格式：/adkptb [分数] [分钟]")
            ADKP_Print("示例：/adkptb 2 5  （2分，5分钟）")
            return
        end
        
        local points = tonumber(arg1)
        if not points then
            ADKP_Print("错误：分数必须是数字！")
            return
        end
        
        local minutes = tonumber(arg2) or 5
        
        -- 初始化替补活动数据
        -- 优先使用ADKP_SubAwardData中的reason，如果没有则使用默认值
        local subReasonValue = "替补分"
        if ADKP_SubAwardData and ADKP_SubAwardData.reason and ADKP_SubAwardData.reason ~= "" then
            subReasonValue = ADKP_SubAwardData.reason
        end
        
        ADKP_SubData = {
            active = true,
            points = points,
            reason = subReasonValue,
            subReason = subReasonValue,
            tableid = ADKP_GetTableid(),
            startTime = GetTime(),
            endTime = GetTime() + (minutes * 60),
            subs = {},
            raidMembers = {},
            timerFrame = nil
        }
        
        -- 保存当前团队成员列表
        ADKP_CurrentRaidMembers = {}
        if GetNumRaidMembers() > 0 then
            for i = 1, GetNumRaidMembers() do
                local name = UnitName("raid" .. i)
                if name then
                    ADKP_CurrentRaidMembers[name] = true
                end
            end
        elseif GetNumPartyMembers() > 0 then
            for i = 1, GetNumPartyMembers() do
                local name = UnitName("party" .. i)
                if name then
                    ADKP_CurrentRaidMembers[name] = true
                end
            end
            local playerName = UnitName("player")
            ADKP_CurrentRaidMembers[playerName] = true
        else
            local playerName = UnitName("player")
            ADKP_CurrentRaidMembers[playerName] = true
        end
        
        -- 保存团队成员列表到ADKP_SubData
        ADKP_SubData.raidMembers = ADKP_CurrentRaidMembers
        
        -- 播报替补打卡提醒
        -- 打卡模式下，使用正确的时间参数
        local timeInfo = minutes .. "分钟"
        -- 优先使用ADKP_SubAwardData中的minutes字段
        if ADKP_SubAwardData and ADKP_SubAwardData.minutes then
            timeInfo = ADKP_SubAwardData.minutes .. "分钟"
        end
        
        local subMessage = "手动替补加分活动开始！替补成员在" .. timeInfo .. "内私密我 TB 记录打卡，过期不候！"
        
        -- 静默模式下不发送团队播报，仅本地显示
        local isSilentMode = WebDKP_Options and WebDKP_Options["SilentMode"]
        if not isSilentMode then
            SendChatMessage(subMessage, "GUILD", nil, nil)
        else
            ADKP_Print("[静默] " .. subMessage)
        end
        ADKP_Print("手动替补加分活动已开始，将在" .. minutes .. "分钟后结束。")
        
        -- 设置计时器，计时结束后处理替补加分
        ADKP_SubData.timerFrame = CreateFrame("Frame")
        ADKP_SubData.timerFrame:SetScript("OnUpdate", function()
            if GetTime() >= ADKP_SubData.endTime then
                local frame =  ADKP_SubData.timerFrame -- 使用this或显式引用
                frame:SetScript("OnUpdate", nil)
                ADKP_ProcessSubstitutes()
            end
        end)
    
    elseif cmd == "md" then

        
        -- 直接使用ADKP_GetSubstituteRecords函数获取所有替补记录
        -- 这个函数是替补名单窗口用来获取数据的核心函数，确保即使没有打开窗口也能获取到正确的数据
        local allSubRecords = ADKP_GetSubstituteRecords()
        
        -- 准备名单信息
        local listEntries = {}
        local playerRecords = {}
        
        -- 处理所有替补记录，统计次数和最后活动时间
        if allSubRecords then
            for _, record in ipairs(allSubRecords) do
                if record.player then
                    -- 尝试多种方式获取时间字段
                    local timeField = record.time or record.date or record.timeStr or record.dateStr
                    local playerName = record.player
                    if not playerRecords[playerName] then
                        playerRecords[playerName] = {
                            count = 0,
                            lastTime = ""
                        }
                    end
                    
                    -- 更新次数
                    playerRecords[playerName].count = playerRecords[playerName].count + 1
                    
                    -- 更新最后活动时间
                    if timeField and timeField > playerRecords[playerName].lastTime then
                        playerRecords[playerName].lastTime = timeField
                    end
                end
            end

       
        
        -- 转换为listEntries格式，添加职业颜色
        for playerName, data in pairs(playerRecords) do
            -- 处理时间信息，支持多种格式
            local timeStr = "未知"
            if data.lastTime then
                -- 检查是否已经是HH:MM格式或包含时间信息
                if string.match(data.lastTime, "%d+:%d+") then
                    -- 提取HH:MM部分
                    local timeMatch = string.match(data.lastTime, "(%d+:%d+)")
                    if timeMatch then
                        timeStr = timeMatch
                    end
                end

            end
            
            -- 获取职业信息
            local class = "战士" -- 默认职业
            if WebDKP_DkpTable and WebDKP_DkpTable[playerName] and WebDKP_DkpTable[playerName].class then
                class = WebDKP_DkpTable[playerName].class
            end
            
            -- 获取职业颜色并格式化玩家名称
            local classColor = ADKP_GetClassColor(class)
            local coloredName = classColor .. playerName .. "|r"
            
            -- 添加到列表中
            table.insert(listEntries, coloredName .. " " .. data.count .. "次 最后：" .. timeStr)
        end
        
        -- 分批次发送名单，每批2个玩家，避免信息过长
        local listEntriesSize = ADKP_GetTableSize(listEntries)
        
        -- 显示玩家记录数量
        ADKP_Print("替补名单：共有 " .. listEntriesSize .. " 个玩家记录")
        
        if listEntriesSize == 0 then
            ADKP_Print("暂无替补记录。")
            return
        end
        
        -- 静默模式下不发送团队播报，仅本地显示
        local isSilentMode = WebDKP_Options and WebDKP_Options["SilentMode"]
        if isSilentMode then
            ADKP_Print("[静默] 替补名单已生成，共 " .. listEntriesSize .. " 个玩家记录")
            -- 本地显示前几个玩家作为调试信息
            local maxDisplay = 3
            local displayed = 0
            for i = 1, math.min(listEntriesSize, maxDisplay) do
                ADKP_Print("[静默] " .. listEntries[i])
                displayed = displayed + 1
            end
            if listEntriesSize > maxDisplay then
                ADKP_Print("[静默] ... 还有 " .. (listEntriesSize - maxDisplay) .. " 个玩家")
            end
            return
        end
        
        -- 获取发送位置
        local tellLocation = ADKP_GetTellLocation()
        if tellLocation == "NONE" then
            tellLocation = "SAY"
        end
        
        -- 分批发送，每批2个玩家
        local batchSize = 2
        local currentIndex = 1
        local batchNumber = 1
        
        -- 创建分批发送函数
        local function sendBatch()
            -- ADKP_Print("调试：发送第 " .. batchNumber .. " 批，当前索引 " .. currentIndex .. "，总数 " .. listEntriesSize)
            
            if currentIndex > listEntriesSize then
                -- ADKP_Print("调试：所有批次发送完毕")
                return  -- 所有批次发送完毕
            end
            
            local batchMessage = ""
            
            -- 构建当前批次的消息
            if batchNumber == 1 then
                batchMessage = "替补名单："
            else
                batchMessage = "替补名单继续："
            end
            
            local count = 0
            local startIndex = currentIndex
            
            -- 确保至少发送1个玩家，即使不足batchSize
            if currentIndex <= listEntriesSize then
                batchMessage = batchMessage .. listEntries[currentIndex]
                currentIndex = currentIndex + 1
                count = count + 1
                
                -- 继续添加更多玩家直到达到batchSize
                while currentIndex <= listEntriesSize and count < batchSize do
                    batchMessage = batchMessage .. "    " .. listEntries[currentIndex]
                    currentIndex = currentIndex + 1
                    count = count + 1
                end
            end
            
            -- ADKP_Print("调试：批次 " .. batchNumber .. " 包含索引 " .. startIndex .. " 到 " .. (currentIndex-1) .. "，共 " .. count .. " 个玩家")
            
            -- 发送当前批次
            ADKP_SendAnnouncement(batchMessage, tellLocation)
            
            -- 如果不是最后一批，设置1秒后发送下一批
            if currentIndex <= listEntriesSize then
                -- ADKP_Print("调试：还有 " .. (listEntriesSize - currentIndex + 1) .. " 个玩家未发送，准备下一批")
                local timerFrame = CreateFrame("Frame")
                timerFrame:SetScript("OnUpdate", function()
                    -- 在Lua 5.0中，OnUpdate处理函数没有参数，需要使用GetTime()来计算时间差
                    local currentTime = GetTime()
                    if not timerFrame.startTime then
                        timerFrame.startTime = currentTime
                    end
                    
                    if currentTime - timerFrame.startTime >= 1.0 then  -- 等待1秒
                        timerFrame:SetScript("OnUpdate", nil)
                        batchNumber = batchNumber + 1
                        sendBatch()  -- 发送下一批
                    end
                end)
            else
                -- ADKP_Print("调试：所有玩家发送完毕")
            end
        end
        
        -- 开始发送第一批
        sendBatch()
    end
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

-- 为玩家提供一个命令来测试替补名单功能
function ADKP_TestSubstituteList()
	-- 检查装备记录功能是否已加载
    if not ADKP_LootListFrame then
        if ADKP_CreateLootListFrame then
            ADKP_CreateLootListFrame()
        else
            ADKP_Print("错误: 无法创建装备记录窗口")
            return
        end
    end
    
	-- 显示窗口
    ADKP_LootListFrame:Show()
    
	-- 切换到替补名单模式
    if ADKP_LootListFrame then
        ADKP_LootListFrame.currentMode = "substitute"
        if ADKP_LootListFrame.titleText then
            ADKP_LootListFrame.titleText:SetText("替补名单")
        end
        
        -- 更新显示
        ADKP_UpdateLootList()
    end
end

-- 添加ADKP_AddDKP函数实现
function ADKP_AddDKP(points, reason, forItem, players, tableid)
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
	
	local date = date("%Y-%m-%d %H:%M:%S");
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
                    playerData[dkpField] = currentDKP + pointsChange
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
            if ReasonEditBox:HasFocus() then
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
            if PointsEditBox:HasFocus() then
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
function ADKP_EditLootRecord(uniqueId, newItemName, newCost)
	-- 检查参数
    if not uniqueId then
        ADKP_Print("错误：缺少uniqueId参数")
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
    local targetUniqueId = uniqueId -- 保存原始uniqueId
    
    ADKP_Print("开始修改装备记录，uniqueId: " .. tostring(uniqueId))
    
    if WebDKP_Log then
        for logKey, logEntry in pairs(WebDKP_Log) do
            if type(logEntry) == "table" and logEntry.uniqueId and logEntry.uniqueId == uniqueId then
                -- 确保这是装备记录
                local isLootRecord = logEntry.foritem == true or logEntry.foritem == "true"
                
                -- ADKP_Print("找到记录，logKey: " .. tostring(logKey) .. ", isLootRecord: " .. tostring(isLootRecord))
                
                if isLootRecord then
                    -- 保存旧数据 - 装备名称使用reason字段
                    -- - 重要：使用oldPoints进行分数计算
                    oldItemName = logEntry.reason or ""
                    oldPoints = tonumber(logEntry.points) or 0
                    
                    -- ADKP_Print("旧装备名称: " .. oldItemName .. ", 旧花费: " .. oldPoints)
                    
                    -- 获取所有获得该装备的玩家
                    if logEntry.awarded then
                        -- ADKP_Print("记录使用awarded格式，玩家数量: " .. ADKP_GetTableSize(logEntry.awarded))
                        for playerName, playerInfo in pairs(logEntry.awarded) do
                            table.insert(affectedPlayers, playerName)
                            -- ADKP_Print("找到玩家: " .. playerName .. ", 信息: " .. tostring(playerInfo))
                        end
                    elseif logEntry.player then
                        -- 兼容旧格式（单个玩家）
                        table.insert(affectedPlayers, logEntry.player)
                        -- ADKP_Print("记录使用player格式，玩家: " .. logEntry.player)
                    else
                        -- ADKP_Print("警告: 记录中没有找到玩家信息")
                    end
                    
                    targetLogEntry = logKey
                    break
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
                
                WebDKP_DkpTable[playerName][dkpField] = currentDKP + costChange
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
    
	-- 同时更新ADKP_DailySubRecords中的记录
    if WebDKP_DailySubRecords then
        for dateKey, dayData in pairs(WebDKP_DailySubRecords) do
            for key, data in pairs(dayData) do
                if data.uniqueId and data.uniqueId == uniqueId then
                    data.reason = newReason
                    data.points = newPoints
                    break
                end
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
                    playerData[dkpField] = currentDKP + pointsChange
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

-- 编辑奖励记录的函数
function ADKP_EditAwardRecord(uniqueId, newReason, newPoints)
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
    
	-- 先从ADKP_Log中找到要修改的奖励记录
    local targetLogEntry = nil
    local oldReason = ""
    local oldPoints = 0
    local affectedPlayers = {}
    
    if WebDKP_Log then
        for logKey, logEntry in pairs(WebDKP_Log) do
            if type(logEntry) == "table" and logEntry.uniqueId and logEntry.uniqueId == uniqueId then
                -- 确保这是奖励记录（不是装备记录也不是替补记录）
                local isLootRecord = logEntry.foritem == true or logEntry.foritem == "true"
                local isSubstituteRecord = logEntry.reason and string.find(logEntry.reason, "替补")
                local isAwardRecord = not isLootRecord and not isSubstituteRecord
                
                if isAwardRecord then
                    -- 保存旧数据
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
        ADKP_Print("错误：未找到要修改的奖励记录")
        return false
    end
    
	-- 计算分数变化量
    local pointsChange = newPoints - oldPoints
    
	-- 更新ADKP_Log中的记录
    WebDKP_Log[targetLogEntry].reason = newReason
    WebDKP_Log[targetLogEntry].points = newPoints
    
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
                    playerData[dkpField] = currentDKP + pointsChange
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
    
    ADKP_Print("成功修改奖励记录: " .. oldReason .. " -> " .. newReason .. ", 分数: " .. oldPoints .. " -> " .. newPoints)
    return true
end

-- 显示修改装备记录对话框的函数
function ADKP_ShowEditLootDialog(uniqueId, currentItem, currentCost)
	-- 首先查找当前记录的装备名称和花费
    local logCost = currentCost -- 默认使用传入的花费
    if WebDKP_Log then
        for _, logEntry in pairs(WebDKP_Log) do
            if type(logEntry) == "table" and logEntry.uniqueId and logEntry.uniqueId == uniqueId then
                currentItem = logEntry.reason or "装备记录"
                logCost = tonumber(logEntry.points) or currentCost -- 优先使用日志中的花费
                break
            end
        end
    end
    
	-- 显示第一个对话框（输入装备名称）
    ADKP_ShowCustomLootItemDialog(uniqueId, currentItem, logCost)
end

-- 自定义装备记录装备名称输入对话框
function ADKP_ShowCustomLootItemDialog(uniqueId, currentItem, currentCost)
	-- 如果对话框已经存在，则销毁它
    if ADKP_LootItemDialog then
        ADKP_LootItemDialog:Hide()
        ADKP_LootItemDialog = nil
    end
    
	-- 创建新的对话框（不使用BasicFrameTemplate）
    local dialog = CreateFrame("Frame", "ADKP_LootItemDialog", UIParent)
    dialog:SetWidth(260)
    dialog:SetHeight(150)
    
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
        -- 保存窗口位置
        if not ADKP_DialogPositions then
            ADKP_DialogPositions = {}
        end
        local x, y = dialog:GetLeft(), dialog:GetTop()
        ADKP_DialogPositions["ADKP_LootItemDialog"] = {x = x, y = y}
    end)
    
    
	-- 设置标题
    dialog.title = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    dialog.title:SetPoint("TOP", dialog, "TOP", 0, -15)
    dialog.title:SetText("修改装备记录")
    
        -- 创建信息文本
    local infoText = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    infoText:SetPoint("TOP", dialog, "TOP", 0, -40)
    infoText:SetWidth(dialog:GetWidth() - 40)
    infoText:SetJustifyH("LEFT")
    infoText:SetText("当前装备: " .. currentItem .. "\n当前分数: " .. tostring(currentCost) .. "\n请输入新装备:")


    
	-- 创建输入框（带唯一名称）
    dialog.itemEditBox = CreateFrame("EditBox", "ADKP_LootItemEditBox"..GetTime(), dialog, "InputBoxTemplate")
    dialog.itemEditBox:SetWidth(dialog:GetWidth() - 60)
    dialog.itemEditBox:SetHeight(24)
    dialog.itemEditBox:SetPoint("TOPLEFT", infoText, "BOTTOMLEFT", 10, -10)
    dialog.itemEditBox:SetMaxLetters(50)
    dialog.itemEditBox:SetText(currentItem)
    dialog.itemEditBox:SetAutoFocus(true)
	-- 修复ESC键退出输入状态
    dialog.itemEditBox:SetScript("OnEscapePressed", function() 
        dialog.itemEditBox:ClearFocus() 
        dialog:EnableKeyboard(true)
    end)
    
	-- 添加焦点获取和失去事件
    dialog.itemEditBox:SetScript("OnEditFocusGained", function() 
        dialog:EnableKeyboard(false)
    end)
    
    dialog.itemEditBox:SetScript("OnEditFocusLost", function() 
        dialog:EnableKeyboard(true)
    end)
    dialog.itemEditBox:SetScript("OnEnterPressed", function() 
        local newItemName = dialog.itemEditBox:GetText()
        if newItemName and newItemName ~= "" then
            -- 显示第二个对话框输入花费
            ADKP_ShowCustomLootCostDialog(uniqueId, newItemName, currentCost)
        end
    end)
    
	-- 创建下一步按钮
    dialog.nextButton = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
    dialog.nextButton:SetWidth(100)
    dialog.nextButton:SetHeight(25)
    dialog.nextButton:SetPoint("BOTTOMLEFT", dialog, "BOTTOMLEFT", 20, 10)
    dialog.nextButton:SetText("下一步")
    dialog.nextButton:SetScript("OnClick", function()
        local newItemName = dialog.itemEditBox:GetText()
        if newItemName and newItemName ~= "" then
            -- 显示第二个对话框输入花费
            ADKP_ShowCustomLootCostDialog(uniqueId, newItemName, currentCost)
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
            if dialog.itemEditBox:HasFocus() then
                dialog.itemEditBox:ClearFocus()
            else
                dialog:Hide()
            end
        end
    end)
    
	-- 保存到全局变量
    ADKP_LootItemDialog = dialog
    dialog:Show()
    
	-- 防止输入框在显示时失去焦点
    dialog.itemEditBox:SetFocus()
end

-- 自定义装备记录花费输入对话框
function ADKP_ShowCustomLootCostDialog(uniqueId, newItemName, currentCost)
	-- 如果对话框已经存在，则销毁它
    if ADKP_LootCostDialog then
        ADKP_LootCostDialog:Hide()
        ADKP_LootCostDialog = nil
    end
    
	-- 如果上一个对话框存在，隐藏它
    if ADKP_LootItemDialog then
        ADKP_LootItemDialog:Hide()
    end
    
	-- 创建新的对话框（不使用BasicFrameTemplate）
    local dialog = CreateFrame("Frame", "ADKP_LootCostDialog", UIParent)
    dialog:SetWidth(260)
    dialog:SetHeight(150)
    
	-- 加载保存的窗口位置，如果没有则居中显示
    if ADKP_DialogPositions and ADKP_DialogPositions["ADKP_LootCostDialog"] then
        local pos = ADKP_DialogPositions["ADKP_LootCostDialog"]
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
        ADKP_DialogPositions["ADKP_LootCostDialog"] = {x = x, y = y}
    end)
    
	-- 设置标题
    dialog.title = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    dialog.title:SetPoint("TOP", dialog, "TOP", 0, -15)
    dialog.title:SetText("修改装备记录")
    

       -- 创建信息文本
    local infoText = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    infoText:SetPoint("TOP", dialog, "TOP", 0, -40)
    infoText:SetWidth(dialog:GetWidth() - 40)
    infoText:SetJustifyH("LEFT")
    infoText:SetText("新装备: " .. newItemName .. "\n当前分数: " .. tostring(currentCost) .. "\n请输入新分数:")
    
	-- 创建输入框（带唯一名称）
    dialog.costEditBox = CreateFrame("EditBox", "ADKP_LootCostEditBox"..GetTime(), dialog, "InputBoxTemplate")
    dialog.costEditBox:SetWidth(dialog:GetWidth() - 60)
    dialog.costEditBox:SetHeight(24)
    dialog.costEditBox:SetPoint("TOPLEFT", infoText, "BOTTOMLEFT", 10, -10)
    dialog.costEditBox:SetMaxLetters(10)
    dialog.costEditBox:SetText(tostring(currentCost))
    dialog.costEditBox:SetAutoFocus(true)
	-- 修复ESC键退出输入状态
    dialog.costEditBox:SetScript("OnEscapePressed", function() 
        dialog.costEditBox:ClearFocus() 
        dialog:EnableKeyboard(true)
    end)
    
	-- 添加焦点获取和失去事件
    dialog.costEditBox:SetScript("OnEditFocusGained", function() 
        dialog:EnableKeyboard(false)
    end)
    
    dialog.costEditBox:SetScript("OnEditFocusLost", function() 
        dialog:EnableKeyboard(true)
    end)
    dialog.costEditBox:SetScript("OnEnterPressed", function() 
        local newCost = dialog.costEditBox:GetText()
        ADKP_EditLootRecord(uniqueId, newItemName, newCost)
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
        local newCost = dialog.costEditBox:GetText()
        ADKP_EditLootRecord(uniqueId, newItemName, newCost)
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
            if dialog.costEditBox:HasFocus() then
                dialog.costEditBox:ClearFocus()
            else
                dialog:Hide()
            end
        end
    end)
    
	-- 保存到全局变量
    ADKP_LootCostDialog = dialog
    dialog:Show()
    
	-- 防止输入框在显示时失去焦点
    dialog.costEditBox:SetFocus()
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
            if dialog.reasonEditBox:HasFocus() then
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
            if dialog.pointsEditBox:HasFocus() then
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

-- 显示修改奖励记录对话框的函数
function ADKP_ShowEditAwardDialog(uniqueId, currentPoints, currentReason)
	-- 交换参数位置以与其他函数保持一致的调用模式
	-- 创建一个简单的输入框对话框
    StaticPopupDialogs["ADKP_EDIT_AWARD"] = {
        text = "修改奖励记录\n当前原因: " .. currentReason .. "\n当前分数: " .. tostring(currentPoints) .. "\n请输入新原因:",
        button1 = "下一步",
        button2 = "取消",
        hasEditBox = 1,
        maxLetters = 100,
        uniqueId = uniqueId,
        currentPoints = currentPoints,
        currentReason = currentReason,
        OnAccept = function()
            local parentName = this:GetParent():GetName()
            if parentName then
                local editBox = getglobal(parentName.."EditBox")
                if editBox then
                    local newReason = editBox:GetText()
                    if newReason and newReason ~= "" then
                        -- 显示第二个对话框输入新分数
                        StaticPopupDialogs["ADKP_EDIT_AWARD_POINTS"] = {
                            text = "修改奖励记录\n新原因: " .. newReason .. "\n当前分数: " .. tostring(currentPoints) .. "\n请输入新分数:",
                            button1 = "确定",
                            button2 = "取消",
                            hasEditBox = 1,
                            maxLetters = 10,
                            uniqueId = uniqueId,
                            newReason = newReason,
                            currentPoints = currentPoints,
                            OnAccept = function()
                                local pointsParentName = this:GetParent():GetName()
                                if pointsParentName then
                                     local pointsEditBox = getglobal(pointsParentName.."EditBox")
                                    if pointsEditBox then
                                        local newPoints = pointsEditBox:GetText()
                                        local uniqueId = StaticPopupDialogs["ADKP_EDIT_AWARD_POINTS"].uniqueId
                                        local newReason = StaticPopupDialogs["ADKP_EDIT_AWARD_POINTS"].newReason
                                        ADKP_EditAwardRecord(uniqueId, newReason, newPoints)
                                        -- 修改分数后刷新界面，相当于按了刷新队伍
                                        ADKP_UpdateTable()
                                        ADKP_UpdateLootList()
                                    end
                                end
                            end,
                            OnShow = function()
                                local showParentName = this:GetParent():GetName()
                                if showParentName then
                                     local editBox = getglobal(showParentName.."EditBox")
                                    if editBox then
                                        -- 确保输入框正确填充分数
                                        editBox:SetText(tostring(StaticPopupDialogs["ADKP_EDIT_AWARD_POINTS"].currentPoints))
                                        editBox:SetFocus()
                                        -- 添加ESC键离开输入模式的功能
                                        editBox:SetScript("OnEscapePressed", function()
                                            editBox:ClearFocus()
                                        end)
                                        -- 添加回车键确认输入的功能
                                        editBox:SetScript("OnEnterPressed", function()
                                            editBox:ClearFocus()
                                        end)
                                    end
                                end
                            end,
                            timeout = 0,
                            exclusive = 1,
                            hideOnEscape = 1,
                            whileDead = 1,
                            movable = 1,  -- 确保窗口可移动
                            closeOnEscape = 1,  -- 确保ESC可以关闭对话框
                            closeOnClick = 1    -- 确保点击对话框外部可以关闭
                        }
                        StaticPopup_Show("ADKP_EDIT_AWARD_POINTS")
                    end
                end
            end
        end,
        OnShow = function()
            local parentName = this:GetParent():GetName()
            if parentName then
                local editBox = getglobal(parentName.."EditBox")
                if editBox then
                    -- 确保输入框正确填充原因
                    editBox:SetText(StaticPopupDialogs["ADKP_EDIT_AWARD"].currentReason)
                    editBox:SetFocus()
                    -- 添加ESC键离开输入模式的功能
                    editBox:SetScript("OnEscapePressed", function()
                        editBox:ClearFocus()
                    end)
                    -- 添加回车键确认输入的功能
                    editBox:SetScript("OnEnterPressed", function()
                        editBox:ClearFocus()
                    end)
                end
            end
        end,
        timeout = 0,
        exclusive = 1,
        hideOnEscape = 1,
        whileDead = 1,
        movable = 1,  -- 确保窗口可移动
        closeOnEscape = 1,  -- 确保ESC可以关闭对话框
        closeOnClick = 1    -- 确保点击对话框外部可以关闭
    }
    StaticPopup_Show("ADKP_EDIT_AWARD")
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
    elseif WebDKP_Options and WebDKP_Options["SubSettings"] then
        captain = WebDKP_Options["SubSettings"].captain or ""
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
    local cap = ""
    if WebDKP_Options and WebDKP_Options["SubSettings"] then
        cap = WebDKP_Options["SubSettings"].captain or ""
    end
    if cap == "" then return false end
    if not ADKP_SubSync_Cache then return false end
    local c = ADKP_SubSync_Cache[string.lower(cap)]
    if not c or not c.members then return false end
    for memberName, _ in pairs(c.members) do
        if memberName == name then return true end
    end
    return false
end

-- ===== Tab1 right-side rebuild (3c) =====
function ADKP_ToggleSubHalf()
    if not WebDKP_Options then WebDKP_Options = {} end
    local v = not WebDKP_Options["SubHalfPointsEnabled"]
    WebDKP_Options["SubHalfPointsEnabled"] = v
    if v then
        WebDKP_Options["SubPointsMode"] = "half"
    else
        WebDKP_Options["SubPointsMode"] = "same"
    end
end

function ADKP_Tab1_SyncChecks()
    if ADKP_AwardDKP_FrameSubCaptainChk then
        ADKP_AwardDKP_FrameSubCaptainChk:SetChecked(WebDKP_Options and WebDKP_Options["IncludeSubCaptain"] and true or false)
    end
    if ADKP_AwardDKP_FrameSubHalfChk then
        ADKP_AwardDKP_FrameSubHalfChk:SetChecked(WebDKP_Options and WebDKP_Options["SubHalfPointsEnabled"] and true or false)
    end
    if ADKP_AwardDKP_FrameSubLeaderInput and WebDKP_Options and WebDKP_Options["SubSettings"] then
        ADKP_AwardDKP_FrameSubLeaderInput:SetText(WebDKP_Options["SubSettings"].captain or "")
    end
    -- 功能设置区（从系统设置迁入）勾选状态恢复
    if ADKP_AwardDKP_FrameToggleAutoAward then
        ADKP_AwardDKP_FrameToggleAutoAward:SetChecked(WebDKP_Options and WebDKP_Options["AutoAwardEnabled"] == 1)
    end
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
    if ADKP_AwardDKP_FrameToggleZeroSum then
        ADKP_AwardDKP_FrameToggleZeroSum:SetChecked(WebDKP_WebOptions and WebDKP_WebOptions["ZeroSumEnabled"] == 1)
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
end

function ADKP_Tab1_SaveSubCaptain()
    local txt = ""
    if ADKP_AwardDKP_FrameSubLeaderInput then
        txt = ADKP_AwardDKP_FrameSubLeaderInput:GetText() or ""
    end
    txt = string.gsub(txt, "^%s+", "")
    txt = string.gsub(txt, "%s+$", "")
    if not WebDKP_Options then WebDKP_Options = {} end
    if not WebDKP_Options["SubSettings"] then WebDKP_Options["SubSettings"] = { captain = "" } end
    WebDKP_Options["SubSettings"]["captain"] = txt
    WebDKP_Options["SubLeader"] = txt
    if ADKP_SubAwardData then ADKP_SubAwardData.captain = txt end
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
        WebDKP_DkpTable = {}
        WebDKP_Log = {}
        if WebDKP_DailySubRecords then WebDKP_DailySubRecords = {} end
        local tableid = ADKP_GetTableid()
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
        ADKP_Print("已导入 " .. count .. " 条初始分。")
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
            hideOnEscape = 1
        }
    end
    StaticPopupDialogs["ADKP_IMPORT_INITIAL_CONFIRM"].text = "注意：历史数据将被全部清空并替换成导入数据！！"
    StaticPopupDialogs["ADKP_IMPORT_INITIAL_CONFIRM"]._confirmCallback = proceedWithImport
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
        local sf = CreateFrame("ScrollFrame", "ADKP_ImportInitialScroll", f, "UIPanelScrollFrameTemplate")
        sf:SetPoint("TOPLEFT", 18, -58)
        sf:SetPoint("BOTTOMRIGHT", -36, 48)
        local eb = CreateFrame("EditBox", "ADKP_ImportInitialEdit", sf)
        eb:SetMultiLine(true)
        eb:SetWidth(350)
        eb:SetHeight(240)
        eb:SetAutoFocus(false)
        eb:SetMaxLetters(0)
        eb:SetFontObject(ChatFontNormal)
        eb:SetScript("OnEscapePressed", function() this:ClearFocus() end)
        sf:SetScrollChild(eb)
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
    local lines = {}
    if WebDKP_Log then
        for key, entry in pairs(WebDKP_Log) do
            if type(entry) == "table" and entry.awarded then
                local pts = entry.points or 0
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
    return table.concat(lines, "\n")
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
        local hint = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        hint:SetPoint("TOPLEFT", 20, -40)
        hint:SetText("点「全选」+Ctrl+C 可一次复制全部（界面未显示部分也已包含）。格式：角色,分值,原因,日期,时间,职业")
        local sf = CreateFrame("ScrollFrame", "ADKP_ExportRecordsScroll", f, "UIPanelScrollFrameTemplate")
        sf:SetPoint("TOPLEFT", 18, -58)
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
    local exportText = ADKP_BuildExportText()
    ADKP_ExportRecordsEdit:SetText(exportText)
    -- 标题显示总行数：用户据此确认「全选+复制」确实拿到了全部数据（粘贴后行数对得上即可）。
    local _, lineCount = string.gsub(exportText, "\n", "\n")
    if exportText == "" then lineCount = 0 else lineCount = lineCount + 1 end
    ADKP_ExportRecordsFrame.title:SetText("导出当前记录（共 " .. lineCount .. " 行）")
    ADKP_ExportRecordsFrame:Show()
    ADKP_ExportRecordsEdit:SetFocus()
    ADKP_ExportRecordsEdit:HighlightText()
end


function ADKP_Options_Init()
    if not WebDKP_Options then WebDKP_Options = {} end
    if not WebDKP_WebOptions then WebDKP_WebOptions = {} end
    
    if ADKP_Options_FrameToggleAutofill then
        ADKP_Options_FrameToggleAutofill:SetChecked(WebDKP_WebOptions["AutofillEnabled"] == 1)
    end
    if ADKP_Options_FrameToggleAutoAward then
        ADKP_Options_FrameToggleAutoAward:SetChecked(WebDKP_Options["AutoAwardEnabled"] == 1)
    end
    if ADKP_Options_FrameToggleZeroSum then
        ADKP_Options_FrameToggleZeroSum:SetChecked(WebDKP_WebOptions["ZeroSumEnabled"] == 1)
    end

    if ADKP_Options_FrameToggleSilentMode then
        ADKP_Options_FrameToggleSilentMode:SetChecked(WebDKP_Options["SilentMode"] and true or false)
    end
    if ADKP_Options_FrameToggleRaidDkpReply then
        ADKP_Options_FrameToggleRaidDkpReply:SetChecked(WebDKP_Options["RaidDkpReply"] and true or false)
    end
    if ADKP_Options_FrameToggleQuickFloatEnabled then
        ADKP_Options_FrameToggleQuickFloatEnabled:SetChecked(WebDKP_Options["QuickFloatEnabled"] and true or false)
    end
    if WebDKP_Options["KeepOnlineEnabled"] == nil then WebDKP_Options["KeepOnlineEnabled"] = false end
    if ADKP_Options_FrameToggleKeepOnline then
        ADKP_Options_FrameToggleKeepOnline:SetChecked(WebDKP_Options["KeepOnlineEnabled"] and true or false)
    end

    -- 密语组人 / 自动转团 / 邀请密语
    if WebDKP_Options["AutoInviteEnabled"] == nil then WebDKP_Options["AutoInviteEnabled"] = false end
    if WebDKP_Options["AutoConvertRaid"] == nil then WebDKP_Options["AutoConvertRaid"] = false end
    if WebDKP_Options["AutoInviteKeyword"] == nil or WebDKP_Options["AutoInviteKeyword"] == "" then
        WebDKP_Options["AutoInviteKeyword"] = "9527"
    end
    if ADKP_AwardDKP_FrameToggleAutoInvite then
        ADKP_AwardDKP_FrameToggleAutoInvite:SetChecked(WebDKP_Options["AutoInviteEnabled"] and true or false)
    end
    if ADKP_AwardDKP_FrameToggleAutoConvertRaid then
        ADKP_AwardDKP_FrameToggleAutoConvertRaid:SetChecked(WebDKP_Options["AutoConvertRaid"] and true or false)
    end
    if ADKP_AwardDKP_FrameAutoInviteKeyword then
        ADKP_AwardDKP_FrameAutoInviteKeyword:SetText(WebDKP_Options["AutoInviteKeyword"] or "9527")
    end
    if WebDKP_Options["AuctionMode"] == nil then WebDKP_Options["AuctionMode"] = "public" end
    if ADKP_Options_FrameToggleAuctionPublic then
        ADKP_Options_FrameToggleAuctionPublic:SetChecked(WebDKP_Options["AuctionMode"] ~= "anonymous")
    end
    if ADKP_Options_FrameToggleAuctionAnonymous then
        ADKP_Options_FrameToggleAuctionAnonymous:SetChecked(WebDKP_Options["AuctionMode"] == "anonymous")
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
    if ADKP_Options_FrameToggleQuickFloatEnabled then
        ADKP_Options_FrameToggleQuickFloatEnabled:SetChecked(WebDKP_Options["QuickFloatEnabled"])
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

function ADKP_SelectAuctionMode(mode)
    if not WebDKP_Options then WebDKP_Options = {} end
    if mode ~= "anonymous" then mode = "public" end
    WebDKP_Options["AuctionMode"] = mode
    if ADKP_Options_FrameToggleAuctionPublic then
        ADKP_Options_FrameToggleAuctionPublic:SetChecked(mode == "public")
    end
    if ADKP_Options_FrameToggleAuctionAnonymous then
        ADKP_Options_FrameToggleAuctionAnonymous:SetChecked(mode == "anonymous")
    end
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

-- 判断当前能否邀请（必须是队长/团长，且队伍未满）
-- 返回 true 可邀请；返回 false, reason 不可邀请
function ADKP_AutoInvite_CanInvite()
    -- 不在任何队伍/团队中，无法邀请
    if GetNumPartyMembers() == 0 and GetNumRaidMembers() == 0 then
        return false, "你不在任何队伍或团队中"
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

function ADKP_SelectSubPointsMode(mode)
    WebDKP_Options["SubPointsMode"] = mode
    
    if ADKP_AwardDKP_FrameSubHalf then
        ADKP_AwardDKP_FrameSubHalf:SetChecked(mode == "half")
    end
    if ADKP_AwardDKP_FrameSubCustom then
        ADKP_AwardDKP_FrameSubCustom:SetChecked(mode == "custom")
    end
    
    if mode == "custom" then
        if ADKP_AwardDKP_FrameSubCustomPercent then
            ADKP_AwardDKP_FrameSubCustomPercent:Show()
        end
        if ADKP_AwardDKP_FrameSubCustomPercentLabel then
            ADKP_AwardDKP_FrameSubCustomPercentLabel:Show()
        end
    else
        if ADKP_AwardDKP_FrameSubCustomPercent then
            ADKP_AwardDKP_FrameSubCustomPercent:Hide()
            ADKP_AwardDKP_FrameSubCustomPercent:ClearFocus()
        end
        if ADKP_AwardDKP_FrameSubCustomPercentLabel then
            ADKP_AwardDKP_FrameSubCustomPercentLabel:Hide()
        end
    end
end

function ADKP_ResolveSubCaptain()
    local cap = ""
    if ADKP_AwardDKP_FrameSubLeaderInput then
        local t = ADKP_AwardDKP_FrameSubLeaderInput:GetText() or ""
        if t ~= "" then cap = t end
    end
    if cap == "" and WebDKP_Options and WebDKP_Options["SubSettings"] then
        cap = WebDKP_Options["SubSettings"].captain or ""
    end
    cap = string.gsub(cap, "^%s+", "")
    cap = string.gsub(cap, "%s+$", "")
    if cap ~= "" then
        if not WebDKP_Options then WebDKP_Options = {} end
        if not WebDKP_Options["SubSettings"] then WebDKP_Options["SubSettings"] = { captain = "" } end
        WebDKP_Options["SubSettings"]["captain"] = cap
        WebDKP_Options["SubLeader"] = cap
        if ADKP_SubAwardData then ADKP_SubAwardData.captain = cap end
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
    ADKP_SubAwardData.captain = captain
    ADKP_SubAwardData.receivedResponse = false
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

function ADKP_AwardRaidAndSub_Event_LegacyUnused2()
    local pointsText = ADKP_AwardDKP_FramePoints:GetText() or ""
    local points = tonumber(pointsText)
    if not points or points <= 0 then
        ADKP_Print("错误：请输入有效的加分值！")
        return
    end
    
    local reason = ADKP_AwardDKP_FrameReason:GetText() or ""
    if reason == "" then
        reason = "未指定原因"
    end
    
    local pointsMode = WebDKP_Options["SubPointsMode"] or "same"
    local standbyPoints = points
    if pointsMode == "half" then
        standbyPoints = points * 0.5
    elseif pointsMode == "custom" then
        local customPercentText = ADKP_AwardDKP_FrameSubCustomPercent:GetText() or ""
        local percent = tonumber(customPercentText) or 0
        standbyPoints = points * (percent / 100)
    end
    
    local captain = ""
    if ADKP_Options_FrameSubLeader then
        captain = ADKP_Options_FrameSubLeader:GetText() or ""
    end
    
    local raidPlayers = {}
    local numRaid = GetNumRaidMembers()
    local numParty = GetNumPartyMembers()
    
    if numRaid > 0 then
        for i = 1, numRaid do
            local name, _, _, _, _, class = GetRaidRosterInfo(i)
            if name then
                tinsert(raidPlayers, { ["name"] = name, ["class"] = class })
            end
        end
    elseif numParty > 0 then
        for i = 1, numParty do
            local name = GetPartyMember(i)
            if name then
                local _, class = UnitClass("party" .. i)
                tinsert(raidPlayers, { ["name"] = name, ["class"] = class })
            end
        end
        local myName = UnitName("player")
        local _, myClass = UnitClass("player")
        tinsert(raidPlayers, { ["name"] = myName, ["class"] = myClass })
    else
        local myName = UnitName("player")
        local _, myClass = UnitClass("player")
        tinsert(raidPlayers, { ["name"] = myName, ["class"] = myClass })
    end
    
    if captain == "" then
        local players = {}
        for idx, p in ipairs(raidPlayers) do
            players[idx - 1] = { ["name"] = p.name, ["class"] = p.class }
        end
        ADKP_AddDKP(points, reason, "false", players)
        ADKP_AnnounceAward(points, reason)
        ADKP_Print("加分成功！已为大团发放分数。")
        ADKP_UpdateTable()
        return
    end
    
    ADKP_Print("正在向替补队长 " .. captain .. " 请求替补人员名单...")
    if not ADKP_PendingSubMembers then
        ADKP_PendingSubMembers = {}
    end
    ADKP_PendingSubMembers[captain] = {}
    ADKP_SubAwardData.captain = captain
    ADKP_SubAwardData.receivedResponse = false
    
    pcall(SendAddonMessage, "AMB_TBQQ", captain, "GUILD")
    
    if not ADKP_RaidAwardTimerFrame then
        ADKP_RaidAwardTimerFrame = CreateFrame("Frame")
    end
    
    ADKP_RaidAwardTimerFrame.timeElapsed = 0
    ADKP_RaidAwardTimerFrame:SetScript("OnUpdate", function()
        local elapsed = tonumber(arg1) or 0
        this.timeElapsed = this.timeElapsed + elapsed
        
        if ADKP_SubAwardData.receivedResponse or this.timeElapsed >= 1.5 then
            this:SetScript("OnUpdate", nil)
            
            local standbyPlayers = {}
            if ADKP_SubAwardData.receivedResponse then
                local subList = ADKP_PendingSubMembers[captain] or {}
                for name, class in pairs(subList) do
                    local isDuplicate = false
                    for _, rp in ipairs(raidPlayers) do
                        if rp.name == name then
                            isDuplicate = true
                            break
                        end
                    end
                    if not isDuplicate then
                        tinsert(standbyPlayers, { ["name"] = name, ["class"] = class })
                    end
                end
                
                local includeCaptain = WebDKP_Options["IncludeSubCaptain"]
                if includeCaptain then
                    local isDuplicate = false
                    for _, rp in ipairs(raidPlayers) do
                        if rp.name == captain then
                            isDuplicate = true
                            break
                        end
                    end
                    for _, sp in ipairs(standbyPlayers) do
                        if sp.name == captain then
                            isDuplicate = true
                            break
                        end
                    end
                    if not isDuplicate then
                        local capClass = "未知"
                        tinsert(standbyPlayers, { ["name"] = captain, ["class"] = capClass })
                    end
                end
                
                ADKP_Print("替补名单获取成功，正在发放 DKP 分数...")
            else
                ADKP_Print("|cffff0000[ADKP] 替补同步超时！|r 降级为仅对大团成员发放 DKP 分数。")
            end
            
            local finalRaidPlayers = {}
            for idx, p in ipairs(raidPlayers) do
                finalRaidPlayers[idx - 1] = { ["name"] = p.name, ["class"] = p.class }
            end
            ADKP_AddDKP(points, reason, "false", finalRaidPlayers)
            
            if table.getn(standbyPlayers) > 0 then
                local finalStandbyPlayers = {}
                for idx, p in ipairs(standbyPlayers) do
                    finalStandbyPlayers[idx - 1] = { ["name"] = p.name, ["class"] = p.class }
                end
                ADKP_AddDKP(standbyPoints, reason .. "-替补", "false", finalStandbyPlayers)
                ADKP_Print(string.format("发放完毕！大团 %d 人 (+%.2f)，替补 %d 人 (+%.2f)。", 
                    table.getn(raidPlayers), points, table.getn(standbyPlayers), standbyPoints))
            else
                ADKP_Print(string.format("发放完毕！大团 %d 人 (+%.2f)，替补 0 人。", table.getn(raidPlayers), points))
            end
            
            ADKP_AnnounceAward(points, reason)
            ADKP_UpdateTable()
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

    local subPoints = points
    local pointsMode = "same"
    if WebDKP_Options and WebDKP_Options["SubPointsMode"] then
        pointsMode = WebDKP_Options["SubPointsMode"]
    end

    if pointsMode == "half" then
        subPoints = points * 0.5
    elseif pointsMode == "custom" then
        local percentText = ""
        if ADKP_AwardDKP_FrameSubCustomPercent then
            percentText = ADKP_AwardDKP_FrameSubCustomPercent:GetText() or ""
        end
        local percent = tonumber(percentText)
        if not percent and WebDKP_Options then
            percent = tonumber(WebDKP_Options["SubPointsCustomPercent"])
        end
        if not percent then
            ADKP_Print("错误：请输入有效的替补百分比。")
            PlaySound("igQuestFailed")
            return
        end
        subPoints = points * (percent / 100)
        if WebDKP_Options then
            WebDKP_Options["SubPointsCustomPercent"] = percent
        end
    end

    if ADKP_ROUND then
        subPoints = ADKP_ROUND(subPoints, 2)
    end

    if ADKP_SubAwardData then
        ADKP_SubAwardData.reason = reason
        ADKP_SubAwardData.points = subPoints
    end

    ADKP_RunRaidAndSubAward(points, subPoints, reason)
end
