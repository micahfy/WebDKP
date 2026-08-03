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
    local groups, proposals = teamStorage(tableid)
    local canonical = canonicalPlayerName(playerName)
    if not canonical then return nil end

    local current = canonical
    local visited = {}
    while current and not visited[current] do
        visited[current] = true
        local directMain = groups[current]
        if not directMain and proposals[current] then
            directMain = proposals[current].main
            groups[current] = directMain
        end
        if not directMain then
            local wanted = string.lower(current)
            for altName, mainName in pairs(groups) do
                if string.lower(altName) == wanted then
                    directMain = mainName
                    break
                end
            end
        end
        if not directMain then return current end
        current = canonicalPlayerName(directMain)
    end
    return current or canonical
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
    local groups, proposals, bases = teamStorage(tableid)
    local total
    if bases[mainName] ~= nil then
        total = tonumber(bases[mainName]) or 0
    elseif WebDKP_DkpTable and WebDKP_DkpTable[mainName] then
        total = tonumber(WebDKP_DkpTable[mainName]["dkp_" .. tableid]) or 0
    else
        total = 0
    end

    -- Website-bound alts already carry the shared balance and must not be
    -- counted again. Only independent bases added by plugin proposals merge in.
    for altName, candidateMain in pairs(groups) do
        if candidateMain == mainName and proposals[altName] then
            total = total + (tonumber(bases[altName]) or 0)
        end
    end
    return total
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
            WebDKP_DkpTable[playerName]["dkp_" .. tableid] = ADKP_ROUND(total, 2)
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
        WebDKP_DkpTable[playerName]["dkp_" .. tableid] = ADKP_ROUND(total, 2)
    end
end

local function initializeMissingBase(playerName, tableid, bases)
    if bases[playerName] ~= nil then return end
    local current = 0
    if WebDKP_DkpTable and WebDKP_DkpTable[playerName] then
        current = tonumber(WebDKP_DkpTable[playerName]["dkp_" .. tableid]) or 0
    end
    local logged = 0
    if WebDKP_Log then
        for logKey, entry in pairs(WebDKP_Log) do
            if logKey ~= "Version" and type(entry) == "table" and entry.awarded then
                local entryTable = entry.tableid or 1
                if entryTable == tableid and entry.awarded[playerName] then
                    logged = logged + (tonumber(entry.points) or 0)
                end
            end
        end
    end
    bases[playerName] = current - logged
    if ADKP_ROUND then bases[playerName] = ADKP_ROUND(bases[playerName], 2) end
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
    if ADKP_Share_UpdateTab then ADKP_Share_UpdateTab() end
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
        ADKP_Print("大小号绑定失败：组内角色不在当前 DKP 清单中。")
        return false
    end
    if not WebDKP_DkpTable[altName] then
        WebDKP_DkpTable[altName] = {
            ["dkp_" .. tableid] = 0,
            ["class"] = ADKP_GetPlayerClass and ADKP_GetPlayerClass(altName) or "未知",
        }
    end
    initializeMissingBase(mainName, tableid, bases)
    initializeMissingBase(altName, tableid, bases)

    groups[altName] = mainName
    proposals[altName] = {
        main = mainName,
        class = WebDKP_DkpTable[altName]["class"] or "未知",
    }
    ADKP_Share_RecalculateGroup(mainName, tableid)
    if ADKP_SaveToDisk then ADKP_SaveToDisk() end
    if ADKP_UpdateTableToShow then ADKP_UpdateTableToShow() end
    if ADKP_UpdateTable then ADKP_UpdateTable() end
    if ADKP_Share_UpdateTab then ADKP_Share_UpdateTab() end
    local mergedBase = tonumber(bases[altName]) or 0
    ADKP_Print("已临时绑定 " .. altName .. " -> " .. mainName .. "，合并期初分 " .. tostring(mergedBase) .. "，活动结束后请在网站确认。")
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
    if ADKP_Share_UpdateTab then ADKP_Share_UpdateTab() end
    ADKP_Print("已取消临时绑定：" .. altName)
    return true
end

if OriginalAddDKP then
    function ADKP_AddDKP(points, reason, forItem, players, ignoredTableId, awardDate)
        local result = OriginalAddDKP(points, reason, forItem, players, ignoredTableId, awardDate)
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
        local changed = false
        for mainName, _ in pairs(affected) do
            ADKP_Share_RecalculateGroup(mainName, tableid)
            changed = true
        end
        if changed then
            if ADKP_SaveToDisk then ADKP_SaveToDisk() end
            if ADKP_UpdateTableToShow then ADKP_UpdateTableToShow() end
            if ADKP_UpdateTable then ADKP_UpdateTable() end
            if ADKP_UpdateLootList then ADKP_UpdateLootList() end
            if ADKP_Share_UpdateTab then ADKP_Share_UpdateTab() end
        end
        return result
    end
end

if OriginalGetDKP then
    function ADKP_GetDKP(playerName)
        local mainName = ADKP_Share_GetMain(playerName, currentTableId())
        if mainName then return OriginalGetDKP(mainName) end
        return OriginalGetDKP(playerName)
    end
end

local function metadataLines(includeInternal)
    local tableid = currentTableId()
    local groups, proposals, bases = teamStorage(tableid)
    local lines = {}
    for altName, mainName in pairs(groups) do
        local class = "未知"
        if WebDKP_DkpTable and WebDKP_DkpTable[altName] then
            class = WebDKP_DkpTable[altName]["class"] or class
        end
        if includeInternal then
            table.insert(lines, "#ADKP_SHARE," .. mainName .. "," .. altName .. "," .. class)
        end
        if proposals[altName] then
            table.insert(lines, "#ADKP_SHARE_PROPOSAL," .. mainName .. "," .. altName .. "," .. class)
        end
    end
    if includeInternal then
        for playerName, value in pairs(bases) do
            table.insert(lines, "#ADKP_SHARE_BASE," .. playerName .. "," .. tostring(value))
        end
    end
    table.sort(lines)
    return lines
end

local function appendMetadata(text, includeInternal)
    local lines = metadataLines(includeInternal)
    if table.getn(lines) == 0 then return text end
    if text and text ~= "" then return text .. "\n" .. table.concat(lines, "\n") end
    return table.concat(lines, "\n")
end

if OriginalBuildBackupCSV then
    function ADKP_BuildBackupCSV(includeHeader)
        return appendMetadata(OriginalBuildBackupCSV(includeHeader), includeHeader and true or false)
    end
end

if OriginalBuildExportText then
    function ADKP_BuildExportText()
        return appendMetadata(OriginalBuildExportText(), false)
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
                groups[altName] = mainName
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

local function sharePlayerNames()
    local tableid = currentTableId()
    local names = {}
    if WebDKP_DkpTable then
        for playerName, data in pairs(WebDKP_DkpTable) do
            if type(data) == "table" and data["dkp_" .. tableid] ~= nil then
                table.insert(names, playerName)
            end
        end
    end
    table.sort(names)
    return names
end

local function updatePickerSuggestions(picker)
    if not picker or not picker.suggestions then return end
    local query = string.lower(trim(picker.edit:GetText()))
    if query == "" or not picker.focused then
        picker.suggestions:Hide()
        return
    end

    local matches = {}
    local names = sharePlayerNames()
    for i = 1, table.getn(names) do
        if string.find(string.lower(names[i]), query, 1, true) then
            table.insert(matches, names[i])
            if table.getn(matches) >= table.getn(picker.buttons) then break end
        end
    end

    for i = 1, table.getn(picker.buttons) do
        local button = picker.buttons[i]
        local playerName = matches[i]
        if playerName then
            button.playerName = playerName
            button:SetText(playerName)
            button:Show()
        else
            button.playerName = nil
            button:Hide()
        end
    end
    if table.getn(matches) > 0 then picker.suggestions:Show() else picker.suggestions:Hide() end
end

local function createPlayerPicker(parent, prefix, x, labelText)
    local picker = { focused = false }
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -60)
    label:SetText(labelText)

    picker.edit = CreateFrame("EditBox", prefix .. "Edit", parent, "InputBoxTemplate")
    picker.edit:SetWidth(185)
    picker.edit:SetHeight(24)
    picker.edit:SetPoint("TOPLEFT", parent, "TOPLEFT", x + 42, -52)
    picker.edit:SetAutoFocus(false)
    picker.edit.picker = picker

    local targetButton = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    targetButton:SetWidth(48)
    targetButton:SetHeight(22)
    targetButton:SetPoint("LEFT", picker.edit, "RIGHT", 5, 0)
    targetButton:SetText("目标")
    targetButton:SetScript("OnClick", function()
        local targetName = UnitName("target")
        if targetName then picker.edit:SetText(targetName) end
    end)

    picker.suggestions = CreateFrame("Frame", prefix .. "Suggestions", parent)
    picker.suggestions:SetWidth(185)
    picker.suggestions:SetHeight(126)
    picker.suggestions:SetPoint("TOPLEFT", picker.edit, "BOTTOMLEFT", 0, -2)
    picker.suggestions:SetFrameLevel(parent:GetFrameLevel() + 30)
    picker.suggestions:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    picker.suggestions:Hide()
    picker.buttons = {}
    for i = 1, 6 do
        local button = CreateFrame("Button", prefix .. "Suggestion" .. i, picker.suggestions, "UIPanelButtonTemplate")
        button:SetWidth(175)
        button:SetHeight(19)
        button:SetPoint("TOPLEFT", picker.suggestions, "TOPLEFT", 5, -(4 + (i - 1) * 20))
        button:SetScript("OnClick", function()
            if this.playerName then
                picker.edit:SetText(this.playerName)
                picker.focused = false
                picker.edit:ClearFocus()
                picker.suggestions:Hide()
            end
        end)
        picker.buttons[i] = button
    end
    picker.edit:SetScript("OnTextChanged", function() updatePickerSuggestions(picker) end)
    picker.edit:SetScript("OnEditFocusGained", function()
        picker.focused = true
        updatePickerSuggestions(picker)
    end)
    picker.edit:SetScript("OnEnterPressed", function()
        picker.focused = false
        this:ClearFocus()
        picker.suggestions:Hide()
    end)
    picker.edit:SetScript("OnEscapePressed", function()
        picker.focused = false
        this:ClearFocus()
        picker.suggestions:Hide()
    end)
    return picker
end

local function shareRelationRows(filterText)
    local tableid = currentTableId()
    local groups, proposals = teamStorage(tableid)
    local rows = {}
    local query = string.lower(trim(filterText))
    for altName, mainName in pairs(groups) do
        if query == "" or string.find(string.lower(mainName), query, 1, true)
            or string.find(string.lower(altName), query, 1, true) then
            local dkp = 0
            if WebDKP_DkpTable and WebDKP_DkpTable[mainName] then
                dkp = tonumber(WebDKP_DkpTable[mainName]["dkp_" .. tableid]) or 0
            end
            table.insert(rows, {
                main = mainName,
                alt = altName,
                dkp = dkp,
                temporary = proposals[altName] and true or false,
            })
        end
    end
    table.sort(rows, function(a, b)
        if a.main == b.main then return a.alt < b.alt end
        return a.main < b.main
    end)
    return rows
end

function ADKP_Share_UpdateTab()
    local frame = ADKP_ShareGroupsFrame
    if not frame or not frame:IsShown() then return end
    local rows = shareRelationRows(frame.searchEdit:GetText())
    local offset = FauxScrollFrame_GetOffset(frame.scroll)
    FauxScrollFrame_Update(frame.scroll, table.getn(rows), table.getn(frame.rows), 24)

    for i = 1, table.getn(frame.rows) do
        local line = frame.rows[i]
        local relation = rows[offset + i]
        if relation then
            line.mainText:SetText(relation.main)
            line.altText:SetText(relation.alt)
            line.dkpText:SetText(string.format("%.2f", relation.dkp))
            line.sourceText:SetText(relation.temporary and "插件临时" or "网站绑定")
            line.action.altName = relation.alt
            if relation.temporary then
                line.action:SetText("解绑")
                line.action:Enable()
            else
                line.action:SetText("网站管理")
                line.action:Disable()
            end
            line:Show()
        else
            line:Hide()
        end
    end
    if table.getn(rows) == 0 then frame.emptyText:Show() else frame.emptyText:Hide() end
    frame.countText:SetText("共 " .. table.getn(rows) .. " 条绑定关系")
end

function ADKP_Share_CreateTab()
    if ADKP_ShareGroupsFrame then return ADKP_ShareGroupsFrame end
    local frame = CreateFrame("Frame", "ADKP_ShareGroupsFrame", ADKP_Frame)
    frame:SetPoint("TOPLEFT", ADKP_Frame, "TOPLEFT", 12, -44)
    frame:SetPoint("BOTTOMRIGHT", ADKP_Frame, "BOTTOMRIGHT", -12, 55)
    frame:SetFrameLevel(ADKP_Frame:GetFrameLevel() + 10)
    frame:EnableMouse(true)

    local background = frame:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints(frame)
    background:SetTexture(0.06, 0.06, 0.08, 0.97)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", 15, -12)
    title:SetText("大小号管理")
    local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", frame, "TOPLEFT", 125, -15)
    hint:SetText("输入角色名即可搜索；插件新增关系会在导回网站后等待确认")

    frame.mainPicker = createPlayerPicker(frame, "ADKP_ShareTabMain", 15, "组内号")
    frame.altPicker = createPlayerPicker(frame, "ADKP_ShareTabAlt", 365, "小号")

    local bindButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    bindButton:SetWidth(82)
    bindButton:SetHeight(24)
    bindButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -15, -52)
    bindButton:SetText("绑定")
    bindButton:SetScript("OnClick", function()
        frame.mainPicker.suggestions:Hide()
        frame.altPicker.suggestions:Hide()
        if ADKP_Share_Bind(frame.mainPicker.edit:GetText(), frame.altPicker.edit:GetText()) then
            frame.altPicker.edit:SetText("")
            ADKP_Share_UpdateTab()
        end
    end)

    local relationLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    relationLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 15, -102)
    relationLabel:SetText("绑定关系")
    frame.countText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.countText:SetPoint("TOPLEFT", frame, "TOPLEFT", 85, -104)

    frame.searchEdit = CreateFrame("EditBox", "ADKP_ShareTabRelationSearch", frame, "InputBoxTemplate")
    frame.searchEdit:SetWidth(180)
    frame.searchEdit:SetHeight(22)
    frame.searchEdit:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -55, -94)
    frame.searchEdit:SetAutoFocus(false)
    frame.searchEdit:SetScript("OnTextChanged", function() ADKP_Share_UpdateTab() end)
    frame.searchEdit:SetScript("OnEscapePressed", function() this:SetText(""); this:ClearFocus() end)
    local searchLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    searchLabel:SetPoint("RIGHT", frame.searchEdit, "LEFT", -5, 0)
    searchLabel:SetText("筛选")

    local headers = {
        { text = "主号", x = 15, width = 180 },
        { text = "小号", x = 200, width = 180 },
        { text = "共享DKP", x = 385, width = 80 },
        { text = "来源", x = 475, width = 100 },
        { text = "操作", x = 610, width = 80 },
    }
    for i = 1, table.getn(headers) do
        local header = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        header:SetPoint("TOPLEFT", frame, "TOPLEFT", headers[i].x, -130)
        header:SetWidth(headers[i].width)
        header:SetJustifyH("LEFT")
        header:SetText(headers[i].text)
    end

    frame.scroll = CreateFrame("ScrollFrame", "ADKP_ShareTabScroll", frame, "FauxScrollFrameTemplate")
    frame.scroll:SetWidth(720)
    frame.scroll:SetHeight(216)
    frame.scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 15, -150)
    frame.scroll:SetScript("OnVerticalScroll", function()
        FauxScrollFrame_OnVerticalScroll(24, ADKP_Share_UpdateTab)
    end)
    frame.rows = {}
    for i = 1, 9 do
        local line = CreateFrame("Frame", "ADKP_ShareTabRow" .. i, frame)
        line:SetWidth(700)
        line:SetHeight(22)
        line:SetPoint("TOPLEFT", frame, "TOPLEFT", 15, -(152 + (i - 1) * 24))
        local rowBg = line:CreateTexture(nil, "BACKGROUND")
        rowBg:SetAllPoints(line)
        rowBg:SetTexture(0.12, 0.12, 0.14, i / 30)

        line.mainText = line:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        line.mainText:SetPoint("LEFT", line, "LEFT", 0, 0)
        line.mainText:SetWidth(180)
        line.mainText:SetJustifyH("LEFT")
        line.altText = line:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        line.altText:SetPoint("LEFT", line, "LEFT", 185, 0)
        line.altText:SetWidth(180)
        line.altText:SetJustifyH("LEFT")
        line.dkpText = line:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        line.dkpText:SetPoint("LEFT", line, "LEFT", 370, 0)
        line.dkpText:SetWidth(80)
        line.dkpText:SetJustifyH("LEFT")
        line.sourceText = line:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        line.sourceText:SetPoint("LEFT", line, "LEFT", 460, 0)
        line.sourceText:SetWidth(105)
        line.sourceText:SetJustifyH("LEFT")
        line.action = CreateFrame("Button", nil, line, "UIPanelButtonTemplate")
        line.action:SetWidth(82)
        line.action:SetHeight(20)
        line.action:SetPoint("LEFT", line, "LEFT", 590, 0)
        line.action:SetScript("OnClick", function()
            if this.altName and ADKP_Share_CancelProposal(this.altName) then
                ADKP_Share_UpdateTab()
            end
        end)
        frame.rows[i] = line
    end

    frame.emptyText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.emptyText:SetPoint("CENTER", frame, "CENTER", 0, -45)
    frame.emptyText:SetText("当前团队还没有大小号绑定关系")
    frame:Hide()
    return frame
end

function ADKP_Share_ShowManager(playerName)
    if ADKP_Frame then ADKP_Frame:Show() end
    if ADKP_FrameTab4 then ADKP_FrameTab4:Click() else ADKP_Share_CreateTab() end
    local frame = ADKP_ShareGroupsFrame
    if not frame then return end

    local tableid = currentTableId()
    local groups = teamStorage(tableid)
    local canonical = canonicalPlayerName(playerName)
    if canonical and groups[canonical] then
        frame.mainPicker.edit:SetText(groups[canonical])
        frame.altPicker.edit:SetText(canonical)
    elseif canonical and mainHasAlts(canonical, tableid) then
        frame.mainPicker.edit:SetText(canonical)
        frame.altPicker.edit:SetText("")
    elseif canonical then
        frame.altPicker.edit:SetText(canonical)
    end
    ADKP_Share_UpdateTab()
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
