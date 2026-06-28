-- ================================  
-- 备份数据功能  
-- ================================  
function WebDKP_BackupData()  
    -- 检查是否支持superwow
    if not SUPERWOW_STRING or not ExportFile then
        WebDKP_Print("错误：备份数据功能需要superwow支持且ExportFile函数可用")
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
    
    -- 数据文件内容格式：“玩家名称,分数,项目名称,日期,时间,职业”
    local exportText = "玩家名称,分数,项目名称,日期,时间,职业\n"
    
    if WebDKP_Log then  
        for key, entry in pairs(WebDKP_Log) do  
            if key ~= "Version" and type(entry) == "table" and entry.awarded then  
                local time = entry.date or "未知时间"  
                local reason = entry.reason or "未知原因"  
                local points = entry.points or 0
                
                -- 将日期和时间用空格分割
                local datePart, timePart = "未知日期", "未知时间"
                local spacePos = string.find(time, " ")
                if spacePos then
                    datePart = string.sub(time, 1, spacePos - 1)
                    timePart = string.sub(time, spacePos + 1)
                else
                    datePart = time
                    timePart = ""
                end
                
                -- 转义逗号
                local cleanReason = string.gsub(reason, ",", " ")
                
                -- 遍历玩家（逐行输出：一个玩家一行）
                for playerName, playerInfo in pairs(entry.awarded) do  
                    local class = "未知"
                    if type(playerInfo) == "table" and playerInfo.class then
                        class = playerInfo.class
                    elseif WebDKP_DkpTable and WebDKP_DkpTable[playerName] then
                        class = WebDKP_DkpTable[playerName].class or "未知"
                    end
                    
                    local line = playerName .. "," .. points .. "," .. cleanReason .. "," .. datePart .. "," .. timePart .. "," .. class .. "\n"
                    exportText = exportText .. line
                end  
            end  
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
    
    WebDKP_Print("数据已成功备份到: " .. dataFileName)
    WebDKP_Print("指针文件已保存: " .. pointerFileName)
end

-- ================================
-- 恢复数据功能  
-- ================================
function WebDKP_RestoreData()  
    -- 检查是否支持superwow
    if not SUPERWOW_STRING or not ImportFile then
        WebDKP_Print("错误：恢复数据功能需要superwow支持且ImportFile函数可用")
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

        -- 如果 checkDate 等于已验证 of svDate，且之前没有找到更新的备份
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
        WebDKP_Print("未找到任何备份记录（已检索近60天及SavedVariables）")
        return
    end

    WebDKP_Print("已找到最新备份记录，日期：" .. foundDate .. " 文件：" .. latestPointerFileName)

    -- 3. 读取指针文件里的数据文件名
    local dataFileName = ImportFile(latestPointerFileName)
    if not dataFileName or dataFileName == "" then
        WebDKP_Print("错误：指针文件内容为空，无法读取数据文件名")
        return
    end

    -- 去除换行符和首尾多余空格
    dataFileName = string.gsub(dataFileName, "[\r\n]", "")
    dataFileName = string.gsub(dataFileName, "^%s*(.-)%s*$", "%1")

    -- 4. 导入数据文件
    local importData = ImportFile(dataFileName) or ImportFile(dataFileName .. ".txt")
    if not importData or importData == "" then
        WebDKP_Print("错误：无法读取备份数据文件：" .. dataFileName)
        return
    end

    -- 5. 开始解析备份数据并恢复
    WebDKP_Print("开始恢复活动数据...")  
    WebDKP_Print("已读取文件：" .. dataFileName)

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
    
    -- 临时结构：按 reason + date + time + points 分组 DKP 记录
    local dkpGroups = {}
    
    for i, line in ipairs(lines) do
        -- 跳过空行和表头
        if line ~= "" and i > 1 then
            local fields = splitString(line, ",")
            if table.getn(fields) >= 6 then
                local player = fields[1]
                local points = tonumber(fields[2]) or 0
                local reason = fields[3]
                local datePart = fields[4]
                local timePart = fields[5]
                local class = fields[6]
                
                local timeStr = datePart .. " " .. timePart
                
                -- 记录职业对照
                if class and class ~= "未知" and class ~= "" then
                    playerClassMap[player] = class
                end
                
                if points >= 0 then
                    -- 分组 DKP
                    local groupKey = reason .. "|" .. timeStr .. "|" .. points
                    if not dkpGroups[groupKey] then
                        dkpGroups[groupKey] = {
                            time = timeStr,
                            reason = reason,
                            points = points,
                            players = {}
                        }
                    end
                    table.insert(dkpGroups[groupKey].players, player)
                else
                    -- 装备记录 (分数 < 0)
                    table.insert(lootRecords, {
                        time = timeStr,
                        item = reason,
                        player = player,
                        points = points
                    })
                end
            end
        end
    end
    
    -- 将 DKP 分组转换为 dkpRecords
    for _, group in pairs(dkpGroups) do
        local playersStr = ""
        for _, p in ipairs(group.players) do
            if playersStr ~= "" then
                playersStr = playersStr .. ","
            end
            playersStr = playersStr .. p
        end
        table.insert(dkpRecords, {
            time = group.time,
            reason = group.reason,
            points = group.points,
            players = playersStr
        })
    end

    local restoredCount = 0 
    local skippedCount = 0 
    local tableid = WebDKP_GetTableid() 

    -- 重复检查辅助函数
    local function isDuplicateDKPRecord(record, players)
        if not WebDKP_Log then
            return false
        end
        for _, existingEntry in pairs(WebDKP_Log) do
            if type(existingEntry) == "table" then
                local isDKPRecord = existingEntry.foritem == false or existingEntry.foritem == "false"
                if isDKPRecord then
                    if existingEntry.date == record.time and 
                       existingEntry.reason == record.reason and 
                       existingEntry.points == record.points then
                        
                        local isSamePlayers = true
                        local existingPlayers = existingEntry.awarded or {}
                        
                        for player, _ in pairs(players) do
                            if not existingPlayers[player] then
                                isSamePlayers = false
                                break
                            end
                        end
                        
                        for player, _ in pairs(existingPlayers) do
                            if not players[player] then
                                isSamePlayers = false
                                break
                            end
                        end
                        
                        if isSamePlayers then
                            return true
                        end
                    end
                end
            end
        end
        return false
    end
    
    local function isDuplicateLootRecord(record)
        if not WebDKP_Log then
            return false
        end
        for _, existingEntry in pairs(WebDKP_Log) do
            if type(existingEntry) == "table" then
                local isLootRecord = existingEntry.foritem == true or existingEntry.foritem == "true"
                if isLootRecord then
                    local existingPlayer = ""
                    for player, _ in pairs(existingEntry.awarded or {}) do
                        existingPlayer = player
                        break
                    end
                    
                    if existingEntry.date == record.time and 
                       existingEntry.reason == record.item and 
                       existingPlayer == record.player and 
                       existingEntry.points == record.points then
                        return true
                    end
                end
            end
        end
        return false
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
            
            for playerName, playerInfo in pairs(players) do
                if not WebDKP_DkpTable[playerName] then
                    WebDKP_DkpTable[playerName] = {
                        ["class"] = playerInfo["class"],
                        ["dkp" .. tableid] = 0,
                        ["Selected"] = false,
                        ["IsSub"] = false
                    }
                end
                local dkpField = "dkp" .. tableid
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
            
            for playerName, playerInfo in pairs(players) do
                if not WebDKP_DkpTable[playerName] then
                    WebDKP_DkpTable[playerName] = {
                        ["class"] = playerInfo["class"],
                        ["dkp" .. tableid] = 0,
                        ["Selected"] = false,
                        ["IsSub"] = false
                    }
                end
                local dkpField = "dkp" .. tableid
                WebDKP_DkpTable[playerName][dkpField] = (WebDKP_DkpTable[playerName][dkpField] or 0) + record.points
            end
            restoredCount = restoredCount + 1
        else
            skippedCount = skippedCount + 1
        end
    end
    
    -- 保存数据
    if WebDKP_SaveToDisk then
        WebDKP_SaveToDisk()
    end
    
    -- 刷新列表
    WebDKP_UpdateTableToShow()
    WebDKP_UpdateTable()
    WebDKP_UpdateLootList()
    
    if WebDKP_Frame then
        WebDKP_Frame:Show()
    end
    
    local totalCount = restoredCount + skippedCount
    WebDKP_Print("数据恢复完成。共处理" .. totalCount .. "条记录，成功恢复" .. restoredCount .. "条。")
    if skippedCount > 0 then
        WebDKP_Print("跳过了" .. skippedCount .. "条重复记录。")
    end
end

-- ================================  
-- 初始化自动备份设置  
-- ================================  
function WebDKP_BackupRestore_Init()
    -- 确保WebDKP_Options表存在
    if not WebDKP_Options then
        WebDKP_Options = {}
    end
    
    -- 初始化自动备份设置
    if WebDKP_Options["AutoBackupEnabled"] == nil then
        WebDKP_Options["AutoBackupEnabled"] = false
    end
end

-- 注册初始化函数到ADDON_LOADED事件
if not WebDKP_BackupRestore_Registered then
    WebDKP_BackupRestore_Registered = true
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("ADDON_LOADED")
    frame:SetScript("OnEvent", function()
        WebDKP_BackupRestore_Init()
    end)
end