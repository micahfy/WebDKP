-- WEB DKP 报名打卡功能模块
-- 提供报名打卡相关的功能，包括：
-- 1. 报名打卡
-- 2. 集合分分配
-- 3. 替补时间管理


-- 报名打卡临时数据存储
WebDKP_CheckInData = {
    registeredPlayers = {},  -- 已报名玩家列表
    standbyPlayers = {},      -- 替补玩家列表
    rallyPoints = 2,          -- 集合分默认值
    standbyTime = 5,          -- 替补时间默认值（分钟）
    lastCheckInTime = 0,      -- 上次签到时间
    unregisteredPoints = 0,   -- 未报名分数默认值
    absentPoints = 0          -- 缺席分数默认值
}



-- 保存打卡设置
WebDKP_CheckIn_SaveSettings = function()
    local standbyTime = 5
    local rallyPoints = 2
    local unregisteredPoints = 0
    local absentPoints = 0
    
    -- 如果框架和输入框存在，从输入框获取值
    if WebDKP_CheckInFrame and WebDKP_CheckInStandbyTimeEdit and WebDKP_CheckInRallyPointsEdit then
        standbyTime = tonumber(WebDKP_CheckInStandbyTimeEdit:GetText()) or 5
        rallyPoints = tonumber(WebDKP_CheckInRallyPointsEdit:GetText()) or 2
        
        -- 获取未报名和缺席分数（允许负值）
        if WebDKP_CheckInUnregisteredEdit then
            unregisteredPoints = tonumber(WebDKP_CheckInUnregisteredEdit:GetText()) or 0
        end
        if WebDKP_CheckInAbsentEdit then
            absentPoints = tonumber(WebDKP_CheckInAbsentEdit:GetText()) or 0
        end
    elseif WebDKP_CheckInData then
        -- 如果框架不存在但有CheckInData，使用现有的值（允许负值）
        standbyTime = WebDKP_CheckInData.standbyTime or 5
        rallyPoints = WebDKP_CheckInData.rallyPoints or 2
        unregisteredPoints = WebDKP_CheckInData.unregisteredPoints or 0  -- 允许负值
        absentPoints = WebDKP_CheckInData.absentPoints or 0  -- 允许负值
    elseif WebDKP_Options and WebDKP_Options["CheckInSettings"] then
        -- 如果有保存的设置，使用保存的值（允许负值）
        standbyTime = WebDKP_Options["CheckInSettings"].standbyTime or 5
        rallyPoints = WebDKP_Options["CheckInSettings"].rallyPoints or 2
        unregisteredPoints = WebDKP_Options["CheckInSettings"].unregisteredPoints or 0  -- 允许负值
        absentPoints = WebDKP_Options["CheckInSettings"].absentPoints or 0  -- 允许负值
    end
    
    -- 验证数值有效性（允许负分）
    if standbyTime <= 0 then standbyTime = 5 end
    if rallyPoints <= 0 then rallyPoints = 2 end
    -- 未报名和缺席分数允许负值，不限制
    
    local settings = {
        standbyTime = standbyTime,
        rallyPoints = rallyPoints,
        unregisteredPoints = unregisteredPoints,
        absentPoints = absentPoints
    }
    
    -- 更新WebDKP_CheckInData中的设置
    WebDKP_CheckInData.standbyTime = settings.standbyTime
    WebDKP_CheckInData.rallyPoints = settings.rallyPoints
    WebDKP_CheckInData.unregisteredPoints = settings.unregisteredPoints
    WebDKP_CheckInData.absentPoints = settings.absentPoints
    
    -- 直接保存到全局变量（与衰减模块相同的机制）
    WebDKP_SavedCheckInSettings = settings
    
    -- 确保WebDKP_Options存在
    if not WebDKP_Options then
        WebDKP_Options = {}
    end
    
    -- 保存到插件设置
    WebDKP_Options["CheckInSettings"] = settings
end

-- 加载打卡设置
WebDKP_CheckIn_LoadSettings = function()
    local hasFrame = WebDKP_CheckInFrame and WebDKP_CheckInStandbyTimeEdit and WebDKP_CheckInRallyPointsEdit
    
    local settings = nil
    local source = "未知"
    
    -- 尝试从插件设置加载（优先使用WebDKP_Options）
    if WebDKP_Options and WebDKP_Options["CheckInSettings"] then
        settings = WebDKP_Options["CheckInSettings"]
        source = "WebDKP_Options.CheckInSettings"
        -- WebDKP_Print("找到WebDKP_Options.CheckInSettings: 替补时间=" .. tostring(settings.standbyTime) .. ", 集合分=" .. tostring(settings.rallyPoints) .. ", 未报名=" .. tostring(settings.unregisteredPoints) .. ", 缺席=" .. tostring(settings.absentPoints))
    -- 尝试从全局变量加载
    elseif WebDKP_SavedCheckInSettings then
        settings = WebDKP_SavedCheckInSettings
        source = "WebDKP_SavedCheckInSettings"
        -- WebDKP_Print("找到WebDKP_SavedCheckInSettings: 替补时间=" .. tostring(settings.standbyTime) .. ", 集合分=" .. tostring(settings.rallyPoints) .. ", 未报名=" .. tostring(settings.unregisteredPoints) .. ", 缺席=" .. tostring(settings.absentPoints))
    else
        -- WebDKP_Print("未找到保存的设置，将使用默认值")
    end
    
    -- 如果找到设置，验证并应用它们
    if settings then
        -- 验证设置数据完整性
        local standbyTime = tonumber(settings.standbyTime) or 5
        local rallyPoints = tonumber(settings.rallyPoints) or 2
        local unregisteredPoints = tonumber(settings.unregisteredPoints) or 0
        local absentPoints = tonumber(settings.absentPoints) or 0
        
        -- 确保数值有效（允许负分）
        if standbyTime <= 0 then standbyTime = 5 end
        if rallyPoints <= 0 then rallyPoints = 2 end
        -- 未报名和缺席分数允许负值，不限制
        
        -- 如果框架存在，应用设置到输入框
        if hasFrame then
            WebDKP_CheckInStandbyTimeEdit:SetText(standbyTime)
            WebDKP_CheckInRallyPointsEdit:SetText(rallyPoints)
            if WebDKP_CheckInUnregisteredEdit then
                WebDKP_CheckInUnregisteredEdit:SetText(unregisteredPoints)
            end
            if WebDKP_CheckInAbsentEdit then
                WebDKP_CheckInAbsentEdit:SetText(absentPoints)
            end
        end
        
        -- 更新数据存储
        WebDKP_CheckInData.standbyTime = standbyTime
        WebDKP_CheckInData.rallyPoints = rallyPoints
        WebDKP_CheckInData.unregisteredPoints = unregisteredPoints
        WebDKP_CheckInData.absentPoints = absentPoints
        
        -- WebDKP_Print("设置已加载：替补时间=" .. standbyTime .. ", 集合分=" .. rallyPoints .. ", 未报名=" .. unregisteredPoints .. ", 缺席=" .. absentPoints)
    else
        -- 使用默认值（允许负分）
        local defaultStandbyTime = WebDKP_CheckInData.standbyTime or 5
        local defaultRallyPoints = WebDKP_CheckInData.rallyPoints or 2
        local defaultUnregisteredPoints = WebDKP_CheckInData.unregisteredPoints or 0  -- 允许负值
        local defaultAbsentPoints = WebDKP_CheckInData.absentPoints or 0  -- 允许负值
        
        -- 如果框架存在，应用默认值到输入框
        if hasFrame then
            WebDKP_CheckInStandbyTimeEdit:SetText(defaultStandbyTime)
            WebDKP_CheckInRallyPointsEdit:SetText(defaultRallyPoints)
            if WebDKP_CheckInUnregisteredEdit then
                WebDKP_CheckInUnregisteredEdit:SetText(defaultUnregisteredPoints)
            end
            if WebDKP_CheckInAbsentEdit then
                WebDKP_CheckInAbsentEdit:SetText(defaultAbsentPoints)
            end
        end
        
        WebDKP_Print("使用默认值: 替补时间=" .. defaultStandbyTime .. ", 集合分=" .. defaultRallyPoints .. ", 未报名=" .. defaultUnregisteredPoints .. ", 缺席=" .. defaultAbsentPoints)
    end
end

-- 初始化报名打卡框架
WebDKP_CheckIn_Init = function()
    if not WebDKP_CheckInFrame then
        WebDKP_Print("错误：报名打卡框架未找到，请检查WebDKDKP是否正确安装")
        return
    end
    
    -- 添加输入框更改事件，自动保存设置
    if WebDKP_CheckInStandbyTimeEdit then
        WebDKP_CheckInStandbyTimeEdit:SetScript("OnTextChanged", function()
            WebDKP_CheckIn_SaveSettings()
        end)
    end
    
    if WebDKP_CheckInRallyPointsEdit then
        WebDKP_CheckInRallyPointsEdit:SetScript("OnTextChanged", function()
            WebDKP_CheckIn_SaveSettings()
        end)
    end
    
    if WebDKP_CheckInUnregisteredEdit then
        WebDKP_CheckInUnregisteredEdit:SetScript("OnTextChanged", function()
            WebDKP_CheckIn_SaveSettings()
        end)
    end
    
    if WebDKP_CheckInAbsentEdit then
        WebDKP_CheckInAbsentEdit:SetScript("OnTextChanged", function()
            WebDKP_CheckIn_SaveSettings()
        end)
    end
    
    -- 尝试加载已保存的设置（参考衰减模块的正确做法）
    WebDKP_CheckIn_LoadSettings()
end
-- 报名打卡功能
WebDKP_CheckIn = function()
    -- 获取输入值（不再需要玩家名单输入框，直接使用固定文件名）
    local standbyTime = tonumber(WebDKP_CheckInStandbyTimeEdit:GetText()) or 5
    local rallyPoints = tonumber(WebDKP_CheckInRallyPointsEdit:GetText()) or 2
    local absentPoints = tonumber(WebDKP_CheckInAbsentEdit:GetText()) or 0
    local unregisteredPoints = tonumber(WebDKP_CheckInUnregisteredEdit:GetText()) or 0
  
    -- 验证所有分数参数的有效性
    if type(rallyPoints) ~= "number" or rallyPoints ~= rallyPoints then
        WebDKP_Print("错误：集合分数无效，请检查输入")
        return
    end
    if type(absentPoints) ~= "number" or absentPoints ~= absentPoints then
        WebDKP_Print("错误：缺席分数无效，请检查输入")
        return
    end
    if type(unregisteredPoints) ~= "number" or unregisteredPoints ~= unregisteredPoints then
        WebDKP_Print("错误：未报名分数无效，请检查输入")
        return
    end
    
    -- 保存当前设置
    WebDKP_CheckIn_SaveSettings()
    
    -- 清空已报名玩家列表
    WebDKP_CheckInData.registeredPlayers = {}
    WebDKP_CheckInData.standbyPlayers = {}
    WebDKP_CheckInData.rallyPoints = rallyPoints
    WebDKP_CheckInData.standbyTime = standbyTime
    WebDKP_CheckInData.unregisteredPoints = unregisteredPoints
    WebDKP_CheckInData.absentPoints = absentPoints
    WebDKP_CheckInData.lastCheckInTime = time()
    
    -- 固定使用"报名打卡"作为文件名
    local fileName = "报名打卡"
    local playerCount = 0
    
    -- 检查ImportFile函数是否可用
    if ImportFile then
        -- WebDKP_Print("正在导入玩家名单文件: " .. fileName)
        local importData = ImportFile(fileName)
        
        if importData then
            -- 简单的文本分割函数，兼容Lua 5.0
            local splitLines = function(text)
                local lines = {}
                local line = ""
                local pos = 1
                local len = string.len(text)
                
                while pos <= len do
                    local nextLinePos = string.find(text, "\n", pos)
                    if nextLinePos then
                        line = string.sub(text, pos, nextLinePos - 1)
                        pos = nextLinePos + 1
                    else
                        line = string.sub(text, pos)
                        pos = len + 1
                    end
                    
                    -- 去除首尾空格
                    line = string.gsub(line, "^%s*(.-)%s*$", "%1")
                    if line ~= "" then
                        table.insert(lines, line)
                    end
                end
                
                return lines
            end
            
            local playerNames = splitLines(importData)
            for _, playerName in ipairs(playerNames) do
                table.insert(WebDKP_CheckInData.registeredPlayers, playerName)
                playerCount = playerCount + 1
            end
            WebDKP_Print("成功从文件导入 " .. playerCount .. " 名报名玩家")
        else
            WebDKP_Print("错误：无法读取文件或文件不存在")
            WebDKP_Print("请确认以下事项：")
            WebDKP_Print("1. 游戏安装目录下存在'imports'文件夹")
            WebDKP_Print("2. imports目录下有'"..fileName.."'文件")
            WebDKP_Print("3. 文件格式正确：一行一个玩家名字")
            return
        end
    else
        WebDKP_Print("错误：ImportFile函数不可用")
        WebDKP_Print("请检查插件是否完整加载或游戏版本兼容性")
        return
    end
    
    -- WebDKP_Print("已加载 " .. playerCount .. " 名报名玩家")
    
    -- 获取当前队伍/团队成员
    local groupMembers = {}
    local raidMembers = GetNumRaidMembers()
    local partyMembers = GetNumPartyMembers()
    
    if raidMembers > 0 then
        -- 在团队中
        for i = 1, raidMembers do
            local name = GetRaidRosterInfo(i)
            if name then
                name = string.gsub(name, "-.*$", "") -- 去除服务器名
                table.insert(groupMembers, name)
            end
        end
    elseif partyMembers > 0 then
        -- 在小队中
        table.insert(groupMembers, UnitName("player"))
        for i = 1, partyMembers do
            local name = UnitName("party" .. i)
            if name then
                name = string.gsub(name, "-.*$", "") -- 去除服务器名
                table.insert(groupMembers, name)
            end
        end
    else
        -- 不在队伍中
        WebDKP_Print("错误：您不在队伍或团队中，无法进行报名打卡")
        return
    end
    
    -- 分类处理玩家
    local registeredInGroup = {}  -- 在队伍中的已报名玩家
    local unregisteredInGroup = {} -- 在队伍中的未报名玩家
    
    for _, name in ipairs(groupMembers) do
        local isRegistered = false
        for _, regName in ipairs(WebDKP_CheckInData.registeredPlayers) do
            if name and regName and string.lower(name) == string.lower(regName) then
                table.insert(registeredInGroup, name)
                isRegistered = true
                break
            end
        end
        
        if not isRegistered then
            table.insert(unregisteredInGroup, name)
        end
    end
    
    -- 对未报名的玩家进行处理
    if table.getn(unregisteredInGroup) > 0 then
        -- WebDKP_Print("以下" .. table.getn(unregisteredInGroup) .. "名玩家未在报名名单中：")
        for _, name in ipairs(unregisteredInGroup) do
            -- WebDKP_Print("  - " .. name)
        end
    end
    
    -- 为已报名玩家添加集合分
    if table.getn(registeredInGroup) > 0 then
        -- WebDKP_Print("已报名玩家：")
        local playerTable = {}
        for i, name in ipairs(registeredInGroup) do
            playerTable[i-1] = {
                name = name,
                class = WebDKP_GetPlayerClass(name) or "Unknown"
            }
            -- WebDKP_Print("  - " .. name .. " +" .. rallyPoints .. " (集合分)")
        end
        
        local tableid = WebDKP_GetTableid()
        WebDKP_AddDKP(rallyPoints, "集合分", "false", playerTable, tableid)
        -- WebDKP_Print("已为 " .. table.getn(registeredInGroup) .. " 名已报名玩家添加集合分")
    end
    
    -- 为未报名玩家添加集合分-未报名
    if table.getn(unregisteredInGroup) > 0 then
        -- WebDKP_Print("未报名玩家：")
        local playerTable = {}
        for i, name in ipairs(unregisteredInGroup) do
            playerTable[i-1] = {
                name = name,
                class = WebDKP_GetPlayerClass(name) or "Unknown"
            }
            -- WebDKP_Print("  - " .. name .. " +" .. unregisteredPoints .. " (集合分-未报名)")
        end
        
        local tableid = WebDKP_GetTableid()
        WebDKP_AddDKP(unregisteredPoints, "集合分-未报名", "false", playerTable, tableid)
        WebDKP_Print("已为 " .. table.getn(unregisteredInGroup) .. " 名未报名玩家添加集合分-未报名，分数：" .. unregisteredPoints)
    end
    
    -- 延迟处理缺席分 - 先处理所有其他分数，最后再处理缺席分
    -- 这样可以确保替补数据已经同步完成
    
    -- 检查是否勾选了打卡模式
    local useCheckIn = false
    if WebDKP_SubAwardData then
        useCheckIn = WebDKP_SubAwardData.useCheckIn or false
    end
    
    -- 如果没有勾选打卡模式，直接根据搜索替补队员结果给替补队员加分
    if not useCheckIn then
        -- 检查是否有替补队员搜索结果
        if WebDKP_PendingSubMembers and next(WebDKP_PendingSubMembers) then
            -- 处理所有替补队员，包括未报名的
            local processedSubMembers = {}
            for captainName, playerList in pairs(WebDKP_PendingSubMembers) do
                for playerName, _ in pairs(playerList) do
                    local isRegistered = false
                    for _, regName in ipairs(WebDKP_CheckInData.registeredPlayers) do
                        if regName and playerName and string.lower(playerName) == string.lower(regName) then
                            isRegistered = true
                            break
                        end
                    end
                    
                    -- 保持原始的数据结构，所有替补队员都处理，不再跳过
                    if not processedSubMembers[captainName] then
                        processedSubMembers[captainName] = {}
                    end
                    processedSubMembers[captainName][playerName] = isRegistered  -- 存储报名状态
                    
                    if not isRegistered then
                        -- WebDKP_Print("替补队员 " .. playerName .. " 不在报名名单中，将按未报名标准处理")
                    end
                end
            end
            
            -- 处理所有替补队员
            local hasMembers = false
            for _, _ in pairs(processedSubMembers) do
                hasMembers = true
                break
            end
            
            if hasMembers then
                -- 临时替换WebDKP_PendingSubMembers为处理后的列表
                local originalPendingMembers = WebDKP_PendingSubMembers
                WebDKP_PendingSubMembers = processedSubMembers
                
                -- 获取UI中的替补设置
                local captain = WebDKP_SubAwardData.captain or ""
                local reason = WebDKP_SubAwardData.reason or ""
                local points = WebDKP_SubAwardData.points or 0
                
                -- 如果UI中没有设置，使用默认值
                if captain == "" then
                    captain = "替补队长"  -- 使用默认队长名
                end
                if reason == "" then
                    reason = "集合-替补"  -- 使用默认原因
                end
                if points == 0 then
                    points = rallyPoints  -- 使用集合分作为替补分数
                end
                
                -- 重要：检查是否有已报名的玩家作为替补
                -- 这些玩家应该获得正常集合分，而不是替补分
                local hasRegisteredSubs = false
                for captainName, playerList in pairs(processedSubMembers) do
                    for playerName, isRegistered in pairs(playerList) do
                        if isRegistered then
                            hasRegisteredSubs = true
                            -- WebDKP_Print("注意：报名玩家 " .. playerName .. " 作为替补，将按正常出勤处理")
                        end
                    end
                end
                
           
                WebDKP_SubAwardData.captain = captain
                WebDKP_SubAwardData.reason = reason
                WebDKP_SubAwardData.points = points
                
                -- 重要：同步替补数据到WebDKP_SubData.subs，以便考勤报告能正确显示
                if not WebDKP_SubData then
                    WebDKP_SubData = {
                        active = false,  -- 非打卡模式，标记为不活跃
                        subs = {},
                        points = points,
                        reason = reason
                    }
                end
                
                -- 将处理后的替补队员信息同步到WebDKP_SubData.subs
                for captainName, playerList in pairs(processedSubMembers) do
                    for playerName, isRegistered in pairs(playerList) do
                        -- 获取玩家职业
                        local playerClass = WebDKP_GetPlayerClass(playerName) or "Unknown"
                        
                        -- 存储到WebDKP_SubData.subs中
                        WebDKP_SubData.subs[playerName] = {
                            class = playerClass,
                            isRegistered = isRegistered,
                            location = "搜索导入"  -- 标记为搜索导入的替补
                        }
                        
                        -- 重要：同时将替补玩家添加到WebDKP_CheckInData.standbyPlayers数组中
                        -- 这样考勤报告才能正确显示替补名单
                        local alreadyInStandby = false
                        for _, existingName in ipairs(WebDKP_CheckInData.standbyPlayers) do
                            if existingName and playerName and string.lower(existingName) == string.lower(playerName) then
                                alreadyInStandby = true
                                break
                            end
                        end
                        
                        if not alreadyInStandby then
                            table.insert(WebDKP_CheckInData.standbyPlayers, playerName)
                            -- WebDKP_Print("调试：已将替补玩家 " .. playerName .. " 添加到WebDKP_CheckInData.standbyPlayers")
                        end
                        
                        -- WebDKP_Print("调试：已将替补玩家 " .. playerName .. " 同步到WebDKP_SubData.subs，isRegistered=" .. tostring(isRegistered))
                    end
                end
                
                -- 自定义逻辑处理替补加分
                -- 1. 确保WebDKP_SubAwardData存在
                if not WebDKP_SubAwardData then
                    WebDKP_SubAwardData = {}
                end
                
                -- 2. 标记为报名打卡按钮触发
                WebDKP_SubAwardData.isCheckInButton = true
                
                -- 3. 获取当前替补队长名称（从UI获取或使用默认值）
                local captain = "系统"
                if WebDKP_AwardDKP_FrameSubLeader then
                    captain = WebDKP_AwardDKP_FrameSubLeader:GetText() or captain
                end
                
                -- 4. 获取分数（从UI获取或使用默认值）
                local points = 0
                if WebDKP_AwardDKP_FrameSubPoints then
                    points = tonumber(WebDKP_AwardDKP_FrameSubPoints:GetText()) or 0
                end
                
                -- 5. 确保WebDKP_PendingSubMembers已初始化
                if not WebDKP_PendingSubMembers then
                    WebDKP_PendingSubMembers = {}
                end
                
                -- 6. 查找匹配的队长键（不区分大小写）
                local targetCaptainKey = nil
                local lowerCaptain = string.lower(captain)
                
                -- 直接匹配原始队长名
                if WebDKP_PendingSubMembers[captain] then
                    targetCaptainKey = captain
                end
                
                -- 如果直接匹配失败，尝试小写匹配
                if not targetCaptainKey and WebDKP_PendingSubMembers[lowerCaptain] then
                    targetCaptainKey = lowerCaptain
                end
                
                -- 如果前两种都失败，遍历所有键进行不区分大小写匹配
                if not targetCaptainKey then
                    for key, _ in pairs(WebDKP_PendingSubMembers) do
                        if string.lower(key) == lowerCaptain then
                            targetCaptainKey = key
                            break
                        end
                    end
                end
                
                -- 7. 如果找到匹配的队长，处理替补队员加分
                if targetCaptainKey then
                    local registeredPlayers = {}
                    local unregisteredPlayers = {}
                    local registeredCount = 0
                    local unregisteredCount = 0
                    
                    -- 分别处理已报名和未报名的替补队员
                    for memberName, data in pairs(WebDKP_PendingSubMembers[targetCaptainKey]) do
                        -- 确保isRegistered是布尔值
                        local isRegistered = type(data) == "boolean" and data or false
                        local playerClass = WebDKP_GetPlayerClass(memberName) or "战士"
                        
                        if isRegistered then
                            -- 已报名的替补队员
                            registeredCount = registeredCount + 1
                            registeredPlayers[registeredCount] = {
                                name = memberName,
                                class = playerClass
                            }
                        else
                            -- 未报名的替补队员
                            unregisteredCount = unregisteredCount + 1
                            unregisteredPlayers[unregisteredCount] = {
                                name = memberName,
                                class = playerClass
                            }
                        end
                    end
                    
                    -- 8. 为已报名的替补队员加分
                    if registeredCount > 0 then
                        local registeredReason = "集合-替补"
                        -- 使用WebDKP_CheckInData中的集合分（rallyPoints），默认值为2
                        local registeredPoints = WebDKP_CheckInData.rallyPoints or 2
                        WebDKP_AddDKP(registeredPoints, registeredReason, "false", registeredPlayers, WebDKP_BossAwardData.tableid)
                        WebDKP_Print("已成功为 " .. registeredCount .. " 名已报名替补队员加 " .. registeredPoints .. " 分 (" .. registeredReason .. ")")
                    end
                    
                    -- 9. 为未报名的替补队员加分
                    if unregisteredCount > 0 then
                        local unregisteredReason = "集合-替补-未报名"
                        local unregisteredPoints = WebDKP_CheckInData.unregisteredPoints or points
                        WebDKP_AddDKP(unregisteredPoints, unregisteredReason, "false", unregisteredPlayers, WebDKP_BossAwardData.tableid)
                        WebDKP_Print("已成功为 " .. unregisteredCount .. " 名未报名替补队员加 " .. unregisteredPoints .. " 分 (" .. unregisteredReason .. ")")
                    end
                    
                    -- 10. 显示总计信息
                    local totalCount = registeredCount + unregisteredCount
                    if totalCount > 0 then
                        WebDKP_Print("总计处理替补队员: " .. totalCount .. " 名")
                    end
                end
                
                -- 11. 额外处理：直接从WebDKP_SubData.subs中获取所有替补队员并确保他们都获得DKP
                if WebDKP_SubData and WebDKP_SubData.subs then
                    local subRegisteredPlayers = {}
                    local subUnregisteredPlayers = {}
                    local subRegisteredCount = 0
                    local subUnregisteredCount = 0
                    
                    -- 遍历WebDKP_SubData.subs中的所有替补队员
                    for playerName, playerData in pairs(WebDKP_SubData.subs) do
                        local isRegistered = playerData.isRegistered or false
                        local playerClass = playerData.class or WebDKP_GetPlayerClass(playerName) or "战士"
                        
                        -- 重要：确保所有替补玩家都被添加到WebDKP_CheckInData.standbyPlayers数组中
                        -- 这样考勤报告才能正确显示替补名单
                        local alreadyInStandby = false
                        for _, existingName in ipairs(WebDKP_CheckInData.standbyPlayers) do
                            if existingName and playerName and string.lower(existingName) == string.lower(playerName) then
                                alreadyInStandby = true
                                break
                            end
                        end
                        
                        if not alreadyInStandby then
                            table.insert(WebDKP_CheckInData.standbyPlayers, playerName)
                        end
                        
                        if isRegistered then
                            -- 已报名的替补队员
                            subRegisteredCount = subRegisteredCount + 1
                            subRegisteredPlayers[subRegisteredCount] = {
                                name = playerName,
                                class = playerClass
                            }
                        else
                            -- 未报名的替补队员
                            subUnregisteredCount = subUnregisteredCount + 1
                            subUnregisteredPlayers[subUnregisteredCount] = {
                                name = playerName,
                                class = playerClass
                            }
                        end
                    end
                    
                    -- 为WebDKP_SubData.subs中的已报名替补队员加分
                    if subRegisteredCount > 0 then
                        local registeredReason = "集合分"
                        local registeredPoints = WebDKP_CheckInData.rallyPoints or 2
                        WebDKP_AddDKP(registeredPoints, registeredReason, "false", subRegisteredPlayers, WebDKP_BossAwardData.tableid)
                        WebDKP_Print("额外处理：已为 " .. subRegisteredCount .. " 名替补队员添加集合分，分数：" .. registeredPoints)
                    end
                    
                    -- 为WebDKP_SubData.subs中的未报名替补队员加分
                    if subUnregisteredCount > 0 then
                        local unregisteredReason = "集合分-未报名"
                        local unregisteredPoints = WebDKP_CheckInData.unregisteredPoints or points
                        WebDKP_AddDKP(unregisteredPoints, unregisteredReason, "false", subUnregisteredPlayers, WebDKP_BossAwardData.tableid)
                        WebDKP_Print("额外处理：已为 " .. subUnregisteredCount .. " 名替补队员添加集合分-未报名，分数：" .. unregisteredPoints)
                    end
                end
                
                -- WebDKP_Print("已根据替补队员搜索结果直接加分，未开启私密加分模式")
                
                -- 恢复原始的WebDKP_PendingSubMembers
                WebDKP_PendingSubMembers = originalPendingMembers
            end
        end
        
        -- 非打卡模式：替补处理完成后，处理缺席分数
        -- 传递缺席分数和团队成员列表
        WebDKP_CheckIn_ProcessAbsentPlayers(WebDKP_CheckInData.absentPoints, groupMembers)
        
    else
        -- 如果勾选了打卡模式，才设置替补命令和启动活动
        -- 确保使用正确的时间和分数参数，避免传递未定义的变量
        local checkInStandbyTime = standbyTime or WebDKP_CheckInData.standbyTime or 5
        local checkInRallyPoints = WebDKP_SubAwardData.points or WebDKP_CheckInData.rallyPoints or 5
        WebDKP_CheckIn_SetStandbyCommand(checkInStandbyTime, checkInRallyPoints, true) -- 传递true表示是打卡模式
        
        -- 打卡模式：将在WebDKP_ProcessSubstitutes函数中处理缺席分数
    end
    
    -- 更新表格显示
    WebDKP_UpdateTableToShow()
    WebDKP_UpdateTable()
end

-- 设置替补命令和计时器
WebDKP_CheckIn_SetStandbyCommand = function(standbyTime, rallyPoints, isCheckInMode, isCheckInButton)
    if not standbyTime or not rallyPoints then
        standbyTime = WebDKP_CheckInData.standbyTime or 5
        -- 优先使用WebDKP_SubAwardData中的分数，而不是击杀奖励的分数
        if WebDKP_SubAwardData and WebDKP_SubAwardData.points then
            rallyPoints = WebDKP_SubAwardData.points
        elseif WebDKP_BossAwardData and WebDKP_BossAwardData.points then
            rallyPoints = WebDKP_BossAwardData.points
        else
            rallyPoints = WebDKP_CheckInData.rallyPoints or 2
        end
    end
    
    -- 确保isCheckInMode参数被正确处理
    isCheckInMode = isCheckInMode or false
    
    -- 保存当前的聊天命令处理函数
    WebDKP_CheckIn_OldChatCommand = SlashCmdList["WEBDKP"]
    
    -- 覆盖聊天命令处理函数，添加替补功能
    SlashCmdList["WEBDKP"] = function(msg)
        -- 将消息转换为小写以进行不区分大小写的比较
        local lowerMsg = string.lower(msg)
        
        -- 检查是否是替补命令
        if lowerMsg == "tb" or lowerMsg == "替补" then
            WebDKP_CheckIn_ProcessStandbyPlayer(UnitName("player"))
        else
            -- 如果不是替补命令，调用原始的命令处理函数
            if WebDKP_CheckIn_OldChatCommand then
                WebDKP_CheckIn_OldChatCommand(msg)
            end
        end
    end
    
    -- 初始化替补活动数据，使用与WebDKP.lua相同的结构
    -- 优先使用WebDKP_SubAwardData中的reason，如果没有则尝试构建boss名称-替补格式
    local subReasonValue = "替补"
    -- 优先使用WebDKP_SubAwardData中的reason
    if WebDKP_SubAwardData and WebDKP_SubAwardData.reason and WebDKP_SubAwardData.reason ~= "" then
        subReasonValue = WebDKP_SubAwardData.reason
    -- 如果没有，尝试从WebDKP_BossAwardData获取boss名称构建项目名称
    elseif WebDKP_BossAwardData and WebDKP_BossAwardData.bossName and WebDKP_BossAwardData.bossName ~= "" then
        subReasonValue = WebDKP_BossAwardData.bossName .. "-替补"
    end
    
    -- 清空之前的替补玩家数据，避免累计
    if WebDKP_CheckInData.standbyPlayers then
        WebDKP_CheckInData.standbyPlayers = {}
    end
    
    WebDKP_SubData = {
        active = true,
        points = rallyPoints,
        reason = subReasonValue,
        subReason = subReasonValue,
        tableid = WebDKP_GetTableid(),
        startTime = GetTime(),
        endTime = GetTime() + (standbyTime * 60),
        subs = {},
        raidMembers = {},
        timerFrame = nil,
        registeredPlayers = WebDKP_CheckInData.registeredPlayers,  -- 添加报名玩家列表
        isCheckInMode = isCheckInMode or false,  -- 标记是否是打卡模式
        isCheckInButton = isCheckInButton or false  -- 标记是否是报名打卡按钮触发的
    }
    
    -- 保存当前团队成员列表（使用小写名称以确保大小写不敏感的比较）
    WebDKP_CurrentRaidMembers = {}
    if GetNumRaidMembers() > 0 then
        for i = 1, GetNumRaidMembers() do
            local name = UnitName("raid" .. i)
            if name then
                WebDKP_CurrentRaidMembers[string.lower(name)] = true
            end
        end
    elseif GetNumPartyMembers() > 0 then
        for i = 1, GetNumPartyMembers() do
            local name = UnitName("party" .. i)
            if name then
                WebDKP_CurrentRaidMembers[string.lower(name)] = true
            end
        end
        local playerName = UnitName("player")
        if playerName then
            WebDKP_CurrentRaidMembers[string.lower(playerName)] = true
        end
    else
        local playerName = UnitName("player")
        if playerName then
            WebDKP_CurrentRaidMembers[string.lower(playerName)] = true
        end
    end
    
    -- 保存团队成员列表到WebDKP_SubData
    WebDKP_SubData.raidMembers = WebDKP_CurrentRaidMembers
    
    -- 播报替补打卡提醒，使用standbyTime作为时间信息
    local timeInfo = standbyTime .. "分钟"
    local subMessage = "手动替补加分活动开始！替补成员在" .. timeInfo .. "内私密我 TB 或 替补 记录打卡，过期不候！"
    
    -- 静默模式下不发送团队播报，仅本地显示
    local isSilentMode = WebDKP_Options and WebDKP_Options["SilentMode"]
    if not isSilentMode then
        SendChatMessage(subMessage, "GUILD", nil, nil)
    else
        WebDKP_Print("[静默] " .. subMessage)
    end
    WebDKP_Print("替补加分活动已开始，将在" .. standbyTime .. "分钟后结束。")
    
    -- 设置计时器，计时结束后处理替补加分
    WebDKP_SubData.timerFrame = CreateFrame("Frame")
    WebDKP_SubData.timerFrame:SetScript("OnUpdate", function()
        if GetTime() >= WebDKP_SubData.endTime then
            local frame = WebDKP_SubData.timerFrame
            frame:SetScript("OnUpdate", nil)
            WebDKP_ProcessSubstitutes()
            
            -- 恢复原始的聊天命令处理函数
            if WebDKP_CheckIn_OldChatCommand then
                SlashCmdList["WEBDKP"] = WebDKP_CheckIn_OldChatCommand
                WebDKP_CheckIn_OldChatCommand = nil
            end
        end
    end)
end

-- 处理替补玩家
WebDKP_CheckIn_ProcessStandbyPlayer = function(playerName)
    if not playerName or playerName == "" then
        WebDKP_Print("错误：无法获取玩家名称")
        return
    end
    
    -- 检查是否有活跃的替补活动
    if not WebDKP_SubData or not WebDKP_SubData.active then
        WebDKP_Print("错误：当前没有活跃的替补活动")
        return
    end
    
    -- 检查玩家是否在团队/队伍中，如果在则不添加到替补（使用小写名称进行比较）
    if WebDKP_SubData and WebDKP_SubData.raidMembers and WebDKP_SubData.raidMembers[string.lower(playerName)] then
        WebDKP_Print(playerName .. " 已经在团队中，无需添加为替补")
        return
    end
    
    -- 检查是否已经在WebDKP_SubData.subs中，如果不在则添加
    if WebDKP_SubData and WebDKP_SubData.subs and WebDKP_SubData.subs[playerName] then
        WebDKP_Print(playerName .. " 已经在替补名单中")
        return
    end
    
    -- 检查玩家是否在报名列表中
    local isRegistered = false
    for _, regName in ipairs(WebDKP_CheckInData.registeredPlayers) do
        if regName and playerName and string.lower(playerName) == string.lower(regName) then
            isRegistered = true
            break
        end
    end
    
    -- 获取玩家职业
    local playerClass = WebDKP_GetPlayerClass(playerName)
    if not playerClass then
        -- 如果无法从DKP表获取职业，尝试从队伍/团队中获取
        if GetNumRaidMembers() > 0 then
            for i = 1, GetNumRaidMembers() do
                local name = UnitName("raid" .. i)
                if name and string.lower(name) == string.lower(playerName) then
                    playerClass = UnitClass("raid" .. i)
                    break
                end
            end
        elseif GetNumPartyMembers() > 0 then
            for i = 1, GetNumPartyMembers() do
                local name = UnitName("party" .. i)
                if name and string.lower(name) == string.lower(playerName) then
                    playerClass = UnitClass("party" .. i)
                    break
                end
            end
        end
        
        -- 如果还是无法获取职业，设置为默认值
        if not playerClass then
            playerClass = "Unknown"
        end
    end
    
    -- 获取玩家位置
    local location = "未知"
    SendWho(playerName)
    
    -- 短暂延迟以获取位置信息
    local tempFrame = CreateFrame("Frame")
    tempFrame.playerName = playerName
    tempFrame:SetScript("OnUpdate", function()
        local frame = this
        local elapsed = tonumber(arg[1]) or 0
        frame.timer = (frame.timer or 0) + elapsed
        if frame.timer > 1.5 then
            frame:SetScript("OnUpdate", nil)
            
            local whoPlayerName, _, _, _, _, whoLocation = GetWhoInfo(1)
            if whoPlayerName and whoLocation then
                local baseName = string.match(whoPlayerName, "^([^%-]+)") or whoPlayerName
                local baseOriginalName = string.match(frame.playerName, "^([^%-]+)") or frame.playerName
                
                if baseName and baseOriginalName and string.lower(baseName) == string.lower(baseOriginalName) then
                    location = whoLocation
                end
            end
            
            -- 使用已设置的项目名称（boss名称-替补）
            local currentReason = WebDKP_SubData.subReason or WebDKP_SubData.reason or "替补"
            WebDKP_Print("调试：添加替补玩家 " .. playerName .. "，isRegistered=" .. tostring(isRegistered) .. "，原因=" .. currentReason)
            
            -- 确保使用正确的分数，从WebDKP_SubData中获取
            if not WebDKP_SubData.points or WebDKP_SubData.points <= 0 then
                WebDKP_SubData.points = 5 -- 默认分数值
            end
            
            -- 添加到WebDKP_SubData.subs中，与现有替补系统集成
            WebDKP_SubData.subs[playerName] = {
                class = playerClass,
                location = location,
                locationNeedsConfirmation = false,
                timestamp = time(),
                isRegistered = isRegistered  -- 添加标记，记录是否已报名
            }
            
            -- 添加到报名打卡数据的替补列表
            table.insert(WebDKP_CheckInData.standbyPlayers, playerName)
            
            WebDKP_Print("已收录替补玩家 " .. playerName .. "，职业: " .. playerClass .. "，位置: " .. location .. "，状态: " .. (isRegistered and "已报名" or "未报名"))
            
            -- 静默模式下不发送私聊播报，仅本地记录
            local isSilentMode = WebDKP_Options and WebDKP_Options["SilentMode"]
            if not isSilentMode then
                SendChatMessage("已收录为本次替补，将获得" .. WebDKP_SubData.points .. " DKP分。", "WHISPER", nil, playerName)
            else
                WebDKP_Print("[静默] 已收录 " .. playerName .. " 为替补，将获得" .. WebDKP_SubData.points .. " DKP分")
            end
        end
    end)
end

-- 获取玩家考勤状态
WebDKP_GetPlayerAttendanceStatus = function(playerName)
    -- 检查是否在团队中
    local inGroup = false
    local raidMembers = GetNumRaidMembers()
    local partyMembers = GetNumPartyMembers()
    
    if raidMembers > 0 then
        for i = 1, raidMembers do
            local name = GetRaidRosterInfo(i)
            if name and playerName and string.lower(name) == string.lower(playerName) then
                inGroup = true
                break
            end
        end
    elseif partyMembers > 0 then
        local playerNameCheck = UnitName("player")
        if playerName and playerNameCheck and string.lower(playerNameCheck) == string.lower(playerName) then
            inGroup = true
        else
            for i = 1, partyMembers do
                local name = UnitName("party" .. i)
                if name and playerName and string.lower(name) == string.lower(playerName) then
                    inGroup = true
                    break
                end
            end
        end
    end
    
    -- 检查是否在报名列表中
    local isRegistered = false
    for _, regName in ipairs(WebDKP_CheckInData.registeredPlayers) do
        if regName and playerName and string.lower(playerName) == string.lower(regName) then
            isRegistered = true
            break
        end
    end
    
    -- 检查是否在替补列表中
    local isStandby = false
    local standbyReason = ""
    if WebDKP_SubData and WebDKP_SubData.subs then
        for name, data in pairs(WebDKP_SubData.subs) do
        if name and playerName and string.lower(name) == string.lower(playerName) then
            isStandby = true
            standbyReason = data.isRegistered and "替补" or "替补-未报名"
            -- 调试输出
            -- WebDKP_Print("调试：玩家 " .. playerName .. " 在替补列表中，isRegistered=" .. tostring(data.isRegistered) .. "，状态=" .. standbyReason)
            break
        end
    end
    end
    
    -- 确定考勤状态
    -- 重要：报名名单中的玩家即使出现在替补队，也应视为正常出勤
    if isRegistered and inGroup then
        return "集合分"
    elseif not isRegistered and inGroup then
        return "集合分-未报名"
    elseif isRegistered and not inGroup and isStandby then
        -- 报名但不在团队中，但在替补队 - 显示为集合-替补状态
        return "集合-替补"
    elseif isRegistered and not inGroup and not isStandby then
        return "缺席"
    elseif not isRegistered and isStandby then
        -- 未报名但在替补队
        return "集合-替补-未报名"
    elseif isStandby then
        -- 其他替补情况
        return standbyReason
    end
    
    return ""
end

-- 考勤报告功能
WebDKP_ReportAttendance = function()
    -- 收集所有玩家
    local allPlayers = {}
    local playerStatus = {}
    local statusType = {}
    
    -- 添加报名玩家
    for _, name in ipairs(WebDKP_CheckInData.registeredPlayers) do
        if not allPlayers[name] then
            allPlayers[name] = true
        end
    end
    
    -- 添加团队中的玩家
    local raidMembers = GetNumRaidMembers()
    local partyMembers = GetNumPartyMembers()
    
    if raidMembers > 0 then
        for i = 1, raidMembers do
            local name = GetRaidRosterInfo(i)
            if name then
                name = string.gsub(name, "-.*$", "") -- 去除服务器名
                if not allPlayers[name] then
                    allPlayers[name] = true
                end
            end
        end
    elseif partyMembers > 0 then
        local playerName = UnitName("player")
        if playerName then
            playerName = string.gsub(playerName, "-.*$", "")
            if not allPlayers[playerName] then
                allPlayers[playerName] = true
            end
        end
        for i = 1, partyMembers do
            local name = UnitName("party" .. i)
            if name then
                name = string.gsub(name, "-.*$", "")
                if not allPlayers[name] then
                    allPlayers[name] = true
                end
            end
        end
    end
    
    -- 添加替补玩家
    -- WebDKP_Print("调试：WebDKP_CheckInData.standbyPlayers 中的替补玩家有：")
    for _, name in ipairs(WebDKP_CheckInData.standbyPlayers) do
        -- WebDKP_Print("  - " .. name)
        if not allPlayers[name] then
            allPlayers[name] = true
        end
    end
    
    -- 调试：显示WebDKP_SubData.subs中的替补玩家
    if WebDKP_SubData and WebDKP_SubData.subs then
        -- WebDKP_Print("调试：WebDKP_SubData.subs 中的替补玩家有：")
        for name, data in pairs(WebDKP_SubData.subs) do
            -- WebDKP_Print("  - " .. name .. " (isRegistered: " .. tostring(data.isRegistered) .. ")")
            -- 确保这些玩家也被包含在allPlayers中
            if not allPlayers[name] then
                allPlayers[name] = true
                -- WebDKP_Print("调试：从WebDKP_SubData.subs添加玩家 " .. name .. " 到allPlayers")
            end
        end
    end
    
    -- 获取每个玩家的考勤状态
    for name, _ in pairs(allPlayers) do
        local status = WebDKP_GetPlayerAttendanceStatus(name)
        playerStatus[name] = status
        
        -- 记录状态类型
        if status and status ~= "" then
            if not statusType[status] then
                statusType[status] = {}
            end
            table.insert(statusType[status], name)
        end
    end
    
    -- 调试输出：显示所有收集到的状态类型
    -- WebDKP_Print("调试：收集到的状态类型有：")
    for status, players in pairs(statusType) do
        -- WebDKP_Print("  - " .. status .. ": " .. table.getn(players) .. "人")
        -- 如果是缺席状态，显示具体玩家名单
        if status == "缺席" then
            -- WebDKP_Print("调试：缺席玩家详细名单：")
            for _, name in ipairs(players) do
                local class = WebDKP_GetPlayerClass(name) or "Unknown"
                -- WebDKP_Print("  - " .. name .. " [" .. class .. "]")
            end
        end
    end
    
    -- 按状态类型排序的顺序（与考勤报告保持一致）
    local statusOrder = {
        "集合分",
        "集合-替补",
        "集合分-未报名",
        "集合-替补-未报名",
        "缺席"
    }
    
    -- 生成报告内容
    local reportContent = "=== 考勤报告 ===\n"
    reportContent = reportContent .. "时间: " .. date("%Y-%m-%d %H:%M:%S") .. "\n\n"
    
    -- 统计每个状态的人数
    local statusCount = {}
    for status, players in pairs(statusType) do
        statusCount[status] = table.getn(players)
    end
    
    -- 按状态类型输出统计
    for _, status in ipairs(statusOrder) do
        if statusCount[status] and statusCount[status] > 0 then
            reportContent = reportContent .. status .. ": " .. statusCount[status] .. "人\n"
            
            -- 对玩家名称排序
            table.sort(statusType[status])
            
            -- 输出玩家列表
            for _, name in ipairs(statusType[status]) do
                local class = WebDKP_GetPlayerClass(name)
                local classText = class and (" [" .. class .. "]") or ""
                reportContent = reportContent .. "  - " .. name .. classText .. "\n"
            end
            reportContent = reportContent .. "\n"
        end
    end
    
    -- 输出总人数统计
    local totalPlayers = 0
    for _, count in pairs(statusCount) do
        totalPlayers = totalPlayers + count
    end
    reportContent = reportContent .. "总人数: " .. totalPlayers .. "人\n"
    
    -- 显示报告
    WebDKP_Print(reportContent)
end


-- 导出考勤功能
WebDKP_ExportAttendance = function()
    -- 收集所有玩家
    local allPlayers = {}
    local playerStatus = {}
    local statusType = {}
    
    -- 添加报名玩家
    for _, name in ipairs(WebDKP_CheckInData.registeredPlayers) do
        if not allPlayers[name] then
            allPlayers[name] = true
        end
    end
    
    -- 添加团队中的玩家
    local raidMembers = GetNumRaidMembers()
    local partyMembers = GetNumPartyMembers()
    
    if raidMembers > 0 then
        for i = 1, raidMembers do
            local name = GetRaidRosterInfo(i)
            if name then
                name = string.gsub(name, "-.*$", "") -- 去除服务器名
                if not allPlayers[name] then
                    allPlayers[name] = true
                end
            end
        end
    elseif partyMembers > 0 then
        local playerName = UnitName("player")
        if playerName then
            playerName = string.gsub(playerName, "-.*$", "")
            if not allPlayers[playerName] then
                allPlayers[playerName] = true
            end
        end
        for i = 1, partyMembers do
            local name = UnitName("party" .. i)
            if name then
                name = string.gsub(name, "-.*$", "")
                if not allPlayers[name] then
                    allPlayers[name] = true
                end
            end
        end
    end
    
    -- 添加替补玩家
    for _, name in ipairs(WebDKP_CheckInData.standbyPlayers) do
        if not allPlayers[name] then
            allPlayers[name] = true
        end
    end
    
    -- 获取每个玩家的考勤状态
    for name, _ in pairs(allPlayers) do
        local status = WebDKP_GetPlayerAttendanceStatus(name)
        playerStatus[name] = status
        
        -- 记录状态类型
        if status and status ~= "" then
            if not statusType[status] then
                statusType[status] = {}
            end
            table.insert(statusType[status], name)
        end
    end
    
    -- 按状态类型排序的顺序
    local statusOrder = {
        "集合分",
        "集合-替补",
        "集合分-未报名",
        "集合-替补-未报名",
        "缺席"
    }
    
    -- 生成导出内容
    local exportContent = "玩家名称,项目名称\n"
    
    -- 按状态类型输出玩家
    for _, status in ipairs(statusOrder) do
        if statusType[status] and table.getn(statusType[status]) > 0 then
            -- 对玩家名称排序
            table.sort(statusType[status])
            
            for _, name in ipairs(statusType[status]) do
                exportContent = exportContent .. name .. "," .. status .. "\n"
            end
        end
    end
    
    -- 保存到文件
    local fileName = "考勤-" .. date("%Y-%m-%d")
    if ExportFile then
        ExportFile(fileName, exportContent)
        WebDKP_Print("考勤已导出到文件: " .. fileName)
    else
        WebDKP_Print("警告：ExportFile函数不可用，无法导出考勤")
    end
end

-- 处理缺席玩家（在所有其他分数处理完成后调用）
WebDKP_CheckIn_ProcessAbsentPlayers = function(absentPoints, groupMembers)
    if not absentPoints then
        absentPoints = WebDKP_CheckInData.absentPoints or 0
    end
    
    if not groupMembers then
        -- 如果没有提供groupMembers，重新收集团队成员
        groupMembers = {}
        if GetNumRaidMembers() > 0 then
            for i = 1, GetNumRaidMembers() do
                local name = GetRaidRosterInfo(i)
                if name then
                    name = string.gsub(name, "-.*$", "") -- 去除服务器名
                    table.insert(groupMembers, name)
                end
            end
        elseif GetNumPartyMembers() > 0 then
            local playerName = UnitName("player")
            if playerName then
                playerName = string.gsub(playerName, "-.*$", "") -- 去除服务器名
                table.insert(groupMembers, playerName)
            end
            for i = 1, GetNumPartyMembers() do
                local name = UnitName("party" .. i)
                if name then
                    name = string.gsub(name, "-.*$", "") -- 去除服务器名
                    table.insert(groupMembers, name)
                end
            end
        end
    end
    
    -- 为缺席的已报名玩家添加缺席分
    local absentPlayers = {}
    for _, regName in ipairs(WebDKP_CheckInData.registeredPlayers) do
        local isInGroup = false
        for _, groupName in ipairs(groupMembers) do
            if regName and groupName and string.lower(regName) == string.lower(groupName) then
                isInGroup = true
                break
            end
        end
        
        -- 检查是否已经是替补玩家（包括手动添加的和搜索导入的）
        local isStandby = false
        for _, standbyName in ipairs(WebDKP_CheckInData.standbyPlayers) do
            if regName and standbyName and string.lower(regName) == string.lower(standbyName) then
                isStandby = true
                break
            end
        end
        
        -- 还要检查是否在WebDKP_SubData.subs中（搜索导入的替补）
        if not isStandby and WebDKP_SubData and WebDKP_SubData.subs then
            for subName, _ in pairs(WebDKP_SubData.subs) do
                if regName and subName and string.lower(regName) == string.lower(subName) then
                    isStandby = true
                    break
                end
            end
        end
        
        if not isInGroup and not isStandby then
            table.insert(absentPlayers, {
                name = regName,
                class = WebDKP_GetPlayerClass(regName) or "Unknown"
            })
        end
    end
    
    if table.getn(absentPlayers) > 0 then
        -- 调试：显示被添加缺席分的玩家名单
        -- WebDKP_Print("调试：以下玩家被判定为缺席并添加缺席分：")
        for _, player in ipairs(absentPlayers) do
            WebDKP_Print("  - " .. player.name .. " [" .. player.class .. "]")
        end
        
        local tableid = WebDKP_GetTableid()
        WebDKP_AddDKP(absentPoints, "缺席", "false", absentPlayers, tableid)
        WebDKP_Print("已为 " .. table.getn(absentPlayers) .. " 名缺席玩家添加缺席分")
    else
        WebDKP_Print("调试：没有玩家被判定为缺席")
    end
end

-- 获取玩家职业（辅助函数）
WebDKP_GetPlayerClass = function(playerName)
    if not playerName or not WebDKP_DkpTable then
        return nil
    end
    
    if WebDKP_DkpTable[playerName] and WebDKP_DkpTable[playerName]["class"] then
        return WebDKP_DkpTable[playerName]["class"]
    end
    
    return nil
end

-- 添加斜杠命令来测试报名打卡窗口
SLASH_WEBDKP_CHECKIN1 = "/webdkp_checkin"
SlashCmdList["WEBDKP_CHECKIN"] = function(msg)
    if WebDKP_CheckInFrame then
        if WebDKP_CheckInFrame:IsVisible() then
            WebDKP_CheckInFrame:Hide()
        else
            -- 在显示框架前重新加载设置，确保显示最新的保存值
            WebDKP_CheckIn_LoadSettings()
            WebDKP_CheckInFrame:Show()
        end
    else
        WebDKP_Print("错误：报名打卡框架未找到")
    end
end

-- 添加斜杠命令来调试替补玩家信息
SLASH_WEBDKP_DEBUG_STANDBY1 = "/webdkp_debug_standby"
SlashCmdList["WEBDKP_DEBUG_STANDBY"] = function(msg)
    WebDKP_CheckIn_DebugStandbyPlayers()
end

-- 添加斜杠命令来测试考勤报告
SLASH_WEBDKP_REPORT_ATTENDANCE1 = "/webdkp_report"
SlashCmdList["WEBDKP_REPORT_ATTENDANCE"] = function(msg)
    WebDKP_ReportAttendance()
end

-- 初始化报名打卡数据将在WebDKP_OnEnable中调用

-- 调试函数：显示替补玩家详细信息
WebDKP_CheckIn_DebugStandbyPlayers = function()
    WebDKP_Print("=== 替补玩家调试信息 ===")
    
    if WebDKP_SubData and WebDKP_SubData.subs then
        local totalStandby = 0
        local registeredStandby = 0
        local unregisteredStandby = 0
        
        WebDKP_Print("WebDKP_SubData.subs 中的替补玩家:")
        for name, data in pairs(WebDKP_SubData.subs) do
            totalStandby = totalStandby + 1
            local class = data.class or WebDKP_GetPlayerClass(name) or "Unknown"
            if data.isRegistered then
                registeredStandby = registeredStandby + 1
                WebDKP_Print("已报名替补: " .. name .. " [" .. class .. "] - 状态: 集合-替补")
            else
                unregisteredStandby = unregisteredStandby + 1
                WebDKP_Print("未报名替补: " .. name .. " [" .. class .. "] - 状态: 集合-替补-未报名")
            end
        end
        
        WebDKP_Print("替补总计: " .. totalStandby .. " (已报名: " .. registeredStandby .. ", 未报名: " .. unregisteredStandby .. ")")
    else
        WebDKP_Print("WebDKP_SubData.subs 不存在")
    end
    
    if WebDKP_CheckInData and WebDKP_CheckInData.standbyPlayers then
        WebDKP_Print("WebDKP_CheckInData.standbyPlayers数量: " .. table.getn(WebDKP_CheckInData.standbyPlayers))
        for i, name in ipairs(WebDKP_CheckInData.standbyPlayers) do
            local status = WebDKP_GetPlayerAttendanceStatus(name)
            WebDKP_Print("  " .. i .. ". " .. name .. " - 状态: " .. (status or "未知"))
        end
    else
        WebDKP_Print("WebDKP_CheckInData.standbyPlayers 不存在")
    end
end

-- 调试函数：显示当前保存的设置状态
WebDKP_CheckIn_DebugSettings = function()
    WebDKP_Print("=== 报名打卡设置调试信息 ===")
    WebDKP_Print("WebDKP_Options存在: " .. (WebDKP_Options and "是" or "否"))
    if WebDKP_Options then
        WebDKP_Print("WebDKP_Options.CheckInSettings存在: " .. (WebDKP_Options.CheckInSettings and "是" or "否"))
        if WebDKP_Options.CheckInSettings then
            WebDKP_Print("WebDKP_Options.CheckInSettings.standbyTime: " .. (WebDKP_Options.CheckInSettings.standbyTime or "nil"))
            WebDKP_Print("WebDKP_Options.CheckInSettings.rallyPoints: " .. (WebDKP_Options.CheckInSettings.rallyPoints or "nil"))
        end
    end
    WebDKP_Print("WebDKP_SavedCheckInSettings存在: " .. (WebDKP_SavedCheckInSettings and "是" or "否"))
    if WebDKP_SavedCheckInSettings then
        WebDKP_Print("WebDKP_SavedCheckInSettings.standbyTime: " .. (WebDKP_SavedCheckInSettings.standbyTime or "nil"))
        WebDKP_Print("WebDKP_SavedCheckInSettings.rallyPoints: " .. (WebDKP_SavedCheckInSettings.rallyPoints or "nil"))
    end
    WebDKP_Print("WebDKP_CheckInData.standbyTime: " .. (WebDKP_CheckInData.standbyTime or "nil"))
    WebDKP_Print("WebDKP_CheckInData.rallyPoints: " .. (WebDKP_CheckInData.rallyPoints or "nil"))
    WebDKP_Print("========================")
end



-- 使用setglobal函数确保函数在全局命名空间中可用（兼容WoW 1.12 Lua环境）
setglobal("WebDKP_CheckIn", WebDKP_CheckIn)
setglobal("WebDKP_CheckIn_ProcessStandbyPlayer", WebDKP_CheckIn_ProcessStandbyPlayer)
setglobal("WebDKP_CheckIn_SetStandbyCommand", WebDKP_CheckIn_SetStandbyCommand)
setglobal("WebDKP_GetPlayerClass", WebDKP_GetPlayerClass)
setglobal("WebDKP_CheckIn_Init", WebDKP_CheckIn_Init)
setglobal("WebDKP_CheckIn_SaveSettings", WebDKP_CheckIn_SaveSettings)
setglobal("WebDKP_CheckIn_LoadSettings", WebDKP_CheckIn_LoadSettings)
setglobal("WebDKP_CheckIn_DebugSettings", WebDKP_CheckIn_DebugSettings)
setglobal("WebDKP_CheckInUnregisteredEdit", WebDKP_CheckInUnregisteredEdit)
setglobal("WebDKP_CheckInAbsentEdit", WebDKP_CheckInAbsentEdit)
setglobal("WebDKP_ReportAttendance", WebDKP_ReportAttendance)
setglobal("WebDKP_ExportAttendance", WebDKP_ExportAttendance)
setglobal("WebDKP_CheckIn_DebugStandbyPlayers", WebDKP_CheckIn_DebugStandbyPlayers)
setglobal("WebDKP_GetPlayerAttendanceStatus", WebDKP_GetPlayerAttendanceStatus)