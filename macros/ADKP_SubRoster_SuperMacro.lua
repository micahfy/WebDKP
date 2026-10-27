-- WoW 1.12 / Turtle WoW. Paste into SuperMacro's Extended Lua box.
-- Start with: /script ADKP_SubRosterMacro_Start("RecorderName")
if ADKP_SubRosterMacro_Stop then ADKP_SubRosterMacro_Stop(true) end
local R = {enabled = false}
local codes = {
    Warrior="战", WARRIOR="战", ["战士"]="战",
    Paladin="骑", PALADIN="骑", ["圣骑士"]="骑",
    Hunter="猎", HUNTER="猎", ["猎人"]="猎",
    Rogue="贼", ROGUE="贼", ["潜行者"]="贼", ["盗贼"]="贼",
    Priest="牧", PRIEST="牧", ["牧师"]="牧",
    Shaman="萨", SHAMAN="萨", ["萨满祭司"]="萨",
    Mage="法", MAGE="法", ["法师"]="法",
    Warlock="术", WARLOCK="术", ["术士"]="术",
    Druid="德", DRUID="德", ["德鲁伊"]="德",
}
local function say(s)
    DEFAULT_CHAT_FRAME:AddMessage("[替补名单宏] " .. s, 1, 0.82, 0)
end
local function trim(s)
    return string.gsub(string.gsub(s or "", "^%s+", ""), "%s+$", "")
end
local function snapshot()
    local members, seen = {}, {}
    local raid, party = GetNumRaidMembers(), GetNumPartyMembers()
    local expected = raid > 0 and raid or party + 1
    local function add(name, class, token)
        if not name or name == "" or seen[string.lower(name)] then return end
        seen[string.lower(name)] = true
        table.insert(members, {name = name, code = codes[class] or codes[token]})
    end
    if raid > 0 then
        for i = 1, raid do
            local name, _, _, _, class = GetRaidRosterInfo(i)
            add(name, class)
        end
    else
        for i = 1, party do
            local class, token = UnitClass("party" .. i)
            add(UnitName("party" .. i), class, token)
        end
        local class, token = UnitClass("player")
        add(UnitName("player"), class, token)
    end
    local after = GetNumRaidMembers()
    local expectedAfter = after > 0 and after or GetNumPartyMembers() + 1
    local count = table.getn(members)
    return members, expected, count, expected == expectedAfter and count == expectedAfter
        and ((raid > 0) == (after > 0))
end
local function packets(job, members, count)
    local prefix = job.to .. "#" .. job.from .. "#"
    local limit = 255 - string.len("AMB_TBFS") - 1 - string.len(prefix) - 4
    local result, batch = {}, ""
    for _, m in ipairs(members) do
        local entry = m.name .. (m.code and ":" .. m.code or "")
        if string.len(entry) > limit then return nil end
        if batch ~= "" and string.len(batch) + 1 + string.len(entry) > limit then
            table.insert(result, prefix .. "SUB:" .. batch)
            batch = ""
        end
        batch = batch == "" and entry or batch .. ";" .. entry
    end
    if batch ~= "" then table.insert(result, prefix .. "SUB:" .. batch) end
    table.insert(result, prefix .. "SUB_COMPLETE:" .. count)
    return result
end
local function finish()
    R.job = nil
    ADKP_SubRosterMacroFrame:SetScript("OnUpdate", nil)
end
local function tick()
    local job = R.job
    if not job then finish(); return end
    job.elapsed = job.elapsed + (tonumber(arg1) or 0)
    if job.elapsed < job.delay then return end
    job.elapsed = 0
    if not job.queue then
        local members, expected, count, stable = snapshot()
        job.attempt = job.attempt + 1
        if not stable and job.attempt < 3 then job.delay = 0.25; return end
        job.count = count
        if stable then
            job.queue = packets(job, members, count)
        else
            job.queue = {job.to .. "#" .. job.from .. "#SUB_ERROR:ROSTER_UNSTABLE:" .. count .. ":" .. expected}
            job.failed = true
        end
        if not job.queue then say("姓名过长，已停止回传。"); finish(); return end
        job.index = 1
    end
    local text = job.queue[job.index]
    if string.len("AMB_TBFS") + 1 + string.len(text) > 255 then
        say("消息过长，已停止回传。"); finish(); return
    end
    local ok, result = pcall(SendAddonMessage, "AMB_TBFS", text, "GUILD")
    if not ok or result == false then
        say("发送失败：" .. tostring(result)); finish(); return
    end
    job.index = job.index + 1
    job.delay = 0.15
    if job.index > table.getn(job.queue) then
        say(job.failed and "名单尚未完整，已通知记分员暂缓替补加分。"
            or "已向 " .. job.to .. " 回传名单（" .. job.count .. "人，含队长）。")
        finish()
    end
end
local function receive()
    if not R.enabled or event ~= "CHAT_MSG_ADDON" or arg1 ~= "AMB_TBQQ"
        or arg3 ~= "GUILD" or type(arg2) ~= "string" or type(arg4) ~= "string" then return end
    if string.lower(arg4) ~= string.lower(R.recorder) then return end
    local _, _, target = string.find(arg2, "^([^#]+)")
    local me = UnitName("player")
    if not me or string.lower(target or "") ~= string.lower(me) then return end
    if R.job or (R.last and GetTime() - R.last < 1) then return end
    R.last = GetTime()
    R.job = {to = arg4, from = me, attempt = 0, elapsed = 0, delay = 0}
    ADKP_SubRosterMacroFrame:SetScript("OnUpdate", tick)
end
function ADKP_SubRosterMacro_Stop(quiet)
    R.enabled = false; R.job = nil; R.last = nil
    if ADKP_SubRosterMacroFrame then
        ADKP_SubRosterMacroFrame:UnregisterAllEvents()
        ADKP_SubRosterMacroFrame:SetScript("OnEvent", nil)
        ADKP_SubRosterMacroFrame:SetScript("OnUpdate", nil)
        ADKP_SubRosterMacroFrame:Hide()
    end
    if not quiet then say("自动响应已关闭。") end
end
function ADKP_SubRosterMacro_Start(recorder)
    recorder = trim(recorder)
    if recorder == "" or recorder == "RecorderName" or recorder == "主记分员名字"
        or string.find(recorder, "[#|:;,\r\n]") then
        say("请把启动宏中的名字改为主记分员的角色名。"); return false
    end
    if ADKP_SubSync_Installed then
        ADKP_SubRosterMacro_Stop(true)
        say("已安装 ADKP，请使用插件响应，避免重复发送。"); return false
    end
    if not GetGuildInfo("player") then say("需要与记分员同公会；入会后重新启动。"); return false end
    ADKP_SubRosterMacro_Stop(true)
    if not ADKP_SubRosterMacroFrame then ADKP_SubRosterMacroFrame = CreateFrame("Frame") end
    R.recorder = recorder; R.enabled = true
    ADKP_SubRosterMacroFrame:RegisterEvent("CHAT_MSG_ADDON")
    ADKP_SubRosterMacroFrame:SetScript("OnEvent", receive)
    ADKP_SubRosterMacroFrame:Show()
    say("已开启，只响应记分员：" .. recorder .. "。")
    return true
end
function ADKP_SubRosterMacro_Status()
    say(R.enabled and "运行中，记分员：" .. R.recorder or "尚未启动。")
end
