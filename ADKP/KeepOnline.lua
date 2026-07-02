-- 注意：请在非休息区使用——休息区小退为即时退出，无倒计时弹窗可取消。

local QueueFunction = QueueFunction
if not QueueFunction then
	local _queue, _frame = {}, CreateFrame("Frame")
	_frame:Hide()
	_frame:SetScript("OnUpdate", function()
		_frame:Hide()
		local n = table.getn(_queue)
		for i = 1, n do
			_queue[i]()
		end
		for i = 1, n do
			_queue[i] = nil
		end
	end)
	QueueFunction = function(func)
		table.insert(_queue, func)
		_frame:Show()
	end
end

-- CloseCamping
local function CloseCamping()
	for i = 1, STATICPOPUP_NUMDIALOGS do
		local KeepOnlineFrame = getglobal("StaticPopup" .. i)
		if KeepOnlineFrame and KeepOnlineFrame:IsVisible() then
			local button = getglobal("StaticPopup" .. i .. "Button1")
			if button then
				button:Click()
			end
		end
	end
end

-- 事件 frame：PLAYER_CAMPING -> QueueFunction(CloseCamping)
local KeepOnlineFrame = CreateFrame("Frame")
KeepOnlineFrame:RegisterEvent("PLAYER_CAMPING")
KeepOnlineFrame:SetScript("OnEvent", function()
	if not ADKP_Options or not ADKP_Options["KeepOnlineEnabled"] then
		return
	end
	QueueFunction(CloseCamping)
end)
