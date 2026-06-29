-- WebDKP_LootList.lua
-- 装备记录功能实现
-- 依赖: WebDKP.lua (必须在本文件之后加载) 没用了 查看用  已经整合到webdkp.lua 中

-- 创建装备记录窗口框架
function WebDKP_CreateLootListFrame()
    -- 如果框架已存在，直接返回
    if WebDKP_LootListFrame then
        return WebDKP_LootListFrame
    end

    -- 全宽数据面板：铺满主窗口内部，底部留出标签条空间
    local frame = CreateFrame("Frame", "WebDKP_LootListFrame", WebDKP_Frame)
    frame:SetPoint("TOPLEFT", WebDKP_Frame, "TOPLEFT", 12, -44)
    frame:SetPoint("BOTTOMRIGHT", WebDKP_Frame, "BOTTOMRIGHT", -12, 128)
    frame:EnableMouse(true)
    -- 抬高层级，覆盖左侧名单等内容
    if WebDKP_Frame and WebDKP_Frame.GetFrameLevel then
        frame:SetFrameLevel(WebDKP_Frame:GetFrameLevel() + 10)
    end

    -- 不透明背景，遮住下层的玩家名单
    local panelBg = frame:CreateTexture(nil, "BACKGROUND")
    panelBg:SetAllPoints(frame)
    panelBg:SetTexture(0.06, 0.06, 0.08, 0.95)
    frame.panelBg = panelBg

    -- 三个子标签：装备记录 / DKP记录 / 替补记录
    local WebDKP_LootList_subTabDefs = {
        { key = "loot", text = "拍卖记录" },
        { key = "dkp", text = "主团记录" },
        { key = "substitute", text = "替补记录" },
    }
    frame.subTabs = {}

    local function WebDKP_LootList_RefreshSubTabs()
        local mode = frame.currentMode or "loot"
        for _, btn in ipairs(frame.subTabs) do
            if btn.modeKey == mode then
                btn:LockHighlight()
            else
                btn:UnlockHighlight()
            end
        end
    end
    frame.RefreshSubTabs = WebDKP_LootList_RefreshSubTabs

    local function WebDKP_LootList_SetMode(modeKey)
        frame.currentMode = modeKey
        local sb = getglobal("WebDKP_LootListScrollScrollBar")
        if sb then sb:SetValue(0) end
        WebDKP_LootList_RefreshSubTabs()
        WebDKP_UpdateLootList()
    end

    for i, def in ipairs(WebDKP_LootList_subTabDefs) do
        local modeKey = def.key
        local subBtn = CreateFrame("Button", "WebDKP_LootListSubTab"..i, frame, "UIPanelButtonTemplate")
        subBtn:SetWidth(80)
        subBtn:SetHeight(24)
        subBtn:SetPoint("TOPLEFT", frame, "TOPLEFT", 15 + (i - 1) * 84, -10)
        subBtn:SetText(def.text)
        subBtn.modeKey = modeKey
        subBtn:SetScript("OnClick", function()
            WebDKP_LootList_SetMode(modeKey)
        end)
        frame.subTabs[i] = subBtn
    end

    -- 导出数据按钮（右上角）
    local exportBtn = CreateFrame("Button", "WebDKP_LootListExportButton", frame, "UIPanelButtonTemplate")
    exportBtn:SetWidth(90)
    exportBtn:SetHeight(24)
    exportBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -15, -10)
    exportBtn:SetText("导出数据")
    exportBtn:SetScript("OnClick", function()
        WebDKP_ExportCurrentData()
    end)
    frame.exportButton = exportBtn

    -- 列标题定义（全宽）
    local headers = {
        {name = "物品名称", width = 290, x = 15},
        {name = "获得者", width = 150, x = 315},
        {name = "花费", width = 70, x = 470},
        {name = "时间", width = 120, x = 545}
    }

    frame.headers = {}
    for i, h in ipairs(headers) do
        local hBtn = CreateFrame("Button", "WebDKP_LootListHeader"..i, frame, "UIPanelButtonTemplate")
        hBtn:SetWidth(h.width)
        hBtn:SetHeight(20)
        hBtn:SetPoint("TOPLEFT", frame, "TOPLEFT", h.x, -45)
        hBtn:SetText(h.name)
        if hBtn.SetNormalFontObject then
            hBtn:SetNormalFontObject("GameFontHighlightSmall")
        end
        if hBtn.SetHighlightFontObject then
            hBtn:SetHighlightFontObject("GameFontHighlightSmall")
        end
        if hBtn.Disable then
            hBtn:Disable()
        end
        frame.headers[i] = hBtn
    end

    -- 右侧可拖动滚动条
    local scroll = CreateFrame("ScrollFrame", "WebDKP_LootListScroll", frame, "FauxScrollFrameTemplate")
    scroll:SetWidth(720)
    scroll:SetHeight(11 * 22)
    scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 15, -68)
    scroll:SetScript("OnVerticalScroll", function()
        FauxScrollFrame_OnVerticalScroll(22, WebDKP_UpdateLootList)
    end)
    frame.scroll = scroll

    -- 创建可见行框架
    for i = 1, 11 do
        local lineFrame = CreateFrame("Frame", "WebDKP_LootListLine"..i, frame)
        lineFrame:SetID(i)
        lineFrame:SetWidth(700)
        lineFrame:SetHeight(20)
        lineFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 15, -(70 + (i-1)*22))

        local bg = lineFrame:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(lineFrame)
        bg:SetTexture(0.1, 0.1, 0.1, 0.15)
        lineFrame.bg = bg

        local itemText = lineFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        itemText:SetPoint("LEFT", lineFrame, "LEFT", 0, 0)
        itemText:SetWidth(290)
        itemText:SetJustifyH("LEFT")
        lineFrame.itemText = itemText

        local playerText = lineFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        playerText:SetPoint("LEFT", lineFrame, "LEFT", 300, 0)
        playerText:SetWidth(150)
        playerText:SetJustifyH("LEFT")
        lineFrame.playerText = playerText

        local costText = lineFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        costText:SetPoint("LEFT", lineFrame, "LEFT", 455, 0)
        costText:SetWidth(70)
        costText:SetJustifyH("LEFT")
        lineFrame.costText = costText

        local timeText = lineFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        timeText:SetPoint("LEFT", lineFrame, "LEFT", 530, 0)
        timeText:SetWidth(120)
        timeText:SetJustifyH("LEFT")
        lineFrame.timeText = timeText

        lineFrame:Hide()
    end

    frame.currentMode = "loot"
    if frame.RefreshSubTabs then frame.RefreshSubTabs() end

    return frame
end

local function WebDKP_LootList_EnsureFrameParts(frame)
    if not frame then
        return
    end

    if not frame.currentMode then
        frame.currentMode = "loot"
    end

    -- 滚动条
    if not getglobal("WebDKP_LootListScroll") then
        local scroll = CreateFrame("ScrollFrame", "WebDKP_LootListScroll", frame, "FauxScrollFrameTemplate")
        scroll:SetWidth(720)
        scroll:SetHeight(11 * 22)
        scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 15, -68)
        scroll:SetScript("OnVerticalScroll", function()
            FauxScrollFrame_OnVerticalScroll(22, WebDKP_UpdateLootList)
        end)
        frame.scroll = scroll
    end

    local headers = {
        {name = "物品名称", width = 290, x = 15},
        {name = "获得者", width = 150, x = 315},
        {name = "花费", width = 70, x = 470},
        {name = "时间", width = 120, x = 545}
    }

    if not frame.headers then
        frame.headers = {}
    end

    for i, h in ipairs(headers) do
        local header = frame.headers[i] or getglobal("WebDKP_LootListHeader"..i)
        if not header then
            header = CreateFrame("Button", "WebDKP_LootListHeader"..i, frame, "UIPanelButtonTemplate")
            header:SetWidth(h.width)
            header:SetHeight(20)
            header:SetPoint("TOPLEFT", frame, "TOPLEFT", h.x, -45)
            if header.SetNormalFontObject then
                header:SetNormalFontObject("GameFontHighlightSmall")
            end
            if header.SetHighlightFontObject then
                header:SetHighlightFontObject("GameFontHighlightSmall")
            end
            if header.Disable then
                header:Disable()
            end
        end
        frame.headers[i] = header
    end

    for i = 1, 11 do
        local lineFrame = getglobal("WebDKP_LootListLine"..i)
        if not lineFrame then
            lineFrame = CreateFrame("Frame", "WebDKP_LootListLine"..i, frame)
            lineFrame:SetID(i)
            lineFrame:SetWidth(700)
            lineFrame:SetHeight(20)
            lineFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 15, -(70 + (i-1)*22))
            lineFrame:Hide()
        end

        if not lineFrame.itemText then
            local itemText = lineFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            itemText:SetPoint("LEFT", lineFrame, "LEFT", 0, 0)
            itemText:SetWidth(290)
            itemText:SetJustifyH("LEFT")
            lineFrame.itemText = itemText
        end

        if not lineFrame.playerText then
            local playerText = lineFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            playerText:SetPoint("LEFT", lineFrame, "LEFT", 300, 0)
            playerText:SetWidth(150)
            playerText:SetJustifyH("LEFT")
            lineFrame.playerText = playerText
        end

        if not lineFrame.costText then
            if lineFrame.costOrLocationText then
                lineFrame.costText = lineFrame.costOrLocationText
            else
                local costText = lineFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                costText:SetPoint("LEFT", lineFrame, "LEFT", 455, 0)
                costText:SetWidth(70)
                costText:SetJustifyH("LEFT")
                lineFrame.costText = costText
            end
        end

        if not lineFrame.timeText then
            local timeText = lineFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            timeText:SetPoint("LEFT", lineFrame, "LEFT", 530, 0)
            timeText:SetWidth(120)
            timeText:SetJustifyH("LEFT")
            lineFrame.timeText = timeText
        end
    end
end


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

    -- 构建 姓名->地点 查询表（只读 WebDKP_DailySubRecords，不修改其结构）
    local locByKey = {}
    local locByName = {}
    if WebDKP_DailySubRecords then
        for dateKey, dayData in pairs(WebDKP_DailySubRecords) do
            if type(dayData) == "table" then
                local dp = string.sub(tostring(dateKey), 1, 10)
                for k, data in pairs(dayData) do
                    if type(data) == "table" then
                        local nm = data.name
                        if not nm and type(k) == "string" then nm = k end
                        local loc = data.location
                        if nm and loc then
                            locByName[nm] = loc
                            locByKey[nm .. "@" .. dp] = loc
                            if data.time then
                                locByKey[nm .. "@" .. string.sub(tostring(data.time), 1, 10)] = loc
                            end
                        end
                    end
                end
            end
        end
    end

    -- 从日志中按"加分事件"分组提取替补记录（结构与DKP记录一致）
    if WebDKP_Log then
        for key, entry in pairs(WebDKP_Log) do
            if type(entry) == "table" and key ~= "Version"
               and entry.reason and string.find(entry.reason, "替补")
               and not (entry.foritem == "true" or entry.foritem == true) then
                local playerCount = 0
                local locations = {}
                local dp = string.sub(tostring(entry.date or ""), 1, 10)
                if entry.awarded then
                    for playerName, _ in pairs(entry.awarded) do
                        playerCount = playerCount + 1
                        locations[playerName] = locByKey[playerName .. "@" .. dp]
                            or locByName[playerName] or "未知"
                    end
                end

                local tableid = entry.tableid or WebDKP_GetTableid()
                local tableName = WebDKP_GetTableNameById(tableid)
                local score = entry.points or 0
                local uniqueId = entry.uniqueId or (entry.reason .. " " .. (entry.date or ""))

                local record = {
                    item = entry.reason or "替补记录",
                    playerCount = playerCount,
                    score = score,
                    points = score,
                    time = entry.date or "未知",
                    date = entry.date or "未知",
                    tableid = tableid,
                    tableName = tableName,
                    uniqueId = uniqueId,
                    key = key,
                    timestamp = entry.timestamp,
                    awarded = entry.awarded,
                    locations = locations,
                    isSubstitute = true
                }
                table.insert(records, record)
            end
        end
    end

    -- 按时间倒序排序
    table.sort(records, function(a, b)
        if a.timestamp and b.timestamp then
            return a.timestamp > b.timestamp
        else
            return (a.time or "") > (b.time or "")
        end
    end)

    return records
end

-- 更新装备记录列表
function WebDKP_UpdateLootList()
    local frame = WebDKP_LootListFrame
    if not frame then
        return
    end

    WebDKP_LootList_EnsureFrameParts(frame)
    
    -- 获取当前模式
    local currentMode = frame.currentMode or "loot"
    if WebDKP_RosterPanel and WebDKP_RosterPanel:IsShown() and currentMode ~= "dkp" and currentMode ~= "substitute" then
        WebDKP_RosterPanel:Hide()
    end
    local headers = frame.headers or {}
    
    -- 更新4个列标题文本
    if currentMode == "loot" then
        if headers[1] then headers[1]:SetText("物品名称") end
        if headers[2] then headers[2]:SetText("获得者") end
        if headers[3] then headers[3]:SetText("花费") end
        if headers[4] then headers[4]:SetText("时间") end
    elseif currentMode == "dkp" then
        if headers[1] then headers[1]:SetText("项目/原因") end
        if headers[2] then headers[2]:SetText("人数") end
        if headers[3] then headers[3]:SetText("分数") end
        if headers[4] then headers[4]:SetText("时间") end
    elseif currentMode == "substitute" then
        if headers[1] then headers[1]:SetText("项目/原因") end
        if headers[2] then headers[2]:SetText("人数") end
        if headers[3] then headers[3]:SetText("分数") end
        if headers[4] then headers[4]:SetText("时间") end
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

    local numRecords = WebDKP_GetTableSize(records)
    local numDisplayed = 11
    local rowHeight = 22

    -- 更新右侧滚动条
    local scroll = getglobal("WebDKP_LootListScroll")
    local offset = 0
    if scroll then
        FauxScrollFrame_Update(scroll, numRecords, numDisplayed, rowHeight)
        offset = FauxScrollFrame_GetOffset(scroll)
    end

    -- 更新15行的数据
    for i = 1, numDisplayed do
        local recordIndex = offset + i
        local record = records[recordIndex]
        local lineFrame = getglobal("WebDKP_LootListLine"..i)

        if lineFrame and record then
            lineFrame:Show()
            lineFrame.recordIndex = recordIndex
            if not lineFrame.rosterHooked then
                lineFrame:EnableMouse(true)
                lineFrame:SetScript("OnMouseUp", function()
                    local hookMode = WebDKP_LootListFrame and WebDKP_LootListFrame.currentMode
                    if hookMode == "dkp" or hookMode == "substitute" then
                        local idx = this.recordIndex
                        local recs
                        if hookMode == "substitute" then
                            recs = WebDKP_GetSubstituteRecords()
                        else
                            recs = WebDKP_GetDKPRecords()
                        end
                        local rec = recs[idx]
                        if rec then WebDKP_ShowRecordRoster(rec) end
                    end
                end)
                lineFrame.rosterHooked = true
            end

            -- 根据模式显示不同的数据
            if currentMode == "loot" then
                local dkpValue = record.dkp or record.cost or "0"
                lineFrame.itemText:SetText(record.item or "未知物品")
                lineFrame.playerText:SetText(record.player or "")

                local displayPoints = tonumber(record.points) or 0
                lineFrame.costText:SetText(tostring(math.abs(displayPoints)))

                -- 截短时间，格式如: "06-08 12:34"
                local shortTime = record.time or "未知"
                if string.len(shortTime) >= 16 then
                    shortTime = string.sub(shortTime, 6, 16)
                end
                lineFrame.timeText:SetText(shortTime)
            elseif currentMode == "dkp" then
                local tableName = WebDKP_GetTableNameById(record.tableid)
                lineFrame.itemText:SetText(record.item or "未知项目")
                lineFrame.playerText:SetText(tostring(record.playerCount or "0"))
                lineFrame.costText:SetText(tostring(record.score or "0"))

                local shortTime = record.time or "未知"
                if string.len(shortTime) >= 16 then
                    shortTime = string.sub(shortTime, 6, 16)
                end
                lineFrame.timeText:SetText(shortTime)
            elseif currentMode == "substitute" then
                lineFrame.itemText:SetText(record.item or "替补")
                lineFrame.playerText:SetText(tostring(record.playerCount or "0"))
                lineFrame.costText:SetText(tostring(record.score or "0"))

                local shortTime = record.time or "未知"
                if string.len(shortTime) >= 16 then
                    shortTime = string.sub(shortTime, 6, 16)
                end
                lineFrame.timeText:SetText(shortTime)
            end

            -- 创建修改按钮
            if not lineFrame.editButton then
                lineFrame.editButton = CreateFrame("Button", "WebDKP_LootListLine"..i.."EditButton", lineFrame, "UIPanelButtonTemplate")
                lineFrame.editButton:SetWidth(18)
                lineFrame.editButton:SetHeight(18)
                lineFrame.editButton:SetText("改")
                lineFrame.editButton:SetPoint("RIGHT", lineFrame, "RIGHT", -26, 0)
                
                lineFrame.editButton:SetScript("OnClick", function()
                    local currentRecordIndex = this:GetParent().recordIndex
                    local currentRecords = {}
                    local currentMode = WebDKP_LootListFrame.currentMode or "loot"
                    if currentMode == "substitute" then
                        currentRecords = WebDKP_GetSubstituteRecords()
                    elseif currentMode == "dkp" then
                        currentRecords = WebDKP_GetDKPRecords()
                    else
                        currentRecords = WebDKP_GetLootRecords()
                    end
                    
                    local latestRecord = currentRecords[currentRecordIndex]
                    if not latestRecord then
                        WebDKP_Print("错误：无法找到索引为 " .. (currentRecordIndex or "nil") .. " 的记录")
                        return
                    end
                    
                    if currentMode == "dkp" then
                        local currentPoints = latestRecord.points or latestRecord.score or 0
                        local uniqueId = latestRecord.uniqueId
                        if WebDKP_ShowEditDKPDialog then
                            WebDKP_ShowEditDKPDialog(uniqueId, currentPoints)
                        else
                            WebDKP_Print("错误：修改DKP功能不可用")
                        end
                    elseif currentMode == "loot" then
                        local uniqueId = latestRecord.uniqueId
                        if WebDKP_ShowEditLootDialog then
                            WebDKP_ShowEditLootDialog(uniqueId, latestRecord.points or 0)
                        else
                            WebDKP_Print("错误：修改装备记录功能不可用")
                        end
                    elseif currentMode == "substitute" then
                        local uniqueId = latestRecord.uniqueId
                        if WebDKP_ShowEditSubstituteDialog then
                            WebDKP_ShowEditSubstituteDialog(uniqueId, latestRecord.item or "替补", latestRecord.points or latestRecord.score or 0)
                        else
                            WebDKP_Print("错误：修改替补记录功能不可用")
                        end
                    end
                end)
            end
            lineFrame.editButton:Show()
            
            -- 创建删除按钮
            if not lineFrame.deleteButton then
                lineFrame.deleteButton = CreateFrame("Button", "WebDKP_LootListLine"..i.."DeleteButton", lineFrame, "UIPanelButtonTemplate")
                lineFrame.deleteButton:SetWidth(18)
                lineFrame.deleteButton:SetHeight(18)
                lineFrame.deleteButton:SetText("X")
                lineFrame.deleteButton:SetPoint("RIGHT", lineFrame, "RIGHT", -4, 0)
                
                lineFrame.deleteButton:SetScript("OnClick", function()
                    local currentRecordIndex = this:GetParent().recordIndex
                    local currentRecords = {}
                    local currentMode = WebDKP_LootListFrame.currentMode or "loot"
                    if currentMode == "substitute" then
                        currentRecords = WebDKP_GetSubstituteRecords()
                    elseif currentMode == "dkp" then
                        currentRecords = WebDKP_GetDKPRecords()
                    else
                        currentRecords = WebDKP_GetLootRecords()
                    end
                    
                    local latestRecord = currentRecords[currentRecordIndex]
                    if not latestRecord then
                        WebDKP_Print("错误：无法找到索引为 " .. (currentRecordIndex or "nil") .. " 的记录")
                        return
                    end
                    
                    WebDKP_CurrentRecord = {}
                    if currentMode == "dkp" then
                        WebDKP_CurrentRecord.item = latestRecord.reason or latestRecord.item or "未知项目"
                        WebDKP_CurrentRecord.time = latestRecord.date or latestRecord.time or date()
                        WebDKP_CurrentRecord.player = latestRecord.name or latestRecord.player or "未知玩家"
                        WebDKP_CurrentRecord.tableid = latestRecord.tableid
                        WebDKP_CurrentRecord.score = latestRecord.score
                    elseif currentMode == "substitute" then
                        WebDKP_CurrentRecord.item = latestRecord.reason or latestRecord.item or "替补记录"
                        WebDKP_CurrentRecord.time = latestRecord.date or latestRecord.time or date()
                        WebDKP_CurrentRecord.player = latestRecord.name or latestRecord.player or "未知玩家"
                        WebDKP_CurrentRecord.location = latestRecord.location or "未知"
                    elseif currentMode == "loot" then
                        WebDKP_CurrentRecord.item = latestRecord.reason or "未知装备"
                        WebDKP_CurrentRecord.time = latestRecord.date or latestRecord.time or date()
                        WebDKP_CurrentRecord.player = latestRecord.name or latestRecord.player or "未知玩家"
                        WebDKP_CurrentRecord.points = latestRecord.points or 0
                    end
                    WebDKP_CurrentRecord.rawRecord = latestRecord
                    
                    WebDKP_CurrentRecordIndex = currentRecordIndex
                    WebDKP_CurrentRecordMode = WebDKP_LootListFrame.currentMode
                    WebDKP_CurrentRecordUniqueId = latestRecord.uniqueId or currentRecordIndex
                    
                    if not StaticPopupDialogs then
                        StaticPopupDialogs = {}
                    end
                    
                    if not StaticPopupDialogs["CONFIRM_DELETE_RECORD"] then
                        StaticPopupDialogs["CONFIRM_DELETE_RECORD"] = {
                            text = "确定要删除这条记录吗？",
                            button1 = "确定",
                            button2 = "取消",
                            OnAccept = function()
                                StaticPopupDialogs["CONFIRM_DELETE_RECORD"]._deleteCallback()
                            end,
                            timeout = 0,
                            whileDead = true,
                            hideOnEscape = true
                        }
                    end
                    
                    local dialogText = "确定要删除这条记录吗？"
                    if WebDKP_CurrentRecordMode == "loot" then
                        dialogText = "确定要删除拍卖记录: " .. (WebDKP_CurrentRecord.item or "未知物品") .. " 吗？"
                    elseif WebDKP_CurrentRecordMode == "dkp" then
                        dialogText = "确定要删除主团记录: " .. (WebDKP_CurrentRecord.item or "未知项目") .. " 吗？"
                    elseif WebDKP_CurrentRecordMode == "substitute" then
                        dialogText = "确定要删除整条替补记录: " .. (WebDKP_CurrentRecord.item or "替补记录") .. " 吗？"
                    end
                    StaticPopupDialogs["CONFIRM_DELETE_RECORD"].text = dialogText
                    
                    StaticPopupDialogs["CONFIRM_DELETE_RECORD"]._deleteCallback = function()
                        if WebDKP_CurrentRecordMode and WebDKP_CurrentRecord then
                            local success = false
                            if WebDKP_CurrentRecordMode == "dkp" then
                                if WebDKP_DeleteDKPRecordByItemAndTime then
                                    success = WebDKP_DeleteDKPRecordByItemAndTime(
                                        WebDKP_CurrentRecord.item, 
                                        WebDKP_CurrentRecord.time
                                    )
                                end
                            elseif WebDKP_CurrentRecordMode == "substitute" then
                                if WebDKP_DeleteDKPRecordByItemAndTime then
                                    success = WebDKP_DeleteDKPRecordByItemAndTime(
                                        WebDKP_CurrentRecord.item,
                                        WebDKP_CurrentRecord.time
                                    )
                                elseif WebDKP_DeleteSubstituteRecordByItemAndTime and WebDKP_CurrentRecord.player then
                                    success = WebDKP_DeleteSubstituteRecordByItemAndTime(
                                        WebDKP_CurrentRecord.player,
                                        WebDKP_CurrentRecord.item,
                                        WebDKP_CurrentRecord.time
                                    )
                                end
                            elseif WebDKP_CurrentRecordMode == "loot" then
                                if WebDKP_DeleteLootRecord then
                                    success = WebDKP_DeleteLootRecord(
                                        WebDKP_CurrentRecord.item,
                                        WebDKP_CurrentRecord.player,
                                        WebDKP_CurrentRecord.time
                                    )
                                end
                            end
                            
                            if success then
                                if WebDKP_SaveToDisk then
                                    WebDKP_SaveToDisk()
                                end
                            else
                                WebDKP_Print("记录删除失败")
                            end
                        end
                        
                        if WebDKP_UpdateLootList then
                            WebDKP_UpdateLootList()
                        end
                    end
                    
                    StaticPopup_Show("CONFIRM_DELETE_RECORD")
                end)
            end
            lineFrame.deleteButton:Show()
        else
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

-- ============ DKP记录人员名单：查看与增删 ============

-- 根据记录定位 WebDKP_Log 中对应条目（优先用 key，回退按 uniqueId）
function WebDKP_FindDKPLogEntry(record)
    if not WebDKP_Log or not record then return nil end
    if record.key and type(WebDKP_Log[record.key]) == "table" then
        return record.key, WebDKP_Log[record.key]
    end
    for k, e in pairs(WebDKP_Log) do
        if k ~= "Version" and type(e) == "table" then
            local uid = e.uniqueId or ((e.reason or "") .. " " .. (e.date or ""))
            if record.uniqueId and uid == record.uniqueId then
                return k, e
            end
        end
    end
    return nil
end

-- 对某玩家当前列表DKP加/减 delta（镜像现有重算逻辑）
function WebDKP_AdjustPlayerDkp(playerName, tableid, delta)
    if not WebDKP_DkpTable or not WebDKP_DkpTable[playerName] then return false end
    tableid = tableid or WebDKP_GetTableid()
    local dkpField = "dkp_" .. tableid
    if type(WebDKP_DkpTable[playerName]) == "number" then
        WebDKP_DkpTable[playerName] = WebDKP_DkpTable[playerName] + delta
    else
        local cur = tonumber(WebDKP_DkpTable[playerName][dkpField])
            or tonumber(WebDKP_DkpTable[playerName].dkp)
            or tonumber(WebDKP_DkpTable[playerName].points) or 0
        if WebDKP_DkpTable[playerName][dkpField] ~= nil then
            WebDKP_DkpTable[playerName][dkpField] = cur + delta
        elseif WebDKP_DkpTable[playerName].dkp ~= nil then
            WebDKP_DkpTable[playerName].dkp = cur + delta
        elseif WebDKP_DkpTable[playerName].points ~= nil then
            WebDKP_DkpTable[playerName].points = cur + delta
        else
            WebDKP_DkpTable[playerName][dkpField] = cur + delta
        end
    end
    return true
end

-- 从某条DKP记录移除一名玩家（同步扣回其本条所得分数）
function WebDKP_RemovePlayerFromDKPRecord(record, playerName)
    local key, entry = WebDKP_FindDKPLogEntry(record)
    if not entry or not entry.awarded or not entry.awarded[playerName] then
        WebDKP_Print("错误：找不到该记录或玩家")
        return false
    end
    local info = entry.awarded[playerName]
    local pts = tonumber(entry.points) or 0
    if type(info) == "table" then
        pts = tonumber(info.points or info.dkp or info.value or pts) or pts
    elseif type(info) == "number" then
        pts = info
    end
    local tableid = entry.tableid or WebDKP_GetTableid()
    WebDKP_AdjustPlayerDkp(playerName, tableid, -pts)
    entry.awarded[playerName] = nil
    if WebDKP_SaveToDisk then WebDKP_SaveToDisk() end
    if WebDKP_UpdateTable then WebDKP_UpdateTable() end
    WebDKP_Print("已从记录中移除 " .. playerName .. "，扣回DKP " .. tostring(pts))
    return true
end

-- 向某条DKP记录添加一名玩家（按该条分数给分）
function WebDKP_AddPlayerToDKPRecord(record, playerName)
    if not playerName or playerName == "" then return false end
    local key, entry = WebDKP_FindDKPLogEntry(record)
    if not entry then
        WebDKP_Print("错误：找不到该记录")
        return false
    end
    if not entry.awarded then entry.awarded = {} end
    if entry.awarded[playerName] then
        WebDKP_Print("玩家 " .. playerName .. " 已在该记录中")
        return false
    end
    local pts = tonumber(entry.points) or 0
    local tableid = entry.tableid or WebDKP_GetTableid()
    if not WebDKP_DkpTable[playerName] then
        local pclass = "未知"
        if WebDKP_GetPlayerClass then
            pclass = WebDKP_GetPlayerClass(playerName) or "未知"
        end
        WebDKP_DkpTable[playerName] = {
            ["class"] = pclass,
            ["dkp_" .. tableid] = 0,
            ["Selected"] = false,
            ["IsSub"] = false
        }
        WebDKP_Print("提示：" .. playerName .. " 不在名单中，已新建条目")
    end
    entry.awarded[playerName] = { points = pts }
    WebDKP_AdjustPlayerDkp(playerName, tableid, pts)
    if WebDKP_SaveToDisk then WebDKP_SaveToDisk() end
    if WebDKP_UpdateTableToShow then WebDKP_UpdateTableToShow() end
    if WebDKP_UpdateTable then WebDKP_UpdateTable() end
    WebDKP_Print("已添加 " .. playerName .. " 到记录，给分 " .. tostring(pts))
    return true
end

-- 构建（懒加载）人员名单覆盖面板
function WebDKP_EnsureRosterPanel()
    if WebDKP_RosterPanel then return WebDKP_RosterPanel end
    local parent = WebDKP_LootListFrame
    if not parent then return nil end

    local panel = CreateFrame("Frame", "WebDKP_RosterPanel", parent)
    panel:SetAllPoints(parent)
    if panel.SetFrameLevel and parent.GetFrameLevel then
        panel:SetFrameLevel(parent:GetFrameLevel() + 20)
    end
    panel:EnableMouse(true)

    local bg = panel:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(panel)
    bg:SetTexture(0.06, 0.06, 0.08, 0.98)
    panel.bg = bg

    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", panel, "TOPLEFT", 20, -14)
    title:SetText("人员名单")
    panel.title = title

    local backBtn = CreateFrame("Button", "WebDKP_RosterBackButton", panel, "UIPanelButtonTemplate")
    backBtn:SetWidth(90)
    backBtn:SetHeight(22)
    backBtn:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -15, -12)
    backBtn:SetText("完成/返回")
    backBtn:SetScript("OnClick", function()
        local record = WebDKP_CurrentRosterRecord
        if WebDKP_PendingDeletes then
            local toRemove = {}
            for pn, _ in pairs(WebDKP_PendingDeletes) do
                table.insert(toRemove, pn)
            end
            for i = 1, table.getn(toRemove) do
                WebDKP_RemovePlayerFromDKPRecord(record, toRemove[i])
            end
            WebDKP_PendingDeletes = {}
        end
        local key, entry = WebDKP_FindDKPLogEntry(record)
        if key and entry and (not entry.awarded or not next(entry.awarded)) then
            WebDKP_Log[key] = nil
            if WebDKP_SaveToDisk then WebDKP_SaveToDisk() end
            if WebDKP_UpdateTable then WebDKP_UpdateTable() end
            WebDKP_Print("该记录已无人员，已删除整条记录")
        end
        WebDKP_RosterPanel:Hide()
        if WebDKP_UpdateLootList then WebDKP_UpdateLootList() end
    end)

    local hdr = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hdr:SetPoint("TOPLEFT", panel, "TOPLEFT", 24, -40)
    hdr:SetText("姓名")
    panel.hdr = hdr

    local locHdr = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    locHdr:SetPoint("TOPLEFT", panel, "TOPLEFT", 194, -40)
    locHdr:SetText("地点")
    panel.locHdr = locHdr

    -- 右侧：编辑该条主团(DKP)记录（分值/原因）
    local editTitle = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    editTitle:SetPoint("TOPLEFT", panel, "TOPLEFT", 510, -52)
    editTitle:SetText("编辑该条记录")
    panel.editTitle = editTitle

    local ptLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ptLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", 510, -88)
    ptLabel:SetText("分值:")
    panel.ptLabel = ptLabel

    local ptBox = CreateFrame("EditBox", "WebDKP_RosterEditPoints", panel, "InputBoxTemplate")
    ptBox:SetWidth(90)
    ptBox:SetHeight(20)
    ptBox:SetPoint("LEFT", ptLabel, "RIGHT", 12, 0)
    ptBox:SetAutoFocus(false)
    ptBox:SetMaxLetters(10)
    ptBox:SetScript("OnEscapePressed", function() this:ClearFocus() end)
    panel.ptBox = ptBox

    local rsLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    rsLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", 510, -120)
    rsLabel:SetText("原因:")
    panel.rsLabel = rsLabel

    local rsBox = CreateFrame("EditBox", "WebDKP_RosterEditReason", panel, "InputBoxTemplate")
    rsBox:SetWidth(180)
    rsBox:SetHeight(20)
    rsBox:SetPoint("LEFT", rsLabel, "RIGHT", 12, 0)
    rsBox:SetAutoFocus(false)
    rsBox:SetMaxLetters(60)
    rsBox:SetScript("OnEscapePressed", function() this:ClearFocus() end)
    panel.rsBox = rsBox

    local saveBtn = CreateFrame("Button", "WebDKP_RosterEditSave", panel, "UIPanelButtonTemplate")
    saveBtn:SetWidth(110)
    saveBtn:SetHeight(24)
    saveBtn:SetPoint("TOPLEFT", panel, "TOPLEFT", 510, -156)
    saveBtn:SetText("保存修改")
    saveBtn:SetScript("OnClick", function()
        local record = WebDKP_CurrentRosterRecord
        if not record then return end
        local uid = record.uniqueId
        if not uid then
            WebDKP_Print("错误：该记录缺少标识，无法修改")
            return
        end
        local pBox = getglobal("WebDKP_RosterEditPoints")
        local rBox = getglobal("WebDKP_RosterEditReason")
        local newPoints = pBox and pBox:GetText() or ""
        local newReason = rBox and rBox:GetText() or ""
        if not tonumber(newPoints) then
            WebDKP_Print("错误：分值必须是数字")
            return
        end
        local ok = false
        if record.isSubstitute then
            if newReason == "" then newReason = record.item or "替补" end
            if WebDKP_EditSubstituteRecord then
                ok = WebDKP_EditSubstituteRecord(uid, newReason, newPoints)
            else
                WebDKP_Print("错误：修改替补记录功能不可用")
            end
        else
            if WebDKP_EditDKPRecord then
                ok = WebDKP_EditDKPRecord(uid, newPoints, newReason)
            else
                WebDKP_Print("错误：修改主团记录功能不可用")
            end
        end
        if ok then
            record.points = tonumber(newPoints)
            record.score = tonumber(newPoints)
            if newReason and newReason ~= "" then record.item = newReason end
        end
        WebDKP_UpdateRosterList()
    end)
    panel.saveBtn = saveBtn

    local editHint = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    editHint:SetPoint("TOPLEFT", panel, "TOPLEFT", 510, -190)
    editHint:SetWidth(240)
    editHint:SetJustifyH("LEFT")
    editHint:SetText("提示：修改分值会同步调整该条所有人员的DKP。")
    panel.editHint = editHint

    local scroll = CreateFrame("ScrollFrame", "WebDKP_RosterScroll", panel, "FauxScrollFrameTemplate")
    scroll:SetWidth(470)
    scroll:SetHeight(10 * 24)
    scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 24, -58)
    scroll:SetScript("OnVerticalScroll", function()
        FauxScrollFrame_OnVerticalScroll(24, WebDKP_UpdateRosterList)
    end)
    panel.scroll = scroll

    for i = 1, 10 do
        local row = CreateFrame("Frame", "WebDKP_RosterLine" .. i, panel)
        row:SetWidth(470)
        row:SetHeight(22)
        row:SetPoint("TOPLEFT", panel, "TOPLEFT", 24, -(58 + (i - 1) * 24))

        local rbg = row:CreateTexture(nil, "BACKGROUND")
        rbg:SetAllPoints(row)
        rbg:SetTexture(0.15, 0.15, 0.18, 0.4)

        local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        nameText:SetPoint("LEFT", row, "LEFT", 6, 0)
        nameText:SetWidth(150)
        nameText:SetJustifyH("LEFT")
        row.nameText = nameText

        local strike = row:CreateTexture(nil, "OVERLAY")
        strike:SetTexture(1, 0.3, 0.3, 0.9)
        strike:SetPoint("LEFT", nameText, "LEFT", 0, 0)
        strike:SetHeight(2)
        strike:SetWidth(1)
        strike:Hide()
        row.strike = strike

        local locText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        locText:SetPoint("LEFT", row, "LEFT", 165, 0)
        locText:SetWidth(230)
        locText:SetJustifyH("LEFT")
        row.locText = locText

        local removeBtn = CreateFrame("Button", "WebDKP_RosterLine" .. i .. "Remove", row, "UIPanelButtonTemplate")
        removeBtn:SetWidth(50)
        removeBtn:SetHeight(18)
        removeBtn:SetText("移除")
        removeBtn:SetPoint("LEFT", row, "LEFT", 405, 0)
        removeBtn:SetScript("OnClick", function()
            local pn = this:GetParent().playerName
            if pn and pn ~= "" then
                if not WebDKP_PendingDeletes then WebDKP_PendingDeletes = {} end
                if WebDKP_PendingDeletes[pn] then
                    WebDKP_PendingDeletes[pn] = nil
                else
                    WebDKP_PendingDeletes[pn] = true
                end
                WebDKP_UpdateRosterList()
            end
        end)
        row.removeButton = removeBtn

        row:Hide()
    end

    local addLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    addLabel:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 24, 16)
    addLabel:SetText("添加人员:")
    panel.addLabel = addLabel

    local addBox = CreateFrame("EditBox", "WebDKP_RosterAddBox", panel, "InputBoxTemplate")
    addBox:SetWidth(160)
    addBox:SetHeight(20)
    addBox:SetPoint("LEFT", addLabel, "RIGHT", 12, 0)
    addBox:SetAutoFocus(false)
    addBox:SetMaxLetters(30)
    addBox:SetScript("OnEscapePressed", function() this:ClearFocus() end)
    addBox:SetScript("OnEnterPressed", function()
        if WebDKP_RosterAddButton then WebDKP_RosterAddButton:Click() end
    end)
    panel.addBox = addBox

    local addBtn = CreateFrame("Button", "WebDKP_RosterAddButton", panel, "UIPanelButtonTemplate")
    addBtn:SetWidth(60)
    addBtn:SetHeight(22)
    addBtn:SetText("添加")
    addBtn:SetPoint("LEFT", addBox, "RIGHT", 10, 0)
    addBtn:SetScript("OnClick", function()
        local box = getglobal("WebDKP_RosterAddBox")
        local pn = box and box:GetText() or ""
        if pn and pn ~= "" then
            if WebDKP_AddPlayerToDKPRecord(WebDKP_CurrentRosterRecord, pn) then
                box:SetText("")
            end
            WebDKP_UpdateRosterList()
        end
    end)

    panel:Hide()
    WebDKP_RosterPanel = panel
    return panel
end

-- 刷新名单行
function WebDKP_UpdateRosterList()
    local panel = WebDKP_RosterPanel
    if not panel or not panel:IsShown() then return end
    local record = WebDKP_CurrentRosterRecord
    local key, entry = WebDKP_FindDKPLogEntry(record)
    local names = {}
    if entry and entry.awarded then
        for n, _ in pairs(entry.awarded) do
            table.insert(names, n)
        end
        table.sort(names)
    end
    panel.names = names
    local locs = (record and record.locations) or {}
    local showEdit = (record ~= nil)
    if panel.editTitle then if showEdit then panel.editTitle:Show() else panel.editTitle:Hide() end end
    if panel.ptLabel then if showEdit then panel.ptLabel:Show() else panel.ptLabel:Hide() end end
    if panel.rsLabel then if showEdit then panel.rsLabel:Show() else panel.rsLabel:Hide() end end
    if panel.saveBtn then if showEdit then panel.saveBtn:Show() else panel.saveBtn:Hide() end end
    if panel.editHint then if showEdit then panel.editHint:Show() else panel.editHint:Hide() end end
    if panel.ptBox then if showEdit then panel.ptBox:Show() else panel.ptBox:Hide() end end
    if panel.rsBox then if showEdit then panel.rsBox:Show() else panel.rsBox:Hide() end end

    local total = table.getn(names)
    if panel.title then
        panel.title:SetText("人员名单 - " .. (record.item or "记录") .. "    (共 " .. total .. " 人)")
    end

    local numDisplayed = 10
    local rowHeight = 24
    local scroll = getglobal("WebDKP_RosterScroll")
    local offset = 0
    if scroll then
        FauxScrollFrame_Update(scroll, total, numDisplayed, rowHeight)
        offset = FauxScrollFrame_GetOffset(scroll)
    end

    for i = 1, numDisplayed do
        local row = getglobal("WebDKP_RosterLine" .. i)
        local name = names[offset + i]
        if row and name then
            row.playerName = name
            row.nameText:SetText(name)
            if row.locText then row.locText:SetText(locs[name] or "") end
            local pending = WebDKP_PendingDeletes and WebDKP_PendingDeletes[name]
            if pending then
                row.nameText:SetTextColor(0.6, 0.6, 0.6)
                if row.strike then
                    row.strike:SetWidth(row.nameText:GetStringWidth() + 2)
                    row.strike:Show()
                end
                if row.removeButton then row.removeButton:SetText("恢复") end
            else
                row.nameText:SetTextColor(1, 1, 1)
                if row.strike then row.strike:Hide() end
                if row.removeButton then row.removeButton:SetText("移除") end
            end
            row:Show()
            if row.removeButton then row.removeButton:Show() end
        elseif row then
            row.playerName = nil
            if row.locText then row.locText:SetText("") end
            if row.strike then row.strike:Hide() end
            row:Hide()
        end
    end
end

-- 打开某条记录的人员名单
function WebDKP_ShowRecordRoster(record)
    if not record then return end
    local panel = WebDKP_EnsureRosterPanel()
    if not panel then return end
    WebDKP_CurrentRosterRecord = record
    WebDKP_PendingDeletes = {}
    local pBox0 = getglobal("WebDKP_RosterEditPoints")
    local rBox0 = getglobal("WebDKP_RosterEditReason")
    if pBox0 then pBox0:SetText(tostring(record.points or record.score or 0)) end
    if rBox0 then rBox0:SetText(record.item or "") end
    local sb = getglobal("WebDKP_RosterScrollScrollBar")
    if sb then sb:SetValue(0) end
    panel:Show()
    WebDKP_UpdateRosterList()
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
