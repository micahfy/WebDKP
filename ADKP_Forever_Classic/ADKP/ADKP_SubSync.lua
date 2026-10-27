-- Forever adapters are private to this addon source file.
local CreateFrame, UnitName, UnitClass = ADKP_CreateFrame, ADKP_UnitName, ADKP_UnitClass
local GetNumRaidMembers, GetNumPartyMembers = ADKP_GetNumRaidMembers, ADKP_GetNumPartyMembers
local GetRaidRosterInfo, GetGuildRosterInfo = ADKP_GetRaidRosterInfo, ADKP_GetGuildRosterInfo
local IsRaidLeader, IsRaidOfficer, IsPartyLeader = ADKP_IsLeader, ADKP_IsAssistant, ADKP_IsLeader
local UnitIsPartyLeader, UnitAffectingCombat = ADKP_UnitIsLeader, ADKP_UnitAffectingCombat
local GuildRoster, GetItemInfo, PlaySound = ADKP_GuildRoster, ADKP_NativeGetItemInfo, ADKP_PlaySound
local SendAddonMessage, SendChatMessage = ADKP_SendAddonMessage, ADKP_NativeSendChatMessage
local InviteByName, UninviteByName, ConvertToRaid = ADKP_Invite, ADKP_Uninvite, ADKP_ConvertToRaid
local PromoteByName, PromoteToAssistant, DemoteByName = ADKP_Promote, ADKP_PromoteAssistant, ADKP_Demote
local StaticPopup_Show, UIDropDownMenu_AddButton = ADKP_StaticPopup_Show, ADKP_DropdownAddButton
local UIDropDownMenu_Initialize, UIDropDownMenu_SetWidth = ADKP_DropdownInitialize, ADKP_DropdownSetWidth
local UIDropDownMenu_SetText, FauxScrollFrame_OnVerticalScroll = ADKP_DropdownSetText, ADKP_FauxVerticalScroll
local FauxScrollFrame_GetOffset, FauxScrollFrame_Update, PanelTemplates_SetTab = ADKP_FauxGetOffset, ADKP_FauxUpdate, ADKP_PanelSetTab
local GetMasterLootCandidate, GiveMasterLoot = ADKP_MasterLootCandidate, ADKP_GiveMasterLoot
local string, table = ADKP_LegacyString, ADKP_LegacyTable
local getglobal, setglobal = ADKP_GetGlobal, ADKP_SetGlobal
local getn, tinsert, tremove, floor = ADKP_LegacyTable.getn, table.insert, table.remove, math.floor
-- Original cache helpers; native WHISPER routing is in ADKP_ForeverNetwork.lua.
if not ADKP_SubSync_Installed then
ADKP_SubSync_Installed = true

-- 缓存有效期(秒)，超过则下次查询会真正发起
ADKP_SubSync_TTL = 300
-- 强制查询标志(手动刷新时置 true，跳过缓存)
ADKP_SubSync_ForceQuery = false
-- 同工会名册集合
ADKP_SubSync_GuildSet = {}
ADKP_SubSync_GuildLoaded = false
ADKP_SubSync_GuildName = nil
-- 回传路由临时标志(Lua 单线程同步执行，窗口内安全)
ADKP_SubSync_Routing = nil

local function SubSyncPrint(text)
	if ADKP_Print then
		ADKP_Print(text)
	elseif DEFAULT_CHAT_FRAME then
		DEFAULT_CHAT_FRAME:AddMessage("[替补同步] " .. text, 0.6, 1, 0.6)
	end
end

local function EnsureCache()
	if not ADKP_SubSync_Cache then ADKP_SubSync_Cache = {} end
end

-- ===================== 同工会判定（基于本地公会名册，零额外网络查询） =====================
function ADKP_SubSync_RebuildGuildSet()
	ADKP_SubSync_GuildSet = {}
	ADKP_SubSync_GuildName = GetGuildInfo and GetGuildInfo("player") or nil
	local n = 0
	if ADKP_SubSync_GuildName and GetNumGuildMembers then n = GetNumGuildMembers() end
	for i = 1, n do
		local name = GetGuildRosterInfo(i)
		if name and name ~= "" then
			ADKP_SubSync_GuildSet[string.lower(name)] = true
		end
	end
	ADKP_SubSync_GuildLoaded = true
end

function ADKP_SubSync_IsSameGuild(name)
	if not name or name == "" then return false end
	local me = UnitName("player")
	if me and string.lower(name) == string.lower(me) then
		return true
	end
	local currentGuild = GetGuildInfo and GetGuildInfo("player") or nil
	if not currentGuild then
		ADKP_SubSync_GuildSet = {}
		ADKP_SubSync_GuildName = nil
		ADKP_SubSync_GuildLoaded = true
		return false
	end
	if ADKP_SubSync_GuildName ~= currentGuild then
		ADKP_SubSync_GuildSet = {}
		ADKP_SubSync_GuildName = currentGuild
		ADKP_SubSync_GuildLoaded = false
	end
	if not ADKP_SubSync_GuildLoaded and GuildRoster then
		GuildRoster()
	end
	return ADKP_SubSync_GuildSet[string.lower(name)] == true
end

-- ===================== 缓存：新鲜度 / 快照 / 回放 =====================
function ADKP_SubSync_HasFreshCache(subName)
	EnsureCache()
	local c = ADKP_SubSync_Cache[string.lower(subName)]
	if not c or not c.members then return false end
	local age = time() - (c.time or 0)
	return age >= 0 and age < (ADKP_SubSync_TTL or 300)
end

function ADKP_SubSync_SnapshotCache(captain)
	if not captain or captain == "" then return end
	EnsureCache()
	local key = string.lower(captain)
	local tbl = nil
	if ADKP_PendingSubMembers then
		tbl = ADKP_PendingSubMembers[captain] or ADKP_PendingSubMembers[key]
	end
	if not tbl then return end
	local members = {}
	local count = 0
	for memberName, info in pairs(tbl) do
		local class = ""
		if type(info) == "table" then class = info.class or "" end
		members[memberName] = class
		count = count + 1
	end
	ADKP_SubSync_Cache[key] = { members = members, time = time(), count = count }
	ADKP_SubSync_UpdateLabel(captain, count, 0)
end

function ADKP_SubSync_ReplayCache(subName)
	EnsureCache()
	local c = ADKP_SubSync_Cache[string.lower(subName)]
	if not c or not c.members then return end
	if ADKP_SubAwardData then
		if not ADKP_SubAwardData.captain or ADKP_SubAwardData.captain == "" then
			ADKP_SubAwardData.captain = subName
		end
	end
	local count = 0
	for memberName, class in pairs(c.members) do
		local entry = memberName
		if class and class ~= "" then entry = memberName .. ":" .. class end
		if ADKP_SubSync_OrigHandleSubWhisperData then
			ADKP_SubSync_OrigHandleSubWhisperData(subName, "ADKP: SUB:" .. entry)
		end
		count = count + 1
	end
	if ADKP_SubSync_OrigHandleSubWhisperData then
		ADKP_SubSync_OrigHandleSubWhisperData(subName, "ADKP: SUB_COMPLETE:" .. count)
	end
	local age = time() - (c.time or 0)
	SubSyncPrint("使用缓存的替补名单（" .. count .. "人，" .. age .. "秒前），未重复查询")
	ADKP_SubSync_UpdateLabel(subName, count, age)
end

function ADKP_SubSync_UpdateLabel(captain, count, age)
	if not ADKP_AwardDKP_FrameSubCaptainLabel then return end
	local txt = "替补队长: " .. (captain or "无")
	if count and count > 0 then
		local when = "刚刚"
		if age and age > 0 then when = age .. "秒前" end
		txt = txt .. "（" .. count .. "人 · " .. when .. "同步）"
	end
	ADKP_AwardDKP_FrameSubCaptainLabel:SetText(txt)
end

-- ===================== 回传(替补->团长) 路由 =====================
-- 复用原 ADKP_SendSubMemberList 的采集/分包逻辑：同工会回传走 GUILD，
-- 通过普通密语收到的查询则强制用普通密语回传。

end -- ADKP_SubSync_Installed
