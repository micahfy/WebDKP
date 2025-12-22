------------------------------------------------------------------------
-- AWARDS	
------------------------------------------------------------------------
-- This file contains methods related to awarding/deducting DKP and 
-- items. It also contains methods for appending this data to the log file. 
------------------------------------------------------------------------
 local GetNumGuildMembers = GetNumGuildMembers;
 local GetGuildRosterInfo = GetGuildRosterInfo;
 local GuildRosterSetOfficerNote = GuildRosterSetOfficerNote;

-- ================================
-- Called when user clicks on the 'award item' box. 
-- Gets the first selected player in the list, and the
-- contents of the award item edit boxes. Uses this to 
-- display a short blirb to the screen then recordes 
-- the changes
-- ================================
function WebDKP_AwardItem_Event()
	local name, class, guild;
	local cost = WebDKP_AwardItem_FrameItemCost:GetText();
	local item = WebDKP_AwardItem_FrameItemName:GetText();
	if ( item == nil or item=="" ) then
		WebDKP_Print("您必须输入物品名称.");
		PlaySound("igQuestFailed");
		return;
	end
	if ( cost == nil or cost=="") then
		WebDKP_Print("您必须输入一个物品成本.");
		PlaySound("igQuestFailed");
		return;
	end

	cost = WebDKP_ROUND(cost,2);

	-- 确保cost是有效数字
	if (type(cost) ~= "number" or cost ~= cost) then
		WebDKP_Print("物品成本必须是有效数字.");
		PlaySound("igQuestFailed");
		return;
	end

	local points = cost * -1;
	local player = WebDKP_GetSelectedPlayers(1);
	
	if ( player == nil ) then
		WebDKP_Print("没有玩家选择奖惩. 奖惩无效.");
		PlaySound("igQuestFailed");
	else
		WebDKP_AddDKP(points, item, "true", player)
		WebDKP_AnnounceAwardItem(points, item, player[0]["name"]);

		WebDKP_UpdateTable();
		WebDKP_UpdateTableToShow()
        WebDKP_UpdateLootList();
		
	end
end

-- ================================
-- Called when user clicks on 'award dkp' on the award 
-- dkp tab. Gets data from the award dkp edit boxes. 
-- Uses this to display a little blirb, then recodes
-- this information for all players currently selected
-- (note, if player is hidden due to filter, they are automattically
-- deselected)
-- ================================
function WebDKP_AwardDKP_Event()
	local name, class, guild;
	local points = WebDKP_AwardDKP_FramePoints:GetText();
	local reason = WebDKP_AwardDKP_FrameReason:GetText();

	if ( points == nil or points=="") then
		WebDKP_Print("您必须输入DKP.");
		PlaySound("igQuestFailed");
		return;
	end
	
	points = WebDKP_ROUND(points,2);
	
	-- 确保points是有效数字
	if (type(points) ~= "number" or points ~= points) then
		WebDKP_Print("DKP点数必须是有效数字.");
		PlaySound("igQuestFailed");
		return;
	end
	
	local players = WebDKP_GetSelectedPlayers(0);
	
	if ( players == nil ) then
		WebDKP_Print("没有玩家被选中. 奖惩无效.");
		PlaySound("igQuestFailed");
	else 
		WebDKP_AddDKP(points, reason, "false", players)
	    WebDKP_AnnounceAward(points,reason);

		-- 更新表格，以便我们能看到新的dkp状态
		WebDKP_UpdateTable();
		WebDKP_UpdateTableToShow();
		WebDKP_UpdateLootList();
	    
	end
end



-- ================================
-- Adds the specified dkp / reason to all selected players
-- If this is an item award, it is only awarded to the first player
-- If it is an item award and zero-sum is used, an automatted
-- zero sum award is also given
-- ================================
function WebDKP_AddDKP(points, reason, forItem, players)
	-- 验证points参数
	if (points == nil) then
		points = 0;
	end
	
	points = tonumber(points) or 0;
	
	if (type(points) ~= "number" or points ~= points) then
		WebDKP_Print("错误: 无效的DKP点数.");
		return;
	end
	
	local date  = date("%Y-%m-%d %H:%M:%S");
	local location = GetZoneText();
	local tableid = WebDKP_GetTableid();
	local awardedBy = UnitName("player");
		
	reason = string.gsub(string.gsub(reason, ".*%[", ""), "%].*", "");
	
	if (not WebDKP_Log) then
		WebDKP_Log = {};
	end
	--next, make sure this player is in the log
	if (not WebDKP_Log[reason.." "..date]) then
		WebDKP_Log[reason.." "..date] = {};
	end
	
	WebDKP_Log["Version"] = 2;
	WebDKP_Log[reason.." "..date]["reason"] = reason;
	WebDKP_Log[reason.." "..date]["date"] = date;
	WebDKP_Log[reason.." "..date]["foritem"] = forItem;
	WebDKP_Log[reason.." "..date]["zone"] = location;
	WebDKP_Log[reason.." "..date]["tableid"] = tableid;
	WebDKP_Log[reason.." "..date]["awardedby"] = awardedBy;
	WebDKP_Log[reason.." "..date]["points"] = points;
	-- 添加唯一标识符用于记录修改
	WebDKP_Log[reason.." "..date]["uniqueId"] = reason.." "..date;
	
	if (not WebDKP_Log[reason.." "..date]["awarded"]) then
		WebDKP_Log[reason.." "..date]["awarded"] = {};
	end
	
	
	for k, v in pairs(players) do
		if ( type(v) == "table" ) then
			name = v["name"]; 
			class = v["class"];
			guild = WebDKP_GetGuildName(name);
			WebDKP_AddDKPToTable(name, class, points);
			--add them to the log entry
			WebDKP_Log[reason.." "..date]["awarded"][name] = {};
			WebDKP_Log[reason.." "..date]["awarded"][name]["name"]=name;
			WebDKP_Log[reason.." "..date]["awarded"][name]["guild"]=guild;
			WebDKP_Log[reason.." "..date]["awarded"][name]["class"]=class;

			-- If awarding an item, only 1 person should be recorded as having recieved it
			if ( forItem == "true" ) then
				break;
			end
		end
	end
	
	-- if this is an item award and we are using zero-sum dkp, we need to give automated
	-- zero sum awards too
	if ( WebDKP_WebOptions["ZeroSumEnabled"]==1 and forItem=="true") then
		WebDKP_AwardZeroSum(points, reason, date, forItem);
	end
	
	-- 保存数据到磁盘
	if WebDKP_SaveToDisk then
		WebDKP_SaveToDisk();
	end
	
	-- 更新数据列表，确保所有DKP变更后立即刷新
	if WebDKP_UpdateLootList then
		WebDKP_UpdateLootList();
	end
	
	-- 刷新DKP主窗口
	if WebDKP_MainFrame then
		WebDKP_MainFrame:Show();
		WebDKP_MainFrame:Update();
	end
	

	WebDKP_UpdateTable();
		WebDKP_UpdateTableToShow()
        WebDKP_UpdateLootList();
end

-- 全局更新队列和状态变量
WebDKP_UpdateQueue = WebDKP_UpdateQueue or {}
WebDKP_IsUpdating = WebDKP_IsUpdating or false
WebDKP_UpdateTimer = WebDKP_UpdateTimer or nil

function WebDKP_ProcessNextUpdate()
    if table.getn(WebDKP_UpdateQueue) == 0 then
        WebDKP_IsUpdating = false
        WebDKP_Print("全团DKP更新完成")
		        -- 自动备份数据（如果启用）
        if WebDKP_Options and WebDKP_Options["AutoBackupEnabled"] then
		WebDKP_BackupData()
	    end
        return
    end
    
    local update = table.remove(WebDKP_UpdateQueue, 1)
    GuildRosterSetOfficerNote(update.index, update.note)
    
    -- local playerName = GetGuildRosterInfo(update.index) or "未知玩家"
    -- WebDKP_Print(string.format("已更新 %s 的DKP (剩余: %d)", playerName, table.getn(WebDKP_UpdateQueue)))
    
    -- 设置下一次更新，严格0.5秒间隔
    -- 使用WoW 1.12兼容的定时器实现
    if not WebDKP_UpdateTimer then
        WebDKP_UpdateTimer = CreateFrame("Frame")
        WebDKP_UpdateTimer.timeToNextUpdate = 0
    end
    
    WebDKP_UpdateTimer.timeToNextUpdate = 0.5
    WebDKP_UpdateTimer:SetScript("OnUpdate", function()
        local elapsed = tonumber(arg1) or 0
        this.timeToNextUpdate = this.timeToNextUpdate - elapsed
        if this.timeToNextUpdate <= 0 then
            this:SetScript("OnUpdate", nil)
            WebDKP_ProcessNextUpdate()
        end
    end)
end

function WebDKP_AddDKPToTable(name, class, points)
    local tableid = WebDKP_GetTableid();
    
    -- 确保玩家条目存在
    if (not WebDKP_DkpTable[name]) then
        WebDKP_DkpTable[name] = {};
        WebDKP_DkpTable[name]["dkp_"..tableid] = 0;
        WebDKP_DkpTable[name]["class"] = class;
    end
    if (WebDKP_DkpTable[name]["dkp_"..tableid] == nil) then
        WebDKP_DkpTable[name]["dkp_"..tableid] = 0;
    end
    
    -- 更新DKP值
    WebDKP_DkpTable[name]["dkp_"..tableid] = WebDKP_DkpTable[name]["dkp_"..tableid] + points;
    
    -- 使用缓存的公会成员索引
    if not WebDKP_GuildMemberIndex then 
        WebDKP_GuildMemberIndex = {} 
        local ngm = GetNumGuildMembers();
        for i=1, ngm do
            local n = GetGuildRosterInfo(i);
            if n then WebDKP_GuildMemberIndex[strlower(n)] = i end
        end
    end
    
    local index = WebDKP_GuildMemberIndex[strlower(name)]
    if index then
        -- 添加到更新队列
        table.insert(WebDKP_UpdateQueue, {
            index = index,
            note = WebDKP_DkpTable[name]["dkp_"..tableid]
        })
        
        -- 如果当前没有在进行更新，则启动更新过程
        if not WebDKP_IsUpdating then
            WebDKP_IsUpdating = true
            WebDKP_ProcessNextUpdate()
        end
    end
end


-- ================================
-- Helper method for ZeroSum Award. Called when a player
-- is recieving an item and the guild is using zero sum. 
-- This method must run through everyone in the current
-- party and give them an award equal to, but opposite
-- the cost of the item just given. 
-- ================================
function WebDKP_AwardZeroSum(points, reason, date, forItem)
	local location = GetZoneText();
	local tableid = WebDKP_GetTableid();
	local awardedBy = UnitName("player");
	WebDKP_UpdatePlayersInGroup();
	
	local numPlayers = WebDKP_GetTableSize(WebDKP_PlayersInGroup);
	if ( numPlayers == 0 ) then
		return;
	end
	
	-- 检查points是否为nil或无效值
	if (points == nil) then
		points = 0;
	end
	
	-- 确保points是数字
	points = tonumber(points) or 0;
	
	-- 再次验证points是有效数字
	if (type(points) ~= "number" or points ~= points) then
		WebDKP_Print("错误: DKP点数无效，无法执行零和奖惩.");
		return;
	end
	
	local toAward = (points * -1) / numPlayers;
	toAward = WebDKP_ROUND(toAward, 2 );
	reason = "ZeroSum: "..reason;
	
	if (not WebDKP_Log) then
		WebDKP_Log = {};
	end
	--next, make sure this player is in the log
	if (not WebDKP_Log[reason.." "..date]) then
		WebDKP_Log[reason.." "..date] = {};
	end
	
	WebDKP_Log[reason.." "..date]["reason"] = reason;
	WebDKP_Log[reason.." "..date]["date"] = date;
	WebDKP_Log[reason.." "..date]["foritem"] = forItem or "";
	WebDKP_Log[reason.." "..date]["zone"] = location;
	WebDKP_Log[reason.." "..date]["tableid"] = tableid;
	WebDKP_Log[reason.." "..date]["awardedby"] = awardedBy;
	WebDKP_Log[reason.." "..date]["points"] = toAward;
	WebDKP_Log[reason.." "..date]["awarded"] = {};
	
	-- 添加唯一标识符用于修改功能
	local uniqueIdPrefix = forItem and "loot" or "award"
	local uniqueId = uniqueIdPrefix.."_"..(WebDKP_GetTableSize(WebDKP_Log) + 1).."_"..reason.."_"..date;
	WebDKP_Log[reason.." "..date]["uniqueId"] = uniqueId;
	
	-- 同步到WebDKP_LootHistory用于修改功能
	if forItem and forItem ~= "" then
		if not WebDKP_LootHistory then
			WebDKP_LootHistory = {}
		end
		table.insert(WebDKP_LootHistory, {
			item = forItem,
			player = "ZeroSum",
			points = -points,  -- 使用points字段，装备花费为负数
			time = date,
			uniqueId = uniqueId
			-- 注意：这里不使用cost字段，只使用points字段表示花费（负数）
		})
	end
	
	for key, entry in pairs(WebDKP_PlayersInGroup) do
		if ( type(entry) == "table" ) then
			local playerName = entry["name"];
			local playerClass = entry["class"];
			local playerGuild = WebDKP_GetGuildName(playerName);
			-- is this a new person we havn't seen before?
			if ( WebDKP_DkpTable[playerName] == nil) then
				-- new person, they need to be added
				local playerDkp = 0;
				local playerTier = 0;
				-- go ahead and add them to our dkp table now, for future reference
				if( not (playerName == nil) ) then
					WebDKP_DkpTable[playerName] = {
						["dkp_"..tableid] = 0,
						["class"] = playerClass,
					}
				end
			end
			
			
			WebDKP_Log[reason.." "..date]["awarded"][playerName] = {};
			WebDKP_Log[reason.." "..date]["awarded"][playerName]["name"]=playerName;
			WebDKP_Log[reason.." "..date]["awarded"][playerName]["guild"]=playerGuild;
			WebDKP_Log[reason.." "..date]["awarded"][playerName]["class"]=playerClass;
			WebDKP_Print("自动奖惩 "..playerName.." 至 "..toAward);
			
			WebDKP_AddDKPToTable(playerName, playerClass, toAward);
		end
	end
end



-- ================================
-- Returns a table of all the selected players from the main dkp table.
-- Limit specifiecs the maximum number players that should be returned. 
-- If limit = 0, there is no limit
-- ================================
function WebDKP_GetSelectedPlayers(limit) 
	local toReturn = {}; 
	local count = 0; 
	for key_name, v in pairs(WebDKP_DkpTable) do
		if ( type(v) == "table" ) then
			if( v["Selected"] ) then
				toReturn[count] = {
					["name"] = key_name,
					["class"] = v["class"],
				}
				count = count + 1; 
				if ( limit~=0 and count >= limit ) then
					return toReturn;
				end
			end		
		end
	end
	if ( count == 0 ) then
		return nil;
	else
		return toReturn;
	end
end