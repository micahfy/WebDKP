-- WebDKP / KeepOnline: 保持在线(挂机模式)

local KeepOnlineFrame = CreateFrame("Frame")

KeepOnlineFrame:RegisterEvent("PLAYER_CAMPING")

KeepOnlineFrame:SetScript("OnEvent", function()
	-- 未启用则不干预小退
	if not WebDKP_Options or not WebDKP_Options["KeepOnlineEnabled"] then
		return
	end
	-- 弹窗可能尚未显示，延迟到下一帧再尝试关闭
	KeepOnlineFrame.delay = 0.2
	KeepOnlineFrame:SetScript("OnUpdate", function()
		KeepOnlineFrame.delay = KeepOnlineFrame.delay - arg1
		if KeepOnlineFrame.delay > 0 then
			return
		end
		KeepOnlineFrame:SetScript("OnUpdate", nil)
		for i = 1, STATICPOPUP_NUMDIALOGS do
			local popup = getglobal("StaticPopup" .. i)
			if popup and popup:IsVisible() then
				local cancelBtn = getglobal("StaticPopup" .. i .. "Button1")
				if cancelBtn then
					cancelBtn:Click()
				end
			end
		end
	end)
end)
