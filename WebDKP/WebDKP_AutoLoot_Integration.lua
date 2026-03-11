-- WebDKP自动分配系统集成补丁
local WebDKP_AutoLoot_Integration = CreateFrame("Frame")

-- 尝试加载自动分配模块
local autoLoot = LibStub and LibStub:GetLibrary("WebDKP_AutoLoot", true)
if not autoLoot then
    -- 尝试直接加载
    LoadAddOn("WebDKP_AutoLoot")
    autoLoot = _G["WebDKP_AutoLoot"]
end

-- 覆盖原扣分函数
local original_AwardPoints = WebDKP_AwardPoints
function WebDKP_AwardPoints(cost, reason, players)
    -- 调用原函数执行扣分
    original_AwardPoints(cost, reason, players)
    
    -- 检查是否是物品分配
    if reason and string.find(reason, "item:") then
        local _, _, itemLink, playerName = string.find(reason, "(item:.+)|h%[(.+)%]|h to (.+)")
        if itemLink and playerName then
            -- 尝试自动分配
            if autoLoot and autoLoot.StartAutoAssign then
                if not autoLoot.StartAutoAssign(itemLink, playerName) then
                    WebDKP_Print("自动分配失败，请手动分配物品")
                end
            else
                WebDKP_Print("自动分配模块未加载，请手动分配物品")
            end
        end
    end
end

-- 注册事件以确保在WebDKP加载后执行
WebDKP_AutoLoot_Integration:RegisterEvent("ADDON_LOADED")
WebDKP_AutoLoot_Integration:SetScript("OnEvent", function(self, event, addon)
    if addon == "WebDKP" then
        -- WebDKP已加载，可以安全地进行集成
        WebDKP_Print("自动分配系统已集成")
        self:UnregisterEvent("ADDON_LOADED")
    end
end)