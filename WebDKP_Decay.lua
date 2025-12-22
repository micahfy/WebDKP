------------------------------------------------------------------------
-- WEB DKP 衰减功能模块
------------------------------------------------------------------------
-- 提供DKP衰减相关的功能，包括：
-- 1. 衰减计算
-- 2. 应用衰减
-- 3. 导出DKP数据
-- 4. 导入初始DKP数据
------------------------------------------------------------------------

-- 衰减临时数据存储
WebDKP_DecayData = {
    calculated = false,
    decayValues = {},
    baseScore = 0,
    decayRate = 15,
    precision = 2,
    savedGroupFilterState = nil -- 保存Group筛选器的原始状态
}

-- 衰减设置保存键
WebDKP_DECAY_SETTINGS_KEY = "WebDKP_DecaySettings"

-- 初始化衰减框架
WebDKP_InitializeDecayFrame = function()
	-- WebDKP_Print("WebDKP_InitializeDecayFrame 被调用")
	
	-- XML中已经定义了框架，这里只需要确保框架被加载
	if not WebDKP_DecayFrame then
		-- 如果框架确实不存在，打印错误信息而不是重新创建
		-- WebDKP_Print("错误：衰减框架未找到，请检查WebDKP是否正确安装")
		return
	end
	
	-- WebDKP_Print("WebDKP_InitializeDecayFrame: 框架已找到")
	
	-- 确保输入框存在
	if not WebDKP_DecayFrameBaseScoreEdit or not WebDKP_DecayFrameDecayRateEdit or not WebDKP_DecayFramePrecisionEdit then
		-- WebDKP_Print("错误：衰减输入框未找到")
		return
	end
	
	-- WebDKP_Print("WebDKP_InitializeDecayFrame: 输入框已找到")
	
	-- 加载保存的设置
	WebDKP_LoadDecaySettings()
	
	-- 更新表头文本
	WebDKP_UpdateDecayHeader()
	
	-- WebDKP_Print("WebDKP_InitializeDecayFrame: 初始化完成")
end

-- 更新衰减页面表头
WebDKP_UpdateDecayHeader = function()
	-- 修改阶层列标题为衰减值
	local tierHeader = getglobal("WebDKP_FrameTierText")
	if tierHeader then
		tierHeader:SetText("衰减值")
	end
end

-- 切换衰减框架显示
WebDKP_ToggleDecayFrame = function()
    -- WebDKP_Print("WebDKP_ToggleDecayFrame 被调用")
    
    if not WebDKP_DecayFrame then
        -- WebDKP_Print("WebDKP_DecayFrame 不存在，尝试初始化...")
        WebDKP_InitializeDecayFrame()
    end
    
    -- 确保其他相关框架先隐藏，避免元素堆叠
    if WebDKP_AwardFrame and WebDKP_AwardFrame:IsShown() then
        WebDKP_AwardFrame:Hide()
    end
    if WebDKP_BidFrame and WebDKP_BidFrame:IsShown() then
        WebDKP_BidFrame:Hide()
    end
    
    if WebDKP_DecayFrame and WebDKP_DecayFrame:IsShown() then
        WebDKP_DecayFrame:Hide()
        -- 隐藏主窗口
        if WebDKP_Frame then
            WebDKP_Frame:Hide()
        end
        -- 切换回其他页面，恢复阶层显示
        WebDKP_CurrentMode = nil
        -- 恢复表头为阶层
        local tierHeader = getglobal("WebDKP_FrameTierText")
        if tierHeader then
            tierHeader:SetText("阶层")
        end
        -- 恢复Group筛选器的原始状态
        if WebDKP_DecayData.savedGroupFilterState ~= nil then
            if WebDKP_Filters["Group"] ~= WebDKP_DecayData.savedGroupFilterState then
                WebDKP_Filters["Group"] = WebDKP_DecayData.savedGroupFilterState
                -- 更新复选框状态
                local checkBox = getglobal("WebDKP_FiltersFrameClassGroup")
                if checkBox then
                    checkBox:SetChecked(WebDKP_DecayData.savedGroupFilterState)
                end
                WebDKP_UpdateTableToShow()
            end
            WebDKP_DecayData.savedGroupFilterState = nil
        end
        -- 清除计算状态，更新显示
        WebDKP_DecayData.calculated = false
        WebDKP_UpdateTable()
    else
        -- 确保主界面先显示
        if WebDKP_Frame then
            WebDKP_Frame:Show()
        end
        WebDKP_DecayFrame:Show()
        
        -- 同步主界面的复选框状态
        local mainLimitRaid = getglobal("WebDKP_FiltersFrameLimitRaid");
        local decayLimitRaid = getglobal("WebDKP_DecayFrameLimitRaid");
        if mainLimitRaid and decayLimitRaid then
            decayLimitRaid:SetChecked(mainLimitRaid:GetChecked());
        end
        
        -- 标记当前为衰减页面
        WebDKP_CurrentMode = "decay"
        -- 保存当前Group筛选器状态
        WebDKP_DecayData.savedGroupFilterState = WebDKP_Filters["Group"]
        -- 如果当前Group筛选器开启（只显示团队成员），则关闭它以显示所有玩家
        if WebDKP_Filters["Group"] == 1 then
            WebDKP_Filters["Group"] = 0
            -- 更新复选框状态
            local checkBox = getglobal("WebDKP_FiltersFrameClassGroup")
            if checkBox then
                checkBox:SetChecked(0)
            end
            WebDKP_UpdateTableToShow()
        end
        -- 更新表头为衰减值（立即执行，确保切换时表头正确更新）
        local tierHeader = getglobal("WebDKP_FrameTierText")
        if tierHeader then
            tierHeader:SetText("衰减值")
        end
        -- 不要在这里调用刷新队伍命令
        WebDKP_UpdateTable()
    end
end

-- 保存衰减设置
WebDKP_SaveDecaySettings = function()
    -- WebDKP_Print("WebDKP_SaveDecaySettings 被调用")
    
    if not WebDKP_DecayFrame then 
        -- WebDKP_Print("WebDKP_SaveDecaySettings: 框架不存在")
        return 
    end
    
    if not WebDKP_DecayFrameBaseScoreEdit or not WebDKP_DecayFrameDecayRateEdit or not WebDKP_DecayFramePrecisionEdit then 
        -- WebDKP_Print("WebDKP_SaveDecaySettings: 输入框不存在")
        return 
    end
    
    local baseScore = tonumber(WebDKP_DecayFrameBaseScoreEdit:GetText()) or 0
    local decayRate = tonumber(WebDKP_DecayFrameDecayRateEdit:GetText()) or 15
    local precision = tonumber(WebDKP_DecayFramePrecisionEdit:GetText()) or 2
    
    -- WebDKP_Print("WebDKP_SaveDecaySettings: 获取到的值 - 底分:" .. baseScore .. ", 衰减率:" .. decayRate .. ", 精度:" .. precision)
    
    local settings = {
        baseScore = baseScore,
        decayRate = decayRate,
        precision = precision
    }
    
    WebDKP_DecayData.baseScore = settings.baseScore
    WebDKP_DecayData.decayRate = settings.decayRate
    WebDKP_DecayData.precision = settings.precision
    
    -- 保存到全局变量（在魔兽世界中，这会在会话间保持）
    WebDKP_SavedDecaySettings = settings
    -- WebDKP_Print("WebDKP_SaveDecaySettings: 设置已保存到 WebDKP_SavedDecaySettings")
    
    -- 如果可用，保存到插件设置
    if WebDKP_Options then
        WebDKP_Options["DecaySettings"] = settings
        -- WebDKP_Print("WebDKP_SaveDecaySettings: 设置已保存到 WebDKP_Options")
    end
end

-- 加载衰减设置
WebDKP_LoadDecaySettings = function()
    -- WebDKP_Print("WebDKP_LoadDecaySettings 被调用")
    
    if not WebDKP_DecayFrame then 
        -- WebDKP_Print("WebDKP_LoadDecaySettings: 框架不存在")
        return 
    end
    
    if not WebDKP_DecayFrameBaseScoreEdit or not WebDKP_DecayFrameDecayRateEdit or not WebDKP_DecayFramePrecisionEdit then 
        -- WebDKP_Print("WebDKP_LoadDecaySettings: 输入框不存在")
        return 
    end
    
    local settings = nil
    
    -- 尝试从插件设置加载
    if WebDKP_Options and WebDKP_Options["DecaySettings"] then
        settings = WebDKP_Options["DecaySettings"]
        -- WebDKP_Print("WebDKP_LoadDecaySettings: 从 WebDKP_Options 加载设置")
    -- 尝试从全局变量加载
    elseif WebDKP_SavedDecaySettings then
        settings = WebDKP_SavedDecaySettings
        -- WebDKP_Print("WebDKP_LoadDecaySettings: 从 WebDKP_SavedDecaySettings 加载设置")
    end
    
    -- 如果找到设置，应用它们
    if settings then
        -- WebDKP_Print("WebDKP_LoadDecaySettings: 应用设置 - 底分:" .. (settings.baseScore or 0) .. ", 衰减率:" .. (settings.decayRate or 15) .. ", 精度:" .. (settings.precision or 2))
        
        WebDKP_DecayFrameBaseScoreEdit:SetText(settings.baseScore or 0)
        WebDKP_DecayFrameDecayRateEdit:SetText(settings.decayRate or 15)
        WebDKP_DecayFramePrecisionEdit:SetText(settings.precision or 2)
        
        WebDKP_DecayData.baseScore = settings.baseScore or 0
        WebDKP_DecayData.decayRate = settings.decayRate or 15
        WebDKP_DecayData.precision = settings.precision or 2
    else
        -- WebDKP_Print("WebDKP_LoadDecaySettings: 未找到保存的设置，使用默认值")
        -- 使用默认值
        WebDKP_DecayFrameBaseScoreEdit:SetText(WebDKP_DecayData.baseScore)
        WebDKP_DecayFrameDecayRateEdit:SetText(WebDKP_DecayData.decayRate)
        WebDKP_DecayFramePrecisionEdit:SetText(WebDKP_DecayData.precision)
    end
end

-- 计算衰减值
WebDKP_Decay_Calculate = function()
    -- WebDKP_Print("开始计算衰减...")
    
    -- 检查输入框是否存在
    if not WebDKP_DecayFrameBaseScoreEdit or not WebDKP_DecayFrameDecayRateEdit or not WebDKP_DecayFramePrecisionEdit then
        -- WebDKP_Print("错误：输入框未找到")
        return
    end
    
    -- 获取输入值
    local baseScore = tonumber(WebDKP_DecayFrameBaseScoreEdit:GetText()) or 0
    local decayRate = tonumber(WebDKP_DecayFrameDecayRateEdit:GetText()) or 15
    local precision = tonumber(WebDKP_DecayFramePrecisionEdit:GetText()) or 2
    
    -- WebDKP_Print("参数：底分=" .. baseScore .. ", 衰减率=" .. decayRate .. "%, 精度=" .. precision)
    
    -- 保存当前设置
    WebDKP_SaveDecaySettings()
    
    -- 验证输入
    if decayRate <= 0 or decayRate > 100 then
        WebDKP_Print("错误：衰减值必须在1-100之间")
        return
    end
    
    if precision < 0 or precision > 3 then
        WebDKP_Print("错误：精度必须在0-3之间")
        return
    end
    
    -- 保存配置
    WebDKP_DecayData.baseScore = baseScore
    WebDKP_DecayData.decayRate = decayRate
    WebDKP_DecayData.precision = precision
    WebDKP_DecayData.decayValues = {}
    WebDKP_DecayData.calculated = true
    
    -- 获取当前表ID
    local tableid = WebDKP_GetTableid()
    local decayMultiplier = decayRate  * 0.01 -- 确保衰减率除以100
    local calculatedCount = 0
    
    -- 计算每个玩家的衰减后分数
    for playerName, playerData in pairs(WebDKP_DkpTable) do
        if type(playerData) == "table" then
            local currentDKP = tonumber(playerData["dkp_"..tableid]) or 0
            local decayAmount = 0
            local afterDecay = currentDKP
            
            -- 只对DKP大于底分的玩家计算衰减值
            if currentDKP > baseScore then
                decayAmount = (currentDKP - baseScore) * decayMultiplier 
                afterDecay = currentDKP - decayAmount
                calculatedCount = calculatedCount + 1
                
                -- 应用精度到衰减值，确保显示正确的小数位数
                local precisionFormat = "%."..precision.."f"
                decayAmount = tonumber(string.format(precisionFormat, decayAmount)) 
                afterDecay = tonumber(string.format(precisionFormat, afterDecay))
                
                -- WebDKP_Print("计算衰减值调试 - 玩家:"..playerName.." 当前DKP:"..currentDKP.." 底分:"..baseScore.." 衰减率:"..decayRate.."% 衰减值:"..decayAmount)
            else
                -- DKP小于等于底分的玩家，衰减值为0，不参与计算，无调试输出
                decayAmount = 0
            end
            
            -- 存储时乘以100，这样显示时乘以0.01就能得到正确结果
            local storedDecayAmount = decayAmount * 100
            
            WebDKP_DecayData.decayValues[playerName] = {
                original = currentDKP,
                decayAmount = storedDecayAmount,  -- 存储乘以100的值
                afterDecay = afterDecay,
                decayRate = decayMultiplier  -- 保存衰减率百分比值，用于显示
            }
            
        end
    end
    
    -- 更新表格显示
    WebDKP_UpdateTable()
    -- WebDKP_Print("衰减计算完成，衰减值："..decayRate.."%，底分："..baseScore.."，计算了"..calculatedCount.."个玩家")
end

-- 应用衰减
WebDKP_Decay_Apply = function()
    WebDKP_Print("开始应用衰减...")
    
    if not WebDKP_DecayData.calculated then
        WebDKP_Print("请先点击'开始计算'按钮")
        return
    end
    
    WebDKP_Print("衰减数据已计算，准备应用...")
    
    -- 创建衰减原因文本，格式：衰减-日期-衰减分
    local currentDate = date("%Y%m%d")
    local reason = "衰减-"..currentDate
    
    -- 按衰减值分组玩家（只处理有衰减值的玩家）
    local decayGroups = {}
    local playersWithDecay = 0
    local precisionFormat = "%0."..WebDKP_DecayData.precision.."f" -- 使用设置的精度进行分组，确保相同衰减值的玩家被正确分组
    
    WebDKP_Print("开始按衰减值分组玩家...")
    
    for playerName, decayInfo in pairs(WebDKP_DecayData.decayValues) do
        local actualDecayAmount = decayInfo.decayAmount * 0.01  -- 将存储的值转换回实际衰减值
        if actualDecayAmount > 0 then
            -- 使用格式化的字符串作为键，确保相同衰减值的玩家被正确分组
            local formattedAmount = string.format(precisionFormat, actualDecayAmount)
            -- WebDKP_Print("玩家: "..playerName..", 衰减值: "..actualDecayAmount..", 格式化键: "..formattedAmount)
            
            if not decayGroups[formattedAmount] then
                decayGroups[formattedAmount] = {
                    amount = actualDecayAmount,  -- 保存原始数值用于DKP扣除
                    players = {}                 -- 单独的玩家数组，避免键值对混乱
                }
                -- WebDKP_Print("创建新分组: "..formattedAmount)
            end
            
            table.insert(decayGroups[formattedAmount].players, playerName)
            playersWithDecay = playersWithDecay + 1
        end
    end
    
    WebDKP_Print("分组完成，总玩家数: "..playersWithDecay..", 分组数: "..WebDKP_GetTableSize(decayGroups))
    
    if playersWithDecay == 0 then
        WebDKP_Print("没有玩家需要应用衰减（所有玩家DKP都小于等于底分）")
        return
    end
    
    -- 为每个玩家单独创建DKP记录，确保每个玩家都应用了正确的衰减值
    local totalPlayersProcessed = 0
    local uniqueDecayValues = {}
    
    WebDKP_Print("开始为每个玩家单独应用衰减值...")
    
    -- 首先统计有多少个不同的衰减值组
    for formattedAmount, groupData in pairs(decayGroups) do
        uniqueDecayValues[formattedAmount] = true
    end
    
    local uniqueDecayCount = WebDKP_GetTableSize(uniqueDecayValues)
    WebDKP_Print("检测到 "..uniqueDecayCount.." 个不同的衰减值组")
    
    -- 为每个玩家单独调用WebDKP_AddDKP
    for formattedAmount, groupData in pairs(decayGroups) do
        local actualDecayAmount = groupData.amount
        local playerList = groupData.players or {}
        -- Lua 5.0兼容方式计算数组长度
        local playerListCount = 0
        for i, _ in ipairs(playerList) do
            playerListCount = i
        end
        
        if playerListCount > 0 then
            -- WebDKP_Print("处理衰减值: -"..actualDecayAmount..", 玩家数: "..playerListCount)
            
            -- 为每个玩家单独调用WebDKP_AddDKP，确保每个玩家都有自己的记录
            for i = 1, playerListCount do
                local playerName = playerList[i]
                local playerClass = WebDKP_DkpTable[playerName] and WebDKP_DkpTable[playerName]["class"] or "未知"
                
                -- WebDKP_Print("  - 处理玩家: "..playerName..", 职业: "..playerClass..", 衰减值: -"..actualDecayAmount)
                
                -- 为单个玩家创建playerTable
                local singlePlayerTable = {}
                singlePlayerTable[0] = {
                    name = playerName,
                    class = playerClass
                }
                
                -- 为每个玩家使用格式为"衰减-日期-衰减分"的reason，这样相同衰减值的玩家会自动合并，使用设置的精度
                local decayValue = string.format("%0."..WebDKP_DecayData.precision.."f", actualDecayAmount)
                local decayReason = reason .. "-" .. decayValue
                -- WebDKP_Print("  调用WebDKP_AddDKP，reason: "..decayReason)
                local tableid = WebDKP_GetTableid()
                WebDKP_AddDKP(-actualDecayAmount, decayReason, "false", singlePlayerTable, tableid)
                totalPlayersProcessed = totalPlayersProcessed + 1
            end
        end
    end
    
    WebDKP_Print("已为 "..totalPlayersProcessed.." 名玩家单独应用衰减值")
    
    -- 重置衰减数据
    WebDKP_DecayData.calculated = false
    WebDKP_DecayData.decayValues = {}
    
    -- 更新表格
    WebDKP_UpdateTableToShow()
    WebDKP_UpdateTable()
    
    WebDKP_Print("衰减已应用，创建了"..WebDKP_GetTableSize(decayGroups).."条衰减记录，合并了相同衰减值的玩家")
end

-- 导出DKP数据
WebDKP_Decay_Export = function()
    WebDKP_Print("开始导出DKP数据...")
    
    local currentDate = date("%Y%m%d")
    local fileName = "DKP导出"..currentDate
    local exportText = "职业,名字,DKP\n"
    
    -- 获取当前表ID
    local tableid = WebDKP_GetTableid()
    
    -- 收集DKP大于0的玩家数据
    local players = {}
    for playerName, playerData in pairs(WebDKP_DkpTable) do
        if type(playerData) == "table" then
            local playerClass = playerData["class"] or "未知"
            local playerDKP = playerData["dkp_"..tableid] or 0
            -- 只收集DKP大于0的玩家
            if playerDKP > 0 then
                table.insert(players, {
                    name = playerName,
                    class = playerClass,
                    dkp = playerDKP
                })
            end
        end
    end
    
    -- 创建职业优先级映射
    local classPriority = {
        ["战士"] = 1,
        ["术士"] = 2,
        ["萨满祭司"] = 3,
        ["圣骑士"] = 4,
        ["牧师"] = 5,
        ["猎人"] = 6,
        ["法师"] = 7,
        ["德鲁伊"] = 8,
        ["潜行者"] = 9
    }
    
    -- 按职业优先级排序，相同职业按名字排序
    table.sort(players, function(a, b)
        -- 先按职业优先级排序
        local aPriority = classPriority[a.class] or 10 -- 未知职业放在最后
        local bPriority = classPriority[b.class] or 10
        
        if aPriority ~= bPriority then
            return aPriority < bPriority
        else
            -- 职业相同则按名字排序
            return a.name < b.name
        end
    end)
    
    -- 生成导出文本
    for _, player in ipairs(players) do
        exportText = exportText .. player.class .. "," .. player.name .. "," .. player.dkp .. "\n"
    end
    
    -- 导出文件
    if ExportFile then
        local success = ExportFile(fileName, exportText)
        if success then
            WebDKP_Print("DKP数据已成功导出到 "..fileName)
        else
            WebDKP_Print("错误：导出失败，请检查文件权限")
        end
    else
        -- 如果没有ExportFile函数，尝试使用其他方法或提示用户
        WebDKP_Print("错误：导出功能不可用，请检查插件版本")
    end
end

-- 导入初始DKP数据
WebDKP_Decay_Import = function()
    WebDKP_Print("开始导入初始DKP数据...")
    
    -- 尝试从imports目录导入dkp导入.txt文件
    local fileName = "dkp导入"
    
    -- 使用ImportFile函数读取游戏目录\imports中的txt文件
    -- 检查是否存在ImportFile函数
    if ImportFile then
        -- 读取文件内容（在Lua 5.0中可能需要完整路径）
     
        local importData = ImportFile(fileName)
        
        -- 详细的错误检查
        if importData then
            if importData ~= "" then
                -- 检查是否有内容（至少包含表头）
                local hasContent = string.len(importData) > 5
                if hasContent then
                    WebDKP_Print("成功读取文件内容，正在处理导入数据...")
                    -- 调用处理函数
                    WebDKP_ProcessImportData(importData)
                else
                    WebDKP_Print("错误：文件内容格式不正确")
                    WebDKP_Print("请确保文件包含正确的表头和数据")
                    WebDKP_Print("格式要求：职业,名字,DKP")
                    WebDKP_Print("示例：战士,玩家1,100")
                end
            else
                WebDKP_Print("错误：文件内容为空")
                WebDKP_Print("请确保dkp导入.txt文件包含有效的数据")
            end
        else
            WebDKP_Print("错误：无法读取文件或文件不存在")
            WebDKP_Print("请确认以下事项：")
            WebDKP_Print("1. 游戏安装目录下存在'imports'文件夹")
            WebDKP_Print("2. imports目录下有'"..fileName.."'文件")
            WebDKP_Print("3. 文件格式正确：职业,名字,DKP")
            WebDKP_Print("示例：战士,玩家1,100")
        end
    else
        WebDKP_Print("错误：ImportFile函数不可用")
        WebDKP_Print("请检查插件是否完整加载或游戏版本兼容性")
    end
end

-- 规范化职业名称的辅助函数
local function NormalizeClass(className)
    if not className then return className end
    
    -- 转换为小写进行匹配
    local lowerClass = string.lower(className)
    
    -- 匹配各种职业名称变体
    if string.find(lowerClass, "战士") then
        return "战士"
    elseif string.find(lowerClass, "术士") then
        return "术士"
    elseif string.find(lowerClass, "萨满") then
        return "萨满祭司"
    elseif string.find(lowerClass, "骑士") then
        return "圣骑士"
    elseif string.find(lowerClass, "牧师") then
        return "牧师"
    elseif string.find(lowerClass, "猎人") then
        return "猎人"
    elseif string.find(lowerClass, "法师") then
        return "法师"
    elseif string.find(lowerClass, "德鲁伊") or string.find(lowerClass, "小德") then
        return "德鲁伊"
    elseif string.find(lowerClass, "潜行者") or string.find(lowerClass, "盗贼") then
        return "潜行者"
    end
    
    -- 无法识别的职业名称保持不变
    return className
end

-- 获取当前日期字符串 (WoW 1.12 API兼容)
local function GetCurrentDateString()
    -- 使用WoW内置的date函数替代os.date
    return date("%Y-%m-%d")
end

-- 处理导入的数据（示例函数）
WebDKP_ProcessImportData = function(importData)
    local lines = {}
    for line in string.gmatch(importData, "[^\n]+") do
        table.insert(lines, line)
    end
    
    local importedCount = 0
    local tableid = WebDKP_GetTableid()
    local currentDate = GetCurrentDateString()
    
    -- 计算总行数（Lua 5.0兼容方式）
    local lineCount = 0
    for _ in pairs(lines) do
        lineCount = lineCount + 1
    end
    
    -- 从第一行开始处理数据，不跳过任何行
    for i = 1, lineCount do
        local line = lines[i]
        local class, name, dkp = string.match(line, "([^,]+),([^,]+),([^,]+)")
        
        if class and name and dkp then
            dkp = tonumber(dkp) or 0
            -- 规范化职业名称
            class = NormalizeClass(class)
            
            -- 检查玩家是否已存在
            if not WebDKP_DkpTable[name] then
                -- 创建新玩家并添加初始DKP记录，使用"日期-玩家名称-初始分"格式
                WebDKP_DkpTable[name] = {
                    ["dkp_"..tableid] = dkp,
                    ["class"] = class,
                    ["Selected"] = false
                }
                
                -- 为新玩家添加DKP记录
                local reason = currentDate.."-"..name.."-"..dkp
                local playerTable = {}
                playerTable[0] = {
                    name = name,
                    class = class
                }
                local tableid = WebDKP_GetTableid()
                WebDKP_AddDKP(dkp, reason, "false", playerTable, tableid)
            else
                -- 更新现有玩家的DKP
                WebDKP_DkpTable[name]["class"] = class
                local oldDKP = WebDKP_DkpTable[name]["dkp_"..tableid] or 0
                local dkpDiff = dkp - oldDKP
                
                if dkpDiff ~= 0 then
                    -- 添加DKP记录，使用"日期-玩家名称-初始分"格式作为项目名称
                    local reason = currentDate.."-"..name.."-"..dkp
                    local playerTable = {}
                    playerTable[0] = {
                        name = name,
                        class = class
                    }
                    local tableid = WebDKP_GetTableid()
                    WebDKP_AddDKP(dkpDiff, reason, "false", playerTable, tableid)
                end
            end
            
            importedCount = importedCount + 1
        end
    end
    
    -- 更新表格
    WebDKP_UpdateTableToShow()
    WebDKP_UpdateTable()
    
    -- 导入成功后，导出同名空白文件以防止连续导入加分
    if importedCount > 0 then
        -- 获取当前日期
        local currentDate = GetCurrentDateString()
        
        -- 使用原始导入文件名导出空白内容
        ExportFile("dkp导入", "")
        WebDKP_Print("已清空导入文件内容，防止重复导入")
        
        -- 使用新的命名格式导出一份记录（日期-玩家名称-初始分）
        local exportFileName = currentDate.."-玩家初始分"
        local exportContent = "职业,名字,DKP\n"
        
        for i = 2, lineCount do
            local line = lines[i]
            exportContent = exportContent .. line .. "\n"
        end
        
        ExportFile(exportFileName, exportContent)
        WebDKP_Print("已备份初始分到文件: "..exportFileName)
    end
    
    WebDKP_Print("成功导入 "..importedCount.." 条初始DKP数据")
end

-- 标记当前是否显示衰减页面
WebDKP_CurrentMode = nil

-- 保存原始阶层数据，用于切换页面时恢复
WebDKP_OriginalTierData = {}

-- 修改WebDKP_UpdateTable函数以支持衰减后分数的显示
local original_WebDKP_UpdateTable = WebDKP_UpdateTable

WebDKP_UpdateTable = function()
    -- 首先根据当前模式更新表头，确保每次都能正确设置
    if WebDKP_CurrentMode == "decay" then
        local tierHeader = getglobal("WebDKP_FrameTierText")
        if tierHeader then
            tierHeader:SetText("衰减值")
        end
    else
        local tierHeader = getglobal("WebDKP_FrameTierText")
        if tierHeader then
            tierHeader:SetText("阶层")
        end
    end
    
    -- Copy data to the temporary array
    local entries = { };
    
    -- 在衰减页面且已计算时，显示所有玩家（从WebDKP_DkpTable获取）
    if WebDKP_CurrentMode == "decay" and WebDKP_DecayData.calculated then
        local baseScore = WebDKP_DecayData.baseScore
        local tableid = WebDKP_GetTableid()
        
        for playerName, playerData in pairs(WebDKP_DkpTable) do
            if type(playerData) == "table" then
                local playerDKP = tonumber(playerData["dkp_"..tableid]) or 0
                local playerClass = playerData["class"] or "未知"
                
                -- 显示所有玩家，无论是否在队伍中
                local tierValue = "" -- 平时不显示
                local displayText = ""
                
                if WebDKP_DecayData.decayValues[playerName] then
                    -- 保存原始阶层数据
                    if not WebDKP_OriginalTierData[playerName] then
                        WebDKP_OriginalTierData[playerName] = playerData["tier"] or ""
                    end
                    
                    -- 使用已计算好的衰减值
                    local decayInfo = WebDKP_DecayData.decayValues[playerName]
                    local storedDecayAmount = decayInfo.decayAmount
                    local actualDecayAmount = storedDecayAmount * 0.01 -- 转换回真实衰减值
                    tierValue = actualDecayAmount
                    
                    -- 只显示有衰减值的玩家（actualDecayAmount > 0）
                    if actualDecayAmount > 0 then
                        local precisionFormat = "%."..WebDKP_DecayData.precision.."f"
                        displayText = string.format(precisionFormat, actualDecayAmount)
                    else
                        -- DKP小于等于底分的玩家，不显示衰减值
                        displayText = ""
                    end
                end
                
                -- 即使分数≤底分也显示，让用户看到所有玩家
                tinsert(entries,{playerName, playerClass, playerDKP, displayText}); -- name, class, dkp, formatted decayAmount
            end
        end
    else
        -- 非衰减页面或未计算时，使用原始逻辑
        for k, v in pairs(WebDKP_DkpTableToShow) do
            if ( type(v) == "table" ) then
                if( v[1] ~= nil and v[2] ~= nil and v[3] ~=nil) then
                    local playerName = v[1]
                    local playerDKP = v[3]
                    
                    -- 非衰减页面或未计算时，显示所有玩家，恢复原始阶层值
                    local tierValue = v[4] or ""
                    
                    -- 如果在切换回其他页面，恢复原始阶层值和表头
                    if WebDKP_CurrentMode ~= "decay" then
                        -- 恢复表头为阶层
                        local tierHeader = getglobal("WebDKP_FrameTier")
                        if tierHeader then
                            tierHeader:SetText("阶层")
                        end
                        
                        -- 恢复原始阶层值
                        if WebDKP_OriginalTierData[playerName] then
                            tierValue = WebDKP_OriginalTierData[playerName]
                        end
                    end
                    
                    tinsert(entries,{playerName, v[2], playerDKP, tierValue});
                end
            end
        end
    end
    
    -- SORT
    table.sort(
        entries,
        function(a1, a2)
            if ( a1 and a2 ) then
                if ( a1 == nil ) then
                    return 1>0;
                elseif (a2 == nil) then
                    return 1<0;
                end
                if ( WebDKP_LogSort["way"] == 1 ) then
                    if ( a1[WebDKP_LogSort["curr"]] == a2[WebDKP_LogSort["curr"]] ) then
                        return a1[1] > a2[1];
                    else
                        return a1[WebDKP_LogSort["curr"]] > a2[WebDKP_LogSort["curr"]];
                    end
                else
                    if ( a1[WebDKP_LogSort["curr"]] == a2[WebDKP_LogSort["curr"]] ) then
                        return a1[1] < a2[1];
                    else
                        return a1[WebDKP_LogSort["curr"]] < a2[WebDKP_LogSort["curr"]];
                    end
                end
            end
        end
    );
    
    local numEntries = getn(entries);
    local offset = FauxScrollFrame_GetOffset(WebDKP_FrameScrollFrame);
    FauxScrollFrame_Update(WebDKP_FrameScrollFrame, numEntries, 20, 20);
    
    -- Run through the table lines and put the appropriate information into each line
    for i=1, 20, 1 do
        local line = getglobal("WebDKP_FrameLine" .. i);
        local nameText = getglobal("WebDKP_FrameLine" .. i .. "Name");
        local classText = getglobal("WebDKP_FrameLine" .. i .. "Class");
        local dkpText = getglobal("WebDKP_FrameLine" .. i .. "DKP");
        local tierText = getglobal("WebDKP_FrameLine" .. i .. "Tier");
        local index = i + FauxScrollFrame_GetOffset(WebDKP_FrameScrollFrame); 
        
        if ( index <= numEntries) then
            local playerName = entries[index][1];
            line:Show();
            nameText:SetText(entries[index][1]);
            classText:SetText(entries[index][2]);
            
            -- 显示原始DKP值
            dkpText:SetText(entries[index][3]);
            
            -- 在衰减页面且已计算时，显示衰减值（直接显示实际衰减值）
            if WebDKP_CurrentMode == "decay" and WebDKP_DecayData.calculated and entries[index][4] and entries[index][4] ~= "" then
                local decayValue = tonumber(entries[index][4]) 
                if decayValue then
                    -- 直接显示衰减值（已经是真实值，不需要再乘以0.01）
                    local precisionFormat = "%."..WebDKP_DecayData.precision.."f"
                    local displayValue = string.format(precisionFormat, decayValue)
                    -- WebDKP_Print("显示衰减值调试 - 玩家:"..entries[index][1].." 衰减值:"..displayValue)
                    tierText:SetText("|cffff0000" .. displayValue .. "|r")
                    tierText:SetJustifyH("RIGHT")
                else
                    tierText:SetText("")
                    tierText:SetJustifyH("LEFT")
                end
            else
                -- 其他情况显示原始阶层值或空，恢复左对齐
                tierText:SetText(entries[index][4] or "");
                tierText:SetJustifyH("LEFT")
            end
            
            -- kill the background of this line if it is not selected
            if( not WebDKP_DkpTable[playerName]["Selected"] ) then
                getglobal("WebDKP_FrameLine" .. i .. "Background"):SetVertexColor(0, 0, 0, 0);
            else
                getglobal("WebDKP_FrameLine" .. i .. "Background"):SetVertexColor(0.1, 0.1, 0.9, 0.8);
            end
        else
            -- if the line isn't in use, hide it so we dont' have mouse overs
            line:Hide();
        end
    end
end

-- 确保小地图菜单可以打开衰减窗口
WebDKP_OpenDecayWindow = function()
    -- 直接调用Toggle函数，它已经处理了显示/隐藏的逻辑
    WebDKP_ToggleDecayFrame()
    return true
end

-- 添加斜杠命令来测试衰减窗口
SLASH_WEBDKPDECAY1 = "/decay"
SlashCmdList["WEBDKPDECAY"] = function(msg)
    WebDKP_Print("执行 /decay 命令")
    WebDKP_ToggleDecayFrame()
end

-- 修改列标题文本，默认显示为阶层
local original_WebDKP_OnLoad = WebDKP_OnLoad
WebDKP_OnLoad = function()
    if original_WebDKP_OnLoad then
        original_WebDKP_OnLoad()
    end
    
    -- 初始化默认显示为阶层
    local tierHeader = getglobal("WebDKP_FrameTier")
    if tierHeader and tierHeader:GetText() then
        tierHeader:SetText("阶层")
    end
    
    -- 初始化衰减数据
    WebDKP_DecayData.calculated = false
    WebDKP_DecayData.decayValues = {}
end