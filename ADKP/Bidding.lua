------------------------------------------------------------------------
-- BIDDING	
------------------------------------------------------------------------
-- Contains methods related to bidding and the bidding gui.
------------------------------------------------------------------------


local ADKP_BidList = {	};					-- Will hold the bids placed during run time
local ADKP_bidInProgress = false;			-- Bid in progress?
local ADKP_Bid_Unfinished = false;          -- Stopped bidding may still await recording/assignment.
local ADKP_bidItem = "";					-- Item name being bid on
local ADKP_bidCountdown = 0;				-- How many seconds until bid ends on its own
local ADKP_TransmogMode = false;
local ADKP_TransmogSequence = 0;
local ADKP_TransmogRecordOnAward = false;
local ADKP_TransmogRecordRef = nil;
local ADKP_Bid_ActionRevision = 0;

function ADKP_Bid_IsInProgress()
	return ADKP_bidInProgress
end

-- 仅供界面显示/返回判断，保留普通出分与幻化各自的业务状态。
function ADKP_Bid_GetPhase()
	if ADKP_TransmogMode then return "transmog" end
	if ADKP_bidInProgress then return "bidding" end
end

-- 拍卖队列：支持一次输入多件装备顺序拍卖
ADKP_BidQueue = {}                           -- 待拍卖物品队列，每项 { item = itemName, time = countdownTime }
ADKP_BidQueueTimer = nil                     -- 延迟启动下一件的 OnUpdate frame

-- 从 itemPart 中提取所有物品，支持 item link 和纯文本 [装备名] 两种格式
-- 返回完整链接/文本，供 ADKP_GetItemInfo 解析出物品名和链接
local function ADKP_Bid_Trim(text)
    if not text then
        return ""
    end
    return string.gsub(text, "^%s*(.-)%s*$", "%1")
end

-- The editable field can scroll to the end on 1.12. Show its name separately
-- while unfocused, retaining the original value for all auction operations.
function ADKP_Bid_UpdateItemDisplay(box)
	if not box or not ADKP_BidFrameItemDisplayText then return end
	local value = box:GetText() or ""
	local _, _, name = string.find(value, "|h%[([^%]]+)%]|h")
	local _, _, color = string.find(value, "^|c(%x%x%x%x%x%x%x%x)")
	if name and color then name = "|c" .. color .. name .. "|r" end
	ADKP_BidFrameItemDisplayText:SetText(name or value)
end

function ADKP_Bid_ShowItemDisplay()
	local box = ADKP_BidFrameItem
	if not box or not ADKP_BidFrameItemDisplay or box.ADKPChangingItemView then return end
	box.ADKPChangingItemView = true
	box:ClearFocus()
	ADKP_Bid_UpdateItemDisplay(box)
	box:Hide()
	ADKP_BidFrameItemDisplay:Show()
	box.ADKPChangingItemView = nil
end

function ADKP_Bid_EditItem()
	ADKP_BidFrameItemDisplay:Hide()
	ADKP_BidFrameItem:Show()
	ADKP_BidFrameItem:SetFocus()
end

-- Read only class restrictions supplied by the item's tooltip. No item database
-- is maintained here; a missing or uncached tooltip simply has no class line.
local ADKP_BidClassItemData, ADKP_BidClassDisplayText
function ADKP_Bid_ClearItemClasses()
	if ADKP_BidFrameItemClassesText then ADKP_BidFrameItemClassesText:SetText("") end
end

-- Shared reader: queue scans must not change the current auction's label/source.
local function ADKP_Bid_GetItemData(item)
	if not item or item == "" then return end
	local _, _, itemData = string.find(item, "(item:[^|%s]+)")
	if not itemData then
		local _, link = GetItemInfo(item)
		if link then
			local _, _, found = string.find(link, "(item:[^|%s]+)")
			itemData = found
		end
	end
	return itemData
end

function ADKP_Bid_ReadItemClasses(item)
	local itemData = ADKP_Bid_GetItemData(item)
	if not itemData then return end
	if not ADKP_BidItemClassTooltip then
		ADKP_BidItemClassTooltip = CreateFrame("GameTooltip", "ADKP_BidItemClassTooltip", UIParent, "GameTooltipTemplate")
		if not getglobal("ADKP_BidItemClassTooltipTextLeft1") and ADKP_BidItemClassTooltip.AddFontStrings then
			local left = ADKP_BidItemClassTooltip:CreateFontString("ADKP_BidItemClassTooltipTextLeft1", nil, "GameTooltipText")
			local right = ADKP_BidItemClassTooltip:CreateFontString("ADKP_BidItemClassTooltipTextRight1", nil, "GameTooltipText")
			ADKP_BidItemClassTooltip:AddFontStrings(left, right)
		end
	end
	local tip = ADKP_BidItemClassTooltip
	tip:SetOwner(UIParent, "ANCHOR_NONE")
	tip:ClearLines()
	local ok, foundLoot = false, false
	local _, _, itemId = string.find(itemData, "^item:(%d+)")
	if itemId and GetNumLootItems and GetLootSlotLink and tip.SetLootItem then
		for i = 1, GetNumLootItems() do
			local lootLink = GetLootSlotLink(i)
			local _, _, lootId = string.find(lootLink or "", "item:(%d+)")
			if lootId == itemId then
				ok = pcall(function() tip:SetLootItem(i) end)
				foundLoot = ok and tip:NumLines() > 0
				break
			end
		end
	end
	if not foundLoot then
		tip:ClearLines()
		ok = pcall(function() tip:SetHyperlink(itemData) end)
	end
	local matched
	-- A populated tooltip without a class line is ready, not a failed read.
	local ready = ok and tip:NumLines() > 1
	if ok then
		local prefix
		if ITEM_CLASSES_ALLOWED then
			local _, _, found = string.find(ITEM_CLASSES_ALLOWED, "^(.-)%%s")
			prefix = found
		end
		for i = 2, tip:NumLines() do
			local line = getglobal("ADKP_BidItemClassTooltipTextLeft" .. i)
			local value = line and line:GetText()
			if value and ((prefix and prefix ~= "" and string.find(value, prefix, 1, true) == 1)
				or string.find(value, "职业:", 1, true) == 1
				or string.find(value, "职业：", 1, true) == 1
				or string.find(value, "職業:", 1, true) == 1
				or string.find(value, "職業：", 1, true) == 1
				or string.find(value, "Classes:", 1, true) == 1) then
				matched = value
				break
			end
		end
	end
	tip:Hide()
	return matched, ready
end

-- Count the names in the tooltip, not a hardcoded list of items or classes.
local function ADKP_Bid_RestrictedClassNames(line)
	if not line or line == "" then return {} end
	local text = string.gsub(line, "|c%x%x%x%x%x%x%x%x", "")
	text = string.gsub(text, "|r", "")
	text = string.gsub(text, "：", ":")
	local colon = string.find(text, ":", 1, true)
	if not colon then return {} end
	text = string.sub(text, colon + 1)
	text = string.gsub(text, "，", ",")
	text = string.gsub(text, "、", ",")
	local names, seen = {}, {}
	for name in string.gfind(text, "[^,]+") do
		name = string.gsub(name, "^%s*(.-)%s*$", "%1")
		if name ~= "" and not seen[name] then
			seen[name] = true
			table.insert(names, name)
		end
	end
	return names
end

local function ADKP_Bid_CountRestrictedClasses(line)
	return table.getn(ADKP_Bid_RestrictedClassNames(line))
end

local function ADKP_Bid_ShortClassText(line)
	local names = ADKP_Bid_RestrictedClassNames(line)
	if table.getn(names) > 0 then
		for i = 1, table.getn(names) do
			-- Lua 5.0 indexes bytes: keep the whole first UTF-8 character.
			local first = string.byte(names[i], 1)
			local bytes = 1
			if first >= 240 then bytes = 4
			elseif first >= 224 then bytes = 3
			elseif first >= 192 then bytes = 2 end
			names[i] = string.sub(names[i], 1, bytes)
		end
		return "职业：" .. table.concat(names, " ")
	end
end

function ADKP_Bid_GetClassAnnouncement(item)
	local text = ADKP_Bid_ShortClassText(ADKP_Bid_ReadItemClasses(item))
	if text then return "---" .. text .. " ---" end
end

local ADKP_BidLootSort = {}
local function ADKP_Bid_StopLootSort()
	local state = ADKP_BidLootSort
	if state.frame then
		state.frame:SetScript("OnUpdate", nil)
		state.frame:Hide()
	end
	state.entries, state.reads, state.appended = nil, nil, nil
end

local function ADKP_Bid_TryLootSort()
	local state = ADKP_BidLootSort
	local pending = false
	for key, result in pairs(state.reads) do
		if not result.ready then
			local line, ready = ADKP_Bid_ReadItemClasses(result.item)
			result.count = ADKP_Bid_CountRestrictedClasses(line)
			result.ready = ready or result.count > 0
			if not result.ready then pending = true end
		end
	end
	if pending and state.elapsed < 0.3 then return end
	local entries = state.entries
	for i = 1, table.getn(entries) do
		entries[i].count = state.reads[entries[i].key].count or 0
	end
	-- Explicit original positions make ties stable even though table.sort isn't.
	table.sort(entries, function(a, b)
		if a.count ~= b.count then return a.count > b.count end
		return a.order < b.order
	end)
	local queue = {}
	for i = 1, table.getn(entries) do table.insert(queue, entries[i].entry) end
	for i = 1, table.getn(state.appended) do table.insert(queue, state.appended[i]) end
	ADKP_Bid_StopLootSort()
	ADKP_BidQueue = queue
	local first = table.remove(ADKP_BidQueue, 1)
	ADKP_Bid_StartBid(first.item, first.time)
end

-- Used only by the loot-window "拍" action. Do not sort the running queue.
function ADKP_Bid_StartSortedLootQueue(queue)
	ADKP_Bid_StopLootSort()
	if not queue or table.getn(queue) == 0 then return end
	if ADKP_Bid_GetPhase() then ADKP_Bid_ShowUI(); return end
	local state = ADKP_BidLootSort
	state.entries, state.reads, state.appended = {}, {}, {}
	state.elapsed, state.nextRetry = 0, 0.1
	state.revision, state.previousQueue = ADKP_Bid_ActionRevision, ADKP_BidQueue
	for i = 1, table.getn(queue) do
		local entry = queue[i]
		local key = ADKP_Bid_GetItemData(entry.item) or entry.item
		state.entries[i] = { entry = entry, key = key, order = i }
		state.reads[key] = state.reads[key] or { item = entry.item }
	end
	ADKP_Bid_TryLootSort()
	if not state.entries then return end -- Cached loot starts immediately.
	if not state.frame then state.frame = CreateFrame("Frame", "ADKP_BidLootSortFrame", UIParent) end
	state.frame:SetScript("OnUpdate", function()
		-- A newer auction/action wins over this short-lived pending request.
		if state.revision ~= ADKP_Bid_ActionRevision or state.previousQueue ~= ADKP_BidQueue
			or ADKP_Bid_GetPhase() or (ADKP_IsAddonDisabled and ADKP_IsAddonDisabled()) then
			ADKP_Bid_StopLootSort()
			return
		end
		state.elapsed = state.elapsed + (tonumber(arg1) or 0)
		if state.elapsed < state.nextRetry and state.elapsed < 0.3 then return end
		state.nextRetry = state.elapsed + 0.1
		ADKP_Bid_TryLootSort()
	end)
	state.frame:Show()
end

function ADKP_Bid_UpdateItemClasses(item)
	ADKP_Bid_ClearItemClasses()
	if not ADKP_BidFrameItemClassesText or not item or item == "" then return end
	local itemData = ADKP_Bid_GetItemData(item)
	if not itemData and item == ADKP_BidClassDisplayText then itemData = ADKP_BidClassItemData end
	if not itemData then return end
	ADKP_BidClassItemData = itemData
	ADKP_BidClassDisplayText = ADKP_BidFrameItem and ADKP_BidFrameItem:GetText() or item
	local classes = ADKP_Bid_ReadItemClasses(itemData)
	if classes then ADKP_BidFrameItemClassesText:SetText(classes) end
	return classes ~= nil
end

-- SetText / OnTextChanged and focus events can arrive in different orders.
-- Coalesce them into a refresh after the UI settles, using the original link.
local ADKP_BidItemRefresh = {}
function ADKP_Bid_GetCurrentItemSource()
	local text = ADKP_BidFrameItem and ADKP_BidFrameItem:GetText() or ""
	if ADKP_BidItemRefresh.text == text then return ADKP_BidItemRefresh.item or text end
	return text
end
function ADKP_Bid_RequestItemRefresh(item)
	if not ADKP_BidFrameItem or not ADKP_BidFrameItemClassesText then return end
	local currentText = ADKP_BidFrameItem:GetText() or ""
	local state = ADKP_BidItemRefresh
	if not item then
		item = state.text == currentText and state.item or currentText
	end
	if item ~= state.item then ADKP_Bid_ClearItemClasses() end
	state.item = item
	state.text = currentText
	state.delay = 0.1
	state.attempts = 0
	if not state.frame then
		state.frame = CreateFrame("Frame", "ADKP_BidItemRefreshFrame", UIParent)
		state.frame:SetScript("OnUpdate", function()
			if not ADKP_BidFrame:IsShown() or ADKP_BidFrameItem:GetText() ~= state.text then
				state.frame:Hide()
				return
			end
			state.delay = state.delay - (tonumber(arg1) or 0)
			if state.delay > 0 then return end
			state.attempts = state.attempts + 1
			if ADKP_Bid_UpdateItemClasses(state.item) or state.attempts >= 4 then
				state.frame:Hide()
			else
				-- Item data may arrive shortly after its link is added to the queue.
				state.delay = 0.3
			end
		end)
	end
	state.frame:Show()
end

function ADKP_Bid_ItemTextChanged(box)
	ADKP_Bid_UpdateItemDisplay(box)
	ADKP_Bid_RequestItemRefresh()
end

local function ADKP_Bid_ParseItems(itemPart)
    local items = {}
    local text = ADKP_Bid_Trim(itemPart)
    local pos
    local token

    if text == "" then
        return items
    end

    -- Keep the raw token whenever possible so the downstream flow matches
    -- the old single-item path and still carries clickable item links.
    if not string.find(text, "|Hitem:") and not string.find(text, "%[[^%]]+%]") then
        table.insert(items, text)
        return items
    end

    pos = 1
    while pos <= string.len(text) do
        local remaining = string.sub(text, pos)
        local spacer = string.match(remaining, "^(%s+)")
        if spacer then
            pos = pos + string.len(spacer)
            remaining = string.sub(text, pos)
        end

        if remaining == "" then
            break
        end

        token = string.match(remaining, "^(|c%x%x%x%x%x%x%x%x|Hitem:[^|]+|h%[[^%]]+%]|h|r)")
        if not token then
            token = string.match(remaining, "^(|Hitem:[^|]+|h%[[^%]]+%]|h)")
        end
        if not token then
            token = string.match(remaining, "^(%[[^%]]+%])")
        end
        if not token then
            token = string.match(remaining, "^(%S+)")
        end

        if not token or token == "" then
            break
        end

        table.insert(items, token)
        pos = pos + string.len(token)
    end

    return items
end

-- Manual countdown state (independent of the automatic bid timer)
ADKP_ManualCountdownFrame = ADKP_ManualCountdownFrame or nil
ADKP_ManualCountdownRunning = ADKP_ManualCountdownRunning or false
ADKP_ManualCountdownValue = ADKP_ManualCountdownValue or 0

-- Normalize bid amounts to 2 decimal places without exceeding the original value.
local function ADKP_Bid_NormalizeAmount(amount)
	local num = tonumber(amount) or 0
	if num ~= num then
		return 0
	end
	-- Truncate to 2 decimals to avoid overbidding due to rounding.
	return math.floor(num * 100 + 0.0000001) / 100
end

local function ADKP_Bid_FormatAmount(amount)
	local num = ADKP_Bid_NormalizeAmount(amount)
	return string.format("%.2f", num)
end

-- Data structure for sorting the table 
ADKP_BidSort = {
	["curr"] = 2,				-- the column to sort
	["way"] = 1					-- Desc
};

-- ================================
-- Toggles displaying the bidding panel
-- ================================
function ADKP_Bid_ToggleUI()
	if ( ADKP_BidFrame:IsShown() ) then
		ADKP_BidFrame:Hide();
	else
		ADKP_BidFrame:Show();
		
		local time = ADKP_BidFrameTime:GetText();
		if(time == nil or time == "") then
			ADKP_BidFrameTime:SetText("0");
		end
	end
end

-- ================================
-- Shows the Bid UI
-- ================================
function ADKP_Bid_ShowUI()
	ADKP_BidFrame:Show();
	local time = ADKP_BidFrameTime:GetText();
	if(time == nil or time == "") then
		ADKP_BidFrameTime:SetText("0");
	end
	ADKP_CreateBidQueueWindow();
	ADKP_UpdateBidQueueWindow();
end

-- ================================
-- Hides the Bid UI
-- ================================
function ADKP_Bid_HideUI()
	ADKP_BidFrame:Hide();
	if ADKP_BidQueueWindow then ADKP_BidQueueWindow:Hide() end
end

-- ================================
-- 拍卖队列窗口（贴竞拍界面右边，显示当前 + 剩余，可取消/调整顺序）
-- ================================
ADKP_BidQueueWindow = nil

-- A fixed number of reusable rows keeps the window bounded even for large queues.
local ADKP_BID_QUEUE_ROWS = 4
-- Scroll offsets use a stable logical step; actual rows collapse without classes.
local ADKP_BID_QUEUE_ROW_HEIGHT = 60

local function ADKP_BidQueue_Label(parent, x, y, width, height)
	local text = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	text:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
	text:SetWidth(width)
	text:SetHeight(height)
	text:SetJustifyH("LEFT")
	text:SetJustifyV("TOP")
	return text
end

local function ADKP_BidQueue_ItemName(item)
	local _, _, name = string.find(item or "", "|h(%[[^%]]+%])|h")
	local _, _, color = string.find(item or "", "^|c(%x%x%x%x%x%x%x%x)")
	if name and color then return "|c" .. color .. name .. "|r" end
	return name or item or ""
end

local function ADKP_BidQueue_Layout(f)
	local currentHasClasses = (f.curClasses:GetText() or "") ~= ""
	local top = currentHasClasses and 104 or 80
	f.curBg:SetHeight(currentHasClasses and 64 or 40)
	if currentHasClasses then f.curClasses:Show() else f.curClasses:Hide() end
	f.scroll:ClearAllPoints()
	f.scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -top)
	local height = 0
	for i = 1, ADKP_BID_QUEUE_ROWS do
		local r = f.rows[i]
		if r.row.idx then
			local hasClasses = (r.classes:GetText() or "") ~= ""
			local rowHeight = hasClasses and 60 or 42
			local buttonTop = hasClasses and -41 or -23
			if hasClasses then r.classes:Show() else r.classes:Hide() end
			r.row:ClearAllPoints()
			r.row:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -top - height)
			r.row:SetHeight(rowHeight)
			r.up:ClearAllPoints()
			r.up:SetPoint("TOPLEFT", r.row, "TOPLEFT", 112, buttonTop)
			r.down:ClearAllPoints()
			r.down:SetPoint("TOPLEFT", r.row, "TOPLEFT", 134, buttonTop)
			r.cancel:ClearAllPoints()
			r.cancel:SetPoint("TOPLEFT", r.row, "TOPLEFT", 156, buttonTop)
			height = height + rowHeight
		end
	end
	f.scroll:SetHeight(math.max(42, height))
	f:SetHeight(top + height + 36)
end

-- Only visible items are inspected, one tooltip per tick. Positive results are
-- reused; missing item data gets four bounded attempts, never permanent polling.
local function ADKP_BidQueue_BindClasses(f, label, item)
	local key = ADKP_Bid_GetItemData(item) or item
	local cached = key and f.classCache[key]
	label:SetText(ADKP_Bid_ShortClassText(cached) or "")
	if not key or key == "" or cached then return end
	local job = f.classJobsByKey[key]
	if not job then
		job = { item = item, key = key, labels = {}, attempts = 0, ready = 0.1 }
		f.classJobsByKey[key] = job
		table.insert(f.classJobs, job)
	end
	table.insert(job.labels, label)
end

local function ADKP_BidQueue_RefreshClasses()
	local f = this
	if not ADKP_BidFrame:IsVisible() then f:SetScript("OnUpdate", nil); return end
	f.classElapsed = f.classElapsed + (tonumber(arg1) or 0)
	if f.classElapsed < f.nextClassScan then return end
	f.nextClassScan = f.classElapsed + 0.05
	for i = 1, table.getn(f.classJobs) do
		local job = f.classJobs[i]
		if job.ready <= f.classElapsed then
			local classes = ADKP_Bid_ReadItemClasses(job.item)
			job.attempts = job.attempts + 1
			if classes then
				f.classCache[job.key] = classes
				for j = 1, table.getn(job.labels) do job.labels[j]:SetText(ADKP_Bid_ShortClassText(classes) or "") end
				ADKP_BidQueue_Layout(f)
			end
			table.remove(f.classJobs, i)
			if not classes and job.attempts < 4 then
				job.ready = f.classElapsed + 0.3
				table.insert(f.classJobs, job)
			end
			break
		end
	end
	if table.getn(f.classJobs) == 0 then f:SetScript("OnUpdate", nil) end
end

function ADKP_CreateBidQueueWindow()
	if ADKP_BidQueueWindow then return ADKP_BidQueueWindow end
	local f = CreateFrame("Frame", "ADKP_BidQueueWindow", UIParent)
	f:SetWidth(210)
	f:SetHeight(200)
	f:SetPoint("TOPLEFT", ADKP_BidFrame, "TOPRIGHT", 8, 0)
	f:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 16,
		insets = { left = 4, right = 4, top = 4, bottom = 4 }
	})
	f:SetBackdropColor(0, 0, 0, 0.85)
	f:SetScript("OnHide", function() this:SetScript("OnUpdate", nil) end)
	f:Hide()
	f.classCache = {}

	local title = ADKP_BidQueue_Label(f, 12, -12, 80, 16)
	title:SetText("拍卖队列")
	f.countText = ADKP_BidQueue_Label(f, 126, -12, 72, 16)
	f.countText:SetJustifyH("RIGHT")

	local curBg = f:CreateTexture(nil, "BACKGROUND")
	curBg:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -32)
	curBg:SetWidth(194)
	curBg:SetHeight(64)
	curBg:SetTexture(0.1, 0.4, 0.1, 0.6)
	f.curBg = curBg
	f.curText = ADKP_BidQueue_Label(f, 14, -52, 182, 16)
	f.curText:SetNonSpaceWrap(false)
	local current = ADKP_BidQueue_Label(f, 14, -36, 182, 14)
	current:SetText("当前拍卖")
	f.curClasses = ADKP_BidQueue_Label(f, 14, -72, 182, 18)

	local scroll = CreateFrame("ScrollFrame", "ADKP_BidQueueScroll", f, "FauxScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -104)
	scroll:SetWidth(174)
	scroll:SetHeight(ADKP_BID_QUEUE_ROWS * ADKP_BID_QUEUE_ROW_HEIGHT)
	scroll:SetScript("OnVerticalScroll", function()
		FauxScrollFrame_OnVerticalScroll(ADKP_BID_QUEUE_ROW_HEIGHT, ADKP_UpdateBidQueueWindow)
	end)
	f.scroll = scroll

	f.rows = {}
	for i = 1, ADKP_BID_QUEUE_ROWS do
		local row = CreateFrame("Frame", nil, f)
		row:SetWidth(174)
		row:SetHeight(ADKP_BID_QUEUE_ROW_HEIGHT)
		row:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -104 - (i - 1) * ADKP_BID_QUEUE_ROW_HEIGHT)
		row:EnableMouse(true)
		row:SetScript("OnMouseDown", function()
			if arg1 == "LeftButton" then ADKP_BidQueue_SwitchTo(this.idx) end
		end)
		local bg = row:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints(row)
		bg:SetTexture(1, 1, 1, math.mod(i, 2) == 0 and 0.04 or 0.08)

		local number = ADKP_BidQueue_Label(row, 2, -3, 22, 16)
		local text = ADKP_BidQueue_Label(row, 24, -3, 150, 16)
		text:SetNonSpaceWrap(false)
		local classes = ADKP_BidQueue_Label(row, 2, -21, 172, 18)

		local up = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
		up:SetWidth(18); up:SetHeight(18)
		up:SetPoint("TOPLEFT", row, "TOPLEFT", 112, -41)
		up:SetText("↑"); up:RegisterForClicks("LeftButtonUp")
		up:SetScript("OnClick", function() ADKP_BidQueue_Up(this:GetParent().idx) end)

		local down = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
		down:SetWidth(18); down:SetHeight(18)
		down:SetPoint("TOPLEFT", row, "TOPLEFT", 134, -41)
		down:SetText("↓"); down:RegisterForClicks("LeftButtonUp")
		down:SetScript("OnClick", function() ADKP_BidQueue_Down(this:GetParent().idx) end)

		local cancel = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
		cancel:SetWidth(18); cancel:SetHeight(18)
		cancel:SetPoint("TOPLEFT", row, "TOPLEFT", 156, -41)
		cancel:SetText("×"); cancel:RegisterForClicks("LeftButtonUp")
		cancel:SetScript("OnClick", function() ADKP_BidQueue_Cancel(this:GetParent().idx) end)
		row:Hide()
		f.rows[i] = { row = row, number = number, text = text, classes = classes, up = up, down = down, cancel = cancel }
	end

	local tip = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	tip:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 12, 8)
	tip:SetWidth(186); tip:SetHeight(28)
	tip:SetJustifyH("LEFT")
	tip:SetText("点击物品切换拍卖\n↑↓ 排序　× 移出")
	ADKP_BidQueueWindow = f
	return f
end

function ADKP_Bid_UpdateQueueLabel()
	if not ADKP_BidQueueLabel and ADKP_BidFrame then
		ADKP_BidQueueLabel = ADKP_BidFrame:CreateFontString("ADKP_BidQueueLabel", "OVERLAY", "GameFontNormal")
		ADKP_BidQueueLabel:SetPoint("TOPLEFT", ADKP_BidFrame, "TOPLEFT", 200, -158)
	end
	if ADKP_BidQueueLabel then
		local count = table.getn(ADKP_BidQueue)
		ADKP_BidQueueLabel:SetText(count > 0 and ("|cffffff00(队列还有" .. count .. "件)|r") or "")
	end
end

function ADKP_UpdateBidQueueWindow()
	ADKP_Bid_UpdateQueueLabel()
	local f = ADKP_BidQueueWindow
	if not f or f.updating then return end
	f.updating = true
	local n = table.getn(ADKP_BidQueue)
	local visible = math.min(ADKP_BID_QUEUE_ROWS, math.max(1, n))
	local offset = math.min(FauxScrollFrame_GetOffset(f.scroll) or 0, math.max(0, n - visible))
	f.scroll.offset = offset
	FauxScrollFrame_Update(f.scroll, n, visible, ADKP_BID_QUEUE_ROW_HEIGHT)
	-- Keep the thumb in range when removing the last item on the final page.
	local bar = getglobal("ADKP_BidQueueScrollScrollBar")
	if bar then bar:SetValue(offset * ADKP_BID_QUEUE_ROW_HEIGHT) end

	-- Rebuild jobs along with the row bindings so old results cannot label a
	-- different item after a reorder, removal or scroll.
	f.classJobs, f.classJobsByKey = {}, {}
	f.classElapsed, f.nextClassScan = 0, 0.1
	local current = ADKP_Bid_GetCurrentItemSource()
	f.curText:SetText("1. " .. ADKP_BidQueue_ItemName(current ~= "" and current or "（无）"))
	f.countText:SetText("待拍 " .. n .. " 件")
	ADKP_BidQueue_BindClasses(f, f.curClasses, current)
	for i = 1, ADKP_BID_QUEUE_ROWS do
		local r = f.rows[i]
		local idx = offset + i
		local entry = ADKP_BidQueue[idx]
		if entry and i <= visible then
			r.row.idx = idx
			r.number:SetText((idx + 1) .. ".")
			r.text:SetText(ADKP_BidQueue_ItemName(entry.item))
			ADKP_BidQueue_BindClasses(f, r.classes, entry.item)
			r.row:Show()
		else
			r.row.idx = nil
			r.row:Hide()
		end
	end
	ADKP_BidQueue_Layout(f)
	f.updating = nil
	if ADKP_BidFrame and ADKP_BidFrame:IsVisible() and n > 0 then
		f:Show()
		if table.getn(f.classJobs) > 0 then
			f:SetScript("OnUpdate", ADKP_BidQueue_RefreshClasses)
		else
			f:SetScript("OnUpdate", nil)
		end
	else
		f:Hide()
	end
end

function ADKP_BidQueue_Cancel(i)
	if i < 1 or i > table.getn(ADKP_BidQueue) then return end
	table.remove(ADKP_BidQueue, i)
	ADKP_UpdateBidQueueWindow()
end

function ADKP_BidQueue_Up(i)
	if i < 1 or i > table.getn(ADKP_BidQueue) then return end
	if i == 1 then
		-- 队列首件点向上：切换为当前拍卖物品（当前拍卖物放回队首）
		ADKP_BidQueue_SwitchTo(1)
		return
	end
	ADKP_BidQueue[i - 1], ADKP_BidQueue[i] = ADKP_BidQueue[i], ADKP_BidQueue[i - 1]
	ADKP_UpdateBidQueueWindow()
end

function ADKP_BidQueue_Down(i)
	if i < 1 or i >= table.getn(ADKP_BidQueue) then return end
	ADKP_BidQueue[i], ADKP_BidQueue[i + 1] = ADKP_BidQueue[i + 1], ADKP_BidQueue[i]
	ADKP_UpdateBidQueueWindow()
end

-- 强制切换：当前拍卖物放回队首，第 i 件变为当前并立即开始
function ADKP_BidQueue_SwitchTo(i)
	if i < 1 or i > table.getn(ADKP_BidQueue) then return end
	local currentItem = ADKP_Bid_GetCurrentItemSource()
	local targetIndex = i
	if currentItem and currentItem ~= "" then
		table.insert(ADKP_BidQueue, 1, { item = currentItem, time = 0 })
		targetIndex = i + 1
	end
	local target = table.remove(ADKP_BidQueue, targetIndex)
	ADKP_Bid_StartBid(target.item, target.time or 0)
	ADKP_UpdateBidQueueWindow()
end

function ADKP_Bid_ReauctionItem(item)
	if not item or item == "" then return false end
	local timerActive = ADKP_BidQueueTimer and ADKP_BidQueueTimer:GetScript("OnUpdate")
	if ADKP_bidInProgress or ADKP_TransmogMode or timerActive then
		table.insert(ADKP_BidQueue, { item = item, time = 0 })
		ADKP_UpdateBidQueueWindow()
		ADKP_Print("已将物品加入拍卖队列末尾")
	else
		ADKP_Bid_StartBid(item, 0)
	end
	return true
end

-- ================================
-- Called when mouse goes over a dkp line entry. 
-- If that player is not selected causes that row
-- to become 'highlighted'
-- ================================
function ADKP_Bid_HandleMouseOver()
	if ADKP_TransmogMode and this.ADKP_BidEntry then
		if not this.ADKP_BidEntry["Selected"] then
			getglobal(this:GetName() .. "Background"):SetVertexColor(0.2, 0.2, 0.7, 0.5);
		end
		if this.ADKP_BidEntry["Kind"] == "roll" and table.getn(this.ADKP_BidEntry["RepeatRolls"] or {}) > 0 then
			GameTooltip:SetOwner(this, "ANCHOR_RIGHT");
			GameTooltip:SetText(this.ADKP_BidEntry["Name"] .. " 的 Roll 点", 1, 1, 1);
			GameTooltip:AddLine("首次有效点数：" .. this.ADKP_BidEntry["Roll"], 0.8, 0.8, 0.8);
			GameTooltip:AddLine("后续重复点数：" .. table.concat(this.ADKP_BidEntry["RepeatRolls"], "、"), 1, 0.4, 0.4);
			GameTooltip:Show();
		end
		return
	end
	local playerName = getglobal(this:GetName().."Name"):GetText();
	local playerBid = getglobal(this:GetName().."Bid"):GetText();
	local selected = ADKP_Bid_IsSelected(playerName, playerBid);
	
	if( not selected ) then
		getglobal(this:GetName() .. "Background"):SetVertexColor(0.2, 0.2, 0.7, 0.5);
	end
end

-- ================================
-- Called when a mouse leaes a dkp line entry. 
-- If that player is not selected, causes that row
-- to return to normal (none highlighted)
-- ================================
function ADKP_Bid_HandleMouseLeave()
	if ADKP_TransmogMode and this.ADKP_BidEntry then
		if not this.ADKP_BidEntry["Selected"] then
			getglobal(this:GetName() .. "Background"):SetVertexColor(0, 0, 0, 0);
		end
		GameTooltip:Hide();
		return
	end
	local playerName = getglobal(this:GetName().."Name"):GetText();
	local playerBid = getglobal(this:GetName().."Bid"):GetText();
	local selected = ADKP_Bid_IsSelected(playerName, playerBid);
	if( not selected ) then
		getglobal(this:GetName() .. "Background"):SetVertexColor(0, 0, 0, 0);
	end
end

-- ================================
-- Called when the user clicks on a player entry. Causes 
-- that entry to either become selected or normal
-- and updates the dkp table with the change
-- ================================
function ADKP_Bid_SelectPlayerToggle()
	if ADKP_TransmogMode and this.ADKP_BidEntry then
		local selectedEntry = this.ADKP_BidEntry
		for _, v in pairs(ADKP_BidList) do
			if type(v) == "table" then
				v["Selected"] = (v == selectedEntry) and not selectedEntry["Selected"] or false
			end
		end
		ADKP_Bid_UpdateTable();
		return
	end
	local playerName = getglobal(this:GetName().."Name"):GetText();
	local playerBid = tonumber(getglobal(this:GetName().."Bid"):GetText()) or 0 ;
	
	
	-- we need to search through the table and figure out which one was selected
	-- an entry is considered a unique name / bid pair
	-- once we find an entry we can toggle its selection state
	for key, v in pairs(ADKP_BidList) do
		if ( type(v) == "table" ) then
			if( v["Name"] ~= nil and v["Bid"] ~= nil ) then
				if ( v["Name"] == playerName and v["Bid"] == playerBid ) then 
					if (v["Selected"] == true) then
						v["Selected"] = false;
						getglobal(this:GetName() .. "Background"):SetVertexColor(0.2, 0.2, 0.7, 0.5);
					else
						-- deselect all the others on the table
						ADKP_Bid_DeselectAll();
						
						v["Selected"] = true;
						getglobal(this:GetName() .. "Background"):SetVertexColor(0.1, 0.1, 0.9, 0.8);
					end
				end
			end
		end
	end
	
	
	ADKP_Bid_UpdateTable();
end

-- ================================
-- Returns true if the given player name / bid value is selected
-- in the bid list table. false otherwise. 
-- ================================
function ADKP_Bid_IsSelected(playerName, playerBid)
	playerBid = tonumber(playerBid) or 0 ; 
	for key, v in pairs(ADKP_BidList) do
		if ( type(v) == "table" ) then
			if( v["Name"] ~= nil and v["Bid"] ~= nil ) then
				if ( v["Name"] == playerName and v["Bid"] == playerBid ) then 
					return v["Selected"];
				end
			end
		end
	end
	return false;
end

-- ================================
-- Deselects all entries in the table
-- ================================
function ADKP_Bid_DeselectAll()
	for key, v in pairs(ADKP_BidList) do
		if ( type(v) == "table" ) then
			if( v["Name"] ~= nil and v["Bid"] ~= nil ) then
				v["Selected"] = false;
			end
		end
	end
end

-- ================================
-- Called when a player clicks on a column header on the table
-- Changes the sorting options / asc&desc. 
-- Causes the table display to be refreshed afterwards
-- to player instantly sees changes
-- ================================
function ADKP_Bid_SortBy(id)
	if ( ADKP_BidSort["curr"] == id ) then
		ADKP_BidSort["way"] = abs(ADKP_BidSort["way"]-1);
	else
		ADKP_BidSort["curr"] = id;
		if( id == 1) then
			ADKP_BidSort["way"] = 0;
		elseif ( id == 2 ) then
			ADKP_BidSort["way"] = 1; --columns with numbers need to be sorted different first in order to get DESC right
		elseif ( id == 3 ) then
			ADKP_BidSort["way"] = 1; --columns with numbers need to be sorted different first in order to get DESC right
		else
			ADKP_BidSort["way"] = 1; --columns with numbers need to be sorted different first in order to get DESC right
		end
		
	end
	-- update table so we can see sorting changes
	ADKP_Bid_UpdateTable();
end



-- ================================
-- Rerenders the sorted table to the screen. This is called 
-- on a few instances - when the scroll frame throws an 
-- event or when bids are placed or when a bid ends. 
-- General structure:
-- First runs through the table to display and puts the data
-- into a temp array to work with
-- Then uses sorting options to sort the temp array
-- Calculates the offset of the table to determine
-- what information needs to be displayed and in what lines 
-- of the table it should be displayed
-- ================================
local function ADKP_Bid_GetTransmogEmptyText()
	if not ADKP_BidTransmogEmptyText and ADKP_BidFrame and ADKP_BidFrameScrollFrame then
		local overlay = CreateFrame("Frame", "ADKP_BidTransmogEmptyOverlay", ADKP_BidFrame)
		overlay:SetAllPoints(ADKP_BidFrameScrollFrame)
		overlay:SetFrameLevel(ADKP_BidFrameScrollFrame:GetFrameLevel() + 5)
		local text = overlay:CreateFontString("ADKP_BidTransmogEmptyText", "OVERLAY", "GameFontNormalLarge")
		text:SetPoint("CENTER", overlay, "CENTER", -8, 0)
		text:SetText("Roll点或打HH进行幻化登记")
		text:SetTextColor(1, 0.82, 0)
		text:Hide()
		ADKP_BidTransmogEmptyText = text
	end
	return ADKP_BidTransmogEmptyText
end

function ADKP_Bid_UpdateTable()
	-- Copy data to the temporary array
	local entries = { };
	for key_name, v in pairs(ADKP_BidList) do
		if ( type(v) == "table" ) then
			if ADKP_TransmogMode and v["Name"] ~= nil and v["Kind"] ~= nil then
				tinsert(entries, v);
			elseif( v["Name"] ~= nil and v["Bid"] ~= nil and v["DKP"] ~=nil and v["Post"] ~=nil) then
				tinsert(entries,{v["Name"],v["Bid"],v["DKP"],v["Post"],v["Date"],v["OverBid"]}); -- copies over name, bid, dkp, dkp-bid
			end
		end
	end
	
	-- SORT
	table.sort(
		entries,
		function(a1, a2) 
			if ( a1 and a2 ) then
				if ADKP_TransmogMode then
					if a1["Kind"] ~= a2["Kind"] then
						return a1["Kind"] == "hh";
					end
					if a1["Kind"] == "roll" and a1["Roll"] ~= a2["Roll"] then
						return a1["Roll"] > a2["Roll"];
					end
					return a1["Sequence"] < a2["Sequence"];
				end
				if ( ADKP_BidSort["way"] == 1 ) then
					if ( a1[ADKP_BidSort["curr"]] == a2[ADKP_BidSort["curr"]] ) then
						return a1[1] > a2[1];
					else
						return a1[ADKP_BidSort["curr"]] > a2[ADKP_BidSort["curr"]];
					end
				else
					if ( a1[ADKP_BidSort["curr"]] == a2[ADKP_BidSort["curr"]] ) then
						return a1[1] < a2[1];
					else
						return a1[ADKP_BidSort["curr"]] < a2[ADKP_BidSort["curr"]];
					end
				end
			end
		end
	);
	
	local numEntries = getn(entries);
	local offset = FauxScrollFrame_GetOffset(ADKP_BidFrameScrollFrame);
	FauxScrollFrame_Update(ADKP_BidFrameScrollFrame, numEntries, 13, 13);
	local emptyText = ADKP_Bid_GetTransmogEmptyText()
	if emptyText then
		if ADKP_TransmogMode and numEntries == 0 then
			emptyText:Show()
		else
			emptyText:Hide()
		end
	end
	
	local firstHighestBidder, highestBid = nil, 0;
	if not ADKP_TransmogMode then
		firstHighestBidder, highestBid = ADKP_Bid_GetHighestBid();
	end
	
	-- Run through the table lines and put the appropriate information into each line
	for i=1, 13, 1 do
		local line = getglobal("ADKP_BidFrameLine" .. i);
		local nameText = getglobal("ADKP_BidFrameLine" .. i .. "Name");
		local bidText = getglobal("ADKP_BidFrameLine" .. i .. "Bid");
		local dkpText = getglobal("ADKP_BidFrameLine" .. i .. "DKP");
		local postBidText = getglobal("ADKP_BidFrameLine" .. i .. "Post");
		local index = i + offset; 
		
		if ( index <= numEntries) then
			local entry = entries[index];
			local playerName = ADKP_TransmogMode and entry["Name"] or entry[1];
			local bidAmount = ADKP_TransmogMode and (entry["Kind"] == "hh" and "HH" or "Roll") or entry[2];
			local isOverBid = not ADKP_TransmogMode and (entry[6] or false);
			line:Show();
			line.ADKP_BidEntry = ADKP_TransmogMode and entry or nil;
			
			-- 设置玩家名字，带职业染色
			local playerClass = ADKP_GetPlayerClass(playerName);
			local classColors = {
				WARRIOR = {r = 0.78, g = 0.61, b = 0.43},
				MAGE = {r = 0.41, g = 0.8, b = 0.94},
				ROGUE = {r = 1, g = 0.96, b = 0.41},
				DRUID = {r = 1, g = 0.49, b = 0.04},
				HUNTER = {r = 0.67, g = 0.83, b = 0.45},
				SHAMAN = {r = 0.14, g = 0.35, b = 1},
				PRIEST = {r = 1, g = 1, b = 1},
				WARLOCK = {r = 0.58, g = 0.51, b = 0.79},
				PALADIN = {r = 0.96, g = 0.55, b = 0.73},
				["战士"] = {r = 0.78, g = 0.61, b = 0.43},
				["法师"] = {r = 0.41, g = 0.8, b = 0.94},
				["盗贼"] = {r = 1, g = 0.96, b = 0.41},
				["潜行者"] = {r = 1, g = 0.96, b = 0.41},
				["德鲁伊"] = {r = 1, g = 0.49, b = 0.04},
				["猎人"] = {r = 0.67, g = 0.83, b = 0.45},
				["萨满"] = {r = 0.14, g = 0.35, b = 1},
				["牧师"] = {r = 1, g = 1, b = 1},
				["术士"] = {r = 0.58, g = 0.51, b = 0.79},
				["圣骑士"] = {r = 0.96, g = 0.55, b = 0.73}
			};
			local color = {r = 1, g = 1, b = 1};
			if playerClass then
				color = classColors[playerClass] or classColors[string.upper(playerClass)] or {r = 1, g = 1, b = 1};
			end
			nameText:SetText(playerName);
			nameText:SetTextColor(color.r, color.g, color.b);
			
			if type(bidAmount) == "number" then
				bidText:SetText(ADKP_Bid_FormatAmount(bidAmount));
			else
				bidText:SetText(bidAmount);
			end
			if ADKP_TransmogMode then
				dkpText:SetText(entry["Kind"] == "hh" and "-" or entry["Roll"]);
				local repeatCount = table.getn(entry["RepeatRolls"] or {});
				if entry["Kind"] == "hh" then
					postBidText:SetText("优先");
				elseif repeatCount > 0 then
					postBidText:SetText("重复" .. repeatCount .. "次");
				else
					postBidText:SetText("首次");
				end
			else
				dkpText:SetText(entry[3]);
				postBidText:SetText(entry[4]);
			end
			dkpText:SetTextColor(1, 1, 1, 1);
			postBidText:SetTextColor(1, 1, 1, 1);
			-- 根据选择状态设置背景颜色
			local selected = ADKP_TransmogMode and entry["Selected"] or ADKP_Bid_IsSelected(playerName, entry[2]);
			if selected then
				getglobal("ADKP_BidFrameLine" .. i .. "Background"):SetVertexColor(0.1, 0.1, 0.9, 0.8); -- 选中状态
			else
				getglobal("ADKP_BidFrameLine" .. i .. "Background"):SetVertexColor(0, 0, 0, 0); -- 未选中状态
			end
			-- 如果是超分出价，设置出价文本为红色
			if ADKP_TransmogMode and entry["Kind"] == "hh" then
				bidText:SetTextColor(0, 1, 0, 1);
			elseif isOverBid then
				bidText:SetTextColor(1, 0, 0, 1); -- 红色
			elseif bidAmount == highestBid and playerName == firstHighestBidder then
				bidText:SetTextColor(0, 1, 0, 1); -- 最高分，绿色
			else
				bidText:SetTextColor(1, 1, 1, 1); -- 其他出价，白色
			end
		else
			-- if the line isn't in use, hide it so we dont' have mouse overs
			line.ADKP_BidEntry = nil;
			line:Hide();
		end
	end
end
-- ================================
-- Handles chat messages directed towards bidding. This includes
-- placing a bid and remotly starting / stopping a bid.
-- ================================
local function ADKP_Bid_HandleItemCommand(name, trigger)
	local prefix
	if string.find(trigger, "^`") then prefix = "`"
	elseif string.find(trigger, "^·") then prefix = "·"
	else return false end
	-- Only the recorder's own messages may start or extend the auction.
	if name ~= UnitName("player") then return true end

	local body = string.sub(trigger, string.len(prefix) + 1)
	local _, _, itemPart, timePart = string.find(body, "^(.-)%s+(%d+)$")
	local countdownTime = 0
	if itemPart and timePart then
		local value = tonumber(timePart) or 0
		countdownTime = value < 10 and 30 or value
	else
		itemPart = body
	end
	local items = ADKP_Bid_ParseItems(itemPart)
	local timerActive = ADKP_BidQueueTimer and ADKP_BidQueueTimer:GetScript("OnUpdate")
	local pendingSort = ADKP_BidLootSort.entries ~= nil
	local busy = ADKP_bidInProgress or ADKP_TransmogMode or ADKP_Bid_Unfinished
		or timerActive or table.getn(ADKP_BidQueue) > 0 or pendingSort
	if table.getn(items) == 0 then
		if busy then ADKP_Bid_ShowUI()
		else ADKP_SendWhisper(name, "您必须指定一个要竞标的物品。示例：" .. prefix .. "[装备1][装备2] 20") end
		return true
	end
	if busy then
		-- Chat additions follow the entire pending loot batch, outside its sort.
		local queue = pendingSort and ADKP_BidLootSort.appended or ADKP_BidQueue
		for i = 1, table.getn(items) do
			table.insert(queue, { item = items[i], time = countdownTime })
		end
		ADKP_Print("已将 " .. table.getn(items) .. " 件装备加入拍卖队列末尾")
		if not pendingSort then ADKP_Bid_ShowUI() end
	else
		ADKP_BidQueue = {}
		for i = 2, table.getn(items) do
			table.insert(ADKP_BidQueue, { item = items[i], time = countdownTime })
		end
		if table.getn(items) > 1 then
			ADKP_Print("已将 " .. (table.getn(items) - 1) .. " 件装备加入拍卖队列")
		end
		ADKP_Bid_StartBid(items[1], countdownTime)
	end
	return true
end

function ADKP_Bid_Event()
	local name, trigger = arg2, arg1
	if ADKP_Bid_HandleItemCommand(name, trigger) then return end
	if not ADKP_IsBidChat(name, trigger) or not ADKP_bidInProgress then return end
	local bidAmount
	if tonumber(trigger) then
		bidAmount = tonumber(trigger)
	elseif string.match(trigger, "^%d+%s*[Pp]$") then
		bidAmount = tonumber(string.match(trigger, "^(%d+)"))
	elseif string.lower(trigger) == "sh" then
		bidAmount = ADKP_Bid_NormalizeAmount(ADKP_GetDKP(name))
		if not ADKP_IsAnonymousAuction() then
			ADKP_SendChatMessage("|cff00FF00" .. name .. " 梭哈 出分 " .. ADKP_Bid_FormatAmount(bidAmount) .. "分|r", "RAID")
		end
	end
	if bidAmount and bidAmount >= 0 then ADKP_Bid_HandleBid(name, bidAmount) end
end


function ADKP_Bid_HandleTransmogChat(chatEvent, name, message)
	if not ADKP_TransmogMode then return end
	if chatEvent ~= "CHAT_MSG_RAID" and chatEvent ~= "CHAT_MSG_RAID_LEADER" and chatEvent ~= "CHAT_MSG_RAID_WARNING" then return end
	if not name or string.lower(ADKP_Bid_Trim(message)) ~= "hh" then return end

	for _, entry in pairs(ADKP_BidList) do
		if type(entry) == "table" and entry["Name"] == name and entry["Kind"] == "hh" then
			return
		end
	end

	ADKP_TransmogSequence = ADKP_TransmogSequence + 1
	table.insert(ADKP_BidList, {
		["Name"] = name,
		["Bid"] = 101,
		["Kind"] = "hh",
		["Sequence"] = ADKP_TransmogSequence,
		["RepeatRolls"] = {},
		["Selected"] = false
	})
	ADKP_Bid_UpdateTable()
end

local function ADKP_Bid_ParseRollMessage(message)
	if not message then return nil end
	if RANDOM_ROLL_RESULT then
		local pattern = string.gsub(RANDOM_ROLL_RESULT, "%%s", "\001")
		pattern = string.gsub(pattern, "%%d", "\002")
		pattern = string.gsub(pattern, "([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
		pattern = string.gsub(pattern, "\001", "(.+)")
		pattern = string.gsub(pattern, "\002", "(%%d+)")
		local name, roll, minimum, maximum = string.match(message, "^" .. pattern .. "$")
		if name then return ADKP_Bid_Trim(name), tonumber(roll), tonumber(minimum), tonumber(maximum) end
	end

	local name, roll, minimum, maximum = string.match(message, "^(.+) rolls (%d+) %((%d+)%-(%d+)%)$")
	if not name then
		name, roll, minimum, maximum = string.match(message, "^(.+)掷出(%d+)（(%d+)%-(%d+)）$")
	end
	if not name then return nil end
	return ADKP_Bid_Trim(name), tonumber(roll), tonumber(minimum), tonumber(maximum)
end

function ADKP_Bid_HandleRollMessage(message)
	if not ADKP_TransmogMode then return end
	local name, roll, minimum, maximum = ADKP_Bid_ParseRollMessage(message)
	if not name or minimum ~= 1 or maximum ~= 100 or not roll then return end

	for _, entry in pairs(ADKP_BidList) do
		if type(entry) == "table" and entry["Name"] == name and entry["Kind"] == "roll" then
			table.insert(entry["RepeatRolls"], tostring(roll))
			ADKP_Bid_UpdateTable()
			return
		end
	end

	ADKP_TransmogSequence = ADKP_TransmogSequence + 1
	table.insert(ADKP_BidList, {
		["Name"] = name,
		["Bid"] = roll,
		["Roll"] = roll,
		["Kind"] = "roll",
		["Sequence"] = ADKP_TransmogSequence,
		["RepeatRolls"] = {},
		["Selected"] = false
	})
	ADKP_Bid_UpdateTable()
end

function ADKP_Bid_IsTransmogMode()
	return ADKP_TransmogMode
end


-- ================================
-- Returns true if the passed whisper is a chat message directed
-- towards web dkp bidding
-- ================================
function ADKP_IsBidChat(name, trigger)
    -- 检查 trigger 是否为纯数字或数字加上 'P' 或 'p'，或者是梭哈命令 'sh' 或 'SH'
    if (tonumber(trigger) ~= nil or string.match(trigger, "^%d+%s*[Pp]$") or string.lower(trigger) == "sh") then
        return true
    end

    -- 使用 string.lower(trigger) 进行不区分大小写的匹配
    if (string.find(string.lower(trigger), "·") == 1 or
        string.find(string.lower(trigger), "`") == 1 or
        string.find(string.lower(trigger), "?stopbid") == 1) then
        return true
    end

    return false
end
-- ================================
-- Triggers Bidding to Start
-- ================================
function ADKP_Bid_StartBid(item, time)
	if ADKP_TransmogMode then
		ADKP_Print("请先完成当前物品的幻化分配")
		return false
	end
	ADKP_BidFrameBidButton:SetText("停止竞拍");

	ADKP_BidList = {};
	if (time == "" or time == nil or time=="0" or time==" ") then
		time = 0 ; 
	end
	
	local quality, itemName, itemLink = ADKP_GetItemInfo(item);
	ADKP_Bid_ActionRevision = ADKP_Bid_ActionRevision + 1
	ADKP_Bid_Unfinished = true
	ADKP_bidItem = itemName;
	ADKP_BidFrameItem:SetText(itemName);
	ADKP_Bid_ShowItemDisplay();
	ADKP_Bid_RequestItemRefresh(itemLink);
	-- 队列剩余数量显示（独立的文本，不影响物品栏和通告）
	ADKP_Bid_UpdateQueueLabel()
	ADKP_BidFrameTime:SetText(time);
	
	ADKP_AnnounceBidStart(itemLink, time);
	ADKP_bidInProgress = true;
	if ADKP_QuickFloat_UpdateBidGlow then ADKP_QuickFloat_UpdateBidGlow() end
	ADKP_Bid_StartAnonTicker();
	
	ADKP_Bid_UpdateTable();
	ADKP_Bid_ShowUI();
	
	if(time ~= 0 ) then 
		ADKP_bidCountdown = time;
		ADKP_Bid_UpdateFrame:Show();
	else
		ADKP_Bid_UpdateFrame:Hide();
	end

	return true
end


local function ADKP_Bid_StartNextQueuedItem()
	if ADKP_BidQueueTimer and ADKP_BidQueueTimer:GetScript("OnUpdate") then return end
	if table.getn(ADKP_BidQueue) == 0 then return end
	local nextEntry = table.remove(ADKP_BidQueue, 1)
	ADKP_Bid_UpdateQueueLabel()
	local remaining = table.getn(ADKP_BidQueue)
	ADKP_Print("队列中还有 " .. remaining .. " 件装备待拍卖，1.5秒后自动开始下一件...")
	if not ADKP_BidQueueTimer then
		ADKP_BidQueueTimer = CreateFrame("Frame")
	end
	ADKP_BidQueueTimer.delay = 1.5
	ADKP_BidQueueTimer:SetScript("OnUpdate", function()
		local elapsed = tonumber(arg1) or 0
		this.delay = this.delay - elapsed
		if this.delay <= 0 then
			this:SetScript("OnUpdate", nil)
			ADKP_Bid_StartBid(nextEntry.item, nextEntry.time)
			ADKP_BidFrameBidButton:SetText("停止竞拍")
		end
	end)
end


-- ================================
-- Stops the current bidding
-- ================================
function ADKP_Bid_StopBid(holdQueue)
		ADKP_Bid_ActionRevision = ADKP_Bid_ActionRevision + 1
		
		ADKP_Bid_UpdateFrame:Hide();								-- stop any countdowns
		ADKP_BidFrame_Countdown:SetText("");
		
		ADKP_BidFrameBidButton:SetText("开始竞拍!");		-- fix the button text
		local bidder, bid = ADKP_Bid_GetHighestBid();					-- find highest bidder (not used any more)
		ADKP_AnnounceBidEnd(ADKP_bidItem, bidder, bid);			-- make the announcement
		ADKP_bidInProgress = false;
		if ADKP_QuickFloat_UpdateBidGlow then ADKP_QuickFloat_UpdateBidGlow() end
		ADKP_Bid_StopAnonTicker();							
		ADKP_Bid_ShowUI();										-- how the bid gui

		if not holdQueue then ADKP_Bid_StartNextQueuedItem() end

end


-- ================================
-- Manual countdown helper (6s or stop) - only sends raid notifications
-- ================================
local function ADKP_ManualCountdown_SetButtonLabel(isRunning)
	local btn = getglobal("ADKP_BidFrameManualCountdownButton")
	if btn then
		if isRunning then
			btn:SetText("停止倒计时")
		else
			btn:SetText("倒计时")
		end
	end
end

function ADKP_ManualCountdown_Stop()
	ADKP_ManualCountdownRunning = false
	ADKP_ManualCountdownValue = 0
	ADKP_ManualCountdown_SetButtonLabel(false)
	if ADKP_ManualCountdownFrame then
		ADKP_ManualCountdownFrame:SetScript("OnUpdate", nil)
		ADKP_ManualCountdownFrame.timeSinceLastUpdate = 0
	end
end

function ADKP_ManualCountdown_Start()
	if ADKP_ManualCountdownRunning then
		return
	end

	ADKP_ManualCountdownRunning = true
	ADKP_ManualCountdownValue = 6
	ADKP_ManualCountdown_SetButtonLabel(true)

	-- Always notify the raid/party regardless of silent mode; include current item link/name
	local _, _, link = ADKP_GetItemInfo(ADKP_bidItem)
	local itemText = link or ADKP_bidItem or "装备"
	ADKP_SendCountdownMessage("竞拍装备 " .. itemText .. " 倒计时")

	ADKP_ManualCountdownFrame = ADKP_ManualCountdownFrame or CreateFrame("Frame")
	ADKP_ManualCountdownFrame.timeSinceLastUpdate = 0
	ADKP_ManualCountdownFrame:SetScript("OnUpdate", function()
		local elapsed = tonumber(arg1) or 0
		this.timeSinceLastUpdate = (this.timeSinceLastUpdate or 0) + elapsed
		if this.timeSinceLastUpdate < 1 then
			return
		end

		this.timeSinceLastUpdate = 0
		ADKP_ManualCountdownValue = ADKP_ManualCountdownValue - 1

		if ADKP_ManualCountdownValue > 0 then
			ADKP_SendCountdownMessage("倒计时" .. ADKP_ManualCountdownValue .. "秒")
		else
			ADKP_SendCountdownMessage("手动倒计时结束")
			ADKP_ManualCountdown_Stop()
		end
	end)
end

function ADKP_ManualCountdown_Toggle()
	if ADKP_ManualCountdownRunning then
		ADKP_SendCountdownMessage("手动倒计时已停止")
		ADKP_ManualCountdown_Stop()
	else
		ADKP_ManualCountdown_Start()
	end
end

-- ================================
-- 超分出价随机吐槽文案（%s 依次为：玩家名、出价分、当前分）
-- ================================
local ADKP_OVERBID_MESSAGES = {
    "%s 出价 %s 分，想屁吃呢？你总共也就 %s 分，出价无效。",
    "%s 出价 %s 分，收手吧阿祖！你总共也就 %s 分，抢不动这件装备的。",
    "%s 出价 %s 分，醒醒！你总共也就 %s 分，这个价格你高攀不起",
    "%s 出价 %s 分，余额  %s 分无法满足你膨胀的野心。",
    "%s 出价 %s 分，你只有 %s 分，别冲动！",
    "%s 出价 %s 分，梦想翻车！你只有 %s 分，要不先观望一下？",
    "%s 出价 %s 分，分数不够冲不动！你只剩 %s 分啦。",
    "%s 出价 %s 分，快按住你的手！你就  %s 分，抢不起嗷！",
    "%s 出价 %s 分，理想很丰满，DKP 很骨感！当前分数： %s 分",
    "%s 出价 %s 分，刹车！你的 DKP %s 分已经追不上你的野心了",
    "%s 出价 %s 分，梦里啥都有，但你现实只有%s分 .",
}
math.randomseed(math.floor(GetTime() * 100000))

function ADKP_Bid_GetOverBidMessage(playerName, bidAmount, dkp)
    local idx = math.random(1, table.getn(ADKP_OVERBID_MESSAGES))
    return string.format(ADKP_OVERBID_MESSAGES[idx], playerName, bidAmount, dkp)
end

-- ================================
-- Handles a bid placed by a player.
-- ================================
function ADKP_Bid_HandleBid(playerName, bidAmount)
    -- 如果竞标未进行，忽略出价
    if (ADKP_bidInProgress) then
        bidAmount = ADKP_Bid_NormalizeAmount(bidAmount)
        local dkp = ADKP_Bid_NormalizeAmount(ADKP_GetDKP(playerName));  -- 获取玩家当前 DKP（同样规范化，避免浮点累加误差导致 sh 误判超分）

        -- 检查出价是否超过当前 DKP
        local isOverBid = false
        if (bidAmount > dkp) then
            local message = ADKP_Bid_GetOverBidMessage(playerName, bidAmount, dkp)
            if not ADKP_IsAnonymousAuction() then ADKP_SendChatMessage("|cffff0000" .. message .. "|r", "RAID"); end  -- 团队频道广播
            ADKP_SendWhisper(playerName, message);  -- 私发消息
            isOverBid = true
            
            -- 用绿色文字提醒超分出价不被标记为最高分
            local _,_,link = ADKP_GetItemInfo(ADKP_bidItem);
            if not ADKP_IsAnonymousAuction() then
                ADKP_SendChatMessage("|cff00FF00" ..  " 超分出价 " .. bidAmount .. " 分不会被标记为目前最高分！".. "|r", "RAID");
            end
        end
        
        -- 保留小数出价，不做四舍五入

        -- 检查玩家的出价是否已经记录
        local existingBidIndex = nil

        for index, v in ipairs(ADKP_BidList) do
            if v["Name"] == playerName and v["Bid"] == bidAmount then
                -- 如果同一玩家已出相同分数，记录其索引
                existingBidIndex = index
				
                break
            end
        end

        -- 如果出价重复，通知玩家并忽略出价
        if existingBidIndex then
            -- ADKP_SendChatMessage(playerName, playerName .. " 你已经出过 " .. bidAmount .. " 分，重复出价无效。", "RAID");
            return;  -- 直接返回，不再处理该出价
        else
            -- 如果出价未重复，添加新的出价记录
            local postDkp = dkp - bidAmount;  -- 计算出价后的 DKP
            local date = date("%Y-%m-%d %H:%M:%S");  -- 记录出价时间
            
            -- 在列表末尾添加新的出价记录
            table.insert(ADKP_BidList, {
                ["Name"] = playerName,
                ["Bid"] = bidAmount,
                ["DKP"] = dkp,
                ["Post"] = postDkp,
                ["Date"] = date,
                ["Selected"] = false,  -- 初始化为未选中
                ["OverBid"] = isOverBid -- 标记是否超分
            })

            ADKP_Bid_UpdateTable();  -- 更新出价表
            
            -- 只在进入倒计时阶段(≤10秒)才重置计时为10秒
            if (ADKP_bidCountdown <= 10 and ADKP_bidCountdown > 0) then
                ADKP_bidCountdown = 10;
                ADKP_BidFrame_Countdown:SetText("Time Left: "..ADKP_bidCountdown.."s");
                
                -- 获取当前最高出价者和出价
                local highestBidder, highestBid = ADKP_Bid_GetHighestBid();
                
                if (highestBidder and highestBid > 0) then
                    -- 显示绿色消息：现在最高分是某某出的XX分，倒计时重置为10秒！

                    if ADKP_IsAnonymousAuction() then ADKP_SendChatMessage("|cff00FF00" .. "现在最高有效出分为 "..highestBid.." 分，倒计时重置为10秒！".. "|r", "RAID"); else ADKP_SendChatMessage("|cff00FF00" .. "现在最高分是 "..highestBidder.." 出的 "..highestBid.." 分，倒计时重置为10秒！".. "|r", "RAID"); end
                else
                    -- 如果没有人出过价
                    local _,_,link = ADKP_GetItemInfo(ADKP_bidItem);
                    ADKP_SendChatMessage(link.." 目前无人出分，现在开始倒计时", "RAID");
                end
            end
        end
    end
end
-- ================================
-- Sends a message to the specified chat channel
-- ================================
function ADKP_SendChatMessage(message, channel)
    -- 静默模式下，不发送团队/队伍/公会播报，仅本地显示
    local isSilentMode = WebDKP_Options and WebDKP_Options["SilentMode"]
    if isSilentMode and (channel == "RAID" or channel == "RAID_WARNING" or channel == "RAID_LEADER" or channel == "PARTY" or channel == "GUILD") then
        if ADKP_Print then
            ADKP_Print("[静默] " .. message)
        end
        return
    end
    SendChatMessage(message, channel);  -- 发送消息到指定频道
end

-- ================================
-- Returns the highest bidder and what they bid. 
-- ================================
function ADKP_Bid_GetHighestBid()
	local highestBidder = nil;
	local highestBid = 0; 

	for key_name, v in pairs(ADKP_BidList) do
		if ( type(v) == "table" ) then
			if( key_name ~= nil and v["Bid"] ~= nil and v["DKP"] ~=nil and v["Post"] ~=nil) then
				-- 忽略超分出价
				if (v["OverBid"] ~= true and v["Bid"] > highestBid ) then
					highestBidder = v["Name"];
					highestBid = v["Bid"];
				end
			end
		end
	end
	return highestBidder, highestBid;
end

local function ADKP_Bid_GetCurrentItemLink()
	local _, itemName, itemLink = ADKP_GetItemInfo(ADKP_bidItem)
	return itemLink, itemName or ADKP_bidItem
end

local function ADKP_Bid_ValidateAssignment(playerName, waitForLoot)
	-- 记录和选择目标不要求分配权限，真正分配物品时再检查。
	local itemLink, itemName = ADKP_Bid_GetCurrentItemLink()
	if not itemLink then
		ADKP_Print("无法读取当前竞拍物品链接")
		PlaySound("igQuestFailed")
		return nil
	end
	if waitForLoot then return itemLink end
	if not GetNumLootItems or GetNumLootItems() == 0 then
		ADKP_Print("请先打开包含当前竞拍物品的掉落窗口")
		PlaySound("igQuestFailed")
		return nil
	end
	local foundItemSlot = nil
	for i = 1, GetNumLootItems() do
		local lootLink = GetLootSlotLink(i)
		if lootLink then
			local _, lootName = ADKP_GetItemInfo(lootLink)
			if lootName == itemName then
				foundItemSlot = i
				break
			end
		end
	end
	if not foundItemSlot then
		ADKP_Print("掉落窗口中找不到当前竞拍物品")
		PlaySound("igQuestFailed")
		return nil
	end

	local foundPlayerIndex = nil
	if playerName then
		for i = 1, 40 do
			if GetMasterLootCandidate(i) == playerName then
				foundPlayerIndex = i
				break
			end
		end
		if not foundPlayerIndex then
			ADKP_Print(playerName .. " 当前不在该物品的可分配名单中")
			PlaySound("igQuestFailed")
			return nil
		end
	end
	return itemLink, foundItemSlot, foundPlayerIndex
end

local function ADKP_Bid_RecordItem(player, bid, announceAward, skipAutoLoot)
	local points = (tonumber(bid) or 0) * -1
	local playerTable = { [0] = {
		["name"] = player,
		["class"] = ADKP_GetPlayerClass(player),
	}}
	local recordRef = ADKP_AddDKP(points, ADKP_bidItem, "true", playerTable, ADKP_GetTableid())
	if announceAward then
		ADKP_AnnounceAwardItem(points, ADKP_bidItem, player, skipAutoLoot, recordRef)
	end
	ADKP_UpdateTableToShow()
	ADKP_UpdateTable()
	PlaySound("LOOTWINDOWCOINSOUND")
	return recordRef
end

local function ADKP_Bid_AnnounceGroup(message, useRaidWarning)
	local location = ADKP_GetTellLocation()
	if location == "NONE" then
		ADKP_Print(message)
	else
		ADKP_SendAnnouncement(message, location, useRaidWarning)
	end
end

local function ADKP_Bid_SetTransmogUI(active)
	if active then
		ADKP_BidFrameAward:Hide()
		ADKP_BidFramePass:Hide()
		ADKP_BidFrameTransmog:SetText("授予幻化")
		ADKP_BidFrameTransmog:ClearAllPoints()
		ADKP_BidFrameTransmog:SetPoint("BOTTOMRIGHT", ADKP_BidFrame, "BOTTOM", -4, 10)
		ADKP_BidFrameEndTransmog:ClearAllPoints()
		ADKP_BidFrameEndTransmog:SetPoint("BOTTOMLEFT", ADKP_BidFrame, "BOTTOM", 4, 10)
		ADKP_BidFrameEndTransmog:Show()
		ADKP_BidFrameBidButton:Disable()
		ADKP_BidFrameManualCountdownButton:Enable()
		ADKP_BidFrameAnnounceHighButton:Disable()
		ADKP_BidFrameAnnounceHighButton:Hide()
		ADKP_BidFrameNameLabel:SetText("玩家")
		ADKP_BidFrameNameListTitle:SetText("幻化参与列表:")
		ADKP_BidFrameBidLabel:SetText("方式")
		ADKP_BidFrameDKPLabel:SetText("点数")
		ADKP_BidFramePostLabel:SetText("备注")
	else
		ADKP_BidFrameAward:Show()
		ADKP_BidFramePass:Show()
		ADKP_BidFrameEndTransmog:Hide()
		ADKP_BidFrameTransmog:SetText("记录并幻化")
		ADKP_BidFrameTransmog:ClearAllPoints()
		ADKP_BidFrameTransmog:SetPoint("LEFT", ADKP_BidFrameAward, "RIGHT", 8, 0)
		ADKP_BidFrameBidButton:Enable()
		ADKP_BidFrameManualCountdownButton:Enable()
		ADKP_BidFrameAnnounceHighButton:Enable()
		if ADKP_UpdateAuctionModeControls then ADKP_UpdateAuctionModeControls() end
		ADKP_BidFrameNameLabel:SetText("名字")
		ADKP_BidFrameNameListTitle:SetText("需求竞拍列表:")
		ADKP_BidFrameBidLabel:SetText("出分")
		ADKP_BidFrameDKPLabel:SetText("DKP")
		ADKP_BidFramePostLabel:SetText("出分后剩余DKP")
	end
	ADKP_BidFrameScrollFrame:SetVerticalScroll(0)
	ADKP_Bid_UpdateTable()
end

function ADKP_Bid_ShowTransmogButtonTooltip(cancel)
	if not this then return end
	if not ADKP_BidTransmogTooltip then
		ADKP_BidTransmogTooltip = CreateFrame("GameTooltip", "ADKP_BidTransmogTooltip", UIParent, "GameTooltipTemplate")
		if ADKP_BidTransmogTooltip.SetClampedToScreen then ADKP_BidTransmogTooltip:SetClampedToScreen(true) end
	end
	local tip = ADKP_BidTransmogTooltip
	tip:SetOwner(this, "ANCHOR_RIGHT")
	tip:ClearLines()
	if cancel or ADKP_TransmogMode then
		tip:SetText(cancel and "取消幻化" or "授予幻化", 1, 1, 1)
		if not cancel then tip:AddLine("选择幻化参与者后，左键分配物品", 0.8, 0.8, 0.8, true) end
		tip:AddLine("装备竞拍已经完成，幻化的授予和取消不影响之前拍分", 1, 0.82, 0, true)
	else
		tip:SetText("记录并幻化", 1, 1, 1)
		tip:AddLine("左键：记录选中出分；未选择时以0分开始幻化", 0.8, 0.8, 0.8, true)
		tip:AddLine("右键：从分配目标菜单选择幻化玩家", 0.8, 0.8, 0.8, true)
	end
	-- 独立提示框固定正文宽度并换行，不改变物品提示框的排版。
	for i = 1, tip:NumLines() do
		local line = getglobal("ADKP_BidTransmogTooltipTextLeft" .. i)
		if line then line:SetWidth(260); line:SetJustifyH("LEFT") end
	end
	tip:Show()
	tip:SetWidth(284)
end

function ADKP_Bid_HideTransmogButtonTooltip()
	if ADKP_BidTransmogTooltip then ADKP_BidTransmogTooltip:Hide() end
end

local function ADKP_Bid_ResetSpecialUI()
	ADKP_Bid_ActionRevision = ADKP_Bid_ActionRevision + 1
	ADKP_Bid_Unfinished = false
	ADKP_TransmogMode = false
	if ADKP_QuickFloat_UpdateBidGlow then ADKP_QuickFloat_UpdateBidGlow() end
	ADKP_Bid_HideTransmogButtonTooltip()
	ADKP_TransmogSequence = 0
	ADKP_TransmogRecordOnAward = false
	ADKP_TransmogRecordRef = nil
	ADKP_BidList = {}
	ADKP_Bid_SetTransmogUI(false)
	ADKP_Bid_HideUI()
end

local function ADKP_Bid_FinishSpecialAssignment()
	ADKP_Bid_ResetSpecialUI()
	ADKP_Bid_StartNextQueuedItem()
end

function ADKP_Bid_EndTransmogSelection()
	if not ADKP_TransmogMode then return end
	if ADKP_ManualCountdownRunning then ADKP_ManualCountdown_Stop() end
	local _, _, itemLink = ADKP_GetItemInfo(ADKP_bidItem)
	ADKP_Bid_AnnounceGroup((itemLink or ADKP_bidItem or "当前物品") .. " 幻化竞拍结束")
	ADKP_Bid_FinishSpecialAssignment()
end

local function ADKP_Bid_WaitForAssignment(itemLink, player, recordRef)
	local lootMethod, masterLooterPartyID = GetLootMethod()
	local isLooter = masterLooterPartyID == 0
	if not isLooter and masterLooterPartyID then
		isLooter = UnitName("party" .. masterLooterPartyID) == UnitName("player")
	end
	if lootMethod ~= "master" or not isLooter then
		ADKP_Print("当前不是队长分配或者没有分配权限，请竞拍完成后手动分配。")
	else
		local started = ADKP_StartAutoLoot(itemLink, player, 0, nil, nil, recordRef)
		if started == false then
			ADKP_AddUnassignedLoot(itemLink, player, "超距/副本外/已有该物品", "当前无法启动队长分配", recordRef)
		end
	end
	ADKP_Bid_ResetSpecialUI()
	ADKP_Bid_StartNextQueuedItem()
	return true
end

local function ADKP_Bid_BeginTransmogSelection(winner, bid, recordOnAward)
	local itemLink = ADKP_Bid_ValidateAssignment(nil, true)
	if not itemLink then return end

	if ADKP_ManualCountdownRunning then ADKP_ManualCountdown_Stop() end
	if ADKP_bidInProgress then ADKP_Bid_StopBid(true) end
	if winner then ADKP_TransmogRecordRef = ADKP_Bid_RecordItem(winner, bid, true, true) end

	ADKP_TransmogMode = true
	if ADKP_QuickFloat_UpdateBidGlow then ADKP_QuickFloat_UpdateBidGlow() end
	ADKP_TransmogSequence = 0
	ADKP_TransmogRecordOnAward = recordOnAward == true
	ADKP_BidList = {}
	ADKP_Bid_SetTransmogUI(true)
	ADKP_Bid_AnnounceGroup(itemLink .. " 幻化，直接Roll点或者团队打 hh 参与", true)
	ADKP_Bid_ShowUI()
end

local function ADKP_Bid_StartTransmogSelection()
	local winner, bid = ADKP_Bid_GetSelected()
	if winner then
		ADKP_Bid_BeginTransmogSelection(winner, bid, false)
		return
	end
	if not StaticPopupDialogs["ADKP_TRANSMOG_WITHOUT_BID_CONFIRM"] then
		StaticPopupDialogs["ADKP_TRANSMOG_WITHOUT_BID_CONFIRM"] = {
			text = "未选择出分玩家，是否开始幻化竞拍？",
			button1 = "确定",
			button2 = "取消",
			timeout = 0,
			whileDead = 1,
			hideOnEscape = 1,
			OnAccept = function()
				ADKP_Bid_BeginTransmogSelection(nil, 0, true)
			end
		}
	end
	StaticPopup_Show("ADKP_TRANSMOG_WITHOUT_BID_CONFIRM")
end

local function ADKP_Bid_AwardTransmogSelected()
	local player = ADKP_Bid_GetSelected()
	if not player then
		ADKP_Print("请先选中一名幻化玩家")
		PlaySound("igQuestFailed")
		return
	end
	local itemLink = ADKP_Bid_ValidateAssignment(player, true)
	if not itemLink then return end
	local recordRef = ADKP_TransmogRecordRef
	if ADKP_TransmogRecordOnAward then
		recordRef = ADKP_Bid_RecordItem(player, 0, false, true)
	end
	ADKP_Bid_AnnounceGroup(itemLink .. " 授予 " .. player .. " 幻化", true)
	ADKP_Bid_WaitForAssignment(itemLink, player, recordRef)
end

local function ADKP_Bid_ExecuteQuickTransmog(context)
	if not context or ADKP_TransmogMode or context.item ~= ADKP_bidItem then return end
	local itemLink = ADKP_Bid_ValidateAssignment(context.target, true)
	if not itemLink then return end
	if ADKP_ManualCountdownRunning then ADKP_ManualCountdown_Stop() end
	if ADKP_bidInProgress then ADKP_Bid_StopBid(true) end
	local recordRef = nil
	if context.winner then
		recordRef = ADKP_Bid_RecordItem(context.winner, context.bid, true, true)
	else
		recordRef = ADKP_Bid_RecordItem(context.target, 0, false, true)
	end
	ADKP_Bid_AnnounceGroup(itemLink .. " 授予 " .. context.target .. " 幻化", true)
	ADKP_Bid_WaitForAssignment(itemLink, context.target, recordRef)
end

local ADKP_Bid_AssignmentMenu = nil
local ADKP_Bid_AssignmentMenuPlayers = {}
local ADKP_Bid_AssignmentMenuCallback = nil
local ADKP_Bid_AssignmentMenuRecentPlayer = nil
local ADKP_Bid_AssignmentClassOrder = {
	"战士", "圣骑士", "猎人", "潜行者", "牧师",
	"萨满祭司", "法师", "术士", "德鲁伊", "未知职业"
}
local ADKP_Bid_AssignmentClassMap = {
	["Warrior"] = "战士", ["WARRIOR"] = "战士", ["战士"] = "战士",
	["Paladin"] = "圣骑士", ["PALADIN"] = "圣骑士", ["圣骑士"] = "圣骑士",
	["Hunter"] = "猎人", ["HUNTER"] = "猎人", ["猎人"] = "猎人",
	["Rogue"] = "潜行者", ["ROGUE"] = "潜行者", ["潜行者"] = "潜行者", ["盗贼"] = "潜行者",
	["Priest"] = "牧师", ["PRIEST"] = "牧师", ["牧师"] = "牧师",
	["Shaman"] = "萨满祭司", ["SHAMAN"] = "萨满祭司", ["萨满祭司"] = "萨满祭司",
	["Mage"] = "法师", ["MAGE"] = "法师", ["法师"] = "法师",
	["Warlock"] = "术士", ["WARLOCK"] = "术士", ["术士"] = "术士",
	["Druid"] = "德鲁伊", ["DRUID"] = "德鲁伊", ["德鲁伊"] = "德鲁伊"
}

local function ADKP_Bid_NormalizeAssignmentClass(className)
	return ADKP_Bid_AssignmentClassMap[className] or "未知职业"
end

local function ADKP_Bid_GetAssignmentPlayers()
	local players = {}
	local seen = {}
	local function addPlayer(playerName, className)
		if playerName and playerName ~= "" and not seen[playerName] then
			seen[playerName] = true
			table.insert(players, {
				name = playerName,
				class = ADKP_Bid_NormalizeAssignmentClass(className or ADKP_GetPlayerClass(playerName))
			})
		end
	end

	if GetNumRaidMembers() > 0 then
		for i = 1, GetNumRaidMembers() do
			local playerName, _, _, _, localizedClass, classToken = GetRaidRosterInfo(i)
			addPlayer(playerName, localizedClass or classToken)
		end
	else
		local localizedClass, classToken = UnitClass("player")
		addPlayer(UnitName("player"), localizedClass or classToken)
		for i = 1, GetNumPartyMembers() do
			localizedClass, classToken = UnitClass("party" .. i)
			addPlayer(UnitName("party" .. i), localizedClass or classToken)
		end
	end

	table.sort(players, function(a, b) return a.name < b.name end)
	return players
end

local function ADKP_Bid_FindAssignmentPlayer(playerName)
	for i = 1, table.getn(ADKP_Bid_AssignmentMenuPlayers) do
		if ADKP_Bid_AssignmentMenuPlayers[i].name == playerName then
			return ADKP_Bid_AssignmentMenuPlayers[i]
		end
	end
	return nil
end

local function ADKP_Bid_AssignmentMenuSelect()
	local playerName = this and this.value
	local callback = ADKP_Bid_AssignmentMenuCallback
	ADKP_Bid_AssignmentMenuCallback = nil
	CloseDropDownMenus()
	if playerName and callback then callback(playerName) end
end

local function ADKP_Bid_AssignmentMenuInitialize()
	local level = UIDROPDOWNMENU_MENU_LEVEL or 1
	if level == 1 then
		UIDropDownMenu_AddButton({
			text = "选择物品分配目标",
			isTitle = 1,
			notCheckable = 1
		}, level)

		local selfName = UnitName("player")
		UIDropDownMenu_AddButton({
			text = "分配给自己",
			value = selfName,
			func = ADKP_Bid_AssignmentMenuSelect,
			notCheckable = 1
		}, level)

		local recentPlayer = ADKP_Bid_FindAssignmentPlayer(ADKP_Bid_AssignmentMenuRecentPlayer)
		if recentPlayer and recentPlayer.name ~= selfName then
			UIDropDownMenu_AddButton({
				text = "上次选择：" .. ADKP_GetClassColor(recentPlayer.class) .. recentPlayer.name .. "|r",
				value = recentPlayer.name,
				func = ADKP_Bid_AssignmentMenuSelect,
				notCheckable = 1
			}, level)
		end

		for i = 1, table.getn(ADKP_Bid_AssignmentClassOrder) do
			local className = ADKP_Bid_AssignmentClassOrder[i]
			local hasPlayers = false
			for j = 1, table.getn(ADKP_Bid_AssignmentMenuPlayers) do
				if ADKP_Bid_AssignmentMenuPlayers[j].class == className then
					hasPlayers = true
					break
				end
			end
			if hasPlayers then
				UIDropDownMenu_AddButton({
					text = ADKP_GetClassColor(className) .. className .. "|r",
					value = className,
					hasArrow = 1,
					notCheckable = 1
				}, level)
			end
		end
	elseif level == 2 then
		local className = UIDROPDOWNMENU_MENU_VALUE
		for i = 1, table.getn(ADKP_Bid_AssignmentMenuPlayers) do
			local player = ADKP_Bid_AssignmentMenuPlayers[i]
			if player.class == className then
				UIDropDownMenu_AddButton({
					text = ADKP_GetClassColor(player.class) .. player.name .. "|r",
					value = player.name,
					func = ADKP_Bid_AssignmentMenuSelect,
					notCheckable = 1
				}, level)
			end
		end
	end
end

local function ADKP_Bid_OpenAssignmentMenu(callback, recentPlayer)
	ADKP_Bid_AssignmentMenuPlayers = ADKP_Bid_GetAssignmentPlayers()
	if table.getn(ADKP_Bid_AssignmentMenuPlayers) == 0 then
		ADKP_Print("当前没有可选择的分配玩家")
		PlaySound("igQuestFailed")
		return
	end
	if not ADKP_Bid_AssignmentMenu then
		ADKP_Bid_AssignmentMenu = CreateFrame("Frame", "ADKP_BidAssignmentMenu", UIParent, "UIDropDownMenuTemplate")
	end
	ADKP_Bid_AssignmentMenuCallback = callback
	ADKP_Bid_AssignmentMenuRecentPlayer = recentPlayer
	UIDropDownMenu_Initialize(ADKP_Bid_AssignmentMenu, ADKP_Bid_AssignmentMenuInitialize, "MENU")
	ToggleDropDownMenu(1, nil, ADKP_Bid_AssignmentMenu, "cursor", 0, 0)
end

local function ADKP_Bid_ShowAssignmentMenu(callback, recentPlayer)
	if not ADKP_Bid_ValidateAssignment(nil, true) then return end
	ADKP_Bid_OpenAssignmentMenu(callback, recentPlayer)
end

function ADKP_Bid_ShowAssignmentTargetMenu(callback, recentPlayer)
	ADKP_Bid_OpenAssignmentMenu(callback, recentPlayer)
end

local function ADKP_Bid_ShowQuickTransmogConfirm(target)
	local winner, bid = ADKP_Bid_GetSelected()
	if not target then
		ADKP_Print("请先选择幻化物品的分配目标")
		PlaySound("igQuestFailed")
		return
	end
	local itemLink = ADKP_Bid_ValidateAssignment(target, true)
	if not itemLink then return end
	if not StaticPopupDialogs["ADKP_QUICK_TRANSMOG_CONFIRM"] then
		StaticPopupDialogs["ADKP_QUICK_TRANSMOG_CONFIRM"] = {
			button1 = "确认",
			button2 = "取消",
			timeout = 0,
			whileDead = 1,
			hideOnEscape = 1,
			OnAccept = function()
				local dialog = StaticPopupDialogs["ADKP_QUICK_TRANSMOG_CONFIRM"]
				local context = dialog._context
				dialog._context = nil
				ADKP_Bid_ExecuteQuickTransmog(context)
			end,
			OnCancel = function()
				StaticPopupDialogs["ADKP_QUICK_TRANSMOG_CONFIRM"]._context = nil
			end
		}
	end
	local dialog = StaticPopupDialogs["ADKP_QUICK_TRANSMOG_CONFIRM"]
	if winner then
		dialog.text = "确认将 " .. itemLink .. " 分配给玩家 " .. target .. " 幻化吗？"
	else
		dialog.text = "未选择出分玩家，是否直接分配给 " .. target .. "？"
	end
	dialog._context = { winner = winner, bid = bid, target = target, item = ADKP_bidItem }
	StaticPopup_Show("ADKP_QUICK_TRANSMOG_CONFIRM")
end

function ADKP_Bid_TransmogButtonClick(mouseButton)
	if ADKP_TransmogMode then
		if mouseButton == "LeftButton" then ADKP_Bid_AwardTransmogSelected() end
	elseif mouseButton == "RightButton" then
		ADKP_Bid_ShowAssignmentMenu(ADKP_Bid_ShowQuickTransmogConfirm)
	else
		ADKP_Bid_StartTransmogSelection()
	end
end

local function ADKP_Bid_AssignPassToPlayer(player)
	if not player then
		ADKP_Print("请先选择流拍物品的分配目标")
		PlaySound("igQuestFailed")
		return
	end
	local itemLink = ADKP_Bid_ValidateAssignment(player, true)
	if not itemLink then return end
	if ADKP_ManualCountdownRunning then ADKP_ManualCountdown_Stop() end
	if ADKP_bidInProgress then ADKP_Bid_StopBid(true) end
	local recordRef = ADKP_Bid_RecordItem(player, 0, false, true)
	ADKP_Bid_AnnounceGroup(itemLink .. " 流拍，分配给 " .. player)
	ADKP_Bid_WaitForAssignment(itemLink, player, recordRef)
	return true
end

local function ADKP_Bid_PassItemRecordOnly()
	local itemLink = ADKP_Bid_ValidateAssignment(nil, true)
	if not itemLink then return end
	if ADKP_ManualCountdownRunning then ADKP_ManualCountdown_Stop() end
	if ADKP_bidInProgress then ADKP_Bid_StopBid(true) end
	ADKP_Bid_RecordItem(UnitName("player"), 0, false, true)
	ADKP_Bid_AnnounceGroup(itemLink .. " 流拍")
	ADKP_Bid_FinishSpecialAssignment()
	return true
end

local function ADKP_Bid_GetPassSettings()
	local options = WebDKP_Options or {}
	local settings = options.PassSettings and options.PassSettings[tostring(ADKP_GetTableid())]
	if settings then return settings.mode or "record", settings.player end
	-- 沿用旧版“分配给自己”的选择；使用新菜单后按 DKP 团队分别保存。
	return options.PassAssignToSelf and "self" or "record", nil
end

local function ADKP_Bid_SavePassSettings(mode, player)
	local _, previousPlayer = ADKP_Bid_GetPassSettings()
	WebDKP_Options = WebDKP_Options or {}
	WebDKP_Options.PassSettings = WebDKP_Options.PassSettings or {}
	WebDKP_Options.PassSettings[tostring(ADKP_GetTableid())] = {
		mode = mode, player = player or previousPlayer,
	}
end

local function ADKP_Bid_ExecutePass(mode, player)
	if ADKP_TransmogMode then return end
	if mode == "record" then
		if ADKP_Bid_PassItemRecordOnly() then ADKP_Bid_SavePassSettings(mode) end
		return
	end
	local target = mode == "self" and UnitName("player") or player
	local inGroup = false
	for _, member in ipairs(ADKP_Bid_GetAssignmentPlayers()) do
		if member.name == target then inGroup = true; break end
	end
	if not target or target == "" or not inGroup then
		ADKP_Print("流拍分配对象未设置或已离队，请右键流拍重新选择。")
		return
	end
	if ADKP_Bid_AssignPassToPlayer(target) then
		ADKP_Bid_SavePassSettings(mode, mode == "player" and target or nil)
	end
end

local ADKP_Bid_PassMenu = nil
local ADKP_Bid_PassMenuContext = nil
local ADKP_Bid_PassMenuGroups = {}

local function ADKP_Bid_PassMenuSelect()
	local mode = this and this.arg1
	local player = this and this.value
	local context = ADKP_Bid_PassMenuContext
	ADKP_Bid_PassMenuContext = nil
	CloseDropDownMenus()
	if not context then return end
	if context.revision ~= ADKP_Bid_ActionRevision or context.item ~= ADKP_bidItem
		or context.tableid ~= ADKP_GetTableid() or ADKP_TransmogMode then
		ADKP_Print("当前竞拍物品或状态已变化，请右键流拍重新选择。")
		return
	end
	ADKP_Bid_ExecutePass(mode, player)
end

local function ADKP_Bid_PassMenuInitialize()
	local level = UIDROPDOWNMENU_MENU_LEVEL or 1
	local mode, player = ADKP_Bid_GetPassSettings()
	if level == 1 then
		UIDropDownMenu_AddButton({text = "处理当前流拍物品", isTitle = 1, notCheckable = 1}, level)
		UIDropDownMenu_AddButton({text = "仅记录，不分配", checked = mode == "record",
			arg1 = "record", func = ADKP_Bid_PassMenuSelect}, level)
		UIDropDownMenu_AddButton({text = "分配给自己", checked = mode == "self",
			arg1 = "self", func = ADKP_Bid_PassMenuSelect}, level)
		UIDropDownMenu_AddButton({text = "分配给：" .. (player or "选择对象"), checked = mode == "player",
			value = "player", hasArrow = 1, keepShownOnClick = 1}, level)
	elseif level == 2 and UIDROPDOWNMENU_MENU_VALUE == "player" then
		for _, group in ipairs(ADKP_Bid_PassMenuGroups) do
			UIDropDownMenu_AddButton({text = ADKP_GetClassColor(group.class) .. group.label .. "|r",
				value = group, hasArrow = 1, notCheckable = 1, keepShownOnClick = 1}, level)
		end
	elseif level == 3 and type(UIDROPDOWNMENU_MENU_VALUE) == "table" then
		local group = UIDROPDOWNMENU_MENU_VALUE
		for _, member in ipairs(group.players or {}) do
			UIDropDownMenu_AddButton({text = ADKP_GetClassColor(member.class) .. member.name .. "|r",
				checked = mode == "player" and player == member.name,
				value = member.name, arg1 = "player", func = ADKP_Bid_PassMenuSelect}, level)
		end
	end
end

local function ADKP_Bid_OpenPassMenu()
	if not ADKP_Bid_ValidateAssignment(nil, true) then return end
	local players = ADKP_Bid_GetAssignmentPlayers()
	ADKP_Bid_PassMenuGroups = {}
	for _, className in ipairs(ADKP_Bid_AssignmentClassOrder) do
		local members = {}
		for _, member in ipairs(players) do
			if member.class == className then table.insert(members, member) end
		end
		-- 原生每层最多 32 项；极端同职业团按 30 人分页，保持三级以内。
		local pages = math.ceil(table.getn(members) / 30)
		for page = 1, pages do
			local group = {class = className, label = className, players = {}}
			if pages > 1 then group.label = className .. "（" .. page .. "/" .. pages .. "）" end
			for i = (page - 1) * 30 + 1, math.min(page * 30, table.getn(members)) do
				table.insert(group.players, members[i])
			end
			table.insert(ADKP_Bid_PassMenuGroups, group)
		end
	end
	ADKP_Bid_PassMenuContext = {revision = ADKP_Bid_ActionRevision, item = ADKP_bidItem, tableid = ADKP_GetTableid()}
	if not ADKP_Bid_PassMenu then
		ADKP_Bid_PassMenu = CreateFrame("Frame", "ADKP_BidPassMenu", UIParent, "UIDropDownMenuTemplate")
	end
	UIDropDownMenu_Initialize(ADKP_Bid_PassMenu, ADKP_Bid_PassMenuInitialize, "MENU")
	ToggleDropDownMenu(1, nil, ADKP_Bid_PassMenu, "cursor", 0, 0)
end

function ADKP_Bid_PassButtonClick(mouseButton)
	if ADKP_TransmogMode then return end
	if mouseButton == "RightButton" then
		ADKP_Bid_OpenPassMenu()
	else
		local mode, player = ADKP_Bid_GetPassSettings()
		ADKP_Bid_ExecutePass(mode, player)
	end
end

function ADKP_Bid_ShowPassButtonTooltip()
	GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
	GameTooltip:SetText("流拍", 1, 1, 1)
	local mode, player = ADKP_Bid_GetPassSettings()
	if mode == "self" then
		GameTooltip:AddLine("左键：0 分记录并分配给自己", 0.8, 0.8, 0.8)
	elseif mode == "player" then
		GameTooltip:AddLine("左键：0 分记录并分配给 " .. (player or "未设置对象"), 0.8, 0.8, 0.8, true)
	else
		GameTooltip:AddLine("左键：0 分记录（不分配物品）", 0.8, 0.8, 0.8)
	end
	GameTooltip:AddLine("右键：选择本次处理方式，并记住选择", 0.8, 0.8, 0.8, true)
	GameTooltip:Show()
end

-- ================================
-- Method invoked when the user clicks the award button the on 
-- bid frame. Finds the first person who is selected
-- and awards them the item. 
-- ================================
function ADKP_Bid_AwardSelected()
	-- find out who is selected
	local player, bid = ADKP_Bid_GetSelected();
	-- if someone is selected, award them the item via the award class
	if ( player == nil ) then 
		ADKP_Print("没有选中");
		PlaySound("igQuestFailed");
	else
		--since we are awarding, stop the bid
		if ( ADKP_bidInProgress) then
			ADKP_Bid_StopBid();
		else
			ADKP_Bid_StartNextQueuedItem();
		end
		ADKP_Bid_RecordItem(player, bid, true, false)
		ADKP_Bid_Unfinished = false
			
		ADKP_Bid_HideUI();
	end
end

-- ================================
-- Event handler for the start / stop bid button. 
-- This button toggles between states when clicked. 
-- ================================
function ADKP_Bid_ButtonHandler()

	if(ADKP_bidInProgress) then
		ADKP_Bid_StopBid();		
	else
		local item = ADKP_BidFrameItem:GetText();
		local time = ADKP_BidFrameTime:GetText();
		ADKP_Bid_StartBid(item, time);
	end
end

-- ================================
-- Method invoked when the user clicks the award button the on 
-- bid frame. Finds the first person who is selected
-- and awards them the item. 
-- ================================
function ADKP_Bid_GetSelected()
	for key_name, v in pairs(ADKP_BidList) do
		if ( type(v) == "table" ) then
			if(  v["Selected"] == true) then
				return v["Name"], v["Bid"];
			end
		end
	end
	return nil, 0;
end


-- ================================
-- Event handler for the bidding update frame. The update frame is visible (and calling this method)
-- when a timer value was specified. The addon countdowns until 0 - and when it reaches 0 it stops
-- the current bid
-- ================================
function ADKP_Bid_OnUpdate(elapsed)	
	this.TimeSinceLastUpdate = this.TimeSinceLastUpdate + elapsed; 	

	if (this.TimeSinceLastUpdate > 1.0) then
		this.TimeSinceLastUpdate = 0;
		-- decrement the count down
		ADKP_bidCountdown = ADKP_bidCountdown - 1;
		--ADKP_Print(ADKP_bidCountdown);
		ADKP_BidFrame_Countdown:SetText("Time Left: "..ADKP_bidCountdown.."s");
		
		
		if ( ADKP_bidCountdown == 30 ) then				-- 30 seconds left
			local _,_,link = ADKP_GetItemInfo(ADKP_bidItem); 
			ADKP_SendCountdownMessage("30秒后结束竞拍 "..link.."!");
		
		elseif ( ADKP_bidCountdown == 10 ) then				-- 10 seconds left
			local _,_,link = ADKP_GetItemInfo(ADKP_bidItem); 
			
			-- 获取当前最高出价者和出价
			local highestBidder, highestBid = ADKP_Bid_GetHighestBid();
			
			if (highestBidder and highestBid > 0) then
				-- 播报当前最高分状态     
				if ADKP_IsAnonymousAuction() then ADKP_SendCountdownMessage("目前 "..link.." 最高有效出分 "..highestBid.." 分，开始倒计时！"); else ADKP_SendCountdownMessage("目前 "..link.." 最高分是 "..highestBidder.." 出的 "..highestBid.." 分，开始倒计时！"); end
			else
				-- 如果没有人出过价
				ADKP_SendCountdownMessage(link.." 目前无人出分，现在开始倒计时！");
			end
	     elseif ( ADKP_bidCountdown == 9 ) then			
			ADKP_SendCountdownMessage("倒计时9秒");
		elseif ( ADKP_bidCountdown == 8 ) then			
			ADKP_SendCountdownMessage("倒计时8秒");
		elseif ( ADKP_bidCountdown == 7 ) then			
			ADKP_SendCountdownMessage("倒计时7秒");
		elseif ( ADKP_bidCountdown == 6 ) then			
			ADKP_SendCountdownMessage("倒计时6秒");
	    elseif ( ADKP_bidCountdown == 5 ) then			
			ADKP_SendCountdownMessage("倒计时5秒");
		elseif ( ADKP_bidCountdown == 4 ) then			
			ADKP_SendCountdownMessage("倒计时4秒");
		elseif ( ADKP_bidCountdown == 3 ) then			
			ADKP_SendCountdownMessage("倒计时3秒");
		elseif ( ADKP_bidCountdown == 2 ) then			
			ADKP_SendCountdownMessage("倒计时2秒");
	    elseif ( ADKP_bidCountdown == 1 ) then			
			ADKP_SendCountdownMessage("倒计时1秒");
		elseif ( ADKP_bidCountdown <= 0 ) then			-- countdown reached 0

			-- stop the bidding!
			ADKP_Bid_StopBid();
		  
		end
	end
end

-- ================================
-- Invoked when a user uses shift+click to display item details. 
-- As long as a bid is not in progress and the big gui is displayed, 
-- fill the item information into the form
-- ================================
function ADKP_Bid_ItemChatClick(link, text, button)
	if ( IsShiftKeyDown() and ADKP_BidFrame:IsShown() and ADKP_bidInProgress == false ) then
		local _,itemName,_ = ADKP_GetItemInfo(link); 
		ADKP_BidFrameItem:SetText(itemName);
		ADKP_Bid_ShowItemDisplay();
		ADKP_Bid_RequestItemRefresh(link);
	end
end


-- ================================
-- anon auction helpers
-- ================================
function ADKP_Bid_AnonAnnounceTick()
	if not ADKP_IsAnonymousAuction() then return end
	if not ADKP_bidInProgress then return end
	local highestBidder, highestBid = ADKP_Bid_GetHighestBid();
	if ( highestBid and highestBid > 0 and highestBid ~= ADKP_Bid_LastAnnouncedBid ) then
		ADKP_Bid_LastAnnouncedBid = highestBid;
		local _,itemName = ADKP_GetItemInfo(ADKP_bidItem);
		ADKP_SendChatMessage("当前 "..(itemName or "").." 最高有效出分："..highestBid.." 分", "RAID");
	end
end

function ADKP_Bid_StartAnonTicker()
	ADKP_Bid_LastAnnouncedBid = nil;
	if not ADKP_IsAnonymousAuction() then return end
	if ( not ADKP_Bid_AnonTickerFrame ) then
		ADKP_Bid_AnonTickerFrame = CreateFrame("Frame");
	end
	ADKP_Bid_AnonTickerFrame.elapsed = 0;
	ADKP_Bid_AnonTickerFrame:SetScript("OnUpdate", function()
		local e = tonumber(arg1) or 0;
		this.elapsed = (this.elapsed or 0) + e;
		if ( this.elapsed < 1.0 ) then return end
		this.elapsed = 0;
		ADKP_Bid_AnonAnnounceTick();
	end);
	ADKP_Bid_AnonTickerFrame:Show();
end

function ADKP_Bid_StopAnonTicker()
	if ( ADKP_Bid_AnonTickerFrame ) then
		ADKP_Bid_AnonTickerFrame:SetScript("OnUpdate", nil);
		ADKP_Bid_AnonTickerFrame:Hide();
	end
	ADKP_Bid_LastAnnouncedBid = nil;
end

function ADKP_Bid_AnnounceSelected()
	local name, bid = ADKP_Bid_GetSelected();
	if ( not name ) then
		ADKP_Print("没有选中出分记录");
		PlaySound("igQuestFailed");
		return;
	end
	local _,itemName = ADKP_GetItemInfo(ADKP_bidItem);
	ADKP_SendChatMessage("该装备 "..(itemName or "").." 的有效出分分值为 "..bid.." 分", "RAID");
end


