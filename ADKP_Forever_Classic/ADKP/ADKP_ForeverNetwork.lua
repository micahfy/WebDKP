-- Original roster encoding/cache/award consumers over native addon WHISPER.
local table = ADKP_LegacyTable
local pending, replies, queue, serial, nextSend = {}, {}, {}, 0, 0
local originalParser, originalWhisper = ADKP_HandleSubWhisperData, ADKP_SendWhisper
local parsing = false
local function key(name) return string.lower(name or "") end
local function emit(prefix, payload, target)
    if string.len(payload) > 255 then error("替补同步数据包过长，已取消发送。") end
    table.insert(queue, {prefix = prefix, payload = payload, target = target})
end
local function parse(sender, message)
    parsing = true
    local ok, err = pcall(originalParser, sender, message)
    parsing = false
    if not ok then error(err, 0) end
end
function ADKP_HandleSubWhisperData(sender, message)
    -- Ordinary player whispers must not inject substitute roster data.
    if parsing then return originalParser(sender, message) end
end
function ADKP_SendWhisper(target, message)
    if type(message) == "string" and string.sub(message, 1, 3) == "SUB" then
        local response = replies[key(target)]
        if not response or GetTime() > response.deadline then return false end
        emit("AMB_TBFS", response.id .. "|" .. message, target); return true
    end
    return originalWhisper(target, message)
end
function ADKP_ForeverSendAddon(prefix, text, _, target)
    if prefix ~= "AMB_TBQQ" then return false end
    local captain = ADKP_ForeverTrim(target or text)
    if not captain or captain == "" then return false end
    if not ADKP_SubSync_ForceQuery and ADKP_SubSync_HasFreshCache(captain) then
        ADKP_SubSync_ReplayCache(captain); return true
    end
    if not ADKP_ForeverCommReady then error("插件通信前缀未注册成功，请 /adkp diag 核对。") end
    serial = serial + 1
    local id = tostring(time()) .. ":" .. serial
    pending[key(captain)] = {id = id, team = ADKP_GetTableid(), deadline = GetTime() + 20}
    ADKP_ResetSubSyncState()
    ADKP_PendingSubMembers = ADKP_PendingSubMembers or {}
    local fresh = {}; ADKP_PendingSubMembers[captain], ADKP_PendingSubMembers[key(captain)] = fresh, fresh
    emit("AMB_TBQQ", id, captain)
    return true
end
function ADKP_SubSync_ReplayCache(captain)
    local cache = ADKP_SubSync_Cache and ADKP_SubSync_Cache[key(captain)]
    if not cache then return end
    ADKP_ResetSubSyncState()
    ADKP_PendingSubMembers = ADKP_PendingSubMembers or {}
    local fresh = {}; ADKP_PendingSubMembers[captain], ADKP_PendingSubMembers[key(captain)] = fresh, fresh
    local count = 0
    for name, class in pairs(cache.members) do
        ADKP_ReceiveSubMember(captain, name .. ":" .. class .. ":" .. captain); count = count + 1
    end
    ADKP_ReceiveSubMember(captain, "COMPLETE:" .. ADKP_ForeverName("player") .. ":" .. count)
    ADKP_SubSync_UpdateLabel(captain, count, time() - cache.time)
end
function ADKP_ForeverHandleAddon(prefix, message, channel, sender)
    if channel ~= "WHISPER" or not ADKP_IsPublic(message) or not ADKP_IsPublic(sender) then return end
    if type(message) ~= "string" or type(sender) ~= "string" then return end
    if ADKP_IsAddonDisabled and ADKP_IsAddonDisabled() then return end
    if prefix == "AMB_TBQQ" then
        if not string.match(message, "^%d+:%d+$") then return end
        local previous = replies[key(sender)]
        if previous and previous.id == message and previous.deadline >= GetTime() then return end
        replies[key(sender)] = {id = message, deadline = GetTime() + 20}
        ADKP_SendSubMemberList(sender)
    elseif prefix == "AMB_TBFS" then
        local request = pending[key(sender)]
        local id, payload = string.match(message, "^([^|]+)|(.+)$")
        if not request or request.id ~= id or request.team ~= ADKP_GetTableid() or request.deadline < GetTime() then return end
        if key(ADKP_ResolveSubCaptain()) ~= key(sender) then return end
        parse(sender, "ADKP: " .. payload)
        if ADKP_SubAwardData and ADKP_SubAwardData.subSyncComplete then
            ADKP_SubSync_SnapshotCache(sender); ADKP_ForeverCommsVerified = true
            pending[key(sender)] = nil
            if ADKP_ListMode == "sub" then ADKP_UpdateTableToShow(); ADKP_UpdateTable() end
        end
    end
end
function ADKP_SubSync_RefreshRoster()
    local captain = ADKP_ResolveSubCaptain()
    if not captain or captain == "" then ADKP_Print("请先在设置中填写替补队长完整名。"); return end
    ADKP_SubAwardData.captain = captain; ADKP_ResetSubSyncState()
    ADKP_SubSync_Cache = ADKP_SubSync_Cache or {}
    ADKP_SubSync_ForceQuery = true
    local ok, err = pcall(ADKP_ForeverSendAddon, "AMB_TBQQ", captain)
    ADKP_SubSync_ForceQuery = false
    if ok then ADKP_Print("已通过插件 WHISPER 请求 " .. captain .. " 的完整替补名单。") else ADKP_Print(err) end
end
SLASH_ADKPSUBSYNC1 = "/subteam"
SlashCmdList.ADKPSUBSYNC = ADKP_SubSync_RefreshRoster

local function abort(message)
    if ADKP_SubAwardData then ADKP_SubAwardData.subSyncAborted = true end
    ADKP_Print(message)
end
local frame = CreateFrame("Frame", "ADKP_ForeverNativePump")
frame:SetScript("OnUpdate", function()
    if GetTime() < nextSend then return end
    nextSend = GetTime() + 0.15
    for target, request in pairs(pending) do
        if request.deadline < GetTime() then pending[target] = nil; abort("替补插件 WHISPER 超时，未确认完整名单。"); end
    end
    if C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() then return end
    if C_ChatInfo.AreOutgoingAddonChatMessagesRestricted and C_ChatInfo.AreOutgoingAddonChatMessagesRestricted() then
        if table.getn(queue) > 0 then queue = {}; abort("当前客户端限制插件通信，未切换普通密语。") end
    else
        local item = table.remove(queue, 1)
        if item then
            local ok, result = pcall(C_ChatInfo.SendAddonMessage, item.prefix, item.payload, "WHISPER", item.target)
            local expected = Enum and Enum.SendAddonMessageResult and Enum.SendAddonMessageResult.Success
            if not ok or result == false or (expected ~= nil and result ~= expected) then
                queue = {}; abort("插件 WHISPER 发送失败：" .. tostring(result))
            end
        end
    end
    local chat = table.remove(ADKP_ForeverChatQueue, 1)
    if chat then
        local send = C_ChatInfo.SendChatMessage or SendChatMessage
        local ok, err = pcall(send, chat[1], chat[2], chat[3], chat[4])
        if not ok then ADKP_Print("聊天发送失败：" .. tostring(err)) end
    end
end)

local ready = true
for _, prefix in ipairs({"AMB_TBQQ", "AMB_TBFS"}) do
    local ok, result = pcall(C_ChatInfo.RegisterAddonMessagePrefix, prefix)
    if not ok or result == false then ready = false end
end
ADKP_ForeverCommReady = ready
