-- ADKP_LootList.lua
-- 装备记录功能实现
-- 依赖: ADKP.lua (必须在本文件之后加载) 没用了 查看用  已经整合到ADKP.lua 中

-- 创建装备记录窗口框架
function ADKP_CreateLootListFrame()
    -- 如果框架已存在，直接返回
    if ADKP_LootListFrame then
        return ADKP_LootListFrame
    end

    -- 全宽数据面板：铺满主窗口内部，底部留出标签条空间
    local frame = CreateFrame("Frame", "ADKP_LootListFrame", ADKP_Frame)
    frame:SetPoint("TOPLEFT", ADKP_Frame, "TOPLEFT", 12, -44)
    frame:SetPoint("BOTTOMRIGHT", ADKP_Frame, "BOTTOMRIGHT", -12, 55)
    frame:EnableMouse(true)
    -- 抬高层级，覆盖左侧名单等内容
    if ADKP_Frame and ADKP_Frame.GetFrameLevel then
        frame:SetFrameLevel(ADKP_Frame:GetFrameLevel() + 10)
    end

    -- 不透明背景，遮住下层的玩家名单
    local panelBg = frame:CreateTexture(nil, "BACKGROUND")
    panelBg:SetAllPoints(frame)
    panelBg:SetTexture(0.06, 0.06, 0.08, 0.95)
    frame.panelBg = panelBg

    -- 三个子标签：装备记录 / DKP记录 / 替补记录
    local ADKP_LootList_subTabDefs = {
        { key = "loot", text = "拍卖记录" },
        { key = "dkp", text = "主团记录" },
        { key = "substitute", text = "替补记录" },
    }
    frame.subTabs = {}

    local function ADKP_LootList_RefreshSubTabs()
        local mode = frame.currentMode or "loot"
        for _, btn in ipairs(frame.subTabs) do
            if btn.modeKey == mode then
                btn:LockHighlight()
            else
                btn:UnlockHighlight()
            end
        end
    end
    frame.RefreshSubTabs = ADKP_LootList_RefreshSubTabs

    local function ADKP_LootList_SetMode(modeKey)
        frame.currentMode = modeKey
        local sb = getglobal("ADKP_LootListScrollScrollBar")
        if sb then sb:SetValue(0) end
        ADKP_LootList_RefreshSubTabs()
        ADKP_UpdateLootList()
    end

    for i, def in ipairs(ADKP_LootList_subTabDefs) do
        local modeKey = def.key
        local subBtn = CreateFrame("Button", "ADKP_LootListSubTab"..i, frame, "UIPanelButtonTemplate")
        subBtn:SetWidth(80)
        subBtn:SetHeight(24)
        subBtn:SetPoint("TOPLEFT", frame, "TOPLEFT", 15 + (i - 1) * 84, -10)
        subBtn:SetText(def.text)
        subBtn.modeKey = modeKey
        subBtn:SetScript("OnClick", function()
            ADKP_LootList_SetMode(modeKey)
        end)
        frame.subTabs[i] = subBtn
    end

    -- 导出数据功能已移除（SuperWoW ExportFile 对中文文件名失败，且与备份重复）

    -- 列标题定义（全宽）
    local headers = {
        {name = "物品名称", width = 290, x = 15},
        {name = "获得者", width = 150, x = 315},
        {name = "花费", width = 70, x = 470},
        {name = "时间", width = 120, x = 545}
    }

    frame.headers = {}
    for i, h in ipairs(headers) do
        local hBtn = CreateFrame("Button", "ADKP_LootListHeader"..i, frame, "UIPanelButtonTemplate")
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
    local scroll = CreateFrame("ScrollFrame", "ADKP_LootListScroll", frame, "FauxScrollFrameTemplate")
    scroll:SetWidth(720)
    scroll:SetHeight(11 * 22)
    scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 15, -68)
    scroll:SetScript("OnVerticalScroll", function()
        FauxScrollFrame_OnVerticalScroll(22, ADKP_UpdateLootList)
    end)
    frame.scroll = scroll

    -- 创建可见行框架
    for i = 1, 11 do
        local lineFrame = CreateFrame("Frame", "ADKP_LootListLine"..i, frame)
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

    -- ===== 备份/恢复/自动备份/导入（从系统控制迁移至此，放在表格下方）=====
    local backupBtn = CreateFrame("Button", "ADKP_LootListBackupButton", frame, "UIPanelButtonTemplate")
    backupBtn:SetWidth(110)
    backupBtn:SetHeight(24)
    backupBtn:SetPoint("TOPLEFT", frame, "TOPLEFT", 15, -313)
    backupBtn:SetText("备份数据")
    backupBtn:SetScript("OnClick", function() ADKP_BackupData() end)

    local restoreBtn = CreateFrame("Button", "ADKP_LootListRestoreButton", frame, "UIPanelButtonTemplate")
    restoreBtn:SetWidth(130)
    restoreBtn:SetHeight(24)
    restoreBtn:SetPoint("TOPLEFT", frame, "TOPLEFT", 135, -313)
    restoreBtn:SetText("恢复最新数据")
    restoreBtn:SetScript("OnClick", function() ADKP_RestoreData() end)

    local autoCheck = CreateFrame("CheckButton", "ADKP_LootListAutoBackupCheck", frame, "OptionsCheckButtonTemplate")
    autoCheck:SetWidth(20)
    autoCheck:SetHeight(20)
    autoCheck:SetPoint("TOPLEFT", frame, "TOPLEFT", 280, -313)
    autoCheck:SetChecked(WebDKP_Options and WebDKP_Options["AutoBackupEnabled"] and true or false)
    autoCheck:SetScript("OnClick", function()
        if not WebDKP_Options then WebDKP_Options = {} end
        WebDKP_Options["AutoBackupEnabled"] = autoCheck:GetChecked() and true or false
        if ADKP_SaveToDisk then ADKP_SaveToDisk() end
    end)
    local autoLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    autoLabel:SetPoint("LEFT", autoCheck, "RIGHT", 5, 0)
    autoLabel:SetText("自动备份")

    -- 导入指定版本：标签 + 输入框 + 导入按钮
    local importLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    importLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 15, -348)
    importLabel:SetText("导入指定版本:")

    local importEdit = CreateFrame("EditBox", "ADKP_LootListImportEditBox", frame, "InputBoxTemplate")
    importEdit:SetWidth(200)
    importEdit:SetHeight(20)
    importEdit:SetPoint("TOPLEFT", frame, "TOPLEFT", 115, -345)
    importEdit:SetAutoFocus(false)
    importEdit:SetScript("OnEscapePressed", function() importEdit:ClearFocus() end)

    local importBtn = CreateFrame("Button", "ADKP_LootListImportBtn", frame, "UIPanelButtonTemplate")
    importBtn:SetWidth(60)
    importBtn:SetHeight(24)
    importBtn:SetPoint("TOPLEFT", frame, "TOPLEFT", 325, -345)
    importBtn:SetText("导入")
    importBtn:SetScript("OnClick", function() ADKP_RequestImportVersion() end)

    frame.currentMode = "loot"
    if frame.RefreshSubTabs then frame.RefreshSubTabs() end

    return frame
end

local function ADKP_LootList_EnsureFrameParts(frame)
    if not frame then
        return
    end

    if not frame.currentMode then
        frame.currentMode = "loot"
    end

    -- 滚动条
    if not getglobal("ADKP_LootListScroll") then
        local scroll = CreateFrame("ScrollFrame", "ADKP_LootListScroll", frame, "FauxScrollFrameTemplate")
        scroll:SetWidth(720)
        scroll:SetHeight(11 * 22)
        scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 15, -68)
        scroll:SetScript("OnVerticalScroll", function()
            FauxScrollFrame_OnVerticalScroll(22, ADKP_UpdateLootList)
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
        local header = frame.headers[i] or getglobal("ADKP_LootListHeader"..i)
        if not header then
            header = CreateFrame("Button", "ADKP_LootListHeader"..i, frame, "UIPanelButtonTemplate")
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
        local lineFrame = getglobal("ADKP_LootListLine"..i)
        if not lineFrame then
            lineFrame = CreateFrame("Frame", "ADKP_LootListLine"..i, frame)
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


function ADKP_GetTableSize(table)
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
function ADKP_GetLootRecords()
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
                    
                    -- 创建唯一标识符 - 使用与ADKP_Log中相同的格式
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
function ADKP_GetDKPRecords()
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
                local tableid = entry.tableid or ADKP_GetTableid()
                -- 使用统一的函数获取表格名称
                local tableName = ADKP_GetTableNameById(tableid)
                
                -- 直接使用entry.points作为分数，保留正负号
                local score = entry.points or 0
                
                -- 创建唯一标识符 - 使用与ADKP_Log中相同的格式
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
function ADKP_GetSubstituteRecords()
    local records = {}

    -- 构建 姓名->地点 查询表（只读 ADKP_DailySubRecords，不修改其结构）
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

                local tableid = entry.tableid or ADKP_GetTableid()
                local tableName = ADKP_GetTableNameById(tableid)
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
function ADKP_UpdateLootList()
    local frame = ADKP_LootListFrame
    if not frame then
        return
    end

    ADKP_LootList_EnsureFrameParts(frame)
    
    -- 获取当前模式
    local currentMode = frame.currentMode or "loot"
    if ADKP_RosterPanel and ADKP_RosterPanel:IsShown() and currentMode ~= "dkp" and currentMode ~= "substitute" then
        ADKP_RosterPanel:Hide()
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
        records = ADKP_GetSubstituteRecords()
    elseif currentMode == "dkp" then
        records = ADKP_GetDKPRecords()
    else
        records = ADKP_GetLootRecords()
    end

    local numRecords = ADKP_GetTableSize(records)
    local numDisplayed = 11
    local rowHeight = 22

    -- 更新右侧滚动条
    local scroll = getglobal("ADKP_LootListScroll")
    local offset = 0
    if scroll then
        FauxScrollFrame_Update(scroll, numRecords, numDisplayed, rowHeight)
        offset = FauxScrollFrame_GetOffset(scroll)
    end

    -- 更新15行的数据
    for i = 1, numDisplayed do
        local recordIndex = offset + i
        local record = records[recordIndex]
        local lineFrame = getglobal("ADKP_LootListLine"..i)

        if lineFrame and record then
            lineFrame:Show()
            lineFrame.recordIndex = recordIndex
            if not lineFrame.rosterHooked then
                lineFrame:EnableMouse(true)
                lineFrame:SetScript("OnMouseUp", function()
                    local hookMode = ADKP_LootListFrame and ADKP_LootListFrame.currentMode
                    if hookMode == "dkp" or hookMode == "substitute" then
                        local idx = this.recordIndex
                        local recs
                        if hookMode == "substitute" then
                            recs = ADKP_GetSubstituteRecords()
                        else
                            recs = ADKP_GetDKPRecords()
                        end
                        local rec = recs[idx]
                        if rec then ADKP_ShowRecordRoster(rec) end
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
                local tableName = ADKP_GetTableNameById(record.tableid)
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
                lineFrame.editButton = CreateFrame("Button", "ADKP_LootListLine"..i.."EditButton", lineFrame, "UIPanelButtonTemplate")
                lineFrame.editButton:SetWidth(18)
                lineFrame.editButton:SetHeight(18)
                lineFrame.editButton:SetText("改")
                lineFrame.editButton:SetPoint("RIGHT", lineFrame, "RIGHT", -26, 0)
                
                lineFrame.editButton:SetScript("OnClick", function()
                    local currentRecordIndex = this:GetParent().recordIndex
                    local currentRecords = {}
                    local currentMode = ADKP_LootListFrame.currentMode or "loot"
                    if currentMode == "substitute" then
                        currentRecords = ADKP_GetSubstituteRecords()
                    elseif currentMode == "dkp" then
                        currentRecords = ADKP_GetDKPRecords()
                    else
                        currentRecords = ADKP_GetLootRecords()
                    end
                    
                    local latestRecord = currentRecords[currentRecordIndex]
                    if not latestRecord then
                        ADKP_Print("错误：无法找到索引为 " .. (currentRecordIndex or "nil") .. " 的记录")
                        return
                    end
                    
                    if currentMode == "dkp" then
                        local currentPoints = latestRecord.points or latestRecord.score or 0
                        local uniqueId = latestRecord.uniqueId
                        if ADKP_ShowEditDKPDialog then
                            ADKP_ShowEditDKPDialog(uniqueId, currentPoints)
                        else
                            ADKP_Print("错误：修改DKP功能不可用")
                        end
                    elseif currentMode == "loot" then
                        local uniqueId = latestRecord.uniqueId
                        if ADKP_ShowEditLootDialog then
                            ADKP_ShowEditLootDialog(uniqueId, latestRecord.points or 0)
                        else
                            ADKP_Print("错误：修改装备记录功能不可用")
                        end
                    elseif currentMode == "substitute" then
                        local uniqueId = latestRecord.uniqueId
                        if ADKP_ShowEditSubstituteDialog then
                            ADKP_ShowEditSubstituteDialog(uniqueId, latestRecord.item or "替补", latestRecord.points or latestRecord.score or 0)
                        else
                            ADKP_Print("错误：修改替补记录功能不可用")
                        end
                    end
                end)
            end
            lineFrame.editButton:Show()
            
            -- 创建删除按钮
            if not lineFrame.deleteButton then
                lineFrame.deleteButton = CreateFrame("Button", "ADKP_LootListLine"..i.."DeleteButton", lineFrame, "UIPanelButtonTemplate")
                lineFrame.deleteButton:SetWidth(18)
                lineFrame.deleteButton:SetHeight(18)
                lineFrame.deleteButton:SetText("X")
                lineFrame.deleteButton:SetPoint("RIGHT", lineFrame, "RIGHT", -4, 0)
                
                lineFrame.deleteButton:SetScript("OnClick", function()
                    local currentRecordIndex = this:GetParent().recordIndex
                    local currentRecords = {}
                    local currentMode = ADKP_LootListFrame.currentMode or "loot"
                    if currentMode == "substitute" then
                        currentRecords = ADKP_GetSubstituteRecords()
                    elseif currentMode == "dkp" then
                        currentRecords = ADKP_GetDKPRecords()
                    else
                        currentRecords = ADKP_GetLootRecords()
                    end
                    
                    local latestRecord = currentRecords[currentRecordIndex]
                    if not latestRecord then
                        ADKP_Print("错误：无法找到索引为 " .. (currentRecordIndex or "nil") .. " 的记录")
                        return
                    end
                    
                    ADKP_CurrentRecord = {}
                    if currentMode == "dkp" then
                        ADKP_CurrentRecord.item = latestRecord.reason or latestRecord.item or "未知项目"
                        ADKP_CurrentRecord.time = latestRecord.date or latestRecord.time or date()
                        ADKP_CurrentRecord.player = latestRecord.name or latestRecord.player or "未知玩家"
                        ADKP_CurrentRecord.tableid = latestRecord.tableid
                        ADKP_CurrentRecord.score = latestRecord.score
                    elseif currentMode == "substitute" then
                        ADKP_CurrentRecord.item = latestRecord.reason or latestRecord.item or "替补记录"
                        ADKP_CurrentRecord.time = latestRecord.date or latestRecord.time or date()
                        ADKP_CurrentRecord.player = latestRecord.name or latestRecord.player or "未知玩家"
                        ADKP_CurrentRecord.location = latestRecord.location or "未知"
                    elseif currentMode == "loot" then
                        ADKP_CurrentRecord.item = latestRecord.reason or "未知装备"
                        ADKP_CurrentRecord.time = latestRecord.date or latestRecord.time or date()
                        ADKP_CurrentRecord.player = latestRecord.name or latestRecord.player or "未知玩家"
                        ADKP_CurrentRecord.points = latestRecord.points or 0
                    end
                    ADKP_CurrentRecord.rawRecord = latestRecord
                    
                    ADKP_CurrentRecordIndex = currentRecordIndex
                    ADKP_CurrentRecordMode = ADKP_LootListFrame.currentMode
                    ADKP_CurrentRecordUniqueId = latestRecord.uniqueId or currentRecordIndex
                    
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
                    if ADKP_CurrentRecordMode == "loot" then
                        dialogText = "确定要删除拍卖记录: " .. (ADKP_CurrentRecord.item or "未知物品") .. " 吗？"
                    elseif ADKP_CurrentRecordMode == "dkp" then
                        dialogText = "确定要删除主团记录: " .. (ADKP_CurrentRecord.item or "未知项目") .. " 吗？"
                    elseif ADKP_CurrentRecordMode == "substitute" then
                        dialogText = "确定要删除整条替补记录: " .. (ADKP_CurrentRecord.item or "替补记录") .. " 吗？"
                    end
                    StaticPopupDialogs["CONFIRM_DELETE_RECORD"].text = dialogText
                    
                    StaticPopupDialogs["CONFIRM_DELETE_RECORD"]._deleteCallback = function()
                        if ADKP_CurrentRecordMode and ADKP_CurrentRecord then
                            local success = false
                            if ADKP_CurrentRecordMode == "dkp" then
                                if ADKP_DeleteDKPRecordByItemAndTime then
                                    success = ADKP_DeleteDKPRecordByItemAndTime(
                                        ADKP_CurrentRecord.item, 
                                        ADKP_CurrentRecord.time
                                    )
                                end
                            elseif ADKP_CurrentRecordMode == "substitute" then
                                if ADKP_DeleteDKPRecordByItemAndTime then
                                    success = ADKP_DeleteDKPRecordByItemAndTime(
                                        ADKP_CurrentRecord.item,
                                        ADKP_CurrentRecord.time
                                    )
                                elseif ADKP_DeleteSubstituteRecordByItemAndTime and ADKP_CurrentRecord.player then
                                    success = ADKP_DeleteSubstituteRecordByItemAndTime(
                                        ADKP_CurrentRecord.player,
                                        ADKP_CurrentRecord.item,
                                        ADKP_CurrentRecord.time
                                    )
                                end
                            elseif ADKP_CurrentRecordMode == "loot" then
                                if ADKP_DeleteLootRecord then
                                    success = ADKP_DeleteLootRecord(
                                        ADKP_CurrentRecord.item,
                                        ADKP_CurrentRecord.player,
                                        ADKP_CurrentRecord.time
                                    )
                                end
                            end
                            
                            if success then
                                if ADKP_SaveToDisk then
                                    ADKP_SaveToDisk()
                                end
                            else
                                ADKP_Print("记录删除失败")
                            end
                        end
                        
                        if ADKP_UpdateLootList then
                            ADKP_UpdateLootList()
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
function ADKP_FindDKPLogEntry(record)
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
function ADKP_AdjustPlayerDkp(playerName, tableid, delta)
    if not WebDKP_DkpTable or not WebDKP_DkpTable[playerName] then return false end
    tableid = tableid or ADKP_GetTableid()
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
function ADKP_RemovePlayerFromDKPRecord(record, playerName)
    local key, entry = ADKP_FindDKPLogEntry(record)
    if not entry or not entry.awarded or not entry.awarded[playerName] then
        ADKP_Print("错误：找不到该记录或玩家")
        return false
    end
    local info = entry.awarded[playerName]
    local pts = tonumber(entry.points) or 0
    if type(info) == "table" then
        pts = tonumber(info.points or info.dkp or info.value or pts) or pts
    elseif type(info) == "number" then
        pts = info
    end
    local tableid = entry.tableid or ADKP_GetTableid()
    ADKP_AdjustPlayerDkp(playerName, tableid, -pts)
    entry.awarded[playerName] = nil
    if ADKP_SaveToDisk then ADKP_SaveToDisk() end
    if ADKP_UpdateTable then ADKP_UpdateTable() end
    ADKP_Print("已从记录中移除 " .. playerName .. "，扣回DKP " .. tostring(pts))
    return true
end

-- 向某条DKP记录添加一名玩家（按该条分数给分）
function ADKP_AddPlayerToDKPRecord(record, playerName)
    if not playerName or playerName == "" then return false end
    local key, entry = ADKP_FindDKPLogEntry(record)
    if not entry then
        ADKP_Print("错误：找不到该记录")
        return false
    end
    if not entry.awarded then entry.awarded = {} end
    if entry.awarded[playerName] then
        ADKP_Print("玩家 " .. playerName .. " 已在该记录中")
        return false
    end
    local pts = tonumber(entry.points) or 0
    local tableid = entry.tableid or ADKP_GetTableid()
    if not WebDKP_DkpTable[playerName] then
        local pclass = "未知"
        if ADKP_GetPlayerClass then
            pclass = ADKP_GetPlayerClass(playerName) or "未知"
        end
        WebDKP_DkpTable[playerName] = {
            ["class"] = pclass,
            ["dkp_" .. tableid] = 0,
            ["Selected"] = false,
            ["IsSub"] = false
        }
        ADKP_Print("提示：" .. playerName .. " 不在名单中，已新建条目")
    end
    entry.awarded[playerName] = { points = pts }
    ADKP_AdjustPlayerDkp(playerName, tableid, pts)
    if ADKP_SaveToDisk then ADKP_SaveToDisk() end
    if ADKP_UpdateTableToShow then ADKP_UpdateTableToShow() end
    if ADKP_UpdateTable then ADKP_UpdateTable() end
    ADKP_Print("已添加 " .. playerName .. " 到记录，给分 " .. tostring(pts))
    return true
end

-- 构建（懒加载）人员名单覆盖面板
function ADKP_EnsureRosterPanel()
    if ADKP_RosterPanel then return ADKP_RosterPanel end
    local parent = ADKP_LootListFrame
    if not parent then return nil end

    local panel = CreateFrame("Frame", "ADKP_RosterPanel", parent)
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

    local backBtn = CreateFrame("Button", "ADKP_RosterBackButton", panel, "UIPanelButtonTemplate")
    backBtn:SetWidth(90)
    backBtn:SetHeight(22)
    backBtn:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -15, -12)
    backBtn:SetText("完成/返回")
    backBtn:SetScript("OnClick", function()
        local record = ADKP_CurrentRosterRecord
        if ADKP_PendingDeletes then
            local toRemove = {}
            for pn, _ in pairs(ADKP_PendingDeletes) do
                table.insert(toRemove, pn)
            end
            for i = 1, table.getn(toRemove) do
                ADKP_RemovePlayerFromDKPRecord(record, toRemove[i])
            end
            ADKP_PendingDeletes = {}
        end
        local key, entry = ADKP_FindDKPLogEntry(record)
        if key and entry and (not entry.awarded or not next(entry.awarded)) then
            WebDKP_Log[key] = nil
            if ADKP_SaveToDisk then ADKP_SaveToDisk() end
            if ADKP_UpdateTable then ADKP_UpdateTable() end
            ADKP_Print("该记录已无人员，已删除整条记录")
        end
        ADKP_RosterPanel:Hide()
        if ADKP_UpdateLootList then ADKP_UpdateLootList() end
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

    local ptBox = CreateFrame("EditBox", "ADKP_RosterEditPoints", panel, "InputBoxTemplate")
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

    local rsBox = CreateFrame("EditBox", "ADKP_RosterEditReason", panel, "InputBoxTemplate")
    rsBox:SetWidth(180)
    rsBox:SetHeight(20)
    rsBox:SetPoint("LEFT", rsLabel, "RIGHT", 12, 0)
    rsBox:SetAutoFocus(false)
    rsBox:SetMaxLetters(60)
    rsBox:SetScript("OnEscapePressed", function() this:ClearFocus() end)
    panel.rsBox = rsBox

    local saveBtn = CreateFrame("Button", "ADKP_RosterEditSave", panel, "UIPanelButtonTemplate")
    saveBtn:SetWidth(110)
    saveBtn:SetHeight(24)
    saveBtn:SetPoint("TOPLEFT", panel, "TOPLEFT", 510, -156)
    saveBtn:SetText("保存修改")
    saveBtn:SetScript("OnClick", function()
        local record = ADKP_CurrentRosterRecord
        if not record then return end
        local uid = record.uniqueId
        if not uid then
            ADKP_Print("错误：该记录缺少标识，无法修改")
            return
        end
        local pBox = getglobal("ADKP_RosterEditPoints")
        local rBox = getglobal("ADKP_RosterEditReason")
        local newPoints = pBox and pBox:GetText() or ""
        local newReason = rBox and rBox:GetText() or ""
        if not tonumber(newPoints) then
            ADKP_Print("错误：分值必须是数字")
            return
        end
        local ok = false
        if record.isSubstitute then
            if newReason == "" then newReason = record.item or "替补" end
            if ADKP_EditSubstituteRecord then
                ok = ADKP_EditSubstituteRecord(uid, newReason, newPoints)
            else
                ADKP_Print("错误：修改替补记录功能不可用")
            end
        else
            if ADKP_EditDKPRecord then
                ok = ADKP_EditDKPRecord(uid, newPoints, newReason)
            else
                ADKP_Print("错误：修改主团记录功能不可用")
            end
        end
        if ok then
            record.points = tonumber(newPoints)
            record.score = tonumber(newPoints)
            if newReason and newReason ~= "" then record.item = newReason end
        end
        ADKP_UpdateRosterList()
    end)
    panel.saveBtn = saveBtn

    local editHint = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    editHint:SetPoint("TOPLEFT", panel, "TOPLEFT", 510, -190)
    editHint:SetWidth(240)
    editHint:SetJustifyH("LEFT")
    editHint:SetText("提示：修改分值会同步调整该条所有人员的DKP。")
    panel.editHint = editHint

    local scroll = CreateFrame("ScrollFrame", "ADKP_RosterScroll", panel, "FauxScrollFrameTemplate")
    scroll:SetWidth(470)
    scroll:SetHeight(10 * 24)
    scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 24, -58)
    scroll:SetScript("OnVerticalScroll", function()
        FauxScrollFrame_OnVerticalScroll(24, ADKP_UpdateRosterList)
    end)
    panel.scroll = scroll

    for i = 1, 10 do
        local row = CreateFrame("Frame", "ADKP_RosterLine" .. i, panel)
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

        local removeBtn = CreateFrame("Button", "ADKP_RosterLine" .. i .. "Remove", row, "UIPanelButtonTemplate")
        removeBtn:SetWidth(50)
        removeBtn:SetHeight(18)
        removeBtn:SetText("移除")
        removeBtn:SetPoint("LEFT", row, "LEFT", 405, 0)
        removeBtn:SetScript("OnClick", function()
            local pn = this:GetParent().playerName
            if pn and pn ~= "" then
                if not ADKP_PendingDeletes then ADKP_PendingDeletes = {} end
                if ADKP_PendingDeletes[pn] then
                    ADKP_PendingDeletes[pn] = nil
                else
                    ADKP_PendingDeletes[pn] = true
                end
                ADKP_UpdateRosterList()
            end
        end)
        row.removeButton = removeBtn

        row:Hide()
    end

    local addLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    addLabel:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 24, 16)
    addLabel:SetText("添加人员:")
    panel.addLabel = addLabel

    local addBox = CreateFrame("EditBox", "ADKP_RosterAddBox", panel, "InputBoxTemplate")
    addBox:SetWidth(160)
    addBox:SetHeight(20)
    addBox:SetPoint("LEFT", addLabel, "RIGHT", 12, 0)
    addBox:SetAutoFocus(false)
    addBox:SetMaxLetters(30)
    addBox:SetScript("OnEscapePressed", function() this:ClearFocus() end)
    addBox:SetScript("OnEnterPressed", function()
        if ADKP_RosterAddButton then ADKP_RosterAddButton:Click() end
    end)
    panel.addBox = addBox

    local addBtn = CreateFrame("Button", "ADKP_RosterAddButton", panel, "UIPanelButtonTemplate")
    addBtn:SetWidth(60)
    addBtn:SetHeight(22)
    addBtn:SetText("添加")
    addBtn:SetPoint("LEFT", addBox, "RIGHT", 10, 0)
    addBtn:SetScript("OnClick", function()
        local box = getglobal("ADKP_RosterAddBox")
        local pn = box and box:GetText() or ""
        if pn and pn ~= "" then
            if ADKP_AddPlayerToDKPRecord(ADKP_CurrentRosterRecord, pn) then
                box:SetText("")
            end
            ADKP_UpdateRosterList()
        end
    end)

    panel:Hide()
    ADKP_RosterPanel = panel
    return panel
end

-- 刷新名单行
function ADKP_UpdateRosterList()
    local panel = ADKP_RosterPanel
    if not panel or not panel:IsShown() then return end
    local record = ADKP_CurrentRosterRecord
    local key, entry = ADKP_FindDKPLogEntry(record)
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
    local scroll = getglobal("ADKP_RosterScroll")
    local offset = 0
    if scroll then
        FauxScrollFrame_Update(scroll, total, numDisplayed, rowHeight)
        offset = FauxScrollFrame_GetOffset(scroll)
    end

    for i = 1, numDisplayed do
        local row = getglobal("ADKP_RosterLine" .. i)
        local name = names[offset + i]
        if row and name then
            row.playerName = name
            row.nameText:SetText(name)
            if row.locText then row.locText:SetText(locs[name] or "") end
            local pending = ADKP_PendingDeletes and ADKP_PendingDeletes[name]
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
function ADKP_ShowRecordRoster(record)
    if not record then return end
    local panel = ADKP_EnsureRosterPanel()
    if not panel then return end
    ADKP_CurrentRosterRecord = record
    ADKP_PendingDeletes = {}
    local pBox0 = getglobal("ADKP_RosterEditPoints")
    local rBox0 = getglobal("ADKP_RosterEditReason")
    if pBox0 then pBox0:SetText(tostring(record.points or record.score or 0)) end
    if rBox0 then rBox0:SetText(record.item or "") end
    local sb = getglobal("ADKP_RosterScrollScrollBar")
    if sb then sb:SetValue(0) end
    panel:Show()
    ADKP_UpdateRosterList()
end

-- 切换装备记录窗口显示状态
function ADKP_ToggleLootList()
    if not ADKP_LootListFrame then
        ADKP_CreateLootListFrame()
    end
    
    if ADKP_LootListFrame:IsShown() then
        ADKP_LootListFrame:Hide()
    else
        ADKP_LootListFrame:Show()
        ADKP_UpdateLootList()
    end
end

