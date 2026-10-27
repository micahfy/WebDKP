local table = ADKP_LegacyTable
local originalSlash = ADKP_SlashCmdHandler
function ADKP_SlashCmdHandler(text)
    if ADKP_ForeverTrim(text or "") == "diag" then ADKP_ForeverDiagnostics(); return end
    return originalSlash(text)
end
SLASH_ADKP1, SLASH_ADKP2 = "/adkp", "/dkp"
SlashCmdList.ADKP = ADKP_SlashCmdHandler
SlashCmdList.ADKPSHARE = function(message)
    local args, err = ADKP_ForeverArguments(message or "")
    if not args then ADKP_Print(err); return end
    if table.getn(args) == 2 then ADKP_Share_Bind(args[1], args[2])
    else ADKP_Share_ShowManager(ADKP_ForeverName("target") or ADKP_ForeverName("player")) end
end

-- The original award implementation creates missing players at zero. Preserve
-- that behavior, while rejecting an unreadable whole roster before any writes.
local originalAdd = ADKP_AddDKP
function ADKP_AddDKP(points, reason, item, players, ...)
    for _, player in pairs(players or {}) do
        if type(player) == "table" and (not ADKP_IsPublic(player.name) or type(player.name) ~= "string" or player.name == "") then
            ADKP_Print("完整玩家名不可读取，未执行本次奖惩。"); return nil
        end
    end
    return originalAdd(points, reason, item, players, ...)
end

local frame = CreateFrame("Frame", "ADKP_ForeverNativeEvents")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("ENCOUNTER_START"); frame:RegisterEvent("ENCOUNTER_END"); frame:RegisterEvent("BOSS_KILL")
frame:SetScript("OnEvent", function(_, event, id, name, difficulty, size, success)
    if event == "PLAYER_LOGIN" then
        local version = GetBuildInfo()
        if not string.match(version or "", "^1%.60%.") or not RegionalUniqueNamesEnabled or not RegionalUniqueNamesEnabled() then
            ADKP_Print("此移植包用于无限 1.60 客户端；当前客户端不匹配。"); return
        end
        if C_AddOns and C_AddOns.IsAddOnLoaded then
            for _, other in ipairs({"ADKP", "ADKP_Forever_Classic", "ADKP_Forever"}) do
                if other ~= ADKP_FOREVER_ADDON and C_AddOns.IsAddOnLoaded(other) then
                    ADKP_Print("请禁用其他目录中的 ADKP 版本，避免同时写入同名保存变量。"); return
                end
            end
        end
        ADKP_ForeverInitializeOriginal()
        ADKP_ForeverInstallAuctionHandlers()
        ADKP_ForeverInstallUIHooks()
        ADKP_Print("原版克隆移植已加载，版本 " .. ADKP_VERSION .. "。/adkp diag 可查看接口状态。")
    elseif event == "ENCOUNTER_START" then
        if not ADKP_IsPublic(id) then return end
        local instance = GetInstanceInfo and select(8, GetInstanceInfo()) or 0
        if not ADKP_IsPublic(instance) then return end
        if WebDKP_Options and WebDKP_Options.ForeverBossSeen then
            WebDKP_Options.ForeverBossSeen[ADKP_GetTableid() .. ":" .. tostring(instance) .. ":" .. id] = nil
        end
    elseif event == "ENCOUNTER_END" then ADKP_ForeverOfficialBoss(id, name, success)
    elseif event == "BOSS_KILL" then ADKP_ForeverOfficialBoss(id, name, 1) end
end)
