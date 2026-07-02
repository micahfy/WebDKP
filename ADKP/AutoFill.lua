------------------------------------------------------------------------
-- 自动填充任务
------------------------------------------------------------------------
-- 此文件包含与在物品掉落时在您的DKP表单中自动填充信息相关的方法
------------------------------------------------------------------------

StaticPopupDialogs["ADKP_AUTOAWARD_MOREINFO"] = {
	text = "授予 ", --%s %s
	button1 = "是",
	button2 = "不",
	--OnShow = function()
		-- getglobal(this:GetName().."EditBox"):SetText("");
		-- 注意：“this”是StaticPopup，通常是“StaticPopup1”
	--end,
	--OnAccept = function()
		-- local cost = getglobal(this:GetParent():GetName().."EditBox"):GetText();
		--ADKP_AutoAward(cost);
	--end,
	timeout = 30,
	whileDead = 1,
	hideOnEscape = 1,
	hasEditBox = 1
};

-- ================================
-- 辅助结构，将物品的稀有度映射回其等级
-- ================================
ADKP_RarityTable = {
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
function ADKP_Loot_Taken()
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
	if ADKP_AutoLootData and ADKP_AutoLootData.isAssigning and sPlayer and sLink then
		local itemName = string.match(sLink, "%[(.+)%]") or sLink;
		-- 当获得物品的玩家是目标玩家时认为分配成功（包括给自己分配的情况）
		if sPlayer == ADKP_AutoLootData.currentPlayer and itemName == ADKP_AutoLootData.currentItem then
			-- 分配成功
			ADKP_StopAutoLoot(true);
			local tellLocation = ADKP_GetTellLocation();
			-- 确保播报时显示具体玩家名字，而不是"你"
			local displayName = sPlayer;
			if sPlayer == UnitName("player") then
				-- 如果是自己，使用具体的玩家名字而不是"你"
				displayName = UnitName("player");
			end
			ADKP_SendAnnouncement(displayName.."获得了物品："..sLink.."。", tellLocation);
			return;
		end
	end
	
	-- 原有的自动填充逻辑
	if ( ADKP_Options["AutofillEnabled"] == 0 ) then
		return;
	end
	
	if ( sLink and sPlayer ) then
		local sRarity, sName, sItem = ADKP_GetItemInfo(sLink);
		local rarity = ADKP_RarityTable[sRarity];
		local cost = nil; 
		
		-- 检查物品拾取记录品质等级设置
		if not ADKP_Options then
			ADKP_Options = {}
		end
		if not ADKP_Options["LootQualityLevel"] then
			ADKP_Options["LootQualityLevel"] = 1
		end
		
		-- 根据品质等级过滤物品
		local shouldRecord = false
		if ADKP_Options["LootQualityLevel"] == 1 then
			-- 等级1：只记录橙色(4)、紫色(3)品质
			shouldRecord = (rarity >= 3)
		elseif ADKP_Options["LootQualityLevel"] == 2 then
			-- 等级2：记录橙色(4)、紫色(3)、蓝色(2)品质
			shouldRecord = (rarity >= 2)
		elseif ADKP_Options["LootQualityLevel"] == 3 then
			-- 等级3：记录橙色(4)、紫色(3)、蓝色(2)、绿色(1)品质
			shouldRecord = (rarity >= 1)
		end
		
		if not shouldRecord then
			return;
		end
		
		if( rarity < ADKP_Options["AutofillThreshold"] ) then
			return;
		end
		ADKP_AwardItem_FrameItemName:SetText(sName);
		-- 看看我们能否在此期间确定成本...
		if ( ADKP_Loot ~= nil ) then
			cost = ADKP_Loot[sName];
			if ( cost ~= nil ) then 
				ADKP_AwardItem_FrameItemCost:SetText(cost);
			else
				ADKP_AwardItem_FrameItemCost:SetText("");
			end
		end
		ADKP_SelectPlayerOnly(sPlayer);
		
		-- 如果我们设置为自动授予物品，继续尝试
		-- 我们需要确保拥有所有数据
		if (ADKP_Options["AutoAwardEnabled"] == 1) then
			--PlaySound("QUESTADDED");
			if ( cost ~= nil ) then
				ADKP_ShowAwardFrame("授予 "..sPlayer.." "..sLink.." 至 "..cost.." DKP? \r\n (输入DKP数值,只能正数)",cost);
				ADKP_AwardFrameCost:SetText(cost);
			else
				ADKP_ShowAwardFrame("授予 "..sPlayer.." "..sLink.."? \r\n (输入DKP数值,只能正数)",nil);
				--PlaySound("igQuestFailed");
			end
		end
	end
end

function ADKP_ShowAwardFrame(title, cost)
	-- 不再显示确认框，而是记录日志
	if ADKP_Print then
		ADKP_Print("已禁用ADKP_ShowAwardFrame确认框")
	else
		DEFAULT_CHAT_FRAME:AddMessage("已禁用ADKP_ShowAwardFrame确认框")
	end
	-- 返回true表示操作应该继续
	return true
end

-- ================================
-- 从自动授予对话框中单击“是”时的回调函数
-- ================================
function ADKP_AutoAward(cost)
	ADKP_AwardItem_FrameItemCost:SetText(cost);
	ADKP_AwardItem_Event();
end

-- ================================
-- 授予物品字段中输入名称的事件处理程序
-- 如果玩家的战利品表中有成本，将自动填入成本
-- ================================
function ADKP_AutoFillCost()
	if ( ADKP_Options["AutofillEnabled"] == 0 ) then
		return;
	end
	local sName = ADKP_AwardItem_FrameItemName:GetText();
	
	-- 看看我们能否在此期间确定成本...
	if ( ADKP_Loot ~= nil and sName ~= nil) then
		local cost = ADKP_Loot[sName];
		if ( cost ~= nil ) then 
			ADKP_AwardItem_FrameItemCost:SetText(cost);
		end
	end
end

-- ================================
-- 授予DKP原因字段中输入名称的事件处理程序
-- 如果玩家的战利品表中有成本，将自动填入成本
-- ================================
function ADKP_AutoFillDKP(reasonFrame, pointsFrame)
	if ( ADKP_Options["AutofillEnabled"] == 0 ) then
		return;
	end
	local reasonBox = reasonFrame or ADKP_AwardDKP_FrameReason;
	local pointsBox = pointsFrame or ADKP_AwardDKP_FramePoints;
	if ( reasonBox == nil or pointsBox == nil or reasonBox.GetText == nil or pointsBox.SetText == nil ) then
		return;
	end
	local sName = reasonBox:GetText();
	
	-- 看看我们能否在此期间确定成本...
	if ( ADKP_Loot ~= nil and sName ~= nil) then
		local cost = ADKP_Loot[sName];
		if ( cost ~= nil ) then 
			pointsBox:SetText(cost);
		end
	end
end

-- ================================
-- 切换自动填充启用状态
-- ================================
function ADKP_ToggleAutofill()
	-- 如果启用，则禁用
	if ( ADKP_Options["AutofillEnabled"] == 1 ) then
		if ADKP_Options_FrameToggleAutofill then
			ADKP_Options_FrameToggleAutofill:SetChecked(0);
		end
		ADKP_Options["AutofillEnabled"] = 0;
		if ADKP_Options_FrameAutofillDropDown then
			ADKP_Options_FrameAutofillDropDown:Hide();
		end
		if ADKP_Options_FrameToggleAutoAward then
			ADKP_Options_FrameToggleAutoAward:Hide();
		end
	-- 如果禁用，则启用
	else
		if ADKP_Options_FrameToggleAutofill then
			ADKP_Options_FrameToggleAutofill:SetChecked(1);
		end
		ADKP_Options["AutofillEnabled"] = 1;
		if ADKP_Options_FrameAutofillDropDown then
			ADKP_Options_FrameAutofillDropDown:Show();
		end
		if ADKP_Options_FrameToggleAutoAward then
			ADKP_Options_FrameToggleAutoAward:Show();
		end
	end
end

-- ================================
-- 切换自动授予状态。当启用时，如果所有信息都可以自动填充，
-- 则将自动完成物品奖励。
-- ================================
function ADKP_ToggleAutoAward()
	-- 如果启用，则禁用
	if ( ADKP_Options["AutoAwardEnabled"] == 1 ) then
		ADKP_Options["AutoAwardEnabled"] = 0;
	-- 如果禁用，则启用
	else
		ADKP_Options["AutoAwardEnabled"] = 1;
	end
end

-- ================================
-- 当图形用户界面加载下拉列表的自动填充阈值时调用
-- ================================
function ADKP_Options_Autofill_DropDown_OnLoad()
	if ADKP_Options_FrameAutofillDropDown then
		UIDropDownMenu_Initialize(ADKP_Options_FrameAutofillDropDown, ADKP_Options_Autofill_DropDown_Init);
	end
end
-- ================================
-- 当自动填充选项的下拉列表加载时调用
-- ================================
function ADKP_Options_Autofill_DropDown_Init()
	if not ADKP_Options_FrameAutofillDropDown then
		return;
	end
	local info;
	local selected = "";
	ADKP_AddAutofillChoice("灰色物品",-1);
	ADKP_AddAutofillChoice("白色物品",0);
	ADKP_AddAutofillChoice("绿色物品",1);
	ADKP_AddAutofillChoice("蓝色物品",2);
	ADKP_AddAutofillChoice("紫色物品",3);
	ADKP_AddAutofillChoice("橙色物品",4);
	
	UIDropDownMenu_SetWidth(130, ADKP_Options_FrameAutofillDropDown);
end
-- ================================
-- 辅助方法，将选项添加到自动填充下拉菜单中
-- ================================
function ADKP_AddAutofillChoice(text, value)
	if not ADKP_Options_FrameAutofillDropDown then
		return;
	end
	info = { };
	info.text = text;
	info.value = value; 
	info.func = ADKP_Options_Autofill_DropDown_OnClick;
	if ( value == ADKP_Options["AutofillThreshold"] ) then
		info.checked = ( 1 == 1 );
		UIDropDownMenu_SetSelectedName(ADKP_Options_FrameAutofillDropDown, info.text );
	end
	UIDropDownMenu_AddButton(info);
end

-- ================================
-- 当用户在不同的自动填充阈值之间切换时调用
-- ================================
function ADKP_Options_Autofill_DropDown_OnClick()
	if not ADKP_Options_FrameAutofillDropDown then
		return;
	end
	ADKP_Options["AutofillThreshold"] = this.value; 
	ADKP_Options_Autofill_DropDown_Init();
end
