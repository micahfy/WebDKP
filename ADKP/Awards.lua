------------------------------------------------------------------------
-- AWARDS	
------------------------------------------------------------------------
-- This file contains methods related to awarding/deducting DKP and 
-- items. It also contains methods for appending this data to the log file. 
------------------------------------------------------------------------
 local GetNumGuildMembers = GetNumGuildMembers;
 local GetGuildRosterInfo = GetGuildRosterInfo;

-- ================================
-- Called when user clicks on the 'award item' box. 
-- Gets the first selected player in the list, and the
-- contents of the award item edit boxes. Uses this to 
-- display a short blirb to the screen then recordes 
-- the changes
-- ================================
function ADKP_AwardItem_Event()
	local name, class, guild;
	local cost = ADKP_AwardItem_FrameItemCost:GetText();
	local item = ADKP_AwardItem_FrameItemName:GetText();
	if ( item == nil or item=="" ) then
		ADKP_Print("您必须输入物品名称.");
		PlaySound("igQuestFailed");
		return;
	end
	if ( cost == nil or cost=="") then
		ADKP_Print("您必须输入一个物品成本.");
		PlaySound("igQuestFailed");
		return;
	end

	cost = ADKP_ROUND(cost,2);

	-- 确保cost是有效数字
	if (type(cost) ~= "number" or cost ~= cost) then
		ADKP_Print("物品成本必须是有效数字.");
		PlaySound("igQuestFailed");
		return;
	end

	local points = cost * -1;
	local player = ADKP_GetSelectedPlayers(1);
	
	if ( player == nil ) then
		ADKP_Print("没有玩家选择奖惩. 奖惩无效.");
		PlaySound("igQuestFailed");
	else
		local recordRef = ADKP_AddDKP(points, item, "true", player)
		ADKP_AnnounceAwardItem(points, item, player[0]["name"], false, recordRef);

		ADKP_UpdateTable();
		ADKP_UpdateTableToShow()
        ADKP_UpdateLootList();
		
	end
end



-- ================================
-- Adds the specified dkp / reason to all selected players
-- If this is an item award, it is only awarded to the first player
-- If it is an item award and zero-sum is used, an automatted
-- zero sum award is also given
-- ================================
function ADKP_AddDKP(points, reason, forItem, players, ignoredTableId, awardDate)
	-- 验证points参数
	if (points == nil) then
		points = 0;
	end
	
	points = tonumber(points) or 0;

	if (type(points) ~= "number" or points ~= points) then
		ADKP_Print("错误: 无效的DKP点数.");
		return;
	end

	-- 统一规范到 2 位小数，从源头杜绝浮点累加误差
	points = ADKP_ROUND(points, 2);
	
	local date  = awardDate or date("%Y-%m-%d %H:%M:%S");
	local location = GetZoneText();
	local tableid = ADKP_GetTableid();
	local awardedBy = UnitName("player");
		
	reason = string.gsub(string.gsub(reason, ".*%[", ""), "%].*", "");
	
	if (not WebDKP_Log) then
		WebDKP_Log = {};
	end
	local baseLogKey = reason.." "..date
	local logKey = baseLogKey
	local duplicateIndex = 2
	while WebDKP_Log[logKey] do
		logKey = baseLogKey.." #"..duplicateIndex
		duplicateIndex = duplicateIndex + 1
	end
	WebDKP_Log[logKey] = {};
	
	WebDKP_Log["Version"] = 2;
	WebDKP_Log[logKey]["reason"] = reason;
	WebDKP_Log[logKey]["date"] = date;
	WebDKP_Log[logKey]["foritem"] = forItem;
	WebDKP_Log[logKey]["zone"] = location;
	WebDKP_Log[logKey]["tableid"] = tableid;
	WebDKP_Log[logKey]["awardedby"] = awardedBy;
	WebDKP_Log[logKey]["points"] = points;
	-- 添加唯一标识符用于记录修改
	WebDKP_Log[logKey]["uniqueId"] = logKey;
	
	if (not WebDKP_Log[logKey]["awarded"]) then
		WebDKP_Log[logKey]["awarded"] = {};
	end
	
	-- 记录本次实际传入 AddDKP 的加分名单，供公告使用；不要再依赖全局 Selected 残留。
	ADKP_LastAwardPlayers = {};
	ADKP_LastAwardPlayerCount = 0;
	
	for k, v in pairs(players) do
		if ( type(v) == "table" ) then
			name = v["name"]; 
			class = v["class"];
			if name and name ~= "" then
				ADKP_LastAwardPlayerCount = ADKP_LastAwardPlayerCount + 1;
				ADKP_LastAwardPlayers[ADKP_LastAwardPlayerCount] = name;
			end
			guild = ADKP_GetGuildName(name);
			ADKP_AddDKPToTable(name, class, points);
			--add them to the log entry
			WebDKP_Log[logKey]["awarded"][name] = {};
			WebDKP_Log[logKey]["awarded"][name]["name"]=name;
			WebDKP_Log[logKey]["awarded"][name]["guild"]=guild;
			WebDKP_Log[logKey]["awarded"][name]["class"]=class;

			-- If awarding an item, only 1 person should be recorded as having recieved it
			if ( forItem == "true" ) then
				break
			end
		end
	end

	-- 保存数据到磁盘
	if ADKP_SaveToDisk then
		ADKP_SaveToDisk();
	end
	
	-- 更新数据列表，确保所有DKP变更后立即刷新
	if ADKP_UpdateLootList then
		ADKP_UpdateLootList();
	end
	
	-- 刷新DKP主窗口
	if ADKP_MainFrame then
		ADKP_MainFrame:Show();
		ADKP_MainFrame:Update();
	end
	
	ADKP_UpdateTable();
	ADKP_UpdateTableToShow()
	ADKP_UpdateLootList();

	return {
		key = logKey,
		uniqueId = WebDKP_Log[logKey] and WebDKP_Log[logKey].uniqueId,
		tableid = tableid,
		date = date
	}
end

function ADKP_AddDKPToTable(name, class, points)
    local tableid = ADKP_GetTableid();
    
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
    WebDKP_DkpTable[name]["dkp_"..tableid] = ADKP_ROUND(WebDKP_DkpTable[name]["dkp_"..tableid] + points, 2);
end




-- ================================
-- Returns a table of all the selected players from the main dkp table.
-- Limit specifiecs the maximum number players that should be returned. 
-- If limit = 0, there is no limit
-- ================================
function ADKP_GetSelectedPlayers(limit) 
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

