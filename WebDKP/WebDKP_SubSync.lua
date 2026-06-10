-- WebDKP_SubSync.lua
-- 替补团信息「同工会/跨工会」智能同步 + 防重复查询模块
-- 加载顺序：本文件位于 .toc 末尾，最后加载，安全覆盖 WebDKP 原函数。
-- 适配 WoW 1.12 / Lua 5.0：不使用 # 长度运算符；使用 table.getn / string.find / string.gsub。
--
-- 协议设计：
--   查询 前缀 AMB_TBQQ：消息体仍为「替补队长名」（保持与旧版兼容，旧客户端仍能识别）。
--   回传 前缀 AMB_TBFS：同工会走 GUILD 插件频道，负载带信封 "目的#来源#负载"，多团并发不串扰。
--   同工会：查询与回传均走 GUILD 插件频道。
--   跨工会：查询走密语(WHISPER 插件消息)，回传维持原密语 SUB:/SUB_COMPLETE:/SUB_EMPTY，行为不变。
--   防重复：团长侧缓存替补名单+时间戳，新鲜期内直接用缓存回放，不再发起查询；/subteam 手动刷新。

if not WebDKP_SubSync_Installed then
WebDKP_SubSync_Installed = true

-- 缓存有效期(秒)，超过则下次查询会真正发起
WebDKP_SubSync_TTL = 300
-- 强制查询标志(手动刷新时置 true，跳过缓存)
WebDKP_SubSync_ForceQuery = false
-- 同工会名册集合
WebDKP_SubSync_GuildSet = {}
WebDKP_SubSync_GuildLoaded = false
-- 回传路由临时标志(Lua 单线程同步执行，窗口内安全)
WebDKP_SubSync_Routing = nil

local function SubSyncPrint(text)
	if WebDKP_Print then
		WebDKP_Print(text)
	elseif DEFAULT_CHAT_FRAME then
		DEFAULT_CHAT_FRAME:AddMessage("[替补同步] " .. text, 0.6, 1, 0.6)
	end
end

local function EnsureCache()
	if not WebDKP_SubSync_Cache then WebDKP_SubSync_Cache = {} end
end

-- ===================== 同工会判定（基于本地公会名册，零额外网络查询） =====================
function WebDKP_SubSync_RebuildGuildSet()
	WebDKP_SubSync_GuildSet = {}
	local n = 0
	if GetNumGuildMembers then n = GetNumGuildMembers() end
	for i = 1, n do
		local name = GetGuildRosterInfo(i)
		if name and name ~= "" then
			WebDKP_SubSync_GuildSet[string.lower(name)] = true
		end
	end
	WebDKP_SubSync_GuildLoaded = true
end

function WebDKP_SubSync_IsSameGuild(name)
	if not name or name == "" then return false end
	local me = UnitName("player")
	if me and string.lower(name) == string.lower(me) then
		return true
	end
	if not WebDKP_SubSync_GuildLoaded and GuildRoster then
		GuildRoster()
	end
	return WebDKP_SubSync_GuildSet[string.lower(name)] == true
end

-- ===================== 缓存：新鲜度 / 快照 / 回放 =====================
function WebDKP_SubSync_HasFreshCache(subName)
	EnsureCache()
	local c = WebDKP_SubSync_Cache[string.lower(subName)]
	if not c or not c.members then return false end
	local age = time() - (c.time or 0)
	return age >= 0 and age < (WebDKP_SubSync_TTL or 300)
end

function WebDKP_SubSync_SnapshotCache(captain)
	if not captain or captain == "" then return end
	EnsureCache()
	local key = string.lower(captain)
	local tbl = nil
	if WebDKP_PendingSubMembers then
		tbl = WebDKP_PendingSubMembers[captain] or WebDKP_PendingSubMembers[key]
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
	WebDKP_SubSync_Cache[key] = { members = members, time = time(), count = count }
	WebDKP_SubSync_UpdateLabel(captain, count, 0)
end

function WebDKP_SubSync_ReplayCache(subName)
	EnsureCache()
	local c = WebDKP_SubSync_Cache[string.lower(subName)]
	if not c or not c.members then return end
	if WebDKP_SubAwardData then
		if not WebDKP_SubAwardData.captain or WebDKP_SubAwardData.captain == "" then
			WebDKP_SubAwardData.captain = subName
		end
	end
	local count = 0
	for memberName, class in pairs(c.members) do
		local entry = memberName
		if class and class ~= "" then entry = memberName .. ":" .. class end
		if WebDKP_SubSync_OrigHandleSubWhisperData then
			WebDKP_SubSync_OrigHandleSubWhisperData(subName, "WebDKP: SUB:" .. entry)
		end
		count = count + 1
	end
	if WebDKP_SubSync_OrigHandleSubWhisperData then
		WebDKP_SubSync_OrigHandleSubWhisperData(subName, "WebDKP: SUB_COMPLETE:" .. count)
	end
	local age = time() - (c.time or 0)
	SubSyncPrint("使用缓存的替补名单（" .. count .. "人，" .. age .. "秒前），未重复查询")
	WebDKP_SubSync_UpdateLabel(subName, count, age)
end

function WebDKP_SubSync_UpdateLabel(captain, count, age)
	if not WebDKP_AwardDKP_FrameSubCaptainLabel then return end
	local txt = "替补队长: " .. (captain or "无")
	if count and count > 0 then
		local when = "刚刚"
		if age and age > 0 then when = age .. "秒前" end
		txt = txt .. "（" .. count .. "人 · " .. when .. "同步）"
	end
	WebDKP_AwardDKP_FrameSubCaptainLabel:SetText(txt)
end

-- ===================== 回传(替补->团长) 路由 =====================
-- 复用原 WebDKP_SendSubMemberList 的采集/分包逻辑：同工会时设置 Routing 标志，
-- 让被覆盖的 WebDKP_SendWhisper 把每个分包改走 GUILD 插件频道(带信封)。
WebDKP_SubSync_OrigSendWhisper = WebDKP_SendWhisper
function WebDKP_SendWhisper(toPlayer, msg)
	local r = WebDKP_SubSync_Routing
	if r and r.to and r.from then
		-- 走工会插件频道，信封：目的#来源#负载
		local envelope = r.to .. "#" .. r.from .. "#" .. (msg or "")
		WebDKP_SubSync_OrigSendAddonMessage("AMB_TBFS", envelope, "GUILD")
		return
	end
	if WebDKP_SubSync_OrigSendWhisper then
		return WebDKP_SubSync_OrigSendWhisper(toPlayer, msg)
	end
end

WebDKP_SubSync_OrigSendSubMemberList = WebDKP_SendSubMemberList
function WebDKP_SendSubMemberList(toPlayer)
	if not toPlayer or toPlayer == "" then return false end
	if WebDKP_SubSync_IsSameGuild(toPlayer) then
		local me = UnitName("player")
		WebDKP_SubSync_Routing = { to = toPlayer, from = me }
		local ok
		if WebDKP_SubSync_OrigSendSubMemberList then
			ok = WebDKP_SubSync_OrigSendSubMemberList(toPlayer)
		end
		WebDKP_SubSync_Routing = nil
		return ok
	end
	if WebDKP_SubSync_OrigSendSubMemberList then
		return WebDKP_SubSync_OrigSendSubMemberList(toPlayer)
	end
end

-- ===================== 查询(团长->替补) 路由 + 防重复 =====================
WebDKP_SubSync_OrigSendAddonMessage = SendAddonMessage
function SendAddonMessage(prefix, text, chatType, target)
	if prefix == "AMB_TBQQ" then
		local subName = text or ""
		local hashPos = string.find(subName, "#")
		if hashPos then subName = string.sub(subName, 1, hashPos - 1) end
		if subName == "" then
			return WebDKP_SubSync_OrigSendAddonMessage(prefix, text, chatType, target)
		end
		-- 防重复：缓存新鲜且非强制刷新 -> 直接用缓存回放，不发查询
		if (not WebDKP_SubSync_ForceQuery) and WebDKP_SubSync_HasFreshCache(subName) then
			WebDKP_SubSync_ReplayCache(subName)
			return
		end
		if WebDKP_SubSync_IsSameGuild(subName) then
			return WebDKP_SubSync_OrigSendAddonMessage("AMB_TBQQ", subName, "GUILD")
		else
			-- 跨工会：走密语(点对点，天然无串扰)
			return WebDKP_SubSync_OrigSendAddonMessage("AMB_TBQQ", subName, "WHISPER", subName)
		end
	end
	return WebDKP_SubSync_OrigSendAddonMessage(prefix, text, chatType, target)
end

-- ===================== 收消息处理（包裹原 AMB 处理器） =====================
WebDKP_SubSync_OrigHandleAddonMessage = WebDKP_HandleAddonMessage
function WebDKP_HandleAddonMessage(prefix, message, channel, sender)
	if prefix == "AMB_TBQQ" then
		-- 收到查询：消息体为目标(替补队长)名，兼容带信封情况只取 # 前部分
		local subName = message or ""
		local hashPos = string.find(subName, "#")
		if hashPos then subName = string.sub(subName, 1, hashPos - 1) end
		local me = UnitName("player")
		if me and string.lower(subName) == string.lower(me) then
			WebDKP_SendSubMemberList(sender)
			if WebDKP_SubAwardData then
				WebDKP_SubAwardData.receivedResponse = true
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
				if WebDKP_SubAwardData and WebDKP_SubAwardData.captain then
					awaited = WebDKP_SubAwardData.captain
				end
				if awaited == "" or string.lower(fromName) == string.lower(awaited) then
					WebDKP_HandleSubWhisperData(fromName, "WebDKP: " .. (payload or ""))
				end
			end
		end
		return
	end
	if WebDKP_SubSync_OrigHandleAddonMessage then
		return WebDKP_SubSync_OrigHandleAddonMessage(prefix, message, channel, sender)
	end
end

-- ===================== 回传完成 -> 缓存快照（包裹密语解析器） =====================
WebDKP_SubSync_OrigHandleSubWhisperData = WebDKP_HandleSubWhisperData
function WebDKP_HandleSubWhisperData(fromPlayer, message)
	if WebDKP_SubSync_OrigHandleSubWhisperData then
		WebDKP_SubSync_OrigHandleSubWhisperData(fromPlayer, message)
	end
	if message and string.find(message, "SUB_COMPLETE:") then
		WebDKP_SubSync_SnapshotCache(fromPlayer)
	end
end

-- ===================== 手动刷新 =====================
function WebDKP_SubSync_RefreshRoster()
	local cap = ""
	if WebDKP_Options and WebDKP_Options["SubSettings"] then
		cap = WebDKP_Options["SubSettings"].captain or ""
	end
	if cap == "" then
		SubSyncPrint("未设置替补队长，无法刷新")
		return
	end
	if WebDKP_SubAwardData then
		WebDKP_SubAwardData.captain = cap
		WebDKP_SubAwardData.receivedResponse = false
	end
	EnsureCache()
	WebDKP_SubSync_Cache[string.lower(cap)] = nil
	WebDKP_SubSync_ForceQuery = true
	SendAddonMessage("AMB_TBQQ", cap)
	WebDKP_SubSync_ForceQuery = false
	local mode = "密语"
	if WebDKP_SubSync_IsSameGuild(cap) then mode = "工会频道" end
	SubSyncPrint("已通过" .. mode .. "向 " .. cap .. " 刷新替补名单……")
end

SLASH_WEBDKPSUBSYNC1 = "/subteam"
SlashCmdList["WEBDKPSUBSYNC"] = function(msg)
	msg = msg or ""
	msg = string.lower(msg)
	msg = string.gsub(msg, "^%s+", "")
	msg = string.gsub(msg, "%s+$", "")
	if msg == "" or msg == "refresh" or msg == "刷新" then
		WebDKP_SubSync_RefreshRoster()
	elseif string.find(msg, "^ttl") then
		local _, _, val = string.find(msg, "(%d+)")
		if val then
			WebDKP_SubSync_TTL = tonumber(val)
			SubSyncPrint("缓存有效期已设为 " .. WebDKP_SubSync_TTL .. " 秒")
		else
			SubSyncPrint("当前缓存有效期 " .. (WebDKP_SubSync_TTL or 300) .. " 秒。用法 /subteam ttl 300")
		end
	else
		SubSyncPrint("用法：/subteam 刷新替补名单 | /subteam ttl 300 设置缓存秒数")
	end
end

-- ===================== 事件 =====================
WebDKP_SubSync_EventFrame = CreateFrame("Frame")
WebDKP_SubSync_EventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
WebDKP_SubSync_EventFrame:RegisterEvent("PLAYER_LOGIN")
WebDKP_SubSync_EventFrame:RegisterEvent("GUILD_ROSTER_UPDATE")
WebDKP_SubSync_EventFrame:RegisterEvent("VARIABLES_LOADED")
WebDKP_SubSync_EventFrame:SetScript("OnEvent", function()
	if event == "GUILD_ROSTER_UPDATE" then
		WebDKP_SubSync_RebuildGuildSet()
	else
		EnsureCache()
		if GuildRoster then GuildRoster() end
	end
end)

SubSyncPrint("替补同步模块已加载：同工会走工会频道、跨工会走密语，自动缓存防重复查询。输入 /subteam 手动刷新。")

end -- WebDKP_SubSync_Installed
