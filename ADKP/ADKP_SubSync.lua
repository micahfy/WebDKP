-- ADKP_SubSync.lua
-- 替补团信息「同工会/跨工会」智能同步 + 防重复查询模块
-- 加载顺序：本文件位于 .toc 末尾，最后加载，安全覆盖 ADKP 原函数。
-- 适配 WoW 1.12 / Lua 5.0：不使用 # 长度运算符；使用 table.getn / string.find / string.gsub。
--
-- 协议设计：
--   查询 前缀 AMB_TBQQ：消息体仍为「替补队长名」（保持与旧版兼容，旧客户端仍能识别）。
--   回传 前缀 AMB_TBFS：同工会走 GUILD 插件频道，负载带信封 "目的#来源#负载"，多团并发不串扰。
--   同工会：查询与回传均走 GUILD 插件频道。
--   跨工会：查询走密语(WHISPER 插件消息)，回传维持原密语 SUB:/SUB_COMPLETE:/SUB_EMPTY，行为不变。
--   防重复：团长侧缓存替补名单+时间戳，新鲜期内直接用缓存回放，不再发起查询；/subteam 手动刷新。

if not ADKP_SubSync_Installed then
ADKP_SubSync_Installed = true

-- 缓存有效期(秒)，超过则下次查询会真正发起
ADKP_SubSync_TTL = 300
-- 强制查询标志(手动刷新时置 true，跳过缓存)
ADKP_SubSync_ForceQuery = false
-- 同工会名册集合
ADKP_SubSync_GuildSet = {}
ADKP_SubSync_GuildLoaded = false
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
	local n = 0
	if GetNumGuildMembers then n = GetNumGuildMembers() end
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
-- 复用原 ADKP_SendSubMemberList 的采集/分包逻辑：同工会时设置 Routing 标志，
-- 让被覆盖的 ADKP_SendWhisper 把每个分包改走 GUILD 插件频道(带信封)。
ADKP_SubSync_OrigSendWhisper = ADKP_SendWhisper
function ADKP_SendWhisper(toPlayer, msg)
	local r = ADKP_SubSync_Routing
	if r and r.to and r.from then
		-- 走工会插件频道，信封：目的#来源#负载
		local envelope = r.to .. "#" .. r.from .. "#" .. (msg or "")
		ADKP_SubSync_OrigSendAddonMessage("AMB_TBFS", envelope, "GUILD")
		return
	end
	if ADKP_SubSync_OrigSendWhisper then
		return ADKP_SubSync_OrigSendWhisper(toPlayer, msg)
	end
end

ADKP_SubSync_OrigSendSubMemberList = ADKP_SendSubMemberList
function ADKP_SendSubMemberList(toPlayer)
	if not toPlayer or toPlayer == "" then return false end
	if ADKP_SubSync_IsSameGuild(toPlayer) then
		local me = UnitName("player")
		ADKP_SubSync_Routing = { to = toPlayer, from = me }
		local ok
		if ADKP_SubSync_OrigSendSubMemberList then
			ok = ADKP_SubSync_OrigSendSubMemberList(toPlayer)
		end
		ADKP_SubSync_Routing = nil
		return ok
	end
	if ADKP_SubSync_OrigSendSubMemberList then
		return ADKP_SubSync_OrigSendSubMemberList(toPlayer)
	end
end

-- ===================== 查询(团长->替补) 路由 + 防重复 =====================
ADKP_SubSync_OrigSendAddonMessage = SendAddonMessage
function SendAddonMessage(prefix, text, chatType, target)
	if prefix == "AMB_TBQQ" then
		local subName = text or ""
		local hashPos = string.find(subName, "#")
		if hashPos then subName = string.sub(subName, 1, hashPos - 1) end
		if subName == "" then
			return ADKP_SubSync_OrigSendAddonMessage(prefix, text, chatType, target)
		end
		-- 防重复：缓存新鲜且非强制刷新 -> 直接用缓存回放，不发查询
		if (not ADKP_SubSync_ForceQuery) and ADKP_SubSync_HasFreshCache(subName) then
			ADKP_SubSync_ReplayCache(subName)
			return
		end
		if ADKP_SubSync_IsSameGuild(subName) then
			return ADKP_SubSync_OrigSendAddonMessage("AMB_TBQQ", subName, "GUILD")
		else
			-- 跨工会：走密语(点对点，天然无串扰)
			SendChatMessage("ADKP: SUBREQ", "WHISPER", nil, subName)
			return
		end
	end
	return ADKP_SubSync_OrigSendAddonMessage(prefix, text, chatType, target)
end

-- ===================== 收消息处理（包裹原 AMB 处理器） =====================
ADKP_SubSync_OrigHandleAddonMessage = ADKP_HandleAddonMessage
function ADKP_HandleAddonMessage(prefix, message, channel, sender)
	if prefix == "AMB_TBQQ" then
		-- 收到查询：消息体为目标(替补队长)名，兼容带信封情况只取 # 前部分
		local subName = message or ""
		local hashPos = string.find(subName, "#")
		if hashPos then subName = string.sub(subName, 1, hashPos - 1) end
		local me = UnitName("player")
		if me and string.lower(subName) == string.lower(me) then
			ADKP_SendSubMemberList(sender)
			if ADKP_SubAwardData then
				ADKP_SubAwardData.receivedResponse = true
			end
		end
		return
	elseif prefix == "AMB_TBFS" then
		-- 同工会回传：信封 目的#来源#负载
		local _, _, toName, fromName, payload = string.find(message or "", "^([^#]+)#([^#]+)#(.*)$")
		if toName and fromName then
			local me = UnitName("player")
			if me and string.lower(toName) == string.lower(me) then
				local awaited = ""
				if ADKP_SubAwardData and ADKP_SubAwardData.captain then
					awaited = ADKP_SubAwardData.captain
				end
				if awaited == "" or string.lower(fromName) == string.lower(awaited) then
					ADKP_HandleSubWhisperData(fromName, "ADKP: " .. (payload or ""))
				end
			end
		end
		return
	end
	if ADKP_SubSync_OrigHandleAddonMessage then
		return ADKP_SubSync_OrigHandleAddonMessage(prefix, message, channel, sender)
	end
end

-- ===================== 回传完成 -> 缓存快照（包裹密语解析器） =====================
ADKP_SubSync_OrigHandleSubWhisperData = ADKP_HandleSubWhisperData
function ADKP_HandleSubWhisperData(fromPlayer, message)
	-- 跨工会查询指令：收到 SUBREQ -> 回传本队替补名单
	if message and string.find(message, "^ADKP: SUBREQ") then
		if fromPlayer and fromPlayer ~= "" then
			ADKP_SendSubMemberList(fromPlayer)
		end
		return
	end
	if ADKP_SubSync_OrigHandleSubWhisperData then
		ADKP_SubSync_OrigHandleSubWhisperData(fromPlayer, message)
	end
	if message and string.find(message, "SUB_COMPLETE:") then
		ADKP_SubSync_SnapshotCache(fromPlayer)
		-- 若当前正在看「替补团队」，名单到达后立即重绘列表
		if ADKP_ListMode == "sub" and ADKP_UpdateTableToShow and ADKP_UpdateTable then
			ADKP_SubQueryTimeoutEmpty = nil
			ADKP_UpdateTableToShow()
			ADKP_UpdateTable()
		end
	end
end

-- ===================== 手动刷新 =====================
function ADKP_SubSync_RefreshRoster()
	local cap = ""
	if ADKP_ResolveSubCaptain then
		cap = ADKP_ResolveSubCaptain()
	elseif ADKP_Options and ADKP_Options["SubSettings"] then
		cap = ADKP_Options["SubSettings"].captain or ""
	end
	if cap == "" then
		SubSyncPrint("未设置替补队长，无法刷新（请在 tab1 右侧或系统控制页填写替补队长名）")
		return
	end
	if ADKP_SubAwardData then
		ADKP_SubAwardData.captain = cap
		ADKP_SubAwardData.receivedResponse = false
	end
	EnsureCache()
	ADKP_SubSync_Cache[string.lower(cap)] = nil
	ADKP_SubQueryTimeoutEmpty = nil
	ADKP_SubSync_ForceQuery = true
	SendAddonMessage("AMB_TBQQ", cap)
	ADKP_SubSync_ForceQuery = false
	local mode = "密语"
	if ADKP_SubSync_IsSameGuild(cap) then mode = "工会频道" end
	SubSyncPrint("已通过" .. mode .. "向 " .. cap .. " 刷新替补名单……")
end

SLASH_ADKPSUBSYNC1 = "/subteam"
SlashCmdList["ADKPSUBSYNC"] = function(msg)
	msg = msg or ""
	msg = string.lower(msg)
	msg = string.gsub(msg, "^%s+", "")
	msg = string.gsub(msg, "%s+$", "")
	if msg == "" or msg == "refresh" or msg == "刷新" then
		ADKP_SubSync_RefreshRoster()
	elseif string.find(msg, "^ttl") then
		local _, _, val = string.find(msg, "(%d+)")
		if val then
			ADKP_SubSync_TTL = tonumber(val)
			SubSyncPrint("缓存有效期已设为 " .. ADKP_SubSync_TTL .. " 秒")
		else
			SubSyncPrint("当前缓存有效期 " .. (ADKP_SubSync_TTL or 300) .. " 秒。用法 /subteam ttl 300")
		end
	else
		SubSyncPrint("用法：/subteam 刷新替补名单 | /subteam ttl 300 设置缓存秒数")
	end
end

-- ===================== MinimapButtonBag / Bagshui 兼容修复 =====================
-- MBB 进行小地图按鈕处理时会尝试把下拉菜单锁定到 {FrameName}Left 区域。
-- ADKP_MinimapButton 是普通 Button 没有该子区域，在此创建一个 1x1 透明贴图并全局注册。
if ADKP_MinimapButton and not getglobal("ADKP_MinimapButtonLeft") then
	local leftTex = ADKP_MinimapButton:CreateTexture(nil, "BACKGROUND")
	leftTex:SetWidth(1)
	leftTex:SetHeight(1)
	leftTex:SetPoint("BOTTOMLEFT", ADKP_MinimapButton, "BOTTOMLEFT", 0, 0)
	setglobal("ADKP_MinimapButtonLeft", leftTex)
end

-- ===================== 事件 =====================
ADKP_SubSync_EventFrame = CreateFrame("Frame")
ADKP_SubSync_EventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
ADKP_SubSync_EventFrame:RegisterEvent("PLAYER_LOGIN")
ADKP_SubSync_EventFrame:RegisterEvent("GUILD_ROSTER_UPDATE")
ADKP_SubSync_EventFrame:RegisterEvent("VARIABLES_LOADED")
ADKP_SubSync_EventFrame:SetScript("OnEvent", function()
	if event == "GUILD_ROSTER_UPDATE" then
		ADKP_SubSync_RebuildGuildSet()
	else
		EnsureCache()
		if GuildRoster then GuildRoster() end
	end
end)

SubSyncPrint("替补同步模块已加载：同工会走工会频道、跨工会走密语，自动缓存防重复查询。输入 /subteam 手动刷新。")

end -- ADKP_SubSync_Installed
