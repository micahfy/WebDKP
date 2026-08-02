-- Main/alt sharing for ADKP.
-- The website remains authoritative. Shared balances here are raid-session
-- projections; exported activity logs keep the original character names.

local OriginalAddDKP = ADKP_AddDKP
local OriginalGetDKP = ADKP_GetDKP
local OriginalBuildBackupCSV = ADKP_BuildBackupCSV
local OriginalBuildExportText = ADKP_BuildExportText
local OriginalRestoreFromData = ADKP_RestoreFromData

local function currentTableId()
    if ADKP_GetTableid then return ADKP_GetTableid() end
    return 1
end

local function initializeStorage()
    if not ADKP_ShareGroups then ADKP_ShareGroups = {} end
    if not ADKP_ShareProposals then ADKP_ShareProposals = {} end
    if not ADKP_ShareSessionBase then ADKP_ShareSessionBase = {} end
end

local function teamStorage(tableid)
    initializeStorage()
    if not ADKP_ShareGroups[tableid] then ADKP_ShareGroups[tableid] = {} end
    if not ADKP_ShareProposals[tableid] then ADKP_ShareProposals[tableid] = {} end
    if not ADKP_ShareSessionBase[tableid] then ADKP_ShareSessionBase[tableid] = {} end
    return ADKP_ShareGroups[tableid], ADKP_ShareProposals[tableid], ADKP_ShareSessionBase[tableid]
end

local function trim(value)
    value = tostring(value or "")
    value = string.gsub(value, "^%s+", "")
    value = string.gsub(value, "%s+$", "")
    return value
end

local function splitCsv(line)
    local fields = {}
    local startAt = 1
    while true do
        local commaAt = string.find(line, ",", startAt)
        if not commaAt then
            table.insert(fields, trim(string.sub(line, startAt)))
            break
        end
        table.insert(fields, trim(string.sub(line, startAt, commaAt - 1)))
        startAt = commaAt + 1
    end
    return fields
end

local function canonicalPlayerName(name)
    name = trim(name)
    if name == "" then return nil end
    if WebDKP_DkpTable and WebDKP_DkpTable[name] then return name end
    local wanted = string.lower(name)
    if WebDKP_DkpTable then
        for playerName, value in pairs(WebDKP_DkpTable) do
            if type(value) == "table" and string.lower(playerName) == wanted then
                return playerName
            end
        end
    end
    return name
end

function ADKP_Share_GetMain(playerName, tableid)
    tableid = tableid or currentTableId()
    local groups = teamStorage(tableid)
    local canonical = canonicalPlayerName(playerName)
    if not canonical then return nil end
    if groups[canonical] then return groups[canonical] end
    local wanted = string.lower(canonical)
    for altName, mainName in pairs(groups) do
        if string.lower(altName) == wanted then return mainName end
    end
    return canonical
end

local function membersForMain(mainName, tableid)
    local groups = teamStorage(tableid)
    local members = { mainName }
    for altName, candidateMain in pairs(groups) do
        if candidateMain == mainName then table.insert(members, altName) end
    end
    return members
end

local function mainHasAlts(mainName, tableid)
    local groups = teamStorage(tableid)
    for _, candidateMain in pairs(groups) do
        if candidateMain == mainName then return true end
    end
    return false
end

local function entryContainsMain(entry, mainName, tableid)
    if not entry or type(entry.awarded) ~= "table" then return false end
    for playerName, _ in pairs(entry.awarded) do
        if ADKP_Share_GetMain(playerName, tableid) == mainName then return true end
    end
    return false
end

local function normalizeAwardReason(reason)
    reason = trim(reason)
    local suffix = "-替补"
    if string.len(reason) >= string.len(suffix)
        and string.sub(reason, -string.len(suffix)) == suffix then
        return trim(string.sub(reason, 1, string.len(reason) - string.len(suffix)))
    end
    return reason
end

local function sessionBase(mainName, tableid)
    local _, _, bases = teamStorage(tableid)
    if bases[mainName] ~= nil then return tonumber(bases[mainName]) or 0 end
    if WebDKP_DkpTable and WebDKP_DkpTable[mainName] then
        return tonumber(WebDKP_DkpTable[mainName]["dkp_" .. tableid]) or 0
    end
    return 0
end

function ADKP_Share_RecalculateGroup(mainName, tableid)
    tableid = tableid or currentTableId()
    mainName = ADKP_Share_GetMain(mainName, tableid)
    if not mainName or not mainHasAlts(mainName, tableid) then return nil end

    local total = sessionBase(mainName, tableid)
    local positiveAwards = {}
    if WebDKP_Log then
        for logKey, entry in pairs(WebDKP_Log) do
            if logKey ~= "Version" and type(entry) == "table" and entry.awarded then
                local entryTable = entry.tableid or 1
                if entryTable == tableid and entryContainsMain(entry, mainName, tableid) then
                    local points = tonumber(entry.points) or 0
                    if points > 0 then
                        local eventKey = tostring(entry.date or "") .. "\001" .. normalizeAwardReason(entry.reason)
                        if positiveAwards[eventKey] == nil or points > positiveAwards[eventKey] then
                            positiveAwards[eventKey] = points
                        end
                    else
                        total = total + points
                    end
                end
            end
        end
    end
    for _, points in pairs(positiveAwards) do total = total + points end
    if ADKP_ROUND then total = ADKP_ROUND(total, 2) end

    local members = membersForMain(mainName, tableid)
    for i = 1, table.getn(members) do
        local playerName = members[i]
        if WebDKP_DkpTable and WebDKP_DkpTable[playerName] then
            WebDKP_DkpTable[playerName]["dkp_" .. tableid] = total
        end
    end
    return total
end

local function recalculateIndependent(playerName, tableid)
    local _, _, bases = teamStorage(tableid)
    local total = tonumber(bases[playerName]) or 0
    if WebDKP_Log then
        for logKey, entry in pairs(WebDKP_Log) do
            if logKey ~= "Version" and type(entry) == "table" and entry.awarded then
                local entryTable = entry.tableid or 1
                if entryTable == tableid and entry.awarded[playerName] then
                    total = total + (tonumber(entry.points) or 0)
                end
            end
        end
    end
    if ADKP_ROUND then total = ADKP_ROUND(total, 2) end
    if WebDKP_DkpTable and WebDKP_DkpTable[playerName] then
        WebDKP_DkpTable[playerName]["dkp_" .. tableid] = total
    end
end

function ADKP_Share_ApplyWebsiteList(text)
    local tableid = currentTableId()
    initializeStorage()
    ADKP_ShareGroups[tableid] = {}
    ADKP_ShareProposals[tableid] = {}
    ADKP_ShareSessionBase[tableid] = {}
    local groups, _, bases = teamStorage(tableid)

    for line in string.gfind(text or "", "[^\r\n]+") do
        local fields = splitCsv(trim(line))
        local name = canonicalPlayerName(fields[1])
        if name and name ~= "" then
            bases[name] = tonumber(fields[3]) or 0
            local mainName = canonicalPlayerName(fields[4])
            if mainName and mainName ~= "" and mainName ~= "-" and mainName ~= name then
                groups[name] = mainName
            end
        end
    end

    local recalculated = {}
    for _, mainName in pairs(groups) do
        if not recalculated[mainName] then
            ADKP_Share_RecalculateGroup(mainName, tableid)
            recalculated[mainName] = true
        end
    end
end

function ADKP_Share_Bind(mainName, altName)
    local tableid = currentTableId()
    local groups, proposals, bases = teamStorage(tableid)
    mainName = ADKP_Share_GetMain(canonicalPlayerName(mainName), tableid)
    altName = canonicalPlayerName(altName)
    if not mainName or not altName or mainName == altName then
        ADKP_Print("大小号绑定失败：请输入不同的主号和小号。")
        return false
    end
    if groups[altName] or mainHasAlts(altName, tableid) then
        ADKP_Print("大小号绑定失败：小号已经属于其他共享组。")
        return false
    end
    if not WebDKP_DkpTable or not WebDKP_DkpTable[mainName] then
        ADKP_Print("大小号绑定失败：主号不在当前 DKP 清单中。")
        return false
    end
    if not WebDKP_DkpTable[altName] then
        WebDKP_DkpTable[altName] = {
            ["dkp_" .. tableid] = 0,
            ["class"] = ADKP_GetPlayerClass and ADKP_GetPlayerClass(altName) or "未知",
        }
    end
    if bases[altName] == nil then bases[altName] = 0 end
    if (tonumber(bases[altName]) or 0) ~= 0 then
        ADKP_Print("大小号绑定失败：该角色的网站期初分不为 0，请在网站确认绑定。")
        return false
    end

    groups[altName] = mainName
    proposals[altName] = {
        main = mainName,
        class = WebDKP_DkpTable[altName]["class"] or "未知",
    }
    ADKP_Share_RecalculateGroup(mainName, tableid)
    if ADKP_SaveToDisk then ADKP_SaveToDisk() end
    if ADKP_UpdateTableToShow then ADKP_UpdateTableToShow() end
    if ADKP_UpdateTable then ADKP_UpdateTable() end
    ADKP_Print("已临时绑定 " .. altName .. " -> " .. mainName .. "，活动结束后请在网站确认。")
    return true
end

function ADKP_Share_CancelProposal(altName)
    local tableid = currentTableId()
    local groups, proposals = teamStorage(tableid)
    altName = canonicalPlayerName(altName)
    local proposal = altName and proposals[altName]
    if not proposal then
        ADKP_Print("只能取消本次活动中新建、尚未上传的临时绑定。")
        return false
    end
    local mainName = proposal.main
    groups[altName] = nil
    proposals[altName] = nil
    if mainHasAlts(mainName, tableid) then
        ADKP_Share_RecalculateGroup(mainName, tableid)
    else
        recalculateIndependent(mainName, tableid)
    end
    recalculateIndependent(altName, tableid)
    if ADKP_SaveToDisk then ADKP_SaveToDisk() end
    if ADKP_UpdateTableToShow then ADKP_UpdateTableToShow() end
    if ADKP_UpdateTable then ADKP_UpdateTable() end
    ADKP_Print("已取消临时绑定：" .. altName)
    return true
end

if OriginalAddDKP then
    function ADKP_AddDKP(points, reason, forItem, players, ignoredTableId, awardDate)
        OriginalAddDKP(points, reason, forItem, players, ignoredTableId, awardDate)
        local tableid = currentTableId()
        local affected = {}
        if players then
            for _, player in pairs(players) do
                if type(player) == "table" and player.name then
                    local mainName = ADKP_Share_GetMain(player.name, tableid)
                    if mainName and mainHasAlts(mainName, tableid) then affected[mainName] = true end
                end
            end
        end
        for mainName, _ in pairs(affected) do ADKP_Share_RecalculateGroup(mainName, tableid) end
    end
end

if OriginalGetDKP then
    function ADKP_GetDKP(playerName)
        local mainName = ADKP_Share_GetMain(playerName, currentTableId())
        if mainName then return OriginalGetDKP(mainName) end
        return OriginalGetDKP(playerName)
    end
end

local function metadataLines()
    local tableid = currentTableId()
    local groups, proposals, bases = teamStorage(tableid)
    local lines = {}
    for altName, mainName in pairs(groups) do
        local class = "未知"
        if WebDKP_DkpTable and WebDKP_DkpTable[altName] then
            class = WebDKP_DkpTable[altName]["class"] or class
        end
        table.insert(lines, "#ADKP_SHARE," .. mainName .. "," .. altName .. "," .. class)
        if proposals[altName] then
            table.insert(lines, "#ADKP_SHARE_PROPOSAL," .. mainName .. "," .. altName .. "," .. class)
        end
    end
    for playerName, value in pairs(bases) do
        table.insert(lines, "#ADKP_SHARE_BASE," .. playerName .. "," .. tostring(value))
    end
    table.sort(lines)
    return lines
end

local function appendMetadata(text)
    local lines = metadataLines()
    if table.getn(lines) == 0 then return text end
    if text and text ~= "" then return text .. "\n" .. table.concat(lines, "\n") end
    return table.concat(lines, "\n")
end

if OriginalBuildBackupCSV then
    function ADKP_BuildBackupCSV(includeHeader)
        return appendMetadata(OriginalBuildBackupCSV(includeHeader))
    end
end

if OriginalBuildExportText then
    function ADKP_BuildExportText()
        return appendMetadata(OriginalBuildExportText())
    end
end

local function restoreMetadata(text)
    local tableid = currentTableId()
    local groups, proposals, bases = teamStorage(tableid)
    for line in string.gfind(text or "", "[^\r\n]+") do
        local fields = splitCsv(trim(line))
        if fields[1] == "#ADKP_SHARE" and fields[2] and fields[3] then
            local mainName = canonicalPlayerName(fields[2])
            local altName = canonicalPlayerName(fields[3])
            if mainName and altName and mainName ~= altName then groups[altName] = mainName end
        elseif fields[1] == "#ADKP_SHARE_PROPOSAL" and fields[2] and fields[3] then
            local mainName = canonicalPlayerName(fields[2])
            local altName = canonicalPlayerName(fields[3])
            if mainName and altName and mainName ~= altName then
                proposals[altName] = { main = mainName, class = fields[4] or "未知" }
            end
        elseif fields[1] == "#ADKP_SHARE_BASE" and fields[2] then
            local playerName = canonicalPlayerName(fields[2])
            if playerName then bases[playerName] = tonumber(fields[3]) or 0 end
        end
    end
    local recalculated = {}
    for _, mainName in pairs(groups) do
        if not recalculated[mainName] then
            ADKP_Share_RecalculateGroup(mainName, tableid)
            recalculated[mainName] = true
        end
    end
end

if OriginalRestoreFromData then
    function ADKP_RestoreFromData(importData, dataFileName)
        OriginalRestoreFromData(importData, dataFileName)
        restoreMetadata(importData)
    end
end

local function refreshManager()
    local frame = ADKP_ShareManagerFrame
    if not frame then return end
    local tableid = currentTableId()
    local _, proposals = teamStorage(tableid)
    local focusName = canonicalPlayerName(frame.focusName)
    local mainName = ADKP_Share_GetMain(focusName, tableid)
    local lines = {}
    if mainName and mainHasAlts(mainName, tableid) then
        local members = membersForMain(mainName, tableid)
        for i = 1, table.getn(members) do
            local name = members[i]
            local suffix = "（小号）"
            if name == mainName then suffix = "（主号）" end
            if proposals[name] then suffix = "（小号，待网站确认）" end
            table.insert(lines, name .. suffix)
        end
    end
    if table.getn(lines) == 0 then table.insert(lines, "当前角色尚未建立大小号组") end
    frame.summary:SetText(table.concat(lines, "\n"))
end

function ADKP_Share_ShowManager(playerName)
    if not ADKP_ShareManagerFrame then
        local frame = CreateFrame("Frame", "ADKP_ShareManagerFrame", UIParent)
        frame:SetWidth(390)
        frame:SetHeight(270)
        frame:SetPoint("CENTER", 0, 0)
        frame:SetFrameStrata("DIALOG")
        frame:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", tile = true, tileSize = 32, edgeSize = 32, insets = { left = 11, right = 12, top = 12, bottom = 11 } })
        frame:EnableMouse(true)
        frame:SetMovable(true)
        frame:RegisterForDrag("LeftButton")
        frame:SetScript("OnDragStart", function() this:StartMoving() end)
        frame:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)

        local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOP", 0, -18)
        title:SetText("大小号管理")

        frame.summary = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        frame.summary:SetPoint("TOPLEFT", 28, -48)
        frame.summary:SetWidth(330)
        frame.summary:SetJustifyH("LEFT")

        local mainLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        mainLabel:SetPoint("TOPLEFT", 28, -125)
        mainLabel:SetText("主号")
        frame.mainEdit = CreateFrame("EditBox", "ADKP_ShareMainEdit", frame, "InputBoxTemplate")
        frame.mainEdit:SetWidth(120)
        frame.mainEdit:SetHeight(22)
        frame.mainEdit:SetPoint("LEFT", mainLabel, "RIGHT", 12, 0)
        frame.mainEdit:SetAutoFocus(false)

        local altLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        altLabel:SetPoint("LEFT", frame.mainEdit, "RIGHT", 18, 0)
        altLabel:SetText("小号")
        frame.altEdit = CreateFrame("EditBox", "ADKP_ShareAltEdit", frame, "InputBoxTemplate")
        frame.altEdit:SetWidth(120)
        frame.altEdit:SetHeight(22)
        frame.altEdit:SetPoint("LEFT", altLabel, "RIGHT", 12, 0)
        frame.altEdit:SetAutoFocus(false)

        local bindButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        bindButton:SetWidth(105)
        bindButton:SetHeight(24)
        bindButton:SetPoint("BOTTOMLEFT", 28, 28)
        bindButton:SetText("临时绑定")
        bindButton:SetScript("OnClick", function()
            if ADKP_Share_Bind(frame.mainEdit:GetText(), frame.altEdit:GetText()) then refreshManager() end
        end)

        local cancelButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        cancelButton:SetWidth(120)
        cancelButton:SetHeight(24)
        cancelButton:SetPoint("LEFT", bindButton, "RIGHT", 8, 0)
        cancelButton:SetText("取消临时绑定")
        cancelButton:SetScript("OnClick", function()
            if ADKP_Share_CancelProposal(frame.altEdit:GetText()) then refreshManager() end
        end)

        local closeButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        closeButton:SetWidth(80)
        closeButton:SetHeight(24)
        closeButton:SetPoint("BOTTOMRIGHT", -28, 28)
        closeButton:SetText("关闭")
        closeButton:SetScript("OnClick", function() frame:Hide() end)
        ADKP_ShareManagerFrame = frame
    end

    local frame = ADKP_ShareManagerFrame
    frame.focusName = playerName
    local tableid = currentTableId()
    local canonical = canonicalPlayerName(playerName)
    local groups = teamStorage(tableid)
    local mainName = ADKP_Share_GetMain(canonical, tableid)
    if canonical and groups[canonical] then
        frame.mainEdit:SetText(mainName)
        frame.altEdit:SetText(canonical)
    elseif canonical and mainHasAlts(canonical, tableid) then
        frame.mainEdit:SetText(canonical)
        frame.altEdit:SetText("")
    elseif canonical then
        frame.mainEdit:SetText("")
        frame.altEdit:SetText(canonical)
    elseif mainName then
        frame.mainEdit:SetText(mainName)
        frame.altEdit:SetText("")
    else
        frame.mainEdit:SetText("")
        frame.altEdit:SetText(playerName or "")
    end
    refreshManager()
    frame:Show()
end

SLASH_ADKPSHARE1 = "/adkpshare"
SlashCmdList["ADKPSHARE"] = function(message)
    local _, _, mainName, altName = string.find(trim(message), "^(%S+)%s+(%S+)$")
    if mainName and altName then
        ADKP_Share_Bind(mainName, altName)
    else
        ADKP_Share_ShowManager(UnitName("target") or UnitName("player"))
    end
end

initializeStorage()
