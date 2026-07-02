------------------------------------------------------------------------
-- BIDDING	
------------------------------------------------------------------------
-- Contains methods related to bidding and the bidding gui.
------------------------------------------------------------------------


local ADKP_BidList = {	};					-- Will hold the bids placed during run time
local ADKP_bidInProgress = false;			-- Bid in progress?
local ADKP_bidItem = "";					-- Item name being bid on
local ADKP_bidCountdown = 0;				-- How many seconds until bid ends on its own

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

function ADKP_CreateBidQueueWindow()
	if ADKP_BidQueueWindow then return ADKP_BidQueueWindow end
	local f = CreateFrame("Frame", "ADKP_BidQueueWindow", UIParent)
	f:SetWidth(210)
	f:SetHeight(200)
	f:SetPoint("TOPLEFT", ADKP_BidFrame, "TOPRIGHT", 10, 0)
	f:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 16,
		insets = { left = 4, right = 4, top = 4, bottom = 4 }
	})
	f:SetBackdropColor(0, 0, 0, 0.85)
	f:Hide()

	local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -10)
	title:SetText("拍卖队列")

	-- 当前行（高亮背景）
	local curBg = f:CreateTexture(nil, "BACKGROUND")
	curBg:SetPoint("TOPLEFT", f, "TOPLEFT", 6, -30)
	curBg:SetWidth(198)
	curBg:SetHeight(24)
	curBg:SetTexture(0.1, 0.4, 0.1, 0.6)

	local curText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	curText:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -35)
	curText:SetWidth(190)
	curText:SetJustifyH("LEFT")
	curText:SetText("▶ (无)")
	f.curText = curText

	-- 预创建 10 个剩余行
	f.rows = {}
	for i = 1, 10 do
		local row = CreateFrame("Frame", nil, f)
		row:SetWidth(198)
		row:SetHeight(16)
		row:SetPoint("TOPLEFT", f, "TOPLEFT", 6, -60 - (i - 1) * 14)
		row.idx = i
		row:EnableMouse(true)
		row:SetScript("OnMouseDown", function()
			ADKP_BidQueue_SwitchTo(this.idx)
		end)

		local text = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		text:SetPoint("LEFT", row, "LEFT", 2, 0)
		text:SetWidth(100)
		text:SetHeight(14)
		text:SetJustifyH("LEFT")
		text:SetNonSpaceWrap(false)

		local upBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
		upBtn:SetWidth(18)
		upBtn:SetHeight(16)
		upBtn:SetPoint("LEFT", row, "LEFT", 104, 0)
		upBtn:SetText("↑")
		upBtn:RegisterForClicks("LeftButtonUp")

		local downBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
		downBtn:SetWidth(18)
		downBtn:SetHeight(16)
		downBtn:SetPoint("LEFT", row, "LEFT", 124, 0)
		downBtn:SetText("↓")
		downBtn:RegisterForClicks("LeftButtonUp")

		local cancelBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
		cancelBtn:SetWidth(18)
		cancelBtn:SetHeight(16)
		cancelBtn:SetPoint("LEFT", row, "LEFT", 168, 0)
		cancelBtn:SetText("×")
		cancelBtn:RegisterForClicks("LeftButtonUp")

		row:Hide()
		f.rows[i] = { row = row, text = text, up = upBtn, cancel = cancelBtn, down = downBtn }
	end

	-- 底部说明
	local tip = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	tip:SetPoint("TOPLEFT", f, "TOPLEFT", 6, -178)
	tip:SetWidth(198)
	tip:SetJustifyH("LEFT")
	tip:SetText("点击对应物品，强制切换至该物品作为当前拍卖品。")

	ADKP_BidQueueWindow = f
	return f
end

function ADKP_UpdateBidQueueWindow()
	local f = ADKP_BidQueueWindow
	if not f then return end

	-- 当前行
	local curName = "（无）"
	if ADKP_BidFrameItem and ADKP_BidFrameItem.GetText then
		local t = ADKP_BidFrameItem:GetText()
		if t and t ~= "" then curName = t end
	end
	f.curText:SetText("▶ " .. curName)

	-- 剩余行
	local n = table.getn(ADKP_BidQueue)
	for i = 1, 10 do
		local r = f.rows[i]
		if i <= n then
			local entry = ADKP_BidQueue[i]
			local idx = i
			r.text:SetText((entry and entry.item) or "")
			r.up:SetScript("OnClick", function() ADKP_BidQueue_Up(idx) end)
			r.cancel:SetScript("OnClick", function() ADKP_BidQueue_Cancel(idx) end)
			r.down:SetScript("OnClick", function() ADKP_BidQueue_Down(idx) end)
			r.row:Show()
		else
			r.row:Hide()
		end
	end

	-- 窗口显隐：竞拍界面显示中 且 队列非空
	if ADKP_BidFrame and ADKP_BidFrame:IsVisible() and n > 0 then
		f:Show()
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
	if i <= 1 or i > table.getn(ADKP_BidQueue) then return end
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
	local currentItem = ADKP_BidFrameItem:GetText()
	if currentItem and currentItem ~= "" then
		table.insert(ADKP_BidQueue, 1, { item = currentItem, time = 0 })
	end
	local target = table.remove(ADKP_BidQueue, i + 1)
	ADKP_Bid_StartBid(target.item, target.time or 0)
	ADKP_UpdateBidQueueWindow()
end

-- ================================
-- Called when mouse goes over a dkp line entry. 
-- If that player is not selected causes that row
-- to become 'highlighted'
-- ================================
function ADKP_Bid_HandleMouseOver()
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
function ADKP_Bid_UpdateTable()
	-- Copy data to the temporary array
	local entries = { };
	for key_name, v in pairs(ADKP_BidList) do
		if ( type(v) == "table" ) then
			if( v["Name"] ~= nil and v["Bid"] ~= nil and v["DKP"] ~=nil and v["Post"] ~=nil) then
				tinsert(entries,{v["Name"],v["Bid"],v["DKP"],v["Post"],v["Date"],v["OverBid"]}); -- copies over name, bid, dkp, dkp-bid
			end
		end
	end
	
	-- SORT
	table.sort(
		entries,
		function(a1, a2) 
			if ( a1 and a2 ) then
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
	
	local firstHighestBidder, highestBid = ADKP_Bid_GetHighestBid();
	
	-- Run through the table lines and put the appropriate information into each line
	for i=1, 13, 1 do
		local line = getglobal("ADKP_BidFrameLine" .. i);
		local nameText = getglobal("ADKP_BidFrameLine" .. i .. "Name");
		local bidText = getglobal("ADKP_BidFrameLine" .. i .. "Bid");
		local dkpText = getglobal("ADKP_BidFrameLine" .. i .. "DKP");
		local postBidText = getglobal("ADKP_BidFrameLine" .. i .. "Post");
		local index = i + offset; 
		
		if ( index <= numEntries) then
			local playerName = entries[index][1];
			local bidAmount = entries[index][2];
			local date = entries[index][5];
			local isOverBid = entries[index][6] or false;
			line:Show();
			
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
			dkpText:SetText(entries[index][3]);
			postBidText:SetText(entries[index][4]);
			-- 根据选择状态设置背景颜色
			local selected = ADKP_Bid_IsSelected(playerName, entries[index][2]);
			if selected then
				getglobal("ADKP_BidFrameLine" .. i .. "Background"):SetVertexColor(0.1, 0.1, 0.9, 0.8); -- 选中状态
			else
				getglobal("ADKP_BidFrameLine" .. i .. "Background"):SetVertexColor(0, 0, 0, 0); -- 未选中状态
			end
			-- 如果是超分出价，设置出价文本为红色
			if isOverBid then
				bidText:SetTextColor(1, 0, 0, 1); -- 红色
			elseif bidAmount == highestBid and playerName == firstHighestBidder then
				bidText:SetTextColor(0, 1, 0, 1); -- 最高分，绿色
			else
				bidText:SetTextColor(1, 1, 1, 1); -- 其他出价，白色
			end
		else
			-- if the line isn't in use, hide it so we dont' have mouse overs
			line:Hide();
		end
	end
end
-- ================================
-- Handles chat messages directed towards bidding. This includes
-- placing a bid and remotly starting / stopping a bid.
-- ================================
function ADKP_Bid_Event()
    local name = arg2;  -- 参数2是玩家名称
    local trigger = arg1;  -- 参数1是纯消息内容(不包含玩家名等前缀)

    -- 检查是否是竞标相关的消息
    if (ADKP_IsBidChat(name, trigger)) then
        -- 非拍卖状态下忽略出分/sh（不影响 · 和 ` 启动拍卖命令）
        local isStartCmd = (string.find(trigger, "^·") == 1 or string.find(trigger, "^`") == 1 or string.find(string.lower(trigger), "^%?stopbid") == 1)
        if not ADKP_bidInProgress and not isStartCmd then
            return
        end

        local bidAmount = nil

        -- 检查是否是纯数字
        if tonumber(trigger) then
            bidAmount = tonumber(trigger)  -- 将数字转换为出价金额
        -- 检查是否是数字加上 P 或 p
        elseif string.match(trigger, "^%d+%s*[Pp]$") then
            bidAmount = tonumber(string.match(trigger, "^(%d+)"))  -- 提取数字部分
        -- 检查是否是梭哈命令 (sh 或 SH)
        elseif string.lower(trigger) == "sh" then
            bidAmount = ADKP_GetDKP(name)  -- 获取玩家当前全部DKP作为出价
            bidAmount = ADKP_Bid_NormalizeAmount(bidAmount)
            -- 绿字播报梭哈信息
            if not ADKP_IsAnonymousAuction() then ADKP_SendChatMessage("|cff00FF00" .. name .. " 梭哈 出分 " .. ADKP_Bid_FormatAmount(bidAmount) .. "分|r", "RAID"); end
        end

        -- 只有在竞标进行中才处理出价
        if (ADKP_bidInProgress) then
            if bidAmount then  -- 如果提取到出价金额
                if (bidAmount == nil or bidAmount < 0) then
                    -- ADKP_SendWhisper(name, "您没有指定有效的出价 - 出价不被接受。");
                else
                    ADKP_Bid_HandleBid(name, bidAmount);  -- 处理出价
                    -- ADKP_SendWhisper(name, "出价 " .. bidAmount .. " DKP 被接受。");
                end
            elseif (name == UnitName("player")) then
                local cleanTrigger = trigger
                if string.find(cleanTrigger, "^·") == 1 or string.find(cleanTrigger, "^`") == 1 then
                    ADKP_BidFrameBidButton:SetText("停止竞拍");
                    ADKP_Bid_ShowUI();
                end
            end
        else
            -- 只有当前玩家可以开启竞拍
            if (name == UnitName("player")) then
                local itemName = nil

                -- 直接使用参数1的纯消息内容(已自动去除前缀)
                local cleanTrigger = trigger
                if string.find(cleanTrigger, "^·") == 1  then
						-- 尝试从命令中提取物品名和可选的倒计时时间
						local itemPart, timePart = string.match(cleanTrigger, "^·%s*(.-)%s+(%d+)$")
						local countdownTime = 0

						if itemPart and timePart then
							local numTime = tonumber(timePart)
							countdownTime = (numTime < 10) and 30 or numTime
						else
							itemPart = string.match(cleanTrigger, "^·-([^·]+)$") or string.sub(cleanTrigger, 3)
						end

						-- 解析多件装备
						local items = ADKP_Bid_ParseItems(itemPart)
						if table.getn(items) == 0 then
                        ADKP_SendWhisper(name, "您必须指定一个要竞标的物品。示例：·[装备1][装备2] 20");
						else
							-- 清空旧队列
							ADKP_BidQueue = {}
							-- 多件装备入队
							if table.getn(items) > 1 then
								for i = 2, table.getn(items) do
									table.insert(ADKP_BidQueue, { item = items[i], time = countdownTime })
								end
								ADKP_Print("已将 " .. (table.getn(items) - 1) .. " 件装备加入拍卖队列")
							end
							ADKP_Bid_StartBid(items[1], countdownTime);
							ADKP_BidFrameBidButton:SetText("停止竞拍");
						end
					elseif string.find(cleanTrigger, "^`") == 1 then
					-- 尝试从命令中提取物品名和可选的倒计时时间
					local itemPart, timePart = string.match(cleanTrigger, "^`%s*(.-)%s+(%d+)$")
					local countdownTime = 0

					if itemPart and timePart then
						local numTime = tonumber(timePart)
						countdownTime = (numTime < 10) and 30 or numTime
					else
						itemPart = string.match(cleanTrigger, "^`-([^`]+)$") or string.sub(cleanTrigger, 2)
					end

					-- 解析多件装备
					local items = ADKP_Bid_ParseItems(itemPart)
					if table.getn(items) == 0 then
                        ADKP_SendWhisper(name, "您必须指定一个要竞标的物品。示例：`[装备1][装备2] 20");
					else
						-- 清空旧队列
						ADKP_BidQueue = {}
						-- 多件装备入队
						if table.getn(items) > 1 then
							for i = 2, table.getn(items) do
								table.insert(ADKP_BidQueue, { item = items[i], time = countdownTime })
							end
							ADKP_Print("已将 " .. (table.getn(items) - 1) .. " 件装备加入拍卖队列")
						end
						ADKP_Bid_StartBid(items[1], countdownTime);
						ADKP_BidFrameBidButton:SetText("停止竞拍");
					end
				elseif (string.find(trigger, "^stopbid") == 1) then
                    if (ADKP_bidInProgress == false) then
                        ADKP_SendWhisper(name, "没有出价，正在为您取消。");
                    else
                        ADKP_Bid_StopBid();  -- 停止竞标
                        ADKP_BidFrameBidButton:SetText("开始竞拍!");
                    end
                    -- 清空拍卖队列
                    ADKP_BidQueue = {}
                    if ADKP_BidQueueTimer then
                        ADKP_BidQueueTimer:SetScript("OnUpdate", nil)
                    end
                end
            -- else
                -- -- 如果不是当前玩家，发送消息告知他们不能开启竞标
                -- ADKP_SendWhisper(name, "只有 " .. UnitName("player") .. " 可以开启竞标。");
            end
        end
    end
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
	ADKP_BidFrameBidButton:SetText("停止竞拍");

	ADKP_BidList = {};
	if (time == "" or time == nil or time=="0" or time==" ") then
		time = 0 ; 
	end
	
	local quality, itemName, itemLink = ADKP_GetItemInfo(item);
	ADKP_bidItem = itemName;
	ADKP_BidFrameItem:SetText(itemName);
	-- 队列剩余数量显示（独立的文本，不影响物品栏和通告）
	local queueSize = table.getn(ADKP_BidQueue)
	if not ADKP_BidQueueLabel then
		local label = ADKP_BidFrame:CreateFontString("ADKP_BidQueueLabel", "OVERLAY", "GameFontNormal")
		label:SetPoint("TOPLEFT", ADKP_BidFrame, "TOPLEFT", 200, -140)
		ADKP_BidQueueLabel = label
	end
	if queueSize > 0 then
		ADKP_BidQueueLabel:SetText("|cffffff00(队列还有" .. queueSize .. "件)|r")
	else
		ADKP_BidQueueLabel:SetText("")
	end
	ADKP_BidFrameTime:SetText(time);
	
	ADKP_AnnounceBidStart(itemLink, time);
	ADKP_bidInProgress = true;
	ADKP_Bid_StartAnonTicker();
	
	ADKP_Bid_UpdateTable();
	ADKP_Bid_ShowUI();
	
	if(time ~= 0 ) then 
		ADKP_bidCountdown = time;
		ADKP_Bid_UpdateFrame:Show();
	else
		ADKP_Bid_UpdateFrame:Hide();
	end
		
end


-- ================================
-- Stops the current bidding
-- ================================
function ADKP_Bid_StopBid()
		
		ADKP_Bid_UpdateFrame:Hide();								-- stop any countdowns
		ADKP_BidFrame_Countdown:SetText("");
		
		ADKP_BidFrameBidButton:SetText("开始竞拍!");		-- fix the button text
		local bidder, bid = ADKP_Bid_GetHighestBid();					-- find highest bidder (not used any more)
		ADKP_AnnounceBidEnd(ADKP_bidItem, bidder, bid);			-- make the announcement
		ADKP_bidInProgress = false;
		ADKP_Bid_StopAnonTicker();							
		ADKP_Bid_ShowUI();										-- how the bid gui

		-- 检查拍卖队列，自动开始下一件
		if table.getn(ADKP_BidQueue) > 0 then
			local nextEntry = table.remove(ADKP_BidQueue, 1)
			local remaining = table.getn(ADKP_BidQueue)
			ADKP_Print("队列中还有 " .. remaining .. " 件装备待拍卖，1.5秒后自动开始下一件...")
			-- 延迟启动下一件，避免与停止公告冲突
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
			btn:SetText("手动倒计时")
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
-- Handles a bid placed by a player. 
-- ================================
function ADKP_Bid_HandleBid(playerName, bidAmount)
    -- 如果竞标未进行，忽略出价
    if (ADKP_bidInProgress) then 
        bidAmount = ADKP_Bid_NormalizeAmount(bidAmount)
        local dkp = ADKP_GetDKP(playerName);           -- 获取玩家当前 DKP
        
        -- 检查出价是否超过当前 DKP
        local isOverBid = false
        if (bidAmount > dkp) then
            local message = playerName .. " 出价 " .. bidAmount .. " 分，想屁吃呢？你总共也就 " .. dkp .. " 分，出价无效。"
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
    local isSilentMode = ADKP_Options and ADKP_Options["SilentMode"]
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
		-- 获取玩家当前 DKP
		local currentDKP = ADKP_GetDKP(player);
		
		-- 检查玩家是否有足够的 DKP
		-- if (bid > currentDKP) then
		-- 	ADKP_Print("无法奖励物品给" .. player .. "，因为出价" .. bid .. "分超过了可用的" .. currentDKP .. "分！");
		-- 	PlaySound("igQuestFailed");
		-- 	return;
		-- end
		
		--since we are awarding, stop the bid
		if ( ADKP_bidInProgress) then
			ADKP_Bid_StopBid();
		end
			
		--See how many points the person will lose
		local points = bid * -1;
		--put this into a points table for the add dkp method
		local playerTable = { [0] = {
				["name"] = player,
				["class"] = ADKP_GetPlayerClass(player),
			}};
		--award the item
		local tableid = ADKP_GetTableid()
		ADKP_AddDKP(points, ADKP_bidItem, "true", playerTable, tableid)
		ADKP_AnnounceAwardItem(points, ADKP_bidItem, player);
		-- Update the table so we can see the new dkp status
		ADKP_UpdateTableToShow();
		ADKP_UpdateTable();
		PlaySound("LOOTWINDOWCOINSOUND");
			
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
