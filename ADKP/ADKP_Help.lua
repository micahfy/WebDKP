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
    ["ADKP_AwardDKP_FrameSubCaptainChk"] = {
        zh = { "替补队长加分",
               "勾选后，给主团加分时一并把替补队长计入奖励名单。" },
        en = { "Include Sub Captain",
               "When checked, the substitute-team captain is included when awarding DKP to the main raid." },
        hidden = false,
    },
    ["ADKP_AwardDKP_FrameSubHalfChk"] = {
        zh = { "替补团半分",
               "勾选后，替补团员获得的 DKP 为主团的一半。" },
        en = { "Subs Get Half",
               "When checked, substitute members receive half the DKP of the main raid." },
        hidden = false,
    },
    ["ADKP_AwardDKP_FrameToggleAutoAward"] = {
        zh = { "击杀自动加分弹窗",
               "击杀 Boss 后自动弹出加分窗口，便于快速给全团发放击杀分。" },
        en = { "Auto-Award on Kill",
               "Automatically pops up the award window after a boss kill, so you can quickly grant kill DKP to the raid." },
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
    ["ADKP_AwardDKP_FrameToggleKeepOnline"] = {
        zh = { "保持在线（挂机模式）",
               "自动取消登出，防止挂机时被踢出游戏。需要在非主城或者旅店才能生效" },
        en = { "Keep Online (Anti-Idle)",
               "Prevents being logged out when AFK. Only works when not in a city or inn." },
        hidden = false,
    },
    ["ADKP_AwardDKP_FrameToggleAutofill"] = {
        zh = { "自动填充物品/分数",
               "加分或发装备时，根据掉落表自动填入物品名称与建议分数。" },
        en = { "Auto-Fill Item/Cost",
               "When awarding, automatically fills in the item name and suggested cost from the loot table." },
        hidden = false,
    },
    ["ADKP_AwardDKP_FrameToggleZeroSum"] = {
        zh = { "零和规则",
               "装备花费将平均分摊给所有在场团员作为奖励。" },
        en = { "Zero-Sum Rule",
               "An item's cost is split equally among all present members as DKP awards." },
        hidden = false,
    },
    ["ADKP_AwardDKP_FrameToggleQuickFloatEnabled"] = {
        zh = { "启用快捷悬浮窗",
               "显示含集合/击杀/解散/调整等快捷按钮的侧边悬浮窗（仅在团队内显示）。" },
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
               "显示含集合/击杀/解散/调整等快捷按钮的侧边悬浮窗（仅在团队内显示）。" },
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
    ["ADKP_Personal_FrameSubHalfPoints"] = {
        zh = { "替补半分",
               "勾选后，替补团员获得的 DKP 为主团的一半。" },
        en = { "Subs Get Half",
               "When checked, substitute members receive half the DKP of the main raid." },
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
-- 风格对齐 ADKP_QuickFloat_ShowMainTooltip：
--   标题白 (1,1,1)，正文浅灰 (0.8,0.8,0.8)，锚点 ANCHOR_RIGHT
-- ================================
function ADKP_Help_Show()
    if not GameTooltip then return end
    local entry = ADKP_HelpText[this:GetName()];
    if not entry then return end
    local t = entry[ADKP_Help_GetLang()] or entry["zh"] or entry["en"];
    if not t then return end
    GameTooltip:SetOwner(this, "ANCHOR_RIGHT");
    GameTooltip:SetText(t[1] or "", 1, 1, 1);
    for i = 2, table.getn(t) do
        GameTooltip:AddLine(t[i], 0.8, 0.8, 0.8);
    end
    GameTooltip:Show();
end

-- ================================
-- 鼠标离开时隐藏帮助（OnLeave）
-- ================================
function ADKP_Help_Hide()
    if GameTooltip then
        GameTooltip:Hide();
    end
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
