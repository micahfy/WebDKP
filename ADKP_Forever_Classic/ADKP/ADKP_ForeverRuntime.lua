-- Keep the original business functions; adapt their native entry points here.
local originalLoad = ADKP_OnLoad
function ADKP_OnLoad() end -- Initialize once at PLAYER_LOGIN, after all XML/modules.
function ADKP_ForeverInitializeOriginal()
    ADKP_LegacyCall(ADKP_Frame, "OnLoad", originalLoad)
    ADKP_ADDON_LOADED()
end
local originalTable = ADKP_UpdateTable
function ADKP_UpdateTable(...)
    if not ADKP_FrameScrollFrame then return end
    return originalTable(...)
end
function ADKP_RefreshSavedState()
    if ADKP_RefreshBossAutoAwardLog then ADKP_RefreshBossAutoAwardLog() end
end

function ADKP_MinimapButton_SetPositionAngle(angle)
    angle = tonumber(angle) or 2.35
    local radius = Minimap:GetWidth() / 2 + 5
    ADKP_MinimapButton:ClearAllPoints()
    ADKP_MinimapButton:SetPoint("CENTER", Minimap, "CENTER", math.sin(angle) * radius, math.cos(angle) * radius)
end

function ADKP_DisplayName(name)
    local value = string.gsub(name or "", "\\", "\\\\")
    value = string.gsub(value, "·", "\\·")
    return (string.gsub(value, " ", "·"))
end
function ADKP_SetNameText(region, name)
    region.ADKP_RawName = name; region:SetText(ADKP_DisplayName(name))
    local parent = region:GetParent()
    if not parent then return end
    local frameName = parent:GetName() or ""
    if string.find(frameName, "^ADKP_FrameLine") then region:SetWidth(116); region:SetWordWrap(false)
    elseif string.find(frameName, "^ADKP_BidFrameLine") then region:SetWidth(136); region:SetWordWrap(false) end
    parent.ADKP_NameLabels = parent.ADKP_NameLabels or {}
    parent.ADKP_NameLabels[region] = name
    if parent.ADKP_NameTipInstalled then return end
    parent.ADKP_NameTipInstalled = true; parent:EnableMouse(true)
    parent:HookScript("OnEnter", function(self)
        local lines = {}
        for _, raw in pairs(self.ADKP_NameLabels) do
            table.insert(lines, ADKP_DisplayName(raw) .. "\n原始全名：【" .. raw .. "】")
        end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText(table.concat(lines, "\n"), 1, 1, 1, 1, true); GameTooltip:Show()
    end)
    parent:HookScript("OnLeave", function() GameTooltip:Hide() end)
end
function ADKP_RowName(frame)
    local region = _G[frame:GetName() .. "Name"]
    return region and (region.ADKP_RawName or region:GetText())
end

function ADKP_ForeverInstallAuctionHandlers()
    -- Bind these controls after XML construction, using modern callback args.
    -- Keep the original auction operations and frame layout.
    local function bind(button, callback, rightClick)
        button:EnableMouse(true); button:Enable()
        if rightClick then button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        else button:RegisterForClicks("LeftButtonUp") end
        ADKP_SetNativeScript(button, "OnClick", callback)
    end
    bind(ADKP_BidFrameBidButton, function()
        ADKP_Bid_ButtonHandler()
        ADKP_BidFrameItem:ClearFocus(); ADKP_BidFrameTime:ClearFocus()
    end)
    bind(ADKP_BidFramePass, function(_, button) ADKP_Bid_PassButtonClick(button) end, true)
    bind(ADKP_BidFrameAward, function() ADKP_Bid_AwardSelected() end)
end

function ADKP_ForeverArguments(text)
    local result, at = {}, 1
    while at <= string.len(text or "") do
        local _, finish = string.find(text, "^%s*", at); at = (finish or at - 1) + 1
        if at > string.len(text) then break end
        local quote = string.sub(text, at, at)
        local value
        if quote == '"' or quote == "'" then
            local stop = string.find(text, quote, at + 1, true)
            if not stop then return nil, '双名请使用配对引号，例如 "张三 四"。' end
            value, at = string.sub(text, at + 1, stop - 1), stop + 1
        else
            local stop = string.find(text, "%s", at)
            value, at = string.sub(text, at, (stop or string.len(text) + 1) - 1), stop or string.len(text) + 1
        end
        table.insert(result, value)
    end
    return result
end

local whisperFilterInstalled, itemHookInstalled, menuInstalled
function ADKP_Register_WhisperHook()
    if whisperFilterInstalled or not ChatFrame_AddMessageEventFilter then return end
    whisperFilterInstalled = true
    local function filter(_, _, message, sender)
        if not ADKP_IsPublic(message) or not ADKP_IsPublic(sender) then return false end
        return ADKP_IsADKPWhisper and ADKP_IsADKPWhisper(sender, message) and true or false
    end
    ChatFrame_AddMessageEventFilter("CHAT_MSG_WHISPER", filter)
    ChatFrame_AddMessageEventFilter("CHAT_MSG_WHISPER_INFORM", function(_, _, message)
        return ADKP_IsPublic(message) and type(message) == "string" and string.find(message, "^ADKP: ") ~= nil
    end)
end
function ADKP_ForeverInstallUIHooks()
    ADKP_Register_WhisperHook()
    if not itemHookInstalled and hooksecurefunc then
        itemHookInstalled = true
        hooksecurefunc("SetItemRef", function(link, text, mouse)
            if not ADKP_IsPublic(link) or not ADKP_IsPublic(text) or type(link) ~= "string" then return end
            if string.sub(link, 1, 5) ~= "item:" then return end
            if ADKP_Bid_ItemChatClick then ADKP_Bid_ItemChatClick(link, text, mouse) end
            if IsShiftKeyDown() and ADKP_AwardItem_FrameItemName then
                local _, name = ADKP_GetItemInfo(link); ADKP_AwardItem_FrameItemName:SetText(name)
            end
        end)
    end
    if not menuInstalled and Menu and Menu.ModifyMenu then
        menuInstalled = true
        for _, tag in ipairs({"MENU_UNIT_PLAYER", "MENU_UNIT_PARTY", "MENU_UNIT_RAID_PLAYER", "MENU_UNIT_FRIEND"}) do
            Menu.ModifyMenu(tag, function(_, root, context)
                local name = context and context.unit and ADKP_ForeverName(context.unit) or (context and context.name)
                if not ADKP_IsPublic(name) or type(name) ~= "string" or name == "" then return end
                root:CreateDivider()
                root:CreateButton("ADKP 加分", function() ADKP_HandleAward(name) end)
                root:CreateButton("ADKP 扣分", function() ADKP_HandleDeduction(name) end)
            end)
        end
    end
end

local originalEvent = ADKP_OnEvent
function ADKP_OnEvent()
    if event == "ADDON_LOADED" and arg1 ~= ADKP_FOREVER_ADDON then return end
    if event == "CHAT_MSG_ADDON" then
        if ADKP_ForeverHandleAddon then ADKP_ForeverHandleAddon(arg1, arg2, arg3, arg4) end
        return
    end
    return originalEvent()
end

function ADKP_ForeverRoster()
    local count, raid, rows, seen = GetNumGroupMembers(), IsInRaid(), {}, {}
    if not ADKP_IsPublic(count) then return nil, "队伍名单暂不可读取。" end
    local first, last = raid and 1 or 0, raid and count or math.max(0, count - 1)
    for i = first, last do
        local unit = raid and ("raid" .. i) or (i == 0 and "player" or "party" .. i)
        local name, class = ADKP_ForeverName(unit), ADKP_UnitClass(unit)
        if not name or not class then return nil, "队伍完整姓名或职业暂不可读取，请稍后重试。" end
        local key = string.lower(name)
        if seen[key] then return nil, "队伍名单存在重复身份。" end
        seen[key] = true; table.insert(rows, {name = name, class = class})
    end
    if count ~= GetNumGroupMembers() or raid ~= IsInRaid() then return nil, "队伍发生变化，请重试。" end
    return rows
end

local originalRunAward = ADKP_RunRaidAndSubAward
function ADKP_RunRaidAndSubAward(...)
    local rows, err = ADKP_ForeverRoster()
    if not rows then
        ADKP_Print(err)
        local callback = select(5, ...)
        if callback then callback(false) end
        return false
    end
    return originalRunAward(...)
end

-- The original auto-loot controller still records failures and waits for loot
-- evidence. Only its slot selection and native call change for Forever.
function ADKP_ForeverResolveLootLink(item)
    if not ADKP_IsPublic(item) or type(item) ~= "string" then return nil, "缺少可读取的物品名称或链接。" end
    if string.match(item, "|Hitem:[^|]+|h") then return item end
    local name = ADKP_ForeverTrim(item)
    name = string.match(name, "^%[(.-)%]$") or name
    local count = GetNumLootItems and GetNumLootItems() or 0
    local found, identity
    if ADKP_IsPublic(count) and type(count) == "number" then
        for slot = 1, count do
            local link = GetLootSlotLink(slot)
            if ADKP_IsPublic(link) and type(link) == "string" and string.match(link, "|h%[(.-)%]|h") == name then
                local key = string.match(link, "|H(item:[^|]+)|h")
                if key then
                    if identity and identity ~= key then return nil, "掉落中有同名但不同的物品，请使用完整物品链接。" end
                    found, identity = link, key
                end
            end
        end
    end
    if found then return found end
    local _, _, cached = ADKP_GetItemInfo(item)
    if ADKP_IsPublic(cached) and type(cached) == "string" and string.match(cached, "|Hitem:[^|]+|h") then return cached end
    return nil, "缺少完整物品链接，请打开对应掉落窗口后重试分配。"
end

function ADKP_ForeverLootThreshold()
    if type(GetLootThreshold) ~= "function" then return nil end
    local ok, quality = pcall(GetLootThreshold)
    if ok and ADKP_IsPublic(quality) and type(quality) == "number" then return quality end
end

local function qualityName(quality)
    return ({[0] = "灰色", [1] = "白色", [2] = "绿色", [3] = "蓝色", [4] = "紫色", [5] = "橙色"})[quality] or tostring(quality)
end

local function failLoot(message, reason)
    local state = ADKP_AutoLootData
    ADKP_AddUnassignedLoot(state.currentItemLink, state.currentPlayer, reason or "需要手动交付", message, state.recordRef, state.pendingId)
    ADKP_StopAutoLoot(false)
end
function ADKP_TryAssignLoot()
    local state = ADKP_AutoLootData
    if not state.isAssigning or state.awaitingResult then return end
    if not GiveMasterLoot or not GetMasterLootCandidate or (InCombatLockdown and InCombatLockdown()) then
        failLoot("客户端接口或当前状态不允许队长分配，请使用原生拾取窗口或交易。"); return
    end
    local count = GetNumLootItems()
    if not ADKP_IsPublic(count) or count == 0 then return end
    local wanted = state.currentItemLink and string.match(state.currentItemLink, "|H(item:[^|]+)|h")
    if not wanted then failLoot("缺少完整装备链接，请手动选择物品。"); return end
    local slot
    for i = 1, count do
        local link = GetLootSlotLink(i)
        if ADKP_IsPublic(link) and link and string.match(link, "|H(item:[^|]+)|h") == wanted then
            if slot then failLoot("掉落中有多件相同装备，请在原生窗口明确选择。"); return end
            slot = i
        end
    end
    if not slot then failLoot("掉落窗口没有对应装备。"); return end
    local threshold = ADKP_ForeverLootThreshold()
    local quality = GetLootSlotInfo and select(5, GetLootSlotInfo(slot))
    if threshold and ADKP_IsPublic(quality) and type(quality) == "number" and quality < threshold then
        failLoot(qualityName(quality) .. "物品低于当前" .. qualityName(threshold) .. "分配阈值，需拾取后交易。", "低于分配阈值"); return
    end
    local candidate
    for i = 1, MAX_RAID_MEMBERS or 40 do
        local name = GetMasterLootCandidate(slot, i)
        if ADKP_IsPublic(name) and name == state.currentPlayer then candidate = i; break end
    end
    if not candidate then failLoot("玩家不在该物品的可分配名单中。"); return end
    state.awaitingResult, state.resultDeadline = true, GetTime() + 5
    local ok, err = pcall(GiveMasterLoot, slot, candidate)
    if not ok or err == false then failLoot(ok and "物品分配接口返回失败，请手动核对。" or tostring(err)); return end
    if not ADKP_AutoLootMonitor then ADKP_AutoLootMonitor = ADKP_CreateFrame("Frame") end
    ADKP_AutoLootMonitor:SetScript("OnUpdate", function()
        if state.isAssigning and state.awaitingResult and GetTime() >= state.resultDeadline then
            failLoot("未收到交付回执，请手动核对。")
        end
    end)
end

-- Keep the original table and popup while showing official encounter evidence.
function ADKP_ForeverOfficialBoss(id, name, success)
    if not ADKP_IsPublic(id) or not ADKP_IsPublic(name) or not ADKP_IsPublic(success) then return end
    if success ~= 1 or type(id) ~= "number" or type(name) ~= "string" then return end
    if GetNumGroupMembers() == 0 or not (ADKP_IsLeader() or ADKP_IsAssistant()) then return end
    if not ADKP_BossEncounter_IsEnabled() then return end
    WebDKP_Options.ForeverBossSeen = WebDKP_Options.ForeverBossSeen or {}
    local instance = GetInstanceInfo and select(8, GetInstanceInfo()) or 0
    if not ADKP_IsPublic(instance) then return end
    local key = ADKP_GetTableid() .. ":" .. tostring(instance) .. ":" .. id
    if WebDKP_Options.ForeverBossSeen[key] then return end
    local boss = ADKP_GetBossDefinition(name)
    local enabled = WebDKP_Options.EnabledRaidBosses or {}
    if enabled[string.lower(name)] == false or (boss and enabled[string.lower(boss.en)] == false) then return end
    for _, excluded in ipairs(WebDKP_Options.ExcludedBosses or {}) do if excluded == name then return end end
    local rows, err = ADKP_ForeverRoster()
    if not rows then ADKP_Print(err); return end
    WebDKP_Options.ForeverBossSeen[key] = true
    local raid, sub = ADKP_GetBossAwardPoints(name)
    table.insert(ADKP_BossEncounterState.queue, {bossName = name, bossId = "official:" .. id,
        raid = raid, sub = sub, tableid = ADKP_GetTableid(), auto = WebDKP_Options.BossAutoAward and true or false})
    ADKP_BossEncounter_Pump()
end

function ADKP_ForeverDiagnostics()
    local version, build, _, interface = GetBuildInfo()
    ADKP_Print("原版克隆移植 " .. ADKP_VERSION .. "；客户端 " .. version .. "." .. build .. "；Interface " .. interface)
    ADKP_Print("完整名：【" .. (ADKP_ForeverName("player") or "不可读取") .. "】；GUID：" .. tostring(UnitGUID("player")))
    local target = ADKP_ForeverName("target")
    if target then ADKP_Print("目标：【" .. target .. "】；分隔显示：" .. ADKP_DisplayName(target)) end
    ADKP_Print("插件 WHISPER：" .. (ADKP_ForeverCommsVerified and "本次会话已收到匹配的完整名单" or "尚未完成本次会话双端验证"))
    ADKP_Print("竞拍状态：" .. (ADKP_Bid_IsInProgress() and "进行中" or "已停止"))
    local threshold = ADKP_ForeverLootThreshold()
    ADKP_Print("队长分配权限：" .. (ADKP_IsMasterLooter() and "有" or "无") .. "；分配品质阈值：" .. (threshold and qualityName(threshold) or "不可读取"))
    local pending = ADKP_UnassignedLoot and ADKP_UnassignedLoot[table.getn(ADKP_UnassignedLoot)]
    if pending then ADKP_Print("最近未交付：" .. (pending.rawError or pending.reason or "未知原因")) end
    if ADKP_ForeverLastCallbackError then ADKP_Print("最近回调错误：" .. ADKP_ForeverLastCallbackError) end
    if ADKP_ForeverLastItemError then ADKP_Print("最近物品查询错误：" .. ADKP_ForeverLastItemError) end
end
