-- 物品自动分配系统主文件
local ADKP_AutoLoot = {}

-- 创建主窗口框架
function ADKP_AutoLoot.CreateFrame()
    local frame = CreateFrame("Frame", "ADKP_AutoLootFrame", UIParent)
    frame:SetWidth(200)
    frame:SetHeight(100)
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
    frame:SetScript("OnDragStart", function() this:StartMoving() end)
    frame:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
    
    -- 状态文本
    frame.statusText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.statusText:SetPoint("TOP", 0, -15)
    frame.statusText:SetText("正在分配物品...")
    
    -- 手动分配按钮
    frame.manualButton = CreateFrame("Button", nil, frame, "GameMenuButtonTemplate")
    frame.manualButton:SetPoint("BOTTOM", 0, 15)
    frame.manualButton:SetWidth(120)
    frame.manualButton:SetHeight(25)
    frame.manualButton:SetText("手动分配")
    frame.manualButton:SetScript("OnClick", function()
        frame:Hide()
        ADKP_AutoLoot.StopAutoAssign()
    end)
    
    frame:Hide()
    return frame
end

-- 启动自动分配
function ADKP_AutoLoot.StartAutoAssign(itemLink, playerName)
    -- 简化判断：只检查是否有可分配物品
	    if GetNumLootItems() == 0 then
	        ADKP_AutoLoot.frame.statusText:SetText("错误：没有可分配物品")
	        local isSilentMode = ADKP_Options and ADKP_Options["SilentMode"]
	        if isSilentMode then
	            if ADKP_Print then
	                ADKP_Print("[静默] 无法自动分配物品，请确保:")
	                ADKP_Print("[静默] 1. 已打开尸体并显示战利品")
	                ADKP_Print("[静默] 2. 你是团长/官员")
	                ADKP_Print("[静默] 3. 分配模式为队长分配")
	            end
	        else
	            SendChatMessage("无法自动分配物品，请确保:", "RAID")
	            SendChatMessage("1. 已打开尸体并显示战利品", "RAID")
	            SendChatMessage("2. 你是团长/官员", "RAID") 
	            SendChatMessage("3. 分配模式为队长分配", "RAID")
	        end
	        return false
	    end

    -- 查找匹配的物品
    local foundItem = false
    for i = 1, GetNumLootItems() do
        local link = GetLootSlotLink(i)
        if link and link == itemLink then
            foundItem = true
            -- 查找匹配玩家
            for j = 1, 40 do
                local name = GetMasterLootCandidate(i, j)
                if name and name == playerName then
                    -- 开始分配
                    ADKP_AutoLoot.isAssigning = true
                    ADKP_AutoLoot.currentPlayer = playerName
                    ADKP_AutoLoot.currentItem = string.match(itemLink, "%[(.+)%]")
                    ADKP_AutoLoot.frame.statusText:SetText("正在分配...")
                    ADKP_AutoLoot.frame:Show()
                    GiveMasterLoot(i, j)
                    return true
                end
            end
            if not foundPlayer then
                ADKP_AutoLoot.frame.statusText:SetText("错误：玩家无拾取权")
                return false
            end
        end
    end
    
    if not foundItem then
        ADKP_AutoLoot.frame.statusText:SetText("错误：物品不匹配")
        return false
    end
end

-- 停止自动分配
function ADKP_AutoLoot.StopAutoAssign(success)
    ADKP_AutoLoot.isAssigning = false
    ADKP_AutoLoot.currentPlayer = nil
    ADKP_AutoLoot.currentItem = nil
    if success then
        ADKP_AutoLoot.frame:Hide()
    end
end

-- 全局变量初始化
ADKP_AutoLoot.isAssigning = false
ADKP_AutoLoot.currentPlayer = nil
ADKP_AutoLoot.currentItem = nil

-- 初始化函数
function ADKP_AutoLoot.Init()
    ADKP_AutoLoot.frame = ADKP_AutoLoot.CreateFrame()
end

-- 初始化
ADKP_AutoLoot.Init()
