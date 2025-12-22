-- WebDKP_LootList.lua
-- 装备记录功能实现
-- 依赖: WebDKP.lua (必须在本文件之后加载) 没用了 查看用  已经整合到webdkp.lua 中

-- 创建装备记录窗口框架
function WebDKP_CreateLootListFrame()
    -- 如果框架已存在，直接返回
    if WebDKP_LootListFrame then
        return WebDKP_LootListFrame
    end
    
    -- 创建主框架
    local frame = CreateFrame("Frame", "WebDKP_LootListFrame", UIParent)
    frame:SetWidth(620)
    frame:SetHeight(400)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function()
        frame:StartMoving()
    end)
    frame:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
    end)
    
    -- 设置背景和边框
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 }
    })
    frame:SetBackdropColor(0, 0, 0, 0.8)
    
    -- 创建标题栏
    local title = frame:CreateTexture(nil, "ARTWORK")
    title:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
    title:SetWidth(620)
    title:SetHeight(64)
    title:SetPoint("TOP", frame, "TOP", 0, 12)
    
    local titleText = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    titleText:SetText("装备记录")
    titleText:SetPoint("TOP", title, "TOP", 0, -14)
    frame.titleText = titleText
    
    -- 创建关闭按钮
    local closeButton = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -3, -3)
    closeButton:SetScript("OnClick", function()
        frame:Hide()
    end)
    
    -- 创建模式切换按钮
    local modeButton = CreateFrame("Button", "WebDKP_LootListModeButton", frame, "UIPanelButtonTemplate")
    modeButton:SetWidth(100)
    modeButton:SetHeight(24)
    modeButton:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -35)
    modeButton:SetText("切换到DKP")
    modeButton:SetScript("OnClick", function()
        local currentMode = frame.currentMode or "loot"
        if currentMode == "loot" then
            frame.currentMode = "dkp"
            modeButton:SetText("切换到替补")
            titleText:SetText("DKP记录")
        elseif currentMode == "dkp" then
            frame.currentMode = "substitute"
            modeButton:SetText("切换到装备")
            titleText:SetText("替补名单")
        else
            frame.currentMode = "loot"
            modeButton:SetText("切换到DKP")
            titleText:SetText("装备记录")
        end
        WebDKP_UpdateLootList()
    end)
    

    
    -- 创建列标题
    local headers = {
        {name = "物品名称", width = 220, anchor = "TOPLEFT", x = 10, y = -60},
        {name = "获得者", width = 120, anchor = "TOPLEFT", x = 230, y = -60},
        {name = "DKP花费", width = 80, anchor = "TOPLEFT", x = 350, y = -60},
        {name = "时间", width = 140, anchor = "TOPLEFT", x = 430, y = -60}
    }
    
    -- 创建DKP模式的列标题
    local dkpHeaders = {
        {name = "项目名称", width = 220, anchor = "TOPLEFT", x = 10, y = -60},
        {name = "玩家人数", width = 120, anchor = "TOPLEFT", x = 230, y = -60},
        {name = "分数", width = 80, anchor = "TOPLEFT", x = 350, y = -60},
        {name = "时间", width = 140, anchor = "TOPLEFT", x = 430, y = -60}
    }
    
    -- 创建替补模式的列标题
    local substituteHeaders = {
        {name = "项目名称", width = 200, anchor = "TOPLEFT", x = 10, y = -60},
        {name = "玩家名称", width = 120, anchor = "TOPLEFT", x = 210, y = -60},
        {name = "分数", width = 60, anchor = "TOPLEFT", x = 330, y = -60},
        {name = "所在地", width = 80, anchor = "TOPLEFT", x = 390, y = -60},
        {name = "加分时间", width = 140, anchor = "TOPLEFT", x = 470, y = -60}
    }
    
    -- 创建标题按钮
    for i, header in ipairs(headers) do
        local headerButton = CreateFrame("Button", "WebDKP_LootListHeader"..i, frame, "UIPanelButtonTemplate")
        headerButton:SetWidth(header.width)
        headerButton:SetHeight(24)
        headerButton:SetPoint(header.anchor, frame, header.anchor, header.x, header.y)
        headerButton:SetText(header.name)
        headerButton:SetNormalFontObject("GameFontHighlightSmall")
        headerButton:SetHighlightFontObject("GameFontHighlightSmall")
        headerButton:Disable()
        frame["header"..i] = headerButton
    end
    
    -- 创建滚动框架
    local scrollFrame = CreateFrame("ScrollFrame", "WebDKP_LootListScrollFrame", frame, "FauxScrollFrameTemplate")
    scrollFrame:SetWidth(600)
    scrollFrame:SetHeight(330)
    scrollFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -70)
    scrollFrame:SetScript("OnVerticalScroll", function()
        FauxScrollFrame_OnVerticalScroll(16, WebDKP_UpdateLootList)
    end)
    
    -- 创建16个静态行框架
    for i = 1, 16 do
        local lineFrame = CreateFrame("Frame", "WebDKP_LootListLine"..i, frame)
        lineFrame:SetID(i)
        lineFrame:SetWidth(580)
        lineFrame:SetHeight(20)
        lineFrame:SetPoint("TOPLEFT", scrollFrame, "TOPLEFT", 0, -(i-1)*20)
        
        -- 创建背景
        local bg = lineFrame:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(lineFrame)
        bg:SetTexture(0.1, 0.1, 0.1, 0.3)
        lineFrame.bg = bg
        
        -- 创建高亮纹理
        local highlightTexture = lineFrame:CreateTexture(nil, "HIGHLIGHT")
        highlightTexture:SetAllPoints(lineFrame)
        highlightTexture:SetTexture(0.2, 0.4, 0.8, 0.5) -- 蓝色半透明
        highlightTexture:Hide()
        lineFrame.highlightTexture = highlightTexture
        
        -- 创建文本框
        local itemText = lineFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        itemText:SetPoint("LEFT", lineFrame, "LEFT", 10, 0)
        itemText:SetWidth(190)
        itemText:SetJustifyH("LEFT")
        lineFrame.itemText = itemText
        
        local playerText = lineFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        playerText:SetPoint("LEFT", lineFrame, "LEFT", 240, 0)
        playerText:SetWidth(90)
        playerText:SetJustifyH("LEFT")
        lineFrame.playerText = playerText
        
        local costText = lineFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        costText:SetPoint("LEFT", lineFrame, "LEFT", 310, 0)
        costText:SetWidth(70)
        costText:SetJustifyH("LEFT")
        lineFrame.costText = costText
        
        local timeText = lineFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        timeText:SetPoint("LEFT", lineFrame, "LEFT", 390, 0)
        timeText:SetWidth(110)
        timeText:SetJustifyH("LEFT")
        lineFrame.timeText = timeText

        -- 创建分数文本框（替补模式专用）
        local scoreText = lineFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        scoreText:SetPoint("LEFT", lineFrame, "LEFT", 290, 0)
        scoreText:SetWidth(50)
        scoreText:SetJustifyH("LEFT")
        lineFrame.scoreText = scoreText
        
        local playerText = lineFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        playerText:SetPoint("LEFT", lineFrame, "LEFT", 240, 0)
        playerText:SetWidth(90)
        playerText:SetJustifyH("LEFT")
        lineFrame.playerText = playerText
        
        local costText = lineFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        costText:SetPoint("LEFT", lineFrame, "LEFT", 310, 0)
        costText:SetWidth(70)
        costText:SetJustifyH("LEFT")
        lineFrame.costText = costText
        
        local timeText = lineFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        timeText:SetPoint("LEFT", lineFrame, "LEFT", 390, 0)
        timeText:SetWidth(110)
        timeText:SetJustifyH("LEFT")
        lineFrame.timeText = timeText
        
        -- 隐藏行框架
        lineFrame:Hide()
    end
    
    -- 设置默认模式
    frame.currentMode = "loot"
    
    return frame
end

-- 获取表格大小
function WebDKP_GetTableSize(table)
    local count = 0
    if table == nil then
        return count
    end
    for key, entry in pairs(table) do
        count = count + 1
    end
    return count
end

-- 获取装备记录
function WebDKP_GetLootRecords()
    local records = {}
    local recordIndex = 1
    
    -- 从日志中提取装备记录
    if WebDKP_Log then
        for key, entry in pairs(WebDKP_Log) do
            if type(entry) == "table" and key ~= "Version" and (entry.foritem == "true" or entry.foritem == true) then
                -- 这是一个物品奖励记录
                for playerName, playerInfo in pairs(entry.awarded or {}) do
                    -- 直接使用储存文件中的数据，不处理装备链接
                    local itemName = entry.reason  -- 使用reason字段作为物品名称
                    
                    -- 创建唯一标识符 - 使用与WebDKP_Log中相同的格式
                local uniqueId = entry.uniqueId or ("loot_" .. recordIndex .. "_" .. (playerName or "unknown") .. "_" .. (entry.timestamp or "unknown"))
                    
                    local record = {
                        item = itemName or "未知装备",  -- 使用物品名称，如果没有则使用默认值
                        player = playerName,
                        points = tonumber(entry.points), -- 确保points是数字类型
                        dkp = math.abs(tonumber(entry.points) or 0), -- 添加dkp字段以兼容显示函数
                        time = entry.date or "未知",
                        date = entry.date or "未知", -- 添加date字段用于安全删除
                        uniqueId = uniqueId, -- 添加唯一标识符
                        key = key, -- 添加原始键值以便于查找
                        timestamp = entry.timestamp
                    }
                    table.insert(records, record)
                    recordIndex = recordIndex + 1
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

-- 获取DKP记录
function WebDKP_GetDKPRecords()
    local records = {}
    local recordIndex = 1
    
    -- 从日志中提取非物品DKP记录
    if WebDKP_Log then
        for key, entry in pairs(WebDKP_Log) do
            if type(entry) == "table" and key ~= "Version" and not (entry.foritem == "true" or entry.foritem == true) and not (entry.reason and string.find(entry.reason, "替补")) then
                -- 这是一个DKP记录（非物品奖励，非替补）
                local playerCount = 0
                
                -- 计算玩家人数
                if entry.awarded then
                    for playerName, playerInfo in pairs(entry.awarded) do
                        playerCount = playerCount + 1
                    end
                end
                
                -- 获取列表ID和对应的列表名称
                local tableid = entry.tableid or WebDKP_GetTableid()
                -- 使用统一的函数获取表格名称
                local tableName = WebDKP_GetTableNameById(tableid)
                
                -- 直接使用entry.points作为分数，保留正负号
                local score = entry.points or 0
                
                -- 创建唯一标识符 - 使用与WebDKP_Log中相同的格式
                local uniqueId = entry.uniqueId or (entry.reason .. " " .. entry.date)
                
                local record = {
                    item = entry.reason or "未知项目",
                    playerCount = playerCount,
                    score = score,
                    points = score, -- 确保同时设置points字段
                    time = entry.date or "未知",
                    date = entry.date or "未知",
                    tableid = tableid,
                    tableName = tableName, -- 添加列表名称
                    uniqueId = uniqueId, -- 添加唯一标识符
                    key = key, -- 添加原始键值以便于查找
                    timestamp = entry.timestamp,
                    awarded = entry.awarded -- 保存受奖励玩家信息
                }
                table.insert(records, record)
                recordIndex = recordIndex + 1
            end
        end
    end
    
    -- 按时间倒序排序
    table.sort(records, function(a, b)
        return a.time > b.time
    end)
    
    return records
end

-- 获取替补记录
function WebDKP_GetSubstituteRecords()
    local records = {}
    local uniqueRecords = {}
    local recordKeys = {}
    local recordIndex = 1
    
    -- 首先处理新格式的独立记录（使用name_timestamp作为键）
    if WebDKP_DailySubRecords then
        for dateKey, dayData in pairs(WebDKP_DailySubRecords) do
            for key, data in pairs(dayData) do
                -- 判断是否为新格式的独立记录（包含timestamp字段）
                if data.timestamp and data.name then
                    -- 创建唯一标识符 - 使用与WebDKP_Log中相同的格式
                    local uniqueId = data.uniqueId or (data.reason .. " " .. data.time)
                    
                    local record = {
                        item = data.reason or "替补记录", -- 使用记录中的实际项目名称，如果没有则使用默认值
                        player = data.name, -- 玩家名称
                        class = data.class,
                        count = data.count or 1,
                        location = data.location or "未知", -- 使用每条记录独立的location
                        time = data.time or dateKey,
                        timestamp = data.timestamp,
                        date = data.time or dateKey, -- 添加date字段用于安全删除
                        source = "daily_unique",
                        uniqueId = uniqueId, -- 添加唯一标识符
                        score = tonumber(data.points) or 0 -- 确保分数是数字类型
                    }
                    table.insert(records, record)
                    recordIndex = recordIndex + 1
                elseif data.class and not data.timestamp then
                    -- 处理旧格式的玩家索引记录（保持兼容性）
                    -- 但不再将其作为独立记录添加，只用于补充信息
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
                    -- 为日志记录创建唯一标识
                    local logKey = playerName .. "_" .. (entry.timestamp or entry.date)
                    
                    -- 检查是否已经从独立记录中获取过
                    local alreadyExists = false
                    for _, existingRecord in ipairs(records) do
                        if existingRecord.player == playerName and 
                           (existingRecord.time == entry.date or 
                            (existingRecord.timestamp and entry.timestamp and 
                             math.abs(existingRecord.timestamp - entry.timestamp) < 1)) then
                            alreadyExists = true
                            break
                        end
                    end
                    
                    if not alreadyExists then
                        -- 尝试从WebDKP_DailySubRecords中查找匹配的独立记录获取location
                        local location = "未知"
                        
                        -- 搜索当天可能的独立记录
                        if WebDKP_DailySubRecords and entry.date then
                            -- 提取日期部分
                            local datePart = string.sub(entry.date, 1, 10)
                            if WebDKP_DailySubRecords[datePart] then
                                for key, data in pairs(WebDKP_DailySubRecords[datePart]) do
                                    if data.timestamp and data.name == playerName and 
                                       (not entry.timestamp or math.abs(data.timestamp - entry.timestamp) < 1) then
                                        location = data.location or "未知"
                                        break
                                    end
                                end
                            end
                        end
                        
                        -- 如果找不到独立记录，再尝试从旧格式记录获取（仅作为后备）
                        if location == "未知" and WebDKP_DailySubRecords and entry.date then
                            -- 提取日期部分
                            local datePart = string.sub(entry.date, 1, 10)
                            if WebDKP_DailySubRecords[datePart] and WebDKP_DailySubRecords[datePart][playerName] then
                                location = WebDKP_DailySubRecords[datePart][playerName].location or "未知"
                            end
                        end
                        
                        -- 如果还是找不到，尝试从WebDKP_SubData.subs获取（仅作为后备）
                        if location == "未知" and WebDKP_SubData and WebDKP_SubData.subs and WebDKP_SubData.subs[playerName] then
                            location = WebDKP_SubData.subs[playerName].location or "未知"
                        end
                        
                        -- 创建唯一标识符 - 使用与WebDKP_Log中相同的格式
                        local uniqueId = entry.uniqueId or (entry.reason .. " " .. entry.date)
                        
                        local record = {
                            item = entry.reason or "替补记录", -- 使用记录中的实际项目名称，如果没有则使用默认值
                            player = playerName, -- 玩家名称
                            location = location, -- 玩家所在地
                            time = entry.date or "未知", -- 加分时间
                            timestamp = entry.timestamp,
                            date = entry.date or "未知", -- 添加date字段用于安全删除
                            source = "log",
                            uniqueId = uniqueId, -- 添加唯一标识符
                            key = key, -- 添加原始键值以便于查找
                            score = tonumber(entry.points) or 0 -- 确保分数是数字类型
                        }
                        table.insert(records, record)
                        recordIndex = recordIndex + 1
                    end
                end
            end
        end
    end
    
    -- 确保每条记录都是唯一的，基于player和timestamp的组合
    for _, record in ipairs(records) do
        -- 使用player和timestamp创建唯一键，确保每条记录独立
        local uniqueKey = record.player .. "_" .. (record.timestamp or record.time)
        
        if not recordKeys[uniqueKey] then
            uniqueRecords[table.getn(uniqueRecords) + 1] = record
            recordKeys[uniqueKey] = true
        end
    end
    
    -- 按时间倒序排序（优先使用timestamp，然后是time）
    table.sort(uniqueRecords, function(a, b) 
        if a.timestamp and b.timestamp then
            return a.timestamp > b.timestamp
        else
            return a.time > b.time
        end
    end)
    
    return uniqueRecords
end

-- 更新装备记录列表
function WebDKP_UpdateLootList()
    local frame = WebDKP_LootListFrame
    if not frame then
        return
    end
    
    -- 获取当前模式
    local currentMode = frame.currentMode or "loot"
    
    -- 根据模式显示不同的列标题
    if frame.columnHeaders then
        -- 先隐藏所有列标题
        for _, headers in pairs(frame.columnHeaders) do
            for _, header in pairs(headers) do
                if header and header.Hide then
                    header:Hide()
                end
            end
        end
        
        -- 然后显示当前模式的列标题
        if frame.columnHeaders[currentMode] then
            for _, header in pairs(frame.columnHeaders[currentMode]) do
                if header and header.Show then
                    header:Show()
                end
            end
        end
    end
    
    -- 获取记录数据
    local records = {}
    if currentMode == "substitute" then
        records = WebDKP_GetSubstituteRecords()
    elseif currentMode == "dkp" then
        records = WebDKP_GetDKPRecords()
    else
        records = WebDKP_GetLootRecords()
    end
    
    -- 更新滚动框架
    local numRecords = WebDKP_GetTableSize(records)
    local numToDisplay = 16
    FauxScrollFrame_Update(WebDKP_LootListScrollFrame, numRecords, numToDisplay, 20)
    
    -- 获取滚动偏移
    local offset = FauxScrollFrame_GetOffset(WebDKP_LootListScrollFrame)
    
    -- 更新行数据
    for i = 1, numToDisplay do
        local recordIndex = offset + i
        local record = records[recordIndex]
        
        local lineFrame = getglobal("WebDKP_LootListLine"..i)
        if lineFrame and record then
            -- 显示行框架
            lineFrame:Show()
            
            -- 设置记录索引
            lineFrame.recordIndex = recordIndex
            
            -- 根据模式显示不同的数据
            if currentMode == "loot" then
                -- 装备记录模式
                local dkpValue = record.dkp or record.cost or "0"
                if lineFrame.itemText then
                    lineFrame.itemText:SetText("[装备] " .. (record.item or "未知物品"))
                end
                if lineFrame.playerText then
                    lineFrame.playerText:SetText(record.player or "")
                end
                if lineFrame.costText then
                    -- 显示装备花费，使用points字段（已经是负数）
                local displayPoints = tonumber(record.points) or 0
                lineFrame.costText:SetText(math.abs(displayPoints))
                end
                if lineFrame.timeText then
                    lineFrame.timeText:SetText(record.time or "未知")
                end
            elseif currentMode == "dkp" then
                -- DKP记录模式
                if lineFrame.itemText then
                    -- 使用统一的函数获取表格名称
                    local tableName = WebDKP_GetTableNameById(record.tableid)
                    lineFrame.itemText:SetText("[" .. tableName .. "] " .. (record.item or "未知项目"))
                end
                if lineFrame.playerText then
                    lineFrame.playerText:SetText(record.playerCount or "0")
                end
                if lineFrame.costText then
                    -- 显示原始分数，保留正负号
                    lineFrame.costText:SetText(record.score or "0")
                end
                if lineFrame.timeText then
                    lineFrame.timeText:SetText(record.time or "未知")
                end
            elseif currentMode == "substitute" then
                -- 替补名单模式
                if lineFrame.itemText then
                    -- 按照 [替补] boss名称 的格式显示
                    local bossName = record.item or "替补"
                    lineFrame.itemText:SetText("[替补] " .. bossName)
                end
                if lineFrame.playerText then
                    lineFrame.playerText:SetText(record.player or "")
                end
                if lineFrame.scoreText then
                    lineFrame.scoreText:SetText(record.score or "0")
                end
                if lineFrame.costText then
                    lineFrame.costText:SetText(record.location or "未知")
                end
                if lineFrame.timeText then
                    lineFrame.timeText:SetText(record.time or "未知")
                end
            end
            
            -- 创建修改按钮（如果不存在）
            if not lineFrame.editButton then
                lineFrame.editButton = CreateFrame("Button", "WebDKP_LootListLine"..i.."EditButton", lineFrame, "UIPanelButtonTemplate")
                lineFrame.editButton:SetWidth(20)
                lineFrame.editButton:SetHeight(18)
                lineFrame.editButton:SetText("改")
                lineFrame.editButton:SetPoint("RIGHT", lineFrame, "RIGHT", -25, 2)
                lineFrame.editButton:SetNormalTexture([[Interface\Buttons\UI-Panel-Button-Down]])
                lineFrame.editButton:GetNormalTexture():SetVertexColor(0.8, 0.2, 0.2)
                lineFrame.editButton:SetHighlightTexture([[Interface\Buttons\UI-Panel-Button-Highlight]])
                lineFrame.editButton:GetHighlightTexture():SetVertexColor(1, 0.3, 0.3)
                lineFrame.editButton:SetPushedTexture([[Interface\Buttons\UI-Panel-Button-Down]])
                lineFrame.editButton:GetPushedTexture():SetVertexColor(1, 0.1, 0.1)
                
                -- 设置修改按钮点击事件
                lineFrame.editButton:SetScript("OnClick", function()
                    -- 获取当前行框架的ID和记录索引
                    local lineFrameID = this:GetParent():GetID()
                    local currentRecordIndex = this:GetParent().recordIndex
                    
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
                    
                    -- 根据不同模式执行不同的修改操作
                    if currentMode == "dkp" then
                        -- DKP记录修改分数
                        local currentPoints = latestRecord.points or latestRecord.score or 0
                        local uniqueId = latestRecord.uniqueId
                        
                        -- 显示修改分数对话框
                        if WebDKP_ShowEditDKPDialog then
                            WebDKP_ShowEditDKPDialog(uniqueId, currentPoints)
                        else
                            WebDKP_Print("错误：修改DKP功能不可用")
                        end
                    elseif currentMode == "loot" then
                        -- 装备获取记录修改
                        local uniqueId = latestRecord.uniqueId
                        if WebDKP_ShowEditLootDialog then
                            WebDKP_ShowEditLootDialog(uniqueId, latestRecord.points or 0)
                        else
                            WebDKP_Print("错误：修改装备记录功能不可用")
                        end
                    elseif currentMode == "substitute" then
                        -- 替补名单修改
                        local uniqueId = latestRecord.uniqueId
                        
                        -- 显示修改替补记录对话框
                        if WebDKP_ShowEditSubstituteDialog then
                            WebDKP_ShowEditSubstituteDialog(uniqueId, latestRecord.points or 0)
                        else
                            WebDKP_Print("错误：修改替补记录功能不可用")
                        end
                    end
                end)
            end
            
            -- 显示修改按钮（在DKP、装备获取记录和替补名单模式下都显示）
            if WebDKP_LootListFrame.currentMode == "dkp" or WebDKP_LootListFrame.currentMode == "loot" or WebDKP_LootListFrame.currentMode == "substitute" then
                lineFrame.editButton:Show()
            else
                lineFrame.editButton:Hide()
            end
            
            -- 创建删除按钮（如果不存在）
            if not lineFrame.deleteButton then
                lineFrame.deleteButton = CreateFrame("Button", "WebDKP_LootListLine"..i.."DeleteButton", lineFrame, "UIPanelButtonTemplate")
                lineFrame.deleteButton:SetWidth(20)
                lineFrame.deleteButton:SetHeight(18)
                lineFrame.deleteButton:SetText("X")
                lineFrame.deleteButton:SetPoint("RIGHT", lineFrame, "RIGHT", 0, 2)
                lineFrame.deleteButton:SetNormalTexture([[Interface\Buttons\UI-Panel-Button-Down]])
                lineFrame.deleteButton:GetNormalTexture():SetVertexColor(0.8, 0.2, 0.2)
                lineFrame.deleteButton:SetHighlightTexture([[Interface\Buttons\UI-Panel-Button-Highlight]])
                lineFrame.deleteButton:GetHighlightTexture():SetVertexColor(1, 0.3, 0.3)
                lineFrame.deleteButton:SetPushedTexture([[Interface\Buttons\UI-Panel-Button-Down]])
                lineFrame.deleteButton:GetPushedTexture():SetVertexColor(1, 0.1, 0.1)
                
                -- 设置删除按钮点击事件
                lineFrame.deleteButton:SetScript("OnClick", function()
                    -- 获取当前行框架的ID和记录索引
                    local lineFrameID = this:GetParent():GetID()
                    local currentRecordIndex = this:GetParent().recordIndex
                    
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
                    
                    -- 保存记录引用和当前模式
                    WebDKP_CurrentRecord = {}
                    
                    -- 根据不同模式正确获取字段信息
                    if currentMode == "dkp" then
                        WebDKP_CurrentRecord.item = latestRecord.reason or latestRecord.item or "未知项目"
                        WebDKP_CurrentRecord.time = latestRecord.date or latestRecord.time or date()
                        WebDKP_CurrentRecord.player = latestRecord.name or latestRecord.player or "未知玩家"
                    elseif currentMode == "substitute" then
                        WebDKP_CurrentRecord.item = latestRecord.reason or latestRecord.item or "替补记录"
                        WebDKP_CurrentRecord.time = latestRecord.date or latestRecord.time or date()
                        WebDKP_CurrentRecord.player = latestRecord.name or latestRecord.player or "未知玩家"
                    elseif currentMode == "loot" then
                        -- 装备记录使用reason字段作为装备名称
                        WebDKP_CurrentRecord.item = latestRecord.reason or "未知装备"
                        WebDKP_CurrentRecord.time = latestRecord.date or latestRecord.time or date()
                        WebDKP_CurrentRecord.player = latestRecord.name or latestRecord.player or "未知玩家"
                    else
                        WebDKP_CurrentRecord.item = latestRecord.item or latestRecord.reason or latestRecord.lootitem or "未知物品"
                        WebDKP_CurrentRecord.time = latestRecord.time or latestRecord.date or date()
                        WebDKP_CurrentRecord.player = latestRecord.player or latestRecord.name or "未知玩家"
                    end
                    WebDKP_CurrentRecord.rawRecord = latestRecord
                     
                    -- 根据模式确保包含特定字段
                    if currentMode == "substitute" then
                        WebDKP_CurrentRecord.location = latestRecord.location or "未知"
                    elseif currentMode == "loot" then
                        WebDKP_CurrentRecord.points = latestRecord.points or 0
                    elseif currentMode == "dkp" then
                        WebDKP_CurrentRecord.tableid = latestRecord.tableid
                        WebDKP_CurrentRecord.score = latestRecord.score
                    end
                    
                    -- 保存当前记录的索引和行框架ID
                    WebDKP_CurrentRecordIndex = currentRecordIndex
                    WebDKP_CurrentLineFrameID = lineFrameID
                    WebDKP_CurrentRecordMode = WebDKP_LootListFrame.currentMode
                    WebDKP_CurrentRecordUniqueId = latestRecord.uniqueId or currentRecordIndex
                    
                    -- 确保StaticPopupDialogs表存在
                    if not StaticPopupDialogs then
                        StaticPopupDialogs = {}
                    end
                    
                    -- 定义删除确认对话框
                    if not StaticPopupDialogs["CONFIRM_DELETE_RECORD"] then
                        StaticPopupDialogs["CONFIRM_DELETE_RECORD"] = {
                            text = "确定要删除这条记录吗？",
                            button1 = "确定",
                            button2 = "取消",
                            OnAccept = function()
                                -- 根据当前模式删除记录的逻辑将在对话框中处理
                                StaticPopupDialogs["CONFIRM_DELETE_RECORD"]._deleteCallback()
                            end,
                            timeout = 0,
                            whileDead = true,
                            hideOnEscape = true
                        }
                    end
                    
                    -- 设置删除确认对话框的文本
                    local dialogText = "确定要删除这条记录吗？"
                    if WebDKP_CurrentRecordMode == "loot" and WebDKP_CurrentRecord then
                        dialogText = "确定要删除装备记录: " .. (WebDKP_CurrentRecord.item or "未知物品") .. " 吗？"
                    elseif WebDKP_CurrentRecordMode == "dkp" and WebDKP_CurrentRecord then
                        dialogText = "确定要删除DKP记录: " .. (WebDKP_CurrentRecord.item or "未知项目") .. " 吗？"
                    elseif WebDKP_CurrentRecordMode == "substitute" and WebDKP_CurrentRecord then
                        dialogText = "确定要删除替补记录: " .. (WebDKP_CurrentRecord.player or "未知玩家") .. " 吗？"
                    end
                    StaticPopupDialogs["CONFIRM_DELETE_RECORD"].text = dialogText
                    
                    -- 设置删除回调函数
                    StaticPopupDialogs["CONFIRM_DELETE_RECORD"]._deleteCallback = function()
                        -- 实际的记录删除逻辑
                        if WebDKP_CurrentRecordMode and WebDKP_CurrentRecord then
                            local success = false
                            
                            -- 根据模式使用相应的删除函数
                            if WebDKP_CurrentRecordMode == "dkp" then
                                -- 删除DKP记录，使用已有的删除函数
                                if WebDKP_DeleteDKPRecordByItemAndTime then
                                    success = WebDKP_DeleteDKPRecordByItemAndTime(
                                        WebDKP_CurrentRecord.item, 
                                        WebDKP_CurrentRecord.time
                                    )
                                end
                            elseif WebDKP_CurrentRecordMode == "substitute" then
                                -- 删除替补记录
                                if WebDKP_DeleteSubstituteRecordByItemAndTime then
                                    success = WebDKP_DeleteSubstituteRecordByItemAndTime(
                                        WebDKP_CurrentRecord.player, 
                                        WebDKP_CurrentRecord.item, 
                                        WebDKP_CurrentRecord.time
                                    )
                                end
                            elseif WebDKP_CurrentRecordMode == "loot" then
                                -- 删除装备记录并恢复DKP分数
                                if WebDKP_DeleteLootRecord then
                                    success = WebDKP_DeleteLootRecord(
                                        WebDKP_CurrentRecord.item,
                                        WebDKP_CurrentRecord.player,
                                        WebDKP_CurrentRecord.time
                                    )
                                end
                            end
                            
                            -- 显示删除结果
                            if success then
                                -- 确保数据保存到磁盘
                                if WebDKP_SaveToDisk then
                                    WebDKP_SaveToDisk()
                                end
                            else
                                WebDKP_Print("记录删除失败")
                            end
                        end
                        
                        -- 更新列表显示
                        if WebDKP_UpdateLootList then
                            WebDKP_UpdateLootList()
                        end
                    end
                    
                    -- 显示确认对话框
                    StaticPopup_Show("CONFIRM_DELETE_RECORD")
                end)
            end
            
            -- 显示删除按钮
            lineFrame.deleteButton:Show()
        else
            -- 隐藏空行
            if lineFrame then
                lineFrame:Hide()
                if lineFrame.deleteButton then
                    lineFrame.deleteButton:Hide()
                end
                if lineFrame.editButton then
                    lineFrame.editButton:Hide()
                end
            end
        end
    end
end

-- 切换装备记录窗口显示状态
function WebDKP_ToggleLootList()
    if not WebDKP_LootListFrame then
        WebDKP_CreateLootListFrame()
    end
    
    if WebDKP_LootListFrame:IsShown() then
        WebDKP_LootListFrame:Hide()
    else
        WebDKP_LootListFrame:Show()
        WebDKP_UpdateLootList()
    end
end

-- 导出当前数据
function WebDKP_ExportCurrentData()
    local frame = WebDKP_LootListFrame
    if not frame then
        WebDKP_Print("错误：无法找到装备记录窗口")
        return
    end
    
    local currentMode = frame.currentMode or "loot"
    local exportText = ""
    local fileName = ""
    
    -- 根据当前模式导出相应数据
    if currentMode == "loot" then
        -- 导出装备记录
        exportText = WebDKP_ExportLootRecords()
        fileName = "装备获取记录" .. date("%Y%m%d") 
    elseif currentMode == "dkp" then
        -- 导出DKP记录
        exportText = WebDKP_ExportDKPRecords()
        fileName = "DKP列表" .. date("%Y%m%d")
    elseif currentMode == "substitute" then
        -- 导出替补记录
        exportText = WebDKP_ExportSubstituteRecords()
        fileName = "替补名单" .. date("%Y%m%d")
    else
        WebDKP_Print("错误：未知的导出模式")
        return
    end
    
    -- 使用superwow的ExportFile接口导出数据
    if exportText and exportText ~= "" then
        local success = ExportFile(fileName, exportText)
        if success then
            WebDKP_Print("数据已成功导出到 " .. fileName)
        else
            WebDKP_Print("导出失败，请检查文件权限或磁盘空间")
        end
    else
        WebDKP_Print("没有数据可导出")
    end
end

-- 导出装备记录
function WebDKP_ExportLootRecords()
    local records = WebDKP_GetLootRecords()
    local exportText = "时间,获得者,物品名称,花费\n"
    
    for _, record in ipairs(records) do
        local time = record.time or "未知"
        local player = record.player or "未知"
        local item = record.item or "未知"
        local points = record.points or 0
        
        -- 将时间格式中的-替换为/
        if time ~= "未知" then
            time = string.gsub(time, "-", "/")
        end
        
        -- 转义逗号，避免破坏CSV格式
        player = string.gsub(player, ",", " ")
        item = string.gsub(item, ",", " ")
        
        exportText = exportText .. time .. "," .. player .. "," .. item .. "," .. math.abs(points) .. "\n"
    end
    
    return exportText
end

-- 导出DKP记录
function WebDKP_ExportDKPRecords()
    local records = WebDKP_GetDKPRecords()
    local negativeRecords = {}
    local positiveRecords = {}
    
    -- 分离扣分项和加分项
    for _, record in ipairs(records) do
        local score = record.score or 0
        if score < 0 then
            table.insert(negativeRecords, record)
        else
            table.insert(positiveRecords, record)
        end
    end
    local exportText = "时间,玩家名称,项目名称,分数\n"
          exportText = exportText .. "==============扣分===============\n"
    
    -- 导出扣分项
    for _, record in ipairs(negativeRecords) do
        -- 从日志中查找原始记录，获取每个玩家的单独分数
        if WebDKP_Log then
            for key, entry in pairs(WebDKP_Log) do
                if type(entry) == "table" and key ~= "Version" and 
                   entry.date == record.time and entry.reason == record.item and 
                   not (entry.foritem == "true" or entry.foritem == true) then
                    
                    for playerName, playerInfo in pairs(entry.awarded or {}) do
                        local time = record.time or "未知"
                        local player = playerName or "未知"
                        local item = record.item or "未知"
                        local score = entry.points or 0
                        
                        -- 将时间格式中的-替换为/
                        if time ~= "未知" then
                            time = string.gsub(time, "-", "/")
                        end
                        
                        -- 转义逗号，避免破坏CSV格式
                        player = string.gsub(player, ",", " ")
                        item = string.gsub(item, ",", " ")
                        
                        exportText = exportText .. time .. "," .. player .. "," .. item .. "," .. score .. "\n"
                    end
                    break
                end
            end
        end
    end
    
    exportText = exportText .. "==============击杀===============\n"
    
    -- 导出加分项
    for _, record in ipairs(positiveRecords) do
        -- 从日志中查找原始记录，获取每个玩家的单独分数
        if WebDKP_Log then
            for key, entry in pairs(WebDKP_Log) do
                if type(entry) == "table" and key ~= "Version" and 
                   entry.date == record.time and entry.reason == record.item and 
                   not (entry.foritem == "true" or entry.foritem == true) then
                    
                    for playerName, playerInfo in pairs(entry.awarded or {}) do
                        local time = record.time or "未知"
                        local player = playerName or "未知"
                        local item = record.item or "未知"
                        local score = entry.points or 0
                        
                        -- 将时间格式中的-替换为/
                        if time ~= "未知" then
                            time = string.gsub(time, "-", "/")
                        end
                        
                        -- 转义逗号，避免破坏CSV格式
                        player = string.gsub(player, ",", " ")
                        item = string.gsub(item, ",", " ")
                        
                        exportText = exportText .. time .. "," .. player .. "," .. item .. "," .. score .. "\n"
                    end
                    break
                end
            end
        end
    end
    
    return exportText
end

-- 导出替补记录
function WebDKP_ExportSubstituteRecords()
    local records = WebDKP_GetSubstituteRecords()
    local exportText = "时间,玩家名称,项目名称,分数\n"
    
    -- 预构建日志索引，按时间+玩家名存储，同时保存reason信息
    local logIndex = {}
    if WebDKP_Log then
        for key, entry in pairs(WebDKP_Log) do
            if type(entry) == "table" and key ~= "Version" and entry.date and entry.reason and entry.points then
                -- 为替补相关记录建立索引，只使用精确匹配的关键词
                local isSubstituteRecord = string.find(entry.reason, "集合-替补") or string.find(entry.reason, "替补加分")
                if isSubstituteRecord and not (entry.foritem == "true" or entry.foritem == true) and entry.awarded then
                    
                    -- 使用完整的日期时间作为键，确保精确匹配
                    local dateKey = entry.date
                    
                    for playerName, _ in pairs(entry.awarded) do
                        -- 使用完整日期+玩家名作为索引键
                        local indexKey = dateKey .. playerName
                        -- 存储分数和项目名称
                        logIndex[indexKey] = {
                            points = tonumber(entry.points) or 0,
                            reason = entry.reason
                        }
                    end
                end
            end
        end
    end
    
    for _, record in ipairs(records) do
        local time = record.time or "未知"
        local player = record.player or "未知"
        local item = record.item or "替补分" -- 默认使用"替补分"
        local score = 0
        
        -- 将时间格式中的-替换为/
        if time ~= "未知" then
            time = string.gsub(time, "-", "/")
        end
        
        -- 尝试从WebDKP_Log中精确查找
        if WebDKP_Log and record.time then
            -- 使用原始时间格式（带-）进行查找
            local originalTime = record.time
            local recordKey = originalTime .. player
            
            -- 方法1：直接使用预构建索引
            if logIndex[recordKey] then
                score = logIndex[recordKey].points
                item = logIndex[recordKey].reason
            else
                -- 方法2：遍历日志进行精确匹配
                for key, entry in pairs(WebDKP_Log) do
                    if type(entry) == "table" and key ~= "Version" and 
                       entry.date and entry.reason and entry.points and 
                       entry.awarded and entry.awarded[player] then
                        
                        -- 精确匹配日期时间
                        if entry.date == originalTime then
                            score = tonumber(entry.points) or 0
                            item = entry.reason
                            break
                        end
                    end
                end
            end
        end
        

        
        -- 转义逗号，避免破坏CSV格式
        player = string.gsub(player, ",", " ")
        item = string.gsub(item, ",", " ")
        
        exportText = exportText .. time .. "," .. player .. "," .. item .. "," .. score .. "\n"
    end
    
    return exportText
end