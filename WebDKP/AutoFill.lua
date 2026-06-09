------------------------------------------------------------------------
-- 自动填充任务
------------------------------------------------------------------------
-- 此文件包含与在物品掉落时在您的DKP表单中自动填充信息相关的方法
------------------------------------------------------------------------

StaticPopupDialogs["WEBDKP_AUTOAWARD_MOREINFO"] = {
	text = "授予 ", --%s %s
	button1 = "是",
	button2 = "不",
	--OnShow = function()
		-- getglobal(this:GetName().."EditBox"):SetText("");
		-- 注意：“this”是StaticPopup，通常是“StaticPopup1”
	--end,
	--OnAccept = function()
		-- local cost = getglobal(this:GetParent():GetName().."EditBox"):GetText();
		--WebDKP_AutoAward(cost);
	--end,
	timeout = 30,
	whileDead = 1,
	hideOnEscape = 1,
	hasEditBox = 1
};

-- ================================
-- 辅助结构，将物品的稀有度映射回其等级
-- ================================
WebDKP_RarityTable = {
	[0] = -1,
	[1] = 0,
	[2] = 1,
	[3] = 2,
	[4] = 3,
	[5] = 4
};

-- ================================
-- 当战利品被领取时触发的事件。如果启用了自动填充，
-- 这必须检查以查看：
-- 1 - 掉落了什么物品，并填入物品输入框
-- 2 - 查看哪个玩家获得了该物品并选择他们
-- 3 - 查看物品是否在战利品表中，并在其存在时输入成本
-- 4 - 如果启用了自动授予，则应授予该物品
-- ================================
function WebDKP_Loot_Taken()
	-- 首先检查是否是自动分配的物品获得消息
	local sPlayer, sLink;
	-- 使用更严格的模式匹配，确保正确提取玩家名称
	local iStart, iEnd, sPlayerName, sItem = string.find(arg1, "^([^%s]+)获得了物品：(.+)。");
	if ( sPlayerName ) then
		-- 验证玩家名称合理性
		if string.len(sPlayerName) > 20 or string.len(sPlayerName) < 2 or 
		   string.find(sPlayerName, "获得了物品") or string.find(sPlayerName, "拾取了物品") then
			-- 玩家名称不合理，尝试其他解析方式
			sPlayerName = nil;
		end
	end
	if ( sPlayerName ) then
		sPlayer = (sPlayerName == "你") and UnitName("player") or sPlayerName;
		sLink = sItem;
	end
	-- 检查是否是自动分配成功
	if WebDKP_AutoLootData and WebDKP_AutoLootData.isAssigning and sPlayer and sLink then
		local itemName = string.match(sLink, "%[(.+)%]") or sLink;
		-- 当获得物品的玩家是目标玩家时认为分配成功（包括给自己分配的情况）
		if sPlayer == WebDKP_AutoLootData.currentPlayer and itemName == WebDKP_AutoLootData.currentItem then
			-- 分配成功
			WebDKP_StopAutoLoot(true);
			local tellLocation = WebDKP_GetTellLocation();
			-- 确保播报时显示具体玩家名字，而不是"你"
			local displayName = sPlayer;
			if sPlayer == UnitName("player") then
				-- 如果是自己，使用具体的玩家名字而不是"你"
				displayName = UnitName("player");
			end
			WebDKP_SendAnnouncement(displayName.."获得了物品："..sLink.."。", tellLocation);
			return;
		end
	end
	
	-- 原有的自动填充逻辑
	if ( WebDKP_Options["AutofillEnabled"] == 0 ) then
		return;
	end
	
	if ( sLink and sPlayer ) then
		local sRarity, sName, sItem = WebDKP_GetItemInfo(sLink);
		local rarity = WebDKP_RarityTable[sRarity];
		local cost = nil; 
		
		-- 检查物品拾取记录品质等级设置
		if not WebDKP_Options then
			WebDKP_Options = {}
		end
		if not WebDKP_Options["LootQualityLevel"] then
			WebDKP_Options["LootQualityLevel"] = 1
		end
		
		-- 根据品质等级过滤物品
		local shouldRecord = false
		if WebDKP_Options["LootQualityLevel"] == 1 then
			-- 等级1：只记录橙色(4)、紫色(3)品质
			shouldRecord = (rarity >= 3)
		elseif WebDKP_Options["LootQualityLevel"] == 2 then
			-- 等级2：记录橙色(4)、紫色(3)、蓝色(2)品质
			shouldRecord = (rarity >= 2)
		elseif WebDKP_Options["LootQualityLevel"] == 3 then
			-- 等级3：记录橙色(4)、紫色(3)、蓝色(2)、绿色(1)品质
			shouldRecord = (rarity >= 1)
		end
		
		if not shouldRecord then
			return;
		end
		
		if( rarity < WebDKP_Options["AutofillThreshold"] ) then
			return;
		end
		WebDKP_AwardItem_FrameItemName:SetText(sName);
		-- 看看我们能否在此期间确定成本...
		if ( WebDKP_Loot ~= nil ) then
			cost = WebDKP_Loot[sName];
			if ( cost ~= nil ) then 
				WebDKP_AwardItem_FrameItemCost:SetText(cost);
			else
				WebDKP_AwardItem_FrameItemCost:SetText("");
			end
		end
		WebDKP_SelectPlayerOnly(sPlayer);
		
		-- 如果我们设置为自动授予物品，继续尝试
		-- 我们需要确保拥有所有数据
		if (WebDKP_Options["AutoAwardEnabled"] == 1) then
			--PlaySound("QUESTADDED");
			if ( cost ~= nil ) then
				WebDKP_ShowAwardFrame("授予 "..sPlayer.." "..sLink.." 至 "..cost.." DKP? \r\n (输入DKP数值,只能正数)",cost);
				WebDKP_AwardFrameCost:SetText(cost);
			else
				WebDKP_ShowAwardFrame("授予 "..sPlayer.." "..sLink.."? \r\n (输入DKP数值,只能正数)",nil);
				--PlaySound("igQuestFailed");
			end
		end
	end
end

function WebDKP_ShowAwardFrame(title, cost)
	-- 不再显示确认框，而是记录日志
	if WebDKP_Print then
		WebDKP_Print("已禁用WebDKP_ShowAwardFrame确认框")
	else
		DEFAULT_CHAT_FRAME:AddMessage("已禁用WebDKP_ShowAwardFrame确认框")
	end
	-- 返回true表示操作应该继续
	return true
end

-- ================================
-- 从自动授予对话框中单击“是”时的回调函数
-- ================================
function WebDKP_AutoAward(cost)
	WebDKP_AwardItem_FrameItemCost:SetText(cost);
	WebDKP_AwardItem_Event();
end

-- ================================
-- 授予物品字段中输入名称的事件处理程序
-- 如果玩家的战利品表中有成本，将自动填入成本
-- ================================
function WebDKP_AutoFillCost()
	if ( WebDKP_Options["AutofillEnabled"] == 0 ) then
		return;
	end
	local sName = WebDKP_AwardItem_FrameItemName:GetText();
	
	-- 看看我们能否在此期间确定成本...
	if ( WebDKP_Loot ~= nil and sName ~= nil) then
		local cost = WebDKP_Loot[sName];
		if ( cost ~= nil ) then 
			WebDKP_AwardItem_FrameItemCost:SetText(cost);
		end
	end
end

-- ================================
-- 授予DKP原因字段中输入名称的事件处理程序
-- 如果玩家的战利品表中有成本，将自动填入成本
-- ================================
function WebDKP_AutoFillDKP(reasonFrame, pointsFrame)
	if ( WebDKP_Options["AutofillEnabled"] == 0 ) then
		return;
	end
	local reasonBox = reasonFrame or WebDKP_AwardDKP_FrameReason;
	local pointsBox = pointsFrame or WebDKP_AwardDKP_FramePoints;
	if ( reasonBox == nil or pointsBox == nil or reasonBox.GetText == nil or pointsBox.SetText == nil ) then
		return;
	end
	local sName = reasonBox:GetText();
	
	-- 看看我们能否在此期间确定成本...
	if ( WebDKP_Loot ~= nil and sName ~= nil) then
		local cost = WebDKP_Loot[sName];
		if ( cost ~= nil ) then 
			pointsBox:SetText(cost);
		end
	end
end

-- ================================
-- 切换自动填充启用状态
-- ================================
function WebDKP_ToggleAutofill()
	-- 如果启用，则禁用
	if ( WebDKP_Options["AutofillEnabled"] == 1 ) then
		if WebDKP_Options_FrameToggleAutofill then
			WebDKP_Options_FrameToggleAutofill:SetChecked(0);
		end
		WebDKP_Options["AutofillEnabled"] = 0;
		if WebDKP_Options_FrameAutofillDropDown then
			WebDKP_Options_FrameAutofillDropDown:Hide();
		end
		if WebDKP_Options_FrameToggleAutoAward then
			WebDKP_Options_FrameToggleAutoAward:Hide();
		end
	-- 如果禁用，则启用
	else
		if WebDKP_Options_FrameToggleAutofill then
			WebDKP_Options_FrameToggleAutofill:SetChecked(1);
		end
		WebDKP_Options["AutofillEnabled"] = 1;
		if WebDKP_Options_FrameAutofillDropDown then
			WebDKP_Options_FrameAutofillDropDown:Show();
		end
		if WebDKP_Options_FrameToggleAutoAward then
			WebDKP_Options_FrameToggleAutoAward:Show();
		end
	end
end

-- ================================
-- 切换自动授予状态。当启用时，如果所有信息都可以自动填充，
-- 则将自动完成物品奖励。
-- ================================
function WebDKP_ToggleAutoAward()
	-- 如果启用，则禁用
	if ( WebDKP_Options["AutoAwardEnabled"] == 1 ) then
		WebDKP_Options["AutoAwardEnabled"] = 0;
	-- 如果禁用，则启用
	else
		WebDKP_Options["AutoAwardEnabled"] = 1;
	end
end

-- ================================
-- 当图形用户界面加载下拉列表的自动填充阈值时调用
-- ================================
function WebDKP_Options_Autofill_DropDown_OnLoad()
	if WebDKP_Options_FrameAutofillDropDown then
		UIDropDownMenu_Initialize(WebDKP_Options_FrameAutofillDropDown, WebDKP_Options_Autofill_DropDown_Init);
	end
end
-- ================================
-- 当自动填充选项的下拉列表加载时调用
-- ================================
function WebDKP_Options_Autofill_DropDown_Init()
	if not WebDKP_Options_FrameAutofillDropDown then
		return;
	end
	local info;
	local selected = "";
	WebDKP_AddAutofillChoice("灰色物品",-1);
	WebDKP_AddAutofillChoice("白色物品",0);
	WebDKP_AddAutofillChoice("绿色物品",1);
	WebDKP_AddAutofillChoice("蓝色物品",2);
	WebDKP_AddAutofillChoice("紫色物品",3);
	WebDKP_AddAutofillChoice("橙色物品",4);
	
	UIDropDownMenu_SetWidth(130, WebDKP_Options_FrameAutofillDropDown);
end
-- ================================
-- 辅助方法，将选项添加到自动填充下拉菜单中
-- ================================
function WebDKP_AddAutofillChoice(text, value)
	if not WebDKP_Options_FrameAutofillDropDown then
		return;
	end
	info = { };
	info.text = text;
	info.value = value; 
	info.func = WebDKP_Options_Autofill_DropDown_OnClick;
	if ( value == WebDKP_Options["AutofillThreshold"] ) then
		info.checked = ( 1 == 1 );
		UIDropDownMenu_SetSelectedName(WebDKP_Options_FrameAutofillDropDown, info.text );
	end
	UIDropDownMenu_AddButton(info);
end

-- ================================
-- 当用户在不同的自动填充阈值之间切换时调用
-- ================================
function WebDKP_Options_Autofill_DropDown_OnClick()
	if not WebDKP_Options_FrameAutofillDropDown then
		return;
	end
	WebDKP_Options["AutofillThreshold"] = this.value; 
	WebDKP_Options_Autofill_DropDown_Init();
end
