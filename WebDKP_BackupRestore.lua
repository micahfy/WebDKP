-- ================================  
-- 备份数据功能  
-- ================================  
function WebDKP_BackupData()  
    -- 只导出活动的加减分项和装备奖惩内容  
    local currentDate = date("%Y-%m-%d")  
    local fileName = "活动数据-" .. currentDate  
    local exportText = "# WebDKP活动数据备份\n"  
    exportText = exportText .. "# 备份日期: " .. currentDate .. "\n\n"  
    -- 导出DKP奖惩记录  
    exportText = exportText .. "# DKP奖惩\n"  
    exportText = exportText .. "时间,原因,点数,涉及玩家\n"  
    
    -- 遍历WebDKP_Log获取DKP奖惩记录（排除装备奖惩）  
    if WebDKP_Log then  
        for key, entry in pairs(WebDKP_Log) do  
            if key ~= "Version" and type(entry) == "table" and entry.awarded and not (entry.foritem == "true" or entry.foritem == true) then  
                local time = entry.date or "未知时间"  
                local reason = entry.reason or "未知原因"  
                local points = entry.points or 0  
                local players = ""  
                
                -- 收集涉及的玩家  
                for playerName, _ in pairs(entry.awarded) do  
                    if players ~= "" then  
                        players = players .. ","  
                    end  
                    players = players .. playerName  
                end  
                
                exportText = exportText .. time .. "," .. reason .. "," .. points .. "," .. players .. "\n"  
            end  
        end  
    end  
    
    -- 导出装备奖惩记录  
    exportText = exportText .. "\n# 装备奖惩\n"  
    exportText = exportText .. "时间,装备,玩家,点数\n"  
    
    -- 遍历WebDKP_Log获取装备奖惩记录  
    if WebDKP_Log then  
        for key, entry in pairs(WebDKP_Log) do  
            if key ~= "Version" and type(entry) == "table" and entry.awarded and (entry.foritem == "true" or entry.foritem == true) then  
                local time = entry.date or "未知时间"  
                local item = entry.reason or "未知装备"  
                local player = ""  
                local points = entry.points or 0  
                
                -- 获取涉及的玩家（装备奖惩通常只有一个玩家）  
                for playerName, _ in pairs(entry.awarded) do  
                    player = playerName  
                    break  
                end  
                
                exportText = exportText .. time .. "," .. item .. "," .. player .. "," .. points .. "\n"  
            end  
        end  
    end  
    
    -- 导出文件  
    if ExportFile then  
        local success = ExportFile(fileName, exportText)  
        if success then  
            WebDKP_Print("活动数据已成功备份到 " .. fileName)  
        else  
            WebDKP_Print("错误：备份失败，请检查文件权限")  
        end  
    else  
        WebDKP_Print("错误：ExportFile函数不可用，无法备份数据")  
    end  
end

-- ================================  
-- 恢复数据功能  
-- ================================  
function WebDKP_RestoreData()  
    -- 从imports目录读取备份文件，支持带有日期后缀的文件  
    local currentDate = date("%Y-%m-%d")
    local fileNames = {
        "活动数据-" .. currentDate,
    }
    
    local importData = nil
    local usedFileName = nil
    
    -- 检查ImportFile函数是否可用  
    if ImportFile then  
        -- 尝试所有可能的文件名  
        for _, fileName in ipairs(fileNames) do
            local fileContent = ImportFile(fileName)
            if fileContent then
                importData = fileContent
                usedFileName = fileName
                break
            end
        end
        
        if importData then  
            if importData ~= "" then  
                WebDKP_Print("开始恢复活动数据...")  
                WebDKP_Print("已读取文件：" .. usedFileName)
                
                -- 检查importData类型，如果是字符串，需要解析
                if type(importData) == "string" then
                    -- 解析导入数据  
                    local lines = {}
                    -- 使用更可靠的方法分割字符串，处理各种换行符
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
                    
                    -- 处理不同类型的换行符
                    local normalizedData = string.gsub(importData, "\r\n", "\n")
                    normalizedData = string.gsub(normalizedData, "\r", "\n")
                    lines = splitString(normalizedData, "\n")
                    
                    local dkpRecords = {}
                    local lootRecords = {}
                    local currentSection = nil
                    
                    -- 用于检测备份文件内部重复记录的辅助表
                    local uniqueDkpRecords = {}
                    local uniqueLootRecords = {}
                    
                    for i, line in ipairs(lines) do
                        -- 跳过空行
                        if line ~= "" then
                            -- 检查是否是DKP奖惩部分标记
                            if string.find(line, "DKP奖惩") then
                                currentSection = "dkp"
                            -- 检查是否是装备奖惩部分标记
                            elseif string.find(line, "装备奖惩") then
                                currentSection = "loot"
                            -- 跳过表头行
                            elseif string.find(line, "时间,") then
                                -- 跳过表头
                            -- 解析DKP奖惩记录
                            elseif currentSection == "dkp" and string.sub(line, 1, 1) ~= "#" then
                                -- 解析DKP变化记录
                                -- 使用更可靠的CSV解析方式
                                local time, reason, points, players
                                local commaCount = 0
                                local startPos = 1
                                
                                -- 解析时间字段
                                local commaPos = string.find(line, ",", startPos)
                                if commaPos then
                                                time = string.sub(line, startPos, commaPos - 1)
                                                -- 去掉前后空格
                                                time = string.gsub(time, "^%s*", "")
                                                time = string.gsub(time, "%s*$", "")
                                                startPos = commaPos + 1
                                                
                                                -- 解析原因字段
                                                commaPos = string.find(line, ",", startPos)
                                                if commaPos then
                                                    reason = string.sub(line, startPos, commaPos - 1)
                                                    -- 去掉前后空格
                                                    reason = string.gsub(reason, "^%s*", "")
                                                    reason = string.gsub(reason, "%s*$", "")
                                                    startPos = commaPos + 1
                                                    
                                                    -- 解析点数字段
                                                    commaPos = string.find(line, ",", startPos)
                                                    if commaPos then
                                                        points = string.sub(line, startPos, commaPos - 1)
                                                        -- 去掉前后空格
                                                        points = string.gsub(points, "^%s*", "")
                                                        points = string.gsub(points, "%s*$", "")
                                                        -- 剩余部分都是玩家列表
                                                        players = string.sub(line, commaPos + 1)
                                                        -- 去掉前后空格
                                                        players = string.gsub(players, "^%s*", "")
                                                        players = string.gsub(players, "%s*$", "")
                                                        
                                                        if time and reason and points and players then
                                                            -- 创建玩家列表，用于生成唯一键
                                                            local playerList = {}
                                                            local playerStart = 1
                                                            local tempPlayers = players
                                                            
                                                            -- 解析玩家列表
                                                            while true do
                                                                local playerCommaPos = string.find(tempPlayers, ",", playerStart)
                                                                local player
                                                                if playerCommaPos then
                                                                    player = string.sub(tempPlayers, playerStart, playerCommaPos - 1)
                                                                    playerStart = playerCommaPos + 1
                                                                else
                                                                    player = string.sub(tempPlayers, playerStart)
                                                                end
                                                                
                                                                -- 去掉前后空格
                                                                player = string.gsub(player, "^%s*", "")
                                                                player = string.gsub(player, "%s*$", "")
                                                                
                                                                if player and player ~= "" then
                                                                    table.insert(playerList, player)
                                                                end
                                                                
                                                                if not playerCommaPos then
                                                                    break
                                                                end
                                                            end
                                                            
                                                            -- 对玩家列表排序，确保相同玩家集合生成相同的唯一键
                                                            table.sort(playerList)
                                                            local sortedPlayers = table.concat(playerList, ",")
                                                            
                                                            -- 生成唯一键，用于检测重复记录
                                                            local uniqueKey = time .. "_" .. reason .. "_" .. points .. "_" .. sortedPlayers
                                                            
                                                            -- 只添加不重复的记录
                                                            if not uniqueDkpRecords[uniqueKey] then
                                                                uniqueDkpRecords[uniqueKey] = true
                                                                table.insert(dkpRecords, {
                                                                    time = time,
                                                                    reason = reason,
                                                                    points = tonumber(points) or 0,
                                                                    players = players
                                                                })
                                                            end
                                                        end
                                                    end
                                                end
                                            end
                            -- 解析装备奖惩记录
                            elseif currentSection == "loot" and string.sub(line, 1, 1) ~= "#" then
                                -- 解析装备奖惩记录
                                -- 使用更可靠的CSV解析方式
                                local time, item, player, points
                                local commaCount = 0
                                local startPos = 1
                                
                                -- 解析时间字段
                                local commaPos = string.find(line, ",", startPos)
                                if commaPos then
                                    time = string.sub(line, startPos, commaPos - 1)
                                    -- 去掉前后空格
                                    time = string.gsub(time, "^%s*", "")
                                    time = string.gsub(time, "%s*$", "")
                                    startPos = commaPos + 1
                                    
                                    -- 解析装备字段
                                    commaPos = string.find(line, ",", startPos)
                                    if commaPos then
                                        item = string.sub(line, startPos, commaPos - 1)
                                        -- 去掉前后空格
                                        item = string.gsub(item, "^%s*", "")
                                        item = string.gsub(item, "%s*$", "")
                                        startPos = commaPos + 1
                                        
                                        -- 解析玩家字段
                                        commaPos = string.find(line, ",", startPos)
                                        if commaPos then
                                            player = string.sub(line, startPos, commaPos - 1)
                                            -- 去掉前后空格
                                            player = string.gsub(player, "^%s*", "")
                                            player = string.gsub(player, "%s*$", "")
                                            -- 剩余部分是点数
                                            points = string.sub(line, commaPos + 1)
                                            -- 去掉前后空格
                                            points = string.gsub(points, "^%s*", "")
                                            points = string.gsub(points, "%s*$", "")
                                            
                                            if time and item and player and points then
                                                -- 生成唯一键，用于检测重复记录
                                                local uniqueKey = time .. "_" .. item .. "_" .. player .. "_" .. points
                                                
                                                -- 只添加不重复的记录
                                                if not uniqueLootRecords[uniqueKey] then
                                                    uniqueLootRecords[uniqueKey] = true
                                                    table.insert(lootRecords, {
                                                        time = time,
                                                        item = item,
                                                        player = player,
                                                        points = tonumber(points) or 0
                                                    })
                                                end
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                    
                    -- 辅助函数：获取表的大小
                    local function getTableSize(tbl) 
                        local count = 0 
                        for _, _ in pairs(tbl) do 
                            count = count + 1 
                        end 
                        return count 
                    end 
                    
                    -- 显示恢复结果  
                    WebDKP_Print("解析完成，找到 " .. getTableSize(dkpRecords) .. " 条DKP变化记录")  
                    WebDKP_Print("解析完成，找到 " .. getTableSize(lootRecords) .. " 条装备奖惩记录")  
                    
                    -- 实际的恢复逻辑  
                    local restoredCount = 0 
                    local skippedCount = 0 
                    local tableid = WebDKP_GetTableid() 
                    
                    -- 辅助函数：检查DKP记录是否重复
                    local function isDuplicateDKPRecord(record, players)
                        if not WebDKP_Log then
                            return false
                        end
                        
                        -- 调试信息：启用调试模式，输出详细的比较信息
                        local debugMode = false
                        
                        -- 遍历所有现有记录进行比较
                        for entryKey, existingEntry in pairs(WebDKP_Log) do
                            -- 确保条件判断与备份数据的代码一致
                            if type(existingEntry) == "table" and not (existingEntry.foritem == "true" or existingEntry.foritem == true) then
                                -- 检查核心字段是否相同
                                local isSameDate = (existingEntry.date == record.time)
                                local isSameReason = (existingEntry.reason == record.reason)
                                local isSamePoints = (tonumber(existingEntry.points) == tonumber(record.points))
                                
                                -- 如果核心字段相同，进一步比较玩家列表
                                if isSameDate and isSameReason and isSamePoints then
                                    
                                    -- 检查玩家列表是否相同
                                    local isSamePlayers = true
                                    local existingPlayers = existingEntry.awarded or {}
                                    
                                    -- 创建玩家名字集合，用于快速比较
                                    local currentPlayersSet = {}
                                    local existingPlayersSet = {}
                                    
                                    -- 为当前记录的玩家创建集合，去除前后空格
                                    for player, _ in pairs(players) do
                                        local trimmedPlayer = string.gsub(player, "^%s*", "")
                                        trimmedPlayer = string.gsub(trimmedPlayer, "%s*$", "")
                                        currentPlayersSet[trimmedPlayer] = true
                                    end
                                    
                                    -- 为现有记录的玩家创建集合，去除前后空格
                                    for player, _ in pairs(existingPlayers) do
                                        local trimmedPlayer = string.gsub(player, "^%s*", "")
                                        trimmedPlayer = string.gsub(trimmedPlayer, "%s*$", "")
                                        existingPlayersSet[trimmedPlayer] = true
                                    end
                                    
                                    -- 检查当前记录的所有玩家是否都在现有记录中
                                    for player, _ in pairs(currentPlayersSet) do
                                        if not existingPlayersSet[player] then
                                            isSamePlayers = false
                                            if debugMode then
                                                WebDKP_Print("调试：玩家" .. player .. "不在现有记录中")
                                            end
                                            break
                                        end
                                    end
                                    
                                    -- 检查现有记录的所有玩家是否都在当前记录中
                                    if isSamePlayers then
                                        for player, _ in pairs(existingPlayersSet) do
                                            if not currentPlayersSet[player] then
                                                isSamePlayers = false
                                                if debugMode then
                                                    WebDKP_Print("调试：现有记录玩家" .. player .. "不在当前记录中")
                                                end
                                                break
                                            end
                                        end
                                    end
                                    
                                    -- 调试信息：玩家列表对比结果
                                    if debugMode then
                                        WebDKP_Print("调试：玩家列表对比结果:" .. tostring(isSamePlayers))
                                    end
                                    
                                    -- 如果玩家列表也相同，则是重复记录
                                    if isSamePlayers then
                                        if debugMode then
                                            WebDKP_Print("调试：发现重复记录，跳过")
                                            WebDKP_Print("调试：现有记录键:" .. tostring(entryKey))
                                        end
                                        return true
                                    end
                                end
                            end
                        end
                        
                        -- 调试：检查原因是否是"333测"，如果是则输出详细信息
                        if record.reason == "333测" then
                            WebDKP_Print("调试：发现333测记录，准备恢复")
                            WebDKP_Print("调试：记录时间:" .. record.time .. " 点数:" .. record.points)
                            WebDKP_Print("调试：玩家列表:" .. record.players)
                            
                            -- 输出现有记录中所有"333测"记录的信息
                            WebDKP_Print("调试：开始检查现有记录中的333测记录")
                            for entryKey, existingEntry in pairs(WebDKP_Log) do
                                if type(existingEntry) == "table" and existingEntry.reason == "333测" then
                                    WebDKP_Print("调试：现有333测记录 - 键:" .. tostring(entryKey) .. " 时间:" .. existingEntry.date .. " 点数:" .. existingEntry.points)
                                    
                                    -- 输出现有记录的玩家列表
                                    local existingPlayers = existingEntry.awarded or {}
                                    local existingPlayerList = ""
                                    for player, _ in pairs(existingPlayers) do
                                        if existingPlayerList ~= "" then
                                            existingPlayerList = existingPlayerList .. ","
                                        end
                                        existingPlayerList = existingPlayerList .. player
                                    end
                                    WebDKP_Print("调试：现有记录玩家列表:" .. existingPlayerList)
                                end
                            end
                        end
                        
                        return false
                    end
                    
                    -- 辅助函数：检查装备记录是否重复
                    local function isDuplicateLootRecord(record)
                        if not WebDKP_Log then
                            return false
                        end
                        
                        for _, existingEntry in pairs(WebDKP_Log) do
                            -- 确保条件判断与备份数据的代码一致
                            if type(existingEntry) == "table" and (existingEntry.foritem == "true" or existingEntry.foritem == true) then
                                -- 获取现有记录的玩家
                                local existingPlayer = ""
                                for player, _ in pairs(existingEntry.awarded or {}) do
                                    existingPlayer = player
                                    break
                                end
                                
                                -- 检查核心字段是否相同
                                if existingEntry.date == record.time and 
                                   existingEntry.reason == record.item and 
                                   existingPlayer == record.player and 
                                   tonumber(existingEntry.points) == tonumber(record.points) then
                                    return true
                                end
                            end
                        end
                        return false
                    end
                    
                    -- 恢复DKP奖惩记录
                    for _, record in ipairs(dkpRecords) do
                        -- 创建玩家列表
                        local players = {}
                        local playerList = record.players
                        local startPos = 1
                        
                        -- 手动解析逗号分隔的玩家列表
                        while true do
                            local commaPos = string.find(playerList, ",", startPos)
                            local player
                            if commaPos then
                                player = string.sub(playerList, startPos, commaPos - 1)
                                startPos = commaPos + 1
                            else
                                player = string.sub(playerList, startPos)
                            end
                            
                            -- 去掉前后空格
                            player = string.gsub(player, "^%s*", "")
                            player = string.gsub(player, "%s*$", "")
                            
                            if player and player ~= "" then
                                players[player] = true
                            end
                            
                            if not commaPos then
                                break
                            end
                        end
                        
                        -- 调试信息：启用调试模式，输出详细的比较信息
                        local debugMode = true
                        
                        if debugMode then
                            -- 打印要添加的记录信息
                            WebDKP_Print("\n=== 调试：准备恢复记录 ===")
                            WebDKP_Print("时间: " .. record.time)
                            WebDKP_Print("原因: " .. record.reason)
                            WebDKP_Print("点数: " .. record.points)
                            WebDKP_Print("玩家列表: " .. record.players)
                            
                            -- 打印已有的所有相关记录信息
                            WebDKP_Print("\n=== 调试：已有的相关记录 ===")
                            local foundRelated = false
                            for entryKey, existingEntry in pairs(WebDKP_Log) do
                                if type(existingEntry) == "table" and not (existingEntry.foritem == "true" or existingEntry.foritem == true) then
                                    -- 只打印原因和点数相同的记录
                                    if existingEntry.reason == record.reason and tonumber(existingEntry.points) == tonumber(record.points) then
                                        foundRelated = true
                                        WebDKP_Print("记录键: " .. tostring(entryKey))
                                        WebDKP_Print("  时间: " .. (existingEntry.date or "未知时间"))
                                        WebDKP_Print("  原因: " .. (existingEntry.reason or "未知原因"))
                                        WebDKP_Print("  点数: " .. (existingEntry.points or 0))
                                        
                                        -- 打印玩家列表
                                        local existingPlayerList = ""
                                        for player, _ in pairs(existingEntry.awarded or {}) do
                                            if existingPlayerList ~= "" then
                                                existingPlayerList = existingPlayerList .. ","
                                            end
                                            existingPlayerList = existingPlayerList .. player
                                        end
                                        WebDKP_Print("  玩家列表: " .. existingPlayerList)
                                    end
                                end
                            end
                            
                            if not foundRelated then
                                WebDKP_Print("没有找到相关记录")
                            end
                        end
                        
                        -- 检查是否是重复记录
                        if isDuplicateDKPRecord(record, players) then
                            skippedCount = skippedCount + 1
                            goto continue
                        end
                        
                        -- 创建DKP记录
                        local newLogEntry = {
                            ["reason"] = record.reason,
                            ["points"] = record.points,
                            ["awarded"] = players,
                            ["date"] = record.time,
                            ["foritem"] = "false",
                            ["uniqueId"] = "RESTORE_" .. time() .. "_" .. math.random(1000)
                        }
                        
                        -- 添加到日志
                        if not WebDKP_Log then
                            WebDKP_Log = {}
                        end
                        local key = "RESTORE_" .. time() .. "_" .. math.random(1000)
                        WebDKP_Log[key] = newLogEntry
                        
                        -- 更新玩家DKP分数
                        for playerName, _ in pairs(players) do
                            if not WebDKP_DkpTable[playerName] then
                                WebDKP_DkpTable[playerName] = {
                                    ["class"] = "未知",
                                    ["dkp" .. tableid] = 0,
                                    ["Selected"] = false,
                                    ["IsSub"] = false
                                }
                            end
                            local dkpField = "dkp_" .. tableid
                            WebDKP_DkpTable[playerName][dkpField] = (WebDKP_DkpTable[playerName][dkpField] or 0) + record.points
                        end
                        
                        restoredCount = restoredCount + 1
                        ::continue::
                    end
                    
                    -- 恢复装备奖惩记录
                    for _, record in ipairs(lootRecords) do
                        -- 检查是否是重复记录
                        if isDuplicateLootRecord(record) then
                            skippedCount = skippedCount + 1
                            goto continue_loot
                        end
                        
                        -- 创建玩家列表
                        local players = { [record.player] = true }
                        
                        -- 创建DKP记录
                        local newLogEntry = {
                            ["reason"] = record.item,
                            ["points"] = record.points,
                            ["awarded"] = players,
                            ["date"] = record.time,
                            ["foritem"] = "true",
                            ["uniqueId"] = "RESTORE_" .. time() .. "_" .. math.random(1000)
                        }
                        
                        -- 添加到日志
                        if not WebDKP_Log then
                            WebDKP_Log = {}
                        end
                        local key = "RESTORE_" .. time() .. "_" .. math.random(1000)
                        WebDKP_Log[key] = newLogEntry
                        
                        -- 更新玩家DKP分数
                        for playerName, _ in pairs(players) do
                            if not WebDKP_DkpTable[playerName] then
                                WebDKP_DkpTable[playerName] = {
                                    ["class"] = "未知",
                                    ["dkp" .. tableid] = 0,
                                    ["Selected"] = false,
                                    ["IsSub"] = false
                                }
                            end
                            local dkpField = "dkp_" .. tableid
                            WebDKP_DkpTable[playerName][dkpField] = (WebDKP_DkpTable[playerName][dkpField] or 0) + record.points
                        end
                        
                        restoredCount = restoredCount + 1
                        ::continue_loot::
                    end
                    
                    -- 保存数据
                    if WebDKP_SaveToDisk then
                        WebDKP_SaveToDisk()
                    end
                    
                    -- 刷新界面，确保所有相关UI元素都能正确更新
                    -- 1. 更新要显示的数据列表
                    if WebDKP_UpdateTableToShow then
                        WebDKP_UpdateTableToShow()
                    end
                    
                    -- 2. 更新表格显示
                    if WebDKP_UpdateTable then
                        WebDKP_UpdateTable()
                    end
                    
                    -- 3. 额外刷新，确保所有相关UI元素都能正确更新
                    -- 检查是否有其他刷新函数可用
                    if WebDKP_UpdateAll then
                        WebDKP_UpdateAll()
                    end
                    
                    -- 4. 检查是否有刷新滚动条的函数
                    if WebDKP_ScrollFrame_OnVerticalScroll then
                        WebDKP_ScrollFrame_OnVerticalScroll(WebDKP_ScrollFrame:GetVerticalScroll(), WebDKP_ScrollFrame:GetVerticalScrollRange())
                    end
                    
                    -- 5. 检查是否有刷新过滤器的函数
                    if WebDKP_FilterPlayers then
                        WebDKP_FilterPlayers()
                    end
                    
                    WebDKP_Print("成功恢复 " .. restoredCount .. " 条记录")  
                    if skippedCount > 0 then
                        WebDKP_Print("跳过了 " .. skippedCount .. " 条重复记录")  
                    end
                    WebDKP_Print("恢复数据功能已完成")  
                end
            else
                WebDKP_Print("错误：导入文件为空")  
            end  
        else  
            WebDKP_Print("错误：无法读取文件，请检查imports目录下是否存在活动数据相关文件")  
        end  
    else  
        WebDKP_Print("错误：ImportFile函数不可用，无法恢复数据")  
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