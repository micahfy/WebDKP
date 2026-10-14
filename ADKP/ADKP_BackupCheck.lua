-- Login confirmation around the existing CSV/log-merge recovery. Lua 5.0.
-- Load before ADKP.lua so initialization cannot overwrite recovery sources.
ADKP_BackupRecovery = { checking = true, started = false, finished = false, elapsed = 0 }
local R = ADKP_BackupRecovery

local function pausedStore(create)
    if not WebDKP_Options or not ADKP_BackupCharacterKey then return nil end
    local key = ADKP_BackupCharacterKey()
    local all = WebDKP_Options.BackupRecoveryPaused
    if type(all) ~= "table" then
        if not create then return nil end
        all = {}; WebDKP_Options.BackupRecoveryPaused = all
    end
    if type(all[key]) ~= "table" then
        if not create then return nil end
        all[key] = {}
    end
    return all[key]
end

function ADKP_IsAutoBackupPaused(tableid)
    local paused = pausedStore(false)
    return paused and paused[tableid or ADKP_GetTableid()] and true or false
end

function ADKP_UpdateBackupRecoveryStatus()
    if ADKP_SettingsAutoBackupLabel and ADKP_GetTableid then
        ADKP_SettingsAutoBackupLabel:SetText(ADKP_IsAutoBackupPaused() and "自动备份（已暂停）" or "自动备份")
    end
end

local function suspend(tableid)
    local paused = pausedStore(true)
    if paused then paused[tableid] = true end
    ADKP_UpdateBackupRecoveryStatus()
end

function ADKP_BackupRecoveryCanWrite(silent, tableid)
    if R.checking or R.pending then return false end
    return not silent or not ADKP_IsAutoBackupPaused(tableid)
end

-- A successful explicit restore, manual backup, or website import resolves
-- the pause. Automatic writes never clear a declined recovery themselves.
function ADKP_ResumeAutoBackup(tableid)
    tableid = tableid or ADKP_GetTableid()
    local paused = pausedStore(false)
    if paused then paused[tableid] = nil end
    if not R.pending or R.pending.TableId == tableid then
        R.pending = nil; R.checking = false; R.finished = true
        if StaticPopup_Hide then StaticPopup_Hide("ADKP_BACKUP_RECOVERY_CONFIRM") end
    end
    ADKP_UpdateBackupRecoveryStatus()
end

local function finish()
    R.pending = nil; R.checking = false; R.finished = true
    ADKP_UpdateBackupRecoveryStatus()
end

local function showConfirmation()
    if not StaticPopupDialogs then StaticPopupDialogs = {} end
    StaticPopupDialogs.ADKP_BACKUP_RECOVERY_CONFIRM = {
        text = "检测到DKP数据差异，是否恢复最新备份数据",
        button1 = "确认", button2 = "取消",
        timeout = 0, whileDead = true, hideOnEscape = true,
        OnAccept = function()
            local candidate = R.pending
            if not candidate then return end
            local ok, restored = pcall(ADKP_RestoreData, false, candidate)
            if not ok or not restored then
                suspend(candidate.TableId)
                if not ok then ADKP_Print("恢复失败，自动备份已暂停：" .. tostring(restored)) end
            end
            finish()
        end,
        OnCancel = function()
            local candidate = R.pending
            if not candidate then return end
            suspend(candidate.TableId)
            finish()
            ADKP_Print("已取消恢复，当前团队的自动备份已暂停；可以继续记分。")
        end
    }
    local shown = StaticPopup_Show and StaticPopup_Show("ADKP_BACKUP_RECOVERY_CONFIRM")
    if shown then R.shown = true end
end

local frame = CreateFrame("Frame", "ADKP_BackupCheckFrame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function()
    if event == "PLAYER_LOGIN" and not R.started then R.started = true; R.elapsed = 0 end
end)
frame:SetScript("OnUpdate", function()
    -- Keep the pause label accurate when the user switches DKP teams.
    if R.started and ADKP_GetTableid then
        local id = ADKP_GetTableid()
        if id ~= R.lastTableId then R.lastTableId = id; ADKP_UpdateBackupRecoveryStatus() end
    end
    if not R.started or R.finished then return end
    R.elapsed = R.elapsed + (tonumber(arg1) or 0)
    if R.elapsed < 1 then return end
    R.elapsed = 0
    if not UnitName("player") or not GetRealmName() then return end
    if R.pending then
        if not R.shown then showConfirmation() end
        return
    end
    local ok, candidate = pcall(ADKP_RestoreData, true)
    if not ok then
        suspend(ADKP_GetTableid())
        ADKP_Print("本地备份检查失败，自动备份已暂停：" .. tostring(candidate))
        finish()
    elseif candidate then
        R.pending = candidate
        showConfirmation()
    else finish() end
end)
