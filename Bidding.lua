------------------------------------------------------------------------
-- BIDDING	
------------------------------------------------------------------------
-- Contains methods related to bidding and the bidding gui.
------------------------------------------------------------------------


local WebDKP_BidList = {	};					-- Will hold the bids placed during run time
local WebDKP_bidInProgress = false;			-- Bid in progress?
local WebDKP_bidItem = "";					-- Item name being bid on
local WebDKP_bidCountdown = 0;				-- How many seconds until bid ends on its own

-- Data structure for sorting the table 
WebDKP_BidSort = {
	["curr"] = 2,				-- the column to sort
	["way"] = 1					-- Desc
};

-- ================================
-- Toggles displaying the bidding panel
-- ================================
function WebDKP_Bid_ToggleUI()
	if ( WebDKP_BidFrame:IsShown() ) then
		WebDKP_BidFrame:Hide();
	else
		WebDKP_BidFrame:Show();
		
		local time = WebDKP_BidFrameTime:GetText();
		if(time == nil or time == "") then
			WebDKP_BidFrameTime:SetText("0");
		end
	end
end

-- ================================
-- Shows the Bid UI
-- ================================
function WebDKP_Bid_ShowUI()
	WebDKP_BidFrame:Show();
	local time = WebDKP_BidFrameTime:GetText();
	if(time == nil or time == "") then
		WebDKP_BidFrameTime:SetText("0");
	end
end

-- ================================
-- Hides the Bid UI
-- ================================
function WebDKP_Bid_HideUI()
	WebDKP_BidFrame:Hide();
end

-- ================================
-- Called when mouse goes over a dkp line entry. 
-- If that player is not selected causes that row
-- to become 'highlighted'
-- ================================
function WebDKP_Bid_HandleMouseOver()
	local playerName = getglobal(this:GetName().."Name"):GetText();
	local playerBid = getglobal(this:GetName().."Bid"):GetText();
	local selected = WebDKP_Bid_IsSelected(playerName, playerBid);
	
	if( not selected ) then
		getglobal(this:GetName() .. "Background"):SetVertexColor(0.2, 0.2, 0.7, 0.5);
	end
end

-- ================================
-- Called when a mouse leaes a dkp line entry. 
-- If that player is not selected, causes that row
-- to return to normal (none highlighted)
-- ================================
function WebDKP_Bid_HandleMouseLeave()
	local playerName = getglobal(this:GetName().."Name"):GetText();
	local playerBid = getglobal(this:GetName().."Bid"):GetText();
	local selected = WebDKP_Bid_IsSelected(playerName, playerBid);
	if( not selected ) then
		getglobal(this:GetName() .. "Background"):SetVertexColor(0, 0, 0, 0);
	end
end

-- ================================
-- Called when the user clicks on a player entry. Causes 
-- that entry to either become selected or normal
-- and updates the dkp table with the change
-- ================================
function WebDKP_Bid_SelectPlayerToggle()
	local playerName = getglobal(this:GetName().."Name"):GetText();
	local playerBid = getglobal(this:GetName().."Bid"):GetText() + 0 ;
	
	
	-- we need to search through the table and figure out which one was selected
	-- an entry is considered a unique name / bid pair
	-- once we find an entry we can toggle its selection state
	for key, v in pairs(WebDKP_BidList) do
		if ( type(v) == "table" ) then
			if( v["Name"] ~= nil and v["Bid"] ~= nil ) then
				if ( v["Name"] == playerName and v["Bid"] == playerBid ) then 
					if (v["Selected"] == true) then
						v["Selected"] = false;
						getglobal(this:GetName() .. "Background"):SetVertexColor(0.2, 0.2, 0.7, 0.5);
					else
						-- deselect all the others on the table
						WebDKP_Bid_DeselectAll();
						
						v["Selected"] = true;
						getglobal(this:GetName() .. "Background"):SetVertexColor(0.1, 0.1, 0.9, 0.8);
					end
				end
			end
		end
	end
	
	
	WebDKP_Bid_UpdateTable();
end

-- ================================
-- Returns true if the given player name / bid value is selected
-- in the bid list table. false otherwise. 
-- ================================
function WebDKP_Bid_IsSelected(playerName, playerBid)
	playerBid = playerBid + 0 ; 
	for key, v in pairs(WebDKP_BidList) do
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
function WebDKP_Bid_DeselectAll()
	for key, v in pairs(WebDKP_BidList) do
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
function WebDKP_Bid_SortBy(id)
	if ( WebDKP_BidSort["curr"] == id ) then
		WebDKP_BidSort["way"] = abs(WebDKP_BidSort["way"]-1);
	else
		WebDKP_BidSort["curr"] = id;
		if( id == 1) then
			WebDKP_BidSort["way"] = 0;
		elseif ( id == 2 ) then
			WebDKP_BidSort["way"] = 1; --columns with numbers need to be sorted different first in order to get DESC right
		elseif ( id == 3 ) then
			WebDKP_BidSort["way"] = 1; --columns with numbers need to be sorted different first in order to get DESC right
		else
			WebDKP_BidSort["way"] = 1; --columns with numbers need to be sorted different first in order to get DESC right
		end
		
	end
	-- update table so we can see sorting changes
	WebDKP_Bid_UpdateTable();
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
function WebDKP_Bid_UpdateTable()
	-- Copy data to the temporary array
	local entries = { };
	for key_name, v in pairs(WebDKP_BidList) do
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
				if ( WebDKP_BidSort["way"] == 1 ) then
					if ( a1[WebDKP_BidSort["curr"]] == a2[WebDKP_BidSort["curr"]] ) then
						return a1[1] > a2[1];
					else
						return a1[WebDKP_BidSort["curr"]] > a2[WebDKP_BidSort["curr"]];
					end
				else
					if ( a1[WebDKP_BidSort["curr"]] == a2[WebDKP_BidSort["curr"]] ) then
						return a1[1] < a2[1];
					else
						return a1[WebDKP_BidSort["curr"]] < a2[WebDKP_BidSort["curr"]];
					end
				end
			end
		end
	);
	
	local numEntries = getn(entries);
	local offset = FauxScrollFrame_GetOffset(WebDKP_BidFrameScrollFrame);
	FauxScrollFrame_Update(WebDKP_BidFrameScrollFrame, numEntries, 13, 13);
	
	-- Run through the table lines and put the appropriate information into each line
	for i=1, 13, 1 do
		local line = getglobal("WebDKP_BidFrameLine" .. i);
		local nameText = getglobal("WebDKP_BidFrameLine" .. i .. "Name");
		local bidText = getglobal("WebDKP_BidFrameLine" .. i .. "Bid");
		local dkpText = getglobal("WebDKP_BidFrameLine" .. i .. "DKP");
		local postBidText = getglobal("WebDKP_BidFrameLine" .. i .. "Post");
		local index = i + offset; 
		
		if ( index <= numEntries) then
			local playerName = entries[index][1];
			local date = entries[index][5];
			local isOverBid = entries[index][6] or false;
			line:Show();
			nameText:SetText(entries[index][1]);
			bidText:SetText(entries[index][2]);
			dkpText:SetText(entries[index][3]);
			postBidText:SetText(entries[index][4]);
			-- 根据选择状态设置背景颜色
			local selected = WebDKP_Bid_IsSelected(playerName, entries[index][2]);
			if selected then
				getglobal("WebDKP_BidFrameLine" .. i .. "Background"):SetVertexColor(0.1, 0.1, 0.9, 0.8); -- 选中状态
			else
				getglobal("WebDKP_BidFrameLine" .. i .. "Background"):SetVertexColor(0, 0, 0, 0); -- 未选中状态
			end
			-- 如果是超分出价，设置出价文本为红色
			if isOverBid then
				bidText:SetTextColor(1, 0, 0, 1); -- 红色
			else
				bidText:SetTextColor(1, 1, 1, 1); -- 白色
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
function WebDKP_Bid_Event()
    local name = arg2;  -- 参数2是玩家名称
    local trigger = arg1;  -- 参数1是纯消息内容(不包含玩家名等前缀)

    -- 检查是否是竞标相关的消息
    if (WebDKP_IsBidChat(name, trigger)) then  
        local bidAmount = nil

        -- 检查是否是纯数字
        if tonumber(trigger) then
            bidAmount = tonumber(trigger)  -- 将数字转换为出价金额
        -- 检查是否是数字加上 P 或 p
        elseif string.match(trigger, "^%d+%s*[Pp]$") then
            bidAmount = tonumber(string.match(trigger, "^(%d+)"))  -- 提取数字部分
        -- 检查是否是梭哈命令 (sh 或 SH)
        elseif string.lower(trigger) == "sh" then
            bidAmount = WebDKP_GetDKP(name)  -- 获取玩家当前全部DKP作为出价
            -- 绿字播报梭哈信息
            WebDKP_SendChatMessage("|cff00FF00" .. name .. " 梭哈 出分 " .. bidAmount .. "分|r", "RAID");
        end

        -- 只有在竞标进行中才处理出价
        if (WebDKP_bidInProgress) then
            if bidAmount then  -- 如果提取到出价金额
                if (bidAmount == nil or bidAmount <= 0) then
                    -- WebDKP_SendWhisper(name, "您没有指定有效的出价 - 出价不被接受。");
                else
                    WebDKP_Bid_HandleBid(name, bidAmount);  -- 处理出价
                    -- WebDKP_SendWhisper(name, "出价 " .. bidAmount .. " DKP 被接受。");
                end
            end
        else
            -- 只有当前玩家可以开启竞拍
            if (name == UnitName("player")) then
                local itemName = nil

                -- 直接使用参数1的纯消息内容(已自动去除前缀)
                local cleanTrigger = trigger
                if string.find(cleanTrigger, "^·") == 1  then
                    --  itemName = string.match(cleanTrigger, "^[·`]%s*(.+)")  -- 从消息中提取物品名称
					-- itemName = string.sub(cleanTrigger, 2) or string.match(cleanTrigger, "^[·`]%s*(.+)") 
					-- 尝试从命令中提取物品名和可选的倒计时时间（格式：·物品 数字）
					local itemPart, timePart = string.match(cleanTrigger, "^·%s*(.-)%s+(%d+)$")
					local countdownTime = 0
					
					if itemPart and timePart then
						-- 如果命令格式为"·物品 数字"，使用提取的物品名和时间
						itemName = itemPart
						local numTime = tonumber(timePart)
						-- 如果时间少于10秒，则默认使用30秒
						countdownTime = (numTime < 10) and 30 or numTime
					else
						-- 否则使用传统方式提取物品名，时间设为0
						itemName = string.match(cleanTrigger, "^·-([^·]+)$") or string.sub(cleanTrigger, 3)
					end
					
					if (itemName == "" or itemName == nil) then
                        WebDKP_SendWhisper(name, "您必须指定一个要竞标的物品。示例：·[巨人追踪者的头盔] 或 ·[巨人追踪者的头盔] 20");
                    else    
                        WebDKP_Bid_StartBid(itemName, countdownTime);  -- 调用开始竞标函数，传入解析的倒计时时间
                        WebDKP_BidFrameBidButton:SetText("停止竞拍");
                    end
				elseif string.find(cleanTrigger, "^`") == 1 then
					-- 尝试从命令中提取物品名和可选的倒计时时间（格式：`物品 数字）
					local itemPart, timePart = string.match(cleanTrigger, "^`%s*(.-)%s+(%d+)$")
					local countdownTime = 0
					
					if itemPart and timePart then
						-- 如果命令格式为"`物品 数字"，使用提取的物品名和时间
						itemName = itemPart
						local numTime = tonumber(timePart)
						-- 如果时间少于10秒，则默认使用30秒
						countdownTime = (numTime < 10) and 30 or numTime
					else
						-- 否则使用传统方式提取物品名，时间设为0
						itemName = string.match(cleanTrigger, "^`-([^`]+)$") or string.sub(cleanTrigger, 2)
					end
					
                    if (itemName == "" or itemName == nil) then
                        WebDKP_SendWhisper(name, "您必须指定一个要竞标的物品。示例：`[巨人追踪者的头盔] 或 `[巨人追踪者的头盔] 20");
                    else    
                        WebDKP_Bid_StartBid(itemName, countdownTime);  -- 调用开始竞标函数，传入解析的倒计时时间
                        WebDKP_BidFrameBidButton:SetText("停止竞拍");
                    end
                elseif (string.find(trigger, "^stopbid") == 1) then
                    if (WebDKP_bidInProgress == false) then
                        WebDKP_SendWhisper(name, "没有出价，正在为您取消。");
                    else
                        WebDKP_Bid_StopBid();  -- 停止竞标
                        WebDKP_BidFrameBidButton:SetText("开始竞拍!");
                    end
                end
            -- else
                -- -- 如果不是当前玩家，发送消息告知他们不能开启竞标
                -- WebDKP_SendWhisper(name, "只有 " .. UnitName("player") .. " 可以开启竞标。");
            end
        end
    end
end


-- ================================
-- Returns true if the passed whisper is a chat message directed
-- towards web dkp bidding
-- ================================
function WebDKP_IsBidChat(name, trigger)
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
function WebDKP_Bid_StartBid(item, time)
	WebDKP_BidFrameBidButton:SetText("停止竞拍");

	WebDKP_BidList = {};
	if (time == "" or time == nil or time=="0" or time==" ") then
		time = 0 ; 
	end
	
	local quality, itemName, itemLink = WebDKP_GetItemInfo(item);
	WebDKP_bidItem = itemName;
	WebDKP_BidFrameItem:SetText(itemName);
	WebDKP_BidFrameTime:SetText(time);
	
	WebDKP_AnnounceBidStart(itemLink, time);
	WebDKP_bidInProgress = true;
	
	WebDKP_Bid_UpdateTable();
	WebDKP_Bid_ShowUI();
	
	if(time ~= 0 ) then 
		WebDKP_bidCountdown = time;
		WebDKP_Bid_UpdateFrame:Show();
	else
		WebDKP_Bid_UpdateFrame:Hide();
	end
		
end


-- ================================
-- Stops the current bidding
-- ================================
function WebDKP_Bid_StopBid()
	
	WebDKP_Bid_UpdateFrame:Hide();								-- stop any countdowns
	WebDKP_BidFrame_Countdown:SetText("");
	
	WebDKP_BidFrameBidButton:SetText("开始竞拍!");		-- fix the button text
	local bidder, bid = WebDKP_Bid_GetHighestBid();				-- find highest bidder (not used any more)
	WebDKP_AnnounceBidEnd(WebDKP_bidItem, bidder, bid);			-- make the announcement
	WebDKP_bidInProgress = false;								
	WebDKP_Bid_ShowUI();										-- how the bid gui
	
end


-- ================================ 
-- Handles a bid placed by a player. 
-- ================================
function WebDKP_Bid_HandleBid(playerName, bidAmount)
    -- 如果竞标未进行，忽略出价
    if (WebDKP_bidInProgress) then 
        local dkp = WebDKP_GetDKP(playerName);           -- 获取玩家当前 DKP
        
        -- 检查出价是否超过当前 DKP
        local isOverBid = false
        if (bidAmount > dkp) then
            local message = playerName .. " 出价 " .. bidAmount .. " 分，想屁吃呢？你总共也就 " .. dkp .. " 分，出价无效。"
            WebDKP_SendChatMessage("|cffff0000" .. message .. "|r", "RAID");  -- 团队频道广播
            WebDKP_SendWhisper(playerName, message);  -- 私发消息
            isOverBid = true
            
            -- 用绿色文字提醒超分出价不被标记为最高分
            local _,_,link = WebDKP_GetItemInfo(WebDKP_bidItem);
            WebDKP_SendChatMessage("|cff00FF00" ..  " 超分出价 " .. bidAmount .. " 分不会被标记为目前最高分！".. "|r", "RAID");
        end
        
        -- 确保出价为整数
        bidAmount = math.floor(bidAmount + 0.5);  -- 四舍五入到整数

        -- 检查玩家的出价是否已经记录
        local existingBidIndex = nil

        for index, v in ipairs(WebDKP_BidList) do
            if v["Name"] == playerName and v["Bid"] == bidAmount then
                -- 如果同一玩家已出相同分数，记录其索引
                existingBidIndex = index
				
                break
            end
        end

        -- 如果出价重复，通知玩家并忽略出价
        if existingBidIndex then
            -- WebDKP_SendChatMessage(playerName, playerName .. " 你已经出过 " .. bidAmount .. " 分，重复出价无效。", "RAID");
            return;  -- 直接返回，不再处理该出价
        else
            -- 如果出价未重复，添加新的出价记录
            local postDkp = dkp - bidAmount;  -- 计算出价后的 DKP
            local date = date("%Y-%m-%d %H:%M:%S");  -- 记录出价时间
            
            -- 在列表末尾添加新的出价记录
            table.insert(WebDKP_BidList, {
                ["Name"] = playerName,
                ["Bid"] = bidAmount,
                ["DKP"] = dkp,
                ["Post"] = postDkp,
                ["Date"] = date,
                ["Selected"] = false,  -- 初始化为未选中
                ["OverBid"] = isOverBid -- 标记是否超分
            })

            WebDKP_Bid_UpdateTable();  -- 更新出价表
            
            -- 只在进入倒计时阶段(≤10秒)才重置计时为10秒
            if (WebDKP_bidCountdown <= 10 and WebDKP_bidCountdown > 0) then
                WebDKP_bidCountdown = 10;
                WebDKP_BidFrame_Countdown:SetText("Time Left: "..WebDKP_bidCountdown.."s");
                
                -- 获取当前最高出价者和出价
                local highestBidder, highestBid = WebDKP_Bid_GetHighestBid();
                
                if (highestBidder and highestBid > 0) then
                    -- 显示绿色消息：现在最高分是某某出的XX分，倒计时重置为10秒！

                    WebDKP_SendChatMessage("|cff00FF00" .. "现在最高分是 "..highestBidder.." 出的 "..highestBid.." 分，倒计时重置为10秒！".. "|r", "RAID");
                else
                    -- 如果没有人出过价
                    local _,_,link = WebDKP_GetItemInfo(WebDKP_bidItem);
                    WebDKP_SendChatMessage(link.." 目前无人出分，现在开始倒计时", "RAID");
                end
            end
        end
    end
end
-- ================================
-- Sends a message to the specified chat channel
-- ================================
function WebDKP_SendChatMessage(message, channel)
    SendChatMessage(message, channel);  -- 发送消息到指定频道
end

-- ================================
-- Returns the highest bidder and what they bid. 
-- ================================
function WebDKP_Bid_GetHighestBid()
	local highestBidder = nil;
	local highestBid = 0; 

	for key_name, v in pairs(WebDKP_BidList) do
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
function WebDKP_Bid_AwardSelected()
	-- find out who is selected
	local player, bid = WebDKP_Bid_GetSelected();
	-- if someone is selected, award them the item via the award class
	if ( player == nil ) then 
		WebDKP_Print("没有选中");
		PlaySound("igQuestFailed");
	else
		-- 获取玩家当前 DKP
		local currentDKP = WebDKP_GetDKP(player);
		
		-- 检查玩家是否有足够的 DKP
		-- if (bid > currentDKP) then
		-- 	WebDKP_Print("无法奖励物品给" .. player .. "，因为出价" .. bid .. "分超过了可用的" .. currentDKP .. "分！");
		-- 	PlaySound("igQuestFailed");
		-- 	return;
		-- end
		
		--since we are awarding, stop the bid
		if ( WebDKP_bidInProgress) then
			WebDKP_Bid_StopBid();
		end
			
		--See how many points the person will lose
		local points = bid * -1;
		--put this into a points table for the add dkp method
		local playerTable = { [0] = {
				["name"] = player,
				["class"] = WebDKP_GetPlayerClass(player),
			}};
		--award the item
		local tableid = WebDKP_GetTableid()
		WebDKP_AddDKP(points, WebDKP_bidItem, "true", playerTable, tableid)
		WebDKP_AnnounceAwardItem(points, WebDKP_bidItem, player);
		-- Update the table so we can see the new dkp status
		WebDKP_UpdateTableToShow();
		WebDKP_UpdateTable();
		PlaySound("LOOTWINDOWCOINSOUND");
			
		WebDKP_Bid_HideUI();
	end
end

-- ================================
-- Event handler for the start / stop bid button. 
-- This button toggles between states when clicked. 
-- ================================
function WebDKP_Bid_ButtonHandler()

	if(WebDKP_bidInProgress) then
		WebDKP_Bid_StopBid();		
	else
		local item = WebDKP_BidFrameItem:GetText();
		local time = WebDKP_BidFrameTime:GetText();
		WebDKP_Bid_StartBid(item, time);
	end
end

-- ================================
-- Method invoked when the user clicks the award button the on 
-- bid frame. Finds the first person who is selected
-- and awards them the item. 
-- ================================
function WebDKP_Bid_GetSelected()
	for key_name, v in pairs(WebDKP_BidList) do
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
function WebDKP_Bid_OnUpdate(elapsed)	
	this.TimeSinceLastUpdate = this.TimeSinceLastUpdate + elapsed; 	

	if (this.TimeSinceLastUpdate > 1.0) then
		this.TimeSinceLastUpdate = 0;
		-- decrement the count down
		WebDKP_bidCountdown = WebDKP_bidCountdown - 1;
		--WebDKP_Print(WebDKP_bidCountdown);
		WebDKP_BidFrame_Countdown:SetText("Time Left: "..WebDKP_bidCountdown.."s");
		
		
		if ( WebDKP_bidCountdown == 30 ) then				-- 30 seconds left
			local _,_,link = WebDKP_GetItemInfo(WebDKP_bidItem); 
			WebDKP_SendCountdownMessage("30秒后结束竞拍 "..link.."!");
		
		elseif ( WebDKP_bidCountdown == 10 ) then				-- 10 seconds left
			local _,_,link = WebDKP_GetItemInfo(WebDKP_bidItem); 
			
			-- 获取当前最高出价者和出价
			local highestBidder, highestBid = WebDKP_Bid_GetHighestBid();
			
			if (highestBidder and highestBid > 0) then
				-- 播报当前最高分状态     
				WebDKP_SendCountdownMessage("目前 "..link.." 最高分是 "..highestBidder.." 出的 "..highestBid.." 分，开始倒计时！");
			else
				-- 如果没有人出过价
				WebDKP_SendCountdownMessage(link.." 目前无人出分，现在开始倒计时！");
			end
	     elseif ( WebDKP_bidCountdown == 9 ) then			
			WebDKP_SendCountdownMessage("倒计时9秒");
		elseif ( WebDKP_bidCountdown == 8 ) then			
			WebDKP_SendCountdownMessage("倒计时8秒");
		elseif ( WebDKP_bidCountdown == 7 ) then			
			WebDKP_SendCountdownMessage("倒计时7秒");
		elseif ( WebDKP_bidCountdown == 6 ) then			
			WebDKP_SendCountdownMessage("倒计时6秒");
	    elseif ( WebDKP_bidCountdown == 5 ) then			
			WebDKP_SendCountdownMessage("倒计时5秒");
		elseif ( WebDKP_bidCountdown == 4 ) then			
			WebDKP_SendCountdownMessage("倒计时4秒");
		elseif ( WebDKP_bidCountdown == 3 ) then			
			WebDKP_SendCountdownMessage("倒计时3秒");
		elseif ( WebDKP_bidCountdown == 2 ) then			
			WebDKP_SendCountdownMessage("倒计时2秒");
	    elseif ( WebDKP_bidCountdown == 1 ) then			
			WebDKP_SendCountdownMessage("倒计时1秒");
		elseif ( WebDKP_bidCountdown <= 0 ) then			-- countdown reached 0

			-- stop the bidding!
			WebDKP_Bid_StopBid();
		  
		end
	end
end

-- ================================
-- Invoked when a user uses shift+click to display item details. 
-- As long as a bid is not in progress and the big gui is displayed, 
-- fill the item information into the form
-- ================================
function WebDKP_Bid_ItemChatClick(link, text, button)
	if ( IsShiftKeyDown() and WebDKP_BidFrame:IsShown() and WebDKP_bidInProgress == false ) then
		local _,itemName,_ = WebDKP_GetItemInfo(link); 
		WebDKP_BidFrameItem:SetText(itemName);
	end
end

