-- WoW 1.12 / Lua 5.0. Recognition, attempt state and award serialization.
-- No dependency on BigWigs or SuperWoW. Only one death-message channel is used.
local definitions, names, deathUnits, yellBosses = {}, {}, {}, {}
local R = { states = {}, queue = {}, elapsed = 0 }
ADKP_BossEncounterState = R

local function lower(value)
    return string.lower(value or "")
end

local function addNames(list, unit)
    if unit.en then table.insert(list, unit.en) end
    if unit.zh then table.insert(list, unit.zh) end
    for _, name in ipairs(unit.aliases or {}) do table.insert(list, name) end
end

function ADKP_BossSettingNames(boss, includeMembers)
    local result = {}
    addNames(result, boss)
    if includeMembers then
        for _, member in ipairs(boss.members or {}) do addNames(result, member) end
    end
    return result
end

for zoneKey, zone in pairs(ADKP_RaidBosses) do
    for _, boss in ipairs(zone.bosses) do
        boss.id = lower(boss.en)
        boss.zoneKey = zoneKey
        table.insert(definitions, boss)
        for _, name in ipairs(ADKP_BossSettingNames(boss, true)) do names[lower(name)] = boss end
        if boss.members then
            for index, member in ipairs(boss.members) do
                local aliases = {}; addNames(aliases, member)
                for _, name in ipairs(aliases) do deathUnits[lower(name)] = { boss = boss, member = index } end
            end
        elseif boss.rule == "yell" then
            table.insert(yellBosses, boss)
        else
            for _, name in ipairs(ADKP_BossSettingNames(boss)) do deathUnits[lower(name)] = { boss = boss } end
        end
    end
end

function ADKP_GetBossDefinition(name)
    return names[lower(name)]
end

function ADKP_BossDisplayName(boss)
    local locale = GetLocale and GetLocale() or "zhCN"
    if locale == "zhCN" or locale == "zhTW" then return boss.zh or boss.en end
    return boss.en or boss.zh
end

function ADKP_BossRule_OnEnter()
    local boss = this and this.bossRef
    if type(boss) ~= "table" then return end
    if not ADKP_BossRuleTooltip then
        ADKP_BossRuleTooltip = CreateFrame("GameTooltip", "ADKP_BossRuleTooltip", UIParent, "GameTooltipTemplate")
        if ADKP_BossRuleTooltip.SetClampedToScreen then ADKP_BossRuleTooltip:SetClampedToScreen(true) end
    end
    local tip = ADKP_BossRuleTooltip
    local chinese = ADKP_BossDisplayName(boss) == boss.zh
    tip:SetOwner(this, "ANCHOR_LEFT")
    tip:ClearLines()
    tip:SetText(ADKP_BossDisplayName(boss), 1, 1, 1)
    tip:AddLine(chinese and boss.en or boss.zh, 0.7, 0.7, 0.7, true)
    local descriptions = {
        any = chinese and "任一成员死亡，脱战后确认；整场只计一次。" or "Any member dies; confirm after combat, once per encounter.",
        all = chinese and "所有成员死亡并脱战后确认，击杀顺序不限。" or "All members must die; confirm after combat, in any kill order.",
        count = chinese and "完成以下死亡数量并脱战后确认。" or "Reach all required death counts, then leave combat.",
        yell = chinese and "匹配此首领的最终胜利喊话，脱战后确认。" or "Match this boss's victory yell, then leave combat.",
    }
    tip:AddLine(descriptions[boss.rule] or (chinese and "此首领死亡后，等待脱战确认。" or "Confirm this boss's death after leaving combat."), 1, 0.82, 0, true)
    tip:AddLine(chinese and "同场最多加分一次，采用最后满足条件的首领及其分值。" or "One award per battle, using the last qualifying boss and its points.", 1, 0.82, 0, true)
    for _, member in ipairs(boss.members or {}) do
        tip:AddLine(ADKP_BossDisplayName(member) .. ((member.count and " x" .. member.count) or ""), 0.85, 0.85, 0.85, true)
    end
    for i = 1, tip:NumLines() do
        local line = getglobal("ADKP_BossRuleTooltipTextLeft" .. i)
        if line then line:SetWidth(260); line:SetJustifyH("LEFT") end
    end
    tip:Show()
    tip:SetWidth(284)
end

function ADKP_BossRule_OnLeave()
    if ADKP_BossRuleTooltip then ADKP_BossRuleTooltip:Hide() end
end

-- One-time settings migration. A pre-existing group setting wins; otherwise
-- member values must agree. Conflicting values are retained for inspection.
function ADKP_MigrateBossEncounterSettings()
    local options = WebDKP_Options
    if not options or options.BossEncounterRulesVersion == 1 then return end
    local points = options.BossPoints or {}
    local enabled = options.EnabledRaidBosses or {}
    local defaults = options.BossPointsDefault or { raid = 1, sub = 1 }
    local updates = {}
    local function fieldValue(unit, field)
        for _, name in ipairs(ADKP_BossSettingNames(unit)) do
            local entry = points[lower(name)]
            if type(entry) == "table" and type(entry[field]) == "number" then return entry[field] end
        end
    end
    for _, boss in ipairs(definitions) do
        local entry, conflicts = {}, {}
        for _, field in ipairs({ "raid", "sub" }) do
            local value = fieldValue(boss, field)
            if value == nil and boss.members then
                local agreed, hasValue, conflict = nil, false, false
                local original = {}
                for _, member in ipairs(boss.members) do
                    local v = fieldValue(member, field)
                    if v ~= nil then hasValue = true; original[member.en] = v end
                    v = v or defaults[field] or 1
                    if agreed ~= nil and agreed ~= v then conflict = true end
                    agreed = v
                end
                if hasValue and not conflict then value = agreed end
                if hasValue and conflict then conflicts[field] = original end
            end
            entry[field] = value
        end
        local state = nil
        for _, name in ipairs(ADKP_BossSettingNames(boss, true)) do
            if enabled[lower(name)] == false then state = false; break end
            if enabled[lower(name)] == true then state = true end
        end
        table.insert(updates, { boss = boss, points = entry, enabled = state, conflicts = conflicts })
    end
    for _, update in ipairs(updates) do
        local boss = update.boss
        points[lower(boss.en)] = update.points
        points[lower(boss.zh)] = update.points
        if update.enabled ~= nil then
            enabled[lower(boss.en)] = update.enabled
            enabled[lower(boss.zh)] = update.enabled
        end
        if next(update.conflicts) then
            options.BossEncounterMergeConflicts = options.BossEncounterMergeConflicts or {}
            options.BossEncounterMergeConflicts[boss.id] = update.conflicts
            if ADKP_Print then
                ADKP_Print("Boss 名单合并：" .. boss.zh .. "的旧分值不一致，已使用统一默认分值，请在 Boss 名单重新设置。")
            end
        end
    end
    options.BossPoints = points
    options.EnabledRaidBosses = enabled
    options.BossEncounterRulesVersion = 1
end

-- UNITDIESOTHER supplies the exact client-language death format. The explicit
-- patterns also accept English messages on Chinese clients and vice versa.
function ADKP_BossEncounter_ExtractName(message)
    if type(message) ~= "string" then return nil end
    local pattern = UNITDIESOTHER
    if type(pattern) == "string" and string.find(pattern, "%s", 1, true) then
        pattern = string.gsub(pattern, "([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
        pattern = string.gsub(pattern, "%%%%s", "(.+)")
        local _, _, name = string.find(message, "^" .. pattern .. "$")
        if name then return name end
    end
    message = string.gsub(message, "%s+$", "")
    -- Lua patterns are byte based: Chinese punctuation cannot be placed in a
    -- one-character class. Strip complete punctuation strings before matching.
    for _, mark in ipairs({ "。", "！", "!", "." }) do
        if string.sub(message, -string.len(mark)) == mark then
            message = string.sub(message, 1, string.len(message) - string.len(mark))
            break
        end
    end
    local patterns = {
        "^(.+)死亡了$", "^(.+)被击败了$", "^(.+)被消灭了$",
        "^(.+)被击杀$", "^(.+)倒下了$", "^(.+) dies$",
        "^You have slain (.+)$", "^You killed (.+)$", "^(.+) is slain by .+$",
        "^你杀死了(.+)$", "^(.+)被你杀死了$",
        "^(.+)被.+干掉了$", "^(.+)被.+杀死了$",
    }
    for _, p in ipairs(patterns) do
        local _, _, name = string.find(message, p)
        if name then
            name = string.gsub(name, "^%s+", "")
            return string.gsub(name, "%s+$", "")
        end
    end
end

local function now()
    return GetTime()
end

local function teamId()
    return ADKP_GetTableid and ADKP_GetTableid() or 1
end

local function inGroup()
    return (GetNumRaidMembers() or 0) > 0 or (GetNumPartyMembers() or 0) > 0
end

function ADKP_BossEncounter_IsEnabled()
    return inGroup() and not (ADKP_IsAddonDisabled and ADKP_IsAddonDisabled())
        and not (WebDKP_Options and WebDKP_Options.BossDeathPopup == false)
end

local function isAllowed(boss, unitName)
    if not ADKP_BossEncounter_IsEnabled() then return false end
    if ADKP_IsBossEnabled and not ADKP_IsBossEnabled(boss.en) then return false end
    if ADKP_IsBossExcluded then
        if ADKP_IsBossExcluded(unitName) or ADKP_IsBossExcluded(boss.en) or ADKP_IsBossExcluded(boss.zh) then return false end
    end
    for _, excluded in ipairs((WebDKP_Options and WebDKP_Options.ExcludedBosses) or {}) do
        if names[lower(excluded)] == boss or lower(excluded) == lower(boss.en) then return false end
    end
    return true
end

local function zoneMatches(boss)
    local zone = ADKP_RaidBosses[boss.zoneKey]
    local accepted = { boss.zoneKey, zone.name_zh }
    for _, name in ipairs(zone.zoneAliases or {}) do table.insert(accepted, name) end
    local current = {}
    if GetRealZoneText then table.insert(current, GetRealZoneText() or "") end
    if GetZoneText then table.insert(current, GetZoneText() or "") end
    if GetSubZoneText then table.insert(current, GetSubZoneText() or "") end
    for _, name in ipairs(current) do
        for _, expected in ipairs(accepted) do if lower(name) == lower(expected) then return true end end
    end
    return false
end

local function stateFor(boss)
    local key = tostring(teamId()) .. ":" .. boss.id
    local state = R.states[key]
    if not state then
        state = { boss = boss, tableid = teamId(), counts = {}, key = key }
        R.states[key] = state
    end
    return state
end

local function enqueue(state)
    if state.queued then return end
    if not isAllowed(state.boss) then state.ready = nil; return end
    state.queued = true
    table.insert(R.queue, {
        bossName = ADKP_BossDisplayName(state.boss), bossId = state.boss.id,
        raid = state.raid, sub = state.sub, tableid = state.tableid,
        auto = state.auto,
    })
    R.awarded = true
end

local function completed(state)
    R.order = (R.order or 0) + 1
    state.order = R.order
    state.ready = true
    state.raid, state.sub = ADKP_GetBossAwardPoints(state.boss.en)
    state.auto = WebDKP_Options and WebDKP_Options.BossAutoAward and true or false
end

local function groupInCombat()
    if UnitAffectingCombat("player") then return true end
    local raid = GetNumRaidMembers() or 0
    local count = raid > 0 and raid or (GetNumPartyMembers() or 0)
    for i = 1, count do
        local unit = (raid > 0 and "raid" or "party") .. i
        if not UnitIsDeadOrGhost(unit) and UnitAffectingCombat(unit) then return true end
    end
    return false
end

local function settleBattle()
    if R.awarded then return end
    local last = nil
    for _, state in pairs(R.states) do
        if state.ready and not state.queued and state.tableid == teamId() and isAllowed(state.boss) then
            if not last or state.order > last.order then last = state end
        end
    end
    if last then enqueue(last) end
end

local function beginCombat()
    if R.idleAt then
        -- A new pull after the living group left combat. Queued award jobs have
        -- their own snapshots, so a new attempt needs no old counters or locks.
        -- Also flush a death received between the final OOC tick and this pull.
        settleBattle()
        R.states = {}
        R.awarded = nil
    end
    R.idleAt = nil
end

local function observeCombat()
    local fighting = groupInCombat()
    if fighting then beginCombat()
    else R.idleAt = R.idleAt or now() end
    return fighting
end

function ADKP_BossEncounter_Death(message)
    if not ADKP_BossEncounter_IsEnabled() then return end
    observeCombat()
    if R.awarded then return end
    local name = ADKP_BossEncounter_ExtractName(message)
    if not name then return end
    local match = deathUnits[lower(name)]
    local boss = match and match.boss
    if not boss then
        -- Built-in group titles and yell-only bosses cannot bypass their rules
        -- even if an old custom list happens to contain those same names.
        if names[lower(name)] then return end
        for _, custom in ipairs((WebDKP_Options and WebDKP_Options.BossPatterns) or {}) do
            if lower(custom) == lower(name) then boss = { id = "custom:" .. lower(custom), en = custom, zh = custom }; break end
        end
    end
    if not boss or not isAllowed(boss, name) then return end
    -- Counters for generic-named Majordomo adds must not consume trash elsewhere.
    if boss.rule == "count" and not zoneMatches(boss) then return end
    local state = stateFor(boss)
    if state.ready or state.queued then return end
    if not boss.members then completed(state); return end
    local index = match.member
    if boss.rule == "any" then completed(state); return end
    local required = boss.members[index].count or 1
    state.counts[index] = math.min(required, (state.counts[index] or 0) + 1)
    for i, member in ipairs(boss.members) do
        if (state.counts[i] or 0) < (member.count or 1) then return end
    end
    completed(state)
end

function ADKP_BossEncounter_Yell(message, speaker)
    observeCombat()
    if R.awarded then return end
    if type(message) ~= "string" or type(speaker) ~= "string" then return end
    for _, boss in ipairs(yellBosses) do
        if names[lower(speaker)] == boss and zoneMatches(boss) and isAllowed(boss, speaker) then
            for _, text in ipairs(boss.yells) do
                if string.find(message, text, 1, true) then
                    local state = stateFor(boss)
                    if not state.ready and not state.queued then completed(state) end
                    return
                end
            end
        end
    end
end

local function finishJob(job)
    if R.active ~= job then return end
    R.active = nil
    ADKP_BossAwardData.bossName = ""
    ADKP_BossAwardData.killedBoss = false
    if ADKP_BossKillAwardFrame then ADKP_BossKillAwardFrame:Hide() end
    -- The next popup opens on a later tick, so a double-click cannot confirm
    -- the next encounter before its new title/values have been seen.
    R.nextAt = now() + 0.2
end

function ADKP_BossEncounter_Submit(raid, sub)
    local job = R.active
    if not job or job.submitting then return end
    if job.tableid ~= teamId() then
        ADKP_Print("当前 DKP 团队已切换，请切回击杀时的团队后确认加分。")
        return
    end
    if not ADKP_BossEncounter_IsEnabled() then return end
    job.submitting = true
    if ADKP_BossKillAwardFrame then ADKP_BossKillAwardFrame:Hide() end
    local recordCtx = nil
    if job.auto then recordCtx = { boss = job.bossName, raid = raid, sub = sub } end
    ADKP_RunRaidAndSubAward(raid, sub, "击杀-" .. job.bossName, recordCtx, function(success)
        if R.active ~= job then return end
        if success == false then
            job.submitting = false
            job.auto = false
            job.contextWarned = nil
            ADKP_BossEncounter_Pump()
        else finishJob(job) end
    end, job.tableid)
end

function ADKP_BossEncounter_Pump()
    if R.pumping or UnitAffectingCombat("player") or not ADKP_BossEncounter_IsEnabled() then return end
    if R.nextAt and now() < R.nextAt then return end
    R.pumping = true
    if not R.active and table.getn(R.queue) > 0 then R.active = table.remove(R.queue, 1) end
    local job = R.active
    if job and not job.submitting then
        if job.tableid ~= teamId() then
            if not job.contextWarned then
                job.contextWarned = true
                ADKP_Print("有待处理的 Boss 击杀，请切回击杀时的 DKP 团队完成加分。")
            end
        else
            ADKP_BossAwardData.bossName = job.bossName
            ADKP_BossAwardData.killedBoss = true
            if job.auto then
                ADKP_Print("全自动加分：" .. job.bossName .. "（主团" .. tostring(job.raid) .. " 替补" .. tostring(job.sub) .. "）")
                ADKP_BossEncounter_Submit(job.raid, job.sub)
            elseif not ADKP_BossKillAwardFrame or not ADKP_BossKillAwardFrame:IsShown() then
                ADKP_ShowBossKillAwardFrame()
            end
        end
    end
    R.pumping = false
end

function ADKP_BossEncounter_PopupHidden()
    local job = R.active
    if job and not job.submitting then finishJob(job) end
end

function ADKP_BossEncounter_Update()
    local fighting = observeCombat()
    if not ADKP_BossEncounter_IsEnabled() then
        -- Do not award old pending kills when the feature is enabled again.
        R.queue = {}
        if R.active and not R.active.submitting then finishJob(R.active) end
        for key, state in pairs(R.states) do
            if not state.queued then R.states[key] = nil end
        end
        return
    end
    if not UnitAffectingCombat("player") then settleBattle() end
    -- An individual death/feign is not a wipe. Reset incomplete groups only
    -- after the whole living group has been out of combat for 3s. Keep the
    -- awarded latch until the next pull, including after dismissal or retry.
    if not fighting and now() - R.idleAt >= 3 then
        for key, state in pairs(R.states) do
            if not state.ready and not state.queued then
                R.states[key] = nil
            end
        end
    end
    ADKP_BossEncounter_Pump()
end

local frame = CreateFrame("Frame", "ADKP_BossEncounterFrame")
frame:RegisterEvent("CHAT_MSG_MONSTER_YELL")
frame:RegisterEvent("PLAYER_REGEN_DISABLED")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
frame:SetScript("OnEvent", function()
    if event == "CHAT_MSG_MONSTER_YELL" then ADKP_BossEncounter_Yell(arg1, arg2)
    elseif event == "PLAYER_REGEN_DISABLED" then
        beginCombat()
    elseif event == "PLAYER_REGEN_ENABLED" then
        if not groupInCombat() then R.idleAt = R.idleAt or now() end
    elseif event == "ZONE_CHANGED_NEW_AREA" then
        for key, state in pairs(R.states) do
            if state.boss.zoneKey and not zoneMatches(state.boss) and not state.ready then R.states[key] = nil end
        end
    end
end)
frame:SetScript("OnUpdate", function()
    R.elapsed = R.elapsed + (tonumber(arg1) or 0)
    if R.elapsed < 0.2 then return end
    R.elapsed = 0
    ADKP_BossEncounter_Update()
end)
