------------------------------------------------------------------------
-- ANNOUNCMENETS	
------------------------------------------------------------------------
-- Contains methods related to the raid announcemenets in game whenever
-- DKP is awarded. 
------------------------------------------------------------------------



-- The following are award strings that the addon uses. If you wish to modify what the addon says for
-- awards you just need to edit these strings. 
-- Do display a new line in your message use \n. 

ADKP_ItemAward =			">$player< 获取装备 >$item< ,花费: $cost 点DKP";

ADKP_ItemAwardZeroSum =	"$dkp 点DKP奖励给所有成员,因为零和规则(均摊奖励)";

ADKP_DkpAwardAll =		"$dkp 点dkp奖励给所有团员,原因: $reason.";

ADKP_DkpAwardSome =		"$dkp 点dkp奖励(惩罚)给某些团员,原因: $reason.";

ADKP_DkpAwardSingle =		"$dkp 点dkp奖励(惩罚)给 $player,原因: $reason.";

ADKP_BidStart =			"拍分系统: 开始拍分 >$item<\n开拍装备 >$item<\n------- >$item< -------";
--							"聊天框输入 你的出分 .你的出分会出现在DKP管理的插件里."..
--							"(范例:50) 私密我 DKP 可查询自己分数";

ADKP_BidEnd =				"拍分系统: >$item< 拍分结束";

-- ================================
-- Returns the location where notifications should be sent to. 
-- "Raid" or "Party". If player is in neither a raid or a party, returns
-- "None"
-- ================================
function ADKP_GetTellLocation()
	
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
function ADKP_AnnounceAwardItem(cost, item, player)
	local tellLocation = ADKP_GetTellLocation();
	cost = cost * -1;
	
	-- Announce the item
	-- (convert the item to a link)
	local _,_,link = ADKP_GetItemInfo(item);
	local toSay =	string.gsub(ADKP_ItemAward, "$player", player);
	toSay =	string.gsub(toSay, "$item", link);
	toSay =	string.gsub(toSay, "$cost", cost);
	
	ADKP_SendAnnouncement(toSay,tellLocation);
	
	-- 开始自动分配物品
	ADKP_StartAutoLoot(link, player);

	-- If using Zero Sum announce the zero sum award
	if ( ADKP_WebOptions["ZeroSumEnabled"]==1) then
		local numPlayers = ADKP_GetTableSize(ADKP_PlayersInGroup);
		if ( numPlayers ~= 0 ) then 
			local toAward = (cost) / numPlayers;
			toAward = ADKP_ROUND(toAward, 2 );
			local toSay =	string.gsub(ADKP_ItemAwardZeroSum, "$dkp", toAward);
			ADKP_SendAnnouncement(toSay, tellLocation);
		end
	end

end

-- ================================
-- Makes an announcement that the raid (or a set of users) has recieved dkp
-- ================================
function ADKP_AnnounceAward(dkp, reason)
	local tellLocation = ADKP_GetTellLocation();
	local allGroupSelected = ADKP_AllGroupSelected();

	
	if ( allGroupSelected == true ) then
	
		-- Announce the award
		local toSay =	string.gsub(ADKP_DkpAwardAll, "$dkp", dkp);
		toSay =	string.gsub(toSay, "$reason", reason);
		ADKP_SendAnnouncement(toSay,tellLocation);
	
	else
		
		-- Announce the award

		local toSay = 	string.gsub(ADKP_DkpAwardSome, "$dkp", dkp);
		toSay = 	string.gsub(toSay, "$reason", reason);
		ADKP_SendAnnouncement(toSay,tellLocation);
		
		-- 优先播报本次实际 AddDKP 传入的玩家名单；
		-- 只有旧入口没有提供名单时，才回退到全局 Selected。
		local selectedPlayers = {}
		if ADKP_LastAwardPlayers and ADKP_LastAwardPlayerCount and ADKP_LastAwardPlayerCount > 0 then
			for i = 1, ADKP_LastAwardPlayerCount do
				if ADKP_LastAwardPlayers[i] then
					table.insert(selectedPlayers, ADKP_LastAwardPlayers[i])
				end
			end
		else
			for k, v in pairs(ADKP_DkpTable) do
				if ( type(v) == "table" ) then
					if( v["Selected"] ) then
						table.insert(selectedPlayers, k)
					end
				end
			end
		end
		
		-- 按每行5个玩家播报
		local totalPlayers = ADKP_GetTableSize(selectedPlayers)
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
			ADKP_SendAnnouncement(playerToSay, tellLocation);
			
			-- 移动到下一批次
			startIndex = endIndex + 1

		end
	end
	-- 防止没有经过 AddDKP 的旧公告入口复用上一轮名单
	ADKP_LastAwardPlayers = nil
	ADKP_LastAwardPlayerCount = 0
end

-- ================================
-- Announces that a single player has received dkp
-- ================================
function ADKP_AnnounceAwardSingle(dkp, reason, playerName)
	local tellLocation = ADKP_GetTellLocation();
	local toSay = string.gsub(ADKP_DkpAwardSingle, "$dkp", dkp);
	toSay = string.gsub(toSay, "$reason", reason);
	toSay = string.gsub(toSay, "$player", playerName);
	ADKP_SendAnnouncement(toSay, tellLocation);
end

-- ================================
-- Announces that bidding has started. 
-- Accepts item name and the time (in seconds) that bidding
-- will go for
-- ================================
function ADKP_AnnounceBidStart(item, time) 
	local tellLocation = ADKP_GetTellLocation();
	if(time == 0 or time == nil or time =="" or time=="0") then
		time = "";
	else
		time = "("..time.."s)";
	end
	
	local toSay =	string.gsub(ADKP_BidStart, "$item", item);
	toSay =	string.gsub(toSay, "$time", time);
	ADKP_SendAnnouncement(toSay,tellLocation);
end

-- ================================
-- Announces that bidding has finished
-- Accepts itemname, name of highest bidder, bid dkp
-- ================================
function ADKP_AnnounceBidEnd(item, name, dkp)
	

	if(name == nil or name == "") then
		name = "noone";
		dkp = 0;
	end
	--convert the item to a link
	local _,_,link = ADKP_GetItemInfo(item);
	local tellLocation = ADKP_GetTellLocation();
	local toSay =	string.gsub(ADKP_BidEnd, "$item", link);
	toSay =	string.gsub(toSay, "$name", name);
	toSay =	string.gsub(toSay, "$dkp", dkp);
	ADKP_SendAnnouncement(toSay,tellLocation);
end

-- ================================
-- Sends out an announcent to the screen. 
-- Possible locations are:
-- "RAID", "PARTY", "GUILD", or "NONE"
-- If "NONE" is selected it will output to the players console.
-- 静默模式下，只有NONE位置的播报会显示（即仅显示在本地聊天框）
-- ================================
function ADKP_SendAnnouncement(toSay, location)
	-- 检查静默模式
	local isSilentMode = ADKP_Options and ADKP_Options["SilentMode"]
	
	if ( location == "NONE" ) then
		ADKP_Print(toSay);
	else
		-- 静默模式下，不发送团队/公会/队伍聊天消息，仅本地显示
		if isSilentMode then
			-- 静默模式下，只在本地聊天框显示调试信息
			ADKP_Print("[静默] " .. toSay);
			return
		end
		
		local newLineLoc = string.find(toSay,"\n");
		local tempToSay;
		local breaker = 0 ; 
		--ADKP_Print("New line loc: "..newLineLoc);
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
function ADKP_SendAnnouncementDefault(toSay)
	local tellLocation = ADKP_GetTellLocation();
	ADKP_SendAnnouncement(toSay, tellLocation);
end

-- ================================
-- Sends countdown messages that should NOT be affected by silent mode
-- This ensures auction countdowns are always visible to the raid
-- ================================
function ADKP_SendCountdownMessage(toSay)
	local tellLocation = ADKP_GetTellLocation();
		
	if ( tellLocation == "NONE" ) then
		ADKP_Print(toSay);
	else
		-- 静默模式下不发送任何团队/队伍/公会播报（含倒计时）
		local isSilentMode = ADKP_Options and ADKP_Options["SilentMode"]
		if isSilentMode then
			ADKP_Print("[静默] " .. toSay);
			return
		end
		SendChatMessage(toSay, tellLocation);
	end
end
