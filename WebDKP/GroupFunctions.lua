------------------------------------------------------------------------
-- GROUP FUNCTIONS
------------------------------------------------------------------------
-- This file contains methods related to working with the dkp table
-- and the current group. 
-- Contained in here are methods to:
-- *	Scan your group to find out what players are currently in it
-- *	Update the 'table to show' which determines the dkp table to show based on members
--		of your group, the current dkp table, and any filters that are selected
-- *	Update the gui with the table to show
------------------------------------------------------------------------

-- ================================
-- Rerenders the table to the screen. This is called 
-- on a few instances - when the scroll frame throws an 
-- event or when filters are applied or when group
-- memebers change. 
-- General structure:
-- First runs through the table to display and puts the data
-- into a temp array to work with
-- Then uses sorting options to sort the temp array
-- Calculates the offset of the table to determine
-- what information needs to be displayed and in what lines 
-- of the table it should be displayed
-- ================================
-- 如果WebDKP_Decay.lua已经重写了此函数，则不定义
if WebDKP_CurrentMode == nil then
function WebDKP_UpdateTable()
	--self:Print("Scroll method called");
	-- Copy data to the temporary array
	local entries = { };
	for k, v in pairs(WebDKP_DkpTableToShow) do
		if ( type(v) == "table" ) then
			if( v[1] ~= nil and v[2] ~= nil and v[3] ~=nil and v[4] ~=nil) then
				-- 检查是否在衰减页面
				local decayFrame = getglobal("WebDKP_DecayFrame")
				if decayFrame and decayFrame:IsVisible() then
					-- 在衰减页面，显示衰减值
				local decayValue = 0
				if WebDKP_DecayData and WebDKP_DecayData.decayValues and WebDKP_DecayData.decayValues[v[1]] then
					local decayInfo = WebDKP_DecayData.decayValues[v[1]]
					decayValue = decayInfo.decayAmount or 0
				end
					tinsert(entries,{v[1],v[2],v[3],decayValue}); -- name, class, dkp, decayValue
				else
					tinsert(entries,{v[1],v[2],v[3],v[4]}); -- copies over name, class, dkp, tier
				end
			end
		end
	end
	
	-- SORT
	table.sort(
		entries,
		function(a1, a2)
			if ( a1 and a2 ) then
				if ( a1 == nil ) then
					return 1>0;
				elseif (a2 == nil) then
					return 1<0;
				end
				if ( WebDKP_LogSort["way"] == 1 ) then
					if ( a1[WebDKP_LogSort["curr"]] == a2[WebDKP_LogSort["curr"]] ) then
						return a1[1] > a2[1];
					else
						return a1[WebDKP_LogSort["curr"]] > a2[WebDKP_LogSort["curr"]];
					end
				else
					if ( a1[WebDKP_LogSort["curr"]] == a2[WebDKP_LogSort["curr"]] ) then
						return a1[1] < a2[1];
					else
						return a1[WebDKP_LogSort["curr"]] < a2[WebDKP_LogSort["curr"]];
					end
				end
			end
		end
	);
	
	local numEntries = getn(entries);
	local offset = FauxScrollFrame_GetOffset(WebDKP_FrameScrollFrame);
	FauxScrollFrame_Update(WebDKP_FrameScrollFrame, numEntries, 20, 20);
	
	-- Run through the table lines and put the appropriate information into each line
	for i=1, 20, 1 do
		local line = getglobal("WebDKP_FrameLine" .. i);
		local nameText = getglobal("WebDKP_FrameLine" .. i .. "Name");
		local classText = getglobal("WebDKP_FrameLine" .. i .. "Class");
		local dkpText = getglobal("WebDKP_FrameLine" .. i .. "DKP");
		local tierText = getglobal("WebDKP_FrameLine" .. i .. "Tier");
		local index = i + FauxScrollFrame_GetOffset(WebDKP_FrameScrollFrame); 
		
		if ( index <= numEntries) then
			local playerName = entries[index][1];
			line:Show();
			nameText:SetText(entries[index][1]);
			classText:SetText(entries[index][2]);
			dkpText:SetText(entries[index][3]);
			
			-- 检查是否在衰减页面
			local decayFrame = getglobal("WebDKP_DecayFrame")
			if decayFrame and decayFrame:IsVisible() then
				-- 在衰减页面，显示衰减值
				local decayValue = 0
				
				-- 获取当前设置
				local baseScore = 0
				local decayRate = 0.1
				if WebDKP_DecayFrameBaseScoreEdit then
					baseScore = tonumber(WebDKP_DecayFrameBaseScoreEdit:GetText()) or 0
				end
				if WebDKP_DecayFrameDecayRateEdit then
					decayRate = tonumber(WebDKP_DecayFrameDecayRateEdit:GetText()) or 0.1
				end
				
				-- 计算预计衰减值
				local playerDkp = entries[index][3]
				if playerDkp > baseScore then
					local excessPoints = playerDkp - baseScore
					decayValue = excessPoints * decayRate *0.01
				end
				
				-- 获取小数位数设置
				local precision = 0
				if WebDKP_DecayData and WebDKP_DecayData.precision then
					precision = WebDKP_DecayData.precision
				end
				
				-- 格式化显示
				if decayValue > 0 then
					local precisionFormat = "%0." .. precision .. "f"
					local displayValue = string.format(precisionFormat, decayValue)
					tierText:SetText("|cffff0000-" .. displayValue .. "|r")
				tierText:SetJustifyH("RIGHT")
					
				else
					tierText:SetText("");
				tierText:SetJustifyH("RIGHT")
				
				end
			else
				-- 正常页面，显示阶层
				tierText:SetText(entries[index][4]);
				tierText:SetJustifyH("RIGHT")
			end
			-- kill the background of this line if it is not selected
			if( not WebDKP_DkpTable[playerName]["Selected"] ) then
				getglobal("WebDKP_FrameLine" .. i .. "Background"):SetVertexColor(0, 0, 0, 0);
			else
				getglobal("WebDKP_FrameLine" .. i .. "Background"):SetVertexColor(0.1, 0.1, 0.9, 0.8);
			end
		else
			-- if the line isn't in use, hide it so we dont' have mouse overs
			line:Hide();
		end
	end
end

-- ================================
-- Global decay function for the current DKP table.
-- Applies percentage based DKP decay to all entries in the table.
-- Using ceil so sub 10 dkp entries eventually dissipate to 0.
-- ================================

function WebDKP_ApplyGlobalDecay(rate)

	local player = {};

	if rate>1 or rate<=0 then
		WebDKP_Print("Bad decay rate. Rate should be within [0,1]. Use 0.1 to apply a 10% reduction for example.");
		return;
	end
	
	local tableid = WebDKP_GetTableid();
	
	for k, v in pairs(WebDKP_DkpTable) do
		if ( type(v) == "table" and v["dkp_"..tableid] >= 1) then
			player[0] = {
					["name"] = k,
					["class"] = v["class"],
				};
			WebDKP_AddDKP((ceil(v["dkp_"..tableid]*rate)*(-1)), k.." decay", "false", player, tableid)	
		end	
		
	end
end


-- ================================
-- Helper method that determines the table that should be shown. 
-- This runs through the dkp list and checks filters against each entry
-- If an entry passes it is moved to the table to show. If it doesn't pass
-- the test it is ignored. 
-- ================================
function WebDKP_UpdateTableToShow()
	local tableid = WebDKP_GetTableid();
	-- clear the old table
	WebDKP_DkpTableToShow = { };
	-- increment through the dkp table and move data over
	for k, v in pairs(WebDKP_DkpTable) do
		if ( type(v) == "table" ) then
			local playerName = k; 
			local playerClass = v["class"];
			local playerDkp = v["dkp_"..tableid];
			if ( playerDkp == nil ) then 
				v["dkp"..tableid] = 0;
				playerDkp = 0;
			end
			local playerTier = floor((playerDkp-1)/WebDKP_TierInterval);
			if( playerDkp == 0 ) then
				playerTier = 0;
			end
			-- if it should be displayed (passes filter) add it to the table
			if (WebDKP_ShouldDisplay(playerName, playerClass, playerDkp, playerTier)) then
				tinsert(WebDKP_DkpTableToShow,{playerName,playerClass,playerDkp,playerTier});
			end
		end
	end
	-- now need to run through anyone else who is in our current raid / party
	-- They may not have dkp yet and may not be in our dkp table. Use this oppurtunity 
	-- to add them to the table with 0 points and add them to the to display table if appropriate
	-- table to be displayed
	for key, entry in pairs(WebDKP_PlayersInGroup) do
		if ( type(entry) == "table" ) then
			local playerName = entry["name"];
			-- is this a new person we havn't seen before?
			if ( WebDKP_DkpTable[playerName] == nil) then
				-- new person, they need to be added
				local playerClass = entry["class"];
				local playerDkp = 0;
				local playerTier = 0;
				-- go ahead and add them to our dkp table now, for future reference
				if( not (playerName == nil) ) then
					WebDKP_DkpTable[playerName] = {
						["dkp_"..tableid] = 0,
						["class"] = playerClass,
					}
				end
				-- do a final check to see if we should display (pass all filters, etc.)
				if (WebDKP_ShouldDisplay(playerName, playerClass, playerDkp, playerTier)) then
					tinsert(WebDKP_DkpTableToShow,{playerName,playerClass,playerDkp,playerTier});
				else
					WebDKP_DkpTable[playerName]["Selected"] = false;
				end
			end
		end
	end
end
end


-- ================================
-- Updates the list of players in our current group.
-- First attempts to get raid data. If user isn't in a raid
-- it checks party data. If user is not in a party there 
-- is no information to get
-- ================================
function WebDKP_UpdatePlayersInGroup()
	-- Updates the list of players currently in the group
	-- First attempts to get this data via a query to the raid. 
	-- If that failes it resorts to querying for party data
	local numberInRaid = GetNumRaidMembers();
	local numberInParty = GetNumPartyMembers();
	WebDKP_PlayersInGroup = {};
	-- Is a raid going?
	if ( numberInRaid > 0 ) then
		-- Yes! Load raid data...
		local name, class, guild;
		for i=1, numberInRaid do
			name, _, _, _, class, _, _, _ , _ = GetRaidRosterInfo(i);
			WebDKP_PlayersInGroup[i]=
			{
				["name"] = name,
				["class"] = class,
			};
		end
	-- Is a party going?
	elseif ( numberInRaid == 0 and numberInParty>0) then
		-- Yes! Load party data instead...
		local name, class, guild, playerHandle;
		for i=1, numberInParty do
			playerHandle = "party"..i;
			name = UnitName(playerHandle);
			class = UnitClass(playerHandle);
			WebDKP_PlayersInGroup[i]=
			{
				["name"] = name,
				["class"] = class,
			};
		end
		-- this doesn't load the current player, so we need to add them manually
		WebDKP_PlayersInGroup[numberInParty+1]=
		{
			["name"] = UnitName("player"),
			["class"] = UnitClass("player"),
		};
	end
	-- not in party or raid, don't need to load anything special
end


-- ================================
-- Returns true if everyone in the current group is selected. 
-- This is a helper method when displaying messages to chat. 
-- If everyone is selected you can just say "awarded points to everyone"
-- versus listing out everyone who was selected invidiually
-- ================================
function WebDKP_AllGroupSelected()
	-- First try running through the raid and see if they are all selected
	local name, class;
	local numberInRaid = GetNumRaidMembers();
	local numberInParty = GetNumPartyMembers();
	if(numberInRaid > 0 ) then
		for i=1, numberInRaid do
			name, _, _, _, _, _, _, _ , _ = GetRaidRosterInfo(i);
			if ( not WebDKP_DkpTable[name]["Selected"]) then
				return false;
			end
		end
		return true;
	elseif ( numberInParty > 0) then
		for i=1, numberInParty do
			playerHandle = "party"..i;
			name = UnitName(playerHandle);
			if ( not WebDKP_DkpTable[name]["Selected"]) then
				return false;
			end
		end
		--before we return true we also need to check the current player...
		if ( not WebDKP_DkpTable[UnitName("player")]["Selected"]) then
			return false;
		end
		return true;
	end
	-- entire group isn't selected, do things manually
	return false;
end


-- ================================
-- Helper method. Returns true if the current player should be displayed
-- on the table by checking it against current filters
-- ================================
function WebDKP_ShouldDisplay(name, class, dkp, tier)
	-- 名称过滤逻辑
	local searchBox = getglobal("WebDKP_NameSearchBox")
	if searchBox then
		local searchText = searchBox:GetText()
		if searchText and searchText ~= "" then
			-- 将搜索文本和玩家名称都转为小写进行比较
			local lowerSearchText = string.lower(searchText)
			local lowerPlayerName = string.lower(name)
			if string.find(lowerPlayerName, lowerSearchText) == nil then
				return false
			end
		end
	end
	
	-- 如果"显示所有"过滤器开启，直接返回true
	if WebDKP_Filters["All"] and WebDKP_Filters["All"] == 1 then
		return true;
	end
	
	if (name == "Unknown") then
		return false;
	end
	
	-- 中英文职业名称映射，支持潜行者/盗贼别名
	local classMap = {
		["德鲁伊"] = "Druid",
		["猎人"] = "Hunter",
		["法师"] = "Mage",
		["盗贼"] = "Rogue",
		["潜行者"] = "Rogue",
		["萨满祭司"] = "Shaman",
		["圣骑士"] = "Paladin",
		["牧师"] = "Priest",
		["战士"] = "Warrior",
		["术士"] = "Warlock"
	}
	
	-- 将中文职业名称转换为英文
	local englishClass = classMap[class] or class
	
	-- 检查职业过滤器
	if (WebDKP_Filters[englishClass] == 0) then
		return false;
	end 
	if (WebDKP_Filters["Group"] == 1 and WebDKP_PlayerInGroup(name) == false) then
		return false
	end
	
	-- 检查是否为替补项目相关的记录
	-- 这里我们需要检查玩家是否有替补相关的记录
	-- 并且如果该玩家只有替补加分，则不显示在DKP列表中
	local tableid = WebDKP_GetTableid();
	local playerInfo = WebDKP_DkpTable[name];
	
	if playerInfo and playerInfo["dkp_"..tableid] and playerInfo["dkp_"..tableid] > 0 then
		-- 检查WebDKP_Log中是否只有替补相关的记录
		local hasNonSubstituteRecord = false;
		local hasSubstituteRecord = false;
		local totalPoints = 0;
		local substitutePoints = 0;
		
		if WebDKP_Log then
			for key, entry in pairs(WebDKP_Log) do
				if key ~= "Version" and type(entry) == "table" and entry.awarded and entry.awarded[name] then
					local isForItem = entry.foritem == "true" or entry.foritem == true;
					local isSubstitute = entry.reason and string.find(entry.reason, "替补");
					local points = tonumber(entry.points) or 0;
					
					-- 累加总分数
					totalPoints = totalPoints + points;
					
					if isSubstitute and not isForItem then
						hasSubstituteRecord = true;
						substitutePoints = substitutePoints + points;
					elseif not isSubstitute then
						hasNonSubstituteRecord = true;
						break; -- 只要有一个非替补记录，就可以显示
					end
				end
			end
		end
		
		-- 如果只有替补记录，没有其他记录，则不显示在DKP列表中
		-- 同时检查玩家的DKP分数是否全部来自替补加分
		local hasOnlySubstitutePoints = (hasSubstituteRecord and not hasNonSubstituteRecord) or 
		                              (playerInfo["dkp_"..tableid] == substitutePoints and substitutePoints > 0);
		
		if hasOnlySubstitutePoints then
			return false;
		end
	end
	
	-- 衰减页面特殊过滤：只显示分数大于底分的玩家
	local decayFrame = getglobal("WebDKP_DecayFrame")
	if decayFrame and decayFrame:IsVisible() then
		-- 获取底分设置
		local baseScore = 0
		if WebDKP_DecayFrameBaseScoreEdit then
			baseScore = tonumber(WebDKP_DecayFrameBaseScoreEdit:GetText()) or 0
		end
		
		-- 只显示分数大于底分的玩家
		if dkp <= baseScore then
			-- WebDKP_Print("隐藏玩家: " .. name .. " (分数" .. dkp .. " <= 底分" .. baseScore .. ")")
			return false
		else
			-- WebDKP_Print("显示玩家: " .. name .. " (分数" .. dkp .. " > 底分" .. baseScore .. ")")
		end
	end
	
	return true; 
end
