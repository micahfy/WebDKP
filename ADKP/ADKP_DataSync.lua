-- Single-writer DKP mirroring. GUILD only; all sender identities come from
-- CHAT_MSG_ADDON, never from an envelope's self-reported sender field.
ADKP_DataSync = { ready = false, applying = false, depth = 0, tx = {}, rx = {}, seen = {}, raw = {}, candidates = {} }
local R, D, C = ADKP_DataSync, ADKP_SyncData, ADKP_SyncCodec
local PREFIX = "ADKPSYN2"
-- Bare pipes are chat escapes in the 1.12 client, including addon packets.
-- Keep envelope separators printable and escape separators inside fields.
local SEP = "#"
local serial = 0
local function now() return GetTime and GetTime() or time() end
local function me() return UnitName("player") end
local function say(text) if ADKP_Print then ADKP_Print("[数据同步] " .. text) end end
local function state() return D.State() end
local function token()
    serial = serial + 1
    return string.sub(C.Hash(D.Identity() .. ":" .. time() .. ":" .. now() .. ":" .. serial), 1, 8) .. "-" .. serial
end
local function metaCopy(m) return C.Copy(m) end
local function activeSnapshot(s)
    if R.validSnapshot == s.snapshot and R.validMeta == s.meta then return R.validResult end
    R.validSnapshot, R.validMeta = s.snapshot, s.meta
    R.validResult = s.snapshot and D.Validate(s.snapshot, s.meta) or false
    return R.validResult
end
local function setStatus(text) R.status = text end
local function save()
    if R.liveMissing or R.recoveryDeclined or R.gatherUntil then return end
    if ADKP_Backup and (ADKP_Backup.IsChecking() or ADKP_Backup.IsSuspended(state().tableid)) then return end
    R.fileSaved = D.WriteFile(state())
end

function ADKP_DataSyncCanWrite(quiet)
    if not R.ready or R.applying then return true end
    if R.refreshing then return false end
    if ADKP_Backup and ADKP_Backup.IsChecking() then
        if not quiet then say("正在检查/恢复数据，暂缓记分。") end
        return false
    end
    local s = state()
    if (s.enabled and s.role == "slave") or R.blocked or R.activePrompt then
        if not quiet then say(s.role == "slave" and "当前为替补队长数据副本，请由主团队长记分。" or "正在检查/恢复数据，暂缓记分。") end
        return false
    end
    local datedMeta = (s.enabled and s.meta) or (ADKP_Backup and ADKP_Backup.Version(ADKP_GetTableid()))
    if datedMeta and date("%Y-%m-%d") < datedMeta.day then
        if not quiet then say("本机日期早于数据版本，请校正日期后再记分。") end
        return false
    end
    return true
end

function ADKP_DataSyncBegin()
    if not ADKP_DataSyncCanWrite() then return false end
    R.depth = R.depth + 1
    return true
end

local function sendMessage(target, message)
    local jobs = 0
    for _ in pairs(R.tx) do jobs = jobs + 1 end
    if jobs >= 64 then return nil end
    local ok, packed = pcall(C.Pack, message)
    if not ok then say("消息过大，未发送；完整数据仍保留在本机。"); return nil end
    local escaped = C.WireEncode(packed)
    if string.len(escaped) > 3145728 then say("同步数据超过大小限制，未发送。"); return nil end
    local id = token()
    local destination = C.WireEncode(target)
    local size = 254 - string.len(PREFIX) - string.len(destination) - string.len(id) - 16
    if size < 64 then return nil end
    local count = math.max(1, math.ceil(string.len(escaped) / size))
    if count > 20000 then return nil end
    local stats
    if message.kind == "FULL" or message.kind == "PATCH" then
        stats = { kind = message.kind, meta = metaCopy(message.meta), rawBytes = string.len(packed), wireBytes = string.len(escaped),
            parts = count, encoding = string.sub(escaped, 1, 1), started = now(), sentBytes = 0, retransmitted = 0 }
        R.lastTransfer = stats
        if message.kind == "FULL" then
            R.fullTransfers = (R.fullTransfers or 0) + 1; R.lastFullTransfer = stats
        end
    end
    R.tx[id] = { stats = stats, target = target, destination = destination, id = id, text = escaped,
        size = size, count = count, cursor = 1, retries = 0, missing = {},
        priority = message.kind ~= "FULL" and message.kind ~= "PATCH", kind = message.kind, meta = message.meta }
    return id
end

local function transportReply(kind, target, id, suffix)
    if table.getn(R.raw) >= 128 then return end
    local packet = kind .. SEP .. C.WireEncode(target) .. SEP .. id
    if suffix then
        local indices = {}
        for value in string.gfind(suffix, "%d+") do
            table.insert(indices, value)
            local candidate = packet .. SEP .. table.concat(indices, ",")
            if string.len(candidate) + string.len(PREFIX) > 254 then table.remove(indices); break end
        end
        if table.getn(indices) == 0 then return end
        packet = packet .. SEP .. table.concat(indices, ",")
    end
    if string.len(packet) + string.len(PREFIX) <= 254 then table.insert(R.raw, packet) end
end

local function namesFor(data, previous) return D.Dictionary(data, previous) end
local function summary(request)
    local s = state()
    return { kind = "SUMMARY", request = request, role = s.role, meta = metaCopy(s.meta),
        needsAccept = s.role == "master" and s.remoteAccepted ~= s.meta.reset }
end

local function offer()
    local s = state()
    if not s.enabled or s.role ~= "master" or not s.peer or s.peer == "" or not activeSnapshot(s)
        or R.blocked or R.recoveryDeclined then return end
    if not R.offer or R.offer.reset ~= s.meta.reset or not D.SameName(R.offer.peer, s.peer) then
        R.offer = { reset = s.meta.reset, peer = s.peer, request = token(), meta = metaCopy(s.meta) }
    end
    local baseline = s.pendingReset and s.baseline
    R.offer.useBaseline = baseline and true or false
    local offered = baseline and baseline.meta or s.meta
    local data = baseline and baseline.data or s.snapshot
    local players, logs = 0, 0
    for _ in pairs(data.players) do players = players + 1 end
    for _ in pairs(data.logs) do logs = logs + 1 end
    sendMessage(s.peer, { kind = "OFFER", request = R.offer.request, meta = metaCopy(offered), latest = metaCopy(s.meta), players = players, logs = logs })
    R.lastOffer = now()
    setStatus("等待替补队长接受重置")
end

local function sendFull(target, request, initial)
    local s = state()
    if not activeSnapshot(s) then return end
    local baseline = initial and R.offer and R.offer.useBaseline and s.baseline
    local data, meta = baseline and baseline.data or s.snapshot, baseline and baseline.meta or s.meta
    local names, reverse = namesFor(data, baseline and baseline.names or s.names)
    if not baseline then s.names = names end
    local id = sendMessage(target, { kind = "FULL", request = request or "", meta = metaCopy(meta),
        names = names, body = C.Pack(data, reverse) })
    if id and s.role == "master" then R.flight = { id = id, meta = metaCopy(meta), started = now() } end
end

local function nextMeta(data, reset)
    local s = state()
    local old = s.meta
    local localMeta = ADKP_Backup and ADKP_Backup.Version(ADKP_GetTableid())
    if localMeta and (not old or s.tableid ~= ADKP_GetTableid() or D.Compare(localMeta, old) == 1) then old = localMeta end
    if s.versionFloor and old and D.Compare(s.versionFloor, old) == 1 then old = s.versionFloor end
    local day = date("%Y-%m-%d")
    if old and day < old.day then error("local date moved backwards") end
    local id = ADKP_GetTableid()
    local sameTeam = old and old.tableid == id and D.SameName(old.master, me())
    local packed = C.Pack(data)
    return { master = me(), realm = GetRealmName(), team = sameTeam and old.team or token(),
        reset = reset and token() or (sameTeam and old.reset or token()), day = day,
        seq = sameTeam and old.day == day and old.seq + 1 or 1,
        hash = C.Hash(packed), tableid = id, name = data.definition.name }
end

function ADKP_DataSyncCommit(reset)
    if not R.ready or R.applying or R.depth > 0 then return end
    local s = state()
    if not reset and ADKP_Backup and ADKP_Backup.IsSuspended(ADKP_GetTableid()) then return end
    if s.role == "slave" and s.enabled then return end
    local pending = s.pendingReset and s.meta and D.SameName(s.meta.master, me())
    if not reset and ((not pending and (not s.enabled or s.role ~= "master")) or R.blocked or s.tableid ~= ADKP_GetTableid()) then return end
    local ok, data = pcall(D.Capture, ADKP_GetTableid())
    if not ok then say("快照创建失败，原副本未改变。"); return end
    local packed, hash = pcall(function() return C.Hash(C.Pack(data)) end)
    if not packed then say("快照超出限制，原副本未改变。"); return end
    if not reset and s.meta and s.meta.hash == hash then R.dirty = false; return end
    local valid, meta = pcall(nextMeta, data, reset)
    if not valid then setStatus("日期异常，暂停发布"); say("无法生成数据版本，请检查本机日期。"); return end
    if not D.Validate(data, meta) then
        R.blocked = s.enabled and true or false
        setStatus("业务数据校验失败，原完整副本保留")
        say("业务数据未通过快照校验，暂停发布。"); return
    end
    local before, previous = s.snapshot, s.meta
    local names, reverse, additions = namesFor(data, reset and nil or s.names)
    local journal = s.journal or {}
    if reset then journal = {} end
    if before and previous and not reset then
        local changes = C.Diff(before, data)
        table.insert(journal, { base = metaCopy(previous), meta = metaCopy(meta), body = C.Pack(changes, reverse), names = additions })
        if table.getn(journal) > 128 then table.remove(journal, 1) end
    end
    s.snapshot, s.meta, s.names, s.journal, s.tableid = data, meta, names, journal, meta.tableid
    s.versionFloor = nil
    R.dirty, R.settingsHash = false, D.SettingsHash()
    if reset then
        R.blocked, R.liveMissing = false, false
        s.remoteAccepted, s.remoteAck = nil, nil
        R.flight, R.offer = nil, nil
        s.pendingReset = true
        s.baseline = { data = C.Copy(data), meta = metaCopy(meta), names = C.Copy(names) }
        for id, job in pairs(R.tx) do
            if not job.priority and job.meta and job.meta.reset ~= meta.reset then R.tx[id] = nil end
        end
    end
    if ADKP_Backup then ADKP_Backup.Record(data, meta, reset) end
    if reset then
        R.recoveryDeclined, R.gatherUntil, R.localDue = nil, nil, nil
        R.declinedVersions, R.deferredSummaries = {}, {}
    end
    save()
    if reset then offer() end
end

function ADKP_DataSyncEnd()
    R.depth = math.max(0, R.depth - 1)
    if R.depth == 0 then ADKP_DataSyncCommit(false) end
end

function ADKP_DataSyncBeginReset()
    local datedMeta = (ADKP_Backup and ADKP_Backup.Version(ADKP_GetTableid())) or state().meta
    if datedMeta and date("%Y-%m-%d") < datedMeta.day then
        say("本机日期早于数据版本，请校正日期后再导入。"); return false
    end
    if R.ready and state().enabled and state().role == "slave" and not R.applying then
        say("替补副本不能自行重置，请先断开同步。"); return false
    end
    local s = state()
    if s.meta and s.peer and R.candidates[s.peer] then
        local candidate = R.candidates[s.peer]
        if candidate.role == "slave" and D.SameName(candidate.meta.master, me())
            and D.Compare(candidate.meta, s.meta) == 1 then s.versionFloor = metaCopy(candidate.meta) end
    end
    R.blocked, R.await, R.discovery = false, nil, nil
    R.candidates, R.promptQueue = {}, {}
    R.activePrompt, R.popupAccept, R.popupCancel = nil, nil, nil
    R.hidingPopup = true
    if StaticPopup_Hide then StaticPopup_Hide("ADKP_DATA_SYNC_CONFIRM") end
    R.hidingPopup = false
    if ADKP_Backup then ADKP_Backup.CheckFinished() end
    R.depth = R.depth + 1
    return true
end

function ADKP_DataSyncAbort()
    R.depth = math.max(0, R.depth - 1)
    if R.ready then
        if ADKP_Backup then ADKP_Backup.Decline(ADKP_GetTableid()) end
        R.blocked = true
        setStatus("业务操作出错，暂停发布；完整旧副本保留")
    end
end

function ADKP_DataSyncEndReset()
    R.depth = math.max(0, R.depth - 1)
    ADKP_DataSyncCommit(true)
end

function ADKP_DataSyncDirty()
    if R.ready and not R.applying and not R.refreshing then R.dirty = true end
end

local function refresh()
    if ADKP_RefreshBossAutoAwardLog then ADKP_RefreshBossAutoAwardLog() end
    if ADKP_UpdateTableToShow then ADKP_UpdateTableToShow() end
    if ADKP_UpdateTable then ADKP_UpdateTable() end
    if ADKP_UpdateLootList then ADKP_UpdateLootList() end
    if ADKP_Tab1_SyncChecks then ADKP_Tab1_SyncChecks() end
    if ADKP_QuickFloat_UpdateVisibility then ADKP_QuickFloat_UpdateVisibility() end
end

local function applySnapshot(data, meta, role, peer, names)
    if not D.Validate(data, meta) then return false end
    R.applying = true
    local ok, err = pcall(D.Apply, data, meta, role)
    R.applying = false
    if not ok then say("恢复失败：" .. tostring(err)); return false end
    local s = state()
    s.snapshot, s.meta, s.names = C.Copy(data), metaCopy(meta), C.Copy(names or namesFor(data))
    s.role, s.peer, s.enabled, s.tableid = role, peer, true, meta.tableid
    s.journal, s.pendingReset = {}, false
    if role == "slave" then s.accepted = meta.reset else s.remoteAccepted = meta.reset end
    R.blocked, R.await, R.flight, R.liveMissing = false, nil, nil, false
    R.gatherUntil, R.localDue, R.deferredSummaries = nil, nil, {}
    R.settingsHash = D.SettingsHash()
    if ADKP_Backup then ADKP_Backup.Complete(meta.tableid, meta) end
    R.recoveryDeclined = nil
    save()
    R.refreshing = true
    local refreshed, refreshError = pcall(refresh)
    R.refreshing = false
    if not refreshed then say("数据已完整恢复，界面刷新失败：" .. tostring(refreshError)) end
    setStatus("已同步 " .. meta.day .. "/" .. meta.seq)
    return true
end

function ADKP_DataSyncRestoreLocal(payload)
    local s, saved = state(), payload.sync
    if s.enabled and s.role == "slave" and (not saved or saved.role ~= "slave" or saved.accepted ~= payload.meta.reset) then
        say("替补副本不能自行替换数据，请由主团队长同步。"); return false
    end
    local role = saved and saved.role == "slave" and "slave" or "master"
    if not applySnapshot(payload.data, payload.meta, role, saved and saved.peer, saved and saved.names) then return false end
    s = state()
    if saved and saved.tableid == payload.meta.tableid and D.Equal(saved.meta, payload.meta) then
        s.enabled, s.role, s.peer = saved.enabled, saved.role, saved.peer
        s.accepted, s.remoteAccepted, s.remoteAck = saved.accepted, saved.remoteAccepted, C.Copy(saved.remoteAck)
        s.pendingReset, s.baseline = saved.pendingReset, C.Copy(saved.baseline)
    else s.enabled, s.role, s.peer = false, "none", nil end
    local observed = R.localPeerVersion
    if s.peer and observed and D.Equal(observed, s.meta) then
        if s.role == "master" then s.remoteAck, s.remoteAccepted = C.Copy(s.meta), s.meta.reset end
        sendMessage(s.peer, { kind = "DONE", meta = metaCopy(s.meta) })
    end
    R.localDue, R.gatherUntil, R.deferredSummaries, R.promptQueue = nil, nil, {}, {}
    R.activePrompt, R.popupAccept, R.popupCancel, R.popupRetry = nil, nil, nil, nil
    R.hidingPopup = true
    if StaticPopup_Hide then StaticPopup_Hide("ADKP_DATA_SYNC_CONFIRM") end
    R.hidingPopup = false
    save()
    say("已完整恢复当前团队的本地备份数据。")
    return true
end

local function declineRecovery(meta)
    if ADKP_Backup then ADKP_Backup.Decline(meta.tableid) end
    R.blocked, R.await, R.recoveryDeclined = false, nil, true
    R.declinedVersions = R.declinedVersions or {}
    R.declinedVersions[C.Pack(meta)] = true
    -- Stop queued business packets as well as new publishing; discovery stays available.
    for id, job in pairs(R.tx) do
        if job.kind == "FULL" or job.kind == "PATCH" or job.kind == "OFFER" then R.tx[id] = nil end
    end
    R.flight, R.offer = nil, nil
    setStatus("记录存在异常，可继续记分；自动备份和同步发布已暂停")
end

local showPrompt
local function presentPrompt()
    local prompt = R.activePrompt
    if not prompt then return end
    if InCinematic and InCinematic() then
        R.popupRetry = now() + 1
        setStatus("已收到申请，等待过场结束后确认")
        return
    end
    -- FrameXML formats this field; player-controlled percent signs are text.
    StaticPopupDialogs.ADKP_DATA_SYNC_CONFIRM.text = "%s"
    StaticPopupDialogs.ADKP_DATA_SYNC_CONFIRM.button1 = prompt.key == "local" and "是" or "接受"
    StaticPopupDialogs.ADKP_DATA_SYNC_CONFIRM.button2 = prompt.key == "local" and "否" or "取消"
    -- Vanilla calls OnCancel when all popup slots are occupied. That is not
    -- user rejection: retain the request and retry without changing data.
    R.showingPopup = true
    local ok, dialog = pcall(StaticPopup_Show, "ADKP_DATA_SYNC_CONFIRM", prompt.text)
    R.showingPopup = false
    if not ok or not dialog then
        R.popupRetry = now() + 1
        setStatus("已收到申请，等待确认窗口可用")
        if not ok and R.popupError ~= tostring(dialog) then
            R.popupError = tostring(dialog); say("确认窗口暂未显示：" .. tostring(dialog))
        end
    else R.popupRetry, R.popupError = nil, nil end
end
local function finishPrompt(accepted)
    if R.hidingPopup or R.showingPopup then return end
    local prompt = R.activePrompt
    R.activePrompt, R.popupAccept, R.popupCancel, R.popupRetry = nil, nil, nil, nil
    if prompt then
        local callback = accepted and prompt.accept or prompt.cancel
        if callback then callback() end
    end
    local nextPrompt = table.remove(R.promptQueue or {}, 1)
    if nextPrompt then
        -- FrameXML hides the old dialog after this callback returns. Show the
        -- next queued request on a later tick so it is not hidden with it.
        R.activePrompt, R.popupAccept, R.popupCancel = nextPrompt, nextPrompt.accept, nextPrompt.cancel
        R.popupRetry = now() + 1
    end
end

showPrompt = function(prompt)
    R.activePrompt, R.popupAccept, R.popupCancel = nil, nil, nil
    R.hidingPopup = true
    if StaticPopup_Hide then StaticPopup_Hide("ADKP_DATA_SYNC_CONFIRM") end
    R.hidingPopup = false
    R.activePrompt, R.popupAccept, R.popupCancel = prompt, prompt.accept, prompt.cancel
    R.popupRetry = nil
    presentPrompt()
end

local function confirm(text, accept, cancel, key)
    StaticPopupDialogs = StaticPopupDialogs or {}
    StaticPopupDialogs.ADKP_DATA_SYNC_CONFIRM = StaticPopupDialogs.ADKP_DATA_SYNC_CONFIRM or {
        text = "", button1 = "接受", button2 = "取消", timeout = 0,
        whileDead = 1, hideOnEscape = 1,
        OnAccept = function() finishPrompt(true) end,
        OnCancel = function(data, reason)
            if R.showingPopup or R.hidingPopup then return end
            if reason == "override" then R.popupRetry = now() + 1; return end
            finishPrompt(false)
        end
    }
    local prompt = { text = text, accept = accept, cancel = cancel, key = key or "general" }
    R.promptQueue = R.promptQueue or {}
    if not R.activePrompt or R.activePrompt.key == prompt.key then showPrompt(prompt)
    else
        for i, pending in ipairs(R.promptQueue) do
            if pending.key == prompt.key then R.promptQueue[i] = prompt; return end
        end
        if table.getn(R.promptQueue) < 4 then table.insert(R.promptQueue, prompt) end
    end
end

local function requestSnapshot(peer, meta, role)
    R.recoveryDeclined = nil
    local s = state()
    R.promptQueue, R.candidates = {}, {}
    local localCopy = D.ReadFiles()
    if localCopy and localCopy.snapshot and D.SameName(localCopy.peer, peer)
        and (D.SameRound(localCopy.meta, meta)
            or (role == "master" and localCopy.role == "master" and D.Compare(localCopy.meta, meta) == 1)) then
        local order = D.Compare(localCopy.meta, meta)
        if D.Equal(localCopy.meta, meta) or order == 1 then
            if applySnapshot(localCopy.snapshot, localCopy.meta, role, peer, localCopy.names) then
                if role == "master" and order == 0 then state().remoteAck = metaCopy(meta) end
                if role == "master" and not D.SameRound(localCopy.meta, meta) then
                    state().remoteAccepted, state().remoteAck = nil, nil
                    state().pendingReset, state().baseline = localCopy.pendingReset, localCopy.baseline
                    R.offer = nil
                end
                say(order == 1 and "本地完整快照更新，已本地恢复并重新校准版本。" or "已完整恢复数据到最新版本。(L)")
                sendMessage(peer, { kind = "DONE", meta = metaCopy(localCopy.meta) })
                return
            end
        end
    end
    R.await = { peer = peer, meta = metaCopy(meta), role = role, request = token(), started = now() }
    R.blocked = true
    sendMessage(peer, { kind = "GET", meta = metaCopy(meta), request = R.await.request })
    setStatus("正在请求完整恢复数据")
end

local function offerLocalRecovery()
    if R.localTried or R.await or R.activePrompt then return end
    local candidate = ADKP_Backup and ADKP_Backup.Candidate()
    if candidate then
        R.localTried = true
        local text = "检测到DKP记录异常，是否恢复自动备份的数据"
        if candidate.meta.tableid ~= ADKP_GetTableid() then text = text .. "\n团队：" .. candidate.meta.name end
        confirm(text, function()
            if ADKP_Backup.Candidate() ~= candidate then return end
            ADKP_Backup.Apply(candidate)
        end, function() declineRecovery(candidate.meta) end, "local")
        return
    end
    if not R.liveMissing then return end
    local s = state()
    local checkpoint = D.ReadFiles()
    if not checkpoint and activeSnapshot(s) then checkpoint = C.Copy(s) end
    if not checkpoint or not checkpoint.snapshot or checkpoint.role ~= "master"
        or not D.SameName(checkpoint.meta.master, me()) then return end
    R.localTried = true
    confirm("尚未收到有效对端回复。是否从本机完整快照恢复？\n版本："
        .. checkpoint.meta.day .. "/" .. checkpoint.meta.seq
        .. "\n包含全部业务数据；可能落后于离线对端，连通后会继续核对。", function()
            if applySnapshot(checkpoint.snapshot, checkpoint.meta, "master", checkpoint.peer, checkpoint.names) then
                local recovered = state()
                recovered.remoteAccepted, recovered.remoteAck = checkpoint.remoteAccepted, checkpoint.remoteAck
                recovered.pendingReset, recovered.baseline = checkpoint.pendingReset, checkpoint.baseline
                recovered.journal = checkpoint.journal or {}
                save()
                say("已从本机完整快照恢复，等待对端核对。")
            end
        end, function() declineRecovery(checkpoint.meta) end, "local")
end

local function acceptOffer(sender, message)
    local s = state()
    s.enabled, s.role, s.peer = true, "slave", sender
    s.accepted = message.meta.reset
    R.blocked = true
    R.promptQueue = {}
    R.await = { peer = sender, meta = metaCopy(message.meta), role = "slave", request = token(), started = now() }
    save()
    sendMessage(sender, { kind = "ACCEPT", reset = message.meta.reset, request = message.request, fullRequest = R.await.request })
    setStatus("申请已接受，初始复制中")
end

local function receiveOffer(sender, message)
    if type(message.request) ~= "string" or string.len(message.request) > 40 then return end
    if not D.ValidMeta(message.meta) or not D.SameName(message.meta.master, sender) then
        sendMessage(sender, { kind = "OFFER_SEEN", request = message.request, reason = "invalid" })
        setStatus("收到申请，但版本或服务器校验不通过")
        return
    end
    local s = state()
    if s.enabled and s.role == "master" then
        sendMessage(sender, { kind = "OFFER_SEEN", request = message.request, reason = "master" })
        setStatus("收到 " .. sender .. " 的申请；请先关闭本机主团同步")
        if R.lastBlockedOffer ~= message.request then
            R.lastBlockedOffer = message.request
            say("收到 " .. sender .. " 的同步申请，但本机正在作为主团发送数据；请先取消本机同步勾选，再由对方重新申请。")
        end
        return
    end
    if s.enabled and s.role == "slave" and D.SameName(s.peer, sender) and s.accepted == message.meta.reset then
        if activeSnapshot(s) and D.Equal(s.meta, message.meta) then
            sendMessage(sender, { kind = "ACCEPT", reset = message.meta.reset, request = message.request })
            sendMessage(sender, { kind = "DONE", meta = metaCopy(s.meta) })
        else acceptOffer(sender, message) end
        return
    end
    sendMessage(sender, { kind = "OFFER_SEEN", request = message.request, reason = "waiting" })
    R.offers = R.offers or {}
    if not R.offers[sender] or R.offers[sender].request ~= message.request then
        say("收到 " .. sender .. " 的数据同步申请，请在确认窗口选择接受或取消。")
    end
    R.offers[sender] = message
    setStatus("已收到 " .. sender .. " 的申请，等待确认")
    local old = s.enabled and s.peer and ("\n将替换原同步对象：" .. s.peer) or ""
    confirm("玩家 " .. sender .. " 申请数据同步。" .. old .. "\n团队：" .. tostring(message.meta.name or "DKP")
        .. "\n版本：" .. message.meta.day .. "/" .. message.meta.seq
        .. "\n接受后将替换当前业务数据，并自动绑定主团队长。", function()
            if R.offers[sender] == message then
                R.offers[sender] = nil; acceptOffer(sender, message)
            end
        end, function()
            R.offers[sender] = nil
            sendMessage(sender, { kind = "REJECT", reset = message.meta.reset, request = message.request })
        end, string.lower(sender))
end

local function receiveSummary(sender, message)
    if not D.ValidMeta(message.meta) or type(R.discovery) ~= "string" or message.request ~= R.discovery then return end
    local s = state()
    if R.await and D.SameName(R.await.peer, sender) and D.SameRound(R.await.meta, message.meta) then return end
    if s.enabled and s.peer and not D.SameName(s.peer, sender) then return end
    local role
    if message.role == "slave" and D.SameName(message.meta.master, me()) then role = "master"
    elseif message.role == "master" and D.SameName(message.meta.master, sender) then role = "slave"
    else return end
    if role == "master" and D.ValidMeta(s.meta) and s.meta.team ~= message.meta.team then return end
    if R.gatherUntil then
        R.deferredSummaries = R.deferredSummaries or {}
        R.deferredSummaries[sender] = message
        return
    end
    if R.declinedVersions and R.declinedVersions[C.Pack(message.meta)] then return end
    if R.recoveryDeclined then R.liveMissing = true end
    R.localDue = nil
    if role == "slave" and message.needsAccept then
        -- The latest reset was never accepted by B: preserve the per-reset consent.
        sendMessage(sender, { kind = "OFFER_REQUEST" }); return
    end
    if role == "master" and s.pendingReset and activeSnapshot(s) and not R.liveMissing then return end
    -- An intentional new website baseline supersedes the previous round. An
    -- old replica's discovery response must not block or undo that reset.
    if role == "master" and not R.liveMissing and activeSnapshot(s) and D.Compare(s.meta, message.meta) == 1 then
        R.blocked = false
        if D.SameRound(s.meta, message.meta) then
            s.remoteAccepted, s.remoteAck = s.meta.reset, metaCopy(message.meta)
        end
        return
    end
    if not R.liveMissing and activeSnapshot(s) and D.Equal(s.meta, message.meta) then
        R.blocked = false
        if role == "master" then s.remoteAccepted, s.remoteAck = s.meta.reset, metaCopy(message.meta) end
        setStatus("已同步 " .. s.meta.day .. "/" .. s.meta.seq)
        return
    end
    if not R.liveMissing and activeSnapshot(s) and D.Compare(s.meta, message.meta) == 1 then
        R.blocked = false
        if role == "master" then s.remoteAccepted, s.remoteAck = s.meta.reset, metaCopy(message.meta) end
        setStatus("本地更新，正在校准对端")
        return
    end
    if s.enabled and s.role == "slave" and D.SameName(s.peer, sender) and s.accepted == message.meta.reset then
        if activeSnapshot(s) and D.SameRound(s.meta, message.meta) then
            -- A valid replica can resume the ordered journal. Discovery during
            -- initial baseline replay must not force a second full database.
            sendMessage(sender, { kind = "CATCHUP", meta = metaCopy(s.meta) })
            setStatus("正在请求缺失操作")
        else requestSnapshot(sender, message.meta, "slave") end
        return
    end
    R.blocked = true
    R.candidates[sender] = message
    local label = s.enabled and (role == "master" and "替补队长 " or "主团队长 ") or "玩家 "
    confirm("是否从" .. label .. sender .. "那里恢复完整数据？"
        .. "\n团队：" .. tostring(message.meta.name or "DKP") .. "\n版本：" .. message.meta.day .. "/" .. message.meta.seq, function()
            if R.candidates[sender] == message then requestSnapshot(sender, message.meta, role) end
        end, function()
            declineRecovery(message.meta)
        end, string.lower(sender))
end

local function finishRecoveryCheck()
    R.gatherUntil = nil
    if ADKP_Backup then ADKP_Backup.CheckFinished() end
    local bestPeer, bestMessage
    for peer, message in pairs(R.deferredSummaries or {}) do
        if not bestMessage or D.Compare(message.meta, bestMessage.meta) == 1 then bestPeer, bestMessage = peer, message end
    end
    R.deferredSummaries = {}
    local localFile = ADKP_Backup and ADKP_Backup.Candidate()
    local checkpoint = D.ReadFiles()
    R.localPeerVersion = bestMessage and metaCopy(bestMessage.meta) or nil
    if bestMessage and localFile then
        local order = D.Compare(localFile.meta, bestMessage.meta)
        if order == 1 or D.Equal(localFile.meta, bestMessage.meta) then bestMessage = nil end
    elseif bestMessage and R.liveMissing and checkpoint and checkpoint.role == "master" then
        if D.Compare(checkpoint.meta, bestMessage.meta) == 1 then bestMessage = nil end
    end
    if bestMessage then
        R.localDue = nil
        receiveSummary(bestPeer, bestMessage)
    else offerLocalRecovery() end
    if not R.activePrompt and not R.await and not R.liveMissing then R.blocked = false end
end

local function validatedNames(names)
    if type(names) ~= "table" or table.getn(names) > 10000 then return false end
    local used = {}
    for id, name in pairs(names) do
        if type(id) ~= "number" or id < 1 or id > table.getn(names) or id ~= math.floor(id)
            or type(name) ~= "string" or string.len(name) == 0 or string.len(name) > 72 or used[name] then return false end
        used[name] = true
    end
    return true
end

local function handle(sender, message)
    if type(message) ~= "table" or type(message.kind) ~= "string" then return end
    local s, kind = state(), message.kind
    R.lastMessage = { sender = sender, kind = kind, stamp = now() }
    if R.recoveryDeclined and kind ~= "DISCOVER" and kind ~= "SUMMARY" and kind ~= "CANCEL" and kind ~= "GET" then return end
    if kind == "DISCOVER" then
        if s.enabled and D.SameName(s.peer, sender) and activeSnapshot(s)
            and (s.role == "master" or (s.role == "slave" and s.accepted == s.meta.reset and D.SameName(s.meta.master, sender))) then
            sendMessage(sender, summary(message.request))
        end
    elseif kind == "SUMMARY" then receiveSummary(sender, message)
    elseif kind == "OFFER" then receiveOffer(sender, message)
    elseif kind == "OFFER_SEEN" then
        if s.enabled and s.role == "master" and D.SameName(s.peer, sender) and R.offer
            and message.request == R.offer.request then
            R.offer.response = message.reason
            if message.reason == "waiting" then setStatus("替补队长已收到申请，等待其确认")
            elseif message.reason == "master" then setStatus("对端正在作为主团；请先关闭对端同步，再重新申请")
            elseif message.reason == "invalid" then setStatus("对端拒收申请：版本或服务器校验不通过") end
        end
    elseif kind == "OFFER_REQUEST" then
        if s.enabled and s.role == "master" and D.SameName(s.peer, sender) then offer() end
    elseif kind == "ACCEPT" then
        if s.enabled and s.role == "master" and D.SameName(s.peer, sender) and R.offer
            and message.request == R.offer.request and message.reset == s.meta.reset then
            local initial = s.remoteAccepted ~= message.reset
            s.remoteAccepted, s.pendingReset = message.reset, false
            save()
            if type(message.fullRequest) == "string" then sendFull(sender, message.fullRequest, initial) end
            setStatus("申请已接受，正在发送数据")
        end
    elseif kind == "REJECT" then
        if R.offer and message.request == R.offer.request and D.SameName(s.peer, sender) then
            R.lastOffer = now(); R.rejected = s.meta.reset; setStatus("替补队长拒绝重置，原副本保留")
        end
    elseif kind == "CATCHUP" then
        if s.enabled and s.role == "master" and D.SameName(s.peer, sender)
            and s.remoteAccepted == s.meta.reset and D.SameRound(s.meta, message.meta)
            and (D.Compare(s.meta, message.meta) or -1) >= 0 then
            s.remoteAck = metaCopy(message.meta)
            if R.flight and D.Equal(R.flight.meta, message.meta) then
                if R.lastFullTransfer and D.Equal(R.lastFullTransfer.meta, message.meta) then R.lastFullTransfer.confirmedAt = now() end
                R.tx[R.flight.id] = nil; R.flight = nil
            end
            setStatus("正在补齐替补队长缺失操作")
        end
    elseif kind == "GET" then
        if s.enabled and D.SameName(s.peer, sender) and D.SameRound(s.meta, message.meta)
            and (s.role == "slave" or s.remoteAccepted == s.meta.reset) then sendFull(sender, message.request) end
    elseif kind == "FULL" then
        local awaited = R.await and D.SameName(R.await.peer, sender) and message.request == R.await.request
            and D.SameRound(R.await.meta, message.meta) and (D.Compare(message.meta, R.await.meta) or -1) >= 0
        local catchup = s.enabled and s.role == "slave" and D.SameName(s.peer, sender)
            and D.SameName(message.meta and message.meta.master, sender) and D.SameRound(s.meta, message.meta)
            and s.accepted == message.meta.reset and (D.Compare(message.meta, s.meta) or -1) >= 0
        if not awaited and not catchup then return end
        if not validatedNames(message.names) or type(message.body) ~= "string" then return end
        local ok, data = pcall(C.Unpack, message.body, message.names)
        if not ok or not D.Validate(data, message.meta) then say("完整数据校验失败，原数据保留。"); return end
        local role = awaited and R.await.role or "slave"
        if role == "master" and not D.SameName(message.meta.master, me()) then return end
        if applySnapshot(data, message.meta, role, sender, message.names) then
            say("完整数据已恢复：" .. message.meta.day .. "/" .. message.meta.seq)
            sendMessage(sender, { kind = "DONE", meta = metaCopy(message.meta) })
        end
    elseif kind == "PATCH" then
        if not s.enabled or s.role ~= "slave" or not D.SameName(s.peer, sender)
            or not D.SameName(message.meta and message.meta.master, sender) or s.accepted ~= (message.meta and message.meta.reset) then return end
        if D.Equal(s.meta, message.meta) then sendMessage(sender, { kind = "DONE", meta = metaCopy(s.meta) }); return end
        if not D.Equal(s.meta, message.base) then requestSnapshot(sender, message.meta, "slave"); return end
        local names = C.Copy(s.names or {})
        local additions = message.names or {}
        for _, id in ipairs(C.Keys(additions)) do
            if id ~= table.getn(names) + 1 then return end
            names[id] = additions[id]
        end
        if not validatedNames(names) then return end
        local ok, data = pcall(function() return C.Patch(s.snapshot, C.Unpack(message.body, names)) end)
        if not ok or not D.Validate(data, message.meta) then requestSnapshot(sender, message.meta, "slave"); return end
        if applySnapshot(data, message.meta, "slave", sender, names) then
            sendMessage(sender, { kind = "DONE", meta = metaCopy(message.meta) })
        end
    elseif kind == "DONE" then
        if s.enabled and s.role == "master" and D.SameName(s.peer, sender) and s.remoteAccepted == s.meta.reset
            and ((R.flight and D.Equal(R.flight.meta, message.meta)) or D.Equal(s.meta, message.meta)) then
            s.remoteAck = metaCopy(message.meta)
            for id, job in pairs(R.tx) do
                if not job.priority and D.Equal(job.meta, message.meta) then R.tx[id] = nil end
            end
            if R.lastTransfer and D.Equal(R.lastTransfer.meta, message.meta) then R.lastTransfer.confirmedAt = now() end
            if R.lastFullTransfer and D.Equal(R.lastFullTransfer.meta, message.meta) then R.lastFullTransfer.confirmedAt = now() end
            R.flight = nil
            setStatus("副本已确认 " .. message.meta.day .. "/" .. message.meta.seq)
        end
    elseif kind == "CANCEL" then
        if s.enabled and D.SameName(s.peer, sender) then
            s.enabled = false; R.blocked = false; R.await = nil; save(); setStatus("对端已断开同步")
        end
    end
end

function ADKP_DataSyncReceive(prefix, text, channel, sender)
    if not R.ready or prefix ~= PREFIX or channel ~= "GUILD" or D.SameName(sender, me())
        or type(sender) ~= "string" or string.len(sender) > 72
        or type(text) ~= "string" or string.len(text) + string.len(PREFIX) > 254 then return end
    if ADKP_IsAddonDisabled and ADKP_IsAddonDisabled() then return end
    R.receivedPackets = (R.receivedPackets or 0) + 1
    R.receivedBytes = (R.receivedBytes or 0) + string.len(text) + string.len(PREFIX)
    local _, _, kind, target, id, rest = string.find(text, "^([MTN])#([^#]+)#([%w%-]+)#?(.*)$")
    if not kind or string.len(id) > 40 then return end
    local ok, destination = pcall(C.WireDecode, target)
    if not ok or string.len(destination) > 72 or (destination ~= "*" and not D.SameName(destination, me())) then return end
    if kind == "T" or kind == "N" then
        local tx = R.tx[id]
        if not tx or not D.SameName(tx.target, sender) then return end
        if kind == "T" then
            if R.flight and R.flight.id == id then R.flight.received = now() end
            if tx.stats then tx.stats.receivedAt = now() end
            R.tx[id] = nil
        else
            local count = 0
            for index in string.gfind(rest, "%d+") do
                index = tonumber(index)
                if index >= 1 and index <= tx.count then tx.missing[index] = true; count = count + 1 end
                if count >= 32 then break end
            end
        end
        return
    end
    local _, _, part, total, payload = string.find(rest, "^(%d+)#(%d+)#(.*)$")
    part, total = tonumber(part), tonumber(total)
    if not part or not total or part < 1 or total > 20000 or part > total then return end
    local key = string.lower(sender) .. ":" .. id
    if R.seen[key] then if destination ~= "*" then transportReply("T", sender, id) end; return end
    local s = state()
    local trusted = (s.enabled and D.SameName(s.peer, sender)) or (R.await and D.SameName(R.await.peer, sender))
    if not trusted and total > 64 then return end
    local rx = R.rx[key]
    if not rx then
        local count = 0
        for _ in pairs(R.rx) do count = count + 1 end
        if count >= 16 then return end
        rx = { sender = sender, id = id, count = total, parts = {}, received = 0, bytes = 0, last = now(), destination = destination }
        R.rx[key] = rx
    end
    if rx.count ~= total then return end
    if not rx.parts[part] then rx.parts[part] = payload; rx.received = rx.received + 1; rx.bytes = rx.bytes + string.len(payload) end
    rx.last = now()
    if R.await and D.SameName(R.await.peer, sender) then R.await.progress = now() end
    local buffered = 0
    for _, transfer in pairs(R.rx) do buffered = buffered + transfer.bytes end
    if rx.bytes > 3145728 or buffered > 4194304 then R.rx[key] = nil; return end
    if rx.received == rx.count then
        R.rx[key] = nil
        local decoded, message = pcall(function() return C.Unpack(C.WireDecode(table.concat(rx.parts))) end)
        if not decoded then return end
        R.seen[key] = now()
        if destination ~= "*" then transportReply("T", sender, id) end
        local handled, err = pcall(handle, sender, message)
        if not handled then say("已拒绝异常同步数据：" .. tostring(err)) end
    end
end

function ADKP_DataSyncDiscover()
    if not R.ready or not GetGuildInfo or not GetGuildInfo("player") then return end
    if R.await then return end
    if R.lastDiscover and now() - R.lastDiscover < 5 then return end
    R.discovery, R.lastDiscover = token(), now()
    R.candidates = {}
    sendMessage("*", { kind = "DISCOVER", request = R.discovery })
    setStatus("正在检查是否存在待恢复数据。")
end

function ADKP_DataSyncCheckRecovery()
    R.lastDiscover, R.localTried = nil, false
    R.gatherUntil, R.localDue = now() + 12, nil
    R.declinedVersions, R.deferredSummaries = {}, {}
    if ADKP_Backup then ADKP_Backup.checked = false end
    ADKP_DataSyncDiscover()
end

function ADKP_DataSyncEnable(enabled)
    local s = state()
    if not enabled then
        if s.peer and s.enabled then sendMessage(s.peer, { kind = "CANCEL" }) end
        s.enabled, s.role = false, "none"
        R.blocked, R.await, R.flight, R.offer = false, nil, nil, nil
        save(); setStatus("同步已关闭"); return
    end
    if s.role == "slave" and s.enabled then say("当前已经从主团队长接收数据。"); return end
    if ADKP_Backup and ADKP_Backup.IsSuspended() then
        say("记录存在异常，请恢复数据或导入网站数据后再开启同步。"); return
    end
    local peer = ADKP_GetSubCaptain and ADKP_GetSubCaptain(ADKP_GetTableid()) or ""
    if peer == "" or D.SameName(peer, me()) then say("请先设置另一位玩家为替补队长。"); return end
    if not GetGuildInfo or not GetGuildInfo("player") then say("数据同步双方必须在相同公会。"); return end
    if s.enabled and s.peer and not D.SameName(s.peer, peer) then sendMessage(s.peer, { kind = "CANCEL" }) end
    s.enabled, s.role, s.peer = true, "master", peer
    if not activeSnapshot(s) or s.tableid ~= ADKP_GetTableid() then ADKP_DataSyncCommit(true)
    else ADKP_DataSyncCommit(false) end
    s.remoteAccepted, s.remoteAck = nil, nil
    R.offer, R.rejected = nil, nil
    save(); offer()
end

local function pumpBusiness()
    local s = state()
    if not s.enabled or s.role ~= "master" or not activeSnapshot(s) or R.blocked or R.recoveryDeclined then return end
    if s.remoteAccepted ~= s.meta.reset then
        if R.rejected ~= s.meta.reset and (not R.lastOffer or now() - R.lastOffer > 30) then offer() end
        return
    end
    if R.flight then
        if R.tx[R.flight.id] or now() - (R.flight.received or R.flight.started) < 30 then return end
        R.flight = nil
    end
    if D.Equal(s.remoteAck, s.meta) then return end
    for _, entry in ipairs(s.journal or {}) do
        if D.Equal(entry.base, s.remoteAck) then
            local id = sendMessage(s.peer, { kind = "PATCH", base = entry.base, meta = entry.meta, names = entry.names, body = entry.body })
            if id then R.flight = { id = id, meta = metaCopy(entry.meta), started = now() } end
            return
        end
    end
    sendFull(s.peer)
end

local function transportTick(elapsed)
    R.budget = math.min(508, (R.budget or 0) + elapsed * 500)
    local packet, job
    if table.getn(R.raw) > 0 then packet = R.raw[1] end
    if not packet then
        for id, tx in pairs(R.tx) do
            if tx.sent and now() - tx.sent > 12 then
                if tx.target == "*" or tx.retries >= 3 then R.tx[id] = nil
                else tx.retries = tx.retries + 1; tx.cursor = 1; tx.sent = nil end
            end
            if R.tx[id] and (tx.cursor <= tx.count or next(tx.missing)) then
                if not job or (tx.priority and not job.priority) then job = tx end
            end
        end
        if job then
            local index = next(job.missing) or job.cursor
            packet = "M" .. SEP .. job.destination .. SEP .. job.id .. SEP .. index .. SEP .. job.count .. SEP
                .. string.sub(job.text, (index - 1) * job.size + 1, index * job.size)
            job.nextIndex = index
        end
    end
    if packet and R.budget >= string.len(packet) + string.len(PREFIX) then
        local ok, err = pcall(SendAddonMessage, PREFIX, packet, "GUILD")
        if not ok then
            R.lastSendError = tostring(err)
            setStatus("数据同步发送失败（/adkpsync 查看完整错误）"); return
        end
        local packetBytes = string.len(packet) + string.len(PREFIX)
        R.sentPackets = (R.sentPackets or 0) + 1
        R.sentBytes = (R.sentBytes or 0) + packetBytes
        if job and job.stats then
            job.stats.sentBytes = job.stats.sentBytes + packetBytes
            job.sentParts = job.sentParts or {}
            if job.sentParts[job.nextIndex] then
                job.stats.retransmitted = job.stats.retransmitted + 1
                R.retransmitted = (R.retransmitted or 0) + 1
            end
            job.sentParts[job.nextIndex] = true
        end
        R.budget = R.budget - string.len(packet) - string.len(PREFIX)
        if job then
            if job.missing[job.nextIndex] then job.missing[job.nextIndex] = nil else job.cursor = job.cursor + 1 end
            if job.cursor > job.count and not next(job.missing) then
                if job.stats then job.stats.sentFinished = now() end
                if job.target == "*" then R.tx[job.id] = nil else job.sent = now() end
            end
        else table.remove(R.raw, 1) end
    end
    for key, rx in pairs(R.rx) do
        if now() - rx.last > 120 then R.rx[key] = nil
        elseif now() - rx.last > 3 and (not rx.nack or now() - rx.nack > 5) and rx.destination ~= "*" then
            local missing = {}
            for i = 1, rx.count do
                if not rx.parts[i] then table.insert(missing, tostring(i)) end
                if table.getn(missing) >= 20 then break end
            end
            transportReply("N", rx.sender, rx.id, table.concat(missing, ",")); rx.nack = now()
        end
    end
    for key, stamp in pairs(R.seen) do if now() - stamp > 600 then R.seen[key] = nil end end
end

function ADKP_DataSyncCreateControls()
    if R.check or not ADKP_AwardDKP_Frame then return end
    local parent = ADKP_AwardDKP_Frame
    R.check = CreateFrame("CheckButton", "ADKP_DataSyncCheck", parent, "UICheckButtonTemplate")
    R.check:SetWidth(22); R.check:SetHeight(22)
    R.check:SetPoint("TOPLEFT", parent, "TOPLEFT", 210, -105)
    R.label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    R.label:SetPoint("LEFT", R.check, "RIGHT", 2, 0)
    R.label:SetText("与替补队长同步数据")
    R.check:SetScript("OnClick", function()
        ADKP_DataSyncEnable(this:GetChecked() and true or false)
        this:SetChecked(state().enabled and true or false)
    end)
    R.check:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
        GameTooltip:SetText("完整 DKP 数据同步")
        GameTooltip:AddLine("仅同公会。替补队长每次接受重置后清空并复制主团数据；收到的副本只读。", 1, 1, 1, true)
        GameTooltip:AddLine(R.status or "同步未开启", 1, 0.8, 0.3, true)
        GameTooltip:Show()
    end)
    R.check:SetScript("OnLeave", function() GameTooltip:Hide() end)
    local button = CreateFrame("Button", "ADKP_DataSyncDiscoverButton", parent, "UIPanelButtonTemplate")
    button:SetWidth(78); button:SetHeight(22)
    button:SetPoint("TOPLEFT", parent, "TOPLEFT", 307, -12)
    button:SetText("检查恢复")
    button:SetScript("OnClick", ADKP_DataSyncCheckRecovery)
    R.statusLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    R.statusLabel:SetPoint("TOPLEFT", parent, "TOPLEFT", 15, -60)
    R.statusLabel:SetWidth(375); R.statusLabel:SetHeight(13); R.statusLabel:SetJustifyH("LEFT")
end

local function updateControls()
    ADKP_DataSyncCreateControls()
    if not R.check then return end
    local s = state()
    R.check:SetChecked(s.enabled and true or false)
    R.label:SetText(s.role == "slave" and s.enabled and "从主团队长接收数据" or "与替补队长同步数据")
    local source = s.enabled and ((s.role == "slave" and "主团：" or "替补：") .. (s.peer or "") .. " · ") or ""
    local status = R.status or "同步未开启"
    if s.enabled and (not GetGuildInfo or not GetGuildInfo("player")) then status = "尚未就绪，暂停通讯" end
    if ADKP_Backup and ADKP_Backup.IsSuspended() and not R.await then status = "记录存在异常，自动备份已暂停" end
    if R.await then
        for _, transfer in pairs(R.rx) do
            if D.SameName(transfer.sender, R.await.peer) and transfer.count > 8 then
                status = "接收完整数据 " .. math.floor(transfer.received * 100 / transfer.count) .. "%"; break
            end
        end
    end
    R.statusLabel:SetText(source .. status .. (s.enabled and (R.fileSaved and " · 文件已保存" or " · 文件待保存") or ""))
end

local function wrap(name, guardOnly)
    local original = getglobal(name)
    if type(original) ~= "function" then return end
    setglobal(name, function(...)
        if not ADKP_DataSyncCanWrite() then return nil end
        if not guardOnly then R.depth = R.depth + 1 end
        local function packedResults(...) return arg end
        local results = packedResults(pcall(original, unpack(arg)))
        if not guardOnly then R.depth = math.max(0, R.depth - 1) end
        if not results[1] then
            if R.ready and state().enabled then R.blocked = true; setStatus("业务操作出错，暂停发布") end
            error(results[2])
        end
        if not guardOnly and R.depth == 0 then ADKP_DataSyncCommit(false) end
        for i = 1, results.n - 1 do results[i] = results[i + 1] end
        results[results.n] = nil
        results.n = results.n - 1
        return unpack(results)
    end)
end

local function installHooks()
    for _, name in ipairs({ "ADKP_AddDKP", "ADKP_AddDKPToTable", "ADKP_EditDKPRecord", "ADKP_EditLootRecord",
        "ADKP_EditSubstituteRecord", "ADKP_RemovePlayerFromDKPRecord", "ADKP_AddPlayerToDKPRecord",
        "ADKP_DeleteLootRecord", "ADKP_DeleteDKPRecordByItemAndTime", "ADKP_DeleteSubstituteRecordByItemAndTime",
        "ADKP_AdjustPlayerDkp", "ADKP_Share_Bind", "ADKP_Share_CancelProposal", "ADKP_Share_ApplyWebsiteList",
        "ADKP_Share_RecalculateGroup", "ADKP_RevertUnassignedLootRecord",
        "ADKP_SetBossPointField", "ADKP_SetAllBossPoints", "ADKP_SetBossEnabledState", "ADKP_AddCustomBoss",
        "ADKP_RemoveCustomBoss", "ADKP_AddExcludedBoss", "ADKP_RemoveExcludedBoss", "ADKP_ProcessSubstitutes" }) do wrap(name, false) end
    for _, name in ipairs({ "ADKP_HandleCombatHostileDeath", "ADKP_AwardItem_Event", "ADKP_RunRaidAndSubAward",
        "ADKP_Bid_StartBid", "ADKP_Bid_AwardSelected", "ADKP_Bid_EndTransmogSelection", "ADKP_Bid_PassButtonClick",
        "ADKP_DeleteTable", "ADKP_CreateTable", "ADKP_AwardSubDKP",
        "ADKP_AwardAllDKP_Event", "ADKP_BossKillAwardFrame_OkClick", "ADKP_SingleAdjust_OnClick",
        "ADKP_AwardRaidAndSub_Event" }) do wrap(name, true) end
    local originalSave = ADKP_SaveToDisk
    ADKP_SaveToDisk = function(skip)
        if originalSave then originalSave(skip) end
        ADKP_DataSyncDirty()
    end
    local originalImport = ADKP_DoImportInitial
    if originalImport then
        ADKP_DoImportInitial = function(text)
            local s = state()
            if R.ready and s.enabled and s.role == "slave" and not R.applying then
                say("替补副本不能自行重置，请先断开同步。"); return
            end
            -- A may explicitly choose a new website baseline instead of
            -- recovery. The existing import confirmation remains mandatory.
            return originalImport(text)
        end
    end
    local originalDisplay = ADKP_UpdateTableToShow
    if originalDisplay then
        ADKP_UpdateTableToShow = function()
            originalDisplay()
            ADKP_DataSyncDirty()
        end
    end
    local originalDelete = ADKP_DeleteTable
    if originalDelete then
        ADKP_DeleteTable = function(tableid)
            local s = state()
            if s.enabled and s.role == "master" and s.tableid == tableid then
                say("请先断开该团队的数据同步，再删除团队。"); return
            end
            return originalDelete(tableid)
        end
    end
    local originalCaptain = ADKP_SetSubCaptain
    ADKP_SetSubCaptain = function(tableid, captain)
        originalCaptain(tableid, captain)
        local s = state()
        if R.ready and not R.applying and s.enabled and s.role == "master" and s.tableid == tableid
            and not D.SameName(s.peer, captain) then ADKP_DataSyncEnable(false) end
    end
end

function ADKP_DataSyncInitialize()
    if R.ready then return end
    if not me() or me() == "" or not GetRealmName() or GetRealmName() == "" then return end
    local s = state()
    if ADKP_Backup then ADKP_Backup.Initialize() end
    local disk = D.ReadFiles()
    if disk and (not activeSnapshot(s) or (tonumber(disk.fileSerial) or 0) > (tonumber(s.fileSerial) or 0)) then
        ADKP_SyncStore[D.Identity()] = disk
        s = disk
    end
    local bestLocal = ADKP_Backup and ADKP_Backup.Candidate()
    if bestLocal and bestLocal.sync and (not activeSnapshot(s) or D.Compare(bestLocal.meta, s.meta) == 1) then
        ADKP_SyncStore[D.Identity()] = C.Copy(bestLocal.sync); s = state()
    end
    s.journal = s.journal or {}
    -- Files provide candidates, not permission to silently replace live DKP.
    -- Slave checkpoints can resume automatically under their retained consent.
    R.ready = true
    R.blocked = s.enabled and (s.role == "slave" or not activeSnapshot(s)) or false
    if s.enabled and s.role == "slave" and activeSnapshot(s) and s.accepted == s.meta.reset
        and D.SameName(s.meta.master, s.peer) then applySnapshot(s.snapshot, s.meta, "slave", s.peer, s.names) end
    if s.enabled and s.role == "master" and activeSnapshot(s) then
        local ok, current = pcall(D.Capture, s.tableid)
        if not ok or C.Hash(C.Pack(current)) ~= s.meta.hash then
            R.blocked, R.liveMissing = true, true
            setStatus("本地数据不完整，等待恢复")
            R.localDue = now() + 12
        end
    end
    local localFile = ADKP_Backup and ADKP_Backup.Candidate()
    if localFile then
        R.liveMissing, R.blocked = true, true
        if not activeSnapshot(s) and localFile.sync then
            ADKP_SyncStore[D.Identity()] = C.Copy(localFile.sync); s = state()
        end
    end
    R.recoveryDeclined = ADKP_Backup and ADKP_Backup.IsSuspended(s.tableid or ADKP_GetTableid()) and not localFile or nil
    if R.recoveryDeclined then R.blocked = false end
    R.gatherUntil, R.localDue, R.deferredSummaries = now() + 12, nil, {}
    R.settingsHash = D.SettingsHash()
    R.discoverDue = now() + 2
    updateControls()
end

function ADKP_DataSyncTick(elapsed)
    if not R.ready then return end
    if ADKP_IsAddonDisabled and ADKP_IsAddonDisabled() then return end
    if R.gatherUntil and now() >= R.gatherUntil then finishRecoveryCheck() end
    if ADKP_Backup then ADKP_Backup.Tick() end
    if R.localDue and now() >= R.localDue then R.localDue = nil; offerLocalRecovery() end
    if R.activePrompt then
        if not R.popupRetry and StaticPopup_Visible and not StaticPopup_Visible("ADKP_DATA_SYNC_CONFIRM") then
            R.popupRetry = now() + 1
        end
        if R.popupRetry and now() >= R.popupRetry then presentPrompt() end
    end
    if not GetGuildInfo or not GetGuildInfo("player") then updateControls(); return end
    transportTick(elapsed)
    R.poll = (R.poll or 0) + elapsed
    if R.poll < 1 then return end
    R.poll = 0
    local s = state()
    if R.offer and not R.offer.response and R.lastOffer and now() - R.lastOffer > 15
        and s.enabled and s.remoteAccepted ~= (s.meta and s.meta.reset) then
        setStatus("对端尚未回复申请；检查同公会、插件版本和总开关状态。")
    end
    if R.discoverDue and now() >= R.discoverDue then R.discoverDue = nil; ADKP_DataSyncDiscover() end
    if s.enabled and R.lastDiscover and now() - R.lastDiscover > 60 and not R.await then ADKP_DataSyncDiscover() end
    if R.await and now() - (R.await.progress or R.await.started) > 180 then
        R.await = nil; setStatus("恢复超时，原数据保留；可再次检查恢复")
    end
    if s.enabled and s.role == "master" and not R.blocked and s.tableid == ADKP_GetTableid() then
        local settingsHash = D.SettingsHash()
        if R.dirty or settingsHash ~= R.settingsHash then ADKP_DataSyncCommit(false) end
    end
    pumpBusiness()
    updateControls()
end

installHooks()
local frame = CreateFrame("Frame", "ADKP_DataSyncEventFrame")
for _, eventName in ipairs({ "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "RAID_ROSTER_UPDATE",
    "PARTY_MEMBERS_CHANGED", "GUILD_ROSTER_UPDATE", "CHAT_MSG_ADDON", "PLAYER_LOGOUT" }) do frame:RegisterEvent(eventName) end
frame:SetScript("OnEvent", function()
    if event == "CHAT_MSG_ADDON" then ADKP_DataSyncReceive(arg1, arg2, arg3, arg4)
    elseif event == "PLAYER_LOGOUT" then
        if R.ready then
            ADKP_DataSyncCommit(false)
            if ADKP_Backup then ADKP_Backup.Tick() end
            save()
        end
    elseif event == "ADDON_LOADED" then if arg1 == "ADKP" then ADKP_DataSyncInitialize() end
    elseif event == "PLAYER_LOGIN" then ADKP_DataSyncInitialize()
    elseif R.ready then
        local grouped = (GetNumRaidMembers and GetNumRaidMembers() > 0) or (GetNumPartyMembers and GetNumPartyMembers() > 0)
        if event == "PLAYER_ENTERING_WORLD" or (grouped and not R.wasGrouped) then R.discoverDue = now() + 2 end
        R.wasGrouped = grouped
    end
end)
frame:SetScript("OnUpdate", function() ADKP_DataSyncTick(arg1 or 0) end)

-- A standalone command works even if the main command parser/UI is unavailable.
SLASH_ADKPDATASYNC1 = "/adkpsync"
SlashCmdList.ADKPDATASYNC = function()
    local s = state()
    say("协议 " .. PREFIX .. "；初始化=" .. tostring(R.ready)
        .. "；公会=" .. tostring(GetGuildInfo and GetGuildInfo("player") or "无")
        .. "；插件=" .. ((ADKP_IsAddonDisabled and ADKP_IsAddonDisabled()) and "已禁用" or "已启用"))
    say("身份=" .. tostring(s.role) .. "；同步=" .. tostring(s.enabled)
        .. "；对象=" .. tostring(s.peer or "无") .. "；状态=" .. tostring(R.status or "未开启"))
    say("发送分片=" .. tostring(R.sentPackets or 0) .. "；收到公会协议包=" .. tostring(R.receivedPackets or 0))
    if R.lastMessage then say("最近完整消息=" .. R.lastMessage.kind .. "；来自=" .. R.lastMessage.sender) end
    say("累计发送字节=" .. tostring(R.sentBytes or 0) .. "；补发分片=" .. tostring(R.retransmitted or 0) .. "；限速=500字节/秒")
    local function printTransfer(t, label)
        if not t then return end
        say(label .. "=" .. t.kind .. "；原始=" .. t.rawBytes .. "；编码后=" .. t.wireBytes
            .. "；分片=" .. t.parts .. "；编码=" .. t.encoding .. "；补发=" .. t.retransmitted)
        if t.sentFinished then say("发送耗时=" .. string.format("%.1f", t.sentFinished - t.started) .. "秒；含包头发送=" .. t.sentBytes .. "字节") end
        if t.confirmedAt then say("业务确认耗时=" .. string.format("%.1f", t.confirmedAt - t.started) .. "秒") end
    end
    printTransfer(R.lastTransfer, "最近业务传输")
    if R.lastFullTransfer ~= R.lastTransfer then printTransfer(R.lastFullTransfer, "最近整库传输") end
    if R.lastSendError then say("最近发送错误（完整）：" .. R.lastSendError) end
end
