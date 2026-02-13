------------------------------------------------------------------------
-- ANNOUNCMENETS	
------------------------------------------------------------------------
-- Contains methods related to the raid announcemenets in game whenever
-- DKP is awarded. 
------------------------------------------------------------------------



-- The following are award strings that the addon uses. If you wish to modify what the addon says for
-- awards you just need to edit these strings. 
-- Do display a new line in your message use \n. 

WebDKP_ItemAward =			">$player< 获取装备 >$item< ,花费: $cost 点DKP";

WebDKP_ItemAwardZeroSum =	"$dkp 点DKP奖励给所有成员,因为零和规则(均摊奖励)";

WebDKP_DkpAwardAll =		"$dkp 点dkp奖励给所有团员,原因: $reason.";

WebDKP_DkpAwardSome =		"$dkp 点dkp奖励(惩罚)给某些团员,原因: $reason.";

WebDKP_DkpAwardSingle =		"$dkp 点dkp奖励(惩罚)给 $player,原因: $reason.";

WebDKP_BidStart =			"拍分系统: 开始拍分 >$item<\n开拍装备 >$item<\n------- >$item< -------";
--							"聊天框输入 你的出分 .你的出分会出现在DKP管理的插件里."..
--							"(范例:50) 私密我 DKP 可查询自己分数";

WebDKP_BidEnd =				"拍分系统: >$item< 拍分结束";

-- ================================
-- Returns the location where notifications should be sent to. 
-- "Raid" or "Party". If player is in neither a raid or a party, returns
-- "None"
-- ================================
function WebDKP_GetTellLocation()
	
	local numberInRaid = GetNumRaidMembers();
	local numberInParty = GetNumPartyMembers();
	
	if( numberInRaid > 0 ) then
		return "RAID";
	elseif (numberInParty > 0 ) then
		return "PARTY";
	else
		return "NONE";
	end
end

-- ================================
-- Makes an announcement that a user has recieved an item. 
-- ================================
function WebDKP_AnnounceAwardItem(cost, item, player)
	local tellLocation = WebDKP_GetTellLocation();
	cost = cost * -1;
	
	-- Announce the item
	-- (convert the item to a link)
	local _,_,link = WebDKP_GetItemInfo(item);
	local toSay =	string.gsub(WebDKP_ItemAward, "$player", player);
	toSay =	string.gsub(toSay, "$item", link);
	toSay =	string.gsub(toSay, "$cost", cost);
	
	WebDKP_SendAnnouncement(toSay,tellLocation);
	
	-- 开始自动分配物品
	WebDKP_StartAutoLoot(link, player);
		 if WebDKP_Options and WebDKP_Options["AutoBackupEnabled"] then
		WebDKP_BackupData()
	    end
	-- If using Zero Sum announce the zero sum award
	if ( WebDKP_WebOptions["ZeroSumEnabled"]==1) then
		local numPlayers = WebDKP_GetTableSize(WebDKP_PlayersInGroup);
		if ( numPlayers ~= 0 ) then 
			local toAward = (cost) / numPlayers;
			toAward = WebDKP_ROUND(toAward, 2 );
			local toSay =	string.gsub(WebDKP_ItemAwardZeroSum, "$dkp", toAward);
			WebDKP_SendAnnouncement(toSay, tellLocation);
		end
	end

end

-- ================================
-- Makes an announcement that the raid (or a set of users) has recieved dkp
-- ================================
function WebDKP_AnnounceAward(dkp, reason)
	local tellLocation = WebDKP_GetTellLocation();
	local allGroupSelected = WebDKP_AllGroupSelected();

	
	if ( allGroupSelected == true ) then
	
		-- Announce the award
		local toSay =	string.gsub(WebDKP_DkpAwardAll, "$dkp", dkp);
		toSay =	string.gsub(toSay, "$reason", reason);
		WebDKP_SendAnnouncement(toSay,tellLocation);
	
	else
		
		-- Announce the award

		local toSay = 	string.gsub(WebDKP_DkpAwardSome, "$dkp", dkp);
		toSay = 	string.gsub(toSay, "$reason", reason);
		WebDKP_SendAnnouncement(toSay,tellLocation);
		
		-- 收集所有选中的玩家
		local selectedPlayers = {}
		for k, v in pairs(WebDKP_DkpTable) do
			if ( type(v) == "table" ) then
				if( v["Selected"] ) then
					table.insert(selectedPlayers, k)
				end
			end
		end
		
		-- 按每行5个玩家播报
		local totalPlayers = WebDKP_GetTableSize(selectedPlayers)
		local startIndex = 1
		local batchSize = 5
		
		while startIndex <= totalPlayers do
			local endIndex = math.min(startIndex + batchSize - 1, totalPlayers)
			local playerNames = ""
			
			-- 构建当前批次的玩家列表
			for i = startIndex, endIndex do
				if playerNames ~= "" then
					playerNames = playerNames .. ", "
				end
				playerNames = playerNames .. selectedPlayers[i]
			end
			
			-- 播报当前批次的玩家
			local playerToSay = "被奖励团员: " .. playerNames
			WebDKP_SendAnnouncement(playerToSay, tellLocation);
			
			-- 移动到下一批次
			startIndex = endIndex + 1

		end
	end
end

-- ================================
-- Announces that a single player has received dkp
-- ================================
function WebDKP_AnnounceAwardSingle(dkp, reason, playerName)
	local tellLocation = WebDKP_GetTellLocation();
	local toSay = string.gsub(WebDKP_DkpAwardSingle, "$dkp", dkp);
	toSay = string.gsub(toSay, "$reason", reason);
	toSay = string.gsub(toSay, "$player", playerName);
	WebDKP_SendAnnouncement(toSay, tellLocation);
end

-- ================================
-- Announces that bidding has started. 
-- Accepts item name and the time (in seconds) that bidding
-- will go for
-- ================================
function WebDKP_AnnounceBidStart(item, time) 
	local tellLocation = WebDKP_GetTellLocation();
	if(time == 0 or time == nil or time =="" or time=="0") then
		time = "";
	else
		time = "("..time.."s)";
	end
	
	local toSay =	string.gsub(WebDKP_BidStart, "$item", item);
	toSay =	string.gsub(toSay, "$time", time);
	WebDKP_SendAnnouncement(toSay,tellLocation);
end

-- ================================
-- Announces that bidding has finished
-- Accepts itemname, name of highest bidder, bid dkp
-- ================================
function WebDKP_AnnounceBidEnd(item, name, dkp)
	

	if(name == nil or name == "") then
		name = "noone";
		dkp = 0;
	end
	--convert the item to a link
	local _,_,link = WebDKP_GetItemInfo(item);
	local tellLocation = WebDKP_GetTellLocation();
	local toSay =	string.gsub(WebDKP_BidEnd, "$item", link);
	toSay =	string.gsub(toSay, "$name", name);
	toSay =	string.gsub(toSay, "$dkp", dkp);
	WebDKP_SendAnnouncement(toSay,tellLocation);
end

-- ================================
-- Sends out an announcent to the screen. 
-- Possible locations are:
-- "RAID", "PARTY", "GUILD", or "NONE"
-- If "NONE" is selected it will output to the players console.
-- 静默模式下，只有NONE位置的播报会显示（即仅显示在本地聊天框）
-- ================================
function WebDKP_SendAnnouncement(toSay, location)
	-- 检查静默模式
	local isSilentMode = WebDKP_Options and WebDKP_Options["SilentMode"]
	
	if ( location == "NONE" ) then
		WebDKP_Print(toSay);
	else
		-- 静默模式下，不发送团队/公会/队伍聊天消息，仅本地显示
		if isSilentMode then
			-- 静默模式下，只在本地聊天框显示调试信息
			WebDKP_Print("[静默] " .. toSay);
			return
		end
		
		local newLineLoc = string.find(toSay,"\n");
		local tempToSay;
		local breaker = 0 ; 
		--WebDKP_Print("New line loc: "..newLineLoc);
		while (newLineLoc  ~= nil ) do 
			tempToSay = string.sub(toSay,0,newLineLoc-1);
			SendChatMessage(tempToSay,location);
			--trim to say of what we just said
			toSay = string.sub(toSay,newLineLoc+1,string.len(toSay));
			-- get the start of the next new line
			newLineLoc = string.find(toSay,"\n");
		end
		-- finish saying what is left
		SendChatMessage(toSay,location);
	end
end

-- ================================
-- Sends an announcement to the default location
-- ================================
function WebDKP_SendAnnouncementDefault(toSay)
	local tellLocation = WebDKP_GetTellLocation();
	WebDKP_SendAnnouncement(toSay, tellLocation);
end

-- ================================
-- Sends countdown messages that should NOT be affected by silent mode
-- This ensures auction countdowns are always visible to the raid
-- ================================
function WebDKP_SendCountdownMessage(toSay)
	local tellLocation = WebDKP_GetTellLocation();
	
	if ( tellLocation == "NONE" ) then
		WebDKP_Print(toSay);
	else
		-- 倒计时消息不受静默模式影响，始终发送到团队频道
		SendChatMessage(toSay, tellLocation);
	end
end
