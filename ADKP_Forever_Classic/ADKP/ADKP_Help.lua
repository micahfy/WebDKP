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
------------------------------------------------------------------------
-- HELP (Hover Tooltips for Checkboxes)
------------------------------------------------------------------------
-- 给设置界面的勾选框提供鼠标悬停说明。
--
-- ▶ 如何修改 / 增删说明：
--   只需编辑下面的 ADKP_HelpText 表。每个勾选框对应一个条目，
--   键 = 勾选框的全局名（与 XML 里 name= 解析后的名字一致）。
--   值 = { zh = { "标题", "正文行1", "正文行2", ... },
--         en = { "Title", "line1", "line2", ... } }
--   - 第一个元素是标题（白色显示），其余是正文（浅灰显示）。
--   - zh = 中文，en = 英文；运行时按客户端语言自动选用。
--   - 想新增一个勾选框的说明，照葫芦画瓢加一个条目即可（注册全自动）。
--   - 想隐藏某个说明（保留文案、悬停不弹出）：给该条目加  hidden = true  即可。
--       ["某个勾选框"] = { zh = { ... }, en = { ... }, hidden = true },
--
-- ▶ 语言切换：
--   客户端为 zhCN / zhTW 显示中文，其余显示英文。
--   若某种语言只有一半文案，缺失时自动回退到中文，再回退到英文。
------------------------------------------------------------------------

ADKP_HelpText = {

    -- ===== 职业过滤（ADKP_ClassFiltersFrame）=====
    ["ADKP_FiltersFrameClassDruid"] = {
        zh = { "德鲁伊", "勾选则在名单中显示德鲁伊，取消则隐藏。" },
        en = { "Druid", "Check to show Druids in the list; uncheck to hide them." },
        hidden = true,
    },
    ["ADKP_FiltersFrameClassHunter"] = {
        zh = { "猎人", "勾选则在名单中显示猎人，取消则隐藏。" },
        en = { "Hunter", "Check to show Hunters in the list; uncheck to hide them." },
        hidden = true,
    },
    ["ADKP_FiltersFrameClassMage"] = {
        zh = { "法师", "勾选则在名单中显示法师，取消则隐藏。" },
        en = { "Mage", "Check to show Mages in the list; uncheck to hide them." },
        hidden = true,
    },
    ["ADKP_FiltersFrameClassRogue"] = {
        zh = { "潜行者", "勾选则在名单中显示潜行者，取消则隐藏。" },
        en = { "Rogue", "Check to show Rogues in the list; uncheck to hide them." },
        hidden = true,
    },
    ["ADKP_FiltersFrameClassShaman"] = {
        zh = { "萨满祭司", "勾选则在名单中显示萨满祭司，取消则隐藏。" },
        en = { "Shaman", "Check to show Shamans in the list; uncheck to hide them." },
        hidden = true,
    },
    ["ADKP_FiltersFrameClassPaladin"] = {
        zh = { "圣骑士", "勾选则在名单中显示圣骑士，取消则隐藏。" },
        en = { "Paladin", "Check to show Paladins in the list; uncheck to hide them." },
        hidden = true,
    },
    ["ADKP_FiltersFrameClassPriest"] = {
        zh = { "牧师", "勾选则在名单中显示牧师，取消则隐藏。" },
        en = { "Priest", "Check to show Priests in the list; uncheck to hide them." },
        hidden = true,
    },
    ["ADKP_FiltersFrameClassWarrior"] = {
        zh = { "战士", "勾选则在名单中显示战士，取消则隐藏。" },
        en = { "Warrior", "Check to show Warriors in the list; uncheck to hide them." },
        hidden = true,
    },
    ["ADKP_FiltersFrameClassWarlock"] = {
        zh = { "术士", "勾选则在名单中显示术士，取消则隐藏。" },
        en = { "Warlock", "Check to show Warlocks in the list; uncheck to hide them." },
        hidden = true,
    },

    -- ===== 设置 Tab1（ADKP_AwardDKP_Frame）=====
    ["ADKP_AwardDKP_FrameSubLeaderInput"] = {
        zh = { "替补队长", "填写当前 DKP 团队的替补队长名字，点击“设置”保存。不同 DKP 团队分别保存。", "当前队长及最近同步情况显示在输入框下方。" },
        en = { "Substitute Captain", "Enter the captain for this DKP team and click Set. Each DKP team keeps its own captain." },
    },
    ["ADKP_AwardDKP_FrameSubLeaderSet"] = {
        zh = { "设置替补队长", "保存输入框中的名字；清空名字后点击此按钮，可取消当前团队的替补队长。" },
        en = { "Set Substitute Captain", "Save the entered name. Save an empty name to clear the captain for this DKP team." },
    },
    ["ADKP_AwardDKP_FrameSubLeaderTestSync"] = {
        zh = { "测试替补名单同步", "向已设置的替补队长请求替补名单，用于检查名单通讯是否正常。" },
        en = { "Test Substitute Roster", "Request the substitute roster from the configured captain to check communication." },
    },
    ["ADKP_AwardDKP_FrameBossBtn"] = {
        zh = { "Boss 名单与分值", "选择需要记录的 Boss，并配置主团和替补的击杀分值。可先统一设置，再调整个别 Boss。" },
        en = { "Boss List and DKP", "Select bosses and configure their raid and substitute awards. Apply a common value first, then adjust individual bosses." },
    },
    ["ADKP_AwardDKP_FrameBidBtn"] = {
        zh = { "打开竞拍窗口", "打开物品竞拍界面，使用上方选定的公开或匿名拍卖模式。" },
        en = { "Open Auction Window", "Open item auctions using the selected public or anonymous mode." },
    },
    ["ADKP_AwardDKP_FrameAutoInviteKeyword"] = {
        zh = { "组人口令", "填写用于自动邀请的口令，按回车或点击“确认”保存。需同时开启“密语组人”。" },
        en = { "Invite Keyword", "Enter the invite keyword and press Enter or Confirm to save. Whisper Invite must also be enabled." },
    },
    ["ADKP_AwardDKP_FrameAutoInviteKeywordSet"] = {
        zh = { "保存组人口令", "保存左侧输入框中的口令。" },
        en = { "Save Invite Keyword", "Save the keyword entered on the left." },
    },
    
    
    
    
    
    ["ADKP_AwardDKP_FrameImportBtn"] = {
        zh = { "导入初始分", "打开网站 DKP 数据导入窗口，按窗口说明导入新一轮活动的初始数据。" },
        en = { "Import Initial DKP", "Open the website DKP import window to start a new round with initial data." },
    },
    ["ADKP_AwardDKP_FrameExportBtn"] = {
        zh = { "导出当前记录", "打开当前活动记录的导出窗口，用于复制并提交到网站。" },
        en = { "Export Current Records", "Open the record export window to copy data for the website." },
    },
    ["ADKP_AwardDKP_FrameReloadBtn"] = {
        zh = { "重载游戏界面", "重新加载插件和游戏界面，相当于 /reload。" },
        en = { "Reload UI", "Reload the game interface and addons, equivalent to /reload." },
    },
    ["ADKP_AwardDKP_FrameSubCaptainChk"] = {
        zh = { "替补队长加分",
               "勾选后，给主团加分时一并把替补队长计入奖励名单。" },
        en = { "Include Sub Captain",
               "When checked, the substitute-team captain is included when awarding DKP to the main raid." },
        hidden = false,
    },
    ["ADKP_AwardDKP_FrameToggleAutoAward"] = {
        zh = { "启用 Boss 击杀加分",
               "Boss 击杀加分总开关。开启后，在下方选择弹窗确认或全自动；两种模式均使用 Boss 名单配置的主团/替补分值。关闭时保留已选模式。" },
        en = { "Enable Boss Kill DKP",
               "Enables boss kill awards. Choose popup confirmation or full auto below; both use the main raid and substitute values from the boss list. Disabling retains the selected mode." },
        hidden = false,
    },
    ["ADKP_AwardDKP_FrameBossAwardConfirm"] = {
        zh = { "弹窗确认",
               "与全自动二选一。Boss 满足击杀规则后，等待脱战弹窗；同场最多一次，采用最后满足条件的 Boss 及其主团/替补分值。不同场战斗依次确认，关闭窗口表示跳过该次加分。" },
        en = { "Popup Confirmation",
               "Prompt after leaving combat, once per battle, using the last qualifying boss and its raid/standby points. Separate battles are queued. Closing a popup skips that award." },
        hidden = false,
    },
    ["ADKP_AwardDKP_FrameToggleBossAutoAward"] = {
        zh = { "全自动",
               "与弹窗确认二选一。Boss 满足击杀规则后，等待脱战加分；同场最多一次，采用最后满足条件的 Boss 及其主团/替补分值并团队播报。不同场战斗依次处理，悬浮窗顶部可查看记录。" },
        en = { "Full Auto Award",
               "Award after leaving combat, once per battle, using the last qualifying boss and its raid/standby points. Separate battles are queued, announced, and shown on the quick float bar." },
        hidden = false,
    },
    ["ADKP_AwardDKP_FrameToggleRaidDkpReply"] = {
        zh = { "允许团员查询 DKP",
               "开启后，团队成员可私密你查询自己或者其他人的 DKP 余额。查询方法密语dkp 查询自己的DKP 或者“dkp 名字” 查询别人的DKP。" },
        en = { "Allow DKP Queries",
               "When checked, members can privately message you to query their own or others' DKP balance. Send 'dkp' to query your own DKP, or 'dkp 名字' to query someone else's DKP." },
        hidden = false,
    },
    ["ADKP_AwardDKP_FrameToggleSilentMode"] = {
        zh = { "全局静默模式",
               "开启后所有团队/队伍/公会播报只在本地聊天框显示，不再发送到聊天频道。" },
        en = { "Global Silent Mode",
               "All raid/party/guild announcements stay local only; nothing is sent to chat channels." },
        hidden = false,
    },
    
    ["ADKP_AwardDKP_FrameToggleAutofill"] = {
        zh = { "自动填充物品/分数",
               "加分或发装备时，根据掉落表自动填入物品名称与建议分数。" },
        en = { "Auto-Fill Item/Cost",
               "When awarding, automatically fills in the item name and suggested cost from the loot table." },
        hidden = false,
    },
    ["ADKP_AwardDKP_FrameToggleQuickFloatEnabled"] = {
        zh = { "启用快捷悬浮窗",
               "显示含集合/击杀/解散/奖惩等快捷按钮的侧边悬浮窗（仅在团队内显示）。" },
        en = { "Quick Float Panel",
               "Shows the side floating panel with quick buttons (rally/kill/dismiss/adjust); only shown inside a raid." },
        hidden = false,
    },
    ["ADKP_AwardDKP_FrameAuctionPublic"] = {
        zh = { "公开拍卖",
               "拍卖模式下，所有人的出分将公开显示。" },
        en = { "Public Auction",
               "In this auction mode, everyone's bids are shown publicly." },
        hidden = false,
    },
    ["ADKP_AwardDKP_FrameAuctionAnonymous"] = {
        zh = { "匿名拍卖",
               "拍卖模式下，出分者的身份将被隐藏。" },
        en = { "Anonymous Auction",
               "In this auction mode, bidders' identities are hidden." },
        hidden = false,
    },
    ["ADKP_AwardDKP_FrameToggleAutoInvite"] = {
        zh = { "密语组人",
               "开启后，当收到密语或在公会频道看到与“邀请密语”完全相同的内容时，自动邀请该玩家入队。",
               "密语忽略大小写。需自己为队长/团长。请在下方输入框设置邀请密语，点“确认”保存（默认 9527）。" },
        en = { "Whisper Invite",
               "When enabled, auto-invites anyone who whispers you or says the keyword in guild chat.",
               "Match is case-insensitive. You must be party/raid leader. Set the keyword below and click Confirm (default 9527)." },
        hidden = false,
    },
    ["ADKP_AwardDKP_FrameToggleAutoConvertRaid"] = {
        zh = { "自动转团",
               "开启后，当你是队长、小队已满5人且尚未转为团队时，密语组人前会先把小队转为团队。" },
        en = { "Auto Convert to Raid",
               "When enabled, auto-converts your full party to a raid before inviting, if you are the leader." },
        hidden = false,
    },

    -- ===== 自用 Tab6（ADKP_Personal_Frame）=====
    ["ADKP_Personal_FrameIncludeSubCaptain"] = {
        zh = { "替补队长加分",
               "勾选后，给主团加分时一并把替补队长计入奖励名单。" },
        en = { "Include Sub Captain",
               "When checked, the substitute-team captain is included when awarding DKP to the main raid." },
        hidden = false,
    },
    ["ADKP_Personal_FrameQuickFloatEnabled"] = {
        zh = { "开启快捷浮窗",
               "显示含集合/击杀/解散/奖惩等快捷按钮的侧边悬浮窗（仅在团队内显示）。" },
        en = { "Quick Float Panel",
               "Shows the side floating panel with quick buttons; only shown inside a raid." },
        hidden = false,
    },
    ["ADKP_Personal_FrameSilentMode"] = {
        zh = { "团队静音模式",
               "开启后所有团队/队伍/公会播报只在本地聊天框显示，不再发送到聊天频道。" },
        en = { "Silent Mode",
               "All raid/party/guild announcements stay local only; nothing is sent to chat channels." },
        hidden = false,
    },
    ["ADKP_Personal_FrameRaidDkpReply"] = {
        zh = { "团队查 DKP 回复",
               "开启后，团队成员可私密你查询自己的 DKP 余额。" },
        en = { "DKP Query Reply",
               "When on, raid members can whisper you to check their own DKP balance." },
        hidden = false,
    },

    -- ===== 拍卖窗口（ADKP_BidFrame）=====
    ["ADKP_BidFrameAuctionPublic"] = {
        zh = { "公开拍卖",
               "拍卖模式下，所有人的出分将公开显示。" },
        en = { "Public Auction",
               "In this auction mode, everyone's bids are shown publicly." },
        hidden = false,
    },
    ["ADKP_BidFrameAuctionAnonymous"] = {
        zh = { "匿名拍卖",
               "拍卖模式下，出分者的身份将被隐藏。" },
        en = { "Anonymous Auction",
               "In this auction mode, bidders' identities are hidden." },
        hidden = false,
    },
}

-- ================================
-- 按客户端语言返回 "zh" 或 "en"
-- ================================
function ADKP_Help_GetLang()
    local loc = GetLocale();
    if loc == "zhCN" or loc == "zhTW" then
        return "zh";
    end
    return "en";
end

-- ================================
-- 鼠标悬停时显示帮助（OnEnter）
-- 使用独立提示框，固定正文宽度并换行，不修改物品共用的 GameTooltip。
-- ================================
function ADKP_Help_Show()
    if not this then return end
    local entry = ADKP_HelpText[this:GetName()];
    if not entry then return end
    local t = entry[ADKP_Help_GetLang()] or entry["zh"] or entry["en"];
    if not t then return end
    if not ADKP_HelpTooltip then
        ADKP_HelpTooltip = CreateFrame("GameTooltip", "ADKP_HelpTooltip", UIParent, "GameTooltipTemplate");
        if ADKP_HelpTooltip.SetClampedToScreen then ADKP_HelpTooltip:SetClampedToScreen(true) end
    end
    local tip = ADKP_HelpTooltip;
    local anchor = "ANCHOR_RIGHT";
    if this:GetRight() and this:GetRight() > UIParent:GetWidth() / 2 then anchor = "ANCHOR_LEFT" end
    tip:SetOwner(this, anchor);
    tip:ClearLines();
    tip:SetText(t[1] or "", 1, 1, 1);
    for i = 2, table.getn(t) do
        tip:AddLine(t[i], 0.8, 0.8, 0.8, true);
    end
    if (this == ADKP_AwardDKP_FrameSubLeaderInput or this == ADKP_AwardDKP_FrameSubLeaderTestSync) and ADKP_AwardDKP_FrameSubCaptainLabel then
        tip:AddLine(ADKP_AwardDKP_FrameSubCaptainLabel:GetText() or "", 0.7, 0.85, 1, true);
    end
    -- Vanilla 的提示文字支持固定宽度后自动换行；Show 按文字高度排版。
    for i = 1, tip:NumLines() do
        local line = getglobal("ADKP_HelpTooltipTextLeft" .. i);
        if line then line:SetWidth(260); line:SetJustifyH("LEFT"); end
    end
    tip:Show();
    tip:SetWidth(284); -- 正文 260，加左右各 12 像素内边距。
end

-- ================================
-- 鼠标离开时隐藏帮助（OnLeave）
-- ================================
function ADKP_Help_Hide()
    if ADKP_HelpTooltip then ADKP_HelpTooltip:Hide(); end
end

-- ================================
-- 把 OnEnter/OnLeave 挂到文案表里列出的每个勾选框
-- 仅遍历 ADKP_HelpText，因此表里有几个键就注册几个，全自动。
-- 设了 hidden = true 的条目会被跳过（保留文案但不接管，悬停无 tooltip）。
-- ================================
function ADKP_Help_RegisterAll()
    for key, entry in pairs(ADKP_HelpText) do
        if not entry.hidden then
            local f = getglobal(key);
            if f then
                f:SetScript("OnEnter", ADKP_Help_Show);
                f:SetScript("OnLeave", ADKP_Help_Hide);
            end
        end
    end
end

-- ================================
-- 自举：等本插件的勾选框都已创建后注册一次。
-- 不依赖 addon 文件夹名（用户改文件夹名也不会失效）：
-- 只要某个已知勾选框已作为全局存在，就说明本插件已加载完毕。
-- 注册成功后立刻注销事件，只跑一次。
-- ================================
function ADKP_Help_OnEvent()
    if getglobal("ADKP_AwardDKP_FrameToggleSilentMode") then
        ADKP_Help_RegisterAll();
        ADKP_HelpBootFrame:UnregisterEvent("ADDON_LOADED");
    end
end
ADKP_HelpBootFrame = CreateFrame("Frame");
ADKP_HelpBootFrame:RegisterEvent("ADDON_LOADED");
ADKP_HelpBootFrame:SetScript("OnEvent", ADKP_Help_OnEvent);
