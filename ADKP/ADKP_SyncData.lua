-- Complete business snapshots and crash-safe local checkpoints.
ADKP_SyncData = {}
local D, C = ADKP_SyncData, ADKP_SyncCodec
D.Settings = {
    "AutofillEnabled", "AutofillThreshold", "AutoAwardEnabled", "LootQualityLevel",
    "BossDeathPopup", "BossAutoAward", "BossPoints", "BossPointsDefault",
    "ExcludedBosses", "BossPatterns", "EnabledRaidBosses",
    "IncludeSubCaptain", "PassAssignToSelf", "SilentMode", "RaidDkpReply", "AuctionMode", "QuickBidQualityFilter",
    "AutoInviteEnabled", "AutoConvertRaid", "AutoInviteKeyword",
    "QuickFloatSettings", "QuickAdjustSettings", "SubSettings", "ZeroSumEnabled"
}

function D.Identity()
    return (GetRealmName() or "") .. ":" .. (UnitName("player") or "")
end

function D.State()
    if type(ADKP_SyncStore) ~= "table" then ADKP_SyncStore = {} end
    local identity = D.Identity()
    if type(ADKP_SyncStore[identity]) ~= "table" then
        ADKP_SyncStore[identity] = { identity = identity, role = "none", enabled = false, journal = {} }
    end
    return ADKP_SyncStore[identity]
end

function D.SameName(a, b)
    return type(a) == "string" and type(b) == "string" and string.lower(a) == string.lower(b)
end

function D.ValidMeta(m)
    return type(m) == "table" and type(m.master) == "string" and string.len(m.master) > 0
        and string.len(m.master) <= 72 and m.realm == GetRealmName()
        and type(m.team) == "string" and string.find(m.team, "^[%w%-]+$")
        and string.len(m.team) <= 48 and type(m.reset) == "string"
        and string.find(m.reset, "^[%w%-]+$") and string.len(m.reset) <= 48
        and type(m.day) == "string" and string.find(m.day, "^%d%d%d%d%-%d%d%-%d%d$")
        and type(m.seq) == "number" and m.seq >= 1 and m.seq <= 1000000000
        and m.seq == math.floor(m.seq) and type(m.hash) == "string"
        and string.len(m.hash) <= 32 and string.find(m.hash, "^%x+:%d+$")
        and (m.name == nil or (type(m.name) == "string" and string.len(m.name) <= 160))
        and type(m.tableid) == "number" and m.tableid >= 1 and m.tableid <= 1000000
        and m.tableid == math.floor(m.tableid)
end

function D.SameRound(a, b)
    return D.ValidMeta(a) and D.ValidMeta(b) and a.team == b.team and a.reset == b.reset
        and D.SameName(a.master, b.master)
end

function D.Compare(a, b)
    if not D.ValidMeta(a) or not D.ValidMeta(b) or a.team ~= b.team
        or not D.SameName(a.master, b.master) then return nil end
    if a.day ~= b.day then return a.day > b.day and 1 or -1 end
    if a.seq ~= b.seq then return a.seq > b.seq and 1 or -1 end
    return 0
end

function D.Equal(a, b)
    return D.SameRound(a, b) and D.Compare(a, b) == 0 and a.hash == b.hash
end

local function businessSettings(tableid)
    local result = {}
    for _, key in ipairs(D.Settings) do
        if WebDKP_Options and WebDKP_Options[key] ~= nil then result[key] = C.Copy(WebDKP_Options[key]) end
    end
    if result.QuickAdjustSettings then result.QuickAdjustSettings.position = nil end
    if result.QuickFloatSettings then result.QuickFloatSettings.position = nil end
    if result.QuickFloatSettings and result.QuickFloatSettings.adjust then result.QuickFloatSettings.adjust.position = nil end
    for _, key in ipairs({ "QuickFloatSettings", "QuickAdjustSettings" }) do
        if result[key] and next(result[key]) == nil then result[key] = nil end
    end
    local captain = ADKP_GetSubCaptain and ADKP_GetSubCaptain(tableid or ADKP_GetTableid()) or ""
    if result.SubSettings then
        result.SubSettings.captains = nil
        result.SubSettings.captain = captain
    end
    return result
end

function D.RecordTeam(record)
    if type(record) ~= "table" then return 1 end
    if tonumber(record.tableid) then return tonumber(record.tableid) end
    if record.uniqueId then
        for _, log in pairs(WebDKP_Log or {}) do
            if type(log) == "table" and log.uniqueId == record.uniqueId then return tonumber(log.tableid) or 1 end
        end
    end
    return 1
end

local function scopedRecords(records, id, keepOthers, named)
    local result = {}
    for _, index in ipairs(C.Keys(records or {})) do
        local record = records[index]
        assert(type(record) == "table", "invalid scoped business record")
        if (D.RecordTeam(record) == id) ~= (keepOthers and true or false) then
            local copy = C.Copy(record)
            copy.tableid = D.RecordTeam(record)
            if named and type(index) == "string" and not copy.name then copy.name = index end
            table.insert(result, copy)
        end
    end
    return result
end
local function scopedDaily(daily, id, keepOthers)
    local result = {}
    for day, records in pairs(daily or {}) do
        local kept = scopedRecords(records, id, keepOthers, true)
        if table.getn(kept) > 0 then result[day] = kept end
    end
    return result
end

function D.Capture(tableid)
    local data = { scope = 2, players = {}, logs = {}, settings = businessSettings(tableid) }
    local field = "dkp_" .. tableid
    for name, player in pairs(WebDKP_DkpTable or {}) do
        if type(player) == "table" and (player[field] ~= nil or player["dkp" .. tableid] ~= nil) then
            local copy = {}
            for key, value in pairs(player) do
                if type(key) == "string" and not string.find(key, "^dkp_?%d+$")
                    and key ~= "Selected" and key ~= "IsSub" then copy[key] = C.Copy(value) end
            end
            copy.dkp = assert(tonumber(player[field] or player["dkp" .. tableid]), "invalid player score")
            data.players[name] = copy
        end
    end
    for key, entry in pairs(WebDKP_Log or {}) do
        if type(entry) == "table" and (tonumber(entry.tableid) or 1) == tableid then
            data.logs[key] = C.Copy(entry)
            data.logs[key].points = assert(tonumber(entry.points), "invalid log score")
            if type(data.logs[key].awarded) ~= "table" then data.logs[key].awarded = {} end
        end
    end
    local definition = nil
    for _, entry in pairs(WebDKP_Tables or {}) do
        if type(entry) == "table" and entry.id == tableid then definition = entry; break end
    end
    data.definition = C.Copy(definition or { id = tableid, name = "DKP" })
    data.daily = scopedDaily(WebDKP_DailySubRecords, tableid)
    data.history = scopedRecords(WebDKP_LootHistory, tableid)
    data.loot = C.Copy(WebDKP_Loot or {})
    data.web = C.Copy(WebDKP_WebOptions or {})
    data.groups = C.Copy(ADKP_ShareGroups and ADKP_ShareGroups[tableid] or {})
    data.proposals = C.Copy(ADKP_ShareProposals and ADKP_ShareProposals[tableid] or {})
    data.bases = C.Copy(ADKP_ShareSessionBase and ADKP_ShareSessionBase[tableid] or {})
    return data
end

function D.SettingsHash()
    return C.Hash(C.Pack(businessSettings()))
end

function D.Validate(data, meta)
    if not D.ValidMeta(meta) or type(data) ~= "table" or data.scope ~= 2 then return false end
    for _, key in ipairs({ "players", "logs", "settings", "definition", "daily", "history",
        "loot", "web", "groups", "proposals", "bases" }) do
        if type(data[key]) ~= "table" then return false end
    end
    if data.definition.id ~= meta.tableid or type(data.definition.name) ~= "string" then return false end
    for _, key in ipairs({ "SubSettings", "BossPoints", "BossPointsDefault", "BossPatterns", "EnabledRaidBosses", "ExcludedBosses", "QuickFloatSettings" }) do
        if data.settings[key] ~= nil and type(data.settings[key]) ~= "table" then return false end
    end
    if data.settings.SubSettings and data.settings.SubSettings.captain ~= nil
        and type(data.settings.SubSettings.captain) ~= "string" then return false end
    for name, player in pairs(data.players) do
        if type(name) ~= "string" or string.len(name) == 0 or string.len(name) > 72
            or type(player) ~= "table" or type(player.dkp) ~= "number"
            or player.dkp ~= player.dkp or math.abs(player.dkp) >= 1e308 then return false end
    end
    for key, entry in pairs(data.logs) do
        if type(key) ~= "string" or type(entry) ~= "table" or type(entry.awarded) ~= "table"
            or type(entry.points) ~= "number" or (tonumber(entry.tableid) or 1) ~= meta.tableid then return false end
    end
    local ok, encoded = pcall(C.Pack, data)
    return ok and C.Hash(encoded) == meta.hash
end

function D.Dictionary(data, existing)
    local names, reverse = C.Copy(existing or {}), {}
    for id, name in ipairs(names) do reverse[name] = id end
    local added = {}
    local function add(name)
        if type(name) == "string" and not reverse[name] then
            table.insert(names, name)
            reverse[name] = table.getn(names)
            added[table.getn(names)] = name
        end
    end
    for _, name in ipairs(C.Keys(data.players)) do add(name) end
    for _, key in ipairs(C.Keys(data.logs)) do
        for _, name in ipairs(C.Keys(data.logs[key].awarded or {})) do add(name) end
    end
    return names, reverse, added
end

function D.Apply(data, meta, role)
    assert(D.Validate(data, meta), "invalid complete snapshot")
    local id = meta.tableid
    local players, logs, tables, groups, proposals, bases
    if role == "slave" then
        players, logs, tables, groups, proposals, bases = {}, {}, {}, {}, {}, {}
    else
        players, logs, tables = C.Copy(WebDKP_DkpTable or {}), C.Copy(WebDKP_Log or {}), C.Copy(WebDKP_Tables or {})
        groups, proposals, bases = C.Copy(ADKP_ShareGroups or {}), C.Copy(ADKP_ShareProposals or {}), C.Copy(ADKP_ShareSessionBase or {})
        for name, player in pairs(players) do
            if type(player) == "table" then
                player["dkp_" .. id], player["dkp" .. id] = nil, nil
            end
        end
        local remove = {}
        for key, entry in pairs(logs) do
            if type(entry) == "table" and (tonumber(entry.tableid) or 1) == id then table.insert(remove, key) end
        end
        for _, key in ipairs(remove) do logs[key] = nil end
    end
    for name, player in pairs(data.players) do
        local target = players[name] or {}
        players[name] = target
        for key, value in pairs(player) do if key ~= "dkp" then target[key] = C.Copy(value) end end
        target["dkp_" .. id] = player.dkp
        target.Selected, target.IsSub = false, false
    end
    for key, entry in pairs(data.logs) do
        if logs[key] and type(logs[key]) == "table" and (tonumber(logs[key].tableid) or 1) ~= id then
            error("恢复日志键与其他团队冲突，原数据未改变")
        end
        logs[key] = C.Copy(entry)
    end
    logs.Version = 2
    tables[id] = C.Copy(data.definition)
    groups[id], proposals[id], bases[id] = C.Copy(data.groups), C.Copy(data.proposals), C.Copy(data.bases)
    local options = C.Copy(WebDKP_Options or {})
    for _, key in ipairs(D.Settings) do
        local localOnly = role == "slave" and (key == "AutoInviteEnabled" or key == "AutoConvertRaid" or key == "AutoInviteKeyword")
        if key ~= "SubSettings" and not localOnly then
            local position = nil
            if key == "QuickFloatSettings" and options[key] and options[key].adjust then position = options[key].adjust.position end
            local localPosition = (key == "QuickFloatSettings" or key == "QuickAdjustSettings")
                and options[key] and C.Copy(options[key].position)
            options[key] = C.Copy(data.settings[key])
            if localPosition then options[key] = options[key] or {}; options[key].position = localPosition end
            if position and options[key] and options[key].adjust then options[key].adjust.position = position end
        end
    end
    if role == "master" and data.settings.SubSettings then
        if type(options.SubSettings) ~= "table" then options.SubSettings = {} end
        for key, value in pairs(data.settings.SubSettings) do
            if key ~= "captain" then options.SubSettings[key] = C.Copy(value) end
        end
        if type(options.SubSettings.captains) ~= "table" then options.SubSettings.captains = {} end
        options.SubSettings.captain = data.settings.SubSettings.captain or ""
        options.SubSettings.captains[id] = options.SubSettings.captain
    end
    options.SelectedTableId = id
    local daily, history, loot, web = C.Copy(data.daily), C.Copy(data.history), C.Copy(data.loot), C.Copy(data.web)
    if role ~= "slave" then
        local otherDaily = scopedDaily(WebDKP_DailySubRecords, id, true)
        for day, records in pairs(daily) do
            otherDaily[day] = otherDaily[day] or {}
            for _, record in ipairs(records) do table.insert(otherDaily[day], record) end
        end
        daily = otherDaily
        local otherHistory = scopedRecords(WebDKP_LootHistory, id, true)
        for _, record in ipairs(history) do table.insert(otherHistory, record) end
        history = otherHistory
    end
    -- No callbacks or UI work runs between these reference swaps. Preparation
    -- errors above leave the live database untouched.
    WebDKP_DkpTable, WebDKP_Log, WebDKP_Tables = players, logs, tables
    WebDKP_DailySubRecords, WebDKP_LootHistory, WebDKP_Loot, WebDKP_WebOptions = daily, history, loot, web
    ADKP_ShareGroups, ADKP_ShareProposals, ADKP_ShareSessionBase = groups, proposals, bases
    WebDKP_Options = options
    if role == "master" and type(ADKP_SubAwardData) == "table" and options.SubSettings then
        ADKP_SubAwardData.captain = options.SubSettings.captain or ""
    end
    selectedTableid = id
    if ADKP_Frame then ADKP_Frame.selectedTableid = id end
end

local function fileName(slot)
    local key = string.gsub(C.Hash(D.Identity()), ":", "-")
    return "ADKP-SYNC-" .. key .. "-" .. slot
end

function D.ReadFiles()
    if not SUPERWOW_STRING or type(ImportFile) ~= "function" then return nil end
    local best = nil
    for slot = 0, 1 do
        local ok, text = pcall(ImportFile, fileName(slot))
        if ok and type(text) == "string" and string.len(text) <= C.MAX_BYTES * 3 + 11
            and string.sub(text, 1, 11) == "ADKP-SYNC1:" then
            local decoded, envelope = pcall(function() return C.Unpack(C.Unescape(string.sub(text, 12))) end)
            if decoded and type(envelope) == "table" and type(envelope.state) == "table" then
                local state = envelope.state
                local packed, payload = pcall(C.Pack, state)
                if packed and envelope.checksum == C.Hash(payload) and state.identity == D.Identity()
                    and type(state.fileSerial) == "number" and state.fileSerial >= 0 and state.fileSerial <= 1000000000000
                    and (state.peer == nil or (type(state.peer) == "string" and string.len(state.peer) <= 72))
                    and (state.role == "none" or state.role == "master" or state.role == "slave")
                    and (not state.snapshot or D.Validate(state.snapshot, state.meta))
                    and (not best or state.fileSerial > best.fileSerial) then best = state end
            end
        end
    end
    return best
end

function D.WriteFile(state)
    if not SUPERWOW_STRING or type(ExportFile) ~= "function" or type(ImportFile) ~= "function" then return false end
    local serial = (tonumber(state.fileSerial) or 0) + 1
    local copy = C.Copy(state)
    copy.fileSerial = serial
    -- The operation queue is recoverable from the complete snapshot. Keep file
    -- checkpoints bounded; live queued deltas remain in SavedVariables.
    copy.journal = {}
    local ok, text = pcall(function()
        local payload = C.Pack(copy)
        -- Printable ASCII also avoids Windows text-mode CRLF translation
        -- changing length-prefixed strings or the complete-state checksum.
        return "ADKP-SYNC1:" .. C.Escape(C.Pack({ state = copy, checksum = C.Hash(payload) }))
    end)
    if not ok then return false end
    local slot = math.mod(serial, 2)
    local written = pcall(ExportFile, fileName(slot), text)
    local read, actual = pcall(ImportFile, fileName(slot))
    if written and read and actual == text then state.fileSerial = serial; return true end
    return false
end
