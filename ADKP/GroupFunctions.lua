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

function ADKP_UpdateTable()
	--self:Print("Scroll method called");
	-- Copy data to the temporary array
	local entries = { };
	for k, v in pairs(ADKP_DkpTableToShow) do
		if ( type(v) == "table" ) then
			if( v[1] ~= nil and v[2] ~= nil and v[3] ~=nil and v[4] ~=nil) then
				tinsert(entries,{v[1],v[2],v[3],v[4]}); -- copies over name, class, dkp, tier
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
				if ( ADKP_LogSort["way"] == 1 ) then
					if ( a1[ADKP_LogSort["curr"]] == a2[ADKP_LogSort["curr"]] ) then
						return a1[1] > a2[1];
					else
						return a1[ADKP_LogSort["curr"]] > a2[ADKP_LogSort["curr"]];
					end
				else
					if ( a1[ADKP_LogSort["curr"]] == a2[ADKP_LogSort["curr"]] ) then
						return a1[1] < a2[1];
					else
						return a1[ADKP_LogSort["curr"]] < a2[ADKP_LogSort["curr"]];
					end
				end
			end
		end
	);
	
	local numEntries = getn(entries);
	local offset = FauxScrollFrame_GetOffset(ADKP_FrameScrollFrame);
	FauxScrollFrame_Update(ADKP_FrameScrollFrame, numEntries, 14, 20);
	
	-- Run through the table lines and put the appropriate information into each line
	for i=1, 14, 1 do
		local line = getglobal("ADKP_FrameLine" .. i);
		local nameText = getglobal("ADKP_FrameLine" .. i .. "Name");
		local classText = getglobal("ADKP_FrameLine" .. i .. "Class");
		local dkpText = getglobal("ADKP_FrameLine" .. i .. "DKP");
		local tierText = getglobal("ADKP_FrameLine" .. i .. "Tier");
		local index = i + FauxScrollFrame_GetOffset(ADKP_FrameScrollFrame); 
		
		if ( index <= numEntries) then
			local playerName = entries[index][1];
			line:Show();
			nameText:SetText(entries[index][1]);
			classText:SetText(entries[index][2]);
			dkpText:SetText(entries[index][3]);
			
			-- 正常页面，显示阶层
			if tierText then
				tierText:SetText(entries[index][4] or "");
				tierText:SetJustifyH("RIGHT")
			end
			-- kill the background of this line if it is not selected
			if( not ADKP_DkpTable[playerName]["Selected"] ) then
				getglobal("ADKP_FrameLine" .. i .. "Background"):SetVertexColor(0, 0, 0, 0);
			else
				getglobal("ADKP_FrameLine" .. i .. "Background"):SetVertexColor(0.1, 0.1, 0.9, 0.8);
			end
		else
			if i == 1 and ADKP_ListMode == "sub" and ADKP_SubQueryTimeoutEmpty then
				line:Show();
				nameText:SetText("替补队长不在线或未安装插件。");
				classText:SetText("");
				dkpText:SetText("");
				if tierText then
					tierText:SetText("");
				end
				getglobal("ADKP_FrameLine" .. i .. "Background"):SetVertexColor(0, 0, 0, 0);
			else
				-- if the line isn't in use, hide it so we dont' have mouse overs
				line:Hide();
			end
		end
	end
	
	-- Explicitly hide lines 15 to 20
	for i=15, 20, 1 do
		local line = getglobal("ADKP_FrameLine" .. i);
		if line then
			line:Hide();
		end
	end
	if ADKP_UpdateSingleAdjustLabel then
		ADKP_UpdateSingleAdjustLabel();
	end
end




-- ================================
-- Helper method that determines the table that should be shown. 
-- This runs through the dkp list and checks filters against each entry
-- If an entry passes it is moved to the table to show. If it doesn't pass
-- the test it is ignored. 
-- ================================
function ADKP_UpdateTableToShow()
	local tableid = ADKP_GetTableid();
	-- clear the old table
	ADKP_DkpTableToShow = { };
	-- 替补团队模式：先把同步缓存里的替补名单并入主表，确保下面的循环会遍历到
	if (ADKP_ListMode or "raid") == "sub" then
		local subCap = ""
		if ADKP_Options and ADKP_Options["SubSettings"] then
			subCap = ADKP_Options["SubSettings"].captain or ""
		end
		if subCap ~= "" and ADKP_SubSync_Cache then
			local subC = ADKP_SubSync_Cache[string.lower(subCap)]
			if subC and subC.members then
				for memberName, memberClass in pairs(subC.members) do
					if ADKP_DkpTable[memberName] == nil then
						ADKP_DkpTable[memberName] = { ["dkp_"..tableid] = 0, ["class"] = memberClass }
					end
				end
			end
		end
	end
	-- increment through the dkp table and move data over
	for k, v in pairs(ADKP_DkpTable) do
		if ( type(v) == "table" ) then
			local playerName = k; 
			local playerClass = v["class"];
			local playerDkp = v["dkp_"..tableid];
			if ( playerDkp == nil ) then 
				v["dkp"..tableid] = 0;
				playerDkp = 0;
			end
			local playerTier = floor((playerDkp-1)/ADKP_TierInterval);
			if( playerDkp == 0 ) then
				playerTier = 0;
			end
			-- if it should be displayed (passes filter) add it to the table
			if (ADKP_ShouldDisplay(playerName, playerClass, playerDkp, playerTier)) then
				tinsert(ADKP_DkpTableToShow,{playerName,playerClass,playerDkp,playerTier});
			end
		end
	end
	-- now need to run through anyone else who is in our current raid / party
	-- They may not have dkp yet and may not be in our dkp table. Use this oppurtunity 
	-- to add them to the table with 0 points and add them to the to display table if appropriate
	-- table to be displayed
	for key, entry in pairs(ADKP_PlayersInGroup) do
		if ( type(entry) == "table" ) then
			local playerName = entry["name"];
			-- is this a new person we havn't seen before?
			if ( ADKP_DkpTable[playerName] == nil) then
				-- new person, they need to be added
				local playerClass = entry["class"];
				local playerDkp = 0;
				local playerTier = 0;
				-- go ahead and add them to our dkp table now, for future reference
				if( not (playerName == nil) ) then
					ADKP_DkpTable[playerName] = {
						["dkp_"..tableid] = 0,
						["class"] = playerClass,
					}
				end
				-- do a final check to see if we should display (pass all filters, etc.)
				if (ADKP_ShouldDisplay(playerName, playerClass, playerDkp, playerTier)) then
					tinsert(ADKP_DkpTableToShow,{playerName,playerClass,playerDkp,playerTier});
				else
					ADKP_DkpTable[playerName]["Selected"] = false;
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
function ADKP_UpdatePlayersInGroup()
	-- Updates the list of players currently in the group
	-- First attempts to get this data via a query to the raid. 
	-- If that failes it resorts to querying for party data
	local numberInRaid = GetNumRaidMembers();
	local numberInParty = GetNumPartyMembers();
	ADKP_PlayersInGroup = {};
	-- Is a raid going?
	if ( numberInRaid > 0 ) then
		-- Yes! Load raid data...
		local name, class, guild;
		for i=1, numberInRaid do
			name, _, _, _, class, _, _, _ , _ = GetRaidRosterInfo(i);
			ADKP_PlayersInGroup[i]=
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
			ADKP_PlayersInGroup[i]=
			{
				["name"] = name,
				["class"] = class,
			};
		end
		-- this doesn't load the current player, so we need to add them manually
		ADKP_PlayersInGroup[numberInParty+1]=
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
function ADKP_AllGroupSelected()
	-- First try running through the raid and see if they are all selected
	local name, class;
	local numberInRaid = GetNumRaidMembers();
	local numberInParty = GetNumPartyMembers();
	if(numberInRaid > 0 ) then
		for i=1, numberInRaid do
			name, _, _, _, _, _, _, _ , _ = GetRaidRosterInfo(i);
			if ( not ADKP_DkpTable[name]["Selected"]) then
				return false;
			end
		end
		return true;
	elseif ( numberInParty > 0) then
		for i=1, numberInParty do
			playerHandle = "party"..i;
			name = UnitName(playerHandle);
			if ( not ADKP_DkpTable[name]["Selected"]) then
				return false;
			end
		end
		--before we return true we also need to check the current player...
		if ( not ADKP_DkpTable[UnitName("player")]["Selected"]) then
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
function ADKP_ShouldDisplay(name, class, dkp, tier)
	-- 名称过滤逻辑
	local searchBox = getglobal("ADKP_NameSearchBox")
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
	-- 人员来源模式过滤（当前团队/替补团队/临时人员）
	local ADKP_listMode = ADKP_ListMode or "raid"
	if ADKP_listMode == "raid" then
		if ADKP_PlayerInGroup(name) == false then return false end
	elseif ADKP_listMode == "sub" then
		if ADKP_IsSubRosterMember(name) == false then return false end
	elseif ADKP_listMode == "out" then
		if ADKP_PlayerInGroup(name) == true or ADKP_IsSubRosterMember(name) == true then return false end
	end
	
	if ADKP_Filters["All"] and ADKP_Filters["All"] == 1 then
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
	if (ADKP_Filters[englishClass] == 0) then
		return false;
	end
	


	
	return true; 
end
