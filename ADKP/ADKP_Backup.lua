-- Team-scoped, self-contained SuperWoW backups. Lua 5.0; never execute files.
ADKP_Backup = { pending = {}, candidates = {}, retryAt = {}, ready = false }
local B, D, C = ADKP_Backup, ADKP_SyncData, ADKP_SyncCodec
local HEADER, OLD_HEADER, POINTER, CATALOG = "ADKP-BACKUP3:", "ADKP-BACKUP2:", "ADKP-POINTER2:", "ADKP-CATALOG2:"
local function say(text) if ADKP_Print then ADKP_Print("[本地备份] " .. text) end end
local function now() return GetTime and GetTime() or 0 end
local function team() return ADKP_GetTableid() end
local function capture(id)
    local s = D.State()
    -- Replica-local captain/invite settings intentionally differ from A.
    -- They must never turn a B backup into a new master-authored revision.
    if s.enabled and s.role == "slave" and s.tableid == id and D.Validate(s.snapshot, s.meta) then
        return C.Copy(s.snapshot)
    end
    return D.Capture(id)
end
local function store()
    if type(ADKP_BackupStore) ~= "table" then ADKP_BackupStore = {} end
    local identity = D.Identity()
    if type(ADKP_BackupStore[identity]) ~= "table" then ADKP_BackupStore[identity] = {} end
    return ADKP_BackupStore[identity]
end
local function entry(id)
    local all = store()
    if type(all[id]) ~= "table" then all[id] = {} end
    return all[id]
end
function B.IsSuspended(id) return entry(id or team()).suspended and true or false end
function B.IsChecking() return B.ready and not B.checked end
function B.Version(id) return entry(id).meta end
local function key(id)
    return string.gsub(C.Hash(D.Identity()), ":", "-") .. "-D" .. id
end
local function encode(header, payload)
    if header == HEADER then
        payload = C.Copy(payload)
        payload.schema = 3
        -- data is the only current full snapshot in this self-contained file.
        if payload.sync then
            payload.sync = D.CompactFileState(payload.sync)
            payload.sync.snapshot = nil
        end
    end
    local envelope = C.Pack({ payload = payload, checksum = C.Hash(C.Pack(payload)) })
    if header == HEADER then return header .. C.WireEncode(envelope) end
    return header .. C.Escape(envelope)
end
local function decode(text, header)
    if type(text) ~= "string" or string.len(text) > C.MAX_BYTES * 3 + 32
        or string.sub(text, 1, string.len(header)) ~= header then return nil end
    local ok, envelope = pcall(function()
        local body = string.sub(text, string.len(header) + 1)
        if header == HEADER then body = C.WireDecode(body) else body = C.Unescape(body) end
        return C.Unpack(body)
    end)
    if not ok or type(envelope) ~= "table" or type(envelope.payload) ~= "table" then return nil end
    local packed, hash = pcall(function() return C.Hash(C.Pack(envelope.payload)) end)
    if not packed or hash ~= envelope.checksum then return nil end
    return envelope.payload
end
local function read(file)
    if not SUPERWOW_STRING or type(ImportFile) ~= "function" then return nil end
    file = string.gsub(file, "%.txt$", "")
    local ok, text = pcall(ImportFile, file)
    if ok and text then return text end
    ok, text = pcall(ImportFile, file .. ".txt")
    if ok then return text end
end
local function finite(n) return type(n) == "number" and n == n and math.abs(n) < 1e308 end
function B.Valid(payload, id)
    if type(payload) ~= "table" or payload.schema ~= 2 or payload.identity ~= D.Identity()
        or not D.Validate(payload.data, payload.meta) or (id and payload.meta.tableid ~= id)
        or not finite(payload.serial) or payload.serial < 1 or payload.serial >= 1000000000000
        or payload.serial ~= math.floor(payload.serial) then return false end
    local data = payload.data
    for name, value in pairs(data.bases) do
        if type(name) ~= "string" or not finite(value) then return false end
    end
    for alt, main in pairs(data.groups) do
        if type(alt) ~= "string" or type(main) ~= "string" or alt == "" or main == ""
            or string.len(alt) > 72 or string.len(main) > 72 then return false end
    end
    for _, log in pairs(data.logs) do
        if not finite(log.points) or type(log.date) ~= "string" then return false end
        for name, player in pairs(log.awarded) do
            if type(name) ~= "string" or type(player) ~= "table" then return false end
        end
    end
    local sync = payload.sync
    if sync ~= nil then
        if type(sync) ~= "table" or sync.identity ~= D.Identity() or sync.tableid ~= payload.meta.tableid
            or not D.Equal(sync.meta, payload.meta) or type(sync.enabled) ~= "boolean"
            or (sync.role ~= "none" and sync.role ~= "master" and sync.role ~= "slave")
            or (sync.peer ~= nil and (type(sync.peer) ~= "string" or string.len(sync.peer) > 72)) then return false end
        if sync.pendingReset and (type(sync.baseline) ~= "table" or not D.Validate(sync.baseline.data, sync.baseline.meta)) then return false end
    end
    return true
end
function B.Decode(text, id)
    local payload = decode(text, HEADER)
    if payload then
        if payload.schema ~= 3 or (payload.sync ~= nil and
            (type(payload.sync) ~= "table" or payload.sync.snapshot ~= nil)) then return nil end
        payload.schema = 2
        if payload.sync then payload.sync.snapshot = C.Copy(payload.data) end
    else payload = decode(text, OLD_HEADER) end
    if B.Valid(payload, id) then return payload end
end
function B.ReadLatest(id)
    local best
    for slot = 0, 1 do
        local pointer = decode(read("P-" .. key(id) .. "-" .. slot), POINTER)
        if pointer and pointer.identity == D.Identity() and pointer.tableid == id
            and type(pointer.file) == "string" and string.find(pointer.file, "^D%-[%w%-]+$") then
            local payload = B.Decode(read(pointer.file), id)
            if payload and payload.serial == pointer.serial and D.Equal(payload.meta, pointer.meta)
                and (not best or payload.serial > best.serial) then
                payload.file = pointer.file; best = payload
            end
        end
    end
    return best
end
function B.ReadBest(id)
    local file, checkpoint = B.ReadLatest(id), D.ReadFiles()
    if checkpoint and checkpoint.snapshot and checkpoint.tableid == id
        and (not file or D.Compare(checkpoint.meta, file.meta) == 1) then
        return { schema = 2, identity = D.Identity(), serial = math.max(1, checkpoint.fileSerial or 1),
            data = checkpoint.snapshot, meta = checkpoint.meta, sync = checkpoint, checkpoint = true }
    end
    return file
end
local function readCatalog()
    local best
    for slot = 0, 1 do
        local data = decode(read("P-" .. key(0) .. "-TEAMS-" .. slot), CATALOG)
        if data and data.identity == D.Identity() and type(data.ids) == "table"
            and finite(data.serial) and data.serial >= 1 and data.serial < 1000000000000
            and (not best or data.serial > best.serial) then best = data end
    end
    return best
end
local function writeVerified(file, text)
    local ok = pcall(ExportFile, file, text)
    return ok and read(file) == text
end
local function makeMeta(data, id, reset)
    local old = entry(id).meta
    local s = D.State()
    local hash = C.Hash(C.Pack(data))
    if not reset and s.tableid == id and D.ValidMeta(s.meta) and s.meta.hash == hash then return C.Copy(s.meta) end
    local today = date("%Y-%m-%d")
    if old and today < old.day then error("本机日期早于备份版本") end
    local seed = string.gsub(C.Hash(D.Identity() .. ":" .. id .. ":" .. time() .. ":" .. now()), ":", "-")
    return { master = UnitName("player"), realm = GetRealmName(), tableid = id, name = data.definition.name,
        team = old and old.team or seed, reset = reset and seed or (old and old.reset or seed),
        day = today, seq = old and old.day == today and old.seq + 1 or 1, hash = hash }
end
function B.Record(data, meta, reset)
    local id, e = meta.tableid, entry(meta.tableid)
    if reset then
        e.suspended = nil; B.candidates[id] = nil
        B.retryAt[id] = nil
        B.checked = true
    end
    if e.suspended then return end
    e.meta = C.Copy(meta)
    B.pending[id] = true
end
function B.Decline(id)
    entry(id or team()).suspended = true
    if B.initialCandidate and B.initialCandidate.meta.tableid == id then entry(team()).suspended = true end
    B.pending[id or team()] = nil
    say("已取消恢复，可继续记分；自动备份和数据同步发布已暂停。")
end
function B.Complete(id, meta)
    local e = entry(id)
    e.suspended, e.meta, e.backedHash = nil, C.Copy(meta), meta.hash
    B.candidates[id], B.pending[id] = nil, nil
    B.retryAt[id] = nil
    B.checked = true
    B.settingsHash = D.SettingsHash()
    -- Shared scoring settings can change on restore. Reconcile the other
    -- teams' live fingerprints without creating recovery-generated files.
    for other, saved in pairs(store()) do
        if other ~= id and type(other) == "number" and saved.meta and not saved.suspended then
            local ok, newMeta = pcall(function()
                local data = capture(other)
                if C.Hash(C.Pack(data)) ~= saved.meta.hash then return makeMeta(data, other, false) end
            end)
            if ok and newMeta then saved.meta, saved.backedHash = newMeta, newMeta.hash end
        end
    end
    if B.initialCandidate and B.initialCandidate.meta.tableid == id then
        entry(B.initialSelection).suspended = nil
        B.initialCandidate = nil
    end
end
function B.CheckFinished() B.checked = true end
function B.Candidate(id)
    return B.candidates[id or team()] or (not id and team() == B.initialSelection and B.initialCandidate)
end
function B.Initialize()
    if B.ready then return end
    B.ready, B.checked = true, false
    local ids = { [team()] = true }
    local catalog = readCatalog()
    for id in pairs(catalog and catalog.ids or {}) do
        if type(id) == "number" and id >= 1 and id <= 1000000 and id == math.floor(id) then ids[id] = true end
    end
    local checkpoint = D.ReadFiles()
    if checkpoint and checkpoint.tableid then ids[checkpoint.tableid] = true end
    for _, definition in pairs(WebDKP_Tables or {}) do
        if type(definition) == "table" and type(definition.id) == "number" then ids[definition.id] = true end
    end
    for id in pairs(store()) do if type(id) == "number" then ids[id] = true end end
    for id in pairs(ids) do
        local file = B.ReadBest(id)
        if file then
            local e = entry(id)
            local ok, data = pcall(capture, id)
            local hashed, hash = pcall(function() return C.Hash(C.Pack(data)) end)
            local order = e.meta and D.Compare(file.meta, e.meta)
            local healthy = ok and hashed and ((e.meta and hash == e.meta.hash and order ~= 1)
                or (not e.meta and hash == file.meta.hash))
            if healthy and not e.suspended then
                if not e.meta then e.meta = C.Copy(file.meta) end
                e.backedHash = file.meta.hash
            else
                e.suspended = true; B.candidates[id] = file
            end
        end
    end
    -- A crash can also erase the list of DKP teams and selected team id.
    local id = catalog and catalog.current
    if id and id ~= team() and B.candidates[id] and not entry(team()).meta then
        local ok, current = pcall(D.Capture, team())
        if ok and next(current.players) == nil and next(current.logs) == nil then
            B.initialCandidate, B.initialSelection = B.candidates[id], team()
        end
    end
end
function ADKP_BackupData(silent, targetId)
    local id = targetId or team()
    local e = entry(id)
    if not SUPERWOW_STRING or type(ExportFile) ~= "function" or type(ImportFile) ~= "function" then
        if not silent then say("备份需要 SuperWoW 的文件读写功能。") end
        return false
    end
    if not B.ready or B.IsChecking() or e.suspended then
        if not silent then say("正在检查恢复或记录存在异常，暂不更新备份。") end
        return false
    end
    local R = ADKP_DataSync
    if R and (R.applying or R.depth > 0 or R.blocked or R.activePrompt) then B.pending[id] = true; return false end
    local ok, data, meta, payload, text = pcall(function()
        local data = capture(id)
        local hash = C.Hash(C.Pack(data))
        local meta = e.meta and e.meta.hash == hash and C.Copy(e.meta) or makeMeta(data, id, false)
        local serial = math.max(tonumber(e.serial) or 0, (B.ReadLatest(id) or {}).serial or 0) + 1
        local sync = D.State()
        local savedSync = sync.tableid == id and D.Equal(sync.meta, meta) and C.Copy(sync) or nil
        if savedSync then savedSync.journal = {} end
        local payload = { schema = 2, identity = D.Identity(), serial = serial, data = data, meta = meta, sync = savedSync }
        assert(B.Valid(payload, id), "完整备份校验失败")
        return data, meta, payload, encode(HEADER, payload)
    end)
    if not ok then say("备份失败，旧备份保留：" .. tostring(data)); return false end
    local file = "D-" .. key(id) .. "-" .. meta.day .. "-" .. meta.seq .. "-" .. payload.serial
    if not writeVerified(file, text) or not B.Decode(read(file), id) then say("备份写入校验失败，旧备份保留。"); return false end
    local catalog = readCatalog() or { identity = D.Identity(), serial = 0, ids = {} }
    catalog.serial, catalog.ids[id] = catalog.serial + 1, true
    if id == team() or not catalog.current then catalog.current = id end
    local encodedCatalog, catalogText = pcall(encode, CATALOG, catalog)
    if not encodedCatalog or not writeVerified("P-" .. key(0) .. "-TEAMS-" .. math.mod(catalog.serial, 2), catalogText) then
        say("团队备份索引写入失败，旧备份保留。"); return false
    end
    local pointer = { identity = D.Identity(), tableid = id, file = file, meta = meta, serial = payload.serial }
    local encoded, pointerText = pcall(encode, POINTER, pointer)
    if not encoded or not writeVerified("P-" .. key(id) .. "-" .. math.mod(payload.serial, 2), pointerText) then
        say("备份指针写入失败，旧备份仍可恢复。"); return false
    end
    e.serial, e.meta, e.backedHash = payload.serial, C.Copy(meta), meta.hash
    B.retryAt[id] = nil
    B.pending[id] = nil
    if not silent then say("数据已完整备份到：" .. file)
    elseif not B.lastNotice or now() - B.lastNotice >= 600 then
        B.lastNotice = now(); say("数据发生变动，已自动备份。")
    end
    return true
end
function B.Apply(payload)
    local automaticTarget = B.initialCandidate == payload and team() == B.initialSelection
    if not B.Valid(payload, automaticTarget and payload.meta.tableid or team()) then
        say("备份不完整、校验失败或团队不匹配，原数据保留。"); return false
    end
    if ADKP_DataSyncRestoreLocal then return ADKP_DataSyncRestoreLocal(payload) end
    return false
end
function ADKP_RestoreData()
    local payload = B.ReadBest(team())
    if not payload then say("未找到当前团队有效的新版完整备份。"); return false end
    return B.Apply(payload)
end
function ADKP_RestoreFromData(text)
    local payload = B.Decode(text, team())
    if not payload then say("仅支持新版完整备份，原数据未改变。"); return false end
    return B.Apply(payload)
end
function ADKP_ImportSpecificVersion(file)
    if type(file) ~= "string" or file == "" then say("请输入版本文件名。"); return false end
    local text = read(file)
    local pointer = decode(text, POINTER)
    if pointer and pointer.identity == D.Identity() and pointer.tableid == team() and type(pointer.file) == "string" then
        local payload = B.Decode(read(pointer.file), team())
        if payload and payload.serial == pointer.serial and D.Equal(payload.meta, pointer.meta) then return B.Apply(payload) end
    end
    return ADKP_RestoreFromData(text)
end
function ADKP_RequestImportVersion()
    local edit = ADKP_LootListImportEditBox
    local file = edit and string.gsub(edit:GetText() or "", "^%s*(.-)%s*$", "%1") or ""
    if file == "" then say("请先输入要导入的版本文件名。"); return end
    local id = team()
    StaticPopupDialogs.ADKP_IMPORT_VERSION_CONFIRM = {
        text = "%s", button1 = "确定", button2 = "取消", timeout = 0, whileDead = 1, hideOnEscape = 1,
        OnAccept = function()
            if team() ~= id then say("当前团队已改变，请重新选择备份。"); return end
            ADKP_ImportSpecificVersion(file)
        end
    }
    StaticPopup_Show("ADKP_IMPORT_VERSION_CONFIRM", "确定从版本 [" .. file .. "] 恢复吗？\n将完整替换当前团队业务数据并恢复记分设置。")
end
local originalSave = ADKP_SaveToDisk
local function hasTeam(id)
    for _, definition in pairs(WebDKP_Tables or {}) do
        if type(definition) == "table" and definition.id == id then return true end
    end
    return false
end
local function scheduleAll()
    B.pending[team()] = true
    for id, saved in pairs(store()) do
        if type(id) == "number" and saved.meta and hasTeam(id) then B.pending[id] = true end
    end
end
ADKP_SaveToDisk = function(skip)
    if originalSave then originalSave(true) end
    local R = ADKP_DataSync
    if not skip and not (R and (R.applying or R.refreshing)) then scheduleAll() end
end
function B.Tick()
    if not B.ready or not B.checked then return end
    local R = ADKP_DataSync
    if R and (R.applying or R.refreshing or R.depth > 0 or R.blocked or R.activePrompt) then return end
    if not B.settingsPoll or now() >= B.settingsPoll then
        B.settingsPoll = now() + 1
        local hash = D.SettingsHash()
        if B.settingsHash and hash ~= B.settingsHash then scheduleAll() end
        B.settingsHash = hash
    end
    for _, id in ipairs(C.Keys(B.pending)) do
      local e = entry(id)
      if not hasTeam(id) then B.pending[id] = nil
      elseif not e.suspended then
        local ok, meta = pcall(function()
            local data = capture(id)
            if e.meta and C.Hash(C.Pack(data)) == e.meta.hash then return e.meta end
            return makeMeta(data, id, false)
        end)
        if not ok then say("记录版本检查失败，旧备份保留：" .. tostring(meta)); B.pending[id] = nil; return end
        e.meta = C.Copy(meta)
        if WebDKP_Options and WebDKP_Options.AutoBackupEnabled and e.backedHash ~= meta.hash then
            if not B.retryAt[id] or now() >= B.retryAt[id] then
                if not ADKP_BackupData(true, id) then B.retryAt[id] = now() + 10 end
            end
        else B.pending[id] = nil end
      end
    end
end
