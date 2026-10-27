-- Private adapters for the cloned 1.12 source. Never replace Blizzard globals.
local addonName = ...
ADKP_FOREVER_ADDON = type(addonName) == "string" and addonName or "ADKP"
local nativeCreateFrame, nativeUnitClass = CreateFrame, UnitClass
local nativeRaidInfo, nativeGuildInfo = GetRaidRosterInfo, GetGuildRosterInfo
local nativeMenuAdd, nativeMenuInit = UIDropDownMenu_AddButton, UIDropDownMenu_Initialize
local nativeMenuWidth, nativeMenuText = UIDropDownMenu_SetWidth, UIDropDownMenu_SetText
local nativePopup, nativeScroll = StaticPopup_Show, FauxScrollFrame_OnVerticalScroll
local unpackValues = unpack or table.unpack
local function pack(...) return {n = select("#", ...), ...} end

ADKP_LegacyString = setmetatable({gfind = string.gmatch}, {__index = string})
ADKP_LegacyTable = setmetatable({getn = function(t)
    local n = 0; for _ in ipairs(t or {}) do n = n + 1 end; return n
end}, {__index = table})
function ADKP_GetGlobal(name) return _G[name] end
function ADKP_SetGlobal(name, value) _G[name] = value end
function ADKP_IsPublic(value) return not issecretvalue or not issecretvalue(value) end
function ADKP_ForeverTrim(value)
    if not ADKP_IsPublic(value) or type(value) ~= "string" then return nil end
    return (string.gsub(value, "^%s*(.-)%s*$", "%1"))
end
function ADKP_ForeverName(unit)
    local ok, name
    if NameUtil and NameUtil.GetUnmodifiedUnitFullName then ok, name = pcall(NameUtil.GetUnmodifiedUnitFullName, unit)
    elseif GetUnitName then ok, name = pcall(GetUnitName, unit, true) end
    if not ok or not ADKP_IsPublic(name) or type(name) ~= "string" or name == "" then return nil end
    return name
end
ADKP_UnitName = ADKP_ForeverName
function ADKP_ForeverChatAuthor(name, guid)
    if not ADKP_IsPublic(name) or type(name) ~= "string" then return nil end
    if ADKP_IsPublic(guid) and type(guid) == "string" and guid ~= "" then
        local function matches(unit)
            local unitGUID = UnitGUID(unit)
            if ADKP_IsPublic(unitGUID) and unitGUID == guid then return ADKP_ForeverName(unit) end
        end
        local fullName = matches("player")
        if fullName then return fullName end
        local count, raid = GetNumGroupMembers(), IsInRaid()
        if ADKP_IsPublic(count) then
            for i = 1, (count or 0) do
                fullName = matches((raid and "raid" or "party") .. i)
                if fullName then return fullName end
            end
        end
    end
    -- Keep all surname boundaries when the sender cannot be resolved by GUID.
    return ADKP_ForeverTrim(name)
end
function ADKP_UnitClass(unit)
    local class, token = nativeUnitClass(unit)
    if ADKP_IsPublic(class) and ADKP_IsPublic(token) then return class, token end
end
function ADKP_GetNumRaidMembers()
    if not IsInRaid() then return 0 end
    local n = GetNumGroupMembers(); if ADKP_IsPublic(n) then return n or 0 end; return 0
end
function ADKP_GetNumPartyMembers()
    if IsInRaid() then return 0 end
    local n = GetNumGroupMembers(); if ADKP_IsPublic(n) then return math.max(0, (n or 0) - 1) end; return 0
end
function ADKP_GetRaidRosterInfo(index)
    if not nativeRaidInfo then return nil end
    local values = pack(nativeRaidInfo(index))
    for i = 1, values.n do if not ADKP_IsPublic(values[i]) then return nil end end
    values[1] = ADKP_ForeverName("raid" .. index)
    return unpackValues(values, 1, values.n)
end
function ADKP_GetGuildRosterInfo(index)
    if not nativeGuildInfo then return nil end
    local values = pack(nativeGuildInfo(index))
    for i = 1, values.n do if not ADKP_IsPublic(values[i]) then return nil end end
    return unpackValues(values, 1, values.n)
end
function ADKP_UnitIsLeader(unit)
    local value = UnitIsGroupLeader(unit); return ADKP_IsPublic(value) and value or false
end
function ADKP_IsLeader() return ADKP_UnitIsLeader("player") end
function ADKP_IsAssistant()
    local value = UnitIsGroupAssistant("player"); return ADKP_IsPublic(value) and value or false
end
function ADKP_GetLootMethod()
    local query = C_PartyInfo and C_PartyInfo.GetLootMethod or _G.GetLootMethod
    if type(query) ~= "function" then return nil, nil, nil, "客户端没有提供拾取方式查询接口。" end
    local ok, method, partyID, raidID = pcall(query)
    if not ok then return nil, nil, nil, "无法查询当前拾取方式。" end
    if not ADKP_IsPublic(method) or not ADKP_IsPublic(partyID) or not ADKP_IsPublic(raidID) then
        return nil, nil, nil, "当前拾取权限暂不可读取。"
    end
    if type(method) == "number" then
        -- C_PartyInfo returns Enum.LootMethod; preserve the old business values.
        local methods = {[0]="freeforall",[1]="roundrobin",[2]="master",[3]="group",[4]="needbeforegreed",[5]="personalloot"}
        method = methods[method]
    end
    return method, partyID, raidID
end
function ADKP_IsMasterLooter()
    local method, partyID, raidID, err = ADKP_GetLootMethod()
    if err then return false, err end
    if method ~= "master" then return false, "当前不是队长分配模式，请手动交付。" end
    if partyID == 0 or raidID == 0 then return true end
    local unit
    if IsInRaid() and type(raidID) == "number" and raidID > 0 then unit = "raid" .. raidID
    elseif type(partyID) == "number" and partyID > 0 then unit = "party" .. partyID end
    if unit then
        local looterGUID, playerGUID = UnitGUID(unit), UnitGUID("player")
        if ADKP_IsPublic(looterGUID) and ADKP_IsPublic(playerGUID) and looterGUID and playerGUID then
            if looterGUID == playerGUID then return true end
        else
            local looter, player = ADKP_ForeverName(unit), ADKP_ForeverName("player")
            if looter and player and looter == player then return true end
        end
    end
    return false, "你不是当前物品分配者，请手动交付。"
end
function ADKP_UnitAffectingCombat(unit)
    local value = UnitAffectingCombat(unit)
    if not ADKP_IsPublic(value) then return true end
    return value
end
function ADKP_GuildRoster() if C_GuildInfo and C_GuildInfo.GuildRoster then return C_GuildInfo.GuildRoster() end end
function ADKP_NativeGetItemInfo(item)
    if not ADKP_IsPublic(item) then return nil end
    local query = C_Item and C_Item.GetItemInfo or GetItemInfo
    if not query then return nil end
    local result = pack(pcall(query, item))
    if not result[1] then
        ADKP_ForeverLastItemError = tostring(result[2]); return nil
    end
    for i = 2, result.n do if not ADKP_IsPublic(result[i]) then return nil end end
    return unpackValues(result, 2, result.n)
end
function ADKP_PlaySound(sound)
    if type(sound) == "number" then return PlaySound(sound) end
    local names = {igQuestFailed = "IG_QUEST_FAILED", igMainMenuOpen = "IG_MAINMENU_OPEN",
        igMainMenuClose = "IG_MAINMENU_CLOSE", igCharacterInfoTab = "IG_CHARACTER_INFO_TAB",
        igMainMenuOptionCheckBoxOn = "IG_MAINMENU_OPTION_CHECKBOX_ON", igMainMenuOptionCheckBoxOff = "IG_MAINMENU_OPTION_CHECKBOX_OFF"}
    local id = SOUNDKIT and SOUNDKIT[names[sound] or ""]
    if id then return PlaySound(id) end
end
local function partyAction(method, ...)
    if InCombatLockdown and InCombatLockdown() then return false end
    if C_PartyInfo and C_PartyInfo[method] then return C_PartyInfo[method](...) end
    if ADKP_Print then ADKP_Print("当前客户端未提供此队伍操作：" .. method) end
    return false
end
function ADKP_Invite(name) return partyAction("InviteUnit", name) end
function ADKP_Uninvite(name) return partyAction("UninviteUnit", name) end
function ADKP_ConvertToRaid() return partyAction("ConvertToRaid") end
function ADKP_Promote(name) return partyAction("PromoteToLeader", name) end
function ADKP_PromoteAssistant(name) return partyAction("PromoteToAssistant", name) end
function ADKP_Demote(name) return partyAction("DemoteAssistant", name) end

-- A stack-scoped bridge preserves old handlers without leaving this/arg/event
-- globals behind, including nested callbacks and exceptions.
function ADKP_LegacyCall(self, script, callback, ...)
    local args, previous = pack(...), {this = _G.this, event = _G.event}
    local chat = script == "OnEvent" and ADKP_IsPublic(args[1]) and
        (args[1] == "CHAT_MSG_RAID" or args[1] == "CHAT_MSG_RAID_LEADER" or args[1] == "CHAT_MSG_RAID_WARNING" or
        args[1] == "CHAT_MSG_PARTY" or args[1] == "CHAT_MSG_PARTY_LEADER" or args[1] == "CHAT_MSG_WHISPER" or args[1] == "CHAT_MSG_GUILD")
    if chat and (not ADKP_IsPublic(args[2]) or not ADKP_IsPublic(args[3])) then return end
    for i = 1, args.n do
        if not ADKP_IsPublic(args[i]) then
            if not chat then return end
            -- These old chat consumers need readable text and author only.
            -- Never expose restricted ancillary fields to a legacy callback.
            args[i] = nil
        end
    end
    for i = 1, 20 do previous[i] = _G["arg" .. i] end
    _G.this = self
    local offset = 0
    if script == "OnEvent" then
        _G.event = args[1]; offset = 1
        if _G.event == "GROUP_ROSTER_UPDATE" then _G.event = "RAID_ROSTER_UPDATE" end
        if _G.event == "UI_ERROR_MESSAGE" then args[2] = args[3]; args[3] = nil end
    end
    for i = 1, 20 do _G["arg" .. i] = args[i + offset] end
    local result = pack(pcall(callback, self, unpackValues(args, 1, args.n)))
    _G.this, _G.event = previous.this, previous.event
    for i = 1, 20 do _G["arg" .. i] = previous[i] end
    if not result[1] then
        ADKP_ForeverLastCallbackError = (self and self:GetName() or "匿名框架") .. "/" .. script .. ": " .. tostring(result[2])
        error(result[2], 0)
    end
    return unpackValues(result, 2, result.n)
end

function ADKP_ApplyBackdrop(frame, descriptor)
    if not frame.SetBackdrop and BackdropTemplateMixin then
        Mixin(frame, BackdropTemplateMixin)
        frame:HookScript("OnSizeChanged", function(self) self:OnBackdropSizeChanged() end)
    end
    frame:SetBackdrop(descriptor)
end
ADKP_ForeverEditBoxMixin = {}
function ADKP_ForeverEditBoxMixin:ADKP_InitializeEditBox()
    ADKP_ApplyBackdrop(self, {bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 12, edgeSize = 12,
        insets = {left = 3, right = 3, top = 3, bottom = 3}})
    self:SetAutoFocus(false)
    self:SetBackdropColor(0, 0, 0, 0.6)
    self:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
    self:SetTextInsets(6, 6, 0, 0)
end
function ADKP_PrepareFrame(frame)
    if frame.ADKP_ModernPrepared then return frame end
    frame.ADKP_ModernPrepared = true
    -- XML instances can replace the template's OnLoad; the inherited mixin
    -- still supplies this initializer before their color setters execute.
    if frame.ADKP_InitializeEditBox then frame:ADKP_InitializeEditBox() end
    if frame:GetObjectType() == "ScrollFrame" then frame:EnableMouseWheel(true) end
    local setScript, hookScript = frame.SetScript, frame.HookScript
    frame.ADKP_NativeSetScript = setScript
    frame.SetScript = function(self, script, callback)
        if not callback then return setScript(self, script, nil) end
        return setScript(self, script, function(owner, ...) return ADKP_LegacyCall(owner, script, callback, ...) end)
    end
    frame.HookScript = function(self, script, callback)
        return hookScript(self, script, function(owner, ...) return ADKP_LegacyCall(owner, script, callback, ...) end)
    end
    return frame
end
function ADKP_SetNativeScript(frame, script, callback)
    local setter = frame.ADKP_NativeSetScript or frame.SetScript
    return setter(frame, script, function(owner, ...)
        local result = pack(pcall(callback, owner, ...))
        if not result[1] then
            ADKP_ForeverLastCallbackError = (owner:GetName() or "匿名框架") .. "/" .. script .. ": " .. tostring(result[2])
            error(result[2], 0)
        end
        return unpackValues(result, 2, result.n)
    end)
end
function ADKP_CreateFrame(kind, name, parent, templates)
    local inputBox = templates == "InputBoxTemplate" or templates == "ADKP_ForeverInputBoxTemplate"
    local legacy = {CharacterFrameTabButtonTemplate=true,OptionsButtonTemplate=true,OptionsCheckButtonTemplate=true,
        UICheckButtonTemplate=true,FauxScrollFrameTemplate=true,GameMenuButtonTemplate=true,InputBoxTemplate=true,UIPanelScrollFrameTemplate=true}
    if templates and legacy[templates] then templates = "ADKP_Forever" .. templates end
    templates = templates and (templates .. ",BackdropTemplate") or "BackdropTemplate"
    local frame = ADKP_PrepareFrame(nativeCreateFrame(kind, name, parent, templates))
    -- The trailing BackdropTemplate can replace the input template's OnLoad.
    -- Apply its visible border and fill after all native load handlers finish.
    if inputBox then ADKP_ForeverEditBoxMixin.ADKP_InitializeEditBox(frame) end
    return frame
end
function ADKP_SetTexture(texture, r, g, b, a) texture:SetColorTexture(r, g, b, a or 1) end
function ADKP_DropdownInitialize(frame, callback, mode)
    return nativeMenuInit(frame, function(owner, ...)
        return ADKP_LegacyCall(owner, "MenuInit", callback, ...)
    end, mode)
end
function ADKP_DropdownAddButton(info, level)
    if info.func then
        local action = info.func
        info.func = function(owner, ...) return ADKP_LegacyCall(owner, "OnClick", action, ...) end
    end
    return nativeMenuAdd(info, level)
end
function ADKP_DropdownSetWidth(width, frame) return nativeMenuWidth(frame or _G.this, width) end
function ADKP_DropdownSetText(value, frame) return nativeMenuText(frame or _G.this, value) end
function ADKP_FauxVerticalScroll(height, update)
    local frame = _G.this
    frame.ADKP_RowHeight = height
    frame.offset = math.floor((_G.arg1 or 0) / height + 0.5)
    return update()
end
function ADKP_FauxGetOffset(frame) return frame and frame.offset or 0 end
function ADKP_FauxUpdate(frame, count, visible, height)
    if not frame then return end
    frame.ADKP_Faux = true
    local name = frame:GetName() or ""
    if name == "ADKP_FrameScrollFrame" or name == "ADKP_BidFrameScrollFrame" then height = 20 end
    height = frame.ADKP_RowHeight or height or 20
    frame.ADKP_RowHeight = height
    local bar = _G[name .. "ScrollBar"]
    if not bar then return end
    local maximum = math.max(0, count - visible) * height
    bar:SetMinMaxValues(0, maximum); bar:SetValueStep(height)
    local value = math.min(maximum, (frame.offset or 0) * height)
    frame.offset = math.floor(value / height + 0.5)
    if math.abs((bar:GetValue() or 0) - value) > 0.1 then bar:SetValue(value) end
    bar:SetShown(maximum > 0)
end
function ADKP_ScrollValueChanged(bar, value)
    local scroll = bar:GetParent()
    if scroll.ADKP_Faux then
        local callback = scroll:GetScript("OnVerticalScroll")
        if callback then callback(scroll, value) end
    else scroll:SetVerticalScroll(value) end
end
function ADKP_ScrollRangeChanged(scroll, _, maximum)
    if scroll.ADKP_Faux then return end
    local bar = _G[scroll:GetName() .. "ScrollBar"]
    if bar then bar:SetMinMaxValues(0, maximum or 0); bar:SetShown((maximum or 0) > 0) end
end
function ADKP_ScrollWheel(scroll, delta)
    local bar = _G[scroll:GetName() .. "ScrollBar"]
    if not bar then return end
    local low, high = bar:GetMinMaxValues()
    bar:SetValue(math.max(low, math.min(high, (bar:GetValue() or 0) - delta * (scroll.ADKP_RowHeight or 24))))
end
function ADKP_PanelSetTab(frame, id)
    frame.selectedTab = id
    for i = 1, 12 do
        local tab = _G[frame:GetName() .. "Tab" .. i]
        if tab then
            if i == id then tab:LockHighlight(); tab:SetNormalFontObject(GameFontHighlight)
            else tab:UnlockHighlight(); tab:SetNormalFontObject(GameFontNormal) end
        end
    end
end
function ADKP_StaticPopup_Show(which, ...)
    local info = StaticPopupDialogs[which]
    if info and not info.ADKP_ModernPrepared then
        info.ADKP_ModernPrepared = true
        for _, script in ipairs({"OnAccept", "OnCancel", "OnShow", "OnHide", "EditBoxOnEnterPressed", "EditBoxOnEscapePressed"}) do
            local action, kind = info[script], script
            if action then info[kind] = function(owner, ...) return ADKP_LegacyCall(owner, kind, action, ...) end end
        end
    end
    return nativePopup(which, ...)
end
function ADKP_PopupEditBox(owner)
    if owner.editBox then return owner.editBox end
    local name = owner:GetName()
    if name and _G[name .. "EditBox"] then return _G[name .. "EditBox"] end
    local parent = owner:GetParent()
    return parent and (parent.editBox or _G[(parent:GetName() or "") .. "EditBox"])
end

ADKP_ForeverChatQueue = {}
function ADKP_NativeSendChatMessage(message, channel, language, target)
    if not ADKP_IsPublic(message) or type(message) ~= "string" or string.len(message) > 255 then return false end
    if target and (not ADKP_IsPublic(target) or type(target) ~= "string") then return false end
    table.insert(ADKP_ForeverChatQueue, {message, channel, language, target}); return true
end
function ADKP_SendAddonMessage(prefix, text, channel, target)
    if ADKP_ForeverSendAddon then return ADKP_ForeverSendAddon(prefix, text, channel, target) end
    return false
end
function ADKP_MasterLootCandidate(slot, index)
    if not index then return nil end -- a slot must be specified by the ported caller
    if GetMasterLootCandidate then return GetMasterLootCandidate(slot, index) end
end
function ADKP_GiveMasterLoot(slot, candidate)
    if InCombatLockdown and InCombatLockdown() then return false end
    if GiveMasterLoot then return GiveMasterLoot(slot, candidate) end
    if ADKP_Print then ADKP_Print("客户端无队长分配接口，请使用原生拾取窗口或交易。") end
    return false
end
