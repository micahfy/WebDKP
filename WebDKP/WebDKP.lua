------------------------------------------------------------------------
-- WEB DKP
------------------------------------------------------------------------
-- An addon to help manage the dkp for a guild. The addon provides a 
-- list of the dkp of all players as well as an interface to add / deduct dkp 
-- points. 
-- The addon generates a log file which can then be uploaded to a companion 
-- website at www.webdkp.com
--
--
-- HOW THIS ADDON IS ORGANIZED:
-- The addon is grouped into a series of files which hold code for certain
-- functions. 
-- 
-- WebDKP			Code to handle start / shutdown / registering events
--					and GUI event handlers. This is the main entry point
--					of the addon and directs events to the functionality
--					in the other files
--
-- Stub function to prevent errors when WebDKP_FinalTest() is called
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

function WebDKP_SaveToDisk()
    -- WoW 1.12 writes SavedVariables on ReloadUI/logout; keep this hook safe for frequent calls.
    if WebDKP_Options and WebDKP_Options["AutoBackupEnabled"] and WebDKP_BackupData then
        WebDKP_BackupData()
    end
end

-- 通过id查找表格名称的统一函数
function WebDKP_GetTableNameById(id)
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
    
    -- 数据文件内容格式：“类型,时间,分值,项目,玩家列表”
    -- 类型可以是: D (加分记录), L (装备记录)
    -- 玩家列表格式为: 名字:职业;名字:职业...
    local exportText = "类型,时间,分值,项目,玩家列表\n"
    
    if WebDKP_Log then  
        for key, entry in pairs(WebDKP_Log) do  
            if key ~= "Version" and type(entry) == "table" and entry.awarded then  
                local time = entry.date or "未知时间"  
                local reason = entry.reason or "未知原因"  
                local points = entry.points or 0
                
                -- 转义逗号，防止CSV格式错乱
                local cleanReason = string.gsub(reason, ",", " ")
                
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
                exportText = exportText .. line
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
    
    for i, line in ipairs(lines) do
        -- 跳过空行和表头
        if line ~= "" and i > 1 then
            local fields = splitString(line, ",")
            if table.getn(fields) >= 5 then
                local recordType = fields[1]
                local timeStr = fields[2]
                local points = tonumber(fields[3]) or 0
                local reason = fields[4]
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

-- DKP玩家创建功能 - 职业选择下拉菜单初始化
function WebDKP_CreatePlayerClassDropDown_Init()
    local dropdown = getglobal("WebDKP_FiltersFrameCreatePlayerFrameClassDropDown")
    if not dropdown then return end
    
    UIDropDownMenu_Initialize(dropdown, WebDKP_CreatePlayerClassDropDown_OnLoad)
    UIDropDownMenu_SetWidth(100)
    UIDropDownMenu_SetSelectedValue(dropdown, "战士")
end

-- DKP玩家创建功能 - 职业选择下拉菜单加载
function WebDKP_CreatePlayerClassDropDown_OnLoad()
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
        info.func = WebDKP_CreatePlayerClassDropDown_OnClick
        UIDropDownMenu_AddButton(info)
    end
end

-- DKP玩家创建功能 - 职业选择下拉菜单点击事件
function WebDKP_CreatePlayerClassDropDown_OnClick()
    local dropdown = getglobal("WebDKP_FiltersFrameCreatePlayerFrameClassDropDown")
    if dropdown then
        UIDropDownMenu_SetSelectedValue(dropdown, this.value)
    end
end

-- DKP玩家创建功能 - 添加玩家
function WebDKP_CreatePlayer()
	-- 获取输入框和下拉菜单
    local nameEditBox = getglobal("WebDKP_FiltersFrameCreatePlayerFramePlayerName")
    local classDropDown = getglobal("WebDKP_FiltersFrameCreatePlayerFrameClassDropDown")
    
    if not nameEditBox or not classDropDown then
        WebDKP_Print("错误：无法获取创建玩家的UI组件！")
        return
    end
    
	-- 获取输入值
    local name = nameEditBox:GetText()
    local class = UIDropDownMenu_GetSelectedValue(classDropDown)
    
	-- 验证输入
    if not name or name == "" then
        WebDKP_Print("错误：请输入玩家名字！")
        return
    end
    
    if not class or class == "" then
        WebDKP_Print("错误：请选择职业！")
        return
    end
    
	-- 使用/dkp tj命令的逻辑添加玩家，初始分默认0
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
        WebDKP_Print("错误：无效的职业！")
        return
    end
    
	-- 检查玩家是否已存在
    if WebDKP_DkpTable[name] then
        WebDKP_Print("警告：" .. name .. " 已存在于DKP列表中！")
        return
    end
    
	-- 添加新玩家到DKP表，存储中文职业名称
    WebDKP_DkpTable[name] = {
        ["class"] = class,
        ["dkp" .. WebDKP_GetTableid()] = initialDkp,
        ["Selected"] = false,
        ["IsSub"] = false
    }
    
	-- 更新显示表格
    WebDKP_UpdateTableToShow()
    WebDKP_UpdateTable()
    
	-- 清空输入框
    nameEditBox:SetText("")
    
    WebDKP_Print("成功添加新玩家：")
    WebDKP_Print("名字：" .. name)
    WebDKP_Print("职业：" .. class)
    WebDKP_Print("初始DKP：" .. initialDkp)
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
WebDKP_TierInterval = 50;   

-- Specify what filters are turned on and off. 1 = on, 0 = off
-- (Don't mess around with)
WebDKP_Filters = {
	["Druid"] = 1,
	["Hunter"] = 1,
	["Mage"] = 1,
	["Rogue"] = 1,
	["Shaman"] = 1,
	["Paladin"] = 1,
	["Priest"] = 1,
	["Warrior"] = 1,
	["Warlock"] = 1,
	["Group"] = 1,
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
--		["id"] = 1 (this is the tableid of the table on the webdkp site)
-- }
WebDKP_Tables = {};
selectedTableid = 1;


-- The dkp table that will be shown. This is filled programmatically
-- based on running through the big dkp table applying the selected filters
WebDKP_DkpTableToShow = {}; 

-- Keeps track of the current players in the group. This is filled programmatically
-- and is filled with Raid data if the player is in a raid, or party data if the
-- player is in a party. It is used to apply the 'Group' filter
WebDKP_PlayersInGroup = {};

-- 替补数据
WebDKP_SubData = {
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
WebDKP_SubAwardData = {
    captain = "",
    members = {},
    bossName = "",
    reason = "",
    points = 0
};

-- 初始化替补设置
function WebDKP_InitSubSettings()
	-- 确保数据结构存在
    if not WebDKP_Options then
        WebDKP_Options = {}
    end
    if not WebDKP_Options["SubSettings"] then
        WebDKP_Options["SubSettings"] = {
            captain = ""
        }
    end
    if not WebDKP_SubAwardData then
        WebDKP_SubAwardData = {
            captain = "",
            members = {},
            bossName = "",
            reason = "",
            points = 0
        }
    end
    
	-- 从设置加载替补队长信息
    local captain = WebDKP_Options["SubSettings"]["captain"] or ""
    WebDKP_SubAwardData.captain = captain
    
    WebDKP_UpdateCaptainLabel()
    
	-- 初始化WebDKP_SubData
    if not WebDKP_SubData then
        WebDKP_SubData = {
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

function WebDKP_UpdateCaptainLabel()
    local captain = WebDKP_SubAwardData and WebDKP_SubAwardData.captain or ""
    if WebDKP_AwardDKP_FrameSubCaptainLabel then
        if captain == "" then
            WebDKP_AwardDKP_FrameSubCaptainLabel:SetText("替补队长: 无")
        else
            WebDKP_AwardDKP_FrameSubCaptainLabel:SetText("替补队长: " .. captain)
        end
    end
end

-- 每日替补记录
WebDKP_DailySubRecords = {};

-- 当前团队成员缓存
WebDKP_CurrentRaidMembers = {};

-- Keeps track of the sorting options. 
-- Curr = current columen being sorted
-- Way = asc or desc order. 0 = desc. 1 = asc
WebDKP_LogSort = {
	["curr"] = 3,
	["way"] = 1 -- Desc
};

-- Additional user options
WebDKP_Options = {
	["AutofillEnabled"] = 1, 		-- auto fill data. 0 = disabled. 1 = enabled. 
	["AutofillThreshold"] = 3, 		-- What level of items should be picked up by auto fill. -1 = Gray, 4 = Orange
	["AutoAwardEnabled"] = 1, 		-- Whether dkp awards should be recorded automatically if all data can be auto filled (user is still prompted)
	["SubHalfPointsEnabled"] = false, -- Whether to award half points to substitutes
	["SubSameReasonEnabled"] = false, -- Whether substitutes use the same reason as raid
	["IncludeSubCaptain"] = false, -- Whether to include sub captain when awarding subs
	["SelectedTableId"] = 1, 		-- The last table that was being looked at
	["MiniMapButtonAngle"] = 1,
	["SilentMode"] = false,			-- 静默模式，关闭团队播报功能
		["RaidDkpReply"] = true,			-- 团队频道查DKP密语自动回复
	["SubSettings"] = {
		["captain"] = "",
		["useCheckIn"] = false
	}
}

-- User options that are syncronized with the website
WebDKP_WebOptions = {			
	["ZeroSumEnabled"] = 0,			-- Whether or not to use ZeroSum DKP settings
	["MapValidationEnabled"] = 1,		-- Whether or not to enable map validation for DKP awards
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

function WebDKP_Contain(value, table)
    if not table then return false end
    for _, v in ipairs(table) do
        if v == value then
            return true
        end
    end
    return false
end

function WebDKP_TrimText(text)
	if text == nil then return "" end
	text = tostring(text)
	text = string.gsub(text, "^%s*", "")
	text = string.gsub(text, "%s*$", "")
	return text
end

function WebDKP_OnLoad()
	-- 确保有正确的frame引用
	local frame =  WebDKP_Frame
	if not frame then
		WebDKP_Print("错误：无法获取WebDKP主框架引用")
		return
	end
	
	-- 衰减功能已移除
	-- WebDKP_Decay_OnLoad();
	
	-- 初始化替补设置，从WebDKP_Options加载
	if not WebDKP_Options then
		WebDKP_Options = {}
	end
	
	-- 确保WebDKP_Options中有SubSettings表
	if not WebDKP_Options["SubSettings"] then
		WebDKP_Options["SubSettings"] = {}
	end
	
	-- 初始化WebDKP_SubAwardData
	if not WebDKP_SubAwardData then
		WebDKP_SubAwardData = {
			captain = "",
			members = {},
			bossName = "",
			reason = "",
			points = 0
		}
	end
	
	-- 确保所有字段都存在
	if not WebDKP_SubAwardData.captain then WebDKP_SubAwardData.captain = "" end
	if not WebDKP_SubAwardData.members then WebDKP_SubAwardData.members = {} end
	if not WebDKP_SubAwardData.bossName then WebDKP_SubAwardData.bossName = "" end
	if not WebDKP_SubAwardData.reason then WebDKP_SubAwardData.reason = "" end
	if not WebDKP_SubAwardData.points then WebDKP_SubAwardData.points = 0 end
	
	-- 从设置加载替补队长信息
	WebDKP_SubAwardData.captain = WebDKP_Options["SubSettings"].captain or ""
	
	-- 初始化WebDKP_SubData
	if not WebDKP_SubData then
		WebDKP_SubData = {
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
	frame:RegisterEvent("ADDON_ACTION_FORBIDDEN");
	frame:RegisterEvent("UI_ERROR_MESSAGE");
	frame:RegisterEvent("LOOT_OPENED");

	-- 检查是否安装了SuperWOW
	if SUPERWOW_STRING then
		-- 如果安装了SuperWOW，注册RAW_COMBATLOG事件
		frame:RegisterEvent("RAW_COMBATLOG");
	else
		-- 否则使用原来的方式
		frame:RegisterEvent("CHAT_MSG_COMBAT_HOSTILE_DEATH");
	end
	frame:RegisterEvent("CHAT_MSG_COMBAT_FACTION_CHANGE");
	frame:RegisterEvent("CHAT_MSG_COMBAT_HONOR_GAIN");
	frame:RegisterEvent("CHAT_MSG_COMBAT_MISC_INFO");
	frame:RegisterEvent("CHAT_MSG_COMBAT_XP_GAIN");
	frame:RegisterEvent("CHAT_MSG_ADDON");
    
	-- ===== 右键菜单注册 =====
	-- 使用标准的UIDropDownMenu系统，不hook系统函数以避免冲突

	WebDKP_OnEnable();
	
end

-- 定时器函数，用于延迟执行某个函数
function WebDKP_ScheduleTimer(func, delay)
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
SLASH_WEBDKP1 = "/webdkp"
SLASH_WEBDKP2 = "/dkp"
SlashCmdList["WEBDKP"] = WebDKP_SlashCmdHandler



-- ================================
-- Called when the addon is enabled. 
-- Takes care of basic startup tasks: hide certain forms, 
-- get the people currently in the group, register for events, 
-- etc. 
-- ================================
function WebDKP_OnEnable()
	WebDKP_Frame:Hide();
	
	if WebDKP_AwardDKP_Frame then WebDKP_AwardDKP_Frame:Show() end
	if WebDKP_LootListFrame then WebDKP_LootListFrame:Hide() end
	if WebDKP_Options_Frame then WebDKP_Options_Frame:Hide() end
	
	if WebDKP_FiltersFrame then WebDKP_FiltersFrame:Hide() end
	if WebDKP_AwardAllDKP_Frame then WebDKP_AwardAllDKP_Frame:Hide() end
	if WebDKP_AwardItem_Frame then WebDKP_AwardItem_Frame:Hide() end
	
	if WebDKP_Personal_Frame then WebDKP_Personal_Frame:Hide() end
	
	WebDKP_Options_Init();
	WebDKP_UpdateSingleAdjustLabel();
	
	WebDKP_UpdatePlayersInGroup();
	WebDKP_UpdateTableToShow();
	
	-- 确保WebDKP_Options表存在
	if not WebDKP_Options then
		WebDKP_Options = {}
	end
	
	-- 初始化静默模式设置
	if WebDKP_Options["SilentMode"] == nil then
		WebDKP_Options["SilentMode"] = false
	end
	
	-- place a hook on the chat frame so we can filter out our whispers
	WebDKP_Register_WhisperHook();
	
		--hooksecurefunc("SetItemRef",WebDKP_ItemChatClick);

-- 为游戏原生玩家右键菜单添加DKP选项
WebDKP_RegisterPopupMenu = function()
	-- 确保UnitPopupButtons存在
    if not UnitPopupButtons then return end
    
	-- 检查DKP扣分按钮是否已存在
    local buttonExists = false
    for i, button in ipairs(UnitPopupButtons) do
        if button == "WEBDKP_DEDUCT" then
            buttonExists = true
            break
        end
    end
    
	-- 如果不存在，则添加按钮
    if not buttonExists then
        table.insert(UnitPopupButtons, "WEBDKP_DEDUCT")
        table.insert(UnitPopupButtons, "WEBDKP_AWARD")
    end
    
	-- 设置按钮属性
    UnitPopupButtons["WEBDKP_DEDUCT"] = {
        text = "DKP扣分",
        dist = 0,
    }
    
    UnitPopupButtons["WEBDKP_AWARD"] = {
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
                if button == "WEBDKP_DEDUCT" then deductExists = true end
                if button == "WEBDKP_AWARD" then awardExists = true end
            end
            -- 在分隔线后添加我们的选项
            for i, button in ipairs(UnitPopupMenus[menu]) do
                if button == "CANCEL" then
                    if not deductExists then
                        table.insert(UnitPopupMenus[menu], i, "WEBDKP_DEDUCT")
                    end
                    if not awardExists then
                        table.insert(UnitPopupMenus[menu], i+1, "WEBDKP_AWARD")
                    end
                    break
                end
        end
    end
    
	-- 保存原始的UnitPopup_OnClick函数
    if not WebDKP_OriginalUnitPopup_OnClick then
        WebDKP_OriginalUnitPopup_OnClick = UnitPopup_OnClick
        UnitPopup_OnClick = WebDKP_UnitPopup_OnClick
    end
end
end
-- 处理我们添加的右键菜单项点击
WebDKP_UnitPopup_OnClick = function()
    if UIDROPDOWNMENU_MENU_VALUE == "WEBDKP_DEDUCT" then
        local unit = UIDROPDOWNMENU_INIT_MENU.unit
        local name = unit and UnitName(unit) or UIDROPDOWNMENU_INIT_MENU.name
        if name then
            WebDKP_HandleDeduction(name)
        end
        return
    elseif UIDROPDOWNMENU_MENU_VALUE == "WEBDKP_AWARD" then
        local unit = UIDROPDOWNMENU_INIT_MENU.unit
        local name = unit and UnitName(unit) or UIDROPDOWNMENU_INIT_MENU.name
        if name then
            WebDKP_HandleAward(name)
        end
        return
    end
    
	-- 调用原始函数处理其他选项
    WebDKP_OriginalUnitPopup_OnClick()
end

-- 在插件加载时注册右键菜单
WebDKP_RegisterPopupMenu();
  	if ( SetItemRef ~= WebDKP_ItemChatClick ) then
		-- place a hook on item shift+clicks so we can get item details
		WebDKP_ItemChatClick_Original = SetItemRef;
		SetItemRef = WebDKP_ItemChatClick;
  	end
 	

end

-- ================================
-- Invoked when we recieve one of the requested events. 
-- Directs that event to the appropriate part of the addon
-- ================================
function WebDKP_OnEvent()
	if(event=="CHAT_MSG_WHISPER") then
		WebDKP_CHAT_MSG_WHISPER();
	elseif(event=="CHAT_MSG_PARTY" or event=="CHAT_MSG_RAID" or event=="CHAT_MSG_RAID_LEADER" or event=="CHAT_MSG_RAID_WARNING") then
		WebDKP_CHAT_MSG_PARTY_RAID();
	elseif(event=="PARTY_MEMBERS_CHANGED") then
		WebDKP_PARTY_MEMBERS_CHANGED();
	elseif(event=="RAID_ROSTER_UPDATE") then
		WebDKP_RAID_ROSTER_UPDATE();
	elseif(event=="ADDON_LOADED") then
		WebDKP_ADDON_LOADED();
	elseif(event=="CHAT_MSG_LOOT") then
		WebDKP_Loot_Taken();
	elseif(event=="ADDON_ACTION_FORBIDDEN") then
		WebDKP_Print(arg1.."  "..arg2);
	elseif(event=="UI_ERROR_MESSAGE") then
		WebDKP_HandleUIError();
	elseif(event=="LOOT_OPENED") then
		WebDKP_LOOT_OPENED();
	elseif(event=="CHAT_MSG_ADDON") then
		WebDKP_HandleAddonMessage(arg1, arg2, arg3, arg4);
	elseif(event=="RAW_COMBATLOG") then
		-- SuperWOW RAW_COMBATLOG事件处理
		local eventType = arg1
		local eventMsg = arg2
		
		if eventType == "CHAT_MSG_COMBAT_HOSTILE_DEATH" then
			-- 从消息中提取GUID，格式为："0xF13000001E0139A0死亡了。"
			local guid = string.match(eventMsg, "^(0x[0-9A-F]+)")
			if guid then
				-- 验证目标是否是worldboss
				local classification = UnitClassification(guid)
				local unitName = UnitName(guid)
				
				-- 使用两种方式验证：classification和名称模式
				if (classification == "worldboss" or WebDKP_IsBossByNamePattern(unitName)) and unitName then
					-- 调用原有处理函数，传递BOSS名称
					WebDKP_HandleCombatHostileDeath(unitName .. "死亡了。")
				end
			end
		end
	elseif(event=="CHAT_MSG_COMBAT_HOSTILE_DEATH") then   
		-- 兼容原有方式，当没有安装SuperWOW时使用
		WebDKP_HandleCombatHostileDeath(arg1);
	end
end

-- 处理插件间通信消息
function WebDKP_HandleAddonMessage(prefix, message, channel, sender)
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
			-- DEFAULT_CHAT_FRAME:AddMessage("[WebDKP] 收到查询，我是替补队长，正在发送团队成员列表", 0, 1, 0)
			WebDKP_SendSubMemberList(sender)
			-- 如果对方设置了响应标志，也标记自己收到了查询
			if WebDKP_SubAwardData then
				WebDKP_SubAwardData.receivedResponse = true
			end
		else
			-- 不是发给自己的消息，忽略
			-- DEFAULT_CHAT_FRAME:AddMessage("[WebDKP] 收到查询，但不是发给我的", 0, 1, 0)
		end
	-- AMB_TBFS 已改用密语发送，此处保留以兼容旧版
	end
end

-- 发送替补队员名单给请求者
function WebDKP_SendSubMemberList(toPlayer)
	-- 详细调试信息
	-- WebDKP_Print("=== WebDKP_SendSubMemberList 开始 ===")
	-- WebDKP_Print("目标玩家: " .. toPlayer)
	-- DEFAULT_CHAT_FRAME:AddMessage("[WebDKP] 开始发送替补队员列表给: " .. toPlayer, 0, 1, 0)
	
	-- 确保toPlayer不为空
	if not toPlayer or toPlayer == "" then
		WebDKP_Print("错误: 目标玩家名为空")
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
		WebDKP_SendWhisper(toPlayer, "SUB_EMPTY")
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
			WebDKP_SendWhisper(toPlayer, "SUB:" .. batches[i])
		end
		WebDKP_SendWhisper(toPlayer, "SUB_COMPLETE:" .. memberCount)
	end

	DEFAULT_CHAT_FRAME:AddMessage("[WebDKP] 已发送 " .. memberCount .. " 名替补队员信息", 0, 1, 0)

	if not WebDKP_SubAwardData then
		WebDKP_SubAwardData = {}
	end
	WebDKP_SubAwardData.receivedResponse = true

	return true
end
-- 解析密语发来的替补数据
function WebDKP_HandleSubWhisperData(fromPlayer, message)
	if not message then return end

	-- 数据消息: WebDKP: SUB:张三:Warrior;李四:Mage
	local _, _, data = string.find(message, "^WebDKP: SUB:(.+)$")
	if data then
		for entry in string.gfind(data, "[^;]+") do
			local _, _, name, class = string.find(entry, "^([^:]+):([^:]+)$")
			if name then
				WebDKP_ReceiveSubMember(fromPlayer, name .. ":" .. class .. ":" .. fromPlayer)
			else
				WebDKP_ReceiveSubMember(fromPlayer, entry .. ":" .. fromPlayer)
			end
		end
		return
	end

	-- 完成消息: WebDKP: SUB_COMPLETE:5
	local _, _, count = string.find(message, "^WebDKP: SUB_COMPLETE:(.+)$")
	if count then
		WebDKP_ReceiveSubMember(fromPlayer, "COMPLETE:" .. UnitName("player") .. ":" .. count)
		return
	end

	-- 空消息: WebDKP: SUB_EMPTY
	if string.find(message, "^WebDKP: SUB_EMPTY$") then
		if WebDKP_SubAwardData then
			WebDKP_SubAwardData.receivedResponse = true
		end
		return
	end
end


-- 接收替补队员信息
function WebDKP_ReceiveSubMember(fromPlayer, memberName)
	-- 检查是否是完成通知消息
	if string.find(memberName, "^COMPLETE:") then
		local _, _, target, count = string.find(memberName, "^COMPLETE:(.+):(.+)")
		if target and count then
			local captainName = fromPlayer or ""
			if WebDKP_SubAwardData and WebDKP_SubAwardData.captain then
				if string.lower(fromPlayer) == string.lower(WebDKP_SubAwardData.captain) then
					captainName = WebDKP_SubAwardData.captain
				end
			end

			local memberTable = nil
			if WebDKP_PendingSubMembers then
				memberTable = WebDKP_PendingSubMembers[captainName]
				if not memberTable then
					memberTable = WebDKP_PendingSubMembers[string.lower(captainName)]
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
			if WebDKP_SubAwardData then
				reason = WebDKP_SubAwardData.reason or ""
				points = WebDKP_SubAwardData.points or 0
			end
			if WebDKP_AwardDKP_FrameSubReason then
				local reasonText = WebDKP_AwardDKP_FrameSubReason:GetText() or ""
				if reasonText ~= "" then
					reason = reasonText
				end
			end
			if WebDKP_AwardDKP_FrameSubPoints then
				local pointsText = WebDKP_AwardDKP_FrameSubPoints:GetText() or ""
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

			local message = "[WebDKP] " .. detailMessage
			DEFAULT_CHAT_FRAME:AddMessage(message, 0, 1, 0)
		end
		
		-- 设置接收响应标志
		if WebDKP_SubAwardData then
			WebDKP_SubAwardData.receivedResponse = true
		end
		return
	end
	
	-- 检查是否是无成员消息
	if string.find(memberName, "^NO_MEMBERS:") then
		if WebDKP_SubAwardData then
			WebDKP_SubAwardData.receivedResponse = true
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
	if receivedClass and WebDKP_NormalizeClassName then
		receivedClass = WebDKP_NormalizeClassName(receivedClass)
	end
	
	-- 检查是否是替补队长自己，如果是则不记录
	local isCaptainSelf = false
	if WebDKP_SubAwardData and WebDKP_SubAwardData.captain then
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
    if not WebDKP_PendingSubMembers then
        WebDKP_PendingSubMembers = {}
    end
	
	-- 查找正确的队长名字键（考虑大小写）
	local targetCaptain = fromPlayer
	local captainMatched = false
	
	if WebDKP_SubAwardData and WebDKP_SubAwardData.captain then
		local lowerFromPlayer = string.lower(fromPlayer)
		local lowerTargetCaptain = string.lower(WebDKP_SubAwardData.captain)
		
		if lowerFromPlayer == lowerTargetCaptain then
			-- 如果大小写不同但名字相同，使用目标队长的名字作为键
			targetCaptain = WebDKP_SubAwardData.captain
			captainMatched = true
		end
	end
	
	-- 如果没有匹配到目标队长，尝试遍历现有的队长列表进行模糊匹配
	if not captainMatched and WebDKP_PendingSubMembers then
		local lowerFromPlayer = string.lower(fromPlayer)
		for existingCaptain, _ in pairs(WebDKP_PendingSubMembers) do
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
	if not WebDKP_PendingSubMembers[targetCaptain] then
		WebDKP_PendingSubMembers[targetCaptain] = {}
	end
	
	-- 同时在小写版本下也记录，确保后续查找能成功
	if not WebDKP_PendingSubMembers[lowerTargetCaptain] then
		WebDKP_PendingSubMembers[lowerTargetCaptain] = {}
	end
	
	-- 存储队员信息到两个版本的队长键下
	local existingEntry = WebDKP_PendingSubMembers[targetCaptain][realPlayerName]
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

	WebDKP_PendingSubMembers[targetCaptain][realPlayerName] = entry
	WebDKP_PendingSubMembers[lowerTargetCaptain][realPlayerName] = entry
    
	-- 设置响应标志，通知定时器已收到信息
	if WebDKP_SubAwardData then
		WebDKP_SubAwardData.receivedResponse = true
	end
end

-- ================================
-- Invoked when addon finishes loading data from the saved variables file. 
-- Should parse the players options and update the gui.
-- ================================
function WebDKP_ADDON_LOADED()
	if( WebDKP_DkpTable == nil) then
		WebDKP_DkpTable = {};
	end
	
	-- 初始化每日替补记录变量
	if( WebDKP_DailySubRecords == nil) then
		WebDKP_DailySubRecords = {};
	end
	
	-- 确保WebDKP_Options表存在
	if not WebDKP_Options then
		WebDKP_Options = {}
	end
	
	--load up the last loot table that was being viewed
	WebDKP_Frame.selectedTableid = WebDKP_Options["SelectedTableId"];
	--WebDKP_Options_Autofill_DropDown_Init();
	
	-- load the options from saved variables and update the settings on the 
	if ( WebDKP_Options["AutofillEnabled"] == 1 ) then
		if WebDKP_Options_FrameToggleAutofill then
			WebDKP_Options_FrameToggleAutofill:SetChecked(1);
		end
		if WebDKP_Options_FrameAutofillDropDown then
			WebDKP_Options_FrameAutofillDropDown:Show();
		end
		if WebDKP_Options_FrameToggleAutoAward then
			WebDKP_Options_FrameToggleAutoAward:Show();
		end
	else
		if WebDKP_Options_FrameToggleAutofill then
			WebDKP_Options_FrameToggleAutofill:SetChecked(0);
		end
		if WebDKP_Options_FrameAutofillDropDown then
			WebDKP_Options_FrameAutofillDropDown:Hide();
		end
		if WebDKP_Options_FrameToggleAutoAward then
			WebDKP_Options_FrameToggleAutoAward:Hide();
		end
	end

	if WebDKP_Options_FrameToggleAutoAward then
		WebDKP_Options_FrameToggleAutoAward:SetChecked(WebDKP_Options["AutoAwardEnabled"]);
	end
	if WebDKP_Options_FrameToggleZeroSum then
		WebDKP_Options_FrameToggleZeroSum:SetChecked(WebDKP_WebOptions["ZeroSumEnabled"]);
	end
	
	
	WebDKP_UpdateTableToShow(); --update who is in the table
	WebDKP_UpdateTable();       --update the gui
	
	-- set the mini map position
	WebDKP_MinimapButton_SetPositionAngle(WebDKP_Options["MiniMapButtonAngle"]);
	
	-- Initialize loot list functionality
	WebDKP_DebugCheckLootList();
	
	-- 初始化替补设置
	WebDKP_InitSubSettings();
	
	-- 快捷浮窗显示/隐藏（仅RAID且勾选开启时显示）
	if WebDKP_QuickFloat_UpdateVisibility then
		WebDKP_QuickFloat_UpdateVisibility()
	end
end





-- ================================
-- Called on shutdown. Does nothing
-- ================================
function WebDKP_OnDisable()
    
end


---------------------------------------------------
-- EVENT HANDLERS (Party changed / gui toggled / etc.)
---------------------------------------------------

-- ================================
-- Called by slash command. Toggles gui. 
-- ================================
function WebDKP_ToggleGUI()
	-- self:Print("Should toggle gui now...")
	-- WebDKP_Refresh()
	if ( WebDKP_Frame:IsShown() ) then
		WebDKP_Frame:Hide();
	else
		WebDKP_Frame:Show();	
		WebDKP_Tables_DropDown_OnLoad();
		WebDKP_Options_Autofill_DropDown_OnLoad();
		WebDKP_Options_Autofill_DropDown_Init();
	end
	
	-- WebDKP_Bid_ToggleUI();
	
end



-- ================================
-- Handles the master loot list being opened 
-- ================================
function WebDKP_OPEN_MASTER_LOOT_LIST()
    
end

-- ================================
-- 处理打开尸体事件
-- ================================
function WebDKP_LOOT_OPENED()
	-- 检查是否有自动分配任务正在进行
	if WebDKP_AutoLootData.isAssigning and GetNumLootItems() > 0 then
		-- 有可分配物品了，尝试自动分配
		if WebDKP_AutoLootData.frame then
			WebDKP_AutoLootData.frame.statusText:SetText("正在分配 "..WebDKP_AutoLootData.currentItem.." 给 "..WebDKP_AutoLootData.currentPlayer);
		end
		WebDKP_TryAssignLoot();
	end
end

-- ================================
-- Called when the party / raid configuration changes. 
-- Causes the list of current group memebers to be refreshed
-- so that filters will be ok
-- ================================
function WebDKP_PARTY_MEMBERS_CHANGED()
	-- self:Print("Party / Raid change");
	WebDKP_UpdatePlayersInGroup();
	WebDKP_UpdateTableToShow();
	WebDKP_UpdateTable();
	if WebDKP_QuickFloat_UpdateVisibility then
		WebDKP_QuickFloat_UpdateVisibility()
	end
end
function WebDKP_RAID_ROSTER_UPDATE()
	-- self:Print("Party / Raid change");
	WebDKP_UpdatePlayersInGroup();
	WebDKP_UpdateTableToShow();
	WebDKP_UpdateTable();
	if WebDKP_QuickFloat_UpdateVisibility then
		WebDKP_QuickFloat_UpdateVisibility()
	end
end

-- ================================
-- Handles an incoming whisper. Directs it to the modules
-- who are interested in it. 
-- ================================
function WebDKP_CHAT_MSG_WHISPER()
	WebDKP_WhisperDKP_Event();
	WebDKP_Bid_Event();
	-- 获取消息发送者名称(arg2)和消息内容(arg1)
	local name = arg2;
	local message = arg1;
	WebDKP_HandleWhisperTB(name, message);
	WebDKP_HandleSubWhisperData(name, message);
end

-- ================================
-- Event handler for all party and raid
-- chat messages. 
-- ================================
function WebDKP_CHAT_MSG_PARTY_RAID()
	WebDKP_Bid_Event();
	WebDKP_RaidDkpQuery();
end

-- 团队/小队频道查 DKP 自动回复
function WebDKP_RaidDkpQuery()
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

	local tableid = WebDKP_GetTableid()
	if not WebDKP_DkpTable[name] then return end

	local dkp = WebDKP_DkpTable[name]["dkp_"..tableid]
	if dkp == nil then dkp = 0 end
	WebDKP_SendWhisper(name, "目前你的DKP为：  " .. dkp)
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
function WebDKP_Refresh()
	WebDKP_UpdatePlayersInGroup();
	WebDKP_UpdateTableToShow();
	WebDKP_UpdateTable();
end

-- ================================
-- Called when a player clicks on different tabs. 
-- Causes certain frames to be hidden and the appropriate
-- frame to be displayed
-- ================================
-- In WoW 1.12 Lua 5.0, use 'this' instead of function parameters
function WebDKP_Tab_OnClick()
	local button = this
	if not button then
		WebDKP_Print("错误：无法获取按钮引用")
		return
	end
	
	-- 隐藏所有右侧框架
	if WebDKP_AwardDKP_Frame then WebDKP_AwardDKP_Frame:Hide() end
	if WebDKP_LootListFrame then WebDKP_LootListFrame:Hide() end
	if WebDKP_Options_Frame then WebDKP_Options_Frame:Hide() end
	
	-- 确保隐藏遗留的框架
	if WebDKP_FiltersFrame then WebDKP_FiltersFrame:Hide() end
	if WebDKP_AwardAllDKP_Frame then WebDKP_AwardAllDKP_Frame:Hide() end
	if WebDKP_AwardItem_Frame then WebDKP_AwardItem_Frame:Hide() end
	
	if WebDKP_Personal_Frame then WebDKP_Personal_Frame:Hide() end

	-- 数据列表为全宽模式：进入时隐藏左侧名单操作区，离开时恢复
	local WebDKP_sideEls = { "WebDKP_SingleAdjustFrame", "WebDKP_FrameSelectAll", "WebDKP_FrameDeselectAll", "WebDKP_FrameSaveLog", "WebDKP_FrameRefresh", "WebDKP_NameSearchBox", "WebDKP_SearchLabel", "WebDKP_FrameModeRaid", "WebDKP_FrameModeSub", "WebDKP_FrameSubRefresh" }
	local WebDKP_hideSide = ( button:GetID() == 2 )
	for _, elName in ipairs(WebDKP_sideEls) do
		local el = getglobal(elName)
		if el then
			if WebDKP_hideSide then el:Hide() else el:Show() end
		end
	end
	
	if ( button:GetID() == 1 ) then
		if WebDKP_AwardDKP_Frame then WebDKP_AwardDKP_Frame:Show() end
		WebDKP_UpdateCaptainLabel()
	elseif ( button:GetID() == 2 ) then
		-- 确保已创建历史记录面板
		if not WebDKP_LootListFrame then
			WebDKP_CreateLootListFrame()
		end
		if WebDKP_LootListFrame then WebDKP_LootListFrame:Show() end
		WebDKP_UpdateLootList()
	elseif ( button:GetID() == 3 ) then
		if WebDKP_Options_Frame then WebDKP_Options_Frame:Show() end
		WebDKP_Options_Init()
	elseif ( button:GetID() == 5 ) then
		-- Tab5: 过滤/管理 - 显示 FiltersFrame (职业过滤、创建玩家、备份恢复)
		if WebDKP_FiltersFrame then WebDKP_FiltersFrame:Show() end
	end
	
	PlaySound("igCharacterInfoTab");
	
	-- 刷新左侧列表
	WebDKP_UpdateTableToShow()
	WebDKP_UpdateTable()
end

-- ================================
-- Called when a player clicks on a column header on the table
-- Changes the sorting options / asc&desc. 
-- Causes the table display to be refreshed afterwards
-- to player instantly sees changes
-- ================================
function WebDPK2_SortBy(id)
	if ( WebDKP_LogSort["curr"] == id ) then
		WebDKP_LogSort["way"] = abs(WebDKP_LogSort["way"]-1);
	else
		WebDKP_LogSort["curr"] = id;
		if( id == 1) then
			WebDKP_LogSort["way"] = 0;
		elseif ( id == 2 ) then
			WebDKP_LogSort["way"] = 0;
		elseif ( id == 3 ) then
			WebDKP_LogSort["way"] = 1; --columns with numbers need to be sorted different first in order to get DESC right
		else
			WebDKP_LogSort["way"] = 1; --columns with numbers need to be sorted different first in order to get DESC right
		end
		
	end
	-- update table so we can see sorting changes
	WebDKP_UpdateTable();
end

-- ================================
-- Called when the user clicks on a filter checkbox. 
-- Changes the filter setting and updates table
-- ================================
function WebDKP_ToggleFilter(filterName)
	WebDKP_Filters[filterName] = abs(WebDKP_Filters[filterName]-1);
	WebDKP_UpdateTableToShow();
	WebDKP_UpdateTable();
	

end

-- ================================
-- Called when user clicks on 'check all'
-- Sets all filters to on and updates table display
-- ================================
function WebDKP_CheckAllFilters()
	WebDKP_SetFilterState("Druid",1);
	WebDKP_SetFilterState("Hunter",1);
	WebDKP_SetFilterState("Mage",1);
	WebDKP_SetFilterState("Rogue",1);
	WebDKP_SetFilterState("Shaman",1);
	WebDKP_SetFilterState("Paladin",1);
	WebDKP_SetFilterState("Priest",1);
	WebDKP_SetFilterState("Warrior",1);
	WebDKP_SetFilterState("Warlock",1);
	WebDKP_UpdateTableToShow();
	WebDKP_UpdateTable();
end

-- ================================
-- Called when user clicks on 'uncheck all'
-- Sets all filters to off and updates table display
-- ================================
function WebDKP_UncheckAllFilters()
	WebDKP_SetFilterState("Druid",0);
	WebDKP_SetFilterState("Hunter",0);
	WebDKP_SetFilterState("Mage",0);
	WebDKP_SetFilterState("Rogue",0);
	WebDKP_SetFilterState("Shaman",0);
	WebDKP_SetFilterState("Paladin",0);
	WebDKP_SetFilterState("Priest",0);
	WebDKP_SetFilterState("Warrior",0);
	WebDKP_SetFilterState("Warlock",0);
	WebDKP_UpdateTableToShow();
	WebDKP_UpdateTable();
end

-- ================================
-- Small helper method for filters - updates
-- checkbox state and updates filter setting in data structure
-- ================================
function WebDKP_SetFilterState(filter,newState)
	local checkBox = getglobal("WebDKP_FiltersFrameClass"..filter);
	checkBox:SetChecked(newState);
	WebDKP_Filters[filter] = newState;
end

-- ================================
-- Called when mouse goes over a dkp line entry. 
-- If that player is not selected causes that row
-- to become 'highlighted'
-- ================================
function WebDKP_HandleMouseOver()
	local frame = arg1 or this
	if not frame then
		return
	end
	local playerName = getglobal(frame:GetName().."Name"):GetText();
	if ( not playerName ) then
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
function WebDKP_HandleMouseLeave()
	local frame = this
	if not frame then
		return
	end
	local playerName = getglobal(frame:GetName().."Name"):GetText();
	if ( not playerName ) then
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
function WebDKP_SelectPlayerToggle()
	-- 检查是否是右键点击
    if arg1 == "RightButton" then
        -- 获取玩家名称
        local playerName = getglobal(this:GetName().."Name"):GetText();
        
        -- 创建右键菜单
        WebDKP_PlayerRightClickMenu_Initialize(playerName, this);
        ToggleDropDownMenu(1, nil, WebDKP_PlayerRightClickMenu, "cursor", 0, 0);
        return;
    end
    
	-- 左键点击的单选逻辑
	local playerName = getglobal(this:GetName().."Name"):GetText();
	local wasSelected = WebDKP_DkpTable[playerName]["Selected"];
	
	
	if wasSelected then
		WebDKP_DkpTable[playerName]["Selected"] = false;
		WebDKP_Frame.selectedPlayer = nil;
	else
		WebDKP_DkpTable[playerName]["Selected"] = true;
		WebDKP_Frame.selectedPlayer = playerName;
	end
	
	-- 更新快速调分面板上的玩家名字标签
	WebDKP_UpdateSingleAdjustLabel();
	
	-- 更新表格以重绘背景
	WebDKP_UpdateTable();
end

-- ================================  
-- 玩家右键菜单初始化函数  
-- ================================
function WebDKP_PlayerRightClickMenu_Initialize(playerName, parentFrame)
	-- 创建菜单框架（如果不存在）
    if not WebDKP_PlayerRightClickMenu then
        WebDKP_PlayerRightClickMenu = CreateFrame("Frame", "WebDKP_PlayerRightClickMenu", UIParent, "UIDropDownMenuTemplate");
    end
    
	-- 保存当前玩家名称供菜单使用
    WebDKP_PlayerRightClickMenu.playerName = playerName;
    
	-- 初始化菜单
    UIDropDownMenu_Initialize(WebDKP_PlayerRightClickMenu, WebDKP_PlayerRightClickMenu_Create);
end

-- ================================  
-- 创建右键菜单内容  
-- ================================
function WebDKP_PlayerRightClickMenu_Create()
    local playerName = WebDKP_PlayerRightClickMenu.playerName;
    
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
        WebDKP_Frame.selectedPlayer = playerName;
        WebDKP_UpdateSingleAdjustLabel();
        WebDKP_Frame:Show();
        WebDKP_UpdateTable();
    end;
    UIDropDownMenu_AddButton(info);
    
	-- 添加查看详细信息选项
    info = {};
    info.text = "查看详细信息";
    info.func = function() 
        WebDKP_ShowPlayerDetails(playerName);
    end;
    UIDropDownMenu_AddButton(info);
    
	-- 添加查看历史记录选项
    info = {};
    info.text = "查看历史记录";
    info.func = function() 
        WebDKP_ShowPlayerHistory(playerName);
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
    info.func = function() WebDKP_HandleDeduction(playerName); end;
    UIDropDownMenu_AddButton(info);
    
	-- 添加加分选项
    info = {};
    info.text = "加分";
    info.func = function() WebDKP_HandleAward(playerName); end;
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
        info.func = function() WebDKP_HandleSub(playerName); end;
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
            StaticPopupDialogs["WEBDKP_UNINVITE_CONFIRM"] = {
                text = "确定要取消邀请 "..playerName.." 吗？",
                button1 = "确定",
                button2 = "取消",
                OnAccept = function()
                    UninviteByName(playerName);
                    WebDKP_Print("已取消邀请 "..playerName);
                end,
                timeout = 0,
                whileDead = true,
                hideOnEscape = true,
                preferredIndex = 3,
            };
            StaticPopup_Show("WEBDKP_UNINVITE_CONFIRM");
        end;
        UIDropDownMenu_AddButton(info);
        
        -- 设为队长
        info = {};
        info.text = "设为队长";
        info.func = function() 
            PromoteByName(playerName);
            WebDKP_Print("已将 "..playerName.." 设为队长");
        end;
        UIDropDownMenu_AddButton(info);
        
        -- 设为助理
        info = {};
        info.text = "设为助理";
        info.func = function() 
            PromoteToAssistant(playerName);
            WebDKP_Print("已将 "..playerName.." 设为助理");
        end;
        UIDropDownMenu_AddButton(info);
        
        -- 降职
        info = {};
        info.text = "降职";
        info.func = function() 
            DemoteByName(playerName);
            WebDKP_Print("已将 "..playerName.." 降职");
        end;
        UIDropDownMenu_AddButton(info);
    end
end

-- ================================  
-- 处理扣分操作  
-- ================================
function WebDKP_HandleDeduction(playerName)
	-- 确保玩家在DKP表中
    if not WebDKP_DkpTable[playerName] then
        WebDKP_Print(playerName .. " 不在DKP列表中！");
        return;
    end
    
	-- 勾选该玩家（支持多选，不取消其他玩家的选择）
    WebDKP_DkpTable[playerName]["Selected"] = true;
    
	-- 显示WebDKP主窗口
    WebDKP_Frame:Show();
    
	-- 切换到DKP奖惩页面（通常是第二个标签）
    getglobal("WebDKP_FrameTab2"):Click();
    
	-- 刷新表格显示，确保选中状态正确显示
    WebDKP_UpdateTable();
    
	-- 统计当前选中的玩家数量
    local selectedCount = 0;
    for name, data in pairs(WebDKP_DkpTable) do
        if data["Selected"] then
            selectedCount = selectedCount + 1;
        end
    end
    
	-- 提示用户已选中玩家，并说明可以继续选择其他玩家
    WebDKP_Print("已选中 " .. playerName .. "，当前共选中 " .. selectedCount .. " 名玩家。可继续右键选择其他玩家进行批量扣分。");
end

-- ================================  
-- 处理加分操作  
-- ================================
function WebDKP_HandleAward(playerName)
	-- 确保玩家在DKP表中
    if not WebDKP_DkpTable[playerName] then
        WebDKP_Print(playerName .. " 不在DKP列表中！");
        return;
    end
    
	-- 勾选该玩家
    WebDKP_DkpTable[playerName]["Selected"] = true;
    
	-- 显示WebDKP主窗口
    WebDKP_Frame:Show();
    
	-- 切换到DKP奖惩页面（通常是第二个标签）
    getglobal("WebDKP_FrameTab2"):Click();
    
	-- 刷新表格显示
    WebDKP_UpdateTable();
    
	-- 提示用户已选中玩家
    WebDKP_Print("已选中 " .. playerName .. "，请在DKP奖惩页面输入加分信息。");
end

-- ================================  
-- 显示玩家详细信息  
-- ================================
function WebDKP_ShowPlayerDetails(playerName)
	-- 确保玩家在DKP表中
    if not WebDKP_DkpTable[playerName] then
        WebDKP_Print(playerName .. " 不在DKP列表中！");
        return;
    end
    
    local playerData = WebDKP_DkpTable[playerName];
    local tableid = WebDKP_GetTableid();
    local playerDkp = playerData["dkp"..tableid] or 0;
    local playerClass = playerData["class"] or "未知职业";
    local playerGuild = playerData["guild"] or "未知公会";
    local playerTier = floor((playerDkp-1)/WebDKP_TierInterval);
    local isSub = playerData["IsSub"] or false;
    local isSelected = playerData["Selected"] or false;
    
	-- 显示详细信息
    WebDKP_Print("=== " .. playerName .. " 的详细信息 ===");
    WebDKP_Print("职业: " .. playerClass);
    WebDKP_Print("公会: " .. playerGuild);
    WebDKP_Print("当前DKP: " .. playerDkp);
    WebDKP_Print("阶层: " .. playerTier);
    WebDKP_Print("替补状态: " .. (isSub and "是" or "否"));
    WebDKP_Print("选中状态: " .. (isSelected and "已选中" or "未选中"));
    
	-- 显示主窗口并选中该玩家
    WebDKP_Frame:Show();
    WebDKP_UpdateTable();
end

-- ================================  
-- 显示玩家历史记录  
-- ================================
function WebDKP_ShowPlayerHistory(playerName)
	-- 确保玩家在DKP表中
    if not WebDKP_DkpTable[playerName] then
        WebDKP_Print(playerName .. " 不在DKP列表中！");
        return;
    end
    
	-- 显示WebDKP主窗口并切换到日志页面
    WebDKP_Frame:Show();
    getglobal("WebDKP_FrameTab3"):Click(); -- 切换到日志标签
    
	-- 如果没有日志数据，提示用户
    if not WebDKP_Log or not next(WebDKP_Log) then
        WebDKP_Print("没有找到 " .. playerName .. " 的历史记录。");
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
        WebDKP_Print("=== " .. playerName .. " 的DKP历史记录 ===");
        local count = 0;
        for _, record in ipairs(playerHistory) do
            if count < 10 then -- 只显示最近10条记录
                local pointsText = "";
                if record.points > 0 then
                    pointsText = "+" .. record.points;
                else
                    pointsText = tostring(record.points);
                end
                WebDKP_Print(string.format("[%s] %s (%s) - %s 由 %s 操作", 
                    record.date, record.reason, pointsText, record.zone, record.awardedby));
                count = count + 1;
            end
        end
        if historyCount > 10 then
            WebDKP_Print("... 还有 " .. (historyCount - 10) .. " 条记录");
        end
    else
        WebDKP_Print("没有找到 " .. playerName .. " 的历史记录。");
    end
end

-- ================================  
-- 处理替补操作  
-- ================================
function WebDKP_HandleSub(playerName)
	-- 确保玩家在DKP表中
    if not WebDKP_DkpTable[playerName] then
        WebDKP_Print(playerName .. " 不在DKP列表中！");
        return;
    end
    
	-- 确保在团队中
    if GetNumRaidMembers() == 0 then
        WebDKP_Print("只有在团队中才能设置替补状态！");
        return;
    end
    
	-- 切换替补状态
    if WebDKP_DkpTable[playerName]["IsSub"] then
        WebDKP_DkpTable[playerName]["IsSub"] = false;
        WebDKP_Print(playerName .. " 已取消替补状态。");
    else
        WebDKP_DkpTable[playerName]["IsSub"] = true;
        WebDKP_Print(playerName .. " 已设为替补。");
    end
    
	-- 刷新表格显示
    WebDKP_UpdateTable();
end



-- ================================
-- Selects all players in the dkp table and updates 
-- table display
-- ================================
function WebDKP_SelectAll()
	local tableid = WebDKP_GetTableid();
	for k, v in pairs(WebDKP_DkpTable) do
		if ( type(v) == "table" ) then
			local playerName = k; 
			local playerClass = v["class"];
			local playerDkp = v["dkp"..tableid];
			if ( playerDkp == nil ) then 
				v["dkp"..tableid] = 0;
				playerDkp = 0;
			end
			local playerTier = floor((playerDkp-1)/WebDKP_TierInterval);
			if (WebDKP_ShouldDisplay(playerName, playerClass, playerDkp, playerTier)) then
				WebDKP_DkpTable[playerName]["Selected"] = true;
			else
				WebDKP_DkpTable[playerName]["Selected"] = false;
			end
		end
	end
	WebDKP_UpdateTable();
	if WebDKP_UpdateSingleAdjustLabel then WebDKP_UpdateSingleAdjustLabel() end
end

-- ================================
-- Deselect all players and update table display
-- ================================
function WebDKP_UnselectAll()
	for k, v in pairs(WebDKP_DkpTable) do
		if ( type(v) == "table" ) then
			local playerName = k; 
			WebDKP_DkpTable[playerName]["Selected"] = false;
		end
	end
	WebDKP_UpdateTable();
	if WebDKP_UpdateSingleAdjustLabel then WebDKP_UpdateSingleAdjustLabel() end
end

-- ================================
-- Invoked when the gui loads up the drop down list of 
-- available dkp tables. 
-- ================================
function WebDKP_Tables_DropDown_OnLoad()
	UIDropDownMenu_Initialize(WebDKP_Tables_DropDown, WebDKP_Tables_DropDown_Init);
	
	local numTables = WebDKP_GetTableSize(WebDKP_Tables)
	if ( WebDKP_Tables == nil or numTables==0 or numTables==1) then
		WebDKP_Tables_DropDown:Hide();
	else
		WebDKP_Tables_DropDown:Show();
	end
end
-- ================================
-- Invoked when the drop down list of available tables
-- needs to be redrawn. Populates it with data 
-- from the tables data structure and sets up an 
-- event handler
-- ================================
function WebDKP_Tables_DropDown_Init()
	if( WebDKP_Frame.selectedTableid == nil ) then
		WebDKP_Frame.selectedTableid = 1;
	end
	local info;
	local selected = "";
	if ( WebDKP_Tables ~= nil and next(WebDKP_Tables)~=nil ) then
		for key, entry in pairs(WebDKP_Tables) do
			if ( type(entry) == "table" ) then
				info = { };
				info.text = entry.name or  key;
				info.value = entry["id"]; 
				info.func = WebDKP_Tables_DropDown_OnClick;
				if ( entry["id"] == WebDKP_Frame.selectedTableid ) then
					info.checked = ( entry["id"] == WebDKP_Frame.selectedTableid );
					selected = info.text;
				end
				UIDropDownMenu_AddButton(info);
			end
		end
	end
	UIDropDownMenu_SetSelectedName(WebDKP_Tables_DropDown, selected );
	UIDropDownMenu_SetWidth(200, WebDKP_Tables_DropDown);
end

-- ================================
-- Called when the user switches between
-- a different dkp table.
-- ================================
-- In WoW 1.12 Lua 5.0, use 'this' instead of function parameters
function WebDKP_Tables_DropDown_OnClick()
	local button = this
	if not button then
		return
	end
	WebDKP_Frame.selectedTableid = button.value;
	WebDKP_Options["SelectedTableId"] = button.value; 
	WebDKP_Tables_DropDown_Init();
	WebDKP_UpdateTableToShow(); --update who is in the table
	WebDKP_UpdateTable();       --update the gui
end


-- ================================
-- Toggles zero sum support
-- ================================
function WebDKP_ToggleZeroSum()
	-- is enabled, disable it
	if ( WebDKP_WebOptions["ZeroSumEnabled"] == 1 ) then
		WebDKP_WebOptions["ZeroSumEnabled"] = 0;
	-- is disabled, enable it
	else
		WebDKP_WebOptions["ZeroSumEnabled"] = 1;
	end
end

-- ================================
-- Toggles map validation support
-- ================================
function WebDKP_ToggleMapValidation()
	-- is enabled, disable it
	if ( WebDKP_WebOptions["MapValidationEnabled"] == 1 ) then
		WebDKP_WebOptions["MapValidationEnabled"] = 0;
		DEFAULT_CHAT_FRAME:AddMessage("[WebDKP] 地图验证已禁用", 1, 1, 1);
	-- is disabled, enable it
	else
		WebDKP_WebOptions["MapValidationEnabled"] = 1;
		DEFAULT_CHAT_FRAME:AddMessage("[WebDKP] 地图验证已启用", 1, 1, 1);
	end
end




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
function WebDKP_MinimapButton_MouseDown(self)
	-- Remember where the cursor was in case the user drags
	local button = self or  WebDKP_MinimapButton
	if not button then
		return
	end
	
	local	vCursorX, vCursorY = GetCursorPosition();
	
	vCursorX = vCursorX / button:GetEffectiveScale();
	vCursorY = vCursorY / button:GetEffectiveScale();
	
	WebDKP_MinimapButton.CursorStartX = vCursorX;
	WebDKP_MinimapButton.CursorStartY = vCursorY;
	
	local	vCenterX, vCenterY = WebDKP_MinimapButton:GetCenter();
	local	vMinimapCenterX, vMinimapCenterY = Minimap:GetCenter();
	
	WebDKP_MinimapButton.CenterStartX = vCenterX - vMinimapCenterX;
	WebDKP_MinimapButton.CenterStartY = vCenterY - vMinimapCenterY;
end

-- ================================
-- Called when the user starts to drag. Shows a frame that is registered
-- to recieve on update signals, we can then have its event handler
-- check to see the current mouse position and update the mini map button
-- correctly
-- ================================
function WebDKP_MinimapButton_DragStart()
	WebDKP_MinimapButton.IsDragging = true;
	WebDKP_UpdateFrame:Show();
end

-- ================================
-- Users stops dragging. Ends the timer
-- ================================
function WebDKP_MinimapButton_DragEnd()
	WebDKP_MinimapButton.IsDragging = false;
	WebDKP_UpdateFrame:Hide();
end

-- ================================
-- Updates the position of the mini map button. Should be called
-- via the on update method of the update frame
-- ================================
function WebDKP_MinimapButton_UpdateDragPosition(self)
	-- Remember where the cursor was in case the user drags
	local button = self or  WebDKP_MinimapButton
	if not button then
		return
	end
	local	vCursorX, vCursorY = GetCursorPosition();
	
	vCursorX = vCursorX / button:GetEffectiveScale();
	vCursorY = vCursorY / button:GetEffectiveScale();
	
	local	vCursorDeltaX = vCursorX - WebDKP_MinimapButton.CursorStartX;
	local	vCursorDeltaY = vCursorY - WebDKP_MinimapButton.CursorStartY;
	
	--
	
	local	vCenterX = WebDKP_MinimapButton.CenterStartX + vCursorDeltaX;
	local	vCenterY = WebDKP_MinimapButton.CenterStartY + vCursorDeltaY;
	
	-- Calculate the angle
	
	local	vAngle = math.atan2(vCenterX, vCenterY);
	
	-- Set the new position
	
	WebDKP_MinimapButton_SetPositionAngle(vAngle);
end

-- ================================
-- Helper method. Helps restrict a given angle from occuring within a restricted angle
-- range. Returns where the angle should be pushed to - before or after the resitricted
-- range. Used to block the minimap button from appear behind the default ui buttons
-- ================================
function WebDKP_RestrictAngle(pAngle, pRestrictStart, pRestrictEnd)
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
function WebDKP_MinimapButton_SetPositionAngle(pAngle)
	local	vAngle = pAngle;
	
	-- Restrict the angle from going over the date/time icon or the zoom in/out icons
	
	local	vRestrictedStartAngle = nil;
	local	vRestrictedEndAngle = nil;
	
	if GameTimeFrame:IsVisible() then
		if MinimapZoomIn:IsVisible()
		or MinimapZoomOut:IsVisible() then
			vAngle = WebDKP_RestrictAngle(vAngle, 0.4302272732931596, 2.930420793963121);
		else
			vAngle = WebDKP_RestrictAngle(vAngle, 0.4302272732931596, 1.720531504573905);
		end
		
	elseif MinimapZoomIn:IsVisible()
	or MinimapZoomOut:IsVisible() then
		vAngle = WebDKP_RestrictAngle(vAngle, 1.720531504573905, 2.930420793963121);
	end
	
	-- Restrict it from the tracking icon area
	
	vAngle = WebDKP_RestrictAngle(vAngle, -1.290357134304173, -0.4918423429923585);
	
	--
	
	local	vRadius = 80;
	
	vCenterX = math.sin(vAngle) * vRadius;
	vCenterY = math.cos(vAngle) * vRadius;
	
	WebDKP_MinimapButton:SetPoint("CENTER", "Minimap", "CENTER", vCenterX - 1, vCenterY - 1);
	
	WebDKP_Options["MiniMapButtonAngle"] = vAngle;
	--gOutfitter_Settings.Options.MinimapButtonAngle = vAngle;
end

-- ================================
-- Event handler for the update frame. Updates the minimap button
-- if it is currently being dragged. 
-- ================================
-- In WoW 1.12 Lua 5.0, OnUpdate handlers don't receive parameters directly
function WebDKP_OnUpdate()
	if WebDKP_MinimapButton.IsDragging then
		WebDKP_MinimapButton_UpdateDragPosition();
	end
end


-- ================================
-- Initializes the minimap drop down
-- ================================
-- In WoW 1.12 Lua 5.0, use 'this' instead of function parameters
function WebDKP_MinimapDropDown_OnLoad()
	local dropdown = this
	if not dropdown then
		return
	end
	UIDropDownMenu_SetAnchor(-2, -20, dropdown, "TOPRIGHT", dropdown:GetName(), "TOPLEFT");
	UIDropDownMenu_Initialize(dropdown, WebDKP_MinimapDropDown_Initialize);
end

-- ================================
-- Adds buttons to the minimap drop down
-- ================================
function WebDKP_MinimapDropDown_Initialize()
	-- 数据列表框架已在插件加载时预加载，这里直接添加菜单项
	WebDKP_Add_MinimapDropDownItem("DKP 列表",WebDKP_ToggleGUI);
	WebDKP_Add_MinimapDropDownItem("竞拍",WebDKP_Bid_ToggleUI);
	
	--WebDKP_Add_MinimapDropDownItem("Help",WebDKP_ToggleGUI);
end

-- ================================
-- Helper method that adds individual entries into the minimap drop down
-- menu.
-- ================================
function WebDKP_Add_MinimapDropDownItem(text, eventHandler)
	local info = { };
	info.text = text;
	info.value = text; 
	info.owner = UIDROPDOWNMENU_OPEN_MENU;
	info.func = eventHandler; -- WebDKP_Tables_DropDown_OnClick;
	UIDropDownMenu_AddButton(info);
end


-- ================================
-- Helper method. Called whenever a player clicks on shift click
-- ================================
function WebDKP_ItemChatClick(link, text, button)
	
	-- do a search for 'player'. If it can be found... this is a player link, not an item link. It can be ignored
	local idx = strfind(text, "player");
	
	if( idx == nil ) then
		-- check to see if the bidding frame wants to do anything with the information
		WebDKP_Bid_ItemChatClick(link, text, button);
		
		-- put the item text into the award editbox as long as the table frame is visible
		if ( IsShiftKeyDown()) then
			local _,itemName,_ = WebDKP_GetItemInfo(link); 
			WebDKP_AwardItem_FrameItemName:SetText(itemName);
		end
	end
	WebDKP_ItemChatClick_Original(link, text, button);
end

---------------------------------------------------
-- 自动分配物品功能
---------------------------------------------------

-- 全局变量
WebDKP_AutoLootData = {
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
function WebDKP_CreateAutoLootFrame()
	if WebDKP_AutoLootData.frame then
		return WebDKP_AutoLootData.frame;
	end
	
	local frame = CreateFrame("Frame", "WebDKP_AutoLootFrame", UIParent);
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
		WebDKP_StopAutoLoot(false);
	end);
	
	frame:Hide();
	WebDKP_AutoLootData.frame = frame;
	return frame;
end

-- ================================
-- 开始自动分配物品
-- ================================
function WebDKP_StartAutoLoot(itemLink, playerName, dkpCost)
	-- 检查是否有分配权限
	local lootMethod, masterLooterPartyID = GetLootMethod();
	if lootMethod ~= "master" then
		WebDKP_Print("错误：当前不是队长分配模式");
		return;
	end
	
	-- 检查是否是分配者
	local isLooter = false;
	-- 检查是否在团队中且masterLooterPartyID不为nil
	if not masterLooterPartyID then
		WebDKP_Print("错误：你不在团队中或无法获取分配者信息");
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
		WebDKP_Print("错误：你不是分配者");
		return;
	end
	
	-- 初始化分配数据
	WebDKP_AutoLootData.isAssigning = true;
	WebDKP_AutoLootData.currentPlayer = playerName;
	WebDKP_AutoLootData.currentItem = string.match(itemLink, "%[(.+)%]") or itemLink;
	WebDKP_AutoLootData.currentItemLink = itemLink;
	WebDKP_AutoLootData.currentCost = dkpCost or 0;
	WebDKP_AutoLootData.retryCount = 0;
	
	-- 创建并显示状态窗口
	local frame = WebDKP_CreateAutoLootFrame();
	frame.statusText:SetText("正在分配 "..WebDKP_AutoLootData.currentItem.." 给 "..playerName);
	frame:Show();
	
	-- 检查是否有可分配物品
	if GetNumLootItems() == 0 then
		frame.statusText:SetText("等待打开尸体...");
		WebDKP_Print("等待打开尸体进行自动分配");
		-- 不返回，保持自动分配状态
	else
		-- 尝试分配物品
		WebDKP_TryAssignLoot();
	end
end

-- ================================
-- 尝试分配物品
-- ================================
function WebDKP_TryAssignLoot()
	if not WebDKP_AutoLootData.isAssigning then
		return;
	end
	
	-- 检查重试次数
	WebDKP_AutoLootData.retryCount = WebDKP_AutoLootData.retryCount + 1;
	if WebDKP_AutoLootData.retryCount > WebDKP_AutoLootData.maxRetries then
		WebDKP_StopAutoLoot(false);
		WebDKP_Print("自动分配失败：重试次数过多");
		return;
	end
	
	-- 检查是否还有可分配物品
	if GetNumLootItems() == 0 then
		-- 没有可分配物品时，不停止自动分配，而是等待
		if WebDKP_AutoLootData.frame then
			WebDKP_AutoLootData.frame.statusText:SetText("等待打开尸体...");
		end
		-- 重置重试计数，因为这不是真正的失败
		WebDKP_AutoLootData.retryCount = WebDKP_AutoLootData.retryCount - 1;
		return;
	end
	
	-- 查找匹配的物品
	local foundItemSlot = nil;
	for i = 1, GetNumLootItems() do
		local link = GetLootSlotLink(i);
		if link then
			local itemName = string.match(link, "%[(.+)%]");
			if itemName == WebDKP_AutoLootData.currentItem then
				foundItemSlot = i;
				break;
			end
		end
	end
	
	if not foundItemSlot then
		WebDKP_StopAutoLoot(false);
		WebDKP_Print("错误：物品不匹配或已被分配");
		return;
	end
	
	-- 查找匹配的玩家
	local foundPlayerIndex = nil;
	for j = 1, 40 do
		local candidateName = GetMasterLootCandidate(j);
		if candidateName == WebDKP_AutoLootData.currentPlayer then
			foundPlayerIndex = j;
			break;
		end
	end
	
	if not foundPlayerIndex then
		local playerName = WebDKP_AutoLootData.currentPlayer or "未知1玩家";
		
		-- 检查是否是给自己分配
		if WebDKP_AutoLootData.currentPlayer == UnitName("player") then
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
				if WebDKP_AutoLootData.frame then
					WebDKP_AutoLootData.frame.statusText:SetText("等待团队信息同步...");
				end
				-- 重置重试计数
				WebDKP_AutoLootData.retryCount = WebDKP_AutoLootData.retryCount - 1;
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
							WebDKP_TryAssignLoot();
						end
					end);
				return;
			else
				-- 不在团队中，直接停止
				WebDKP_StopAutoLoot(false);
				WebDKP_Print("错误：你不在团队中");
				return;
			end
		end
		
		-- 其他玩家不在拾取队列，继续自动分配模式
		if WebDKP_AutoLootData.frame then
			WebDKP_AutoLootData.frame.statusText:SetText("玩家不在拾取范围，等待返回...");
		end
		local tellLocation = WebDKP_GetTellLocation();
		WebDKP_SendAnnouncement(playerName.." 不在副本内 无法分配 请迅速返回", tellLocation);
		if WebDKP_AutoLootData.currentPlayer then
			SendChatMessage(playerName.." 不在副本内 无法分配 请迅速返回", "WHISPER", nil, WebDKP_AutoLootData.currentPlayer);
		end
		-- 重置重试计数，因为这不是真正的失败
		WebDKP_AutoLootData.retryCount = WebDKP_AutoLootData.retryCount - 1;
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
				WebDKP_TryAssignLoot();
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
function WebDKP_StopAutoLoot(success)
	WebDKP_AutoLootData.isAssigning = false;
	WebDKP_AutoLootData.currentPlayer = nil;
	WebDKP_AutoLootData.currentItem = nil;
	WebDKP_AutoLootData.currentItemLink = nil;
	WebDKP_AutoLootData.currentCost = 0;
	WebDKP_AutoLootData.retryCount = 0;
	
	if WebDKP_AutoLootData.frame then
		WebDKP_AutoLootData.frame:Hide();
	end
end

-- ================================
-- 处理UI错误消息
-- ================================
function WebDKP_HandleUIError()
	if not WebDKP_AutoLootData.isAssigning then
		return;
	end
	
	local errorMsg = arg1;
	if not errorMsg then
		return;
	end
	
	-- 确保currentPlayer不为nil
	local playerName = WebDKP_AutoLootData.currentPlayer or "未知2玩家";
	
	if string.find(errorMsg, "该玩家的物品栏已满") then
		-- 背包已满，继续自动分配模式
		if WebDKP_AutoLootData.frame then
			WebDKP_AutoLootData.frame.statusText:SetText("背包已满，等待清理背包...");
		end
		local tellLocation = WebDKP_GetTellLocation();
		WebDKP_SendAnnouncement(playerName.." 背包已满 请清理背包", tellLocation);
		if WebDKP_AutoLootData.currentPlayer then
			SendChatMessage(playerName.." 背包已满 请清理背包", "WHISPER", nil, WebDKP_AutoLootData.currentPlayer);
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
				WebDKP_TryAssignLoot();
			end
		end);
	elseif string.find(errorMsg, "无法将物品分配给该玩家") then
		-- 玩家不在副本内，继续自动分配模式
		if WebDKP_AutoLootData.frame then
			WebDKP_AutoLootData.frame.statusText:SetText("玩家不在副本，等待返回...");
		end
		local tellLocation = WebDKP_GetTellLocation();
		WebDKP_SendAnnouncement(playerName.." 不在副本内 无法分配 请迅速返回", tellLocation);
		if WebDKP_AutoLootData.currentPlayer then
			SendChatMessage(playerName.." 不在副本内 无法分配 请迅速返回", "WHISPER", nil, WebDKP_AutoLootData.currentPlayer);
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
				WebDKP_TryAssignLoot();
			end
		end);
	else
		-- 其他错误，重试
		if WebDKP_AutoLootData.frame then
			WebDKP_AutoLootData.frame.statusText:SetText("分配失败，正在重试...（"..WebDKP_AutoLootData.retryCount.."/"..WebDKP_AutoLootData.maxRetries.."）");
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
				WebDKP_TryAssignLoot();
			end
		end);
	end
end


-- ================================
-- BOSS击杀处理函数
-- ================================

-- 全局变量用于存储BOSS击杀信息
WebDKP_BossAwardData = {
    bossName = nil,
    points = 2,
    frame = nil,
    subTime = 5 -- 替补计时默认5分钟
}

-- 初始化Boss奖励数据，从WebDKP_Options加载保存的设置
function WebDKP_InitBossAwardData()
	-- 确保WebDKP_Options存在
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
function WebDKP_IsWorldBossByName(Name)
    if not Name or Name == "" then
        return false
    end
    
	-- 保存当前目标信息
    local hadTarget = UnitExists("target")
    local oldTargetName = hadTarget and UnitName("target") or nil
    
	-- 尝试选中目标
    TargetByName(Name, true)
    
	-- 检查是否成功选中了目标且该目标是世界BOSS
    local isWorldBoss = false
    if UnitExists("target") then
        local unitClassification = UnitClassification("target")
        if unitClassification == "worldboss" then
            isWorldBoss = true
        end
    end
    
	-- 恢复之前的目标状态
    if hadTarget then
        -- 如果之前有目标，尝试切回
        TargetLastTarget()
        -- 双重保险：确认是否切回了正确的目标
        if UnitExists("target") and UnitName("target") ~= oldTargetName then
            ClearTarget()
            TargetByName(oldTargetName, true)
        end
    else
        -- 如果之前没有目标，清除当前目标
        ClearTarget()
    end
    
	-- 返回检查结果
    return isWorldBoss
end

-- ================================
-- 处理战斗敌对死亡事件
-- ================================
function WebDKP_HandleCombatHostileDeath(message)
	-- 解析消息，提取被杀死的目标名称
    local killedUnitName = WebDKP_ExtractBossName(message)
    
    if killedUnitName then
        -- 检查是否为世界BOSS或者匹配BOSS名称模式
        if WebDKP_IsWorldBossByName(killedUnitName) or WebDKP_IsBossByNamePattern(killedUnitName) then
            -- 检查BOSS死亡弹窗开关
            local isBossPopupEnabled = true
            if WebDKP_Options and WebDKP_Options["BossDeathPopup"] ~= nil then
                isBossPopupEnabled = WebDKP_Options["BossDeathPopup"]
            end
            
            -- 如果弹窗被关闭，则直接返回，不显示弹窗
            if not isBossPopupEnabled then
                return
            end
            
            -- 保存BOSS名称
            WebDKP_BossAwardData.bossName = killedUnitName
            
            -- 检查玩家是否在战斗中（WoW 1.12兼容方式）
            if UnitAffectingCombat("player") then
                -- 在战斗中，延迟显示弹窗，直到脱战
                WebDKP_ScheduleBossAwardFrame()
            else
                -- 不在战斗中，立即显示弹窗
                WebDKP_ShowBossAwardFrame()
            end
        end
    end
end

-- ================================
-- 安排BOSS奖励窗口在脱战后显示
-- ================================
function WebDKP_ScheduleBossAwardFrame()
	-- 创建定时器来检测脱战状态
    if not WebDKP_BossAwardData.combatCheckTimer then
        WebDKP_BossAwardData.combatCheckTimer = CreateFrame("Frame")
    end
    
	-- 设置定时器脚本（WoW 1.12兼容方式）
    WebDKP_BossAwardData.combatCheckTimer:SetScript("OnUpdate", function()
        -- 检查是否已脱战
        if not UnitAffectingCombat("player") then
            -- 已脱战，清除定时器并显示弹窗
            local frame =  WebDKP_BossAwardData.combatCheckTimer
            frame:SetScript("OnUpdate", nil)
            WebDKP_ShowBossAwardFrame()
        end
    end)
end

-- ================================
-- 从消息中提取BOSS名称
-- ================================
-- 从消息中提取BOSS名称
-- ================================
function WebDKP_ExtractBossName(message)
	-- 匹配BOSS死亡消息格式，如："拉格纳罗斯死亡了。"
    local patterns = {
        "(.+)死亡了。",
        "(.+)被击败了。",
        "(.+)被消灭了。",
        "(.+)被击杀。",
        "(.+)倒下了。"
    }
    
    for _, pattern in ipairs(patterns) do
        local bossName = string.match(message, pattern)
        if bossName then
            return bossName
        end
    end
    
	-- 如果没有匹配到任何模式，尝试提取被击杀的单位名称
	-- 格式可能是："你杀死了拉格纳罗斯" 或 "拉格纳罗斯被玩家名杀死了"
    local killPatterns = {
        "你杀死了(.+)",
        "(.+)被你杀死了",
		"(.+)被.+干掉了",
        "(.+)被.+杀死了"
    }
    
    for _, pattern in ipairs(killPatterns) do
        local bossName = string.match(message, pattern)
        if bossName then
            return bossName
        end
    end
    
    return nil
end

-- ================================
-- 判断是否为BOSS（综合验证）
-- ================================
function WebDKP_IsBoss(unitName)
    if not unitName or unitName == "" then
        return false
    end
    
	-- 直接使用名称模式识别BOSS，不再依赖UnitClassification
    return WebDKP_IsBossByNamePattern(unitName)
end

-- ================================
-- 通过名称模式识别BOSS（不依赖UnitClassification）
-- ================================
function WebDKP_IsBossByNamePattern(unitName)
    if not unitName or unitName == "" then
        return false
    end  
	-- 检查名称模式（常见的BOSS名称关键词）
    local bossPatterns = {
        "拉格纳罗斯", "奥妮克希亚","破碎者鲁普图兰"
    }  --自定义添加名字 以防万一 应该都是worldboss
    for _, pattern in ipairs(bossPatterns) do
        if string.find(unitName, pattern) then
            return true
        end
    end
    return false
end

-- ================================
-- 显示BOSS奖励窗口
-- ================================
function WebDKP_ShowBossAwardFrame()
    if not WebDKP_BossAwardData.frame then
        WebDKP_CreateBossAwardFrame()
    end
    
    local frame = WebDKP_BossAwardData.frame
    if frame then
        -- 设置BOSS名称
        frame.bossNameText:SetText("BOSS: " .. (WebDKP_BossAwardData.bossName or "未知"))
        -- 设置默认分数
        frame.pointsEditBox:SetText(WebDKP_BossAwardData.points)
        

        
        -- 显示窗口
        frame:Show()
    end
end

-- ================================
-- 创建BOSS奖励窗口
-- ================================
function WebDKP_CreateBossAwardFrame()
    local frame = CreateFrame("Frame", "WebDKP_BossAwardFrame", UIParent)
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
    frame.bossNameText:SetText("BOSS: " .. (WebDKP_BossAwardData.bossName or "未知"))
    

    
	-- 分数输入框
    frame.pointsLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.pointsLabel:SetPoint("TOPLEFT", 20, -70)
    frame.pointsLabel:SetText("分数:")
    
    frame.pointsEditBox = CreateFrame("EditBox", "WebDKP_BossAwardPointsEditBox", frame, "InputBoxTemplate")
    frame.pointsEditBox:SetWidth(60)
    frame.pointsEditBox:SetHeight(20)
    frame.pointsEditBox:SetPoint("LEFT", frame.pointsLabel, "RIGHT", 10, 0)
    frame.pointsEditBox:SetAutoFocus(false)
    frame.pointsEditBox:SetNumeric(true)
    frame.pointsEditBox:SetText(WebDKP_BossAwardData.points)
    
	-- 设置背景
    frame.pointsEditBox:SetBackdropColor(0, 0, 0, 0.8)
    frame.pointsEditBox:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
    
	-- 设置文字居中显示
    frame.pointsEditBox:SetJustifyH("CENTER")
    frame.pointsEditBox:SetJustifyV("MIDDLE")

    frame.pointsEditBox:SetScript("OnTextChanged", function()
        local points = tonumber(frame.pointsEditBox:GetText())
        if points then
            WebDKP_BossAwardData.points = points
        end
    end)
    
	-- DKP列表下拉框（移到分数右边）
    frame.tableLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.tableLabel:SetPoint("LEFT", frame.pointsEditBox, "RIGHT", 10, 0)
    frame.tableLabel:SetText("列表:")
    
    frame.tableDropdown = CreateFrame("Frame", "WebDKP_BossAwardTableDropdown", frame, "UIDropDownMenuTemplate")
    frame.tableDropdown:SetPoint("LEFT", frame.tableLabel, "RIGHT", -10, 0)
    frame.tableDropdown:SetWidth(90)
    
	-- 初始化下拉菜单
    UIDropDownMenu_Initialize(frame.tableDropdown, WebDKP_BossAwardTableDropdown_Init)
    
	-- 设置默认选择
    WebDKP_BossAwardData.tableid = WebDKP_BossAwardData.tableid or 1
	-- 延迟设置下拉菜单选择，避免在初始化过程中访问未设置的frame字段
    frame:SetScript("OnShow", function()
        UIDropDownMenu_SetSelectedID(frame.tableDropdown, WebDKP_BossAwardData.tableid)
        -- 使用UIDropDownMenu_SetWidth来正确设置下拉框宽度
        UIDropDownMenu_SetWidth(90, frame.tableDropdown)
        
        -- 获取并设置当前选中的表名称作为下拉菜单显示文本
        if WebDKP_Tables then
            for name, tableData in pairs(WebDKP_Tables) do
                if tableData["id"] == WebDKP_BossAwardData.tableid then
                    UIDropDownMenu_SetText(name, frame.tableDropdown)
                    break
                end
            end
        end
        

    end)
    
    local function BossAwardRunRaidAndSub()
        local pointsText = frame.pointsEditBox:GetText() or ""
        if pointsText == "" then
            WebDKP_Print("请输入分数")
            return
        end
        local reason = "击杀-" .. (WebDKP_BossAwardData.bossName or "未知BOSS")
        -- 临时设置原因和分数，复用统一的大团+替补奖惩入口。
        local prevReason = WebDKP_AwardDKP_FrameReason
        local prevPoints = WebDKP_AwardDKP_FramePoints
        WebDKP_AwardDKP_FrameReason = { GetText = function() return reason end }
        WebDKP_AwardDKP_FramePoints = { GetText = function() return pointsText end }
        WebDKP_AwardRaidAndSub_Event()
        WebDKP_AwardDKP_FrameReason = prevReason
        WebDKP_AwardDKP_FramePoints = prevPoints
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
    
    frame.subTimeEditBox = CreateFrame("EditBox", "WebDKP_BossAwardSubTimeEditBox", frame, "InputBoxTemplate")
    frame.subTimeEditBox:SetWidth(60)
    frame.subTimeEditBox:SetHeight(20)
    frame.subTimeEditBox:SetPoint("LEFT", frame.subTimeLabel, "RIGHT", 10, 0)
    frame.subTimeEditBox:SetAutoFocus(false)
    frame.subTimeEditBox:SetNumeric(true)
    frame.subTimeEditBox:SetText(WebDKP_BossAwardData.subTime) -- 默认5分钟
    

    frame.subTimeEditBox:SetBackdropColor(0, 0, 0, 0.8)
    frame.subTimeEditBox:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
    
	-- 设置文字居中显示
    frame.subTimeEditBox:SetJustifyH("CENTER")
    frame.subTimeEditBox:SetJustifyV("MIDDLE")

    
    frame.subTimeEditBox:SetScript("OnTextChanged", function()
        local time = tonumber(frame.subTimeEditBox:GetText())
        if time and time > 0 then
            WebDKP_BossAwardData.subTime = time
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
        WebDKP_Frame:Show()
        -- 设置主窗口的DKP列表选择
        WebDKP_Frame.selectedTableid = WebDKP_BossAwardData.tableid
        -- 切换到奖惩DKP页（通常是第二个标签）
        getglobal("WebDKP_FrameTab2"):Click()
        -- 填充原因字段
        WebDKP_AwardDKP_FrameReason:SetText("击杀-" .. (WebDKP_BossAwardData.bossName or "未知BOSS"))
        -- 填充分数字段
        WebDKP_AwardDKP_FramePoints:SetText(WebDKP_BossAwardData.points)
        -- 刷新主界面的列表显示
        WebDKP_Tables_DropDown_Init()
        -- 确保DKP列表下拉框正确显示/隐藏
        WebDKP_Tables_DropDown_OnLoad()
    end)
    
    frame:Hide()
    WebDKP_BossAwardData.frame = frame
    return frame
end

-- ================================
-- 创建替补加分面板
-- ================================
function WebDKP_CreateSubAwardFrame()
    if not WebDKP_SubAwardData then
        WebDKP_SubAwardData = {
            active = false,
            captain = "",
            reason = "",
            points = 0,
            bossName = ""
        }
    end
    
    local frame = CreateFrame("Frame", "WebDKP_SubAwardFrame", UIParent)
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
        WebDKP_SubAwardData.active = false
        frame:Hide()
    end)
    
	-- BOSS名称显示
    frame.bossNameText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.bossNameText:SetPoint("TOP", 0, -50)
    frame.bossNameText:SetText("BOSS: " .. (WebDKP_SubAwardData.bossName or "未知"))
    
	-- 替补队队长输入框
    frame.captainLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.captainLabel:SetPoint("TOPLEFT", 20, -70)
    frame.captainLabel:SetText("替补队队长:")
    
    frame.captainEditBox = CreateFrame("EditBox", "WebDKP_SubAwardCaptainEditBox", frame, "InputBoxTemplate")
    frame.captainEditBox:SetWidth(150)
    frame.captainEditBox:SetHeight(20)
    frame.captainEditBox:SetPoint("LEFT", frame.captainLabel, "RIGHT", 10, 0)
    frame.captainEditBox:SetAutoFocus(false)
    frame.captainEditBox:SetText(WebDKP_SubAwardData.captain)
    frame.captainEditBox:SetBackdropColor(0, 0, 0, 0.8)
    frame.captainEditBox:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
    frame.captainEditBox:SetJustifyH("LEFT")
    frame.captainEditBox:SetJustifyV("MIDDLE")
    
    frame.captainEditBox:SetScript("OnTextChanged", function()
			WebDKP_SubAwardData.captain = frame.captainEditBox:GetText()
			-- 保存到WebDKP_Options，确保设置持久化
			if WebDKP_Options and WebDKP_Options["SubSettings"] then
				WebDKP_Options["SubSettings"].captain = WebDKP_SubAwardData.captain
			end
    end)
    
	-- 原因输入框
    frame.reasonLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.reasonLabel:SetPoint("TOPLEFT", 20, -100)
    frame.reasonLabel:SetText("原因:")
    
    frame.reasonEditBox = CreateFrame("EditBox", "WebDKP_SubAwardReasonEditBox", frame, "InputBoxTemplate")
    frame.reasonEditBox:SetWidth(230)
    frame.reasonEditBox:SetHeight(20)
    frame.reasonEditBox:SetPoint("LEFT", frame.reasonLabel, "RIGHT", 10, 0)
    frame.reasonEditBox:SetAutoFocus(false)
    frame.reasonEditBox:SetText(WebDKP_SubAwardData.reason)
    frame.reasonEditBox:SetBackdropColor(0, 0, 0, 0.8)
    frame.reasonEditBox:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
    frame.reasonEditBox:SetJustifyH("LEFT")
    frame.reasonEditBox:SetJustifyV("MIDDLE")
    
    frame.reasonEditBox:SetScript("OnTextChanged", function()
        WebDKP_SubAwardData.reason = frame.reasonEditBox:GetText()
    end)
    
	-- 分数输入框
    frame.pointsLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.pointsLabel:SetPoint("TOPLEFT", 20, -130)
    frame.pointsLabel:SetText("分数:")
   
    frame.pointsEditBox = CreateFrame("EditBox", "WebDKP_SubAwardPointsEditBox", frame, "InputBoxTemplate")
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
    local points = frame.pointsEditBox:GetText() or WebDKP_SubAwardData.points
    frame.pointsEditBox:SetScript("OnTextChanged", function()
        local points = tonumber(frame.pointsEditBox:GetText())
        if points then
            WebDKP_SubAwardData.points = points
        end
    end)
    
	-- 搜索替补队员按钮
    frame.searchButton = CreateFrame("Button", nil, frame, "GameMenuButtonTemplate")
    frame.searchButton:SetWidth(120)
    frame.searchButton:SetHeight(25)
    frame.searchButton:SetPoint("LEFT", frame.pointsEditBox, "RIGHT", 20, 0)
    frame.searchButton:SetText("搜索替补队员")
    frame.searchButton:SetScript("OnClick", function()
        WebDKP_SearchSubMembers()
    end)

    
	-- 加分按钮
    frame.awardButton = CreateFrame("Button", nil, frame, "GameMenuButtonTemplate")
    frame.awardButton:SetWidth(100)
    frame.awardButton:SetHeight(25)
    frame.awardButton:SetPoint("BOTTOMRIGHT", -30, 20)
    frame.awardButton:SetText("加分")
    frame.awardButton:SetScript("OnClick", function()
        -- 确保WebDKP_SubAwardData存在并包含所有必要字段
        if not WebDKP_SubAwardData then
            WebDKP_SubAwardData = {
                captain = "",
                reason = "",
                points = 0,
                bossName = ""
            }
            WebDKP_Print("警告: WebDKP_SubAwardData 未初始化，已创建默认对象")
        end
        
        -- 同步UI输入到WebDKP_SubAwardData
        WebDKP_SubAwardData.captain = WebDKP_SubAwardData.points or frame.captainEditBox:GetText() or ""
        WebDKP_SubAwardData.reason = frame.reasonEditBox:GetText() or ""
        local pointsText = frame.pointsEditBox:GetText() or "0"
        WebDKP_SubAwardData.points = tonumber(pointsText) or 0
        
        -- 调试信息
        -- WebDKP_Print("加分按钮点击: captain='" .. WebDKP_SubAwardData.captain .. "', reason='" .. WebDKP_SubAwardData.reason .. "', points='" .. WebDKP_SubAwardData.points .. "'")
        
        -- 只检查队长名称，其他验证在WebDKP_AwardSubPoints中处理
        if WebDKP_SubAwardData.captain == "" then
            WebDKP_Print("请输入替补队队长名称")
            frame.captainEditBox:SetFocus()
            frame.captainEditBox:HighlightText()
            PlaySound("igQuestFailed")
            return
        end
        
        -- 直接调用WebDKP_AwardSubPoints函数，让它处理其他验证和自动设置默认值
        WebDKP_AwardSubPoints()
    end)
    
	-- 取消按钮
    frame.cancelButton = CreateFrame("Button", nil, frame, "GameMenuButtonTemplate")
    frame.cancelButton:SetWidth(100)
    frame.cancelButton:SetHeight(25)
    frame.cancelButton:SetPoint("BOTTOMLEFT", 30, 20)
    frame.cancelButton:SetText("取消")
    frame.cancelButton:SetScript("OnClick", function()
        WebDKP_SubAwardData.active = false
        frame:Hide()
    end)
    
	-- 初始化
        WebDKP_SubAwardData.frame = frame
        frame:Hide()
        return frame
    end

-- 初始化替补队员数据存储
WebDKP_PendingSubMembers = WebDKP_PendingSubMembers or {}

-- ================================
-- 显示替补加分面板
-- ================================
function WebDKP_ShowSubAwardFrame(requireCaptainSetup)
    if not WebDKP_SubAwardData then
        WebDKP_SubAwardData = {
            active = false,
            captain = "",
            reason = "",
            points = 0,
            bossName = ""
        }
        WebDKP_Print("WebDKP_SubAwardData 已初始化")
    end
    
	-- 复制BOSS奖励数据
    WebDKP_SubAwardData.bossName = WebDKP_BossAwardData.bossName or ""
    
    WebDKP_SubAwardData.points = WebDKP_BossAwardData.points or 0
    
	-- 调试信息
	-- WebDKP_Print("WebDKP_ShowSubAwardFrame调试: bossName='" .. (WebDKP_SubAwardData.bossName or "nil") .. "', points='" .. (WebDKP_SubAwardData.points or "nil") .. "'")
    
	-- 保留bossName-替补格式，但处理空值情况
    if WebDKP_SubAwardData.bossName and WebDKP_SubAwardData.bossName ~= "" then
        WebDKP_SubAwardData.reason = WebDKP_SubAwardData.bossName .. "-替补"
        WebDKP_Print("设置默认原因: " .. WebDKP_SubAwardData.reason)
    else
        WebDKP_SubAwardData.reason = "替补" -- 当bossName为空时使用默认值
        WebDKP_Print("设置默认原因(空bossName): " .. WebDKP_SubAwardData.reason)
    end
    

    
    if not WebDKP_SubAwardData.frame then
        WebDKP_CreateSubAwardFrame()
    end
    
    local frame = WebDKP_SubAwardData.frame
    if frame then
        -- 更新UI显示
        frame.bossNameText:SetText("BOSS: " .. WebDKP_SubAwardData.bossName)
        frame.captainEditBox:SetText(WebDKP_SubAwardData.captain)
        frame.reasonEditBox:SetText(WebDKP_SubAwardData.reason)
        frame.pointsEditBox:SetText(WebDKP_SubAwardData.points)
        

        
        -- 如果需要设置替补队长，显示提示消息
        if requireCaptainSetup then
            if not WebDKP_SubAwardData.setupNotice then
                WebDKP_SubAwardData.setupNotice = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                WebDKP_SubAwardData.setupNotice:SetPoint("TOP", 0, -35)
                WebDKP_SubAwardData.setupNotice:SetTextColor(1, 0.5, 0) -- 橙色文字
            end
            WebDKP_SubAwardData.setupNotice:SetText("请设置替补队长后再进行操作")
            WebDKP_SubAwardData.setupNotice:Show()
        else
            -- 隐藏提示消息
            if WebDKP_SubAwardData.setupNotice then
                WebDKP_SubAwardData.setupNotice:Hide()
            end
        end
        
        -- 清空之前的队员列表
        if WebDKP_PendingSubMembers then
            WebDKP_PendingSubMembers = {}
        end
        
        -- 激活状态
        WebDKP_SubAwardData.active = true
        
        -- 显示窗口
        frame:Show()
        
        -- 隐藏BOSS奖励窗口
        if WebDKP_BossAwardData.frame then
            WebDKP_BossAwardData.frame:Hide()
        end
    end
end

-- ================================
-- 搜索替补队员
-- ================================
function WebDKP_SearchSubMembers()
	-- 确保WebDKP_SubAwardData对象存在并包含所有必要字段
    if not WebDKP_SubAwardData then
        WebDKP_SubAwardData = {
            active = false,
            captain = "",
            reason = "",
            points = 0,
            bossName = ""
        }
        WebDKP_Print("警告: WebDKP_SubAwardData 未初始化，已创建默认对象")
    end
   
	-- 确保所有必要字段都有默认值
    WebDKP_SubAwardData.captain =  WebDKP_SubAwardData.captain or ""
    WebDKP_SubAwardData.reason = WebDKP_SubAwardData.reason or ""
    WebDKP_SubAwardData.points =  WebDKP_SubAwardData.points or 0
    WebDKP_SubAwardData.bossName = WebDKP_SubAwardData.bossName or ""
    
	-- 从UI获取最新的队长名称 - 修复从正确的UI元素获取数据
    if WebDKP_AwardDKP_FrameSubLeader then
        WebDKP_SubAwardData.captain = WebDKP_AwardDKP_FrameSubLeader:GetText()
    elseif WebDKP_SubAwardData.frame and WebDKP_SubAwardData.frame.captainEditBox then
        WebDKP_SubAwardData.captain = WebDKP_SubAwardData.frame.captainEditBox:GetText()
    end
    
    local captain = ""
    if WebDKP_SubAwardFrame and WebDKP_SubAwardFrame.captainEditBox then
        captain = WebDKP_SubAwardFrame.captainEditBox:GetText() or ""
    end
    captain = captain or WebDKP_SubAwardData.captain
    if not captain or captain == "" then
        WebDKP_Print("请输入替补队队长名称")
        return
    end
    
	-- 初始化或清空替补队员列表
    if not WebDKP_PendingSubMembers then
        WebDKP_PendingSubMembers = {}
    end
    
	-- 清空之前可能存在的该队长的队员信息
    WebDKP_PendingSubMembers[string.lower(captain)] = nil
    WebDKP_PendingSubMembers[captain] = nil
    
	-- 直接向队长发送耳语消息，不再检查是否在团队中
    WebDKP_Print("搜索替补队员: " .. captain)
    
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
    if not WebDKP_SubAwardData.timer then
        WebDKP_SubAwardData.timer = CreateFrame("Frame")
    end
    
	-- 重置响应标志
    WebDKP_SubAwardData.receivedResponse = false
    

end



-- ================================
-- 为替补队员加分
-- ================================
-- 添加缺失的WebDKP_AwardSubPoints_Event函数，解决UI按钮点击错误
-- ================================
-- 为所有团队成员加分
-- ================================
-- 添加缺失的WebDKP_AwardAllDKP_Event函数，解决UI按钮点击错误
function WebDKP_AwardAllDKP_Event()
	-- 优先使用WebDKP_BossAwardData中的数据（击杀弹窗调用时）
    local points = WebDKP_BossAwardData and WebDKP_BossAwardData.points or WebDKP_AwardDKP_FramePoints:GetText();
    
	-- 固定使用"击杀-boss名称"格式作为项目名称，不使用玩家填写的内容
    local reason = "";
    if WebDKP_BossAwardData and WebDKP_BossAwardData.bossName then
        reason = "击杀-" .. WebDKP_BossAwardData.bossName;

    else
        -- 非击杀弹窗调用时，使用输入框的内容
        reason = WebDKP_AwardDKP_FrameReason:GetText();
    end

    if (points == nil or points == "") then
        WebDKP_Print("您必须输入DKP.");
        PlaySound("igQuestFailed");
        return;
    end
    
    points = WebDKP_ROUND(points, 2);
    
	-- 确保points是有效数字
    if (type(points) ~= "number" or points ~= points) then
        WebDKP_Print("DKP点数必须是有效数字.");
        PlaySound("igQuestFailed");
        return;
    end
    
	-- 获取所有团队成员
    local players = WebDKP_GetAllRaidMembers();
    
    local isEmpty = true
    if players ~= nil then
        for k, v in pairs(players) do
            isEmpty = false
            break
        end
    end
    if (players == nil or isEmpty) then
        WebDKP_Print("没有找到团队成员. 奖惩无效.");
        PlaySound("igQuestFailed");
    else
        WebDKP_AddDKP(points, reason, "false", players);
        WebDKP_AnnounceAward(points, reason);

        -- 更新表格显示
        WebDKP_UpdateTableToShow();
        WebDKP_UpdateTable();
        
        -- 同时更新数据列表
        if WebDKP_UpdateLootList then
            WebDKP_UpdateLootList();
        end
        

    end
end

-- 获取所有团队成员
function WebDKP_GetAllRaidMembers()
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
                    class = WebDKP_GetPlayerClass(name) or "战士"
                };
            end
        end
    else
        -- 如果不在团队中，至少包括自己
        local playerName = UnitName("player");
        playerCount = playerCount + 1;
        players[playerCount] = {
            name = playerName,
            class = WebDKP_GetPlayerClass(playerName) or "战士"
        };
    end
    
    if playerCount > 0 then
        return players;
    else
        return nil;
    end
end

-- 将英文职业名规范化为中文（用于显示）
function WebDKP_NormalizeClassName(className)
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
local function WebDKP_GetSubMembersForAward()
    local subPlayers = {}
    local subCount = 0
    local captain = ""
    local includeSubCaptain = WebDKP_Options and WebDKP_Options["IncludeSubCaptain"]
    local lowerCaptain = nil

    if WebDKP_AwardDKP_FrameSubLeader then
        captain = WebDKP_AwardDKP_FrameSubLeader:GetText() or ""
    end
    if captain == "" and WebDKP_SubAwardData and WebDKP_SubAwardData.captain then
        captain = WebDKP_SubAwardData.captain or ""
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

    if WebDKP_PendingSubMembers and captain ~= "" then
        local targetKey = nil
        local lowerCaptainKey = string.lower(captain)

        if WebDKP_PendingSubMembers[captain] then
            targetKey = captain
        elseif WebDKP_PendingSubMembers[lowerCaptainKey] then
            targetKey = lowerCaptainKey
        else
            for key, _ in pairs(WebDKP_PendingSubMembers) do
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
            for memberName, entry in pairs(WebDKP_PendingSubMembers[targetKey]) do
                if lowerCaptainForList and string.lower(memberName) == lowerCaptainForList then
                    -- skip sub captain when unchecked
                elseif not WebDKP_PlayerInGroup(memberName) then
                    subCount = subCount + 1
                    local className = nil
                    if type(entry) == "table" and entry.class and entry.class ~= "" then
                        className = entry.class
                    elseif type(entry) == "string" and entry ~= "" then
                        className = entry
                    end
                    if not className then
                        className = WebDKP_GetPlayerClass(memberName) or "战士"
                    end
                    subPlayers[subCount] = {
                        name = memberName,
                        class = WebDKP_NormalizeClassName(className)
                    }
                end
            end
        end
    end

    if subCount == 0 and WebDKP_SubData and WebDKP_SubData.subs then
        for memberName, info in pairs(WebDKP_SubData.subs) do
            if lowerCaptain and string.lower(memberName) == lowerCaptain then
                -- skip sub captain when unchecked
            elseif not WebDKP_PlayerInGroup(memberName) then
                subCount = subCount + 1
                local className = (info and info.class) or WebDKP_GetPlayerClass(memberName) or "战士"
                subPlayers[subCount] = {
                    name = memberName,
                    class = WebDKP_NormalizeClassName(className)
                }
            end
        end
    end

    if subCount == 0 then
        return nil, 0
    end

    return subPlayers, subCount
end

function WebDKP_AwardRaidAndSub_Event_LegacyUnused()
    local pointsText = ""
    local reason = ""

    if WebDKP_AwardDKP_FramePoints then
        pointsText = WebDKP_AwardDKP_FramePoints:GetText() or ""
    end
    if WebDKP_AwardDKP_FrameReason then
        reason = WebDKP_AwardDKP_FrameReason:GetText() or ""
    end

    if pointsText == "" then
        WebDKP_Print("您必须输入DKP.");
        PlaySound("igQuestFailed");
        return
    end

    local points = WebDKP_ROUND(pointsText, 2)
    if (type(points) ~= "number" or points ~= points) then
        WebDKP_Print("DKP点数必须是有效数字");
        PlaySound("igQuestFailed");
        return
    end

    local function beginAward()
        local captain = ""
        if WebDKP_AwardDKP_FrameSubLeader then
            captain = WebDKP_AwardDKP_FrameSubLeader:GetText() or ""
        end

        -- Update subs from captain if provided.
        if captain ~= "" and WebDKP_SearchSubMembers_Event then
            WebDKP_SearchSubMembers_Event()
        end

        local function doAward()
            if WebDKP_UpdatePlayersInGroup then
                WebDKP_UpdatePlayersInGroup()
            end

            local raidPlayers = WebDKP_GetAllRaidMembers()
            local raidCount = 0
            if raidPlayers then
                for _, _ in pairs(raidPlayers) do
                    raidCount = raidCount + 1
                end
            end

            local awardedRaidCount = 0
            if raidCount > 0 then
                WebDKP_AddDKP(points, reason, "false", raidPlayers)
                WebDKP_AnnounceAward(points, reason)
                awardedRaidCount = raidCount
            end

            local subPlayers, subCount = WebDKP_GetSubMembersForAward()
            local awardedSubCount = 0
            if not subPlayers then
                WebDKP_Print("未找到替补队员名单，请先点击搜索替补队员。")
                subCount = 0
            else
                local useHalf = false
                if WebDKP_AwardDKP_FrameSubHalfPoints then
                    useHalf = WebDKP_AwardDKP_FrameSubHalfPoints:GetChecked() and true or false
                elseif WebDKP_Options then
                    useHalf = WebDKP_Options["SubHalfPointsEnabled"] and true or false
                end

                local sameReason = false
                if WebDKP_AwardDKP_FrameSubSameReason then
                    sameReason = WebDKP_AwardDKP_FrameSubSameReason:GetChecked() and true or false
                elseif WebDKP_Options then
                    sameReason = WebDKP_Options["SubSameReasonEnabled"] and true or false
                end

                local subPoints = points
                if useHalf then
                    subPoints = WebDKP_ROUND(points / 2, 2)
                end

                local subReason = reason
                if not sameReason then
                    if subReason == "" then
                        subReason = "替补"
                    else
                        subReason = subReason .. "-替补"
                    end
                end

                WebDKP_AddDKP(subPoints, subReason, "false", subPlayers)
                WebDKP_AnnounceAward(subPoints, subReason)
                WebDKP_Print("已为 " .. subCount .. " 名替补加分: " .. subPoints)
                awardedSubCount = subCount
            end

            WebDKP_UpdateTableToShow()
            WebDKP_UpdateTable()
            if WebDKP_UpdateLootList then
                WebDKP_UpdateLootList()
            end

            if awardedRaidCount > 0 or awardedSubCount > 0 then
                local announceText = "已为团队" .. awardedRaidCount .. "和替补" .. awardedSubCount .. "调整DKP " .. points
                local channel = "NONE"
                if GetNumRaidMembers() > 0 then
                    channel = "RAID"
                elseif GetNumPartyMembers() > 0 then
                    channel = "PARTY"
                end
	                if WebDKP_SendAnnouncement then
	                    WebDKP_SendAnnouncement(announceText, channel)
	                elseif SendChatMessage then
	                    local isSilentMode = WebDKP_Options and WebDKP_Options["SilentMode"]
	                    if channel == "NONE" then
	                        WebDKP_Print(announceText)
	                    elseif isSilentMode then
	                        WebDKP_Print("[静默] " .. announceText)
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

        if not WebDKP_SubAwardData then
            WebDKP_SubAwardData = {}
        end
        WebDKP_SubAwardData.receivedResponse = false

        local waitFrame = CreateFrame("Frame")
        waitFrame.startTime = GetTime()
        waitFrame:SetScript("OnUpdate", function()
            local frame = this or waitFrame
            local elapsed = GetTime() - (frame.startTime or 0)
            local responded = WebDKP_SubAwardData and WebDKP_SubAwardData.receivedResponse
            if responded or elapsed >= 2 then
                frame:SetScript("OnUpdate", nil)
                doAward()
            end
        end)
    end

    if not StaticPopupDialogs then
        StaticPopupDialogs = {}
    end
    if not StaticPopupDialogs["WEBDKP_AWARD_RAID_SUB_CONFIRM"] then
        StaticPopupDialogs["WEBDKP_AWARD_RAID_SUB_CONFIRM"] = {
            text = "",
            button1 = "确定",
            button2 = "取消",
            OnAccept = function()
                local dialog = StaticPopupDialogs["WEBDKP_AWARD_RAID_SUB_CONFIRM"]
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
    StaticPopupDialogs["WEBDKP_AWARD_RAID_SUB_CONFIRM"].text = "确定要为团队和替补调整DKP吗？\n分数: " .. points .. "\n原因: " .. reasonText
    StaticPopupDialogs["WEBDKP_AWARD_RAID_SUB_CONFIRM"]._confirmCallback = beginAward
    StaticPopup_Show("WEBDKP_AWARD_RAID_SUB_CONFIRM")
end

local function WebDKP_Z_GetCaptainName()
    local captain = ""
    if WebDKP_Options_FrameSubLeader then
        captain = WebDKP_Options_FrameSubLeader:GetText() or ""
    end
    if captain == "" and WebDKP_AwardDKP_FrameSubLeader then
        captain = WebDKP_AwardDKP_FrameSubLeader:GetText() or ""
    end
    if captain == "" and WebDKP_SubAwardData and WebDKP_SubAwardData.captain then
        captain = WebDKP_SubAwardData.captain or ""
    end
    if captain == "" and WebDKP_Options and WebDKP_Options["SubSettings"] and WebDKP_Options["SubSettings"].captain then
        captain = WebDKP_Options["SubSettings"].captain or ""
    end
    captain = WebDKP_TrimText(captain)
    return captain
end

local function WebDKP_Z_SearchSubsThenRun(callback)
    local captain = WebDKP_Z_GetCaptainName()
    if captain == "" then
        WebDKP_Print("错误：请先设置替补队长。")
        return
    end

    if WebDKP_AwardDKP_FrameSubLeader then
        WebDKP_AwardDKP_FrameSubLeader:SetText(captain)
    end
    if not WebDKP_SubAwardData then
        WebDKP_SubAwardData = {}
    end
    WebDKP_SubAwardData.captain = captain
    WebDKP_SubAwardData.receivedResponse = false

    -- 强制查询：保持 ForceQuery=true 直到收到真实响应或超时
    if WebDKP_SearchSubMembers_Event then
        WebDKP_SubSync_ForceQuery = true
        WebDKP_SearchSubMembers_Event()
    end

    local waitFrame = CreateFrame("Frame")
    waitFrame.startTime = GetTime()
    waitFrame:SetScript("OnUpdate", function()
        local frame = this or waitFrame
        local elapsed = GetTime() - (frame.startTime or 0)
        local responded = WebDKP_SubAwardData and WebDKP_SubAwardData.receivedResponse
        if responded then
            frame:SetScript("OnUpdate", nil)
            WebDKP_SubSync_ForceQuery = false
            if callback then
                callback()
            end
        elseif elapsed >= 2 then
            frame:SetScript("OnUpdate", nil)
            WebDKP_SubSync_ForceQuery = false
            -- 替补队长超时未响应：中止操作，提示用户
            WebDKP_Print("[WebDKP] 警告：无法获取替补数据，请确认替补队长 [" .. captain .. "] 是否在线并安装了本插件。")
            WebDKP_Print("[WebDKP] 本次操作已中止，请先进行替补同步再重试。")
        end
    end)
end

local function WebDKP_Z_ApplyAward(raidPoints, subPoints, reason)
    if WebDKP_UpdatePlayersInGroup then
        WebDKP_UpdatePlayersInGroup()
    end

    local raidPlayers = WebDKP_GetAllRaidMembers()
    local raidCount = 0
    if raidPlayers then
        for _, _ in pairs(raidPlayers) do
            raidCount = raidCount + 1
        end
    end

    local awardedRaidCount = 0
    if raidPlayers and raidCount > 0 then
        WebDKP_AddDKP(raidPoints, reason, "false", raidPlayers)
        WebDKP_AnnounceAward(raidPoints, reason)
        awardedRaidCount = raidCount
    end

    local subPlayersAll, subCountAll = WebDKP_GetSubMembersForAward()
    local awardedSubCount = 0
    if subPlayersAll and subCountAll > 0 then
        local subReason = reason
        if subReason == "" then
            subReason = "替补"
        else
            subReason = subReason .. "-替补"
        end
        WebDKP_AddDKP(subPoints, subReason, "false", subPlayersAll)
        WebDKP_AnnounceAward(subPoints, subReason)
        awardedSubCount = subCountAll
    end

    WebDKP_UpdateTableToShow()
    WebDKP_UpdateTable()
    if WebDKP_UpdateLootList then
        WebDKP_UpdateLootList()
    end

    if awardedRaidCount > 0 or awardedSubCount > 0 then
        local announceText = "已按主替独立分值调整DKP，主团" .. awardedRaidCount .. "，替补" .. awardedSubCount
        local channel = "NONE"
        if GetNumRaidMembers() > 0 then
            channel = "RAID"
        elseif GetNumPartyMembers() > 0 then
            channel = "PARTY"
        end
        if WebDKP_SendAnnouncement then
            WebDKP_SendAnnouncement(announceText, channel)
        elseif SendChatMessage then
            local isSilentMode = WebDKP_Options and WebDKP_Options["SilentMode"]
            if channel == "NONE" then
                WebDKP_Print(announceText)
            elseif isSilentMode then
            WebDKP_Print("[静默] " .. announceText)
            else
            SendChatMessage(announceText, channel)
            end
        end
    end
end

local function WebDKP_Z_ShowConfirm(mode, raidPoints, subPoints, reason)
    if not StaticPopupDialogs then
        StaticPopupDialogs = {}
    end
    if not StaticPopupDialogs["WEBDKP_Z_CONFIRM"] then
        StaticPopupDialogs["WEBDKP_Z_CONFIRM"] = {
            text = "",
            button1 = "确定",
            button2 = "取消",
            OnAccept = function()
                local dialog = StaticPopupDialogs["WEBDKP_Z_CONFIRM"]
                if dialog and dialog._confirmCallback then
                    dialog._confirmCallback()
                end
            end,
            timeout = 0,
            whileDead = 1,
            hideOnEscape = 1
        }
    end

    local confirmText = "确认执行主替分值操作吗？\n主队: " .. raidPoints .. "\n替补: " .. subPoints .. "\n原因: " .. reason
    StaticPopupDialogs["WEBDKP_Z_CONFIRM"].text = confirmText
    StaticPopupDialogs["WEBDKP_Z_CONFIRM"]._confirmCallback = function()
        if WebDKP_Z_Frame then
            WebDKP_Z_Frame:Hide()
        end
        WebDKP_Z_SearchSubsThenRun(function()
            WebDKP_Z_ApplyAward(raidPoints, subPoints, reason)
        end)
    end
    StaticPopup_Show("WEBDKP_Z_CONFIRM")
end

function WebDKP_Z_Submit(mode)
    if not WebDKP_Z_Frame or not WebDKP_Z_Frame.rows then
        return
    end
    local row = WebDKP_Z_Frame.rows[mode]
    if not row then
        return
    end

    local raidPoints = tonumber(row.raidEdit:GetText() or "")
    local subPoints = tonumber(row.subEdit:GetText() or "")
    if not raidPoints or not subPoints then
        WebDKP_Print("错误：主队分数和替补分数都必须是数字。")
        return
    end

    local reason = ""
    if mode == "rally" then
        reason = "集合分"
    elseif mode == "kill" then
        local inputReason = ""
        if row.reasonEdit then
            inputReason = WebDKP_TrimText(row.reasonEdit:GetText() or "")
        end
        if inputReason == "" then
            local targetName = UnitName("target")
            if not targetName or targetName == "" then
                WebDKP_Print("错误：请先选中目标，或填写击杀原因。")
                return
            end
            inputReason = targetName
        end
        reason = "击杀-" .. inputReason
    elseif mode == "dismiss" then
        reason = "解散分"
    elseif mode == "adjust" then
        local inputReason = ""
        if row.reasonEdit then
            inputReason = WebDKP_TrimText(row.reasonEdit:GetText() or "")
        end
        if inputReason == "" then
            inputReason = "分数调整"
        end
        reason = inputReason
    else
        return
    end

    WebDKP_Z_ShowConfirm(mode, raidPoints, subPoints, reason)
end

local WebDKP_Z_EditSerial = 0
local function WebDKP_Z_CreateEdit(parent, x, y, width)
    WebDKP_Z_EditSerial = WebDKP_Z_EditSerial + 1
    local editName = "WebDKP_Z_EditBox" .. tostring(WebDKP_Z_EditSerial)
    local edit = CreateFrame("EditBox", editName, parent, "InputBoxTemplate")
    edit:SetAutoFocus(false)
    edit:SetWidth(width)
    edit:SetHeight(22)
    edit:SetPoint("TOPLEFT", x, y)
    edit:SetFontObject("ChatFontNormal")
    edit:SetTextInsets(4, 4, 0, 0)
    edit:SetScript("OnEscapePressed", function()
        this:ClearFocus()
    end)
    return edit
end

local function WebDKP_Z_CreateRow(frame, key, y, buttonText, reasonEditable)
    local row = {}
    row.raidEdit = WebDKP_Z_CreateEdit(frame, 20, y, 65)
    row.subEdit = WebDKP_Z_CreateEdit(frame, 110, y, 65)
    row.raidEdit:SetNumeric(true)
    row.subEdit:SetNumeric(true)

    if reasonEditable then
        row.reasonEdit = WebDKP_Z_CreateEdit(frame, 200, y, 150)
    else
        row.reasonLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.reasonLabel:SetPoint("TOPLEFT", 265, y - 5)
        row.reasonLabel:SetText("\\")
    end

    row.button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    row.button:SetWidth(120)
    row.button:SetHeight(22)
    row.button:SetPoint("TOPLEFT", 365, y - 2)
    row.button:SetText(buttonText)
    row.button:SetScript("OnClick", function()
        WebDKP_Z_Submit(key)
    end)

    frame.rows[key] = row
end

function WebDKP_Z_RefreshFrame()
    if not WebDKP_Z_Frame then
        return
    end
end

function WebDKP_Z_ShowFrame()
    if not WebDKP_Z_Frame then
        local frame = CreateFrame("Frame", "WebDKP_Z_Frame", UIParent)
        frame:SetWidth(500)
        frame:SetHeight(260)
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        frame:SetFrameStrata("DIALOG")
        frame:EnableMouse(true)
        frame:SetMovable(true)
        frame:RegisterForDrag("LeftButton")
        frame:SetScript("OnDragStart", function()
            this:StartMoving()
        end)
        frame:SetScript("OnDragStop", function()
            this:StopMovingOrSizing()
        end)
        frame:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true,
            tileSize = 32,
            edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 }
        })

        local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOP", frame, "TOP", 0, -12)
        title:SetText("主替分值面板")

        local header1 = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        header1:SetPoint("TOPLEFT", 20, -38)
        header1:SetText("主队分数")
        local header2 = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        header2:SetPoint("TOPLEFT", 110, -38)
        header2:SetText("替补分数")
        local header3 = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        header3:SetPoint("TOPLEFT", 200, -38)
        header3:SetText("原因")
        local header4 = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        header4:SetPoint("TOPLEFT", 365, -38)
        header4:SetText("操作")

ame.rows = {}
        WebDKP_Z_CreateRow(frame, "rally", -95, "主替集合分", false)
        WebDKP_Z_CreateRow(frame, "kill", -125, "主替击杀boss", true)
        WebDKP_Z_CreateRow(frame, "dismiss", -155, "主替解散分", false)
        WebDKP_Z_CreateRow(frame, "adjust", -185, "主替分数调整", true)

        local closeBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        closeBtn:SetWidth(80)
        closeBtn:SetHeight(22)
        closeBtn:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -16, 16)
        closeBtn:SetText("关闭")
        closeBtn:SetScript("OnClick", function()
            frame:Hide()
        end)

        frame:SetScript("OnShow", function()
            WebDKP_Z_RefreshFrame()
        end)

        frame:Hide()
        WebDKP_Z_Frame = frame
    end

    WebDKP_Z_RefreshFrame()
    WebDKP_Z_Frame:Show()
end

-- ================================
-- 快捷浮窗：集 / 散 / 杀 / 调
-- 说明：
-- 1) 仅在 RAID 团队中显示（GetNumRaidMembers() > 0）
-- 2) 在“自用”Tab 勾选 WebDKP_Options["QuickFloatEnabled"] 后才显示
-- 3) 左键：按已保存的默认分值执行（带确认）
-- 4) 右键：弹出设置小窗；集/散/杀设置主队和替补分值，调设置分数/玩家/原因
-- 语义对应：
-- - 集：等同 /dkp a（原因=集合分，受排除未报名/未出勤扣分影响）
-- - 散：等同 /dkp b（原因=解散分）
-- - 杀：等同 /dkp k（原因=击杀-目标名/原因）
-- - 调：等同 /dkp c（单目标奖惩；玩家可选，缺省当前目标；原因可选，缺省=菜出天际-犯错）
-- 注意：集/散/杀使用主队/替补独立分值；调始终是单目标奖惩

local function WebDKP_QuickFloat_InitOptions()
    if not WebDKP_Options then
        WebDKP_Options = {}
    end
    if WebDKP_Options["QuickFloatEnabled"] == nil then
        WebDKP_Options["QuickFloatEnabled"] = false
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

local function WebDKP_QuickFloat_GetSettings(key)
    WebDKP_QuickFloat_InitOptions()
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

local function WebDKP_QuickFloat_SetSettings(key, raidPoints, subPoints, reason)
    WebDKP_QuickFloat_InitOptions()
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

local function WebDKP_QuickFloat_GetActionLabel(key)
    if key == "rally" then return "集" end
    if key == "dismiss" then return "散" end
    if key == "kill" then return "杀" end
    if key == "adjust" then return "调" end
    return "?"
end

local function WebDKP_QuickFloat_GetActionName(key)
    if key == "rally" then return "集合分" end
    if key == "dismiss" then return "解散分" end
    if key == "kill" then return "击杀" end
    if key == "adjust" then return "分数调整" end
    return ""
end

local function WebDKP_QuickFloat_ShowConfirm(text, onAccept)
    if not StaticPopupDialogs then
        StaticPopupDialogs = {}
    end
    if not StaticPopupDialogs["WEBDKP_QUICKFLOAT_CONFIRM"] then
        StaticPopupDialogs["WEBDKP_QUICKFLOAT_CONFIRM"] = {
            text = "",
            button1 = "确定",
            button2 = "取消",
            OnAccept = function()
                local dialog = StaticPopupDialogs["WEBDKP_QUICKFLOAT_CONFIRM"]
                if dialog and dialog._confirmCallback then
                    dialog._confirmCallback()
                end
            end,
            timeout = 0,
            whileDead = 1,
            hideOnEscape = 1
        }
    end
    StaticPopupDialogs["WEBDKP_QUICKFLOAT_CONFIRM"].text = text
    StaticPopupDialogs["WEBDKP_QUICKFLOAT_CONFIRM"]._confirmCallback = onAccept
    StaticPopup_Show("WEBDKP_QUICKFLOAT_CONFIRM")
end

local function WebDKP_QuickFloat_SearchSubsThenRun(callback)
    -- 每次全团加分都强制向替补队长重新请求最新名单，不使用缓存。
    local captain = ""
    if WebDKP_Z_GetCaptainName then
        captain = WebDKP_Z_GetCaptainName()
    end

    -- 没有配置替补队长：直接执行（仅主团加分）
    if captain == "" or not WebDKP_SearchSubMembers_Event then
        if callback then callback() end
        return
    end

    if WebDKP_AwardDKP_FrameSubLeader then
        WebDKP_AwardDKP_FrameSubLeader:SetText(captain)
    end
    if not WebDKP_SubAwardData then
        WebDKP_SubAwardData = {}
    end
    WebDKP_SubAwardData.captain = captain
    WebDKP_SubAwardData.receivedResponse = false

    -- 强制查询：保持 ForceQuery=true 直到收到真实响应或超时
    -- 防止 waitFrame 期间其他路径调用 SearchSubMembers 时命中缓存
    WebDKP_SubSync_ForceQuery = true
    WebDKP_SearchSubMembers_Event()

    local waitFrame = CreateFrame("Frame")
    waitFrame.startTime = GetTime()
    waitFrame:SetScript("OnUpdate", function()
        local frame = this or waitFrame
        local elapsed = GetTime() - (frame.startTime or 0)
        local responded = WebDKP_SubAwardData and WebDKP_SubAwardData.receivedResponse
        if responded then
            frame:SetScript("OnUpdate", nil)
            WebDKP_SubSync_ForceQuery = false
            if callback then callback() end
        elseif elapsed >= 2 then
            frame:SetScript("OnUpdate", nil)
            WebDKP_SubSync_ForceQuery = false
            -- 替补队长超时未响应：中止加分，提示用户
            WebDKP_Print("[WebDKP] 警告：无法获取替补数据，请确认替补队长 [" .. captain .. "] 是否在线并安装了本插件。")
            WebDKP_Print("[WebDKP] 本次加分已中止，主团分数未执行。")
        end
    end)
end

local function WebDKP_RunRaidAndSubAward(raidPoints, subPoints, reason)
    WebDKP_QuickFloat_SearchSubsThenRun(function()
        WebDKP_Z_ApplyAward(raidPoints, subPoints, reason)
    end)
end

local function WebDKP_QuickFloat_IsSubMember(name)
    if not name or name == "" then
        return false
    end
    local lowerName = string.lower(name)
    if WebDKP_SubData and WebDKP_SubData.subs then
        for memberName, _ in pairs(WebDKP_SubData.subs) do
            if memberName and string.lower(memberName) == lowerName then
                return true
            end
        end
    end
    if WebDKP_SubAwardData and WebDKP_SubAwardData.members then
        local members = WebDKP_SubAwardData.members
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

local function WebDKP_QuickFloat_ExecuteRaidSub(key, raidPoints, subPoints, reason)
    WebDKP_QuickFloat_ShowConfirm(
        "确认执行【" .. WebDKP_QuickFloat_GetActionLabel(key) .. "】吗？\n主队: " .. tostring(raidPoints) .. "\n替补: " .. tostring(subPoints) .. "\n原因: " .. reason,
        function()
            WebDKP_RunRaidAndSubAward(raidPoints, subPoints, reason)
        end
    )
end

local function WebDKP_QuickFloat_ExecuteAdjust(points, playerName, reason)
    -- 完全按 /dkp c 逻辑：对单个玩家执行（默认当前目标），原因可选
    local targetName = WebDKP_TrimText(playerName or "")
    if targetName == "" then
        targetName = UnitName("target") or ""
        targetName = WebDKP_TrimText(targetName)
    end
    if targetName == "" then
        WebDKP_Print("错误：请先选中目标，或在右键设置中填写玩家。")
        return
    end

    if type(points) ~= "number" then
        WebDKP_Print("错误：请先右键设置【调】的分数。")
        return
    end

    local finalReason = WebDKP_TrimText(reason or "")
    if finalReason == "" then
        finalReason = "菜出天际-犯错"
    end

    local className = WebDKP_GetPlayerClass(targetName) or "战士"
    if WebDKP_NormalizeClassName then
        className = WebDKP_NormalizeClassName(className)
    end
    local playerTable = {{ name = targetName, class = className }}

    WebDKP_QuickFloat_ShowConfirm(
        "确认对目标执行【调】吗？\n目标: " .. targetName .. "\n分数: " .. tostring(points) .. "\n原因: " .. finalReason,
        function()
            WebDKP_AddDKP(points, finalReason, "false", playerTable)
            WebDKP_AnnounceAwardSingle(points, finalReason, targetName)
            WebDKP_UpdateTable()
            WebDKP_UpdateTableToShow()
            if WebDKP_UpdateLootList then
                WebDKP_UpdateLootList()
            end
        end
    )
end

local WebDKP_QuickFloatFrame = nil
local WebDKP_QuickFloatSettingsFrame = nil

local function WebDKP_QuickFloat_UpdateTooltip(key)
    if not GameTooltip then
        return
    end
    local v1, v2, reason = WebDKP_QuickFloat_GetSettings(key)
    local title = "快捷浮窗 - " .. WebDKP_QuickFloat_GetActionLabel(key)
    GameTooltip:SetText(title, 1, 1, 1)
    if key == "adjust" then
        local points = v1
        local player = WebDKP_TrimText(v2 or "")
        if type(points) == "number" then
            GameTooltip:AddLine("分数: " .. tostring(points), 0.8, 0.8, 0.8)
        else
            GameTooltip:AddLine("右键设置分数", 0.8, 0.8, 0.8)
        end
        if player ~= "" then
            GameTooltip:AddLine("玩家: " .. player, 0.8, 0.8, 0.8)
        end
        reason = WebDKP_TrimText(reason or "")
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
            reason = WebDKP_TrimText(reason or "")
            if reason ~= "" then
                GameTooltip:AddLine("原因: " .. reason, 0.8, 0.8, 0.8)
            else
                GameTooltip:AddLine("原因: (空)", 0.8, 0.8, 0.8)
            end
        end
    end
end

local function WebDKP_QuickFloat_ShowSettings(key)
    WebDKP_QuickFloat_InitOptions()
    if not WebDKP_QuickFloatSettingsFrame then
        local f = CreateFrame("Frame", "WebDKP_QuickFloatSettingsFrame", UIParent)
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
        f.raidEdit = CreateFrame("EditBox", "WebDKP_QuickFloatRaidEdit", f, "InputBoxTemplate")
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
        f.subEdit = CreateFrame("EditBox", "WebDKP_QuickFloatSubEdit", f, "InputBoxTemplate")
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
        f.reasonEdit = CreateFrame("EditBox", "WebDKP_QuickFloatReasonEdit", f, "InputBoxTemplate")
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
                    WebDKP_Print("错误：分数必须是数字。")
                    return
                end
                local player = WebDKP_TrimText(f.subEdit:GetText() or "")
                local reason = WebDKP_TrimText(f.reasonEdit:GetText() or "")
                WebDKP_QuickFloat_SetSettings(key, points, player, reason)
            else
                local raidPoints = tonumber(f.raidEdit:GetText() or "")
                local subPoints = tonumber(f.subEdit:GetText() or "")
                if type(raidPoints) ~= "number" or type(subPoints) ~= "number" then
                    WebDKP_Print("错误：主队/替补分数必须是数字。")
                    return
                end
                local reason = nil
                if key == "kill" then
                    reason = WebDKP_TrimText(f.reasonEdit:GetText() or "")
                end
                WebDKP_QuickFloat_SetSettings(key, raidPoints, subPoints, reason)
            end
            f:Hide()
        end)

        f:Hide()
        WebDKP_QuickFloatSettingsFrame = f
    end

    local f = WebDKP_QuickFloatSettingsFrame
    f.actionKey = key
    local v1, v2, reason = WebDKP_QuickFloat_GetSettings(key)
    f.title:SetText("快捷浮窗设置 - " .. WebDKP_QuickFloat_GetActionLabel(key) .. "（" .. WebDKP_QuickFloat_GetActionName(key) .. "）")
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

local function WebDKP_QuickFloat_OnAction(key, mouseButton)
    if mouseButton == "RightButton" then
        WebDKP_QuickFloat_ShowSettings(key)
        return
    end

    local v1, v2, reason = WebDKP_QuickFloat_GetSettings(key)
    if key == "rally" then
        local raidPoints = v1
        local subPoints = v2
        if type(raidPoints) ~= "number" or type(subPoints) ~= "number" then
            WebDKP_Print("错误：请先右键设置【集】的默认分数。")
            return
        end
        WebDKP_QuickFloat_ExecuteRaidSub("rally", raidPoints, subPoints, "集合分")
        return
    end

    if key == "dismiss" then
        local raidPoints = v1
        local subPoints = v2
        if type(raidPoints) ~= "number" or type(subPoints) ~= "number" then
            WebDKP_Print("错误：请先右键设置【散】的默认分数。")
            return
        end
        WebDKP_QuickFloat_ExecuteRaidSub("dismiss", raidPoints, subPoints, "解散分")
        return
    end

    if key == "kill" then
        local raidPoints = v1
        local subPoints = v2
        if type(raidPoints) ~= "number" or type(subPoints) ~= "number" then
            WebDKP_Print("错误：请先右键设置【杀】的默认分数。")
            return
        end
        local source = WebDKP_TrimText(reason or "")
        if source == "" then
            local targetName = UnitName("target")
            if not targetName or targetName == "" then
                WebDKP_Print("错误：请先选中目标，或右键设置击杀原因。")
                return
            end
            source = targetName
        end
        local reason = "击杀-" .. source
        WebDKP_QuickFloat_ExecuteRaidSub("kill", raidPoints, subPoints, reason)
        return
    end

    if key == "adjust" then
        local points = v1
        local player = v2
        if type(points) ~= "number" then
            WebDKP_Print("错误：请先右键设置【调】的默认分数。")
            return
        end
        WebDKP_QuickFloat_ExecuteAdjust(points, player or "", reason or "")
        return
    end
end

local function WebDKP_QuickFloat_GetFrame()
    if WebDKP_QuickFloatFrame then
        return WebDKP_QuickFloatFrame
    end

    WebDKP_QuickFloat_InitOptions()

    local f = CreateFrame("Frame", "WebDKP_QuickFloatFrame", UIParent)
    f:SetWidth(176)
    f:SetHeight(46)
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
    f.buttons = {}
    for i = 1, 4 do
        local key = keys[i]
        local btn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        btn:SetWidth(36)
        btn:SetHeight(26)
        btn:SetPoint("LEFT", f, "LEFT", 10 + (i - 1) * 40, 0)
        btn:SetText(WebDKP_QuickFloat_GetActionLabel(key))
        btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        btn:SetScript("OnClick", function()
            WebDKP_QuickFloat_OnAction(key, arg1)
        end)
        btn:SetScript("OnEnter", function()
            if GameTooltip then
                GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
                WebDKP_QuickFloat_UpdateTooltip(key)
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

    f:Hide()
    WebDKP_QuickFloatFrame = f
    return f
end

function WebDKP_QuickFloat_UpdateVisibility()
    WebDKP_QuickFloat_InitOptions()
    local enabled = WebDKP_Options and WebDKP_Options["QuickFloatEnabled"]
    local inRaid = (GetNumRaidMembers and GetNumRaidMembers() or 0) > 0
    if enabled and inRaid then
        WebDKP_QuickFloat_GetFrame():Show()
    else
        if WebDKP_QuickFloatFrame then
            WebDKP_QuickFloatFrame:Hide()
        end
    end
end

function WebDKP_AwardSubPoints_Event()
	-- 奖惩DKP界面的替补加分按钮调用此函数
	-- 优先加载替补队队长输入框内容，确保输入框的值优先级最高
	-- 确保WebDKP_SubAwardData存在
    if not WebDKP_SubAwardData then
        WebDKP_SubAwardData = {}
    end
    
	-- 从UI元素获取最新值
	-- 特别注意：替补队队长输入框的值优先级最高，无论何时都优先使用
    local captain = ""
    local reason = ""
    local points = 0
    
	-- 1. 首先获取替补队队长输入框的内容（最高优先级）
    if WebDKP_AwardDKP_FrameSubLeader then
        captain = WebDKP_AwardDKP_FrameSubLeader:GetText() or ""
        -- 直接将队长输入框的值设置到WebDKP_SubAwardData，确保优先级
        WebDKP_SubAwardData.captain = captain
    end
    
	-- 2. 获取其他输入框的值
    if WebDKP_AwardDKP_FrameSubReason then
        reason = WebDKP_AwardDKP_FrameSubReason:GetText() or ""
        WebDKP_SubAwardData.reason = reason
    end
    if WebDKP_AwardDKP_FrameSubPoints then
        local pointsText = WebDKP_AwardDKP_FrameSubPoints:GetText() or ""
        points = tonumber(pointsText) or 0
        WebDKP_SubAwardData.points = points
    end
    

    
	-- 然后调用WebDKP_AwardSubPoints处理加分
    WebDKP_AwardSubPoints()
end

-- 击杀弹窗的替补加分按钮调用此函数


-- 搜索替补队员事件处理函数
function WebDKP_SearchSubMembers_Event()
    local captain = ""
    if WebDKP_Options_FrameSubLeader then
        captain = WebDKP_Options_FrameSubLeader:GetText() or ""
    elseif WebDKP_SubAwardData then
        captain = WebDKP_SubAwardData.captain or ""
    end
    
	-- 检查是否输入了替补队长名称
    if captain == "" then
        WebDKP_Print("请输入替补队长名称")
        return
    end
    
	-- 初始化WebDKP_PendingSubMembers（如果不存在）
    if not WebDKP_PendingSubMembers then
        WebDKP_PendingSubMembers = {}
    end
    
	-- 清空之前的替补队员数据
    WebDKP_PendingSubMembers[captain] = {}
    
	-- 确保WebDKP_SubAwardData存在
    if not WebDKP_SubAwardData then
        WebDKP_SubAwardData = {}
    end
    
	-- 设置当前替补队长
    WebDKP_SubAwardData.captain = captain
    
	-- 重置响应标志
    WebDKP_SubAwardData.receivedResponse = false
    
	-- 发送查询消息给替补队长
	-- 使用SendAddonMessage发送查询消息，前缀为"AMB_TBQQ"
    local success, errorMsg = pcall(SendAddonMessage, "AMB_TBQQ", captain, "GUILD")
    if not success then
        WebDKP_Print("发送查询消息失败: " .. (errorMsg or "未知错误"))
    end
end

function WebDKP_AwardSubPoints()
	-- 确保WebDKP_SubAwardData对象存在并包含必要字段
    if not WebDKP_SubAwardData then
        WebDKP_SubAwardData = {
            captain = "",
            reason = "",
            points = 0,
            bossName = "",
            receivedResponse = false
        }
    end
    
	-- 确保所有必要字段都有默认值
    WebDKP_SubAwardData.captain = WebDKP_SubAwardData.captain or ""
    WebDKP_SubAwardData.reason = WebDKP_SubAwardData.reason or ""
    WebDKP_SubAwardData.bossName = WebDKP_SubAwardData.bossName or ""
	-- 安全地获取分数值，避免访问不存在的框架
    local pointsText = ""
    if WebDKP_SubAwardFrame and WebDKP_SubAwardFrame.pointsEditBox then
        pointsText = WebDKP_SubAwardFrame.pointsEditBox:GetText() or ""
    elseif WebDKP_AwardDKP_FrameSubPoints then
        pointsText = WebDKP_AwardDKP_FrameSubPoints:GetText() or ""
    end
    WebDKP_SubAwardData.points = tonumber(pointsText) or WebDKP_SubAwardData.points or 0
    WebDKP_SubAwardData.receivedResponse = WebDKP_SubAwardData.receivedResponse or false
    
	-- 从UI元素获取数据，特别是替补队队长输入框的内容
    local captain = ""
    local reason = ""
    local points = 0
    
	-- 1. 优先获取替补队队长输入框的内容（最高优先级）
    if WebDKP_AwardDKP_FrameSubLeader then
        captain = WebDKP_Options["SubSettings"].captain or WebDKP_AwardDKP_FrameSubLeader:GetText() or ""
        -- 确保队长输入框的值直接设置到WebDKP_SubAwardData
        WebDKP_SubAwardData.captain = captain
    end
    
	-- 2. 获取其他输入框的值
    if WebDKP_AwardDKP_FrameSubReason then
        reason = WebDKP_AwardDKP_FrameSubReason:GetText() or ""
    end
    if WebDKP_AwardDKP_FrameSubPoints then
        local pointsText = WebDKP_AwardDKP_FrameSubPoints:GetText() or ""
        points = tonumber(pointsText) or 0
    end
    
	-- 3. 如果队长输入框为空，才回退到WebDKP_SubAwardData中的值
	-- 强调：队长输入框的值优先级最高，只要不为空就使用它
    if captain == "" and WebDKP_SubAwardData then
        captain = WebDKP_SubAwardData.captain or ""
    end
	-- 对于原因和分数，可以回退到WebDKP_SubAwardData中的值
    if reason == "" then
        reason = WebDKP_SubAwardData.reason or ""
    end
    if points == 0 then
        -- 安全地获取分数值，避免访问不存在的框架
        if WebDKP_SubAwardFrame and WebDKP_SubAwardFrame.pointsEditBox then
            points = tonumber(WebDKP_SubAwardFrame.pointsEditBox:GetText()) or WebDKP_SubAwardData.points or 0
        elseif WebDKP_AwardDKP_FrameSubPoints then
            points = tonumber(WebDKP_AwardDKP_FrameSubPoints:GetText()) or WebDKP_AwardDKP_FrameSubPoints or 0
        else
            points = WebDKP_SubAwardData.points or 0
        end
    end
    
	-- 3. 更新WebDKP_SubAwardData，保持数据同步
    WebDKP_SubAwardData.captain = captain
    WebDKP_SubAwardData.reason = reason
    WebDKP_SubAwardData.points = points
    
    if captain == "" then
        WebDKP_Print("请输入替补队队长名称")
        return
    else
        WebDKP_SubAwardData.captain = captain
    end
    
	-- 自动为空白原因设置默认值
    if reason == "" then
        -- 优先使用WebDKP_BossAwardData中的bossName
        if WebDKP_BossAwardData and WebDKP_BossAwardData.bossName and WebDKP_BossAwardData.bossName ~= "" then
            reason = WebDKP_BossAwardData.bossName .. "-替补"
            WebDKP_SubAwardData.bossName = WebDKP_BossAwardData.bossName
        -- 其次使用WebDKP_SubAwardData中的bossName
        elseif WebDKP_SubAwardData.bossName and WebDKP_SubAwardData.bossName ~= "" then
            reason = WebDKP_SubAwardData.bossName .. "-替补"
        else
            reason = "替补"
        end
        WebDKP_SubAwardData.reason = reason
    else
        -- 如果原因不为空，检查是否需要更新为boss名字-替补格式
        local needsUpdate = false
        local newReason = reason
        
        -- 检查当前原因是否已经是boss名字-替补格式
        if not string.find(reason, "-替补$") then
            -- 优先使用WebDKP_BossAwardData中的bossName
            if WebDKP_BossAwardData and WebDKP_BossAwardData.bossName and WebDKP_BossAwardData.bossName ~= "" then
                newReason = WebDKP_BossAwardData.bossName .. "-替补"
                WebDKP_SubAwardData.bossName = WebDKP_BossAwardData.bossName
                needsUpdate = true
            -- 其次使用WebDKP_SubAwardData中的bossName
            elseif WebDKP_SubAwardData.bossName and WebDKP_SubAwardData.bossName ~= "" then
                newReason = WebDKP_SubAwardData.bossName .. "-替补"
                needsUpdate = true
            end
        end
        
        if needsUpdate then
            reason = newReason
            WebDKP_SubAwardData.reason = reason
        end
    end
    
	-- 确保points是数字类型并检查有效性
    local pointsNum = tonumber(points) or 0
    if pointsNum < 0 then
        WebDKP_Print("请输入有效的分数")
        return
    end
	-- 更新为有效的数字值
    points = pointsNum
    WebDKP_SubAwardData.points = pointsNum
    
	-- 确保WebDKP_PendingSubMembers已初始化
    if not WebDKP_PendingSubMembers then
        WebDKP_PendingSubMembers = {}
    end
    
	-- 检查是否有替补队员信息，不区分大小写查找
    local targetCaptainKey = nil
    local lowerCaptain = string.lower(captain)
    
	-- 1. 直接匹配原始队长名
    if WebDKP_PendingSubMembers[captain] then
        targetCaptainKey = captain
    end
    
	-- 2. 如果直接匹配失败，尝试小写匹配
    if not targetCaptainKey and WebDKP_PendingSubMembers[lowerCaptain] then
        targetCaptainKey = lowerCaptain
    end
    
	-- 3. 如果前两种都失败，遍历所有键进行不区分大小写匹配
    if not targetCaptainKey then
        for key, _ in pairs(WebDKP_PendingSubMembers) do
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
		for memberName, entry in pairs(WebDKP_PendingSubMembers[targetCaptainKey]) do
			local entryClass = nil
			if type(entry) == "table" then
				entryClass = entry.class
			end
 
			if entryClass and WebDKP_NormalizeClassName then
				entryClass = WebDKP_NormalizeClassName(entryClass)
			end
 
			local playerClass = entryClass or WebDKP_GetPlayerClass(memberName) or "战士"
 
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
            WebDKP_AddDKP(points, subReason, "false", registeredPlayers, WebDKP_BossAwardData.tableid)
            WebDKP_Print("已成功为 " .. registeredCount .. " 名替补队员加 " .. points .. " 分 (" .. subReason .. ")")
        end
        
        if registeredCount > 0 then
            WebDKP_Print("总计处理替补队员: " .. registeredCount .. " 名")
 
            local announceCaptain = targetCaptainKey or captain or ""
            if announceCaptain == "" and WebDKP_SubAwardData then
                announceCaptain = WebDKP_SubAwardData.captain or ""
            end
 
            local message = "替补加分完成: " .. subNames .. " (+" .. points .. " DKP)"
            if subReason and subReason ~= "" then
                message = message .. ", 原因: " .. subReason
            end
            message = message .. ")"
            if announceCaptain ~= "" then
                message = "替补队长" .. announceCaptain .. " 提示: " .. message
            end
 
            local tellLocation = WebDKP_GetTellLocation()
            if WebDKP_SendAnnouncement then
                WebDKP_SendAnnouncement(message, tellLocation)
            elseif SendChatMessage then
                local isSilentMode = WebDKP_Options and WebDKP_Options["SilentMode"]
                if isSilentMode then
                    WebDKP_Print("[静默] " .. message)
                elseif tellLocation == "RAID" then
                    SendChatMessage(message, "RAID")
                elseif tellLocation == "PARTY" then
                    SendChatMessage(message, "PARTY")
                end
            end
            
            -- 关闭窗口
            WebDKP_SubAwardData.active = false
            if WebDKP_SubAwardData.frame then
                WebDKP_SubAwardData.frame:Hide()
            end
        end
    end
end

-- 获取玩家职业
function WebDKP_GetPlayerClass(playerName)
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
function WebDKP_TestSubAwardSystem()
	-- 1. 检查关键对象是否存在
    WebDKP_Print("开始替补加分系统测试")
	-- 1. 检查关键对象是否存在
    WebDKP_Print("开始替补加分系统测试")
    
	-- 确保WebDKP_SubAwardData已初始化
    if not WebDKP_SubAwardData then
        WebDKP_SubAwardData = {
            captain = "",
            reason = "",
            points = 0,
            bossName = "",
            receivedResponse = false
        }
    end
    
	-- 确保WebDKP_PendingSubMembers已初始化
    if not WebDKP_PendingSubMembers then
        WebDKP_PendingSubMembers = {}
    end
    
	-- 2. 检查UI元素是否存在
    WebDKP_Print("检查UI元素状态")
    
	-- 3. 测试通信功能
    WebDKP_Print("通信功能测试")
    
	-- 测试SendAddonMessage函数是否可用
    local canSendAddonMessage = pcall(SendAddonMessage, "AMB_TBQQ", "TEST", "GUILD")
    
	-- 4. 测试事件注册
    WebDKP_Print("事件注册检查")
    
	-- 5. 提供使用说明
    WebDKP_Print("测试完成")
    WebDKP_Print("使用说明: 1.设置替补队长名称和加分信息 2.点击搜索替补队员按钮发起通信 3.等待替补队长响应后点击替补加分")
    
	-- 自动调用搜索替补队员函数进行测试
    if WebDKP_SearchSubMembers then
        WebDKP_SearchSubMembers()
    end
end

-- ================================
-- BOSS奖励事件处理
-- ================================
function WebDKP_BossAward_Event()
    local frame = WebDKP_BossAwardData.frame
    if not frame then
        return
    end
    
    local points = WebDKP_BossAwardData.points
    local bossName = WebDKP_BossAwardData.bossName
    local reason = "击杀-" .. (bossName or "未知BOSS")
    
	-- 更新团队玩家信息
    WebDKP_UpdatePlayersInGroup()
    
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
        
        -- 如果禁用了地图验证，为所有玩家加分，不管在线状态 and 地图位置
        if ( WebDKP_WebOptions["MapValidationEnabled"] ~= 1 ) then
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
            -- 从WebDKP_DkpTable中获取玩家职业信息
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
                    ["dkp_"..WebDKP_BossAwardData.tableid] = 0,
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
    local originalTableid = WebDKP_Frame.selectedTableid
    
	-- 临时设置为BOSS奖励选择的DKP列表
    WebDKP_Frame.selectedTableid = WebDKP_BossAwardData.tableid
    
	-- WebDKP_AddDKP函数内部会处理表格的检查和创建，此处无需重复处理
    
	-- 为符合条件的玩家加分
    local awardSuccess = false
    if next(playerTable) then
        awardSuccess = WebDKP_AddDKP(points, reason, "false", playerTable, WebDKP_BossAwardData.tableid)
        
        -- 恢复播报加分情况，确保boss击杀时有同步信息发送
        WebDKP_AnnounceAward(points, "击杀-" .. (WebDKP_BossAwardData.bossName or "未知BOSS"))
    else
        WebDKP_Print("没有玩家符合加分条件，加分操作已取消。")
    end
    
	-- 只有当加分成功时才播报信息
    if awardSuccess then
        -- 获取播报位置
        local tellLocation = WebDKP_GetTellLocation()
        
        -- 播报奖励信息
        local awardedCount = 0
        for _, selected in pairs(playerTable) do
            if selected then
                awardedCount = awardedCount + 1
            end
        end
        
        if awardedCount > 0 then
            local rewardMessage = points .. "点dkp奖励给" .. awardedCount .. "名团员,原因: " .. reason
            WebDKP_SendAnnouncement(rewardMessage, tellLocation)
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
            WebDKP_SendAnnouncement(announceText, tellLocation)
        end
    end
    
	-- 恢复原来的DKP列表选择
    WebDKP_Frame.selectedTableid = originalTableid
    
	-- 刷新主界面的显示，确保分数正确更新
    WebDKP_UpdateTableToShow()
    WebDKP_UpdateTable()
    
	-- 清除所有玩家的选择状态，避免影响后续操作
    for k, v in pairs(WebDKP_DkpTable) do
        if type(v) == "table" then
            v["Selected"] = false
        end
    end
    
	-- 备份数据
    WebDKP_BackupData()
    
	-- 隐藏窗口
    frame:Hide()
end

-- ================================
-- BOSS奖励窗口DKP列表下拉菜单初始化
-- ================================
function WebDKP_BossAwardTableDropdown_Init()
    local info;
    local selected = "";
    
	-- 使用WebDKP_Tables数据中的实际列表
    if ( WebDKP_Tables ~= nil and next(WebDKP_Tables)~=nil ) then
        for key, entry in pairs(WebDKP_Tables) do
            if ( type(entry) == "table" ) then
                info = { };
                info.text = entry.name or key;
                info.value = entry["id"]; 
                info.func = WebDKP_BossAwardTableDropdown_OnClick;
                if ( entry["id"] == WebDKP_BossAwardData.tableid ) then
                    info.checked = true;
                    selected = info.text;
                end
                UIDropDownMenu_AddButton(info);
            end
        end
        
        -- 设置下拉菜单显示的文本和选中状态
        if selected ~= "" then
            UIDropDownMenu_SetText(selected, WebDKP_BossAwardTableDropdown);
            -- 同时设置选中的名称，确保正确显示勾选状态
            UIDropDownMenu_SetSelectedName(WebDKP_BossAwardTableDropdown, selected);
        end
    end
end

-- ================================
-- BOSS奖励窗口DKP列表下拉菜单点击处理
-- ================================
-- In WoW 1.12 Lua 5.0, use 'this' instead of function parameters
function WebDKP_BossAwardTableDropdown_OnClick()
	-- 安全获取按钮对象 - 兼容不同调用方式
    local button = this or  (UIDropDownMenu_GetSelectedName and UIDropDownMenu_GetSelectedName(WebDKP_BossAwardTableDropdown)) or WebDKP_BossAwardTableDropdown
    
    if not button or not button.value then
        -- 尝试从全局下拉菜单状态获取
        local selectedName = UIDropDownMenu_GetText(WebDKP_BossAwardTableDropdown)
        if selectedName and WebDKP_Tables[selectedName] then
            WebDKP_BossAwardData.tableid = WebDKP_Tables[selectedName]["id"]
            WebDKP_BossAwardTableDropdown_Init()
            return
        end
        return
    end
    
    WebDKP_BossAwardData.tableid = button.value;
	-- 更新下拉菜单显示的文本
    UIDropDownMenu_SetText(button:GetText(), WebDKP_BossAwardTableDropdown);
	-- 直接重新初始化下拉菜单来更新选中状态，与主窗口的处理方式保持一致
    WebDKP_BossAwardTableDropdown_Init();
end

-- 全局变量：存储当前的替补活动信息
WebDKP_SubData = WebDKP_SubData or {}
-- 确保subs子表已初始化
WebDKP_SubData.subs = WebDKP_SubData.subs or {}
-- 全局变量：存储当天的替补记录
WebDKP_DailySubRecords = WebDKP_DailySubRecords or {}
-- 全局变量：存储当前活动的团队成员列表
WebDKP_CurrentRaidMembers = {}

-- ================================
-- BOSS奖励+替补事件处理
-- ================================
function WebDKP_BossAwardWithSub_Event()
    local frame = WebDKP_BossAwardData.frame
    if not frame then
        return
    end
    
	-- 确保WebDKP_SubData已初始化
    WebDKP_SubData = {
        active = true,
        points = WebDKP_BossAwardData.points,
        bossName = WebDKP_BossAwardData.bossName,
        reason = "击杀-" .. (WebDKP_BossAwardData.bossName or "未知BOSS"),
        subReason = "击杀-" .. (WebDKP_BossAwardData.bossName or "未知BOSS") .. " 替补分",
        tableid = WebDKP_BossAwardData.tableid,
        startTime = GetTime(),
        endTime = 0,
        subs = {},
        raidMembers = {},
        timerFrame = nil
    }
    
	-- 同时更新WebDKP_SubAwardData，确保bossName字段同步
    WebDKP_SubAwardData.bossName = WebDKP_BossAwardData.bossName
    WebDKP_SubAwardData.reason = (WebDKP_BossAwardData.bossName or "未知BOSS") .. "-替补"
    WebDKP_SubAwardData.points = WebDKP_BossAwardData.points
    
	-- 从UI输入框获取替补队长名称
    local captainName = ""
    if frame and frame.subCaptainEditBox then
        captainName = frame.subCaptainEditBox:GetText() or ""
    end
    
	-- 如果UI中没有输入，尝试从已保存的设置中获取
    if captainName == "" then
        if WebDKP_Options and WebDKP_Options["SubSettings"] and WebDKP_Options["SubSettings"]["captain"] then
            captainName = WebDKP_Options["SubSettings"]["captain"]
        elseif WebDKP_SubAwardData.captain and WebDKP_SubAwardData.captain ~= "" then
            captainName = WebDKP_SubAwardData.captain
        end
    end
    
	-- 如果仍然为空，使用默认值
    if captainName == "" then
        captainName = "系统"
    end
    
	-- 更新WebDKP_SubAwardData和UI中的值
    WebDKP_SubAwardData.captain = captainName
    if frame and frame.subCaptainEditBox then
        frame.subCaptainEditBox:SetText(captainName)
    end
    
    WebDKP_SubAwardData.receivedResponse = true
    
	-- 确保WebDKP_BossAwardData有正确的数据
    if not WebDKP_BossAwardData.points or WebDKP_BossAwardData.points == "" then
        WebDKP_BossAwardData.points = WebDKP_SubData.points
    end
    
	-- 调用全员加分函数
    WebDKP_AwardAllDKP_Event()
    
    WebDKP_Print("全员加分执行完成")
    DEFAULT_CHAT_FRAME:AddMessage("[WebDKP] 全员加分执行完成", 0, 1, 0)
    
	-- 确保WebDKP_SubData.points有正确的值
    if not WebDKP_SubData.points or WebDKP_SubData.points <= 0 then
        WebDKP_SubData.points = WebDKP_BossAwardData.points
    end
    
	-- 获取替补计时分钟数
    local subTimeMinutes = tonumber(frame.subTimeEditBox:GetText()) or 5
    WebDKP_SubData.endTime = WebDKP_SubData.startTime + (subTimeMinutes * 60)
    
	-- 保存当前团队成员列表到WebDKP_CurrentRaidMembers
    WebDKP_CurrentRaidMembers = {}
    if GetNumRaidMembers() > 0 then
        for i = 1, GetNumRaidMembers() do
            local name = UnitName("raid" .. i)
            if name then
                WebDKP_CurrentRaidMembers[name] = true
            end
        end
    elseif GetNumPartyMembers() > 0 then
        for i = 1, GetNumPartyMembers() do
            local name = UnitName("party" .. i)
            if name then
                WebDKP_CurrentRaidMembers[name] = true
            end
        end
        local playerName = UnitName("player")
        WebDKP_CurrentRaidMembers[playerName] = true
    else
        local playerName = UnitName("player")
        WebDKP_CurrentRaidMembers[playerName] = true
    end
    
    WebDKP_SubData.raidMembers = WebDKP_CurrentRaidMembers
    
    local subMessage = "手动替补加分活动开始！替补成员在" .. subTimeMinutes .. "分钟内私聊我 'TB' 报数进行记录，过期不候！"
    local isSilentMode = WebDKP_Options and WebDKP_Options["SilentMode"]
    if isSilentMode then
        WebDKP_Print("[静默] " .. subMessage)
    else
        SendChatMessage(subMessage, "GUILD", nil, nil)
    end
    
	-- 设置计时器，计时结束后处理替补加分
    WebDKP_SubData.timerFrame = CreateFrame("Frame")
    WebDKP_SubData.timerFrame:SetScript("OnUpdate", function()
        if GetTime() >= WebDKP_SubData.endTime then
            local frame =  WebDKP_SubData.timerFrame
            frame:SetScript("OnUpdate", nil)
            WebDKP_ProcessSubstitutes()
        end
    end)
    
	-- 隐藏窗口
    frame:Hide()
    
	-- 显示倒计时信息
    WebDKP_Print("替补加分活动已开始，将在" .. subTimeMinutes .. "分钟后结束。")
end

-- ================================
-- 处理替补加分
-- ================================
function WebDKP_ProcessSubstitutes()
    if not WebDKP_SubData or not WebDKP_SubData.active then
        return
    end
    
	-- 优先使用WebDKP_SubAwardData.points（用户输入的分数），如果没有则使用WebDKP_SubData.points
    local points = WebDKP_SubData.points
    if WebDKP_SubAwardData and WebDKP_SubAwardData.points then
        points = WebDKP_SubAwardData.points
    end
    local reason = WebDKP_SubData.subReason
    local tableid = WebDKP_SubData.tableid
    local bossName = WebDKP_SubData.bossName
    
	-- 创建替补玩家信息表
    local subPlayerTable = {}
    local subIndex = 1
    local subNames = ""
    local subDetails = {}
    
    if next(WebDKP_SubData.subs) then
        -- 保存当前选择 of DKP list
        local originalTableid = WebDKP_Frame.selectedTableid
        
        -- 临时设置为BOSS奖励选择 of DKP list
        WebDKP_Frame.selectedTableid = tableid
        
        for name, playerInfo in pairs(WebDKP_SubData.subs) do
            -- 检查玩家是否在团队/队伍中，如果在则跳过（使用小写名称进行比较）
            if WebDKP_SubData and WebDKP_SubData.raidMembers and WebDKP_SubData.raidMembers[string.lower(name)] then
                WebDKP_Print(name .. " 已经在团队中，跳过替补加分")
                -- 从WebDKP_SubData.subs中移除该玩家
                WebDKP_SubData.subs[name] = nil
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
                
                -- 确保所有在WebDKP_SubData.subs中的玩家都能获得加分
                WebDKP_AddDKP(playerPoints, playerReason, "false", {{name = name, class = class}})
                
                -- 为替补记录添加uniqueId字段
                local currentTime = date("%H:%M:%S")
                local uniqueId = "sub_" .. subIndex .. "_" .. name .. "_" .. currentTime
                
                -- 查找并更新刚添加的替补记录 of uniqueId
                if WebDKP_Log then
                    for logKey, logEntry in pairs(WebDKP_Log) do
                        if type(logEntry) == "table" and logEntry.reason == playerReason and logEntry.points == points and logEntry.awarded and logEntry.awarded[name] and not logEntry.uniqueId then
                            logEntry.uniqueId = uniqueId
                            logEntry.item = playerReason
                            WebDKP_Print("为替补记录添加uniqueId: " .. uniqueId)
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
        WebDKP_Frame.selectedTableid = originalTableid
        
        -- 播报替补加分信息
        if subNames ~= "" then
            local message = "替补加分完成: " .. subNames .. " (+" .. points .. " DKP)"

            local captainName = ""
            if WebDKP_SubAwardData then
                captainName = WebDKP_SubAwardData.captain or ""
                if captainName ~= "" and tonumber(captainName) then
                    captainName = ""
                end
            end
            if captainName ~= "" then
                message = "替补队长" .. captainName .. " 提示: " .. message
            end
            
            DEFAULT_CHAT_FRAME:AddMessage("[WebDKP] " .. message, 0, 1, 0)
            
            local tellLocation = WebDKP_GetTellLocation()
            
            if WebDKP_SendAnnouncement then
                WebDKP_SendAnnouncement(message, tellLocation)
            elseif SendChatMessage then
                local isSilentMode = WebDKP_Options and WebDKP_Options["SilentMode"]
                if isSilentMode then
                    WebDKP_Print("[静默] " .. message)
                elseif tellLocation == "RAID" then
                    SendChatMessage(message, "RAID")
                elseif tellLocation == "PARTY" then
                    SendChatMessage(message, "PARTY")
                end
            end
        end
    else
        DEFAULT_CHAT_FRAME:AddMessage("[WebDKP] 没有替补玩家需要加分", 1, 0.7, 0)
    end
    
    WebDKP_SubData.active = false
    WebDKP_SubData.subs = {}
    
    if WebDKP_SubAwardData then
        WebDKP_SubAwardData = {}
    end
    
    if WebDKP_PendingSubMembers then
        WebDKP_PendingSubMembers = {}
    end
end

-- ================================
-- 处理私密消息中的TB命令
-- ================================
-- 全局变量用于跟踪最后一次查询时间
WebDKP_LastWhoQueryTime = WebDKP_LastWhoQueryTime or 0
WebDKP_WhoQueryCooldown = 5 -- 5秒查询冷却

-- 根据名字获取公会成员信息
function WebDKP_GetGuildMemberInfoByName(name)
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

function WebDKP_HandleWhisperTB(name, message)
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
    if not WebDKP_SubData or not WebDKP_SubData.active then
        return false
    end
    
    if isTBCommand then
        -- 检查玩家是否已在团队中（已获得全员加分）
        if WebDKP_SubData.raidMembers and WebDKP_SubData.raidMembers[name] then
            local isSilentMode = WebDKP_Options and WebDKP_Options["SilentMode"]
            if not isSilentMode then
                SendChatMessage("你已经在团队中，无需申请替补。", "WHISPER", nil, name)
            else
                WebDKP_Print("[静默] " .. name .. " 已获得全员加分，无需申请替补")
            end
            return true
        end
        
        -- 检查玩家是否已经提交过申请
        if WebDKP_SubData.subs[name] then
            local isSilentMode = WebDKP_Options and WebDKP_Options["SilentMode"]
            if not isSilentMode then
                SendChatMessage("你的申请已经收录，请勿重复提交。", "WHISPER", nil, name)
            else
                WebDKP_Print("[静默] " .. name .. " 的申请已收录，请勿重复提交")
            end
            return true
        end
        
        -- 首先尝试从公会成员信息中获取玩家所在地
        local className, location = WebDKP_GetGuildMemberInfoByName(name)
        
        if className then
            local finalClass = className or "战士"
            
            WebDKP_SubData.subs[name] = {
                class = finalClass,
                location = location or "未知地点",
                locationNeedsConfirmation = true
            }
            
            -- 检查玩家是否在DKP列表中，如果不在则创建新记录
            if not WebDKP_DkpTable[name] then
                local tableid = WebDKP_SubData.tableid or WebDKP_Options.SelectedTableId or 1
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
                WebDKP_Print("[静默] 替补队员 " .. name .. " 已打卡成功")
            end
            WebDKP_Print("替补队员 " .. name .. " 已记录")
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
function WebDKP_AttemptWhoQuery(name)
	-- 记录玩家是否已发送确认消息
    if not WebDKP_SubData.whisperedPlayers then
        WebDKP_SubData.whisperedPlayers = {}
    end
    
	-- 初始化玩家数据，先使用默认值
    local finalClass = "战士" -- 默认职业
    local location = nil -- 初始化所在地变量
    local playerName = name -- 提前定义playerName变量，确保在所有代码路径中都有定义
    
	-- 检查玩家是否在报名列表中
    local isRegistered = false
    if WebDKP_SubData.registeredPlayers then
        for _, regName in ipairs(WebDKP_SubData.registeredPlayers) do
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
    WebDKP_SubData.subs[playerName] = {
        class = finalClass,
        location = finalLocation,
        isRegistered = isRegistered  -- 添加标记，记录是否已报名
    }
    
	-- 检查玩家是否在DKP列表中，如果不在则创建新记录
    if not WebDKP_DkpTable[playerName] then
        -- 获取当前使用的DKP列表ID
        local tableid = WebDKP_SubData.tableid or WebDKP_Options.SelectedTableId or 1
        
        -- 创建新的DKP记录，初始分数为0
        WebDKP_DkpTable[playerName] = {
            ["dkp_"..tableid] = 0,
            ["class"] = finalClass
        }
    end
    
	-- 只发送一次确认消息
    if not WebDKP_SubData.whisperedPlayers[name] then
        -- 静默模式下不发送私聊，仅本地记录
        local isSilentMode = WebDKP_Options and WebDKP_Options["SilentMode"]
        if not isSilentMode then
            SendChatMessage("已收录为本次替补。", "WHISPER", nil, name)
        else
            WebDKP_Print("[静默] 已收录 " .. name .. " 为本次替补")
        end
        WebDKP_SubData.whisperedPlayers[name] = true
    end
    
	-- 检查30秒冷却时间，如果可以查询且地点未知，则尝试获取位置信息
    local currentTime = GetTime()
    WebDKP_LastWhoQueryTime = WebDKP_LastWhoQueryTime or 0
    
    if (currentTime - WebDKP_LastWhoQueryTime >= 30) and finalLocation == "未知地点" then
        -- 更新最后查询时间
        WebDKP_LastWhoQueryTime = currentTime
        
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
                            if WebDKP_SubData.subs[frame.playerName] then
                                WebDKP_SubData.subs[frame.playerName].location = whoLocation
                                -- 标记位置信息已确认
                                WebDKP_SubData.subs[frame.playerName].locationNeedsConfirmation = false
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
                WebDKP_AttemptWhoQuery(frame.playerName)
            end
        end)
    end
            

end

function WebDKP_DebugCheckLootList()
	-- 检查装备记录功能是否已加载
    if WebDKP_ToggleLootList then
        -- 保存原始函数
        local originalToggleLootList = WebDKP_ToggleLootList
        
        -- 更新WebDKP_ToggleLootList，确保它能使用替代实现
        WebDKP_ToggleLootList = function()
            -- 先确保所有必要的替代函数都已创建
            if not WebDKP_CreateLootListFrame or not WebDKP_UpdateLootList or not WebDKP_GetLootRecords then
                WebDKP_DebugCheckLootList()
            end
            
            -- 然后尝试创建和显示窗口
            if WebDKP_CreateLootListFrame and WebDKP_UpdateLootList then
                local frame = WebDKP_CreateLootListFrame()
                
                if frame:IsShown() then
                    frame:Hide()
                else
                    frame:Show()
                    WebDKP_UpdateLootList()
                end
            else
                -- 如果仍然缺少必要的函数，调用原始函数作为最后的尝试
                originalToggleLootList()
            end
        end
        
        -- WebDKP_Print("WebDKP_ToggleLootList 函数已加载")
        
        -- 检查其他关键函数
        local missingFunctions = {}
        if not WebDKP_CreateLootListFrame then table.insert(missingFunctions, "WebDKP_CreateLootListFrame") end
        if not WebDKP_UpdateLootList then table.insert(missingFunctions, "WebDKP_UpdateLootList") end
        if not WebDKP_GetLootRecords then table.insert(missingFunctions, "WebDKP_GetLootRecords") end
        
        -- 检查WebDKP_CreateLootListFrame是否缺失，如果缺失则创建替代实现
        if not WebDKP_CreateLootListFrame then
            
            WebDKP_CreateLootListFrame = function()
                if not WebDKP_LootListFrame then
                    -- 主窗口
                    local frame = CreateFrame("Frame", "WebDKP_LootListFrame", WebDKP_Frame)
                    frame:SetWidth(620)
                    frame:SetHeight(400)
                    frame:SetPoint("TOPLEFT", WebDKP_Frame, "TOPLEFT", 350, -42)
                    frame:EnableMouse(true)
                    frame:SetMovable(true)
 
                    
                    -- 背景 - 设置为80%透明度
                    local bg = frame:CreateTexture(nil, "BACKGROUND")
                    bg:SetAllPoints(frame)
                    bg:SetTexture(0, 0, 0, 0.6) -- 80%透明度，只保留20%的不透明度


                     local bottomCloseButton = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
                    bottomCloseButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0,0)
                    bottomCloseButton:EnableMouse(true)
                    bottomCloseButton:Show() -- 显式显示按钮
                    bottomCloseButton:SetScript("OnClick", function()
                        frame:Hide()
                    end)

                    
                    -- 边框 - 调整为半透明以配合80%透明效果
                    local border = frame:CreateTexture(nil, "ARTWORK")
                    border:SetPoint("TOPLEFT", frame, "TOPLEFT", -2, 2)
                    border:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 2, -2)
                    border:SetTexture(0.2, 0.2, 0.2, 0.5) -- 50%透明度
                    
                    -- 标题栏 - 调整高度增加间距
                    local titleBar = CreateFrame("Frame", nil, frame)
                    titleBar:SetWidth(620)
                    titleBar:SetHeight(35) -- 增加5px高度提高标题栏间距
                    titleBar:SetPoint("TOP", frame, "TOP", 0, 0)
                    titleBar:EnableMouse(true)
                    titleBar:SetMovable(true)
                    titleBar:RegisterForDrag("LeftButton")
                    titleBar:SetScript("OnDragStart", function() frame:StartMoving() end)
                    titleBar:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)
                    
                    local titleBg = titleBar:CreateTexture(nil, "BACKGROUND")
                    titleBg:SetAllPoints(titleBar)
                    titleBg:SetTexture(0.2, 0.4, 0.6, 0.8)
                    
                    local titleText = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                    titleText:SetPoint("CENTER", titleBar, "CENTER", 0, 0)
                    titleText:SetTextColor(1, 1, 1, 1)
                    titleText:SetText("装备获取记录")
                    frame.titleText = titleText
                    
                    -- 添加导出按钮
                    local exportButton = CreateFrame("Button", nil, titleBar, "UIPanelButtonTemplate")
                    exportButton:SetWidth(80)
                    exportButton:SetHeight(22)
                    exportButton:SetText("导出数据")
                    exportButton:EnableMouse(true)
                    exportButton:Show()
                    exportButton:SetScript("OnClick", function()
                        -- 确保WebDKP_ExportCurrentData函数存在
                        if WebDKP_ExportCurrentData then
                            WebDKP_ExportCurrentData()
                        else
                            WebDKP_Print("导出功能未加载，请检查插件完整性。")
                        end
                    end)
                    
                    -- 添加模式切换按钮
                    local modeButton = CreateFrame("Button", nil, titleBar, "UIPanelButtonTemplate")
                    modeButton:SetPoint("TOPRIGHT", bottomCloseButton, "TOPLEFT", -10, -5)
                    modeButton:SetWidth(100)
                    modeButton:SetHeight(22)
                    modeButton:EnableMouse(true)
                    modeButton:Show()
                    
                    -- 设置导出按钮位置在模式切换按钮左侧
                    exportButton:SetPoint("TOPRIGHT", modeButton, "TOPLEFT", -5, 0)
                    
                    -- 保存切换状态
                    frame.currentMode = "dkp"
                    
                    -- 更新按钮文本和窗口标题
                    local function updateModeButton()
                        if frame.currentMode == "dkp" then
                            modeButton:SetText("DKP列表")
                            frame.titleText:SetText("DKP列表")
                        elseif frame.currentMode == "substitute" then
                            modeButton:SetText("替补名单")
                            frame.titleText:SetText("替补名单")
                        else
                            modeButton:SetText("装备记录")
                            frame.titleText:SetText("装备获取记录")
                        end
                    end
                    
                    -- 初始化按钮文本
                    updateModeButton()
                    
                    -- 切换按钮点击事件
                    modeButton:SetScript("OnClick", function()
                        -- 循环切换三种模式
                        if frame.currentMode == "dkp" then
                            frame.currentMode = "substitute"
                        elseif frame.currentMode == "substitute" then
                            frame.currentMode = "loot"
                        else
                            frame.currentMode = "dkp"
                        end
                        
                        -- 更新全局变量的currentMode属性，确保在任何地方都能获取到正确的模式
                        if WebDKP_LootListFrame then
                            WebDKP_LootListFrame.currentMode = frame.currentMode
                        end
                        
                        -- 更新按钮文本和窗口标题
                        updateModeButton()
                        
                        -- 更新列表内容
                        WebDKP_UpdateLootList()
                    end)
                    
                    
                    -- 保存列标题引用，以便根据模式切换
                    frame.columnHeaders = {
                        loot = {},
                        substitute = {},
                        dkp = {}
                    }
                    
                    -- 装备记录列标题
                    local col1_loot = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                    col1_loot:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -40)
                    col1_loot:SetText("物品名称")
                    col1_loot:SetWidth(175)
                    
                    local col2_loot = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                    col2_loot:SetPoint("TOPLEFT", col1_loot, "TOPRIGHT", 0, 0)
                    col2_loot:SetText("获得者")
                    col2_loot:SetWidth(120)
                    
                    local col3_loot = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                    col3_loot:SetPoint("TOPLEFT", col2_loot, "TOPRIGHT", 10, 0)
                    col3_loot:SetText("DKP花费")
                    col3_loot:SetWidth(80)
                    
                    local col4_loot = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                    col4_loot:SetPoint("TOPLEFT", col3_loot, "TOPRIGHT", 10, 0)
                    col4_loot:SetText("时间")
                    col4_loot:SetWidth(120)
                    
                    frame.columnHeaders.loot = {
                        col1_loot,
                        col2_loot,
                        col3_loot,
                        col4_loot
                    }
                    
                    -- DKP列表列标题（初始隐藏）
                    local col1_dkp = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                    col1_dkp:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -40)
                    col1_dkp:SetText("项目名称")
                    col1_dkp:SetWidth(180)
                    col1_dkp:Hide()
                    
                    local col2_dkp = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                    col2_dkp:SetPoint("TOPLEFT", col1_dkp, "TOPRIGHT", 0, 0)
                    col2_dkp:SetText("玩家人数")
                    col2_dkp:SetWidth(120)
                    col2_dkp:Hide()
                    
                    local col3_dkp = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                    col3_dkp:SetPoint("TOPLEFT", col2_dkp, "TOPRIGHT", 10, 0)
                    col3_dkp:SetText("分数")
                    col3_dkp:SetWidth(80)
                    col3_dkp:Hide()
                    
                    local col4_dkp = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                    col4_dkp:SetPoint("TOPLEFT", col3_dkp, "TOPRIGHT", 10, 0)
                    col4_dkp:SetText("时间")
                    col4_dkp:SetWidth(120)
                    col4_dkp:Hide()
                    
                    frame.columnHeaders.dkp = {
                        col1_dkp,
                        col2_dkp,
                        col3_dkp,
                        col4_dkp
                    }
                    
                    -- 替补名单列标题（初始隐藏）
                    local col1_sub = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                    col1_sub:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -40)
                    col1_sub:SetText("项目名称")
                    col1_sub:SetWidth(170)
                    col1_sub:Hide()
                    
                    local col2_sub = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                    col2_sub:SetPoint("TOPLEFT", col1_sub, "TOPRIGHT", 0, 0)
                    col2_sub:SetText("玩家名称")
                    col2_sub:SetWidth(120)
                    col2_sub:Hide()
                    
                    local col3_sub = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                    col3_sub:SetPoint("TOPLEFT", col2_sub, "TOPRIGHT", 10, 0)
                    col3_sub:SetText("所在地")
                    col3_sub:SetWidth(100)
                    col3_sub:Hide()
                    
                    local col4_sub = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                    col4_sub:SetPoint("TOPLEFT", col3_sub, "TOPRIGHT", 10, 0)
                    col4_sub:SetText("加分时间")
                    col4_sub:SetWidth(120)
                    col4_sub:Hide()
                    
                    frame.columnHeaders.substitute = {
                        col1_sub,
                        col2_sub,
                        col3_sub,
                        col4_sub
                    }
                    
                    -- 使用FauxScrollFrameTemplate，参考XML文件的实现方式
                    -- 预先创建行框架，使用XML格式的静态行定义
                    local numLines = 16 -- 可显示的行数
                    local lineHeight = 20 -- 每行高度
                    
                    -- 创建滚动框架 - 使用FauxScrollFrameTemplate
                    local scrollFrame = CreateFrame("ScrollFrame", "WebDKP_LootListScrollFrame", frame, "FauxScrollFrameTemplate")
                    scrollFrame:SetWidth(600)
                    scrollFrame:SetHeight(330)
                    scrollFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", -10, -60)
                    
                    -- 设置滚动处理脚本 - 使用FauxScrollFrame的标准方式
                    scrollFrame:SetScript("OnVerticalScroll", function()
                        FauxScrollFrame_OnVerticalScroll(20, WebDKP_UpdateLootList)
                    end)
                    
                    -- 预先创建静态行框架，类似XML中的定义
                    for i = 1, numLines do
                        local lineFrame = CreateFrame("Frame", "WebDKP_LootListLine"..i, frame)
                        lineFrame:SetWidth(580)
                        lineFrame:SetHeight(lineHeight)
                        lineFrame:SetID(i) -- 设置ID用于滚动计算
                        
                        -- 设置位置 - 相对于滚动框架
                        if i == 1 then
                            lineFrame:SetPoint("TOPLEFT", scrollFrame, "TOPLEFT", 20, 0)
                        else
                            lineFrame:SetPoint("TOPLEFT", "WebDKP_LootListLine"..(i-1), "BOTTOMLEFT")
                        end
                        
                        -- 创建背景
                        local bg = lineFrame:CreateTexture(nil, "BACKGROUND")
                        bg:SetAllPoints(lineFrame)
                        if math.fmod(i, 2) == 0 then
                            bg:SetTexture(0.1, 0.1, 0.1, 0.3)
                        else
                            bg:SetTexture(0.2, 0.2, 0.2, 0.6)
                        end
                        
                        -- 创建高亮纹理 - 使用ARTWORK层级确保在WoW 1.12中正常工作
                        local highlightTexture = lineFrame:CreateTexture(nil, "ARTWORK")
                        highlightTexture:SetAllPoints(lineFrame)
                        highlightTexture:SetTexture(0.2, 0.5, 1.0, 0.9) -- 更亮的蓝色，更高的透明度
                        highlightTexture:Hide()
                        lineFrame.highlightTexture = highlightTexture
                        
                        -- 创建装备记录文本框
                        local itemText = lineFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                        itemText:SetPoint("TOPLEFT", lineFrame, "TOPLEFT", 20, 0) -- 与列标题对齐
                        itemText:SetWidth(220)
                        itemText:SetJustifyH("LEFT")
                        lineFrame.itemText = itemText
                        
                        -- 创建获得者/玩家名称文本框
                        local playerText = lineFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                        playerText:SetPoint("TOPLEFT", lineFrame, "TOPLEFT", 220, 0) -- 与列标题对齐
                        playerText:SetWidth(120)
                        playerText:SetJustifyH("LEFT")
                        lineFrame.playerText = playerText
                        
                        -- 创建DKP花费文本框（装备记录）/ 所在地文本框（替补名单）
                        local costOrLocationText = lineFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                        costOrLocationText:SetPoint("TOPLEFT", lineFrame, "TOPLEFT", 340, 0) -- 与列标题对齐
                        costOrLocationText:SetWidth(80)
                        costOrLocationText:SetJustifyH("LEFT")
                        lineFrame.costText = costOrLocationText
                        lineFrame.locationText = costOrLocationText -- 复用同一个文本框
                        
                        -- 创建时间文本框
                        local timeText = lineFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                        timeText:SetPoint("TOPLEFT", lineFrame, "TOPLEFT", 420, 0) -- 与列标题对齐
                        timeText:SetWidth(120)
                        timeText:SetJustifyH("LEFT")
                        lineFrame.timeText = timeText
                        lineFrame.addTimeText = timeText -- 复用同一个文本框
                        
                        -- 初始隐藏
                        lineFrame:Hide()
                    end
                    
                    -- 保存引用
                    WebDKP_LootListFrame = frame
                    WebDKP_LootListScrollFrame = scrollFrame
                    
                    -- 统一设置全局变量的currentMode属性
                    if WebDKP_LootListFrame and frame.currentMode then
                        WebDKP_LootListFrame.currentMode = frame.currentMode
                    end
                end
                
                return WebDKP_LootListFrame
            end
        end
        
        -- 检查WebDKP_GetTableSize是否缺失，如果缺失则创建替代实现
        if not WebDKP_GetTableSize then
            
            WebDKP_GetTableSize = function(table)
                local count = 0;
                if( table == nil ) then
                    return count;
                end
                for key, entry in pairs(table) do
                    count = count + 1;
                end
                return count;
            end
        end
        
        -- 检查WebDKP_GetDKPRecords是否缺失，如果缺失则创建替代实现
        if not WebDKP_GetDKPRecords then
            WebDKP_GetDKPRecords = function()
                local records = {}
                
                -- 确保WebDKP_DKPRecords表存在
                if not WebDKP_DKPRecords then
                    WebDKP_DKPRecords = {}
                end
                
                -- 从缓存文件WebDKP_Log中提取真实DKP记录
                local logEntries = {}
                if WebDKP_Log and type(WebDKP_Log) == "table" then
                    for key, entry in pairs(WebDKP_Log) do
                        -- 跳过版本记录和无效条目
                        if key ~= "Version" and type(entry) == "table" and entry.date and entry.reason and entry.points then
                            local isForItem = entry.foritem == "true" or entry.foritem == true
                            local points = tonumber(entry.points) or 0
                            
                            -- 只处理非物品记录（DKP奖惩记录）
                            if not isForItem then
                                -- 根据记录类型创建DKP记录
                                local logItem = {
                                    reason = entry.reason,
                                    date = entry.date,
                                    points = points,
                                    isItem = isForItem,
                                    awardedCount = WebDKP_GetTableSize(entry.awarded or {}),
                                    tableid = entry.tableid, -- 保存tableid信息，用于后续获取列表名称
                                    uniqueId = key -- 添加唯一标识符，用于删除操作
                                }
                                
                                table.insert(logEntries, logItem)
                            end
                        end
                    end
                end
                
                -- 按时间排序（最新的在前）
                table.sort(logEntries, function(a, b)
                    return a.date > b.date
                end)
                
                -- 转换为DKP列表需要的格式，只包含非物品记录
                for i, logEntry in ipairs(logEntries) do
                    -- 只显示非物品记录（DKP奖惩记录）
                    if not logEntry.isItem then
                        local record = {
                            item = logEntry.reason,
                            playerCount = logEntry.awardedCount,
                            score = logEntry.points,
                            time = logEntry.date,
                            date = logEntry.date, -- 添加date字段用于安全删除
                            uniqueId = logEntry.uniqueId, -- 使用稳定的唯一标识符替代易变的index
                            tableid = logEntry.tableid -- 包含tableid，用于显示正确的列表名称
                        }
                        
                        table.insert(records, record)
                        
                        -- 如果WebDKP_DKPRecords中没有这条记录，则添加进去
                        local exists = false
                        for j, dkpRecord in ipairs(WebDKP_DKPRecords) do
                            if dkpRecord.item == record.item and dkpRecord.time == record.time then
                                exists = true
                                break
                            end
                        end
                        
                        if not exists then
                            table.insert(WebDKP_DKPRecords, record)
                        end
                    end
                end
                
                -- 确保至少有一些记录（如果日志为空）
                if WebDKP_GetTableSize(records) == 0 and WebDKP_GetTableSize(WebDKP_DKPRecords) == 0 then
                    table.insert(WebDKP_DKPRecords, { item = "暂无DKP记录", playerCount = 0, score = 0, time = date("%Y-%m-%d %H:%M") })
                    table.insert(records, {
                        item = "暂无DKP记录",
                        playerCount = 0,
                        score = 0,
                        time = date("%Y-%m-%d %H:%M"),
                        uniqueId = "no_records" -- 添加唯一标识符
                    })
                end
                
                return records
            end
        end
        
        -- 添加删除DKP记录的函数（按uniqueId删除，保留兼容性）
        if not WebDKP_DeleteDKPRecord then
            WebDKP_DeleteDKPRecord = function(uniqueId)
                -- WebDKP_Print("尝试根据uniqueId删除DKP记录: " .. tostring(uniqueId))
                
                -- 检查参数
                if not uniqueId then
                    WebDKP_Print("错误：缺少uniqueId参数")
                    return false
                end
                
                -- 先从WebDKP_Log中找到要删除的记录，获取分数和受影响的玩家
                local pointsToRestore = 0
                local affectedPlayers = {}
                local targetLogEntry = nil
                
                if WebDKP_Log then
                    for logKey, logEntry in pairs(WebDKP_Log) do
                        if type(logEntry) == "table" and logEntry.uniqueId and logEntry.uniqueId == uniqueId then
                            -- 确保这是DKP记录而不是装备记录或替补记录
                            local isLootRecord = logEntry.foritem == true or logEntry.foritem == "true"
                            local isSubstituteRecord = logEntry.reason and string.find(logEntry.reason, "替补")
                            
                            if not isLootRecord and not isSubstituteRecord then
                                -- 保存分数和受影响的玩家
                                pointsToRestore = tonumber(logEntry.points) or 0
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
                    WebDKP_Print("=== WebDKP_Log 查找结束，找到: " .. tostring(deleted) .. " ===")
                
                -- 如果删除失败且是未知装备，提供额外的调试信息
                if not deleted and (string.find(itemName, "未知装备") or string.find(itemName, "未知物品")) then
                    WebDKP_Print("未知装备删除失败调试信息:")
                    WebDKP_Print("- 目标: 物品=" .. itemName .. ", 玩家=" .. playerName .. ", 时间=" .. timeString)
                    WebDKP_Print("- 建议检查: 记录是否包含foritem=true, 玩家是否在awarded表中, 时间格式是否匹配")
                end
                end
                
                -- 首先尝试直接从WebDKP_DKPRecords中删除
                local deletedFromDKP = false
                if WebDKP_DKPRecords then
                    for i, record in ipairs(WebDKP_DKPRecords) do
                        if record.uniqueId and record.uniqueId == uniqueId then
                            table.remove(WebDKP_DKPRecords, i)
                            deletedFromDKP = true
                            -- WebDKP_Print("成功从WebDKP_DKPRecords删除记录")
                            break
                        end
                    end
                end
                
                -- 同时从WebDKP_Log中删除对应的记录
                local deletedFromLog = false
                if WebDKP_Log then
                    if targetLogEntry then
                        WebDKP_Log[targetLogEntry] = nil
                        deletedFromLog = true
                        WebDKP_Print("成功从WebDKP_Log删除记录")
                    else
                        for logKey, logEntry in pairs(WebDKP_Log) do
                            if type(logEntry) == "table" and logEntry.uniqueId and logEntry.uniqueId == uniqueId then
                                WebDKP_Log[logKey] = nil
                                deletedFromLog = true
                                WebDKP_Print("成功从WebDKP_Log删除记录")
                                break
                            end
                        end
                    end
                end
                
                -- 恢复受影响玩家的DKP分数
                                if (deletedFromDKP or deletedFromLog) and pointsToRestore ~= 0 and next(affectedPlayers) then
                                    -- 获取当前使用的tableid
                                    local tableid = WebDKP_GetTableid()
                                    local dkpField = "dkp_"..tableid
                                    
                                    -- 遍历WebDKP_DkpTable更新玩家分数
                                    if WebDKP_DkpTable then
                                        for playerName, playerData in pairs(WebDKP_DkpTable) do
                                            if type(playerData) == "table" and affectedPlayers[playerName] then
                                                -- 恢复原来添加的分数（删除加分记录时减去，删除扣分记录时加上）
                                                local currentDKP = tonumber(playerData[dkpField]) or 0
                                                playerData[dkpField] = currentDKP - pointsToRestore
                                                -- WebDKP_Print("已恢复玩家 " .. playerName .. " 的DKP分数: " .. playerData[dkpField])
                                            end
                                        end
                                    end
                                end
                
                -- 如果上面的方法失败，尝试备选方案
                -- WebDKP_Print("从WebDKP_DKPRecords删除失败，尝试备选方案")
                
                -- 遍历WebDKP_Log查找匹配的DKP记录
                if WebDKP_Log and not (deletedFromDKP or deletedFromLog) then
                    for logKey, logEntry in pairs(WebDKP_Log) do
                        if type(logEntry) == "table" and logEntry.uniqueId and logEntry.uniqueId == uniqueId then
                            -- 确保这是DKP记录而不是装备记录
                            local isLootRecord = logEntry.foritem == true or logEntry.foritem == "true"
                            local isSubstituteRecord = logEntry.reason and string.find(logEntry.reason, "替补")
                            
                            if not isLootRecord and not isSubstituteRecord then
                                -- 获取分数和受影响的玩家
                                local altPointsToRestore = tonumber(logEntry.points) or 0
                                local altAffectedPlayers = {}
                                if logEntry.awarded then
                                    for playerName, _ in pairs(logEntry.awarded) do
                                        altAffectedPlayers[playerName] = true
                                    end
                                end
                                
                                WebDKP_Log[logKey] = nil
                                WebDKP_Print("成功通过备选方案从WebDKP_Log删除DKP记录")
                                
                                -- 恢复受影响玩家的DKP分数
                                if altPointsToRestore ~= 0 and next(altAffectedPlayers) then
                                    -- 获取当前使用的tableid
                                    local tableid = WebDKP_GetTableid()
                                    local dkpField = "dkp_"..tableid
                                    
                                    -- 遍历WebDKP_DkpTable更新玩家分数
                                    if WebDKP_DkpTable then
                                        for playerName, playerData in pairs(WebDKP_DkpTable) do
                                            if type(playerData) == "table" and altAffectedPlayers[playerName] then
                                                -- 恢复原来添加的分数
                                                local currentDKP = tonumber(playerData[dkpField]) or 0
                                                playerData[dkpField] = currentDKP - altPointsToRestore
                                                -- WebDKP_Print("已恢复玩家 " .. playerName .. " 的DKP分数: " .. playerData[dkpField])
                                            end
                                        end
                                    end
                                end
                                
                                -- 保存数据并刷新界面
                                if WebDKP_SaveToDisk then
                                    WebDKP_SaveToDisk()
                                end
                                if WebDKP_UpdateTable then
                                    WebDKP_UpdateTable()
                                end
                                if WebDKP_UpdateLootList then
                                    WebDKP_UpdateLootList()
                                end
                                -- 调用刷新队伍函数，相当于按了刷新队伍按钮
                                if WebDKP_Refresh then
                                    WebDKP_Refresh()
                                end
                                
                                return true
                            end
                        end
                    end
                end
                
                -- 如果成功删除，保存数据并刷新界面
                if deletedFromDKP or deletedFromLog then
                    if WebDKP_SaveToDisk then
                        WebDKP_SaveToDisk()
                    end
                    if WebDKP_UpdateTable then
                        WebDKP_UpdateTable()
                    end
                    if WebDKP_UpdateLootList then
                        WebDKP_UpdateLootList()
                    end
                    -- 刷新DKP主窗口
                    if WebDKP_MainFrame then
                        WebDKP_MainFrame:Show()
                        WebDKP_MainFrame:Update()
                    end
                    -- 调用刷新队伍函数，相当于按了刷新队伍按钮
                    if WebDKP_Refresh then
                        WebDKP_Refresh()
                    end
                end
                
                -- WebDKP_Print("未能找到匹配的DKP记录进行删除")
                return deletedFromDKP or deletedFromLog
            end
        end
        
        -- 添加按项目和时间删除DKP记录的函数（新的精确删除方式）
        if not WebDKP_DeleteDKPRecordByItemAndTime then
            WebDKP_DeleteDKPRecordByItemAndTime = function(itemName, timeString)
                if not itemName or not timeString then
                    WebDKP_Print("删除DKP记录失败 - 缺少项目名或时间")
                    return false
                end
                
                WebDKP_Print("按项目和时间删除DKP记录 - 项目: " .. itemName .. ", 时间: " .. timeString)
                
                local deleted = false
                local totalPointsRestored = 0
                local pointsRestored = false
                local individualPointsToRestore = 0
                
                -- 先从WebDKP_Log中找到要删除的记录，获取分数和受影响的玩家
                if WebDKP_Log then
                    for key, entry in pairs(WebDKP_Log) do
                        if key ~= "Version" and type(entry) == "table" then
                            -- 增强的字段匹配，移除foritem排除条件，使函数能处理装备记录
                            local itemMatch = entry.reason == itemName or entry.item == itemName or entry.name == itemName
                            local timeMatch = entry.date == timeString or entry.time == timeString or tostring(entry.timestamp) == timeString
                            
                            if itemMatch and timeMatch then
                                -- 从entry中获取points值（支持多种格式）
                                local pointsToRestore = tonumber(entry.points) or 0
                                individualPointsToRestore = pointsToRestore
                                
                                -- 获取受影响的玩家列表
                                if entry.awarded then
                                    for playerName, playerInfo in pairs(entry.awarded) do
                                        -- 为每个玩家分别恢复DKP
                                        local playerPointsToRestore = pointsToRestore
                                        -- 如果玩家信息包含单独的points值，优先使用
                                        if type(playerInfo) == "table" then
                                            playerPointsToRestore = tonumber(playerInfo.points or playerInfo.dkp or playerInfo.value or pointsToRestore) or 0
                                        elseif type(playerInfo) == "number" then
                                            playerPointsToRestore = playerInfo
                                        end
                                        -- 装备记录通常是扣分，需要转换符号
                                        if entry.foritem == "true" or entry.foritem == true then
                                            playerPointsToRestore = -playerPointsToRestore
                                        end
                                        -- 保存第一个玩家的恢复分数作为显示值
                                        if individualPointsToRestore == 0 then
                                            individualPointsToRestore = playerPointsToRestore
                                        end
                                        
                                        -- 确保有分数要恢复
                                        if playerPointsToRestore ~= 0 and WebDKP_DkpTable and WebDKP_DkpTable[playerName] then
                                            -- 获取当前使用的tableid
                                            local tableid = WebDKP_GetTableid()
                                            local dkpField = "dkp_"..tableid
                                            
                                            -- 尝试多种可能的DKP字段
                                            if type(WebDKP_DkpTable[playerName]) == "number" then
                                                -- 如果是简单数字格式
                                                WebDKP_DkpTable[playerName] = WebDKP_DkpTable[playerName] - playerPointsToRestore
                                                totalPointsRestored = totalPointsRestored - playerPointsToRestore
                                                pointsRestored = true
                                                WebDKP_Print("已恢复玩家 " .. playerName .. " 的DKP分数: +" .. tostring(-playerPointsToRestore))
                                            else
                                                -- 尝试多种可能的DKP字段
                                                local currentDKP = tonumber(WebDKP_DkpTable[playerName][dkpField]) or 
                                                                 tonumber(WebDKP_DkpTable[playerName].dkp) or 
                                                                 tonumber(WebDKP_DkpTable[playerName].points) or 0
                                                -- 更新玩家的DKP分数
                                                if WebDKP_DkpTable[playerName][dkpField] then
                                                    WebDKP_DkpTable[playerName][dkpField] = currentDKP - playerPointsToRestore
                                                elseif WebDKP_DkpTable[playerName].dkp then
                                                    WebDKP_DkpTable[playerName].dkp = currentDKP - playerPointsToRestore
                                                elseif WebDKP_DkpTable[playerName].points then
                                                    WebDKP_DkpTable[playerName].points = currentDKP - playerPointsToRestore
                                                else
                                                    -- 如果没有找到合适的字段，创建默认字段
                                                    WebDKP_DkpTable[playerName][dkpField] = currentDKP - playerPointsToRestore
                                                end
                                                totalPointsRestored = totalPointsRestored - playerPointsToRestore
                                                pointsRestored = true
                                                -- WebDKP_Print("已恢复玩家 " .. playerName .. " 的DKP分数: +" .. tostring(-playerPointsToRestore))
                                            end
                                        end
                                    end
                                end
                                -- 从WebDKP_Log中删除记录
                                WebDKP_Log[key] = nil
                                deleted = true
                                -- WebDKP_Print("已从WebDKP_Log删除记录")
                                break
                            end
                        end
                    end
                end
                -- 从WebDKP_DKPRecords中删除
                if WebDKP_DKPRecords then
                    for i, dkpRecord in pairs(WebDKP_DKPRecords) do
                        if dkpRecord.item == itemName and dkpRecord.time == timeString then
                            table.remove(WebDKP_DKPRecords, i)
                            deleted = true
                            WebDKP_Print("已从WebDKP_DKPRecords删除记录")
                            break
                        end
                    end
                end
                -- 从WebDKP_LootRecords中删除（如果存在）
                if WebDKP_LootRecords then
                    for i, record in pairs(WebDKP_LootRecords) do
                        if record.item == itemName and (record.time == timeString or record.date == timeString) then
                            table.remove(WebDKP_LootRecords, i)
                            deleted = true
                            WebDKP_Print("已从WebDKP_LootRecords删除装备记录")
                            break
                        end
                    end
                end
                
                -- 如果成功删除，保存数据并刷新界面
                if deleted then
                    -- 保存数据到磁盘
                    if WebDKP_SaveToDisk then
                        WebDKP_SaveToDisk()
                        WebDKP_Print("数据已保存")
                    end
                    
                    -- 整合提示信息，明确显示删除和恢复状态
                    if pointsRestored then
                        -- 直接显示恢复的DKP值，系统会自动处理正负号
                        WebDKP_Print("记录删除成功，恢复DKP:" .. tostring(individualPointsToRestore))
                    else
                        WebDKP_Print("记录删除成功，但未能恢复DKP分数")
                    end
                    
                    -- 刷新相关界面
                    if WebDKP_UpdateTable then
                        WebDKP_UpdateTable()
                    end
                    if WebDKP_UpdateLootList then
                        WebDKP_UpdateLootList()
                    end
                    
                    -- 刷新DKP主窗口
                    if WebDKP_MainFrame then
                        WebDKP_MainFrame:Show()
                        if WebDKP_MainFrame.Update then
                            WebDKP_MainFrame:Update()
                        end
                    end
                    
                    -- 调用刷新队伍函数，相当于按了刷新队伍按钮
                    if WebDKP_Refresh then
                        WebDKP_Refresh()
                    end
                else
                    WebDKP_Print("未找到匹配的记录进行删除")
                end
                
                return deleted
            end
        end
        
        -- 添加删除单个玩家DKP记录的函数（用于修复误删问题）
        if not WebDKP_DeletePlayerDKPRecord then
            WebDKP_DeletePlayerDKPRecord = function(playerName, itemName, timeString)
                if not playerName or not itemName or not timeString then
                    WebDKP_Print("删除玩家DKP记录失败 - 缺少必要参数")
                    return false
                end
                
                WebDKP_Print("删除玩家DKP记录 - 玩家: " .. playerName .. ", 项目: " .. itemName .. ", 时间: " .. timeString)
                
                local deleted = false
                
                -- 从WebDKP_Log中删除该玩家的记录
                if WebDKP_Log then
                    for key, entry in pairs(WebDKP_Log) do
                        if key ~= "Version" and type(entry) == "table" and entry.date and entry.reason and entry.points and entry.awarded then
                            if entry.reason == itemName and entry.date == timeString and entry.awarded[playerName] and (entry.foritem == "true" or entry.foritem == true) then
                                -- 获取玩家的扣分信息，用于恢复DKP
                                local dkpCost = entry.awarded[playerName].dkp or 0
                                local pointsToRestore = -dkpCost -- 转换为正值用于恢复
                                
                                -- 只删除该玩家的记录，保留其他玩家的记录
                                entry.awarded[playerName] = nil
                                -- WebDKP_Print("已从WebDKP_Log删除玩家 " .. playerName .. " 的记录")
                                deleted = true
                                
                                -- 恢复玩家的DKP分数
                                if pointsToRestore ~= 0 and WebDKP_DkpTable and WebDKP_DkpTable[playerName] then
                                    local tableid = WebDKP_GetTableid()
                                    local dkpField = "dkp_"..tableid
                                    local currentDKP = tonumber(WebDKP_DkpTable[playerName][dkpField]) or 0
                                    WebDKP_DkpTable[playerName][dkpField] = currentDKP + pointsToRestore
                                    -- WebDKP_Print("已恢复玩家 " .. playerName .. " 的DKP分数: " .. WebDKP_DkpTable[playerName][dkpField])
                                end
                                
                                -- 检查是否还有其他玩家，如果没有则删除整个条目
                                local hasOtherPlayers = false
                                for _, _ in pairs(entry.awarded) do
                                    hasOtherPlayers = true
                                    break
                                end
                                if not hasOtherPlayers then
                                    WebDKP_Log[key] = nil
                                    WebDKP_Print("该记录已无其他玩家，删除整个条目")
                                end
                                break
                            end
                        end
                    end
                end
                
                -- 如果成功删除，保存数据并刷新界面
                if deleted then
                    if WebDKP_SaveToDisk then
                        WebDKP_SaveToDisk()
                    end
                    if WebDKP_UpdateTable then
                        WebDKP_UpdateTable()
                    end
                    if WebDKP_UpdateLootList then
                        WebDKP_UpdateLootList()
                    end
                    -- 调用刷新队伍函数，相当于按了刷新队伍按钮
                    if WebDKP_Refresh then
                        WebDKP_Refresh()
                    end
                end
                
                return deleted
            end
        end
        
        -- 添加删除装备记录的函数
        if not WebDKP_DeleteLootRecord then
            WebDKP_DeleteLootRecord = function(itemName, playerName, timeString)
                if not itemName or not playerName or not timeString then
                    WebDKP_Print("删除装备记录失败 - 缺少必要参数")
                    return false
                end
                
                WebDKP_Print("删除装备记录 - 物品: " .. itemName .. ", 玩家: " .. playerName .. ", 时间: " .. timeString)
                
                -- 调试信息：显示WebDKP_LootRecords中的记录
                if WebDKP_LootRecords then
                    -- WebDKP_Print("=== WebDKP_LootRecords 中的记录 ===")
                    for i, record in pairs(WebDKP_LootRecords) do
                        WebDKP_Print("记录 " .. i .. ": item=" .. (record.item or "nil") .. ", player=" .. (record.player or "nil") .. ", time=" .. (record.time or "nil"))
                    end
                end
                
                -- 调试信息：显示WebDKP_Log中的装备记录
                if WebDKP_Log then
                    -- WebDKP_Print("=== WebDKP_Log 中的装备记录 ===")
                    for key, entry in pairs(WebDKP_Log) do
                        if key ~= "Version" and type(entry) == "table" and (entry.foritem == "true" or entry.foritem == true) then
                            -- WebDKP_Print("记录 key=" .. key .. ": reason=" .. (entry.reason or "nil") .. ", time=" .. (entry.time or "nil") .. ", date=" .. (entry.date or "nil") .. ", foritem=" .. tostring(entry.foritem or "nil"))
                            if entry.awarded then
                                for player, info in pairs(entry.awarded) do
                                    local infoType = type(info)
                                    local pointsInfo = ""
                                    if infoType == "number" then
                                        pointsInfo = " (分数: " .. tostring(info) .. ")"
                                    elseif infoType == "table" then
                                        local points = info.points or info.dkp or info.value or "无"
                                        pointsInfo = " (分数: " .. tostring(points) .. ", 表类型)"
                                    end
                                    -- WebDKP_Print("  玩家: " .. player .. " (数据类型: " .. infoType .. ")" .. pointsInfo)
                                end
                            end
                        end
                    end
                end
                
                local deleted = false
                local pointsRestored = false
                local totalPointsRestored = 0
                
                -- 首先从WebDKP_LootRecords中查找和删除
                if WebDKP_LootRecords then
                    -- WebDKP_Print("=== 开始查找 WebDKP_LootRecords ===")
                    for i, record in pairs(WebDKP_LootRecords) do
                        -- 对于未知装备，使用更宽松的匹配条件，主要匹配玩家名和时间
                        local isUnknownItem = string.find(itemName, "未知装备") ~= nil or string.find(itemName, "未知物品") ~= nil
                        
                        -- 时间匹配逻辑：尝试精确匹配或部分匹配（只匹配到分钟）
                        local timeMatch = false
                        if record.time and timeString then
                            -- 尝试精确匹配
                            timeMatch = record.time == timeString or record.date == timeString
                            
                            -- 如果精确匹配失败，尝试部分匹配（只匹配到分钟）
                            if not timeMatch then
                                local recordTimeShort = string.sub(record.time, 1, 16) -- 格式：2025-11-06 01:46
                                local givenTimeShort = string.sub(timeString, 1, 16)
                                timeMatch = recordTimeShort == givenTimeShort
                            end
                        end
                        
                        -- 检查匹配条件
                        local itemMatch = isUnknownItem or (record.item == itemName)
                        local playerMatch = (record.player == playerName)
                        
                        -- WebDKP_Print("检查记录 " .. i .. ": item=" .. (record.item or "nil") .. " vs " .. itemName .. " (匹配:" .. tostring(itemMatch) .. "), player=" .. (record.player or "nil") .. " vs " .. playerName .. " (匹配:" .. tostring(playerMatch) .. "), time=" .. (record.time or "nil") .. " vs " .. timeString .. " (匹配:" .. tostring(timeMatch) .. ")")
                        
                        -- 宽松的匹配条件：如果是未知装备，主要匹配玩家名和时间
                        -- 如果不是未知装备，则需要严格匹配物品名
                        if (isUnknownItem and record.player == playerName and timeMatch) or 
                           (not isUnknownItem and record.item == itemName and record.player == playerName and timeMatch) then
                            table.remove(WebDKP_LootRecords, i)
                            deleted = true
                            -- WebDKP_Print("已从WebDKP_LootRecords删除装备记录")
                            break
                        end
                    end
                    -- WebDKP_Print("=== WebDKP_LootRecords 查找结束，找到: " .. tostring(deleted) .. " ===")
                end
                
                -- 从WebDKP_Log中查找和删除，并恢复DKP
                if WebDKP_Log then
                    -- WebDKP_Print("=== 开始查找 WebDKP_Log ===")
                
                -- 特殊调试：如果是未知装备，显示所有相关记录的详细信息
                if string.find(itemName, "未知装备") or string.find(itemName, "未知物品") then
                    -- WebDKP_Print("特殊调试 - 查找未知装备记录，目标: 物品=" .. itemName .. ", 玩家=" .. playerName .. ", 时间=" .. timeString)
                    for key, entry in pairs(WebDKP_Log) do
                        if key ~= "Version" and type(entry) == "table" then
                            local hasReason = entry.reason ~= nil
                            local hasTime = entry.time ~= nil or entry.date ~= nil
                            local hasAwarded = entry.awarded ~= nil
                            local isForItem = entry.foritem == "true" or entry.foritem == true
                            
                            if hasReason and hasTime and hasAwarded and isForItem then
                                -- WebDKP_Print("  候选记录 key=" .. key .. ": reason=" .. tostring(entry.reason) .. 
                                --           ", time=" .. tostring(entry.time) .. ", date=" .. tostring(entry.date) .. 
                                --           ", foritem=" .. tostring(entry.foritem))
                                if entry.awarded[playerName] then
                                    -- WebDKP_Print("    找到玩家 " .. playerName .. " in awarded表, 数据类型: " .. type(entry.awarded[playerName]))
                                end
                            end
                        end
                    end
                end
                    for key, entry in pairs(WebDKP_Log) do
                        if key ~= "Version" and type(entry) == "table" then
                            -- 增强的字段匹配逻辑，支持更多可能的数据结构
                            local isUnknownItem = string.find(itemName, "未知装备") ~= nil or string.find(itemName, "未知物品") ~= nil
                            local itemMatch = entry.item == itemName or entry.reason == itemName or entry.name == itemName
                            
                            -- 对于未知装备，放宽物品匹配条件
                            if isUnknownItem then
                                itemMatch = true -- 未知装备时不严格匹配物品名
                            end
                            
                            -- 玩家匹配逻辑：检查entry.awarded中是否有该玩家，或者entry.player字段匹配
                            local playerMatch = false
                            if entry.awarded and entry.awarded[playerName] then
                                playerMatch = true  -- awarded表中存在该玩家
                            elseif entry.player and entry.player == playerName then
                                playerMatch = true  -- player字段匹配
                            end
                            
                            -- 改进的时间匹配逻辑
                            local timeMatch = false
                            if timeString then
                                -- 尝试多种时间字段的精确匹配
                                timeMatch = (entry.time and entry.time == timeString) or 
                                           (entry.date and entry.date == timeString) or 
                                           (entry.timestamp and tostring(entry.timestamp) == timeString)
                                
                                -- 如果精确匹配失败，尝试部分匹配（只匹配到分钟）
                                if not timeMatch and entry.time then
                                    local entryTimeShort = string.sub(entry.time, 1, 16) -- 格式：2025-11-06 01:46
                                    local givenTimeShort = string.sub(timeString, 1, 16)
                                    timeMatch = entryTimeShort == givenTimeShort
                                end
                                
                                -- 如果entry.time为nil但entry.date存在，尝试用entry.date进行部分匹配
                                if not timeMatch and entry.date and not entry.time then
                                    local entryDateShort = string.sub(entry.date, 1, 16) -- 格式：2025-11-06 01:46
                                    local givenTimeShort = string.sub(timeString, 1, 16)
                                    timeMatch = entryDateShort == givenTimeShort
                                end
                                
                                -- 特殊处理：未知装备记录的时间匹配
                                if isUnknownItem and not timeMatch and entry.date and entry.date ~= "" then
                                    -- 对于未知装备，允许更宽松的时间匹配
                                    -- 检查entry.date是否与给定时间完全匹配或部分匹配
                                    if entry.date == timeString then
                                        timeMatch = true
                                    elseif string.sub(entry.date, 1, 16) == string.sub(timeString, 1, 16) then
                                        timeMatch = true
                                    end
                                end
                            end
                            
                            -- 增强调试信息：显示更多记录结构细节
                            local debugInfo = "检查WebDKP_Log记录 key=" .. key .. ": "
                            debugInfo = debugInfo .. "item=" .. (entry.item or "nil") .. "/reason=" .. (entry.reason or "nil") .. " vs " .. itemName .. " (匹配:" .. tostring(itemMatch) .. "), "
                            debugInfo = debugInfo .. "player=" .. (entry.player or "nil") .. " vs " .. playerName .. " (匹配:" .. tostring(playerMatch) .. "), "
                            debugInfo = debugInfo .. "time=" .. (entry.time or "nil") .. "/date=" .. (entry.date or "nil") .. " vs " .. timeString .. " (匹配:" .. tostring(timeMatch) .. ")"
                            
                            -- 如果是未知装备，显示更多字段信息
                            if isUnknownItem then
                                debugInfo = debugInfo .. " [未知装备特殊信息: foritem=" .. tostring(entry.foritem or "nil")
                                if entry.awarded and entry.awarded[playerName] then
                                    debugInfo = debugInfo .. ", awarded[" .. playerName .. "]类型=" .. type(entry.awarded[playerName])
                                end
                                debugInfo = debugInfo .. "]"
                            end
                            
                            -- WebDKP_Print(debugInfo)
                            
                            -- 宽松匹配条件：如果是未知装备，主要匹配玩家名和时间
                            -- 如果不是未知装备，则需要物品名、玩家名和时间都匹配
                            if ((isUnknownItem and playerMatch and timeMatch) or 
                                (not isUnknownItem and itemMatch and playerMatch and timeMatch)) then
                                local pointsToRestore = 0
                                
                                -- 采用与WebDKP_DeleteDKPRecordByItemAndTime相同的逻辑
                                -- 首先从entry获取通用points值
                                local originalPoints = tonumber(entry.points) or 0
                                
                                -- 然后检查玩家特定的信息
                                if entry.awarded and entry.awarded[playerName] then
                                    if type(entry.awarded[playerName]) == "number" then
                                        originalPoints = entry.awarded[playerName] -- 优先使用玩家特定的数字
                                    elseif type(entry.awarded[playerName]) == "table" then
                                        -- 如果玩家信息是表类型，优先使用玩家特定的points/dkp/value
                                        local playerPoints = tonumber(entry.awarded[playerName].points or entry.awarded[playerName].dkp or entry.awarded[playerName].value or 0)
                                        if playerPoints ~= 0 then
                                            originalPoints = playerPoints
                                        end
                                    end
                                end
                                
                                -- 对于装备记录，分数通常是负数（扣分），需要反转符号来恢复
                                if entry.foritem == "true" or entry.foritem == true then
                                    originalPoints = -originalPoints
                                end
                                
                                if originalPoints ~= 0 then
                                    -- 获取当前使用的tableid
                                    local tableid = WebDKP_GetTableid()
                                    local dkpField = "dkp_"..tableid
                                    
                                    -- 恢复玩家的DKP分数，严格按照WebDKP_DeleteDKPRecord的逻辑
                                    if WebDKP_DkpTable and WebDKP_DkpTable[playerName] then
                                        -- 支持多种数据格式
                                        if type(WebDKP_DkpTable[playerName]) == "number" then
                                            -- 如果是简单数字格式
                                            local oldDKP = WebDKP_DkpTable[playerName]
                                            WebDKP_DkpTable[playerName] = WebDKP_DkpTable[playerName] + originalPoints
                                            pointsToRestore = originalPoints
                                            pointsRestored = true
                                            totalPointsRestored = totalPointsRestored + pointsToRestore
                                            -- WebDKP_Print("已恢复玩家 " .. playerName .. " 的DKP分数: " .. tostring(pointsToRestore) .. " (" .. tostring(oldDKP) .. " -> " .. tostring(WebDKP_DkpTable[playerName]) .. ")")
                                        
                                        elseif type(WebDKP_DkpTable[playerName]) == "table" then
                                            -- 如果是表格式，尝试多种可能的DKP字段
                                            local currentDKP = tonumber(WebDKP_DkpTable[playerName][dkpField]) or 
                                                             tonumber(WebDKP_DkpTable[playerName].dkp) or 
                                                             tonumber(WebDKP_DkpTable[playerName].points) or 0
                                            
                                            -- 更新玩家的DKP分数
                                            local oldDKP = currentDKP
                                            if WebDKP_DkpTable[playerName][dkpField] then
                                                WebDKP_DkpTable[playerName][dkpField] = currentDKP + originalPoints
                                            elseif WebDKP_DkpTable[playerName].dkp then
                                                WebDKP_DkpTable[playerName].dkp = currentDKP + originalPoints
                                            elseif WebDKP_DkpTable[playerName].points then
                                                WebDKP_DkpTable[playerName].points = currentDKP + originalPoints
                                            else
                                                -- 如果没有找到合适的字段，创建默认字段
                                                WebDKP_DkpTable[playerName][dkpField] = currentDKP + originalPoints
                                            end
                                            
                                            pointsToRestore = originalPoints
                                            pointsRestored = true
                                            totalPointsRestored = totalPointsRestored + pointsToRestore
                                            -- WebDKP_Print("已恢复玩家 " .. playerName .. " 的DKP分数: " .. tostring(pointsToRestore) .. " (" .. tostring(oldDKP) .. " -> " .. tostring(currentDKP + originalPoints) .. ")")
                                        end
                                    end
                                end
                                
                                -- 从记录中删除该玩家
                                if entry.awarded and entry.awarded[playerName] then
                                    entry.awarded[playerName] = nil
                                    deleted = true
                                    WebDKP_Print("已从记录中删除玩家 " .. playerName .. " 的数据")
                                end
                                
                                -- 检查是否需要删除整个条目（如果没有其他玩家了）
                                if entry.awarded and next(entry.awarded) == nil then
                                    WebDKP_Log[key] = nil
                                    -- WebDKP_Print("已删除空的装备记录条目")
                                end
                                
                                break
                            end
                        end
                    end
                end
                
                -- 如果成功删除，保存数据并刷新界面
                if deleted then
                    -- 保存数据到磁盘
                    if WebDKP_SaveToDisk then
                        WebDKP_SaveToDisk()
                    end
                    
                    -- 整合提示信息，明确显示删除和恢复状态
                    if pointsRestored then
                        WebDKP_Print("装备记录删除成功，恢复DKP: " .. tostring(totalPointsRestored))
                    else
                        WebDKP_Print("装备记录删除成功，但未能恢复DKP分数")
                    end
                    
                    if WebDKP_Refresh then
                       WebDKP_Refresh()
                   end
                    -- 刷新相关界面
                    if WebDKP_UpdateTable then
                        WebDKP_UpdateTable()
                    end
                    if WebDKP_UpdateLootList then
                        WebDKP_UpdateLootList()
                    end
                else
                    WebDKP_Print("未找到匹配的装备记录进行删除")
                end
                
                return deleted
            end
        end
        
        -- 添加删除替补记录的函数（按玩家名和时间删除）
        if not WebDKP_DeleteSubstituteRecord then
            WebDKP_DeleteSubstituteRecord = function(playerName, timeString)
                if not playerName or not timeString then
                    WebDKP_Print("删除替补记录失败 - 缺少必要参数")
                    return false
                end
                
                WebDKP_Print("按玩家和时间删除替补记录 - 玩家: " .. playerName .. ", 时间: " .. timeString)
                
                local deleted = false
                local pointsRestored = false
                local totalPointsRestored = 0
                
                -- 从WebDKP_DailySubRecords中删除
                if WebDKP_DailySubRecords then
                    for date, dayRecords in pairs(WebDKP_DailySubRecords) do
                        if dayRecords[playerName] then
                            -- 完全删除该玩家当天的所有记录
                            dayRecords[playerName] = nil
                            deleted = true
                            WebDKP_Print("已从WebDKP_DailySubRecords删除玩家 " .. playerName .. " 的替补记录")
                            
                            -- 检查当天是否还有其他记录，如果没有则删除当天记录
                            if WebDKP_GetTableSize(dayRecords) == 0 then
                                WebDKP_DailySubRecords[date] = nil
                                WebDKP_Print("该日期已无其他替补记录，删除当天记录")
                            end
                        end
                    end
                end
                
                -- 从WebDKP_Log中删除替补记录并恢复DKP
                if WebDKP_Log then
                    for key, entry in pairs(WebDKP_Log) do
                        if key ~= "Version" and type(entry) == "table" and entry.date and entry.reason and entry.awarded then
                            local isForItem = entry.foritem == "true" or entry.foritem == true
                            -- 检查是否是替补记录（通过项目名称中包含"替补"关键词判断）且不是装备记录
                            if not isForItem and string.find(entry.reason, "替补") and entry.date == timeString and entry.awarded[playerName] then
                                -- 恢复DKP分数
                                local pointsToRestore = 0
                                
                                -- 尝试多种方式获取分数信息
                                if type(entry.awarded[playerName]) == "number" then
                                    -- 如果是直接的数字格式
                                    pointsToRestore = -entry.awarded[playerName]
                                elseif type(entry.awarded[playerName]) == "table" then
                                    -- 如果是表格式，尝试多种可能的分数字段
                                    pointsToRestore = -tonumber(entry.awarded[playerName].points or entry.awarded[playerName].dkp or entry.awarded[playerName].value or 0)
                                else
                                    -- 尝试从entry中获取通用points值
                                    pointsToRestore = -tonumber(entry.points or 0)
                                end
                                
                                -- 如果找到了要恢复的分数
                                if pointsToRestore ~= 0 and WebDKP_DkpTable and WebDKP_DkpTable[playerName] then
                                    -- 获取当前使用的tableid
                                    local tableid = WebDKP_GetTableid()
                                    local dkpField = "dkp_"..tableid
                                    
                                    if type(WebDKP_DkpTable[playerName]) == "number" then
                                        -- 如果是简单数字格式
                                        WebDKP_DkpTable[playerName] = WebDKP_DkpTable[playerName] + pointsToRestore
                                    elseif type(WebDKP_DkpTable[playerName]) == "table" then
                                        -- 如果是表格式，尝试多种可能的DKP字段
                                        local currentDKP = tonumber(WebDKP_DkpTable[playerName][dkpField]) or 
                                                         tonumber(WebDKP_DkpTable[playerName].dkp) or 
                                                         tonumber(WebDKP_DkpTable[playerName].points) or 0
                                        
                                        -- 更新玩家的DKP分数
                                        if WebDKP_DkpTable[playerName][dkpField] then
                                            WebDKP_DkpTable[playerName][dkpField] = currentDKP + pointsToRestore
                                        elseif WebDKP_DkpTable[playerName].dkp then
                                            WebDKP_DkpTable[playerName].dkp = currentDKP + pointsToRestore
                                        elseif WebDKP_DkpTable[playerName].points then
                                            WebDKP_DkpTable[playerName].points = currentDKP + pointsToRestore
                                        else
                                            -- 如果没有找到合适的字段，创建默认字段
                                            WebDKP_DkpTable[playerName][dkpField] = currentDKP + pointsToRestore
                                        end
                                    end
                                    
                                    pointsRestored = true
                                    totalPointsRestored = totalPointsRestored + pointsToRestore
                                    WebDKP_Print("已恢复玩家 " .. playerName .. " 的DKP分数: " .. tostring(pointsToRestore))
                                end
                                
                                entry.awarded[playerName] = nil
                                deleted = true
                                -- WebDKP_Print("已从WebDKP_Log删除玩家 " .. playerName .. " 的替补记录")
                                
                                -- 检查是否还有其他玩家
                                local hasOtherPlayers = false
                                for _, _ in pairs(entry.awarded) do
                                    hasOtherPlayers = true
                                    break
                                end
                                if not hasOtherPlayers then
                                    WebDKP_Log[key] = nil
                                    WebDKP_Print("该替补记录已无其他玩家，删除整个条目")
                                end
                            end
                        end
                    end
                end
                
                -- 如果成功删除，保存数据并刷新界面
                if deleted then
                    -- 保存数据到磁盘
                    if WebDKP_SaveToDisk then
                        WebDKP_SaveToDisk()
                    end
                    
                    -- 整合提示信息，明确显示删除和恢复状态
                    if pointsRestored then
                        WebDKP_Print("替补记录删除成功，恢复DKP:" .. tostring(totalPointsRestored))
                    else
                        WebDKP_Print("替补记录删除成功，但未能恢复DKP分数")
                    end
                    
                    -- 刷新相关界面
                    if WebDKP_Refresh then
                        WebDKP_Refresh()
                    end
                    if WebDKP_UpdateTable then
                        WebDKP_UpdateTable()
                    end
                    if WebDKP_UpdateLootList then
                        WebDKP_UpdateLootList()
                    end
                else
                    WebDKP_Print("未找到匹配的替补记录进行删除")
                end
                
                return deleted
            end
        end
        
        -- 添加按项目和玩家删除替补记录的函数（更精确的删除）
        if not WebDKP_DeleteSubstituteRecordByItemAndTime then
            WebDKP_DeleteSubstituteRecordByItemAndTime = function(playerName, itemName, timeString)
                if not playerName or not timeString then
                    WebDKP_Print("删除替补记录失败 - 缺少必要参数")
                    return false
                end
                
                WebDKP_Print("按项目和玩家删除替补记录 - 玩家: " .. playerName .. ", 项目: " .. (itemName or "未知") .. ", 时间: " .. timeString)
                
                local deleted = false
                local pointsRestored = false
                local totalPointsRestored = 0
                
                -- 从WebDKP_Log中删除该玩家的替补记录并恢复DKP
                if WebDKP_Log then
                    for key, entry in pairs(WebDKP_Log) do
                        if key ~= "Version" and type(entry) == "table" and entry.date and entry.reason and entry.awarded then
                            local isForItem = entry.foritem == "true" or entry.foritem == true
                            -- 检查是否是替补记录（通过项目名称中包含"替补"关键词判断）且不是装备记录
                            if not isForItem and string.find(entry.reason, "替补") and entry.date == timeString and entry.awarded[playerName] then
                                -- 调试信息：显示找到的记录结构
                                -- WebDKP_Print("找到替补记录: " .. key)
                                -- WebDKP_Print("记录reason: " .. (entry.reason or "未知"))
                                -- WebDKP_Print("记录points: " .. (tostring(entry.points) or "未知"))
                                
                                -- 恢复DKP分数 - 简化并改进分数识别逻辑
                                local pointsToRestore = 0
                                
                                -- 首先尝试直接从entry.points获取分数（这是最常见的情况）
                                if entry.points and tonumber(entry.points) then
                                    pointsToRestore = tonumber(entry.points)  -- 注意这里不再取负数，因为我们要直接使用WebDKP_AddDKP的负值
                                    -- WebDKP_Print("从entry.points获取分数: " .. pointsToRestore)
                                else
                                    -- 尝试从awarded[playerName]中获取
                                    if type(entry.awarded[playerName]) == "number" then
                                        pointsToRestore = math.abs(entry.awarded[playerName])
                                        -- WebDKP_Print("从awarded[playerName]数字获取分数: " .. pointsToRestore)
                                    elseif type(entry.awarded[playerName]) == "table" then
                                        if entry.awarded[playerName].points then
                                            pointsToRestore = tonumber(entry.awarded[playerName].points) or 0
                                            -- WebDKP_Print("从awarded[playerName].points获取分数: " .. pointsToRestore)
                                        elseif entry.awarded[playerName].dkp then
                                            pointsToRestore = tonumber(entry.awarded[playerName].dkp) or 0
                                            -- WebDKP_Print("从awarded[playerName].dkp获取分数: " .. pointsToRestore)
                                        else
                                            -- 默认尝试从entry中获取
                                            pointsToRestore = tonumber(entry.points or 0)
                                            -- WebDKP_Print("使用默认分数: " .. pointsToRestore)
                                        end
                                    end
                                end
                                
                                -- 如果找到了要恢复的分数，使用WebDKP_AddDKP的负值来恢复DKP（更符合插件设计）
                                if pointsToRestore > 0 and WebDKP_DkpTable and WebDKP_DkpTable[playerName] then
                                    -- WebDKP_Print("尝试恢复玩家 " .. playerName .. " 的DKP分数: " .. pointsToRestore)
                                    
                                    -- 使用直接修改WebDKP_DkpTable的方式恢复DKP（与删除DKP记录的逻辑保持一致）
                                    local tableid = WebDKP_GetTableid()
                                    local dkpField = "dkp_"..tableid
                                    
                                    if type(WebDKP_DkpTable[playerName]) == "table" then
                                        -- 恢复原来添加的分数（删除加分记录时减去）
                                        local currentDKP = tonumber(WebDKP_DkpTable[playerName][dkpField] or WebDKP_DkpTable[playerName].dkp or 0)
                                        WebDKP_DkpTable[playerName][dkpField] = currentDKP - pointsToRestore
                                        pointsRestored = true
                                        totalPointsRestored = totalPointsRestored + pointsToRestore
                                    end
                                else
                                    WebDKP_Print("未能获取有效分数进行恢复: " .. tostring(pointsToRestore))
                                end
                                
                                -- 从记录中删除该玩家
                                entry.awarded[playerName] = nil
                                deleted = true
                                -- WebDKP_Print("已从WebDKP_Log删除玩家 " .. playerName .. " 的替补记录")
                                
                                -- 检查是否还有其他玩家
                                local hasOtherPlayers = false
                                for _, _ in pairs(entry.awarded) do
                                    hasOtherPlayers = true
                                    break
                                end
                                if not hasOtherPlayers then
                                    WebDKP_Log[key] = nil
                                    WebDKP_Print("该替补记录已无其他玩家，删除整个条目")
                                end
                                
                                break
                            end
                        end
                    end
                end
                
                -- 从WebDKP_DailySubRecords中删除
                if WebDKP_DailySubRecords then
                    local datePart = string.sub(timeString, 1, 10)
                    if WebDKP_DailySubRecords[datePart] and WebDKP_DailySubRecords[datePart][playerName] then
                        WebDKP_DailySubRecords[datePart][playerName] = nil
                        deleted = true
                        -- WebDKP_Print("已从WebDKP_DailySubRecords删除玩家 " .. playerName .. " 的替补记录")
                        
                        -- 检查当天是否还有其他记录
                        if WebDKP_GetTableSize(WebDKP_DailySubRecords[datePart]) == 0 then
                            WebDKP_DailySubRecords[datePart] = nil
                            WebDKP_Print("该日期已无其他替补记录，删除当天记录")
                        end
                    end
                end
                
                -- 如果成功删除，保存数据并刷新界面
                if deleted then
                    -- 保存数据到磁盘
                    if WebDKP_SaveToDisk then
                        WebDKP_SaveToDisk()
                    end
                    
                    -- 整合提示信息，明确显示删除和恢复状态
                    if pointsRestored then
                        WebDKP_Print("替补记录删除成功，恢复DKP:" .. tostring(totalPointsRestored))
                    else
                        WebDKP_Print("替补记录删除成功，但未能恢复DKP分数")
                    end
                    
                    -- 刷新相关界面
                    if WebDKP_Refresh then
                        WebDKP_Refresh()
                    end
                    if WebDKP_UpdateTable then
                        WebDKP_UpdateTable()
                    end
                    if WebDKP_UpdateLootList then
                        WebDKP_UpdateLootList()
                    end
                else
                    WebDKP_Print("未找到匹配的替补记录进行删除")
                end
                
                return deleted
            end
        end
                    
                    -- 检查WebDKP_GetLootRecords是否缺失，如果缺失则创建替代实现
        if not WebDKP_GetLootRecords then
            WebDKP_GetLootRecords = function()
                local records = {}
                
                -- 从日志中提取装备记录
                if WebDKP_Log and WebDKP_Log.Version then
                    for key, entry in pairs(WebDKP_Log) do
                        if type(entry) == "table" and key ~= "Version" and (entry.foritem == "true" or entry.foritem == true) then
                            -- 这是一个物品奖励记录
                            for playerName, playerInfo in pairs(entry.awarded or {}) do
                                local record = {
                                    item = entry.reason,
                                    player = playerName,
                                    cost = math.abs(entry.points),
                                    dkp = math.abs(entry.points), -- 添加dkp字段以兼容显示函数
                                    time = entry.date or "未知",
                                    date = entry.date or "未知" -- 添加date字段用于安全删除
                                }
                                table.insert(records, record)
                            end
                        end
                    end
                end
                
                -- 按时间倒序排序
                table.sort(records, function(a, b)
                    return a.time > b.time
                end)
                
                return records
            end
        end
        
        -- 检查WebDKP_GetSubstituteRecords是否缺失，如果缺失则创建替代实现
        if not WebDKP_GetSubstituteRecords then
            WebDKP_GetSubstituteRecords = function()
                local records = {}
                
                -- 从每日替补记录中提取信息
                if WebDKP_DailySubRecords then
                    for date, dayRecords in pairs(WebDKP_DailySubRecords) do
                        for playerName, playerInfo in pairs(dayRecords) do
                            -- 确保WebDKP_DailySubRecords中的location字段存在
                            local location = "未知" -- 默认值
                            if playerInfo and playerInfo.location then
                                location = playerInfo.location
                            end
                            
                            -- 尝试从当天的日志中查找对应的记录，获取更多详细信息
                            if WebDKP_Log then
                                for key, logEntry in pairs(WebDKP_Log) do
                                    if type(logEntry) == "table" and key ~= "Version" and logEntry.date and string.find(logEntry.date, date) and 
                                       logEntry.reason and string.find(logEntry.reason, "替补") and not (logEntry.foritem == "true" or logEntry.foritem == true) then
                                        
                                        -- 构建记录，确保使用WebDKP_DailySubRecords中的location
                                        local record = {
                                            item = logEntry.reason or "替补", -- 项目名称
                                            player = playerName, -- 玩家名称
                                            location = location, -- 玩家所在地，使用WebDKP_DailySubRecords中的值
                                            time = logEntry.date or date -- 加分时间
                                        }
                                        
                                        table.insert(records, record)
                                        break
                                    end
                                end
                            end
                        end
                    end
                end
            
                -- 补充从日志中提取的替补记录（包含"替补"关键词的记录）
                if WebDKP_Log then
                    for key, entry in pairs(WebDKP_Log) do
                        if type(entry) == "table" and key ~= "Version" and entry.reason and string.find(entry.reason, "替补") and not (entry.foritem == "true" or entry.foritem == true) then
                            -- 这是一个替补记录
                            for playerName, playerInfo in pairs(entry.awarded or {}) do
                                -- 检查是否已经添加过这个记录
                                local alreadyExists = false
                                for _, existingRecord in ipairs(records) do
                                    if existingRecord.player == playerName and existingRecord.time == entry.date then
                                        alreadyExists = true
                                        break
                                    end
                                end
                                
                                if not alreadyExists then
                                    -- 优先从WebDKP_DailySubRecords获取location信息
                                    local location = "未知"
                                    
                                    -- 尝试从WebDKP_DailySubRecords获取
                                    if WebDKP_DailySubRecords and entry.date then
                                        -- 提取日期部分
                                        local datePart = string.sub(entry.date, 1, 10)
                                        if WebDKP_DailySubRecords[datePart] and WebDKP_DailySubRecords[datePart][playerName] then
                                            location = WebDKP_DailySubRecords[datePart][playerName].location or "未知"
                                        end
                                    end
                                    
                                    -- 如果从WebDKP_DailySubRecords没有获取到，再尝试从WebDKP_SubData.subs获取
                                    if location == "未知" and WebDKP_SubData and WebDKP_SubData.subs and WebDKP_SubData.subs[playerName] then
                                        location = WebDKP_SubData.subs[playerName].location or "未知"
                                    end
                                    
                                    local record = {
                                        item = entry.reason, -- 项目名称
                                        player = playerName, -- 玩家名称
                                        location = location, -- 玩家所在地
                                        time = entry.date or "未知", -- 加分时间
                                        date = entry.date or "未知" -- 添加date字段用于安全删除
                                    }
                                    table.insert(records, record)
                                end
                            end
                        end
                    end
                end
                
                -- 按时间倒序排序
                table.sort(records, function(a, b)
                    return a.time > b.time
                end)
                
                return records
            end
        end
        
        -- 检查WebDKP_UpdateLootList是否缺失，如果缺失则创建替代实现
        if not WebDKP_UpdateLootList then
            
            WebDKP_UpdateLootList = function()
                -- 在魔兽世界1.12 Lua 5.0中，函数参数应该使用this和arg1，但这个函数不接收参数
                
                if not WebDKP_LootListFrame then
                    return
                end
                
                -- 获取窗口引用和当前模式
                local frame = WebDKP_LootListFrame
                local currentMode = frame and frame.currentMode or "loot"
                
                -- 切换列标题显示
                if frame and frame.columnHeaders then
                    -- 隐藏所有列标题
                    for _, headers in pairs(frame.columnHeaders) do
                        for _, header in ipairs(headers) do
                            header:Hide()
                        end
                    end
                    
                    -- 显示当前模式的列标题
                    if frame.columnHeaders[currentMode] then
                        for _, header in ipairs(frame.columnHeaders[currentMode]) do
                            header:Show()
                        end
                    end
                end
                
                -- 获取相应记录
                local records = {}
                if currentMode == "substitute" then
                    records = WebDKP_GetSubstituteRecords()
                elseif currentMode == "dkp" then
                    records = WebDKP_GetDKPRecords()
                else
                    records = WebDKP_GetLootRecords()
                end
                local numRecords = WebDKP_GetTableSize(records)
                
                -- 安全检查滚动框架 - 使用FauxScrollFrame
                local scrollFrame = WebDKP_LootListScrollFrame
                
                if not scrollFrame then
                    return
                end
                
                -- 设置滚动区域参数
                local lineHeight = 20
                local numToDisplay = 16 -- 可视区域能显示的行数，与创建的行框架数量一致
                
                -- 使用FauxScrollFrame的标准方式更新滚动条
                FauxScrollFrame_Update(scrollFrame, numRecords, numToDisplay, lineHeight)
                
                -- 获取滚动偏移 - FauxScrollFrame的标准方式
                local offset = FauxScrollFrame_GetOffset(scrollFrame) or 0
                
                -- 显示记录行，确保始终显示16行数据
                for i = 1, numToDisplay do
                    local recordIndex = offset + i
                    local record = records[recordIndex]
                    
                    -- 保存当前行的记录索引到行框架中，用于删除操作
                    local lineFrame = getglobal("WebDKP_LootListLine"..i)
                    if lineFrame then
                        lineFrame.recordIndex = recordIndex
                    end
                    
                    -- 确保即使在列表末尾也能显示满16行数据
                    -- 如果当前索引的记录不存在，调整offset重新计算
                    if not record then
                        -- 检查是否是因为接近列表末尾导致的记录不足
                        if recordIndex > numRecords then
                            -- 调整offset，确保能显示完整的16行
                            local adjustedOffset = numRecords - numToDisplay
                            if adjustedOffset < 0 then adjustedOffset = 0 end
                            offset = adjustedOffset
                            recordIndex = offset + i
                            record = records[recordIndex]
                        end
                    end
                    
                    -- 如果仍然没有记录，尝试使用后面的记录
                    if not record and recordIndex <= numRecords then
                        -- 查找后面的有效记录
                        for j = recordIndex + 1, numRecords do
                            if records[j] then
                                record = records[j]
                                break
                            end
                        end
                    end
                    
                    -- 获取预创建的行框架
                    local lineFrame = getglobal("WebDKP_LootListLine"..i)
                    
                    if lineFrame then
                        if record then
                            -- 在魔兽世界1.12 Lua 5.0中，确保所有操作都兼容
                            
                            -- 从WebDKP_GetLootRecords函数返回的数据中，字段名为cost
                            local dkpValue = record.cost or record.dkp or 0
                            
                            -- 确保dkpValue是数字
                            dkpValue = tonumber(dkpValue) or 0
                            
                            -- 根据当前模式设置文本内容
                            if currentMode == "substitute" then
                                -- 替补名单模式 - 显示当前加载的DKP列表名称在前面
                                if lineFrame.itemText then
                                    -- 获取当前加载的DKP列表名称
                                    local selectedTableName = WebDKP_GetTableNameById(WebDKP_Frame and WebDKP_Frame.selectedTableid or nil)
                                    
                                    -- 显示当前加载的DKP列表名称
                                    lineFrame.itemText:SetText("[" .. selectedTableName .. "] " .. (record.item or ""))
                                    lineFrame.itemText:SetTextColor(0.8, 0.8, 0.8)
                                end
                                if lineFrame.playerText then
                                    lineFrame.playerText:SetText(record.player or "") -- 玩家名称
                                    lineFrame.playerText:SetTextColor(0.8, 0.8, 0.8) -- 设置初始颜色
                                end
                                if lineFrame.locationText then
                                    lineFrame.locationText:SetText(record.location or "未知") -- 玩家所在地
                                    lineFrame.locationText:SetTextColor(0.8, 0.8, 0.8) -- 设置初始颜色
                                end
                                if lineFrame.addTimeText then
                                    lineFrame.addTimeText:SetText(record.time or "未知") -- 加分时间
                                    lineFrame.addTimeText:SetTextColor(0.8, 0.8, 0.8) -- 设置初始颜色
                                end
                            elseif currentMode == "dkp" then
                                -- DKP列表模式 - 显示[列表名称]项目名称
                                if lineFrame.itemText then
                                    -- 根据记录的tableid获取对应的列表名称
                                    local selectedTableName = WebDKP_GetTableNameById(record.tableid)
                                    
                                    -- 按照"[列表名称]项目名称"的格式显示
                                    local displayText = "[" .. selectedTableName .. "] " .. (record.item or "列表记录")
                                    lineFrame.itemText:SetText(displayText)
                                    lineFrame.itemText:SetTextColor(0.8, 0.8, 0.8) -- 设置初始颜色
                                end
                                if lineFrame.playerText then
                                    lineFrame.playerText:SetText(record.playerCount or "0") -- 玩家人数
                                    lineFrame.playerText:SetTextColor(0.8, 0.8, 0.8) -- 设置初始颜色
                                end
                                if lineFrame.costText then
                                    lineFrame.costText:SetText(record.score or "0") -- 分数
                                    lineFrame.costText:SetTextColor(0.8, 0.8, 0.8) -- 设置初始颜色
                                end
                                if lineFrame.timeText then
                                    lineFrame.timeText:SetText(record.time or "未知") -- 时间
                                    lineFrame.timeText:SetTextColor(0.8, 0.8, 0.8) -- 设置初始颜色
                                end
                            else
                                    -- 装备记录模式 - 显示项目名称在前面
                                    if lineFrame.itemText then
                                        -- 直接使用储存文件中的数据，不处理装备链接
                                        local displayItemName = record.item or ""
                                        lineFrame.itemText:SetText("[装备] " .. displayItemName) -- 项目名称带标识
                                        lineFrame.itemText:SetTextColor(0.8, 0.8, 0.8) -- 设置初始颜色
                                    end
                                    
                                    -- 为行框架添加点击事件，允许编辑项目名称或分数
                                    lineFrame:SetScript("OnMouseDown", function()
                                        local button = arg1
                                        if button == "LeftButton" then
                                            -- 获取点击位置
                                            local cursorX, cursorY = GetCursorPosition()
                                            local scale = lineFrame:GetEffectiveScale()
                                            local x = cursorX / scale
                                            local y = cursorY / scale
                                            
                                            if currentMode == "loot" then
                                                -- 检查点击是否在itemText区域内
                                                if lineFrame.itemText then
                                                    local frameX, frameY = lineFrame.itemText:GetCenter()
                                                    local frameWidth = lineFrame.itemText:GetWidth()
                                                    local frameHeight = lineFrame.itemText:GetHeight()
                                                    
                                                    if frameX and frameY then
                                                        local left = frameX - (frameWidth / 2)
                                                        local right = frameX + (frameWidth / 2)
                                                        local top = frameY + (frameHeight / 2)
                                                        local bottom = frameY - (frameHeight / 2)
                                                        
                                                        if x >= left and x <= right and y >= bottom and y <= top then
                                                            -- 创建一个输入框用于编辑项目名称
                                                            local editBox = CreateFrame("EditBox", "WebDKP_TempEditBox"..GetTime(), lineFrame, "InputBoxTemplate")
                                                            editBox:SetWidth(180)
                                                            editBox:SetHeight(20)
                                                            editBox:SetPoint("LEFT", lineFrame.itemText, "LEFT", 0, 0)
                                                            editBox:SetText(record.item or "")
                                                            editBox:Show()
                                                            editBox:SetFocus()
                                                            
                                                            -- 处理输入框失去焦点事件
                                                            editBox:SetScript("OnEscapePressed", function()
                                                                editBox:Hide()
                                                            end)
                                                            
                                                            editBox:SetScript("OnEnterPressed", function()
                                                                -- 添加对editBox和lineFrame的空值检查
                                                                if not editBox or not lineFrame or not lineFrame.itemText then
                                                                    WebDKP_Print("错误：编辑框或行框架不存在")
                                                                    editBox:Hide()
                                                                    return
                                                                end
                                                                
                                                                local newName = editBox:GetText()
                                                                if newName ~= "" and newName ~= (record.item or "") then
                                                                    -- 更新记录中的项目名称
                                                                    record.item = newName
                                                                    -- 更新显示
                                                                    lineFrame.itemText:SetText("[装备] " .. newName)
                                                                    -- 保存更改到日志
                                                                    
                                                                end
                                                                editBox:Hide()
                                                            end)
                                                            return  -- 处理完项目名称点击后直接返回
                                                        end
                                                    end
                                                end
                                                
                                                -- 检查点击是否在costText区域内
                                                if lineFrame.costText then
                                                    local frameX, frameY = lineFrame.costText:GetCenter()
                                                    local frameWidth = lineFrame.costText:GetWidth()
                                                    local frameHeight = lineFrame.costText:GetHeight()
                                                    
                                                    if frameX and frameY then
                                                        local left = frameX - (frameWidth / 2)
                                                        local right = frameX + (frameWidth / 2)
                                                        local top = frameY + (frameHeight / 2)
                                                        local bottom = frameY - (frameHeight / 2)
                                                        
                                                        if x >= left and x <= right and y >= bottom and y <= top then
                                                            -- 创建一个输入框用于编辑分数
                                                            local editBox = CreateFrame("EditBox", "WebDKP_TempEditBox"..GetTime(), lineFrame, "InputBoxTemplate")
                                                            editBox:SetWidth(60)
                                                            editBox:SetHeight(20)
                                                            editBox:SetPoint("LEFT", lineFrame.costText, "LEFT", 0, 0)
                                                            editBox:SetText(record.cost or "0")
                                                            editBox:Show()
                                                            editBox:SetFocus()
                                                            
                                                            -- 处理输入框失去焦点事件
                                                            editBox:SetScript("OnEscapePressed", function()
                                                                editBox:Hide()
                                                            end)
                                                            
                                                            editBox:SetScript("OnEnterPressed", function()
                                                                -- 添加对editBox和lineFrame的空值检查
                                                                if not editBox or not lineFrame or not lineFrame.costText then
                                                                    WebDKP_Print("错误：编辑框或行框架不存在")
                                                                    editBox:Hide()
                                                                    return
                                                                end
                                                                
                                                                local newCost = tonumber(editBox:GetText())
                                                                if newCost and newCost ~= (record.cost or 0) then
                                                                    -- 更新记录中的分数
                                                                    record.cost = newCost
                                                                    -- 更新显示
                                                                    lineFrame.costText:SetText(newCost)
                                                                    -- 保存更改到日志
                                                                    
                                                                end
                                                                editBox:Hide()
                                                            end)
                                                        end
                                                    end
                                                end
                                            elseif currentMode == "dkp" then
                                                -- 检查点击是否在itemText区域内（DKP模式）
                                                if lineFrame.itemText then
                                                    local frameX, frameY = lineFrame.itemText:GetCenter()
                                                    local frameWidth = lineFrame.itemText:GetWidth()
                                                    local frameHeight = lineFrame.itemText:GetHeight()
                                                    
                                                    if frameX and frameY then
                                                        local left = frameX - (frameWidth / 2)
                                                        local right = frameX + (frameWidth / 2)
                                                        local top = frameY + (frameHeight / 2)
                                                        local bottom = frameY - (frameHeight / 2)
                                                        
                                                        if x >= left and x <= right and y >= bottom and y <= top then
                                                            -- 创建一个输入框用于编辑DKP原因
                                                            local editBox = CreateFrame("EditBox", "WebDKP_TempEditBox"..GetTime(), lineFrame, "InputBoxTemplate")
                                                            editBox:SetWidth(180)
                                                            editBox:SetHeight(20)
                                                            editBox:SetPoint("LEFT", lineFrame.itemText, "LEFT", 0, 0)
                                                            editBox:SetText(record.item or "")
                                                            editBox:Show()
                                                            editBox:SetFocus()
                                                            
                                                            -- 处理输入框失去焦点事件
                                                            editBox:SetScript("OnEscapePressed", function()
                                                                editBox:Hide()
                                                            end)
                                                            
                                                            editBox:SetScript("OnEnterPressed", function()
                                                                -- 添加对editBox和lineFrame的空值检查
                                                                if not editBox or not lineFrame or not lineFrame.itemText then
                                                                    WebDKP_Print("错误：编辑框或行框架不存在")
                                                                    editBox:Hide()
                                                                    return
                                                                end
                                                                
                                                                local newName = editBox:GetText()
                                                                if newName ~= "" and newName ~= (record.item or "") then
                                                                    -- 更新记录中的项目名称
                                                                    record.item = newName
                                                                    -- 更新显示
                                                                    lineFrame.itemText:SetText(newName)
                                                                    -- 保存更改到日志
                                                                    
                                                                end
                                                                editBox:Hide()
                                                            end)
                                                            return  -- 处理完项目名称点击后直接返回
                                                        end
                                                    end
                                                end
                                                
                                                -- 检查点击是否在playerText区域内（DKP模式）- 玩家名称可编辑
                                                if lineFrame.playerText then
                                                    local frameX, frameY = lineFrame.playerText:GetCenter()
                                                    local frameWidth = lineFrame.playerText:GetWidth()
                                                    local frameHeight = lineFrame.playerText:GetHeight()
                                                    
                                                    if frameX and frameY then
                                                        local left = frameX - (frameWidth / 2)
                                                        local right = frameX + (frameWidth / 2)
                                                        local top = frameY + (frameHeight / 2)
                                                        local bottom = frameY - (frameHeight / 2)
                                                        
                                                        if x >= left and x <= right and y >= bottom and y <= top then
                                                            -- 创建一个输入框用于编辑玩家名称
                                                            local editBox = CreateFrame("EditBox", "WebDKP_TempEditBox"..GetTime(), lineFrame, "InputBoxTemplate")
                                                            editBox:SetWidth(100)
                                                            editBox:SetHeight(20)
                                                            editBox:SetPoint("LEFT", lineFrame.playerText, "LEFT", 0, 0)
                                                            editBox:SetText(record.player or "")
                                                            editBox:Show()
                                                            editBox:SetFocus()
                                                            
                                                            -- 处理输入框失去焦点事件
                                                            editBox:SetScript("OnEscapePressed", function()
                                                                editBox:Hide()
                                                            end)
                                                            
                                                            editBox:SetScript("OnEnterPressed", function()
                                                                -- 添加对editBox和lineFrame的空值检查
                                                                if not editBox or not lineFrame or not lineFrame.playerText then
                                                                    WebDKP_Print("错误：编辑框或行框架不存在")
                                                                    editBox:Hide()
                                                                    return
                                                                end
                                                                
                                                                local newPlayer = editBox:GetText()
                                                                if newPlayer ~= "" and newPlayer ~= (record.player or "") then
                                                                    -- 更新记录中的玩家名称
                                                                    record.player = newPlayer
                                                                    -- 更新显示
                                                                    lineFrame.playerText:SetText(newPlayer)
                                                                    -- 保存更改到日志
                                                                    
                                                                end
                                                                editBox:Hide()
                                                            end)
                                                        end
                                                    end
                                                end
                                                
                                                -- 检查点击是否在playerText区域内（装备记录模式）- 玩家名称可编辑
                                                if lineFrame.playerText then
                                                    local frameX, frameY = lineFrame.playerText:GetCenter()
                                                    local frameWidth = lineFrame.playerText:GetWidth()
                                                    local frameHeight = lineFrame.playerText:GetHeight()
                                                    
                                                    if frameX and frameY then
                                                        local left = frameX - (frameWidth / 2)
                                                        local right = frameX + (frameWidth / 2)
                                                        local top = frameY + (frameHeight / 2)
                                                        local bottom = frameY - (frameHeight / 2)
                                                        
                                                        if x >= left and x <= right and y >= bottom and y <= top then
                                                            -- 创建一个输入框用于编辑玩家名称
                                                            local editBox = CreateFrame("EditBox", "WebDKP_TempEditBox"..GetTime(), lineFrame, "InputBoxTemplate")
                                                            editBox:SetWidth(100)
                                                            editBox:SetHeight(20)
                                                            editBox:SetPoint("LEFT", lineFrame.playerText, "LEFT", 0, 0)
                                                            editBox:SetText(record.player or "")
                                                            editBox:Show()
                                                            editBox:SetFocus()
                                                            
                                                            -- 处理输入框失去焦点事件
                                                            editBox:SetScript("OnEscapePressed", function()
                                                                this:Hide()
                                                            end)
                                                            
                                                            editBox:SetScript("OnEnterPressed", function()
                                                                -- 添加对editBox和lineFrame的空值检查
                                                                if not editBox or not lineFrame or not lineFrame.playerText then
                                                                    WebDKP_Print("错误：编辑框或行框架不存在")
                                                                    editBox:Hide()
                                                                    return
                                                                end
                                                                
                                                                local newPlayer = editBox:GetText()
                                                                if newPlayer ~= "" and newPlayer ~= (record.player or "") then
                                                                    -- 更新记录中的玩家名称
                                                                    record.player = newPlayer
                                                                    -- 更新显示
                                                                    lineFrame.playerText:SetText(newPlayer)
                                                                    -- 保存更改到日志
                                                                    
                                                                end
                                                                editBox:Hide()
                                                            end)
                                                        end
                                                    end
                                                end
                                                
                                                -- 检查点击是否在costText区域内（DKP模式）
                                                if lineFrame.costText then
                                                    local frameX, frameY = lineFrame.costText:GetCenter()
                                                    local frameWidth = lineFrame.costText:GetWidth()
                                                    local frameHeight = lineFrame.costText:GetHeight()
                                                    
                                                    if frameX and frameY then
                                                        local left = frameX - (frameWidth / 2)
                                                        local right = frameX + (frameWidth / 2)
                                                        local top = frameY + (frameHeight / 2)
                                                        local bottom = frameY - (frameHeight / 2)
                                                        
                                                        if x >= left and x <= right and y >= bottom and y <= top then
                                                            -- 创建一个输入框用于编辑DKP分数
                                                            local editBox = CreateFrame("EditBox", "WebDKP_TempEditBox"..GetTime(), lineFrame, "InputBoxTemplate")
                                                            editBox:SetWidth(60)
                                                            editBox:SetHeight(20)
                                                            editBox:SetPoint("LEFT", lineFrame.costText, "LEFT", 0, 0)
                                                            editBox:SetText(record.cost or "0")
                                                            editBox:Show()
                                                            editBox:SetFocus()
                                                            
                                                            -- 处理输入框失去焦点事件
                                                            editBox:SetScript("OnEscapePressed", function()
                                                                this:Hide()
                                                            end)
                                                            
                                                            editBox:SetScript("OnEnterPressed", function()
                                                                -- 添加对editBox和lineFrame的空值检查
                                                                if not editBox or not lineFrame or not lineFrame.costText then
                                                                    WebDKP_Print("错误：编辑框或行框架不存在")
                                                                    editBox:Hide()
                                                                    return
                                                                end
                                                                
                                                                local newCost = tonumber(editBox:GetText())
                                                                if newCost and newCost ~= (record.cost or 0) then
                                                                    -- 更新记录中的分数
                                                                    record.cost = newCost
                                                                    -- 更新显示
                                                                    lineFrame.costText:SetText(newCost)
                                                                    -- 保存更改到日志
                                                                    
                                                                end
                                                                editBox:Hide()
                                                            end)
                                                        end
                                                    end
                                                end
                                            elseif currentMode == "substitute" then
                                                -- 检查点击是否在itemText区域内（替补模式）
                                                if lineFrame.itemText then
                                                    local frameX, frameY = lineFrame.itemText:GetCenter()
                                                    local frameWidth = lineFrame.itemText:GetWidth()
                                                    local frameHeight = lineFrame.itemText:GetHeight()
                                                    
                                                    if frameX and frameY then
                                                        local left = frameX - (frameWidth / 2)
                                                        local right = frameX + (frameWidth / 2)
                                                        local top = frameY + (frameHeight / 2)
                                                        local bottom = frameY - (frameHeight / 2)
                                                        
                                                        if x >= left and x <= right and y >= bottom and y <= top then
                                                            -- 创建一个输入框用于编辑替补原因
                                                            local editBox = CreateFrame("EditBox", "WebDKP_TempEditBox"..GetTime(), lineFrame, "InputBoxTemplate")
                                                            editBox:SetWidth(180)
                                                            editBox:SetHeight(20)
                                                            editBox:SetPoint("LEFT", lineFrame.itemText, "LEFT", 0, 0)
                                                            editBox:SetText(record.item or "")
                                                            editBox:Show()
                                                            editBox:SetFocus()
                                                            
                                                            -- 处理输入框失去焦点事件
                                                            editBox:SetScript("OnEscapePressed", function()
                                                                this:Hide()
                                                            end)
                                                            
                                                            editBox:SetScript("OnEnterPressed", function()
                                                                -- 添加对editBox和lineFrame的空值检查
                                                                if not editBox or not lineFrame or not lineFrame.itemText then
                                                                    WebDKP_Print("错误：编辑框或行框架不存在")
                                                                    editBox:Hide()
                                                                    return
                                                                end
                                                                
                                                                local newName = editBox:GetText()
                                                                if newName ~= "" and newName ~= (record.item or "") then
                                                                    -- 更新记录中的项目名称
                                                                    record.item = newName
                                                                    -- 更新显示
                                                                    lineFrame.itemText:SetText(newName)
                                                                    -- 保存更改到日志
                                                                    
                                                                end
                                                                editBox:Hide()
                                                            end)
                                                            return  -- 处理完项目名称点击后直接返回
                                                        end
                                                    end
                                                end
                                                
                                                -- 检查点击是否在playerText区域内（替补模式）- 玩家名称可编辑
                                                if lineFrame.playerText then
                                                    local frameX, frameY = lineFrame.playerText:GetCenter()
                                                    local frameWidth = lineFrame.playerText:GetWidth()
                                                    local frameHeight = lineFrame.playerText:GetHeight()
                                                    
                                                    if frameX and frameY then
                                                        local left = frameX - (frameWidth / 2)
                                                        local right = frameX + (frameWidth / 2)
                                                        local top = frameY + (frameHeight / 2)
                                                        local bottom = frameY - (frameHeight / 2)
                                                        
                                                        if x >= left and x <= right and y >= bottom and y <= top then
                                                            -- 创建一个输入框用于编辑玩家名称
                                                            local editBox = CreateFrame("EditBox", "WebDKP_TempEditBox"..GetTime(), lineFrame, "InputBoxTemplate")
                                                            editBox:SetWidth(100)
                                                            editBox:SetHeight(20)
                                                            editBox:SetPoint("LEFT", lineFrame.playerText, "LEFT", 0, 0)
                                                            editBox:SetText(record.player or "")
                                                            editBox:Show()
                                                            editBox:SetFocus()
                                                            
                                                            -- 处理输入框失去焦点事件
                                                            editBox:SetScript("OnEscapePressed", function()
                                                                editBox:Hide()
                                                            end)
                                                            
                                                            editBox:SetScript("OnEnterPressed", function()
                                                                -- 添加对editBox和lineFrame的空值检查
                                                                if not editBox or not lineFrame or not lineFrame.playerText then
                                                                    WebDKP_Print("错误：编辑框或行框架不存在")
                                                                    editBox:Hide()
                                                                    return
                                                                end
                                                                
                                                                local newPlayer = editBox:GetText()
                                                                if newPlayer ~= "" and newPlayer ~= (record.player or "") then
                                                                    -- 更新记录中的玩家名称
                                                                    record.player = newPlayer
                                                                    -- 更新显示
                                                                    lineFrame.playerText:SetText(newPlayer)
                                                                    -- 保存更改到日志
                                                                    
                                                                end
                                                                editBox:Hide()
                                                            end)
                                                        end
                                                    end
                                                end
                                                
                                                -- 检查点击是否在locationText区域内（替补模式）
                                                if lineFrame.locationText then
                                                    local frameX, frameY = lineFrame.locationText:GetCenter()
                                                    local frameWidth = lineFrame.locationText:GetWidth()
                                                    local frameHeight = lineFrame.locationText:GetHeight()
                                                    
                                                    if frameX and frameY then
                                                        local left = frameX - (frameWidth / 2)
                                                        local right = frameX + (frameWidth / 2)
                                                        local top = frameY + (frameHeight / 2)
                                                        local bottom = frameY - (frameHeight / 2)
                                                        
                                                        if x >= left and x <= right and y >= bottom and y <= top then
                                                            -- 创建一个输入框用于编辑替补位置
                                                            local editBox = CreateFrame("EditBox", "WebDKP_TempEditBox"..GetTime(), lineFrame, "InputBoxTemplate")
                                                            editBox:SetWidth(80)
                                                            editBox:SetHeight(20)
                                                            editBox:SetPoint("LEFT", lineFrame.locationText, "LEFT", 0, 0)
                                                            editBox:SetText(record.location or "")
                                                            editBox:Show()
                                                            editBox:SetFocus()
                                                            
                                                            -- 处理输入框失去焦点事件
                                                            editBox:SetScript("OnEscapePressed", function()
                                                                editBox:Hide()
                                                            end)
                                                            
                                                            editBox:SetScript("OnEnterPressed", function()
                                                                -- 添加对editBox和lineFrame的空值检查
                                                                if not editBox or not lineFrame or not lineFrame.locationText then
                                                                    WebDKP_Print("错误：编辑框或行框架不存在")
                                                                    editBox:Hide()
                                                                    return
                                                                end
                                                                
                                                                local newLocation = editBox:GetText()
                                                                if newLocation ~= (record.location or "") then
                                                                    -- 更新记录中的位置信息
                                                                    record.location = newLocation
                                                                    -- 更新显示
                                                                    lineFrame.locationText:SetText(newLocation)
                                                                    -- 保存更改到日志
                                                                    
                                                                end
                                                                editBox:Hide()
                                                            end)
                                                        end
                                                    end
                                                end
                                                
                                                -- 检查点击是否在playerText区域内（所有模式）- 玩家名称可编辑
                                                if lineFrame.playerText then
                                                    local frameX, frameY = lineFrame.playerText:GetCenter()
                                                    local frameWidth = lineFrame.playerText:GetWidth()
                                                    local frameHeight = lineFrame.playerText:GetHeight()
                                                    
                                                    if frameX and frameY then
                                                        local left = frameX - (frameWidth / 2)
                                                        local right = frameX + (frameWidth / 2)
                                                        local top = frameY + (frameHeight / 2)
                                                        local bottom = frameY - (frameHeight / 2)
                                                        
                                                        if x >= left and x <= right and y >= bottom and y <= top then
                                                            -- 创建一个输入框用于编辑玩家名称
                                                            local editBox = CreateFrame("EditBox", "WebDKP_TempEditBox"..GetTime(), lineFrame, "InputBoxTemplate")
                                                            editBox:SetWidth(100)
                                                            editBox:SetHeight(20)
                                                            editBox:SetPoint("LEFT", lineFrame.playerText, "LEFT", 0, 0)
                                                            editBox:SetText(record.player or "")
                                                            editBox:Show()
                                                            editBox:SetFocus()
                                                            
                                                            -- 处理输入框失去焦点事件
                                                            editBox:SetScript("OnEscapePressed", function()
                                                                editBox:Hide()
                                                            end)
                                                            
                                                            editBox:SetScript("OnEnterPressed", function()
                                                                -- 添加对editBox和lineFrame的空值检查
                                                                if not editBox or not lineFrame or not lineFrame.playerText then
                                                                    WebDKP_Print("错误：编辑框或行框架不存在")
                                                                    editBox:Hide()
                                                                    return
                                                                end
                                                                
                                                                local newPlayer = editBox:GetText()
                                                                if newPlayer ~= "" and newPlayer ~= (record.player or "") then
                                                                    -- 更新记录中的玩家名称
                                                                    record.player = newPlayer
                                                                    -- 更新显示
                                                                    lineFrame.playerText:SetText(newPlayer)
                                                                    -- 保存更改到日志
                                                                    
                                                                end
                                                                editBox:Hide()
                                                            end)
                                                        end
                                                    end
                                                end
                                                
                                                -- 检查点击是否在timeText区域内（所有模式）- 时间字段不可编辑
                                                if lineFrame.timeText then
                                                    local frameX, frameY = lineFrame.timeText:GetCenter()
                                                    local frameWidth = lineFrame.timeText:GetWidth()
                                                    local frameHeight = lineFrame.timeText:GetHeight()
                                                    
                                                    if frameX and frameY then
                                                        local left = frameX - (frameWidth / 2)
                                                        local right = frameX + (frameWidth / 2)
                                                        local top = frameY + (frameHeight / 2)
                                                        local bottom = frameY - (frameHeight / 2)
                                                        
                                                        if x >= left and x <= right and y >= bottom and y <= top then
                                                            -- 时间字段不可编辑，显示提示信息
                                                            WebDKP_Print("时间字段不可编辑")
                                                            -- 添加视觉反馈，短暂变红表示不可编辑
                                                            lineFrame.timeText:SetTextColor(1, 0.5, 0.5)
                                                            -- 0.5秒后恢复颜色
                                                            local timeText = lineFrame.timeText
                                                            local restoreColor = function()
                                                                timeText:SetTextColor(0.8, 0.8, 0.8)
                                                            end
                                                            -- 使用简单的延迟恢复
                                                            local elapsed = 0
                                                            timeText:SetScript("OnUpdate", function()
                                                                local elapsedTime = tonumber(arg1) or 0
                                                                elapsed = elapsed + elapsedTime
                                                                if elapsed >= 0.5 then
                                                                    restoreColor()
                                                                    timeText:SetScript("OnUpdate", nil)
                                                                end
                                                            end)
                                                        end
                                                    end
                                                end
                                            end
                                        end
                                    end)
                                    
                                    -- 添加鼠标进入事件，实现高亮效果
                                    lineFrame:SetScript("OnEnter", function()
                                        -- 高亮整行背景
                                        if lineFrame.highlightTexture then
                                            lineFrame.highlightTexture:Show()
                                        end
                                        -- 让文字颜色变亮
                                        if lineFrame.itemText then lineFrame.itemText:SetTextColor(1, 1, 1) end
                                        if lineFrame.playerText then lineFrame.playerText:SetTextColor(1, 1, 1) end
                                        if lineFrame.costText then lineFrame.costText:SetTextColor(1, 1, 1) end
                                        if lineFrame.timeText then lineFrame.timeText:SetTextColor(1, 1, 1) end
                                    end)
                                    
                                    -- 添加鼠标离开事件，取消高亮效果
                                    lineFrame:SetScript("OnLeave", function()
                                        -- 取消高亮整行背景
                                        if lineFrame.highlightTexture then
                                            lineFrame.highlightTexture:Hide()
                                        end
                                        -- 恢复文字颜色
                                        if lineFrame.itemText then lineFrame.itemText:SetTextColor(0.8, 0.8, 0.8) end
                                        if lineFrame.playerText then lineFrame.playerText:SetTextColor(0.8, 0.8, 0.8) end
                                        if lineFrame.costText then lineFrame.costText:SetTextColor(0.8, 0.8, 0.8) end
                                        if lineFrame.timeText then lineFrame.timeText:SetTextColor(0.8, 0.8, 0.8) end
                                    end)
                                    if lineFrame.playerText then
                                        lineFrame.playerText:SetText(record.player or "")
                                        lineFrame.playerText:SetTextColor(0.8, 0.8, 0.8) -- 设置初始颜色
                                    end
                                    if lineFrame.costText then
                                        lineFrame.costText:SetText(dkpValue)
                                        lineFrame.costText:SetTextColor(0.8, 0.8, 0.8) -- 设置初始颜色
                                    end
                                    if lineFrame.timeText then
                                        lineFrame.timeText:SetText(record.time or "未知")
                                        lineFrame.timeText:SetTextColor(0.8, 0.8, 0.8) -- 设置初始颜色
                                    end
                                end
                            
                            -- 创建删除按钮（如果不存在）
                            -- 创建修改按钮（改按钮）
                            if not lineFrame.editButton then
                                lineFrame.editButton = CreateFrame("Button", "WebDKP_LootListLine"..i.."EditButton", lineFrame, "UIPanelButtonTemplate")
                                lineFrame.editButton:SetWidth(20)
                                lineFrame.editButton:SetHeight(18)
                                lineFrame.editButton:SetText("改")
                                lineFrame.editButton:SetPoint("RIGHT", lineFrame, "RIGHT", -10, 2)
                                lineFrame.editButton:SetNormalTexture([[Interface\Buttons\UI-Panel-Button-Down]])
                                lineFrame.editButton:GetNormalTexture():SetVertexColor(1, 0, 0)
                                lineFrame.editButton:SetHighlightTexture([[Interface\Buttons\UI-Panel-Button-Highlight]])
                                lineFrame.editButton:GetHighlightTexture():SetVertexColor(1, 0, 0)
                                lineFrame.editButton:SetPushedTexture([[Interface\Buttons\UI-Panel-Button-Down]])
                                lineFrame.editButton:GetPushedTexture():SetVertexColor(1, 0, 0)
                                
                                -- 设置修改按钮文字颜色为红色
                                lineFrame.editButton:SetTextColor(1, 1, 1)
                                
                                -- 设置修改按钮鼠标进入事件，高亮对应的行
                                lineFrame.editButton:SetScript("OnEnter", function()
                                    local editButton = this
                                    -- 高亮整行背景
                                    local parentFrame = editButton:GetParent()
                                    if parentFrame and parentFrame.highlightTexture then
                                        parentFrame.highlightTexture:Show()
                                    end
                                    -- 让文字颜色变亮
                                    if parentFrame then
                                        if parentFrame.itemText then parentFrame.itemText:SetTextColor(1, 1, 1) end
                                        if parentFrame.playerText then parentFrame.playerText:SetTextColor(1, 1, 1) end
                                        if parentFrame.costText then parentFrame.costText:SetTextColor(1, 1, 1) end
                                        if parentFrame.timeText then parentFrame.timeText:SetTextColor(1, 1, 1) end
                                    end
                                    -- 修改按钮自身高亮效果
                                    editButton:SetTextColor(1, 0.5, 0.5)  -- 更亮的红色
                                    if editButton:GetNormalTexture() then
                                        editButton:GetNormalTexture():SetVertexColor(1.0, 0.3, 0.3)  -- 按钮纹理高亮
                                    end
                                end)
                                
                                -- 设置修改按钮鼠标离开事件，取消高亮对应的行
                                lineFrame.editButton:SetScript("OnLeave", function()
                                    local editButton = this
                                    -- 取消高亮整行背景
                                    local parentFrame = editButton:GetParent()
                                    if parentFrame and parentFrame.highlightTexture then
                                        parentFrame.highlightTexture:Hide()
                                    end
                                    -- 恢复文字颜色
                                    if parentFrame then
                                        if parentFrame.itemText then parentFrame.itemText:SetTextColor(0.8, 0.8, 0.8) end
                                        if parentFrame.playerText then parentFrame.playerText:SetTextColor(0.8, 0.8, 0.8) end
                                        if parentFrame.costText then parentFrame.costText:SetTextColor(0.8, 0.8, 0.8) end
                                        if parentFrame.timeText then parentFrame.timeText:SetTextColor(0.8, 0.8, 0.8) end
                                    end
                                    -- 恢复修改按钮自身颜色
                                    editButton:SetTextColor(1, 1, 1)  -- 恢复为红色
                                    if editButton:GetNormalTexture() then
                                        editButton:GetNormalTexture():SetVertexColor(1, 1, 1)  -- 恢复按钮纹理颜色
                                    end
                                end)
                                
                                -- 设置修改按钮点击事件
                                lineFrame.editButton:SetScript("OnClick", function()
                                    local editButton = this
                                    -- 添加对editButton和lineFrame的空值检查
                                    local lineFrame = editButton and editButton:GetParent()
                                    if not lineFrame then
                                        WebDKP_Print("错误：修改按钮或其父框架不存在")
                                        return
                                    end
                                    
                                    -- 获取当前行框架的ID和记录索引
                                    local lineFrameID = lineFrame:GetID()
                                    local currentRecordIndex = lineFrame.recordIndex
                                    
                                    -- 重新获取当前模式下的记录数据，确保使用最新的数据
                                    local currentRecords = {}
                                    local currentMode = WebDKP_LootListFrame.currentMode or "loot"
                                    if currentMode == "substitute" then
                                        currentRecords = WebDKP_GetSubstituteRecords()
                                    elseif currentMode == "dkp" then
                                        currentRecords = WebDKP_GetDKPRecords()
                                    else
                                        currentRecords = WebDKP_GetLootRecords()
                                    end
                                    
                                    -- 获取当前行对应的最新记录
                                    local latestRecord = currentRecords[currentRecordIndex]
                                    if not latestRecord then
                                        WebDKP_Print("错误：无法找到索引为 " .. (currentRecordIndex or "nil") .. " 的记录")
                                        return
                                    end
                                    
                                    -- 根据当前模式调用相应的修改对话框
                                    if currentMode == "dkp" then
                                        -- DKP模式下修改分数
                                        local uniqueId = latestRecord.uniqueId or currentRecordIndex
                                        local currentPoints = latestRecord.score or latestRecord.points or 0
                                        WebDKP_ShowEditDKPDialog(uniqueId, currentPoints)
                                    elseif currentMode == "loot" then
                                        -- 装备模式下修改物品和花费
                                        local uniqueId = latestRecord.uniqueId or currentRecordIndex
                                        local currentItem = latestRecord.reason or "未知物品"  -- 装备名称使用reason字段
                                        local currentPoints = math.abs(tonumber(latestRecord.points) or 0)
                                        WebDKP_ShowEditLootDialog(uniqueId, currentItem, currentPoints)
                                    elseif currentMode == "substitute" then
                                        -- 替补模式下修改原因和分数
                                        local uniqueId = latestRecord.uniqueId or currentRecordIndex
                                        local currentReason = latestRecord.reason or "替补记录"
                                        local currentPoints = latestRecord.score or latestRecord.points or 0
                                        WebDKP_ShowEditSubstituteDialog(uniqueId, currentReason, currentPoints)
                                    else
                                        WebDKP_Print("不支持修改当前记录类型")
                                    end
                                end)
                            end
                            
                            -- 创建删除按钮（X按钮）
                            if not lineFrame.deleteButton then
                                lineFrame.deleteButton = CreateFrame("Button", "WebDKP_LootListLine"..i.."DeleteButton", lineFrame, "UIPanelButtonTemplate")
                                lineFrame.deleteButton:SetWidth(20)
                                lineFrame.deleteButton:SetHeight(18)
                                lineFrame.deleteButton:SetText("X")
                                lineFrame.deleteButton:SetPoint("RIGHT", lineFrame, "RIGHT", -20, 2)
                                lineFrame.deleteButton:SetNormalTexture([[Interface\Buttons\UI-Panel-Button-Down]])
                            lineFrame.deleteButton:GetNormalTexture():SetVertexColor(1, 0, 0)
                                lineFrame.deleteButton:SetHighlightTexture([[Interface\Buttons\UI-Panel-Button-Highlight]])
                                lineFrame.deleteButton:GetHighlightTexture():SetVertexColor(1, 0, 0)
                                lineFrame.deleteButton:SetPushedTexture([[Interface\Buttons\UI-Panel-Button-Down]])
                            lineFrame.deleteButton:GetPushedTexture():SetVertexColor(1, 0, 0)
                            
                            -- 设置删除按钮文字颜色为鲜红色
                            lineFrame.deleteButton:SetTextColor(1, 1, 1)
                                
                                -- 设置删除按钮鼠标进入事件，高亮对应的行
                                lineFrame.deleteButton:SetScript("OnEnter", function()
                                    local deleteButton = this
                                    -- 高亮整行背景
                                    local parentFrame = deleteButton:GetParent()
                                    if parentFrame and parentFrame.highlightTexture then
                                        parentFrame.highlightTexture:Show()
                                    end
                                    -- 让文字颜色变亮
                                    if parentFrame then
                                        if parentFrame.itemText then parentFrame.itemText:SetTextColor(1, 1, 1) end
                                        if parentFrame.playerText then parentFrame.playerText:SetTextColor(1, 1, 1) end
                                        if parentFrame.costText then parentFrame.costText:SetTextColor(1, 1, 1) end
                                        if parentFrame.timeText then parentFrame.timeText:SetTextColor(1, 1, 1) end
                                    end
                                    -- 删除按钮自身高亮效果
                                    deleteButton:SetTextColor(1, 0.5, 0.5)  -- 更亮的红色
                                    if deleteButton:GetNormalTexture() then
                                        deleteButton:GetNormalTexture():SetVertexColor(1.0, 0.3, 0.3)  -- 按钮纹理高亮
                                    end
                                end)
                                
                                -- 设置删除按钮鼠标离开事件，取消高亮对应的行
                                lineFrame.deleteButton:SetScript("OnLeave", function()
                                    local deleteButton = this
                                    -- 取消高亮整行背景
                                    local parentFrame = deleteButton:GetParent()
                                    if parentFrame and parentFrame.highlightTexture then
                                        parentFrame.highlightTexture:Hide()
                                    end
                                    -- 恢复文字颜色
                                    if parentFrame then
                                        if parentFrame.itemText then parentFrame.itemText:SetTextColor(0.8, 0.8, 0.8) end
                                        if parentFrame.playerText then parentFrame.playerText:SetTextColor(0.8, 0.8, 0.8) end
                                        if parentFrame.costText then parentFrame.costText:SetTextColor(0.8, 0.8, 0.8) end
                                        if parentFrame.timeText then parentFrame.timeText:SetTextColor(0.8, 0.8, 0.8) end
                                    end
                                    -- 恢复删除按钮自身颜色
                                    deleteButton:SetTextColor(1, 1, 1)  -- 恢复为鲜红色
                                    if deleteButton:GetNormalTexture() then
                                        deleteButton:GetNormalTexture():SetVertexColor(1, 1, 1)  -- 恢复按钮纹理颜色
                                    end
                                end)
                                
                                -- 设置删除按钮点击事件
                                lineFrame.deleteButton:SetScript("OnClick", function()
                                    local deleteButton = this
                                    -- 添加对deleteButton和lineFrame的空值检查
                                    local lineFrame = deleteButton and deleteButton:GetParent()
                                    if not lineFrame then
                                        WebDKP_Print("错误：删除按钮或其父框架不存在")
                                        return
                                    end
                                    
                                    -- 获取当前行框架的ID和记录索引
                                    local lineFrameID = lineFrame:GetID()
                                    local currentRecordIndex = lineFrame.recordIndex
                                    
                                    -- 重新获取当前模式下的记录数据，确保使用最新的数据
                                    local currentRecords = {}
                                    local currentMode = WebDKP_LootListFrame.currentMode or "loot"
                                    if currentMode == "substitute" then
                                        currentRecords = WebDKP_GetSubstituteRecords()
                                    elseif currentMode == "dkp" then
                                        currentRecords = WebDKP_GetDKPRecords()
                                    else
                                        currentRecords = WebDKP_GetLootRecords()
                                    end
                                    
                                    -- 获取当前行对应的最新记录
                                    local latestRecord = currentRecords[currentRecordIndex]
                                    if not latestRecord then
                                        WebDKP_Print("错误：无法找到索引为 " .. (currentRecordIndex or "nil") .. " 的记录")
                                        return
                                    end
                                    
                                    -- 保存记录引用和当前模式（使用全局变量以便在确认对话框中访问）
                                    -- 创建一个新的记录对象，确保包含所有必要字段
                                    WebDKP_CurrentRecord = {}
                                    
                                    -- 根据不同模式正确获取字段信息，避免信息混淆
                                    if currentMode == "dkp" then
                                        -- DKP记录主要使用reason字段作为项目名称
                                        WebDKP_CurrentRecord.item = latestRecord.reason or latestRecord.item or "未知项目"
                                        WebDKP_CurrentRecord.time = latestRecord.date or latestRecord.time or date()
                                        WebDKP_CurrentRecord.player = latestRecord.name or latestRecord.player or "未知玩家"
                                    elseif currentMode == "substitute" then
                                        -- 替补记录使用reason字段作为项目名称
                                        WebDKP_CurrentRecord.item = latestRecord.reason or latestRecord.item or "替补记录"
                                        WebDKP_CurrentRecord.time = latestRecord.date or latestRecord.time or date()
                                        WebDKP_CurrentRecord.player = latestRecord.name or latestRecord.player or "未知玩家"
                                    elseif currentMode == "loot" then
                                        -- 装备记录使用reason字段作为装备名称
                                        WebDKP_CurrentRecord.item = latestRecord.reason or "未知装备"
                                        WebDKP_CurrentRecord.time = latestRecord.date or latestRecord.time or date()
                                        WebDKP_CurrentRecord.player = latestRecord.name or latestRecord.player or "未知玩家"
                                    else
                                        -- 默认处理
                                        WebDKP_CurrentRecord.item = latestRecord.item or latestRecord.reason or latestRecord.lootitem or "未知物品"
                                        WebDKP_CurrentRecord.time = latestRecord.time or latestRecord.date or date()
                                        WebDKP_CurrentRecord.player = latestRecord.player or latestRecord.name or "未知玩家"
                                    end
                                    WebDKP_CurrentRecord.rawRecord = latestRecord -- 保存原始记录引用，便于后续操作
                                     
                                    -- 根据模式确保包含特定字段
                                    if currentMode == "substitute" then
                                        WebDKP_CurrentRecord.location = latestRecord.location or "未知"
                                    elseif currentMode == "loot" then
                                        WebDKP_CurrentRecord.points = latestRecord.points or 0
                                    elseif currentMode == "dkp" then
                                        WebDKP_CurrentRecord.tableid = latestRecord.tableid
                                        WebDKP_CurrentRecord.score = latestRecord.score
                                    end
                                    
                                    -- 保存当前记录的索引，用于在删除后刷新UI
                                    WebDKP_CurrentRecordIndex = currentRecordIndex
                                    
                                    -- 同时保存行框架的ID，用于在删除后准确定位
                                    WebDKP_CurrentLineFrameID = lineFrameID
                                     
                                    -- 添加详细的调试信息
                                    -- WebDKP_Print("记录原始数据 - item: " .. (latestRecord.item or "nil") .. ", player: " .. (latestRecord.player or "nil") .. ", time: " .. (latestRecord.time or "nil") .. ", date: " .. (latestRecord.date or "nil"))
                                    
                                    WebDKP_CurrentRecordMode = WebDKP_LootListFrame.currentMode -- 直接使用frame的currentMode属性，确保获取正确的模式
                                    WebDKP_CurrentRecordUniqueId = latestRecord.uniqueId or currentRecordIndex  -- 保存当前记录的唯一标识符
                                    

                                    -- 显示确认删除对话框 - 在WoW 1.12中，text字段必须是字符串，不能是函数
                                    -- 通用删除函数，用于处理不同模式的删除逻辑
                                    -- 统一删除记录函数，根据模式调用对应的删除方法
                                    function DeleteRecordByMode(mode, record)
                                        local success = false
                                        
                                        -- 添加调试信息
                                        -- WebDKP_Print("尝试删除记录 - 模式: " .. (mode or "未知") .. ", uniqueId: " .. (WebDKP_CurrentRecordUniqueId or "无"))
                                        
                                        -- 优先尝试使用uniqueId进行精确删除
                                        if WebDKP_CurrentRecordUniqueId then
                                            -- 根据模式使用对应的删除函数
                                            if mode == "dkp" then
                                                success = WebDKP_DeleteDKPRecord(WebDKP_CurrentRecordUniqueId)
                                            elseif mode == "substitute" then
                                                -- 替补记录使用玩家和时间进行删除
                                                if record.player and record.time then
                                                    success = WebDKP_DeleteSubstituteRecord(record.player, record.time)
                                                end
                                            elseif mode == "loot" then
                                                -- 装备记录使用项目名、玩家名和时间进行删除
                                                if record.item and record.player and record.time then
                                                    success = WebDKP_DeleteLootRecord(record.item, record.player, record.time)
                                                end
                                            end
                                            
                                            if success then
                                                -- WebDKP_Print("使用uniqueId成功删除记录")
                                            else
                                                -- WebDKP_Print("使用uniqueId删除记录失败，尝试其他方式")
                                            end
                                        end
                                        
                                        -- 如果uniqueId删除失败，根据模式使用特定方法
                                        if not success then
                                            if mode == "dkp" then
                                                local item = record.item
                                                local time = record.time
                                                if item and time then
                                                    success = WebDKP_DeleteDKPRecordByItemAndTime(item, time)
                                                end
                                            elseif mode == "substitute" then
                                                local player = record.player
                                                local item = record.item
                                                local time = record.time
                                                if player and item and time then  -- 所有字段必须都存在
                                                    success = WebDKP_DeleteSubstituteRecordByItemAndTime(player, item, time)
                                                end
                                            elseif mode == "loot" then
                                                local item = record.item
                                                local player = record.player
                                                local time = record.time
                                                if item and player and time then  -- 所有字段必须都存在
                                                    success = WebDKP_DeleteLootRecord(item, player, time)
                                                end
                                            end
                                            
                                            if success then
                                                -- WebDKP_Print("使用字段匹配成功删除记录")
                                            end
                                        end
                                        
                                        return success
                                    end
                                    
                                    -- 通用备选删除方案，直接遍历WebDKP_Log
                                    -- 改进的备选删除函数 - 提高删除逻辑的准确性和稳定性
                                    function FallbackDeleteRecord(mode, record)
                                        local success = false
                                        local item = record.item
                                        local player = record.player
                                        local time = record.time
                                        
                                        -- WebDKP_Print("原始方法失败，尝试直接遍历WebDKP_Log删除记录")
                                        -- WebDKP_Print("删除模式: " .. (mode or "未知") .. ", 项目: " .. (item or "无") .. ", 玩家: " .. (player or "无") .. ", 时间: " .. (time or "无"))
                                        
                                        -- 遍历WebDKP_Log查找匹配的记录（反向遍历避免索引问题）
                                        local keysToRemove = {}  -- 记录需要删除的键
                                        local entriesToUpdate = {}  -- 记录需要更新的条目
                                        
                                        for logKey, logEntry in pairs(WebDKP_Log) do
                                            -- 跳过非表类型的条目和版本信息
                                            if type(logEntry) == "table" and logKey ~= "Version" then
                                                local isLootRecord = logEntry.foritem == true or logEntry.foritem == "true"
                                                local isSubstituteRecord = logEntry.reason and string.find(logEntry.reason, "替补")
                                                
                                                -- 根据模式判断是否为目标记录类型
                                                local isTargetRecord = false
                                                if mode == "dkp" then
                                                    isTargetRecord = not isLootRecord and not isSubstituteRecord
                                                elseif mode == "substitute" then
                                                    isTargetRecord = isSubstituteRecord and not isLootRecord
                                                elseif mode == "loot" then
                                                    isTargetRecord = isLootRecord
                                                end
                                                
                                                if isTargetRecord then
                                                    local matchFound = false
                                                    
                                                    if mode == "dkp" then
                                                        -- DKP记录匹配条件：reason匹配且date匹配
                                                        local reasonMatch = logEntry.reason and item and (logEntry.reason == item)
                                                        local timeMatch = time and logEntry.date and (logEntry.date == time)
                                                        matchFound = reasonMatch and timeMatch
                                                    elseif mode == "substitute" then
                                                        -- 替补记录匹配条件：玩家匹配且date匹配
                                                        local playerMatch = player and logEntry.awarded and logEntry.awarded[player]
                                                        local timeMatch = time and logEntry.date and (logEntry.date == time)
                                                        matchFound = playerMatch and timeMatch
                                                    elseif mode == "loot" then
                                                        -- 装备记录匹配条件：reason匹配且date匹配且玩家匹配
                                                        local itemMatch = item and logEntry.reason and (logEntry.reason == item)
                                                        local playerMatch = player and logEntry.awarded and logEntry.awarded[player]
                                                        local timeMatch = time and logEntry.date and (logEntry.date == time)
                                                        matchFound = itemMatch and playerMatch and timeMatch
                                                    end
                                                    
                                                    if matchFound then
                                                        if mode == "dkp" then
                                                            -- DKP记录直接标记删除
                                                            table.insert(keysToRemove, logKey)
                                                            success = true
                                                            WebDKP_Print("标记删除DKP记录 - 键: " .. tostring(logKey))
                                                        else
                                                            -- 替补和装备记录需要处理玩家
                                                            if logEntry.awarded then
                                                                local playersToRemove = {}
                                                                for awardedPlayer, _ in pairs(logEntry.awarded) do
                                                                    local shouldDelete = false
                                                                    
                                                                    if mode == "substitute" then
                                                                        -- 替补记录：玩家名和时间都匹配时删除
                                                                        local playerMatches = player and awardedPlayer == player
                                                                        local timeMatches = time and logEntry.date and (logEntry.date == time)
                                                                        shouldDelete = playerMatches and timeMatches
                                                                    elseif mode == "loot" then
                                                                        -- 装备记录：玩家名、物品名和时间都匹配时删除
                                                                        local playerMatches = player and awardedPlayer == player
                                                                        local itemMatches = item and logEntry.reason and (logEntry.reason == item)
                                                                        local timeMatches = time and logEntry.date and (logEntry.date == time)
                                                                        shouldDelete = playerMatches and itemMatches and timeMatches
                                                                    end
                                                                    
                                                                    if shouldDelete then
                                                                        table.insert(playersToRemove, awardedPlayer)
                                                                        success = true
                                                                        WebDKP_Print("标记删除玩家记录 - 玩家: " .. tostring(awardedPlayer) .. ", 键: " .. tostring(logKey))
                                                                    end
                                                                end
                                                                
                                                                if table.getn(playersToRemove) > 0 then
                                                                    -- 记录需要更新的条目
                                                                    entriesToUpdate[logKey] = {
                                                                        entry = logEntry,
                                                                        playersToRemove = playersToRemove
                                                                    }
                                                                end
                                                            end
                                                        end
                                                    end
                                                end
                                            end
                                        end
                                        
                                        -- 执行实际删除操作
                                        -- 1. 删除完整的记录
                                        for _, key in ipairs(keysToRemove) do
                                            WebDKP_Log[key] = nil
                                            WebDKP_Print("成功删除完整记录 - 键: " .. tostring(key))
                                        end
                                        
                                        -- 2. 删除玩家记录
                                        for key, data in pairs(entriesToUpdate) do
                                            local entry = data.entry
                                            local playersToRemove = data.playersToRemove
                                            
                                            for _, playerToRemove in ipairs(playersToRemove) do
                                                entry.awarded[playerToRemove] = nil
                                            end
                                            
                                            -- 检查是否还有玩家，如果没有则删除整个记录
                                            local playerCount = 0
                                            for _ in pairs(entry.awarded) do playerCount = playerCount + 1 end
                                            
                                            if playerCount == 0 then
                                                WebDKP_Log[key] = nil
                                                WebDKP_Print("删除最后一个玩家后，移除完整记录 - 键: " .. tostring(key))
                                            else
                                                WebDKP_Print("成功删除玩家记录，剩余玩家数: " .. playerCount .. " - 键: " .. tostring(key))
                                            end
                                        end
                                        
                                        if success then
                                            WebDKP_Print("备选删除方案执行完成")
                                        else
                                            WebDKP_Print("备选删除方案未找到匹配记录")
                                        end
                                        
                                        return success
                                    end
                                    
                                    StaticPopupDialogs["CONFIRM_DELETE_RECORD"] = {
                                        text = "确定要删除这条记录吗？", -- 默认文本，稍后会在显示前动态修改
                                        button1 = "确定",
                                        button2 = "取消",
                                        OnAccept = function()
                                            -- 根据当前模式调用不同的删除函数
                                            local success = false
                                            local mode = WebDKP_CurrentRecordMode
                                            local record = WebDKP_CurrentRecord
                                            
                         
                                            
                                            if mode == "dkp" or mode == "substitute" or mode == "loot" then
                                                -- WebDKP_Print("删除记录，模式: " .. mode .. ", 项目: " .. (record.item or "未知") .. ", 玩家: " .. (record.player or "未知") .. ", 时间: " .. (record.time or "未知") .. ", UniqueId: " .. (WebDKP_CurrentRecordUniqueId or "无"))
                                                
                                                -- 检查必要字段
                                                local hasRequiredFields = false
                                                if mode == "dkp" then
                                                    hasRequiredFields = record.item and record.time
                                                elseif mode == "substitute" then
                                                    hasRequiredFields = record.player and record.time
                                                elseif mode == "loot" then
                                                    hasRequiredFields = record.item and record.player and record.time
                                                end
                                                
                                                if hasRequiredFields then
                                                    -- 尝试标准删除方法
                                                    success = DeleteRecordByMode(mode, record)
                                                    
                                                    -- 如果标准方法失败，尝试备选方案
                                                    if not success then
                                                        -- WebDKP_Print("标准删除方法失败，尝试备选方案")
                                                        success = FallbackDeleteRecord(mode, record)
                                                    end
                                                else
                                                    -- WebDKP_Print("删除失败 - 缺少必要字段")
                                                    if mode == "dkp" then
                                                        -- WebDKP_Print("DKP记录需要: item=" .. (record.item or "nil") .. ", time=" .. (record.time or "nil"))
                                                    elseif mode == "substitute" then
                                                        -- WebDKP_Print("替补记录需要: player=" .. (record.player or "nil") .. ", time=" .. (record.time or "nil"))
                                                    elseif mode == "loot" then
                                                        -- WebDKP_Print("装备记录需要: item=" .. (record.item or "nil") .. ", player=" .. (record.player or "nil") .. ", time=" .. (record.time or "nil"))
                                                    end
                                                end
                                            else
                                                -- WebDKP_Print("删除失败 - 不支持的模式")
                                                WebDKP_Print("当、前模式: " .. (mode or "nil"))
                                            end
                                            
                                            -- 显示删除结果
                                            if success then
                                                WebDKP_Print("记录已成功删除。")
                                                -- 保存当前滚动位置
                                                local currentOffset = 0
                                                if WebDKP_LootListScrollFrame then
                                                    currentOffset = FauxScrollFrame_GetOffset(WebDKP_LootListScrollFrame) or 0
                                                end
                                                
                                                -- 更新列表
                                                WebDKP_UpdateLootList()
                                                
                                                -- 重置滚动位置以确保UI正确显示
                                                if WebDKP_LootListScrollFrame then
                                                    -- 如果当前偏移大于0，保持滚动位置不变
                                                    -- 否则重置到顶部
                                                    if currentOffset > 0 then
                                                        -- 重新计算偏移量，确保不超过最大值
                                                        local records = {}
                                                        local frame = WebDKP_LootListFrame
                                                        local currentMode = frame and frame.currentMode or "loot"
                                                        
                                                        if currentMode == "substitute" then
                                                            records = WebDKP_GetSubstituteRecords()
                                                        elseif currentMode == "dkp" then
                                                            records = WebDKP_GetDKPRecords()
                                                        else
                                                            records = WebDKP_GetLootRecords()
                                                        end
                                                        
                                                        local numRecords = WebDKP_GetTableSize(records)
                                                        local numToDisplay = 16
                                                        local maxOffset = math.max(0, numRecords - numToDisplay)
                                                        
                                                        if currentOffset > maxOffset then
                                                            currentOffset = maxOffset
                                                        end
                                                        
                                                        if currentOffset >= 0 then
                                                            FauxScrollFrame_SetOffset(WebDKP_LootListScrollFrame, currentOffset)
                                                        end
                                                    else
                                                        WebDKP_LootListScrollFrame:SetVerticalScroll(0)
                                                    end
                                                end
                                                
                                                -- 强制刷新UI以确保删除按钮位置正确，但不关闭窗口
                                                if WebDKP_LootListFrame then
                                                    -- 保存当前模式
                                                    local currentMode = WebDKP_LootListFrame.currentMode or "loot"
                                                    -- 先隐藏所有行框架
                                                    for j = 1, 16 do
                                                        local lineFrame = getglobal("WebDKP_LootListLine" .. j)
                                                        if lineFrame then
                                                            lineFrame:Hide()
                                                            if lineFrame.deleteButton then
                                                                lineFrame.deleteButton:Hide()
                                                            end
                                                        end
                                                    end
                                                    -- 直接更新列表显示而不切换窗口状态
                                                    WebDKP_UpdateLootList()
                                                end
                                            else
                                                WebDKP_Print("删除记录失败。")
                                                -- 更新列表以确保UI状态正确
                                                WebDKP_UpdateLootList()
                                            end
                                        end,
                                        timeout = 0,
                                        whileDead = true,
                                        hideOnEscape = true
                                    }                                    
 
                                    -- 为确认对话框设置文本，确保即使字段不完整也能显示有用信息
                                    if WebDKP_CurrentRecordMode == "dkp" then
                                        local dkpText = "确定要删除DKP记录吗？"
                                        if WebDKP_CurrentRecord.item then
                                            dkpText = "确定要删除DKP记录：" .. WebDKP_CurrentRecord.item .. "吗？"
                                        end
                                        StaticPopupDialogs["CONFIRM_DELETE_RECORD"].text = dkpText
                                    elseif WebDKP_CurrentRecordMode == "substitute" then
                                        -- 为替补模式创建更明确的显示文本，确保不显示DKP列表内容
                                        local substituteText = "确定要删除替补记录吗？"
                                        if WebDKP_CurrentRecord.player and WebDKP_CurrentRecord.time then
                                            substituteText = "确定要删除替补记录: " .. (WebDKP_CurrentRecord.player or "未知玩家") .. " (" .. (WebDKP_CurrentRecord.time or "未知时间") .. ") 吗？"
                                        elseif WebDKP_CurrentRecord.player then
                                            substituteText = "确定要删除替补记录: " .. (WebDKP_CurrentRecord.player or "未知玩家") .. " 吗？"
                                        end
                                        StaticPopupDialogs["CONFIRM_DELETE_RECORD"].text = substituteText
                                    elseif WebDKP_CurrentRecordMode == "loot" then
                                        -- 为装备模式创建更明确的显示文本，确保不显示DKP列表内容
                                        local lootText = "确定要删除装备记录吗？"
                                        -- 直接使用储存文件中的数据，不处理装备链接
                                        local displayItemName = WebDKP_CurrentRecord.item or "未知物品"
                                        if WebDKP_CurrentRecord.item and WebDKP_CurrentRecord.player then
                                            lootText = "确定要删除装备记录: " .. displayItemName .. " (获得者: " .. (WebDKP_CurrentRecord.player or "未知") .. ") 吗？"
                                        elseif WebDKP_CurrentRecord.item then
                                            lootText = "确定要删除装备记录: " .. displayItemName .. " 吗？"
                                        end
                                        StaticPopupDialogs["CONFIRM_DELETE_RECORD"].text = lootText
                                    else
                                        StaticPopupDialogs["CONFIRM_DELETE_RECORD"].text = "确定要删除这条记录吗？"
                                    end
                                    StaticPopup_Show("CONFIRM_DELETE_RECORD")
                                end)
                            end
                            
                            -- 显示行和按钮
                            lineFrame:Show()
                            lineFrame.deleteButton:Show()
                            
                            -- 在DKP、装备获取记录和替补名单模式下都显示修改按钮
                            local currentMode = WebDKP_LootListFrame.currentMode or "loot"
                            if lineFrame.editButton then
                                if currentMode == "dkp" or currentMode == "loot" or currentMode == "substitute" then
                                    lineFrame.editButton:Show()
                                else
                                    lineFrame.editButton:Hide()
                                end
                            end
                        else
                            -- 隐藏空行
                            lineFrame:Hide()
                            if lineFrame.deleteButton then
                                lineFrame.deleteButton:Hide()
                            end
                            if lineFrame.editButton then
                                lineFrame.editButton:Hide()
                            end
                        end
                    else
                        -- 如果没有找到预创建的行框架，尝试创建一个简单的行框架
                        lineFrame = CreateFrame("Frame", "WebDKP_LootListLine"..i, frame)
                        lineFrame:SetWidth(560)
                        lineFrame:SetHeight(lineHeight)
                        lineFrame:SetPoint("TOPLEFT", scrollFrame, "TOPLEFT", 0, -(i-1)*lineHeight)
                        
                        -- 创建背景
                        local bg = lineFrame:CreateTexture(nil, "BACKGROUND")
                        bg:SetAllPoints(lineFrame)
                        bg:SetTexture(0.1, 0.1, 0.1, 0.3)
                        
                        -- 创建高亮纹理 - 使用ARTWORK层级确保在WoW 1.12中正常工作
                        local highlightTexture = lineFrame:CreateTexture(nil, "ARTWORK")
                        highlightTexture:SetAllPoints(lineFrame)
                        highlightTexture:SetTexture(0.2, 0.5, 1.0, 0.9) -- 更亮的蓝色，更高的透明度
                        highlightTexture:Hide()
                        lineFrame.highlightTexture = highlightTexture
                        
                        -- 创建简单的文本框
                        local text = lineFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                        text:SetPoint("LEFT", lineFrame, "LEFT", 10, 0)
                        text:SetText("未找到预创建的行框架")
                        
                        lineFrame:Show()
                    end
                end
            end
        end
    else
        -- WebDKP_Print("错误: WebDKP_LootList.lua 未正确加载，WebDKP_ToggleLootList 函数不存在。")
        
        -- 检查是否有任何相关函数被加载
        local hasAnyFunction = false
        if WebDKP_CreateLootListFrame then hasAnyFunction = true end
        if WebDKP_UpdateLootList then hasAnyFunction = true end
        if WebDKP_GetLootRecords then hasAnyFunction = true end
        
        -- if hasAnyFunction then
        --     WebDKP_Print("部分函数已加载，但不完全。可能是文件加载过程中出现了错误。")
        -- else
        --     WebDKP_Print("没有检测到任何装备记录相关函数。请检查插件安装和WebDKP.toc文件。")
        -- end
        
        -- 创建临时替代函数
        WebDKP_Print("正在创建替代的文本显示功能...")
        
        -- 手动定义WebDKP_GetTableSize函数，避免依赖Utility.lua
        if not WebDKP_GetTableSize then
            WebDKP_GetTableSize = function(table)
                local count = 0;
                if( table == nil ) then
                    return count;
                end
                for key, entry in pairs(table) do
                    count = count + 1;
                end
                return count;
            end
        end
        -- 确保使用UI版本的WebDKP_UpdateLootList函数
        -- if not WebDKP_UpdateLootList then
        --     WebDKP_Print("错误: 无法加载装备记录UI。请检查插件安装。")
        -- end
        -- WebDKP_Print("已创建替代的装备记录显示功能。")
        -- 确保使用UI版本的WebDKP_UpdateLootList函数
        -- if not WebDKP_UpdateLootList then
        --     WebDKP_Print("错误: 无法加载装备记录UI。请检查插件安装。")
        -- end
        -- WebDKP_Print("已创建替代的装备记录显示功能。")
    end
end
 
-- 获取玩家当天最后一次替补活动的时间
function WebDKP_GetPlayerLastSubActivityTime(playerName, todayDate)
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
function WebDKP_ToggleLootList()
	-- 确保所有必要的函数都存在
    if not WebDKP_CreateLootListFrame then
        WebDKP_DebugCheckLootList()
    end
    
	-- 调用完整的装备记录显示功能
    if WebDKP_CreateLootListFrame and WebDKP_UpdateLootList then
        local frame = WebDKP_CreateLootListFrame()
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
                WebDKP_UpdateLootList()
            end)
        end
    else
        WebDKP_Print("无法显示装备记录窗口，请检查插件完整性。")
    end
end

-- 在插件加载时运行调试检查
WebDKP_OnEnable = function()
    WebDKP_Frame:Hide();
    getglobal("WebDKP_FiltersFrame"):Show();
    getglobal("WebDKP_AwardDKP_Frame"):Hide();
    getglobal("WebDKP_AwardItem_Frame"):Hide();
    getglobal("WebDKP_Options_Frame"):Hide();
    
    WebDKP_UpdatePlayersInGroup();
    WebDKP_UpdateTableToShow();
    
	-- place a hook on the chat frame so we can filter out our whispers
    WebDKP_Register_WhisperHook();
    
        --hooksecurefunc("SetItemRef",WebDKP_ItemChatClick);
    if ( SetItemRef ~= WebDKP_ItemChatClick ) then
        -- place a hook on item shift+clicks so we can get item details
        WebDKP_ItemChatClick_Original = SetItemRef;
        SetItemRef = WebDKP_ItemChatClick;
    end
    
	-- 检查装备记录功能是否加载
    WebDKP_DebugCheckLootList();
    

    
	-- 立即预加载数据列表框架和函数，确保首次点击即可响应
    WebDKP_PreloadLootList()
end

-- ================================
-- 立即预加载数据列表功能，解决重载后需要两次点击的问题
-- ================================
function WebDKP_PreloadLootList()
	-- 确保所有必需的函数都存在
    if not WebDKP_CreateLootListFrame then
        WebDKP_DebugCheckLootList()
    end
    
	-- 预创建已禁用：避免在 WebDKP_LootList.lua 加载前用兑底实现抢先创建并缓存独立窗口
    -- 框架将在首次点击“数据列表”标签时，由正式实现按内嵌面板方式创建
    WebDKP_LootListFramePreloaded = false
end

-- ================================
-- 处理自定义命令：/替补 和 /名单
-- ================================
function WebDKP_SlashCmdHandler(cmd)
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
        WebDKP_ToggleGUI();
        return
    end   
	-- 处理debug命令
    if cmd == "debug" then
        WebDKP_DebugCheckLootList();
        return
    end
	-- 处理help命令，显示帮助信息
	    if cmd == "help" then
	        WebDKP_Print("===== WebDKP 插件命令 =====")
	        WebDKP_Print("/webdkp 或 /dkp - 显示主界面")
        WebDKP_Print("/webdkp tb [分数] [分钟] - 开始替补加分活动（分数必填）")
        WebDKP_Print("/webdkp md - 查看当天替补名单")
        WebDKP_Print("/webdkp list 或 /webdkp loot - 显示装备获取记录")
        
        WebDKP_Print("/webdkp bb - 切换静默模式（关闭团队播报，仅记录分数）")
        WebDKP_Print("/webdkp tc - 切换BOSS死亡弹窗开关")
        WebDKP_Print("/webdkp pz [1-3] - 设置物品拾取记录品质等级（1=橙紫，2=橙紫蓝，3=橙紫蓝绿）")
        WebDKP_Print("/webdkp tj 名字 职业 [DKP初始分] - 新增一个DKP名单，初始分可选，默认0")
	        WebDKP_Print("/dkp k<分数> [原因] - 原因为“击杀-目标名/原因”，执行奖惩团队和替补")
	        WebDKP_Print("/dkp a<分数> - 原因为“集合分”，执行奖惩团队和替补")
	        WebDKP_Print("/dkp b<分数> - 原因为“解散分”，执行奖惩团队和替补")
	        WebDKP_Print("/dkp c<分数> [原因] - 对当前目标单点奖惩（缺省原因：菜出天际-犯错）")
	        WebDKP_Print("/dkp z - 打开主替独立分值面板（先确认后执行，自动搜索替补）")
	        WebDKP_Print("/webdkp help - 显示此帮助信息")
	        WebDKP_Print("=========================")
	        return
	    end

	    if cmd == "z" then
	        if WebDKP_Z_ShowFrame then
	            WebDKP_Z_ShowFrame()
	        else
	            WebDKP_Print("错误：未找到 /dkp z 功能入口。")
	        end
	        return
	    end
	    
		-- 处理bb命令，切换静默模式
    -- /dkp k<分数> [原因] 或 /dkp k <分数> [原因]：
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
            WebDKP_Print("用法：/dkp k<分数> [原因] 或 /dkp k <分数> [原因]")
            return
        end

        local pointsVal = tonumber(autoPointsText)
        if not pointsVal then
            WebDKP_Print("错误：分数必须是数字。用法：/dkp k<分数> [原因]")
            return
        end

        autoReasonText = string.gsub(autoReasonText or "", "^%s*", "")
        autoReasonText = string.gsub(autoReasonText, "%s*$", "")

        local reasonSource = autoReasonText
        if reasonSource == "" then
            local targetName = UnitName("target")
            if not targetName or targetName == "" then
                WebDKP_Print("错误：请先选中目标，或在命令中填写原因。")
                return
            end
            reasonSource = targetName
        end

        local reasonText = "击杀-" .. reasonSource

        local restoreReason = WebDKP_AwardDKP_FrameReason
        local restorePoints = WebDKP_AwardDKP_FramePoints

        if WebDKP_AwardDKP_FrameReason and WebDKP_AwardDKP_FrameReason.SetText then
            WebDKP_AwardDKP_FrameReason:SetText(reasonText)
        else
            WebDKP_AwardDKP_FrameReason = { GetText = function() return reasonText end }
        end

        if WebDKP_AwardDKP_FramePoints and WebDKP_AwardDKP_FramePoints.SetText then
            WebDKP_AwardDKP_FramePoints:SetText(tostring(pointsVal))
        else
            WebDKP_AwardDKP_FramePoints = { GetText = function() return tostring(pointsVal) end }
        end

        if WebDKP_AwardRaidAndSub_Event then
            WebDKP_AwardRaidAndSub_Event()
        else
            WebDKP_Print("错误：未找到奖惩团队和替补功能。")
        end

        if restoreReason == nil then
            WebDKP_AwardDKP_FrameReason = nil
        end
        if restorePoints == nil then
            WebDKP_AwardDKP_FramePoints = nil
        end
        return
    end

    -- /dkp a<分数> 或 /dkp a <分数>：原因为“集合分”，执行“奖惩团队和替补”
    -- /dkp b<分数> 或 /dkp b <分数>：原因为“解散分”，执行“奖惩团队和替补”
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
        WebDKP_Print("用法：/dkp a<分数> 或 /dkp b<分数>")
            return
        end

        local pointsVal = tonumber(fixedPointsText)
        if not pointsVal then
            WebDKP_Print("错误：分数必须是数字。用法：/dkp a<分数> 或 /dkp b<分数>")
            return
        end

        local restoreReason = WebDKP_AwardDKP_FrameReason
        local restorePoints = WebDKP_AwardDKP_FramePoints

        if WebDKP_AwardDKP_FrameReason and WebDKP_AwardDKP_FrameReason.SetText then
            WebDKP_AwardDKP_FrameReason:SetText(fixedReasonText)
        else
            WebDKP_AwardDKP_FrameReason = { GetText = function() return fixedReasonText end }
        end

        if WebDKP_AwardDKP_FramePoints and WebDKP_AwardDKP_FramePoints.SetText then
            WebDKP_AwardDKP_FramePoints:SetText(tostring(pointsVal))
        else
            WebDKP_AwardDKP_FramePoints = { GetText = function() return tostring(pointsVal) end }
        end

        if WebDKP_AwardRaidAndSub_Event then
            WebDKP_AwardRaidAndSub_Event()
        else
            WebDKP_Print("错误：未找到奖惩团队和替补功能。")
        end

        if restoreReason == nil then
            WebDKP_AwardDKP_FrameReason = nil
        end
        if restorePoints == nil then
            WebDKP_AwardDKP_FramePoints = nil
        end
        return
    end


    -- /dkp c<分数> [原因]：当前目标单点奖惩，原因默认“菜出天际-犯错”
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
            WebDKP_Print("用法：/dkp c<分数> [原因]")
            return
        end

        local pointsVal = tonumber(cPointsText)
        if not pointsVal then
            WebDKP_Print("错误：分数必须是数字。用法：/dkp c<分数> [原因]")
            return
        end

        local targetName = UnitName("target")
        if not targetName or targetName == "" then
            WebDKP_Print("错误：请先选中目标。")
            return
        end

        if not cReasonText or cReasonText == "" then
            cReasonText = "菜出天际-犯错"
        end

        local className = WebDKP_GetPlayerClass(targetName) or "战士"
        if WebDKP_NormalizeClassName then
            className = WebDKP_NormalizeClassName(className)
        end
        local playerTable = {{ name = targetName, class = className }}

        if not StaticPopupDialogs then
            StaticPopupDialogs = {}
        end
        if not StaticPopupDialogs["WEBDKP_AWARD_TARGET_CONFIRM"] then
            StaticPopupDialogs["WEBDKP_AWARD_TARGET_CONFIRM"] = {
                text = "",
                button1 = "确定",
                button2 = "取消",
                timeout = 0,
                whileDead = 1,
                hideOnEscape = 1,
                OnAccept = function()
                    local dialog = StaticPopupDialogs["WEBDKP_AWARD_TARGET_CONFIRM"]
                    if dialog and dialog._confirmCallback then
                        dialog._confirmCallback()
                    end
                end
            }
        end

        local confirmText = "确定要为目标调整DKP吗？\n目标: " .. targetName .. "\n分数: " .. tostring(pointsVal) .. "\n原因: " .. cReasonText
        StaticPopupDialogs["WEBDKP_AWARD_TARGET_CONFIRM"].text = confirmText
        StaticPopupDialogs["WEBDKP_AWARD_TARGET_CONFIRM"]._confirmCallback = function()
            WebDKP_AddDKP(pointsVal, cReasonText, "false", playerTable)
            WebDKP_AnnounceAwardSingle(pointsVal, cReasonText, targetName)
            WebDKP_UpdateTable()
            WebDKP_UpdateTableToShow()
            if WebDKP_UpdateLootList then
                WebDKP_UpdateLootList()
            end
        end
        StaticPopup_Show("WEBDKP_AWARD_TARGET_CONFIRM")
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
	            WebDKP_Print("静默模式已开启 - 团队播报已关闭，仅记录分数")
	        else
	            WebDKP_Print("静默模式已关闭 - 团队播报已开启")
	        end
	        
	        -- 同步自用页勾选框状态（如果已加载）
	        if WebDKP_Personal_FrameSilentMode and WebDKP_Personal_FrameSilentMode.SetChecked then
	            WebDKP_Personal_FrameSilentMode:SetChecked(WebDKP_Options["SilentMode"] and true or false)
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
			WebDKP_Print("BOSS死亡弹窗已开启")
		else
			-- 切换状态
			WebDKP_Options["BossDeathPopup"] = not WebDKP_Options["BossDeathPopup"]
			
			if WebDKP_Options["BossDeathPopup"] then
				WebDKP_Print("BOSS死亡弹窗已开启")
			else
				WebDKP_Print("BOSS死亡弹窗已关闭")
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
			WebDKP_Print("当前物品拾取记录品质等级：" .. WebDKP_Options["LootQualityLevel"] .. "（" .. qualityText .. "）")
			WebDKP_Print("使用 /dkp pz [1-3] 来修改设置")
			return
		end
		
		-- 解析参数
		local level = tonumber(arg1)
		if not level or level < 1 or level > 3 then
			WebDKP_Print("错误：品质等级必须是1-3之间的数字！")
			WebDKP_Print("正确格式：/dkp pz [1-3]")
			WebDKP_Print("1=只记录橙色、紫色品质")
			WebDKP_Print("2=记录橙色、紫色、蓝色品质") 
			WebDKP_Print("3=记录橙色、紫色、蓝色、绿色品质")
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
		
		WebDKP_Print("物品拾取记录品质等级已设置为：" .. level .. "（" .. qualityText .. "）")
		return
	end
	
    
    

    
	-- 处理tj命令，添加新的DKP名单
    if cmd == "tj" then
        -- 解析参数：名字 职业 [DKP初始分]，初始分可选，默认0
        local name = args[2] or ""
        local class = args[3] or ""
        local initialDkp = args[4] or "0" -- 默认初始分为0
        
        if not name or not class then
            WebDKP_Print("用法：/dkp tj 名字 职业 [DKP初始分]")
            WebDKP_Print("例如：/dkp tj 张三 战士")
            WebDKP_Print("例如：/dkp tj 张三 战士 100")
            return
        end
        
        -- 验证初始分是否为数字
        if not tonumber(initialDkp) then
            WebDKP_Print("错误：DKP初始分必须是数字！")
            WebDKP_Print("用法：/dkp tj 名字 职业 [DKP初始分]")
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
            WebDKP_Print("错误：无效的职业！")
            WebDKP_Print("有效职业：德鲁伊, 猎人, 法师, 盗贼, 萨满祭司, 圣骑士, 牧师, 战士, 术士")
            return
        end
        
        -- 使用英文职业名称存储
        class = englishClass
        
        -- 转换DKP为数字
        initialDkp = tonumber(initialDkp)
        
        -- 检查玩家是否已存在
        if WebDKP_DkpTable[name] then
            WebDKP_Print("警告：" .. name .. " 已存在于DKP列表中！")
            WebDKP_Print("当前DKP：" .. (WebDKP_DkpTable[name]["dkp_" .. WebDKP_GetTableid()] or 0))
            WebDKP_Print("如需修改，请使用DKP奖惩功能。")
            return
        end
        
        -- 添加新玩家到DKP表
        WebDKP_DkpTable[name] = {
            ["class"] = class,
            ["dkp" .. WebDKP_GetTableid()] = initialDkp,
            ["Selected"] = false,
            ["IsSub"] = false
        }
        
        -- 更新显示表格
        WebDKP_UpdateTableToShow()
        WebDKP_UpdateTable()
        
        WebDKP_Print("成功添加新玩家：")
        WebDKP_Print("名字：" .. name)
        WebDKP_Print("职业：" .. class)
        WebDKP_Print("初始DKP：" .. initialDkp)
        return
    end
    
	-- 处理list命令，显示装备获取记录
    if cmd == "list" or cmd == "loot" then
        -- 确保WebDKP_ToggleLootList函数存在
        if not WebDKP_ToggleLootList then
            -- 如果函数不存在，先调用调试检查函数来创建临时替代函数
            WebDKP_DebugCheckLootList()
        end
        
        -- 调用函数显示装备记录
        if WebDKP_ToggleLootList then
            WebDKP_ToggleLootList()
        else
            -- 如果仍然没有WebDKP_ToggleLootList函数，直接尝试创建并显示窗口
            if WebDKP_CreateLootListFrame and WebDKP_UpdateLootList then
                local frame = WebDKP_CreateLootListFrame()
                if frame then
                    frame:Show()
                    WebDKP_UpdateLootList()
                else
                    WebDKP_Print("无法显示装备记录，请检查插件安装是否正确。")
                end
            else
                WebDKP_Print("无法显示装备记录，请检查插件安装是否正确。")
            end
        end
        return
    end
    
    if cmd == "tb" then
        -- 解析参数，分数必填
        if not arg1 or arg1 == "" then
            WebDKP_Print("错误：/dkp tb 命令需要分数参数！")
            WebDKP_Print("正确格式：/dkp tb [分数] [分钟]")
            WebDKP_Print("示例：/dkp tb 2 5  （2分，5分钟）")
            return
        end
        
        local points = tonumber(arg1)
        if not points then
            WebDKP_Print("错误：分数必须是数字！")
            return
        end
        
        local minutes = tonumber(arg2) or 5
        
        -- 初始化替补活动数据
        -- 优先使用WebDKP_SubAwardData中的reason，如果没有则使用默认值
        local subReasonValue = "替补分"
        if WebDKP_SubAwardData and WebDKP_SubAwardData.reason and WebDKP_SubAwardData.reason ~= "" then
            subReasonValue = WebDKP_SubAwardData.reason
        end
        
        WebDKP_SubData = {
            active = true,
            points = points,
            reason = subReasonValue,
            subReason = subReasonValue,
            tableid = WebDKP_GetTableid(),
            startTime = GetTime(),
            endTime = GetTime() + (minutes * 60),
            subs = {},
            raidMembers = {},
            timerFrame = nil
        }
        
        -- 保存当前团队成员列表
        WebDKP_CurrentRaidMembers = {}
        if GetNumRaidMembers() > 0 then
            for i = 1, GetNumRaidMembers() do
                local name = UnitName("raid" .. i)
                if name then
                    WebDKP_CurrentRaidMembers[name] = true
                end
            end
        elseif GetNumPartyMembers() > 0 then
            for i = 1, GetNumPartyMembers() do
                local name = UnitName("party" .. i)
                if name then
                    WebDKP_CurrentRaidMembers[name] = true
                end
            end
            local playerName = UnitName("player")
            WebDKP_CurrentRaidMembers[playerName] = true
        else
            local playerName = UnitName("player")
            WebDKP_CurrentRaidMembers[playerName] = true
        end
        
        -- 保存团队成员列表到WebDKP_SubData
        WebDKP_SubData.raidMembers = WebDKP_CurrentRaidMembers
        
        -- 播报替补打卡提醒
        -- 打卡模式下，使用正确的时间参数
        local timeInfo = minutes .. "分钟"
        -- 优先使用WebDKP_SubAwardData中的minutes字段
        if WebDKP_SubAwardData and WebDKP_SubAwardData.minutes then
            timeInfo = WebDKP_SubAwardData.minutes .. "分钟"
        end
        
        local subMessage = "手动替补加分活动开始！替补成员在" .. timeInfo .. "内私密我 TB 记录打卡，过期不候！"
        
        -- 静默模式下不发送团队播报，仅本地显示
        local isSilentMode = WebDKP_Options and WebDKP_Options["SilentMode"]
        if not isSilentMode then
            SendChatMessage(subMessage, "GUILD", nil, nil)
        else
            WebDKP_Print("[静默] " .. subMessage)
        end
        WebDKP_Print("手动替补加分活动已开始，将在" .. minutes .. "分钟后结束。")
        
        -- 设置计时器，计时结束后处理替补加分
        WebDKP_SubData.timerFrame = CreateFrame("Frame")
        WebDKP_SubData.timerFrame:SetScript("OnUpdate", function()
            if GetTime() >= WebDKP_SubData.endTime then
                local frame =  WebDKP_SubData.timerFrame -- 使用this或显式引用
                frame:SetScript("OnUpdate", nil)
                WebDKP_ProcessSubstitutes()
            end
        end)
    
    elseif cmd == "md" then

        
        -- 直接使用WebDKP_GetSubstituteRecords函数获取所有替补记录
        -- 这个函数是替补名单窗口用来获取数据的核心函数，确保即使没有打开窗口也能获取到正确的数据
        local allSubRecords = WebDKP_GetSubstituteRecords()
        
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
            local classColor = WebDKP_GetClassColor(class)
            local coloredName = classColor .. playerName .. "|r"
            
            -- 添加到列表中
            table.insert(listEntries, coloredName .. " " .. data.count .. "次 最后：" .. timeStr)
        end
        
        -- 分批次发送名单，每批2个玩家，避免信息过长
        local listEntriesSize = WebDKP_GetTableSize(listEntries)
        
        -- 显示玩家记录数量
        WebDKP_Print("替补名单：共有 " .. listEntriesSize .. " 个玩家记录")
        
        if listEntriesSize == 0 then
            WebDKP_Print("暂无替补记录。")
            return
        end
        
        -- 静默模式下不发送团队播报，仅本地显示
        local isSilentMode = WebDKP_Options and WebDKP_Options["SilentMode"]
        if isSilentMode then
            WebDKP_Print("[静默] 替补名单已生成，共 " .. listEntriesSize .. " 个玩家记录")
            -- 本地显示前几个玩家作为调试信息
            local maxDisplay = 3
            local displayed = 0
            for i = 1, math.min(listEntriesSize, maxDisplay) do
                WebDKP_Print("[静默] " .. listEntries[i])
                displayed = displayed + 1
            end
            if listEntriesSize > maxDisplay then
                WebDKP_Print("[静默] ... 还有 " .. (listEntriesSize - maxDisplay) .. " 个玩家")
            end
            return
        end
        
        -- 获取发送位置
        local tellLocation = WebDKP_GetTellLocation()
        if tellLocation == "NONE" then
            tellLocation = "SAY"
        end
        
        -- 分批发送，每批2个玩家
        local batchSize = 2
        local currentIndex = 1
        local batchNumber = 1
        
        -- 创建分批发送函数
        local function sendBatch()
            -- WebDKP_Print("调试：发送第 " .. batchNumber .. " 批，当前索引 " .. currentIndex .. "，总数 " .. listEntriesSize)
            
            if currentIndex > listEntriesSize then
                -- WebDKP_Print("调试：所有批次发送完毕")
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
            
            -- WebDKP_Print("调试：批次 " .. batchNumber .. " 包含索引 " .. startIndex .. " 到 " .. (currentIndex-1) .. "，共 " .. count .. " 个玩家")
            
            -- 发送当前批次
            WebDKP_SendAnnouncement(batchMessage, tellLocation)
            
            -- 如果不是最后一批，设置1秒后发送下一批
            if currentIndex <= listEntriesSize then
                -- WebDKP_Print("调试：还有 " .. (listEntriesSize - currentIndex + 1) .. " 个玩家未发送，准备下一批")
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
                -- WebDKP_Print("调试：所有玩家发送完毕")
            end
        end
        
        -- 开始发送第一批
        sendBatch()
    end
end
end
-- 职业颜色映射表（魔兽世界1.12版本）
WebDKP_CLASS_COLORS = {
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
function WebDKP_GetClassColor(class)
    local color = WebDKP_CLASS_COLORS[class]
    if color then
        return color
    else
        return "|cffffffff"  -- 默认白色
    end
end

-- 为玩家提供一个命令来测试替补名单功能
function WebDKP_TestSubstituteList()
	-- 检查装备记录功能是否已加载
    if not WebDKP_LootListFrame then
        if WebDKP_CreateLootListFrame then
            WebDKP_CreateLootListFrame()
        else
            WebDKP_Print("错误: 无法创建装备记录窗口")
            return
        end
    end
    
	-- 显示窗口
    WebDKP_LootListFrame:Show()
    
	-- 切换到替补名单模式
    if WebDKP_LootListFrame then
        WebDKP_LootListFrame.currentMode = "substitute"
        if WebDKP_LootListFrame.titleText then
            WebDKP_LootListFrame.titleText:SetText("替补名单")
        end
        
        -- 更新显示
        WebDKP_UpdateLootList()
    end
end

-- 添加WebDKP_AddDKP函数实现
function WebDKP_AddDKP(points, reason, forItem, players, tableid)
	-- 检查是否选择了玩家
	if not players or not next(players) then
		WebDKP_Print("错误: 请选择至少一名玩家。");
		return false;
	end
	
	-- 如果没有指定tableid，使用当前选中的表格
	if not tableid then
		tableid = WebDKP_GetTableid();
	end
	-- WebDKP_AddDKPToTable函数内部会处理表格的检查和创建，此处无需重复处理
	
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
	WebDKP_LastAwardPlayers = {};
	WebDKP_LastAwardPlayerCount = 0;
	
	for k, v in pairs(players) do
		local name, class
		if (type(v) == "table") then
			name = v["name"];
			class = v["class"];
		else
			name = v;
			class = WebDKP_GetPlayerClass(name) or "战士";
		end
		if not class or class == "" then
			class = WebDKP_GetPlayerClass(name) or "战士";
		end
		if WebDKP_NormalizeClassName then
			class = WebDKP_NormalizeClassName(class);
		end
		
		if name and name ~= "" then
			WebDKP_LastAwardPlayerCount = WebDKP_LastAwardPlayerCount + 1;
			WebDKP_LastAwardPlayers[WebDKP_LastAwardPlayerCount] = name;
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
		
		local guild = WebDKP_GetGuildName(name);
		WebDKP_AddDKPToTable(name, class, points);
		--add them to the log entry
		WebDKP_Log[reason.." "..date]["awarded"][name] = {};
		WebDKP_Log[reason.." "..date]["awarded"][name]["name"]=name;
		WebDKP_Log[reason.." "..date]["awarded"][name]["guild"]=guild;
		WebDKP_Log[reason.." "..date]["awarded"][name]["class"]=class;
	end
		
		-- 通知团队
		local announceMsg = "[WebDKP] "..reason..": "..points.." 分"
		local tellLocation = "RAID"
		if WebDKP_GetTellLocation then
			tellLocation = WebDKP_GetTellLocation()
		end
		if WebDKP_SendAnnouncement then
			WebDKP_SendAnnouncement(announceMsg, tellLocation)
		else
			local isSilentMode = WebDKP_Options and WebDKP_Options["SilentMode"]
			if tellLocation == "NONE" then
				WebDKP_Print(announceMsg)
			elseif isSilentMode then
				WebDKP_Print("[静默] " .. announceMsg)
			else
				SendChatMessage(announceMsg, tellLocation)
			end
		end
		
		-- 更新UI - 移除不存在的WebDKP_UpdateUI函数调用
		-- UI更新由其他机制处理
	end

-- 添加WebDKP_AddDKPToTable函数实现
function WebDKP_AddDKPToTable(name, class, points)
	local tableid = WebDKP_GetTableid();
	
	-- 确保WebDKP_Tables和相应的表结构存在
	if (not WebDKP_Tables) then
		WebDKP_Tables = {};
	end
	if (not WebDKP_Tables[tableid]) then
		-- 使用统一的函数获取表格名称
		local tableName = WebDKP_GetTableNameById(tableid)
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
function WebDKP_EditDKPRecord(uniqueId, newPoints, newReason)
	-- 检查参数
    if not uniqueId then
        WebDKP_Print("错误：缺少uniqueId参数")
        return false
    end
    
    if not newPoints then
        WebDKP_Print("错误：缺少新分数参数")
        return false
    end
    
	-- 转换为数字
    newPoints = tonumber(newPoints)
    if not newPoints then
        WebDKP_Print("错误：新分数必须是数字")
        return false
    end
    
	-- 先从WebDKP_Log中找到要修改的记录
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
        WebDKP_Print("错误：未找到要修改的DKP记录")
        return false
    end
    
	-- 计算分数变化量
    local pointsChange = newPoints - oldPoints
    
	-- 更新WebDKP_Log中的记录
    WebDKP_Log[targetLogEntry].points = newPoints
	-- 如果提供了新原因，则更新原因字段
    if newReason and newReason ~= "" then
        WebDKP_Log[targetLogEntry].reason = newReason
    end
    
	-- 同时更新WebDKP_DKPRecords中的记录
    if WebDKP_DKPRecords then
        for i, record in ipairs(WebDKP_DKPRecords) do
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
        local tableid = WebDKP_GetTableid()
        local dkpField = "dkp_"..tableid
        
        -- 遍历WebDKP_DkpTable更新玩家分数
        if WebDKP_DkpTable then
            for playerName, playerData in pairs(WebDKP_DkpTable) do
                if type(playerData) == "table" and affectedPlayers[playerName] then
                    -- 更新玩家分数
                    local currentDKP = tonumber(playerData[dkpField]) or 0
                    playerData[dkpField] = currentDKP + pointsChange
                    -- WebDKP_Print("已更新玩家 " .. playerName .. " 的DKP分数: " .. playerData[dkpField])
                end
            end
        end
    end
    
	-- 保存数据并刷新界面
    if WebDKP_SaveToDisk then
        WebDKP_SaveToDisk()
    end
    if WebDKP_UpdateTable then
        WebDKP_UpdateTable()
    end
    if WebDKP_UpdateLootList then
        WebDKP_UpdateLootList()
    end
    
	-- 根据是否修改了原因显示不同的提示信息
    if newReason and newReason ~= "" and newReason ~= oldReason then
        WebDKP_Print("成功修改DKP记录: " .. oldReason .. " -> " .. newReason .. ", 分数: " .. oldPoints .. " -> " .. newPoints)
    else
        WebDKP_Print("成功修改DKP记录分数: " .. oldPoints .. " -> " .. newPoints)
    end
    return true
end

-- 显示修改DKP分数对话框的函数
function WebDKP_ShowEditDKPDialog(uniqueId, currentPoints)
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
    WebDKP_ShowCustomReasonDialog(uniqueId, currentPoints, currentReason)
end

-- 创建自定义的原因输入对话框
function WebDKP_ShowCustomReasonDialog(uniqueId, currentPoints, currentReason)
	-- 如果对话框已存在，先隐藏
    if WebDKP_ReasonDialog then
        WebDKP_ReasonDialog:Hide()
    end
    
	-- 创建对话框主窗口
    local dialog = CreateFrame("Frame", "WebDKP_ReasonDialog", UIParent)
    dialog:SetWidth(260)
    dialog:SetHeight(150)
    
	-- 加载保存的窗口位置，如果没有则居中显示
    if WebDKP_DialogPositions and WebDKP_DialogPositions["WebDKP_ReasonDialog"] then
        local pos = WebDKP_DialogPositions["WebDKP_ReasonDialog"]
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
        if not WebDKP_DialogPositions then
            WebDKP_DialogPositions = {}
        end
        local x, y = this:GetLeft(), this:GetTop()
        WebDKP_DialogPositions["WebDKP_ReasonDialog"] = {x = x, y = y}
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
    local ReasonEditBox = CreateFrame("EditBox", "WebDKP_ModifyReasonEditBox"..GetTime(), dialog, "InputBoxTemplate")
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
        if WebDKP_NextButton then
            WebDKP_NextButton:Click()
        end
    end)
    
	-- 创建下一步按钮
    local nextButton = CreateFrame("Button", "WebDKP_NextButton", dialog, "UIPanelButtonTemplate")
    nextButton:SetWidth(100)
    nextButton:SetHeight(25)
    nextButton:SetPoint("BOTTOMLEFT", dialog, "BOTTOMLEFT", 20, 10)
    nextButton:SetText("下一步")
    nextButton:SetScript("OnClick", function()
        local newReason = ReasonEditBox:GetText() or "DKP记录"
        dialog:Hide()
        -- 显示分数输入对话框
        WebDKP_ShowCustomPointsDialog(uniqueId, currentPoints, newReason)
    end)
    
	-- 创建取消按钮
    local cancelButton = CreateFrame("Button", "WebDKP_CancelButton", dialog, "UIPanelButtonTemplate")
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
    WebDKP_ReasonDialog = dialog
    
	-- 显示对话框
    dialog:Show()
end

-- 创建自定义的分数输入对话框
function WebDKP_ShowCustomPointsDialog(uniqueId, currentPoints, newReason)
	-- 如果对话框已存在，先隐藏
    if WebDKP_PointsDialog then
        WebDKP_PointsDialog:Hide()
    end
    
	-- 创建对话框主窗口
    local dialog = CreateFrame("Frame", "WebDKP_PointsDialog", UIParent)
    dialog:SetWidth(260)
    dialog:SetHeight(150)
    
	-- 加载保存的窗口位置，如果没有则居中显示
    if WebDKP_DialogPositions and WebDKP_DialogPositions["WebDKP_PointsDialog"] then
        local pos = WebDKP_DialogPositions["WebDKP_PointsDialog"]
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
        if not WebDKP_DialogPositions then
            WebDKP_DialogPositions = {}
        end
        local x, y = this:GetLeft(), this:GetTop()
        WebDKP_DialogPositions["WebDKP_PointsDialog"] = {x = x, y = y}
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
    local PointsEditBox = CreateFrame("EditBox", "WebDKP_ModifyPointsEditBox"..GetTime(), dialog, "InputBoxTemplate")
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
        if WebDKP_ConfirmButton then
            WebDKP_ConfirmButton:Click()
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
    local confirmButton = CreateFrame("Button", "WebDKP_ConfirmButton", dialog, "UIPanelButtonTemplate")
    confirmButton:SetWidth(100)
    confirmButton:SetHeight(25)
    confirmButton:SetPoint("BOTTOMLEFT", dialog, "BOTTOMLEFT",  20, 10)
    confirmButton:SetText("确定")
    confirmButton:SetScript("OnClick", function()
        local newPoints = PointsEditBox:GetText()
        -- 执行DKP记录修改
        WebDKP_EditDKPRecord(uniqueId, newPoints, newReason)
        -- 修改分数后刷新界面
        WebDKP_UpdateTable()
        WebDKP_Refresh()
        WebDKP_UpdateLootList()
        dialog:Hide()
    end)
    
	-- 创建取消按钮
    local cancelButton = CreateFrame("Button", "WebDKP_PointsCancelButton", dialog, "UIPanelButtonTemplate")
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
    WebDKP_PointsDialog = dialog
    
	-- 显示对话框
    dialog:Show()
end

-- 编辑装备记录的函数
function WebDKP_EditLootRecord(uniqueId, newItemName, newCost)
	-- 检查参数
    if not uniqueId then
        WebDKP_Print("错误：缺少uniqueId参数")
        return false
    end
    
    if not newItemName then
        WebDKP_Print("错误：缺少新物品名称参数")
        return false
    end
    
    if not newCost then
        WebDKP_Print("错误：缺少新花费参数")
        return false
    end
    
	-- 转换为数字并确保为负数（装备花费应为负值）
    newCost = tonumber(newCost)
    if not newCost then
        WebDKP_Print("错误：新花费必须是数字")
        return false
    end
    
	-- 确保花费为负数（装备花费应为负值）
    if newCost > 0 then
        newCost = -newCost
    end
    
	-- 先从WebDKP_Log中找到要修改的装备记录
    local targetLogEntry = nil
    local oldItemName = ""
    local oldPoints = 0
    local affectedPlayers = {} -- 改为存储多个玩家
    local targetUniqueId = uniqueId -- 保存原始uniqueId
    
    WebDKP_Print("开始修改装备记录，uniqueId: " .. tostring(uniqueId))
    
    if WebDKP_Log then
        for logKey, logEntry in pairs(WebDKP_Log) do
            if type(logEntry) == "table" and logEntry.uniqueId and logEntry.uniqueId == uniqueId then
                -- 确保这是装备记录
                local isLootRecord = logEntry.foritem == true or logEntry.foritem == "true"
                
                -- WebDKP_Print("找到记录，logKey: " .. tostring(logKey) .. ", isLootRecord: " .. tostring(isLootRecord))
                
                if isLootRecord then
                    -- 保存旧数据 - 装备名称使用reason字段
                    -- - 重要：使用oldPoints进行分数计算
                    oldItemName = logEntry.reason or ""
                    oldPoints = tonumber(logEntry.points) or 0
                    
                    -- WebDKP_Print("旧装备名称: " .. oldItemName .. ", 旧花费: " .. oldPoints)
                    
                    -- 获取所有获得该装备的玩家
                    if logEntry.awarded then
                        -- WebDKP_Print("记录使用awarded格式，玩家数量: " .. WebDKP_GetTableSize(logEntry.awarded))
                        for playerName, playerInfo in pairs(logEntry.awarded) do
                            table.insert(affectedPlayers, playerName)
                            -- WebDKP_Print("找到玩家: " .. playerName .. ", 信息: " .. tostring(playerInfo))
                        end
                    elseif logEntry.player then
                        -- 兼容旧格式（单个玩家）
                        table.insert(affectedPlayers, logEntry.player)
                        -- WebDKP_Print("记录使用player格式，玩家: " .. logEntry.player)
                    else
                        -- WebDKP_Print("警告: 记录中没有找到玩家信息")
                    end
                    
                    targetLogEntry = logKey
                    break
                end
            end
        end
    end
    
	-- 如果没找到记录，返回失败
    if not targetLogEntry then
        WebDKP_Print("错误：未找到要修改的装备记录")
        return false
    end
    
	-- 计算花费变化量
    local costChange = newCost - oldPoints
    
	-- 更新WebDKP_Log中的记录 - 装备名称使用reason字段
    WebDKP_Log[targetLogEntry].reason = newItemName
    WebDKP_Log[targetLogEntry].points = newCost
    
	-- 同时更新WebDKP_LootHistory中的记录
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
        local tableid = WebDKP_GetTableid()
        local dkpField = "dkp_"..tableid
        
        -- WebDKP_Print("使用tableid: " .. tableid .. ", dkp字段: " .. dkpField)
        
        -- 更新所有获得该装备的玩家分数
        for _, playerName in ipairs(affectedPlayers) do
            -- WebDKP_Print("正在更新玩家: " .. playerName)
            if WebDKP_DkpTable and WebDKP_DkpTable[playerName] then
                local currentDKP = tonumber(WebDKP_DkpTable[playerName][dkpField]) or 0
                local currentSpent = tonumber(WebDKP_DkpTable[playerName]["spent"]) or 0
                
                -- WebDKP_Print("玩家当前DKP: " .. currentDKP .. ", 当前总花费: " .. currentSpent)
                
                WebDKP_DkpTable[playerName][dkpField] = currentDKP + costChange
                WebDKP_DkpTable[playerName]["spent"] = currentSpent + costChange
                
                -- WebDKP_Print("已更新玩家 " .. playerName .. " 的DKP分数: " .. currentDKP .. " -> " .. WebDKP_DkpTable[playerName][dkpField] .. " (变化: " .. costChange .. ")")
                -- WebDKP_Print("玩家总花费更新: " .. currentSpent .. " -> " .. WebDKP_DkpTable[playerName]["spent"])
            else
                -- WebDKP_Print("警告: 玩家 " .. playerName .. " 的DKP数据不存在，无法更新")
                -- WebDKP_Print("可用玩家: " .. WebDKP_GetTableSize(WebDKP_DkpTable))
            end
        end

    end
    
	-- 保存数据并刷新界面
    if WebDKP_SaveToDisk then
        WebDKP_SaveToDisk()
    end
    if WebDKP_UpdateTable then
        WebDKP_UpdateTable()
    end
    if WebDKP_UpdateLootList then
        WebDKP_UpdateLootList()
    end
    

    return true
end

-- 编辑替补记录的函数
function WebDKP_EditSubstituteRecord(uniqueId, newReason, newPoints)
	-- 检查参数
    if not uniqueId then
        WebDKP_Print("错误：缺少uniqueId参数")
        return false
    end
    
    if not newReason then
        WebDKP_Print("错误：缺少新原因参数")
        return false
    end
    
    if not newPoints then
        WebDKP_Print("错误：缺少新分数参数")
        return false
    end
    
	-- 转换为数字
    newPoints = tonumber(newPoints)
    if not newPoints then
        WebDKP_Print("错误：新分数必须是数字")
        return false
    end
    
	-- 先从WebDKP_Log中找到要修改的替补记录
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
        WebDKP_Print("错误：未找到要修改的替补记录")
        return false
    end
    
	-- 计算分数变化量
    local pointsChange = newPoints - oldPoints
    
	-- 更新WebDKP_Log中的记录
    WebDKP_Log[targetLogEntry].reason = newReason
    WebDKP_Log[targetLogEntry].points = newPoints
    
	-- 同时更新WebDKP_SubstituteRecords中的记录
    if WebDKP_SubstituteRecords then
        for i, record in ipairs(WebDKP_SubstituteRecords) do
            if record.uniqueId and record.uniqueId == uniqueId then
                record.reason = newReason
                record.points = newPoints
                break
            end
        end
    end
    
	-- 同时更新WebDKP_DailySubRecords中的记录
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
        local tableid = WebDKP_GetTableid()
        local dkpField = "dkp_"..tableid
        
        -- 遍历WebDKP_DkpTable更新玩家分数
        if WebDKP_DkpTable then
            for playerName, playerData in pairs(WebDKP_DkpTable) do
                if type(playerData) == "table" and affectedPlayers[playerName] then
                    -- 更新玩家分数
                    local currentDKP = tonumber(playerData[dkpField]) or 0
                    playerData[dkpField] = currentDKP + pointsChange
                    playerData["earned"] = (tonumber(playerData["earned"]) or 0) + pointsChange
                    -- WebDKP_Print("已更新玩家 " .. playerName .. " 的DKP分数: " .. playerData[dkpField])
                end
            end
        end
    end
    
	-- 保存数据并刷新界面
    if WebDKP_SaveToDisk then
        WebDKP_SaveToDisk()
    end
    if WebDKP_UpdateTable then
        WebDKP_UpdateTable()
    end
    if WebDKP_UpdateLootList then
        WebDKP_UpdateLootList()
    end
    
    WebDKP_Print("成功修改替补记录: " .. oldReason .. " -> " .. newReason .. ", 分数: " .. oldPoints .. " -> " .. newPoints)
    return true
end

-- 编辑奖励记录的函数
function WebDKP_EditAwardRecord(uniqueId, newReason, newPoints)
	-- 检查参数
    if not uniqueId then
        WebDKP_Print("错误：缺少uniqueId参数")
        return false
    end
    
    if not newReason then
        WebDKP_Print("错误：缺少新原因参数")
        return false
    end
    
    if not newPoints then
        WebDKP_Print("错误：缺少新分数参数")
        return false
    end
    
	-- 转换为数字
    newPoints = tonumber(newPoints)
    if not newPoints then
        WebDKP_Print("错误：新分数必须是数字")
        return false
    end
    
	-- 先从WebDKP_Log中找到要修改的奖励记录
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
        WebDKP_Print("错误：未找到要修改的奖励记录")
        return false
    end
    
	-- 计算分数变化量
    local pointsChange = newPoints - oldPoints
    
	-- 更新WebDKP_Log中的记录
    WebDKP_Log[targetLogEntry].reason = newReason
    WebDKP_Log[targetLogEntry].points = newPoints
    
	-- 更新受影响玩家的DKP分数
    if pointsChange ~= 0 and next(affectedPlayers) then
        -- 获取当前使用的tableid
        local tableid = WebDKP_GetTableid()
        local dkpField = "dkp_"..tableid
        
        -- 遍历WebDKP_DkpTable更新玩家分数
        if WebDKP_DkpTable then
            for playerName, playerData in pairs(WebDKP_DkpTable) do
                if type(playerData) == "table" and affectedPlayers[playerName] then
                    -- 更新玩家分数
                    local currentDKP = tonumber(playerData[dkpField]) or 0
                    playerData[dkpField] = currentDKP + pointsChange
                    playerData["earned"] = (tonumber(playerData["earned"]) or 0) + pointsChange
                    -- WebDKP_Print("已更新玩家 " .. playerName .. " 的DKP分数: " .. playerData[dkpField])
                end
            end
        end
    end
    
	-- 保存数据并刷新界面
    if WebDKP_SaveToDisk then
        WebDKP_SaveToDisk()
    end
    if WebDKP_UpdateTable then
        WebDKP_UpdateTable()
    end
    if WebDKP_UpdateLootList then
        WebDKP_UpdateLootList()
    end
    
    WebDKP_Print("成功修改奖励记录: " .. oldReason .. " -> " .. newReason .. ", 分数: " .. oldPoints .. " -> " .. newPoints)
    return true
end

-- 显示修改装备记录对话框的函数
function WebDKP_ShowEditLootDialog(uniqueId, currentItem, currentCost)
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
    WebDKP_ShowCustomLootItemDialog(uniqueId, currentItem, logCost)
end

-- 自定义装备记录装备名称输入对话框
function WebDKP_ShowCustomLootItemDialog(uniqueId, currentItem, currentCost)
	-- 如果对话框已经存在，则销毁它
    if WebDKP_LootItemDialog then
        WebDKP_LootItemDialog:Hide()
        WebDKP_LootItemDialog = nil
    end
    
	-- 创建新的对话框（不使用BasicFrameTemplate）
    local dialog = CreateFrame("Frame", "WebDKP_LootItemDialog", UIParent)
    dialog:SetWidth(260)
    dialog:SetHeight(150)
    
	-- 加载保存的窗口位置，如果没有则居中显示
    if WebDKP_DialogPositions and WebDKP_DialogPositions["WebDKP_LootItemDialog"] then
        local pos = WebDKP_DialogPositions["WebDKP_LootItemDialog"]
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
        if not WebDKP_DialogPositions then
            WebDKP_DialogPositions = {}
        end
        local x, y = dialog:GetLeft(), dialog:GetTop()
        WebDKP_DialogPositions["WebDKP_LootItemDialog"] = {x = x, y = y}
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
    dialog.itemEditBox = CreateFrame("EditBox", "WebDKP_LootItemEditBox"..GetTime(), dialog, "InputBoxTemplate")
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
            WebDKP_ShowCustomLootCostDialog(uniqueId, newItemName, currentCost)
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
            WebDKP_ShowCustomLootCostDialog(uniqueId, newItemName, currentCost)
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
    WebDKP_LootItemDialog = dialog
    dialog:Show()
    
	-- 防止输入框在显示时失去焦点
    dialog.itemEditBox:SetFocus()
end

-- 自定义装备记录花费输入对话框
function WebDKP_ShowCustomLootCostDialog(uniqueId, newItemName, currentCost)
	-- 如果对话框已经存在，则销毁它
    if WebDKP_LootCostDialog then
        WebDKP_LootCostDialog:Hide()
        WebDKP_LootCostDialog = nil
    end
    
	-- 如果上一个对话框存在，隐藏它
    if WebDKP_LootItemDialog then
        WebDKP_LootItemDialog:Hide()
    end
    
	-- 创建新的对话框（不使用BasicFrameTemplate）
    local dialog = CreateFrame("Frame", "WebDKP_LootCostDialog", UIParent)
    dialog:SetWidth(260)
    dialog:SetHeight(150)
    
	-- 加载保存的窗口位置，如果没有则居中显示
    if WebDKP_DialogPositions and WebDKP_DialogPositions["WebDKP_LootCostDialog"] then
        local pos = WebDKP_DialogPositions["WebDKP_LootCostDialog"]
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
        if not WebDKP_DialogPositions then
            WebDKP_DialogPositions = {}
        end
        local x, y = dialog:GetLeft(), dialog:GetTop()
        WebDKP_DialogPositions["WebDKP_LootCostDialog"] = {x = x, y = y}
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
    dialog.costEditBox = CreateFrame("EditBox", "WebDKP_LootCostEditBox"..GetTime(), dialog, "InputBoxTemplate")
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
        WebDKP_EditLootRecord(uniqueId, newItemName, newCost)
        -- 修改分数后刷新界面，相当于按了刷新队伍
        WebDKP_UpdateTable()
        WebDKP_UpdateLootList()
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
        WebDKP_EditLootRecord(uniqueId, newItemName, newCost)
        -- 修改分数后刷新界面，相当于按了刷新队伍
        WebDKP_UpdateTable()
        WebDKP_Refresh()
        WebDKP_UpdateLootList()
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
    WebDKP_LootCostDialog = dialog
    dialog:Show()
    
	-- 防止输入框在显示时失去焦点
    dialog.costEditBox:SetFocus()
end

-- 显示修改替补记录对话框的函数
function WebDKP_ShowEditSubstituteDialog(uniqueId, currentReason, currentPoints)
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
    WebDKP_ShowCustomSubstituteReasonDialog(uniqueId, currentReason, logPoints)
end

-- 自定义替补记录原因输入对话框
function WebDKP_ShowCustomSubstituteReasonDialog(uniqueId, currentReason, currentPoints)
	-- 如果对话框已经存在，则销毁它
    if WebDKP_SubstituteReasonDialog then
        WebDKP_SubstituteReasonDialog:Hide()
        WebDKP_SubstituteReasonDialog = nil
    end
    
	-- 创建新的对话框（不使用BasicFrameTemplate）
    local dialog = CreateFrame("Frame", "WebDKP_SubstituteReasonDialog", UIParent)
     dialog:SetWidth(260)
    dialog:SetHeight(150)
    
	-- 加载保存的窗口位置，如果没有则居中显示
    if WebDKP_DialogPositions and WebDKP_DialogPositions["WebDKP_SubstituteReasonDialog"] then
        local pos = WebDKP_DialogPositions["WebDKP_SubstituteReasonDialog"]
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
        if not WebDKP_DialogPositions then
            WebDKP_DialogPositions = {}
        end
        local x, y = dialog:GetLeft(), dialog:GetTop()
        WebDKP_DialogPositions["WebDKP_SubstituteReasonDialog"] = {x = x, y = y}
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
    dialog.reasonEditBox = CreateFrame("EditBox", "WebDKP_SubstituteReasonEditBox"..GetTime(), dialog, "InputBoxTemplate")
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
            WebDKP_ShowCustomSubstitutePointsDialog(uniqueId, newReason, currentPoints)
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
            WebDKP_ShowCustomSubstitutePointsDialog(uniqueId, newReason, currentPoints)
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
    WebDKP_SubstituteReasonDialog = dialog
    dialog:Show()
    
	-- 防止输入框在显示时失去焦点
    dialog.reasonEditBox:SetFocus()
end

-- 自定义替补记录分数输入对话框
function WebDKP_ShowCustomSubstitutePointsDialog(uniqueId, newReason, currentPoints)
	-- 如果对话框已经存在，则销毁它
    if WebDKP_SubstitutePointsDialog then
        WebDKP_SubstitutePointsDialog:Hide()
        WebDKP_SubstitutePointsDialog = nil
    end
    
	-- 如果上一个对话框存在，隐藏它
    if WebDKP_SubstituteReasonDialog then
        WebDKP_SubstituteReasonDialog:Hide()
    end
    
	-- 创建新的对话框（不使用BasicFrameTemplate）
    local dialog = CreateFrame("Frame", "WebDKP_SubstitutePointsDialog", UIParent)
    dialog:SetWidth(260)
    dialog:SetHeight(150)
    
	-- 加载保存的窗口位置，如果没有则居中显示
    if WebDKP_DialogPositions and WebDKP_DialogPositions["WebDKP_SubstitutePointsDialog"] then
        local pos = WebDKP_DialogPositions["WebDKP_SubstitutePointsDialog"]
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
        if not WebDKP_DialogPositions then
            WebDKP_DialogPositions = {}
        end
        local x, y = dialog:GetLeft(), dialog:GetTop()
        WebDKP_DialogPositions["WebDKP_SubstitutePointsDialog"] = {x = x, y = y}
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
    dialog.pointsEditBox = CreateFrame("EditBox", "WebDKP_SubstitutePointsEditBox"..GetTime(), dialog, "InputBoxTemplate")
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
        WebDKP_EditSubstituteRecord(uniqueId, newReason, newPoints)
        -- 修改分数后刷新界面，相当于按了刷新队伍
        WebDKP_UpdateTable()
        WebDKP_UpdateLootList()
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
        WebDKP_EditSubstituteRecord(uniqueId, newReason, newPoints)
        -- 修改分数后刷新界面，相当于按了刷新队伍
        WebDKP_UpdateTable()
        WebDKP_Refresh()
        WebDKP_UpdateLootList()
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
    WebDKP_SubstitutePointsDialog = dialog
    dialog:Show()
    
	-- 防止输入框在显示时失去焦点
    dialog.pointsEditBox:SetFocus()
end

-- 显示修改奖励记录对话框的函数
function WebDKP_ShowEditAwardDialog(uniqueId, currentPoints, currentReason)
	-- 交换参数位置以与其他函数保持一致的调用模式
	-- 创建一个简单的输入框对话框
    StaticPopupDialogs["WEBDKP_EDIT_AWARD"] = {
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
                        StaticPopupDialogs["WEBDKP_EDIT_AWARD_POINTS"] = {
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
                                        local uniqueId = StaticPopupDialogs["WEBDKP_EDIT_AWARD_POINTS"].uniqueId
                                        local newReason = StaticPopupDialogs["WEBDKP_EDIT_AWARD_POINTS"].newReason
                                        WebDKP_EditAwardRecord(uniqueId, newReason, newPoints)
                                        -- 修改分数后刷新界面，相当于按了刷新队伍
                                        WebDKP_UpdateTable()
                                        WebDKP_UpdateLootList()
                                    end
                                end
                            end,
                            OnShow = function()
                                local showParentName = this:GetParent():GetName()
                                if showParentName then
                                     local editBox = getglobal(showParentName.."EditBox")
                                    if editBox then
                                        -- 确保输入框正确填充分数
                                        editBox:SetText(tostring(StaticPopupDialogs["WEBDKP_EDIT_AWARD_POINTS"].currentPoints))
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
                        StaticPopup_Show("WEBDKP_EDIT_AWARD_POINTS")
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
                    editBox:SetText(StaticPopupDialogs["WEBDKP_EDIT_AWARD"].currentReason)
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
    StaticPopup_Show("WEBDKP_EDIT_AWARD")
end

-- =========================================================================
-- Antigravity Added Helpers and Click Handlers
-- =========================================================================

function WebDKP_UpdateSingleAdjustLabel()
    local raidCount = 0
    local subCount = 0
    local otherCount = 0
    local totalCount = 0
    if WebDKP_DkpTable then
        for k, v in pairs(WebDKP_DkpTable) do
            if type(v) == "table" and v["Selected"] then
                totalCount = totalCount + 1
                if WebDKP_PlayerInGroup and WebDKP_PlayerInGroup(k) then
                    raidCount = raidCount + 1
                elseif WebDKP_IsSubRosterMember and WebDKP_IsSubRosterMember(k) then
                    subCount = subCount + 1
                else
                    otherCount = otherCount + 1
                end
            end
        end
    end

    if WebDKP_SingleAdjustFrameCharName then
        if totalCount == 0 then
            WebDKP_SingleAdjustFrameCharName:SetText("未选择任何玩家")
        else
            local display = "团队:" .. raidCount .. "人  替补:" .. subCount .. "人"
            if otherCount > 0 then
                display = display .. "  其他:" .. otherCount .. "人"
            end
            WebDKP_SingleAdjustFrameCharName:SetText(display)
        end
    end
end

function WebDKP_SingleAdjust_OnClick(mode)
    local pointsText = ""
    if WebDKP_SingleAdjustFramePoints then
        pointsText = WebDKP_SingleAdjustFramePoints:GetText() or ""
    end
    local points = tonumber(pointsText)
    if (not points) or (points < 0) then
        WebDKP_Print("请输入有效的分数（0 或正数）！")
        return
    end
    local reason = ""
    if WebDKP_SingleAdjustFrameReason then
        reason = WebDKP_SingleAdjustFrameReason:GetText() or ""
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
        WebDKP_Print("错误：请先在列表中选中要调分的玩家！")
        return
    end

    WebDKP_AddDKP(points, reason, "false", fullPlayers)

    if WebDKP_AnnounceAward then 
        WebDKP_AnnounceAward(points, reason) 
    end
    WebDKP_Print("已对选中的 " .. fullCount .. " 位玩家调分: " .. tostring(points) .. " 分 / 原因: " .. reason)
    if WebDKP_SingleAdjustFramePoints then 
        WebDKP_SingleAdjustFramePoints:SetText("") 
    end
    if WebDKP_UpdateTableToShow then WebDKP_UpdateTableToShow() end
    if WebDKP_UpdateTable then WebDKP_UpdateTable() end
end

function WebDKP_SingleAdjust_Spin(delta)
    local cur = tonumber(WebDKP_SingleAdjustFramePoints:GetText()) or 0
    cur = cur + delta
    if cur < 0 then cur = 0 end
    WebDKP_SingleAdjustFramePoints:SetText(tostring(cur))
end

function WebDKP_UpdateModeButtons()
    local m = WebDKP_ListMode or "raid"
    if WebDKP_FrameModeRaid then if m == "raid" then WebDKP_FrameModeRaid:Disable() else WebDKP_FrameModeRaid:Enable() end end
    if WebDKP_FrameModeSub then if m == "sub" then WebDKP_FrameModeSub:Disable() else WebDKP_FrameModeSub:Enable() end end
end

function WebDKP_SetListMode(mode)
    WebDKP_ListMode = mode
    if mode == "raid" then
        WebDKP_UpdatePlayersInGroup()
    end
    WebDKP_UpdateModeButtons()
    WebDKP_UpdateTableToShow()
    WebDKP_UpdateTable()
end

-- 点击「替补团队」标签时自动强制刷新替补名单
-- 超时未响应则弹确认窗：「替补队长超时未响应，是否清除替补人员名单」
function WebDKP_SwitchToSubMode()
    WebDKP_SetListMode("sub")

    -- 获取替补队长
    local captain = ""
    if WebDKP_ResolveSubCaptain then
        captain = WebDKP_ResolveSubCaptain()
    elseif WebDKP_Options and WebDKP_Options["SubSettings"] then
        captain = WebDKP_Options["SubSettings"].captain or ""
    end
    if captain == "" then return end  -- 无替补队长，仅切换显示

    -- 初始化 StaticPopup
    if not StaticPopupDialogs["WEBDKP_SUB_TIMEOUT_CONFIRM"] then
        StaticPopupDialogs["WEBDKP_SUB_TIMEOUT_CONFIRM"] = {
            text = "替补队长超时未响应，是否清除替补人员名单？",
            button1 = "清除",
            button2 = "保留",
            timeout = 0,
            whileDead = 1,
            hideOnEscape = 1,
            OnAccept = function()
                local dlg = StaticPopupDialogs["WEBDKP_SUB_TIMEOUT_CONFIRM"]
                local cap = dlg and dlg._captain or ""
                -- 清除 SubSync 缓存
                if WebDKP_SubSync_Cache and cap ~= "" then
                    WebDKP_SubSync_Cache[string.lower(cap)] = nil
                end
                -- 清除 PendingSubMembers
                if WebDKP_PendingSubMembers and cap ~= "" then
                    WebDKP_PendingSubMembers[cap] = nil
                    WebDKP_PendingSubMembers[string.lower(cap)] = nil
                end
                WebDKP_UpdateTableToShow()
                WebDKP_UpdateTable()
                WebDKP_Print("[WebDKP] 替补人员名单已清除。")
            end,
        }
    end

    -- 准备查询
    if not WebDKP_SubAwardData then WebDKP_SubAwardData = {} end
    WebDKP_SubAwardData.captain = captain
    WebDKP_SubAwardData.receivedResponse = false

    -- 强制向替补队长发起实时查询
    WebDKP_SubSync_ForceQuery = true
    if WebDKP_SearchSubMembers_Event then
        WebDKP_SearchSubMembers_Event()
    end

    local waitFrame = CreateFrame("Frame")
    waitFrame.startTime = GetTime()
    waitFrame:SetScript("OnUpdate", function()
        local frame = this or waitFrame
        local elapsed = GetTime() - (frame.startTime or 0)
        local responded = WebDKP_SubAwardData and WebDKP_SubAwardData.receivedResponse
        if responded then
            frame:SetScript("OnUpdate", nil)
            WebDKP_SubSync_ForceQuery = false
            WebDKP_UpdateTableToShow()
            WebDKP_UpdateTable()
        elseif elapsed >= 2 then
            frame:SetScript("OnUpdate", nil)
            WebDKP_SubSync_ForceQuery = false
            -- 超时：弹确认窗
            StaticPopupDialogs["WEBDKP_SUB_TIMEOUT_CONFIRM"]._captain = captain
            StaticPopup_Show("WEBDKP_SUB_TIMEOUT_CONFIRM")
        end
    end)
end

function WebDKP_IsSubRosterMember(name)
    local cap = ""
    if WebDKP_Options and WebDKP_Options["SubSettings"] then
        cap = WebDKP_Options["SubSettings"].captain or ""
    end
    if cap == "" then return false end
    if not WebDKP_SubSync_Cache then return false end
    local c = WebDKP_SubSync_Cache[string.lower(cap)]
    if not c or not c.members then return false end
    for memberName, _ in pairs(c.members) do
        if memberName == name then return true end
    end
    return false
end

-- ===== Tab1 right-side rebuild (3c) =====
function WebDKP_ToggleSubHalf()
    if not WebDKP_Options then WebDKP_Options = {} end
    local v = not WebDKP_Options["SubHalfPointsEnabled"]
    WebDKP_Options["SubHalfPointsEnabled"] = v
    if v then
        WebDKP_Options["SubPointsMode"] = "half"
    else
        WebDKP_Options["SubPointsMode"] = "same"
    end
end

function WebDKP_ToggleSubSame()
    if not WebDKP_Options then WebDKP_Options = {} end
    WebDKP_Options["SubSameReasonEnabled"] = not WebDKP_Options["SubSameReasonEnabled"]
end

function WebDKP_Tab1_SyncChecks()
    if WebDKP_AwardDKP_FrameSubCaptainChk then
        WebDKP_AwardDKP_FrameSubCaptainChk:SetChecked(WebDKP_Options and WebDKP_Options["IncludeSubCaptain"] and true or false)
    end
    if WebDKP_AwardDKP_FrameSubHalfChk then
        WebDKP_AwardDKP_FrameSubHalfChk:SetChecked(WebDKP_Options and WebDKP_Options["SubHalfPointsEnabled"] and true or false)
    end
    if WebDKP_AwardDKP_FrameSubSameChk then
        WebDKP_AwardDKP_FrameSubSameChk:SetChecked(WebDKP_Options and WebDKP_Options["SubSameReasonEnabled"] and true or false)
    end
    if WebDKP_AwardDKP_FrameSubLeaderInput and WebDKP_Options and WebDKP_Options["SubSettings"] then
        WebDKP_AwardDKP_FrameSubLeaderInput:SetText(WebDKP_Options["SubSettings"].captain or "")
    end
end

function WebDKP_Tab1_SaveSubCaptain()
    local txt = ""
    if WebDKP_AwardDKP_FrameSubLeaderInput then
        txt = WebDKP_AwardDKP_FrameSubLeaderInput:GetText() or ""
    end
    txt = string.gsub(txt, "^%s+", "")
    txt = string.gsub(txt, "%s+$", "")
    if not WebDKP_Options then WebDKP_Options = {} end
    if not WebDKP_Options["SubSettings"] then WebDKP_Options["SubSettings"] = { captain = "" } end
    WebDKP_Options["SubSettings"]["captain"] = txt
    WebDKP_Options["SubLeader"] = txt
    if WebDKP_SubAwardData then WebDKP_SubAwardData.captain = txt end
    if WebDKP_UpdateCaptainLabel then WebDKP_UpdateCaptainLabel() end
    if WebDKP_AwardDKP_FrameSubCaptainLabel then
        local disp = "无"
        if txt ~= "" then disp = txt end
        WebDKP_AwardDKP_FrameSubCaptainLabel:SetText("替补队长: " .. disp)
    end
    if txt ~= "" then
        WebDKP_Print("已设置替补队长: " .. txt)
    else
        WebDKP_Print("已清空替补队长。")
    end
end

function WebDKP_DoImportInitial(text)
    if not text or text == "" then
        WebDKP_Print("导入内容为空！")
        return
    end
    local tableid = WebDKP_GetTableid()
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
            local class = fields[2] or "未知"
            local dkp = tonumber(fields[3]) or 0
            if name and name ~= "" then
                local enClass = class
                if WebDKP_NormalizeClassName then enClass = WebDKP_NormalizeClassName(class) end
                if not WebDKP_DkpTable[name] then WebDKP_DkpTable[name] = {} end
                WebDKP_DkpTable[name]["dkp_" .. tableid] = dkp
                WebDKP_DkpTable[name]["class"] = enClass
                count = count + 1
            end
        end
    end
    WebDKP_Print("已导入 " .. count .. " 条初始分。")
    if WebDKP_SaveToDisk then WebDKP_SaveToDisk() end
    if WebDKP_UpdateTableToShow then WebDKP_UpdateTableToShow() end
    if WebDKP_UpdateTable then WebDKP_UpdateTable() end
end

function WebDKP_ShowImportInitial()
    if not WebDKP_ImportInitialFrame then
        local f = CreateFrame("Frame", "WebDKP_ImportInitialFrame", UIParent)
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
        local sf = CreateFrame("ScrollFrame", "WebDKP_ImportInitialScroll", f, "UIPanelScrollFrameTemplate")
        sf:SetPoint("TOPLEFT", 18, -58)
        sf:SetPoint("BOTTOMRIGHT", -36, 48)
        local eb = CreateFrame("EditBox", "WebDKP_ImportInitialEdit", sf)
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
        doBtn:SetScript("OnClick", function() WebDKP_DoImportInitial(WebDKP_ImportInitialEdit:GetText()) end)
        local closeBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        closeBtn:SetWidth(100)
        closeBtn:SetHeight(24)
        closeBtn:SetPoint("BOTTOMRIGHT", -24, 14)
        closeBtn:SetText("关闭")
        closeBtn:SetScript("OnClick", function() WebDKP_ImportInitialFrame:Hide() end)
    end
    WebDKP_ImportInitialEdit:SetText("")
    WebDKP_ImportInitialFrame:Show()
end

function WebDKP_BuildExportText()
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

function WebDKP_ShowExportRecords()
    if not WebDKP_ExportRecordsFrame then
        local f = CreateFrame("Frame", "WebDKP_ExportRecordsFrame", UIParent)
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
        local hint = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        hint:SetPoint("TOPLEFT", 20, -40)
        hint:SetText("格式：角色ID,分值,原因,日期,时间,职业 （点全选后 Ctrl+C 复制）")
        local sf = CreateFrame("ScrollFrame", "WebDKP_ExportRecordsScroll", f, "UIPanelScrollFrameTemplate")
        sf:SetPoint("TOPLEFT", 18, -58)
        sf:SetPoint("BOTTOMRIGHT", -36, 48)
        local eb = CreateFrame("EditBox", "WebDKP_ExportRecordsEdit", sf)
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
        selBtn:SetScript("OnClick", function() WebDKP_ExportRecordsEdit:SetFocus(); WebDKP_ExportRecordsEdit:HighlightText() end)
        local closeBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        closeBtn:SetWidth(100)
        closeBtn:SetHeight(24)
        closeBtn:SetPoint("BOTTOMRIGHT", -24, 14)
        closeBtn:SetText("关闭")
        closeBtn:SetScript("OnClick", function() WebDKP_ExportRecordsFrame:Hide() end)
    end
    WebDKP_ExportRecordsEdit:SetText(WebDKP_BuildExportText())
    WebDKP_ExportRecordsFrame:Show()
    WebDKP_ExportRecordsEdit:SetFocus()
    WebDKP_ExportRecordsEdit:HighlightText()
end


function WebDKP_Options_Init()
    if not WebDKP_Options then WebDKP_Options = {} end
    if not WebDKP_WebOptions then WebDKP_WebOptions = {} end
    
    if WebDKP_Options_FrameToggleAutofill then
        WebDKP_Options_FrameToggleAutofill:SetChecked(WebDKP_WebOptions["AutofillEnabled"] == 1)
    end
    if WebDKP_Options_FrameToggleAutoAward then
        WebDKP_Options_FrameToggleAutoAward:SetChecked(WebDKP_Options["AutoAwardEnabled"] == 1)
    end
    if WebDKP_Options_FrameToggleZeroSum then
        WebDKP_Options_FrameToggleZeroSum:SetChecked(WebDKP_WebOptions["ZeroSumEnabled"] == 1)
    end
    if WebDKP_Options_FrameToggleMapValidation then
        WebDKP_Options_FrameToggleMapValidation:SetChecked(WebDKP_WebOptions["MapValidationEnabled"] == 1)
    end

    if WebDKP_Options_FrameToggleSilentMode then
        WebDKP_Options_FrameToggleSilentMode:SetChecked(WebDKP_Options["SilentMode"] and true or false)
    end
    if WebDKP_Options_FrameToggleRaidDkpReply then
        WebDKP_Options_FrameToggleRaidDkpReply:SetChecked(WebDKP_Options["RaidDkpReply"] and true or false)
    end
    if WebDKP_Options_FrameToggleIncludeSubCaptain then
        WebDKP_Options_FrameToggleIncludeSubCaptain:SetChecked(WebDKP_Options["IncludeSubCaptain"] and true or false)
    end
    if WebDKP_Options_FrameToggleQuickFloatEnabled then
        WebDKP_Options_FrameToggleQuickFloatEnabled:SetChecked(WebDKP_Options["QuickFloatEnabled"] and true or false)
    end
    if WebDKP_Options["AuctionMode"] == nil then WebDKP_Options["AuctionMode"] = "public" end
    if WebDKP_Options_FrameToggleAuctionPublic then
        WebDKP_Options_FrameToggleAuctionPublic:SetChecked(WebDKP_Options["AuctionMode"] ~= "anonymous")
    end
    if WebDKP_Options_FrameToggleAuctionAnonymous then
        WebDKP_Options_FrameToggleAuctionAnonymous:SetChecked(WebDKP_Options["AuctionMode"] == "anonymous")
    end

end

function WebDKP_ToggleSilentMode()
    WebDKP_Options["SilentMode"] = not WebDKP_Options["SilentMode"]
    if WebDKP_Options["SilentMode"] then
        WebDKP_Print("静默模式已开启 - 团队播报已关闭")
    else
        WebDKP_Print("静默模式已关闭 - 团队播报已开启")
    end
end

function WebDKP_ToggleRaidDkpReply()
    WebDKP_Options["RaidDkpReply"] = not WebDKP_Options["RaidDkpReply"]
    if WebDKP_Options["RaidDkpReply"] then
        WebDKP_Print("允许团队成员查询已开启")
    else
        WebDKP_Print("允许团队成员查询已关闭")
    end
end

function WebDKP_ToggleIncludeSubCaptain()
    WebDKP_Options["IncludeSubCaptain"] = not WebDKP_Options["IncludeSubCaptain"]
    if WebDKP_Options["IncludeSubCaptain"] then
        WebDKP_Print("替补加分包含替补队长已开启")
    else
        WebDKP_Print("替补加分包含替补队长已关闭")
    end
end

function WebDKP_ToggleQuickFloatEnabled()
    WebDKP_Options["QuickFloatEnabled"] = not WebDKP_Options["QuickFloatEnabled"]
    if WebDKP_Options["QuickFloatEnabled"] then
        WebDKP_Print("快捷悬浮窗已启用")
        if WebDKP_Bid_ButtonFrame then WebDKP_Bid_ButtonFrame:Show() end
    else
        WebDKP_Print("快捷悬浮窗已禁用")
        if WebDKP_Bid_ButtonFrame then WebDKP_Bid_ButtonFrame:Hide() end
    end
end

function WebDKP_SelectAuctionMode(mode)
    if not WebDKP_Options then WebDKP_Options = {} end
    if mode ~= "anonymous" then mode = "public" end
    WebDKP_Options["AuctionMode"] = mode
    if WebDKP_Options_FrameToggleAuctionPublic then
        WebDKP_Options_FrameToggleAuctionPublic:SetChecked(mode == "public")
    end
    if WebDKP_Options_FrameToggleAuctionAnonymous then
        WebDKP_Options_FrameToggleAuctionAnonymous:SetChecked(mode == "anonymous")
    end
    if mode == "anonymous" then
        WebDKP_Print("拍卖模式已设为：匿名拍卖")
    else
        WebDKP_Print("拍卖模式已设为：公开拍卖")
    end
end

function WebDKP_IsAnonymousAuction()
    return WebDKP_Options and WebDKP_Options["AuctionMode"] == "anonymous"
end

function WebDKP_SelectSubPointsMode(mode)
    WebDKP_Options["SubPointsMode"] = mode
    
    if WebDKP_AwardDKP_FrameSubSame then
        WebDKP_AwardDKP_FrameSubSame:SetChecked(mode == "same")
    end
    if WebDKP_AwardDKP_FrameSubHalf then
        WebDKP_AwardDKP_FrameSubHalf:SetChecked(mode == "half")
    end
    if WebDKP_AwardDKP_FrameSubCustom then
        WebDKP_AwardDKP_FrameSubCustom:SetChecked(mode == "custom")
    end
    
    if mode == "custom" then
        if WebDKP_AwardDKP_FrameSubCustomPercent then
            WebDKP_AwardDKP_FrameSubCustomPercent:Show()
        end
        if WebDKP_AwardDKP_FrameSubCustomPercentLabel then
            WebDKP_AwardDKP_FrameSubCustomPercentLabel:Show()
        end
    else
        if WebDKP_AwardDKP_FrameSubCustomPercent then
            WebDKP_AwardDKP_FrameSubCustomPercent:Hide()
            WebDKP_AwardDKP_FrameSubCustomPercent:ClearFocus()
        end
        if WebDKP_AwardDKP_FrameSubCustomPercentLabel then
            WebDKP_AwardDKP_FrameSubCustomPercentLabel:Hide()
        end
    end
end

function WebDKP_ResolveSubCaptain()
    local cap = ""
    if WebDKP_AwardDKP_FrameSubLeaderInput then
        local t = WebDKP_AwardDKP_FrameSubLeaderInput:GetText() or ""
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
        if WebDKP_SubAwardData then WebDKP_SubAwardData.captain = cap end
        if WebDKP_AwardDKP_FrameSubLeaderInput and (WebDKP_AwardDKP_FrameSubLeaderInput:GetText() or "") ~= cap then
            WebDKP_AwardDKP_FrameSubLeaderInput:SetText(cap)
        end
        if WebDKP_UpdateCaptainLabel then WebDKP_UpdateCaptainLabel() end
    end
    return cap
end

function WebDKP_TestStandbySync_Event()
    local captain = WebDKP_ResolveSubCaptain()
    if captain == "" then
        WebDKP_Print("错误：请先在“分数调整”界面的“设置替补队长”处输入名字并点击“设置”按钮！")
        return
    end
    if not WebDKP_SubAwardData then
        WebDKP_SubAwardData = { captain = captain, members = {}, bossName = "", reason = "", points = 0 }
    end
    WebDKP_Print("正在发送同步测试请求到: " .. captain .. " ...")
    if not WebDKP_PendingSubMembers then
        WebDKP_PendingSubMembers = {}
    end
    WebDKP_PendingSubMembers[captain] = {}
    WebDKP_SubAwardData.captain = captain
    WebDKP_SubAwardData.receivedResponse = false
    WebDKP_SubSync_ForceQuery = true
    pcall(SendAddonMessage, "AMB_TBQQ", captain, "GUILD")
    WebDKP_SubSync_ForceQuery = false
    
    if not WebDKP_TestSyncTimerFrame then
        WebDKP_TestSyncTimerFrame = CreateFrame("Frame")
    end
    
    WebDKP_TestSyncTimerFrame.timeElapsed = 0
    WebDKP_TestSyncTimerFrame:SetScript("OnUpdate", function()
        local elapsed = tonumber(arg1) or 0
        this.timeElapsed = this.timeElapsed + elapsed
        
        if WebDKP_SubAwardData.receivedResponse then
            this:SetScript("OnUpdate", nil)
            local subList = WebDKP_PendingSubMembers[captain] or {}
            local count = 0
            for _ in pairs(subList) do
                count = count + 1
            end
            WebDKP_Print("|cff00ff00[WebDKP] 同步测试成功！|r 替补队长 " .. captain .. " 在线，当前替补人数: " .. count)
            return
        end
        
        if this.timeElapsed >= 4.0 then
            this:SetScript("OnUpdate", nil)
            WebDKP_Print("|cffff0000[WebDKP] 同步测试失败！|r 无法收到 " .. captain .. " 的响应。请确保对方在线、安装了本插件且是替补队长。")
        end
    end)
end

function WebDKP_AwardRaidAndSub_Event_LegacyUnused2()
    local pointsText = WebDKP_AwardDKP_FramePoints:GetText() or ""
    local points = tonumber(pointsText)
    if not points or points <= 0 then
        WebDKP_Print("错误：请输入有效的加分值！")
        return
    end
    
    local reason = WebDKP_AwardDKP_FrameReason:GetText() or ""
    if reason == "" then
        reason = "未指定原因"
    end
    
    local pointsMode = WebDKP_Options["SubPointsMode"] or "same"
    local standbyPoints = points
    if pointsMode == "half" then
        standbyPoints = points * 0.5
    elseif pointsMode == "custom" then
        local customPercentText = WebDKP_AwardDKP_FrameSubCustomPercent:GetText() or ""
        local percent = tonumber(customPercentText) or 0
        standbyPoints = points * (percent / 100)
    end
    
    local captain = ""
    if WebDKP_Options_FrameSubLeader then
        captain = WebDKP_Options_FrameSubLeader:GetText() or ""
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
        WebDKP_AddDKP(points, reason, "false", players)
        WebDKP_AnnounceAward(points, reason)
        WebDKP_Print("加分成功！已为大团发放分数。")
        WebDKP_UpdateTable()
        return
    end
    
    WebDKP_Print("正在向替补队长 " .. captain .. " 请求替补人员名单...")
    if not WebDKP_PendingSubMembers then
        WebDKP_PendingSubMembers = {}
    end
    WebDKP_PendingSubMembers[captain] = {}
    WebDKP_SubAwardData.captain = captain
    WebDKP_SubAwardData.receivedResponse = false
    
    pcall(SendAddonMessage, "AMB_TBQQ", captain, "GUILD")
    
    if not WebDKP_RaidAwardTimerFrame then
        WebDKP_RaidAwardTimerFrame = CreateFrame("Frame")
    end
    
    WebDKP_RaidAwardTimerFrame.timeElapsed = 0
    WebDKP_RaidAwardTimerFrame:SetScript("OnUpdate", function()
        local elapsed = tonumber(arg1) or 0
        this.timeElapsed = this.timeElapsed + elapsed
        
        if WebDKP_SubAwardData.receivedResponse or this.timeElapsed >= 1.5 then
            this:SetScript("OnUpdate", nil)
            
            local standbyPlayers = {}
            if WebDKP_SubAwardData.receivedResponse then
                local subList = WebDKP_PendingSubMembers[captain] or {}
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
                
                WebDKP_Print("替补名单获取成功，正在发放 DKP 分数...")
            else
                WebDKP_Print("|cffff0000[WebDKP] 替补同步超时！|r 降级为仅对大团成员发放 DKP 分数。")
            end
            
            local finalRaidPlayers = {}
            for idx, p in ipairs(raidPlayers) do
                finalRaidPlayers[idx - 1] = { ["name"] = p.name, ["class"] = p.class }
            end
            WebDKP_AddDKP(points, reason, "false", finalRaidPlayers)
            
            if table.getn(standbyPlayers) > 0 then
                local finalStandbyPlayers = {}
                for idx, p in ipairs(standbyPlayers) do
                    finalStandbyPlayers[idx - 1] = { ["name"] = p.name, ["class"] = p.class }
                end
                WebDKP_AddDKP(standbyPoints, reason .. "-替补", "false", finalStandbyPlayers)
                WebDKP_Print(string.format("发放完毕！大团 %d 人 (+%.2f)，替补 %d 人 (+%.2f)。", 
                    table.getn(raidPlayers), points, table.getn(standbyPlayers), standbyPoints))
            else
                WebDKP_Print(string.format("发放完毕！大团 %d 人 (+%.2f)，替补 0 人。", table.getn(raidPlayers), points))
            end
            
            WebDKP_AnnounceAward(points, reason)
            WebDKP_UpdateTable()
        end
    end)
end

function WebDKP_AwardRaidAndSub_Event()
    local pointsText = ""
    local reason = ""

    if WebDKP_AwardDKP_FramePoints then
        pointsText = WebDKP_AwardDKP_FramePoints:GetText() or ""
    elseif WebDKP_BossAwardData and WebDKP_BossAwardData.points then
        pointsText = tostring(WebDKP_BossAwardData.points)
    end

    if WebDKP_AwardDKP_FrameReason then
        reason = WebDKP_AwardDKP_FrameReason:GetText() or ""
    elseif WebDKP_BossAwardData and WebDKP_BossAwardData.bossName then
        reason = "击杀-" .. WebDKP_BossAwardData.bossName
    end

    if pointsText == "" then
        WebDKP_Print("错误：请输入有效的分数。")
        PlaySound("igQuestFailed")
        return
    end

    local points = nil
    if WebDKP_ROUND then
        points = WebDKP_ROUND(pointsText, 2)
    else
        points = tonumber(pointsText)
    end
    if type(points) ~= "number" or points ~= points then
        WebDKP_Print("错误：分数必须是数字。")
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
        if WebDKP_AwardDKP_FrameSubCustomPercent then
            percentText = WebDKP_AwardDKP_FrameSubCustomPercent:GetText() or ""
        end
        local percent = tonumber(percentText)
        if not percent and WebDKP_Options then
            percent = tonumber(WebDKP_Options["SubPointsCustomPercent"])
        end
        if not percent then
            WebDKP_Print("错误：请输入有效的替补百分比。")
            PlaySound("igQuestFailed")
            return
        end
        subPoints = points * (percent / 100)
        if WebDKP_Options then
            WebDKP_Options["SubPointsCustomPercent"] = percent
        end
    end

    if WebDKP_ROUND then
        subPoints = WebDKP_ROUND(subPoints, 2)
    end

    if WebDKP_SubAwardData then
        WebDKP_SubAwardData.reason = reason
        WebDKP_SubAwardData.points = subPoints
    end

    WebDKP_RunRaidAndSubAward(points, subPoints, reason)
end
