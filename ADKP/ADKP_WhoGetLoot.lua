-- ADKP WhoGetLoot 模块 - 无界面版拾取助理
-- 确保兼容WoW 1.12和Lua 5.0

-- 常量定义
WHOGETLOOT_VERSION = "1.1.0"
WHOGETLOOT_MSG_LOAD = "%s 拾取助理已加载!"
WHOGETLOOT_MSG_PATTERN = "(%w+)%s*(获得了物品:|拾取了物品:)"
WHOGETLOOT_MSG_WIN_PATTERN = "(%w+)%s*获得了物品:"
WHOGETLOOT_MSG_LOOT_PATTERN = "%[(.+)%]"
WHOGETLOOT_MSG_WIN_LOOT_PATTERN = "%[(.+)%]"
WHOGETLOOT_MSG_SYSTEM_MESSAGE_JOIN = "你加入了一个团队。"
WHOGETLOOT_MSG_SYSTEM_MESSAGE_LEAVE = "你离开了队伍。"

-- 全局变量初始化
ADKP_WhoGetLoot = {
    isEnabled = false,        -- 是否启用自动扫描
    lootRecord = {},         -- 记录拾取信息
    warnedPlayers = {},      -- 用于避免重复警告
    lastBid = {},            -- 记录最后出价
    recentLoots = {}         -- 最近的拾取记录，用于快速查询
}

-- Lua 5.0兼容函数 - 获取表长度
_G["table_length"] = function(t)
    local count = 0
    for _ in pairs(t) do
        count = count + 1
    end
    return count
end

-- 确保ADKP_Print函数存在
if not ADKP_Print then
    _G["ADKP_Print"] = function(message)
        DEFAULT_CHAT_FRAME:AddMessage("[ADKP] " .. message)
    end
end

-- 拾取助理主函数 - 用于切换自动扫描功能
_G["ADKP_ToggleWhoGetLoot"] = function()
    ADKP_WhoGetLoot.isEnabled = not ADKP_WhoGetLoot.isEnabled
    
    if ADKP_WhoGetLoot.isEnabled then
        ADKP_Print("拾取助理已启用 - 开始自动扫描拾取信息")
        ADKP_WhoGetLoot_RegisterEvents()
    else
        ADKP_Print("拾取助理已禁用 - 停止自动扫描拾取信息")
        ADKP_WhoGetLoot_UnregisterEvents()
    end
end

-- 注册事件
_G["ADKP_WhoGetLoot_RegisterEvents"] = function()
    if not ADKP_WhoGetLootEventFrame then
        ADKP_WhoGetLootEventFrame = CreateFrame("Frame", "ADKP_WhoGetLootEventFrame")
        ADKP_WhoGetLootEventFrame:SetScript("OnEvent", ADKP_WhoGetLoot_OnEvent)
    end
    ADKP_WhoGetLootEventFrame:RegisterEvent("CHAT_MSG_LOOT")
    ADKP_WhoGetLootEventFrame:RegisterEvent("CHAT_MSG_RAID")
    ADKP_WhoGetLootEventFrame:RegisterEvent("CHAT_MSG_RAID_LEADER")
    ADKP_WhoGetLootEventFrame:RegisterEvent("VARIABLES_LOADED")
    ADKP_WhoGetLootEventFrame:RegisterEvent("CHAT_MSG_SYSTEM")
end

-- 注销事件
_G["ADKP_WhoGetLoot_UnregisterEvents"] = function()
    if ADKP_WhoGetLootEventFrame then
        ADKP_WhoGetLootEventFrame:UnregisterEvent("CHAT_MSG_LOOT")
        ADKP_WhoGetLootEventFrame:UnregisterEvent("CHAT_MSG_RAID")
        ADKP_WhoGetLootEventFrame:UnregisterEvent("CHAT_MSG_RAID_LEADER")
    end
end

-- 事件处理
_G["ADKP_WhoGetLoot_OnEvent"] = function()
    -- 捕获团队频道中的数字出价
    if event == "CHAT_MSG_RAID" or event == "CHAT_MSG_RAID_LEADER" then
        local num = tonumber(arg1)
        if num and num >= 0 then  -- 移除上限限制，支持任意大的出分数值
            local playerName = arg2
            ADKP_WhoGetLoot.lastBid[playerName] = { num = num, time = GetTime() }
            
            -- 检查出价是否超过玩家可用分数（即使拾取助理未启用也要检查）
            ADKP_WhoGetLoot_check_bid(playerName, num)
        end
    end

    -- 处理拾取消息
    if event == "CHAT_MSG_LOOT" then
        if ADKP_WhoGetLoot.isEnabled then
            ADKP_WhoGetLoot_handle_loot_message(arg1)
        end
    end

    -- 初始化
    if event == "VARIABLES_LOADED" then
        ADKP_WhoGetLoot_Initialize()
    end

    -- 团队加入/离开处理
    if event == "CHAT_MSG_SYSTEM" then
        if arg1 == WHOGETLOOT_MSG_SYSTEM_MESSAGE_JOIN then
            ADKP_WhoGetLoot_start_listen()
        elseif arg1 == WHOGETLOOT_MSG_SYSTEM_MESSAGE_LEAVE then
            ADKP_WhoGetLoot_stop_listen()
        end
    end
end

-- 检查出价是否超过可用分数
_G["ADKP_WhoGetLoot_check_bid"] = function(playerName, bidAmount)
    -- 获取玩家可用分数
    local availableDkp = 0
    -- 确保正确获取玩家DKP分数
    if ADKP_GetDKP then
        availableDkp = ADKP_GetDKP(playerName)
    elseif ADKP and ADKP.GetDKP then
        availableDkp = ADKP.GetDKP(playerName)
    elseif ADKP_DkpTable and ADKP_GetTableid then
        local tableid = ADKP_GetTableid()
        if ADKP_DkpTable[playerName] and ADKP_DkpTable[playerName]["dkp_"..tableid] then
            availableDkp = ADKP_DkpTable[playerName]["dkp_"..tableid]
        end
    end
    
    -- 如果出价超过可用分数，发送警告，无论DKP是否为负数
    if bidAmount > availableDkp then
        -- 避免重复警告
        if not ADKP_WhoGetLoot.warnedPlayers[playerName] or ADKP_WhoGetLoot.warnedPlayers[playerName] ~= bidAmount then
            ADKP_WhoGetLoot.warnedPlayers[playerName] = bidAmount
            local warningMsg = "警告: "..playerName.." 出分 "..bidAmount.." 超过其可用分数 "..availableDkp
            
            -- 在本地聊天框显示警告
            -- ADKP_Print(warningMsg)
            
            -- 在团队警告频道播报警告（遵循静默模式）
	            if ADKP_SendAnnouncement then
	                ADKP_SendAnnouncement(warningMsg, "RAID", true)
	            elseif SendChatMessage then
	                local isSilentMode = ADKP_Options and ADKP_Options["SilentMode"]
	                if isSilentMode then
	                    if ADKP_Print then
	                        ADKP_Print("[静默] " .. warningMsg)
	                    end
	                else
	                    SendChatMessage(warningMsg, "RAID")
	                end
	            end
	        end
	    end
end

-- 验证玩家名称是否合理
local function IsValidPlayerName(name)
    if not name or string.len(name) < 2 or string.len(name) > 20 then
        return false
    end
    -- 检查是否包含明显的消息内容
    if string.find(name, "获得了物品") or string.find(name, "拾取了物品") or 
       string.find(name, "扣除DKP") or string.find(name, "获得了") then
        return false
    end
    -- 检查是否包含特殊字符或标点符号
    if string.find(name, "[。：%[%]%(%)%{%}%+%-%*%?%$%^]") then
        return false
    end
    return true
end

-- 处理拾取消息
_G["ADKP_WhoGetLoot_handle_loot_message"] = function(message)
    -- 打印详细调试信息
    -- ADKP_Print("[调试] 接收到拾取消息原始内容: "..message)
    
    -- 使用增强的解析函数
    local player, item = ADKP_ParseLootMessage(message)
    
    if player and item then
        -- 打印解析结果的调试信息
        -- ADKP_Print("[调试] 解析结果 - 玩家: "..player.." 物品: "..item)
        -- ADKP_Print("[调试] 物品内容类型: "..type(item).." 物品长度: "..string.len(item))
        -- 直接从消息中提取颜色代码
        local colorPart = string.match(message, '|c(%x+)|Hitem')
        -- print("颜色部分: "..tostring(colorPart))
        
        -- 颜色代码到品质等级的映射
        local colorToQuality = {
        ["ff9d9d9d"] = 0, -- 灰色/垃圾
        ["ffffffff"] = 1, -- 白色/普通
        ["ff1eff00"] = 2, -- 绿色/优秀
        ["ff0070dd"] = 3, -- 蓝色/精良
        ["ffa335ee"] = 4, -- 紫色/史诗
        ["ffff8000"] = 5, -- 橙色/传说
        ["ffe6cc80"] = 6  -- 金色/神器
        }
        
        -- 获取物品品质
        local itemRarity = 0
        if colorPart then
            -- 转换为小写以确保匹配
            colorPart = string.lower(colorPart)
            itemRarity = colorToQuality[colorPart] or 0
            -- print("根据颜色代码确定的品质等级: "..itemRarity)
        end
        
        -- 验证玩家名称的合理性
        if not IsValidPlayerName(player) then
            -- ADKP_Print("错误：解析到的玩家名称不合理："..player)
            -- ADKP_Print("原始消息："..message)
            return
        end
        
        -- 清理玩家名称
        player = string.match(player, "^([^-]+)") or player
        
        -- 记录拾取信息
        local now = date("%Y-%m-%d %H:%M:%S")
        
        -- 记录到recentLoots，用于快速查询
        ADKP_WhoGetLoot.recentLoots[player] = {
            item = item,
            time = now,
            timestamp = time()
        }
        
        -- 同时记录到lootRecord，确保拾取信息被完整保存
        table.insert(ADKP_WhoGetLoot.lootRecord, {
            player = player,
            item = item,
            time = now,
            timestamp = time()
        })
        
        -- ADKP_Print("已记录拾取："..player.." 获得了 "..item)
        
        -- 尝试查询玩家的最后出价，传入物品品质
        ADKP_WhoGetLoot_process_loot_with_bid(player, item, itemRarity)
    else
        -- 解析失败时输出调试信息
        -- ADKP_Print("[调试] 无法解析拾取消息："..message)
    end
end

-- 处理拾取并关联出价
_G["ADKP_WhoGetLoot_process_loot_with_bid"] = function(player, item, itemRarity)
    -- 标准化玩家名称，移除可能的特殊字符
    local normalizedPlayer = string.gsub(player, "[<>%[%]]", "")
    normalizedPlayer = string.gsub(normalizedPlayer, "^%s+", "")
    normalizedPlayer = string.gsub(normalizedPlayer, "%s+$", "")
    
    if normalizedPlayer ~= player then
        player = normalizedPlayer
    end
    
    -- 定义物品品质常量 (Lua 5.0兼容)
    local ITEM_QUALITY_UNCOMMON = 2 -- 绿色
    local ITEM_QUALITY_RARE = 3     -- 蓝色
    local ITEM_QUALITY_EPIC = 4     -- 紫色
    local ITEM_QUALITY_LEGENDARY = 5 -- 橙色
    
    -- 默认记录高品质物品
    local shouldRecord = false
    
    -- 获取全局品质过滤设置
    local qualityLevel = 1 -- 默认为1（橙紫）
    if ADKP_Options and ADKP_Options["LootQualityLevel"] then
        qualityLevel = ADKP_Options["LootQualityLevel"]
    end
    
    -- 确保itemRarity有值
    if not itemRarity then
        itemRarity = 0
        -- ADKP_Print("[调试] 物品品质未定义，默认设为0")
    end
    
    -- 使用从颜色代码直接获取的物品品质
    -- ADKP_Print("[调试] 使用从颜色代码获取的物品品质: "..itemRarity..", 过滤等级: "..qualityLevel)
    
    -- 根据品质等级设置判断是否记录
    if (qualityLevel == 1 and (itemRarity == ITEM_QUALITY_EPIC or itemRarity == ITEM_QUALITY_LEGENDARY)) or
       (qualityLevel == 2 and itemRarity >= ITEM_QUALITY_RARE) or
       (qualityLevel == 3 and itemRarity >= ITEM_QUALITY_UNCOMMON) then
        shouldRecord = true
        -- ADKP_Print("已记录拾取："..player.." 获得了 "..item.." (品质等级: "..itemRarity..")")
    else
        -- 不符合品质要求，不记录
        -- ADKP_Print("忽略低品质物品："..item.." (品质等级: "..itemRarity..")")
        return -- 直接返回，不处理低品质物品
    end
    
    -- 只有shouldRecord为true时才处理拾取信息
    if shouldRecord then
        -- 检查是否有该玩家的最近出价
        if ADKP_WhoGetLoot.lastBid[player] then
            local bidInfo = ADKP_WhoGetLoot.lastBid[player]
            local bidAmount = bidInfo.num
            local bidTime = bidInfo.time
            local currentTime = GetTime()
            
            -- 添加调试信息，显示玩家的最近出价
            -- ADKP_Print("玩家 "..player.." 的最近出价: "..bidAmount..", 时间差: "..(currentTime - bidTime).."秒")
            
            -- 检查出价是否在合理时间范围内（例如5分钟内）
            if currentTime - bidTime < 300 then
                -- ADKP_Print("检测到 "..player.." 最近出价: "..bidAmount.." (在时间范围内)")
                
                -- 添加到装备奖惩
                ADKP_WhoGetLoot_add_to_loot_record(player, item, bidAmount)

            else
                -- 添加调试信息，显示当前所有记录的出价
                local bidInfo = "当前记录的出价: "
                for name, bid in pairs(ADKP_WhoGetLoot.lastBid) do
                    bidInfo = bidInfo..name.."="..bid.num.." "
                end
                ADKP_Print(bidInfo)
                ADKP_Print("未检测到 "..player.." 的最近出价记录")
                
                -- 尝试模糊匹配，查找可能的玩家名称变体
                local foundMatch = false
                for name, bid in pairs(ADKP_WhoGetLoot.lastBid) do
                    -- 首先验证原始玩家名称的合理性
                    if IsValidPlayerName(player) then
                        -- 检查玩家名称是否相似（忽略大小写）
                        local lowerPlayer = string.lower(player)
                        local lowerName = string.lower(name)
                        
                        -- 确保玩家名长度合理，防止将整个消息作为玩家名
                        if string.len(player) <= 20 and string.len(player) >= 2 then
                            -- 如果名称相似且没有特殊字符
                            if string.find(lowerName, lowerPlayer) or string.find(lowerPlayer, lowerName) then
                                ADKP_Print("发现可能的玩家名称匹配: "..name.." -> "..player)
                                local currentTime = GetTime()
                                
                                if currentTime - bid.time < 300 then
                                    ADKP_Print("使用模糊匹配的出价: "..name.." = "..bid.num)
                                    -- 更新记录，使用正确的玩家名称
                                    ADKP_WhoGetLoot.lastBid[player] = bid
                                    -- 添加到装备奖惩
                                    ADKP_WhoGetLoot_add_to_loot_record(player, item, bid.num)
                                    foundMatch = true
                                    break
                                end
                            end
                        end
                    end
                end
                
                -- 如果没有找到匹配的出价，记录拾取但扣分为0
                if not foundMatch then
                    ADKP_WhoGetLoot_add_to_loot_record(player, item, 0)
                end
            end
        else
            -- 没有找到玩家出价记录，记录拾取但扣分为0
            ADKP_WhoGetLoot_add_to_loot_record(player, item, 0)
        end
end
end
-- 添加到装备奖惩记录
_G["ADKP_WhoGetLoot_add_to_loot_record"] = function(player, item, cost)
    -- 即使ADKP未加载，也继续处理，创建自己的数据结构
    if not ADKP then
        -- ADKP_Print("ADKP未加载，创建独立数据结构处理DKP记录")
        
        -- 创建ADKP全局表（如果不存在）
        if not _G.ADKP then
            _G.ADKP = {}
        end
        
        -- 创建必要的数据结构
        if not ADKP_Loot then
            ADKP_Loot = {}
        end
        if not ADKP_DkpTable then
            ADKP_DkpTable = {}
        end
        if not ADKP_Log then
            ADKP_Log = {}
        end
    end
    
    -- 确保只有在拾取助理启用时才处理DKP扣除
    if not ADKP_WhoGetLoot.isEnabled then
        ADKP_Print("拾取助理未启用，跳过DKP扣除")
        return
    end
    
    -- 仅保留关键信息输出（只有cost>0时才显示）
    if cost > 0 then
        ADKP_Print(player.." 获得了 "..item.." 扣除DKP: "..cost)
    end
    
    -- 获取ADKP_GetTableid函数或创建一个默认实现
    local getTableIdFunc = ADKP_GetTableid
    if not getTableIdFunc then
        getTableIdFunc = function() return "main" end
    end
    
    -- 首先检查玩家的DKP是否足够
    local availableDkp = 0
    local hasDkpCheck = false
    local tableid = getTableIdFunc()
    
    -- 优先使用ADKP_DkpTable检查DKP
    if ADKP_DkpTable then
        if not ADKP_DkpTable[player] then
            ADKP_DkpTable[player] = {}
        end
        if not ADKP_DkpTable[player]["dkp_"..tableid] then
            ADKP_DkpTable[player]["dkp_"..tableid] = 0
        end
        availableDkp = ADKP_DkpTable[player]["dkp_"..tableid]
        hasDkpCheck = true
    -- 其次尝试使用ADKP的函数
    elseif ADKP_GetDKP then
        availableDkp = ADKP_GetDKP(player)
        hasDkpCheck = true
    elseif ADKP and ADKP.GetDKP then
        availableDkp = ADKP.GetDKP(player)
        hasDkpCheck = true
    end
    
	        if hasDkpCheck then
	        -- 只在DKP不足时发出警告，无论DKP是否为负数
	        if cost > availableDkp then
	            local warningMsg = "警告: "..player.." 的DKP不足! 出价: "..cost..", 可用: "..availableDkp

	            if SendChatMessage then
	                local isSilentMode = ADKP_Options and ADKP_Options["SilentMode"]
	                if isSilentMode then
	                    if ADKP_Print then
	                        ADKP_Print("[静默] " .. warningMsg)
	                    end
	                else
	                    SendChatMessage(warningMsg, "RAID")
	                end
	            end
	        end
	    end
    
    -- 构建物品链接格式，以便在确认框中显示
    local itemLink = "["..item.."]"
    local confirmMsg = "授予 "..player.." "..itemLink.." 扣除 "..cost.." DKP?"
    
    -- 移除多余的调试信息
    
    -- 确保不会调用任何会弹出确认框的函数
    if ADKP_ShowAwardFrame then
        -- 临时备份并禁用ADKP_ShowAwardFrame函数，防止弹出确认框
        ADKP_ShowAwardFrame = function()
            return true
        end
    end
    
    -- 1. 尝试使用ADKP的物品奖励功能（奖惩装备）
    if ADKP and ADKP.AddDKP then
        local success, err = pcall(function()
            -- 创建一个符合ADKP_AddDKP函数要求的玩家表
            local targetPlayer = {}
            targetPlayer[0] = { 
                ["name"] = player,
                ["class"] = ADKP_DkpTable[player] and ADKP_DkpTable[player]["class"] or "未知"
            }
            
            -- 使用ADKP_AddDKP函数，第三个参数为"true"表示物品奖励，确保正确记录到奖惩装备类别
            ADKP.AddDKP(-cost, item, "true", targetPlayer)
        end)
        
        if success then
            -- ADKP_AddDKP函数内部已经处理了团队通知和UI更新
            return
        else
            -- 如果ADKP_AddDKP失败，尝试备用方案
            ADKP_Print("ADKP_AddDKP调用失败，尝试备用扣除方案")
        end
    end
    
    -- 如果AwardPlayerDKP失败，尝试直接操作数据结构
    local currentTime = date("%Y-%m-%d %H:%M:%S")
    local deductionSuccess = false
    
    -- 1. 尝试直接操作数据结构（即使ADKP未完全加载）
    if ADKP_Loot then
        
        -- 添加到ADKP_Loot表
        table.insert(ADKP_Loot, {
            playername = player,
            itemname = item,
            cost = cost,
            time = currentTime
        })
        
        -- 确保ADKP_DkpTable存在并扣除DKP
        if ADKP_DkpTable then
            local tableid = getTableIdFunc()
            if not ADKP_DkpTable[player] then
                ADKP_DkpTable[player] = {}
            end
            if not ADKP_DkpTable[player]["dkp_"..tableid] then
                ADKP_DkpTable[player]["dkp_"..tableid] = 0
            end
            ADKP_DkpTable[player]["dkp_"..tableid] = ADKP_DkpTable[player]["dkp_"..tableid] - cost
            
            -- 更新日志，使用正确的格式记录，确保与ADKP_AddDKP函数生成的格式一致
            if ADKP_Log then
                ADKP_Log["Version"] = 2; -- 确保版本标记正确
                -- 创建正确格式的日志条目
                local logKey = item .. " " .. currentTime;
                ADKP_Log[logKey] = {
                    date = currentTime,
                    reason = item,
                    foritem = "true",
                    zone = GetZoneText(),
                    tableid = ADKP_GetTableid and ADKP_GetTableid() or 1,
                    awardedby = UnitName("player"),
                    points = -cost,
                    uniqueId = "loot_" .. (ADKP_GetTableSize(ADKP_Log) + 1) .. "_" .. player .. "_" .. currentTime, -- 添加唯一标识符
                    awarded = {
                        [player] = {
                            name = player,
                            class = ADKP_DkpTable[player] and ADKP_DkpTable[player]["class"] or "未知",
                            guild = ADKP_GetGuildName and ADKP_GetGuildName(player) or nil
                        }
                    }
                }
                
                -- 保存数据到磁盘（如果可用）
                if ADKP_SaveToDisk then
                    ADKP_SaveToDisk();
                end
                
                -- 同时添加到ADKP_LootHistory用于修改功能
                if not ADKP_LootHistory then
                    ADKP_LootHistory = {}
                end
                table.insert(ADKP_LootHistory, {
                    item = item,
                    player = player,
                    points = -cost,  -- 使用points字段，装备花费为负数
                    time = currentTime,
                    uniqueId = "loot_" .. (ADKP_GetTableSize(ADKP_Log) + 1) .. "_" .. player .. "_" .. currentTime
                    -- 注意：这里不使用cost字段，只使用points字段表示花费（负数）
                })
            end
            
            deductionSuccess = true
        end
    end
    
    -- 2. 如果上面的方法失败，尝试其他ADKP方法
    if not deductionSuccess then
        if ADKP and ADKP.AddLootItem then
            ADKP.AddLootItem(player, item, cost, currentTime)
            deductionSuccess = true
        elseif ADKP and ADKP.AddItemToLootList then
            ADKP.AddItemToLootList(player, item, cost)
            deductionSuccess = true
        -- 直接操作数据结构作为备用方案
        elseif not deductionSuccess then
            -- 确保基本的数据结构存在
            if not ADKP_DkpTable then
                ADKP_DkpTable = {}
            end
            if not ADKP_Loot then
                ADKP_Loot = {}
            end
            
            -- 添加到ADKP_Loot表
            table.insert(ADKP_Loot, {
                playername = player,
                itemname = item,
                cost = cost,
                time = currentTime
            })
            
            -- 确保玩家有DKP记录并扣除
            local tableid = getTableIdFunc()
            if not ADKP_DkpTable[player] then
                ADKP_DkpTable[player] = {}
            end
            if not ADKP_DkpTable[player]["dkp_"..tableid] then
                ADKP_DkpTable[player]["dkp_"..tableid] = 0
            end
            ADKP_DkpTable[player]["dkp_"..tableid] = ADKP_DkpTable[player]["dkp_"..tableid] - cost
            
            deductionSuccess = true
        end
    end
    
    -- 通知成功或失败
	    if deductionSuccess then
	        local successMsg = player.." 获得 "..item.." 扣除DKP: "..cost
	        
	        -- 在团队频道播报（只有cost>0时才播报）
	        if cost > 0 and SendChatMessage then
	            local isSilentMode = ADKP_Options and ADKP_Options["SilentMode"]
	            if isSilentMode then
	                if ADKP_Print then
	                    ADKP_Print("[静默] " .. successMsg)
	                end
	            else
	                SendChatMessage(successMsg, "RAID")
	            end
	        end
        
        -- 清除所有玩家的出价记录
        if ADKP_WhoGetLoot and ADKP_WhoGetLoot.lastBid then
            ADKP_WhoGetLoot.lastBid = {}
        end
        
        -- 确保保存数据到磁盘（如果可用）
        if ADKP_SaveToDisk then
            ADKP_SaveToDisk();
        end
        
        -- 更新DKP表格和UI（如果可用）
        if ADKP_UpdateTable then
            ADKP_UpdateTable()
        end
        if ADKP_UpdateTableToShow then
            ADKP_UpdateTableToShow()
        end
        
        -- 刷新装备获取记录列表（这是关键函数，确保装备记录正确更新）
        if ADKP_UpdateLootList then
            ADKP_UpdateLootList()
        end
        
        -- 额外刷新拾取记录UI（如果有相关函数）
        if ADKP_RefreshLootRecords then
            ADKP_RefreshLootRecords()
        end
    else
        -- 静默失败，不在聊天框显示错误
    end
end

-- 解析拾取信息
_G["ADKP_ParseLootMessage"] = function(message)
    -- 匹配多种拾取信息格式
    local player, item
    
    -- 首先检查是否是自己拾取的情况（中文）
    if string.find(message, "你获得了物品") or string.find(message, "你拾取了物品") then
        item = string.match(message, "%[(.+)%]")
        if item then
            return UnitName("player"), item
        end
    end
    
    -- 增强中文格式匹配，特别是针对用户聊天记录中的格式
    -- 先尝试严格匹配标准格式：玩家名 获得了物品：[物品名]。
    player, item = string.match(message, "^(.-)获得了物品：%[(.+)%]。")
    if player and item then
        -- 清理玩家名称，移除可能的特殊字符或空格
        player = string.gsub(player, "^%s+", "") -- 移除开头空格
        player = string.gsub(player, "%s+$", "") -- 移除结尾空格
        -- 确保玩家名不包含特殊字符或多余文字
        if not string.find(player, "获得了物品") and not string.find(player, "拾取了物品") then
            -- ADKP_Print("成功匹配标准格式: "..player.." 获得了 "..item)
            return player, item
        end
    end
    
    -- 尝试匹配无句号结尾的格式
    player, item = string.match(message, "^(.-)获得了物品：%[(.+)%]")
    if player and item then
        player = string.gsub(player, "^%s+", "")
        player = string.gsub(player, "%s+$", "")
        if not string.find(player, "获得了物品") and not string.find(player, "拾取了物品") then
            -- ADKP_Print("成功匹配无句号格式: "..player.." 获得了 "..item)
            return player, item
        end
    end
    
    -- 额外的格式匹配，处理"已记录拾取：Janis获得了物品：[恶魔颅壳]。"这样的格式
    player = string.match(message, "已记录拾取：(.-)获得了物品：")
    if player then
        item = string.match(message, "%[(.+)%]")
        if item then
            player = string.gsub(player, "^%s+", "")
            player = string.gsub(player, "%s+$", "")
            if not string.find(player, "获得了物品") and not string.find(player, "拾取了物品") then
                -- ADKP_Print("成功匹配记录格式: "..player.." 获得了 "..item)
                return player, item
            end
        end
    end
    
    -- 尝试直接从消息中提取玩家名和物品名（最宽松的匹配）
    if string.find(message, "获得了物品") or string.find(message, "拾取了物品") then
        -- 尝试获取第一个非空白字符串作为玩家名
        local firstWord = string.match(message, "^%s*([^%s]+)")
        if firstWord and string.match(firstWord, "^[^%s]*") then
            -- 验证第一个词不是"获得了物品"或"拾取了物品"
            if not string.find(firstWord, "获得了物品") and not string.find(firstWord, "拾取了物品") then
                player = firstWord
                item = string.match(message, "%[(.+)%]")
                if item then
                    -- ADKP_Print("宽松匹配: "..player.." 获得了 "..item)
                    return player, item
                end
            end
        end
    end
    
    -- 使用表存储所有可能的模式，方便维护和扩展
    local patterns = {
        -- 标准中文格式
        {pattern = "([^%s]+) 获得了物品: .-%[(.+)%]", desc = "标准格式1"},
        {pattern = "([^%s]+) 拾取了物品: .-%[(.+)%]", desc = "标准格式2"},
        {pattern = "(.+)获得了物品：%[(.+)%]。", desc = "带标点格式1"},
        {pattern = "(.+) 获得了物品 %[(.+)%]", desc = "标准格式3"},
        {pattern = "([^%s]+)获得了物品：%[(.+)%]", desc = "无空格格式1"},
        {pattern = "([^%s]+)拾取了物品：%[(.+)%]", desc = "无空格格式2"},
        {pattern = "([^%s]+)获得了物品：%[(.+)%]。", desc = "无空格格式3"},
        {pattern = "([^%s]+)拾取了物品：%[(.+)%]。", desc = "无空格格式4"},
        -- 可能的英文格式
        {pattern = "(.+) received item: .-%[(.+)%]", desc = "英文格式1"},
        {pattern = "(.+) looted item: .-%[(.+)%]", desc = "英文格式2"},
        -- 可能的空格变化
        {pattern = "([^%s]+)%s-获得了物品:%s-.-%[(.+)%]", desc = "空格变化1"},
        {pattern = "([^%s]+)%s-拾取了物品:%s-.-%[(.+)%]", desc = "空格变化2"},
        {pattern = "([^%s]+)%s-获得了物品：%s-.-%[(.+)%]", desc = "空格变化3"},
        {pattern = "([^%s]+)%s-拾取了物品：%s-.-%[(.+)%]", desc = "空格变化4"},
    }
    
    -- 遍历所有模式进行匹配
    for _, p in pairs(patterns) do
        player, item = string.match(message, p.pattern)
        if player and item then
            -- 清理玩家名称，移除可能的特殊字符或空格
            player = string.gsub(player, "^%s+", "") -- 移除开头空格
            player = string.gsub(player, "%s+$", "") -- 移除结尾空格
            -- 移除可能的特殊符号
            player = string.gsub(player, "[<>%[%]]", "")
            -- ADKP_Print("成功匹配"..p.desc..": "..player.." 获得了 "..item)
            return player, item
        end
    end
    
    -- 最后的尝试：最宽松的格式匹配
    player = string.match(message, "([^%s]+)")  -- 第一个非空格字符串作为玩家名
    
    -- 尝试匹配有中括号的物品名
    item = string.match(message, "%[(.+)%]")    -- 中括号中的内容作为物品名
    
    -- 如果没有找到带中括号的物品名，尝试匹配"获得了"后面的内容
    if player and not item and string.find(message, "获得了") then
        item = string.match(message, "获得了%s+(.+)")
        if item then
            -- 清理物品名，移除可能的句号或其他标点
            item = string.gsub(item, "%.$", "")
            item = string.gsub(item, "%s+$", "")
            ADKP_Print("匹配无中括号格式: "..player.." 获得了 "..item)
            return player, item
        end
    end
    
    if player and item then
        return player, item
    end
    
    -- 匹配自己拾取的情况（英文）
    item = string.match(message, "You receive loot: .-%[(.+)%]")
    if item then
        return UnitName("player"), item
    end
    
    -- 匹配英文格式
    player, item = string.match(message, "([^%s]+) receives item: .-%[(.+)%]")
    if player and item then
        return player, item
    end
    
    player, item = string.match(message, "([^%s]+) loots item: .-%[(.+)%]")
    if player and item then
        return player, item
    end
    
    return nil, nil
end

-- 开始监听
_G["ADKP_WhoGetLoot_start_listen"] = function()
    -- 移除对不存在变量的引用，统一使用isEnabled控制
    ADKP_Print("已开始监听拾取信息")
end

-- 停止监听
_G["ADKP_WhoGetLoot_stop_listen"] = function()
    -- 移除对不存在变量的引用，统一使用isEnabled控制
    ADKP_Print("已停止监听拾取信息")
end

-- 初始化函数
_G["ADKP_WhoGetLoot_Initialize"] = function()
    -- 初始化必要的变量
    if not ADKP_WhoGetLoot.lootRecord then
        ADKP_WhoGetLoot.lootRecord = {}
    end
    
    if not ADKP_WhoGetLoot.recentLoots then
        ADKP_WhoGetLoot.recentLoots = {}
    end
    
    if not ADKP_WhoGetLoot.lastBid then
        ADKP_WhoGetLoot.lastBid = {}
    end
    
    if not ADKP_WhoGetLoot.warnedPlayers then
        ADKP_WhoGetLoot.warnedPlayers = {}
    end
    
    -- 注册命令
    SLASH_WEBKPWHOGETLOOT1 = "/wgl"
    SLASH_WEBKPWHOGETLOOT2 = "/adkpwhogetloot"
    SLASH_WEBKPWHOGETLOOT3 = "/adkpwhogetloot"
    SlashCmdList["WEBKPWHOGETLOOT"] = function(msg)
        if msg and string.lower(msg) == "show" then
            -- 显示当前拾取记录
            ADKP_ShowLootRecords()
        else
            -- 默认切换拾取助理功能
            ADKP_ToggleWhoGetLoot()
        end
    end
    
    -- 显示拾取记录函数
    _G["ADKP_ShowLootRecords"] = function()
        ADKP_Print("当前拾取记录:")
        if not ADKP_WhoGetLoot.lootRecord or table_length(ADKP_WhoGetLoot.lootRecord) == 0 then
            ADKP_Print("暂无拾取记录")
        else
            for i, record in pairs(ADKP_WhoGetLoot.lootRecord) do
                if record.player and record.item and record.time then
                    ADKP_Print(string.format("%d. %s 获得了 %s [%s]", i, record.player, record.item, record.time))
                end
            end
        end
        
        -- 同时显示recentLoots中的记录
        if ADKP_WhoGetLoot.recentLoots then
            local recentCount = 0
            for player, data in pairs(ADKP_WhoGetLoot.recentLoots) do
                recentCount = recentCount + 1
            end
            ADKP_Print(string.format("最近拾取记录数量: %d", recentCount))
        end
    end
    
    -- 打印加载信息
    ADKP_Print(string.format(WHOGETLOOT_MSG_LOAD, WHOGETLOOT_VERSION))
    ADKP_Print("输入 /wgl 或 /adkpwhogetloot 切换拾取助理功能")
    ADKP_Print("输入 /wgl show 查看当前拾取记录")
end

-- 确保在插件加载时初始化
ADKP_WhoGetLoot_Initialize()

-- 注意：ADKP_ToggleWhoGetLoot函数已在ADKP.lua的迷你地图下拉菜单中绑定
-- 用户可以通过点击迷你地图按钮->拾取助理 或使用 /wgl 命令来切换功能
