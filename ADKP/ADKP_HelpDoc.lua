
ADKP_HelpDocSections = {

    {
        title = "简介与特色",
        collapsed = false,
        lines = {
            "本插件基于 WebDKP 调整了界面并做了大量精简和功能优化，用于在游戏内记录与管理团队的 DKP。",
            "特色：",
            "1. 自动备份：游戏崩溃也不会丢失数据（需要 SuperWOW）。",
            "2. 替补团队数据同步：同工会走插件频道同步，跨工会走密语同步。",
            "3. 悬浮窗：一键加集合分、解散分、击杀分。",
            "4. 拾取窗口：打开后可一键拍卖本次掉落的全部装备。",
            "5. 拍卖队列：拍完一件自动接着拍下一件，无需重新发起。",
            "6. 替补队长挂机：为替补队长提供防掉线挂机功能。",
            "7. 匿名拍卖：支持隐藏出分者身份的拍卖模式。",
            "8. 数据列表：可修改分值、原因、成员等记录。",
        },
    },

    {
        title = "标准使用流程",
        collapsed = false,
        lines = {
            "1. 从 DKP 网站下载全员的 DKP 数据，打开并复制数据到剪贴板。",
            "2. 在主界面「导入初始分」中粘贴并导入全部数据。",
            "3. 正常开展活动，记录集合分、击杀分、解散分，以及装备竞拍的分值。",
            "4. 导出当前记录，复制粘贴到网站的数据导入；或在网站上导入 SavedVariable 里的 WebDKP.lua。",
            "提示：在游戏内输入 /adkp 可随时呼出本主界面。",
        },
    },

    {
        title = "悬浮窗快捷键",
        collapsed = true,
        lines = {
            "悬浮窗仅在团队内显示，含以下快捷按钮（右键通常可自定义分值）：",
            "集 ：为主团、替补团分配集合分；右键可自定义分值。",
            "散 ：为主团、替补团分配解散分；右键可自定义分值。",
            "杀 ：手动录入 Boss 击杀得分；右键预设分值，使用前需选中已击杀 Boss 为目标。",
            "调 ：调整选中玩家的分数；右键设置数值（正数加分、负数扣分），未填原因时默认备注「犯错」。",
            "拍 ：将本次所有拾取物品批量提交至竞拍队列，打开拾取列表后点击，按顺序开展竞拍。",
        },
    },

    {
        title = "拍卖与匿名拍卖",
        collapsed = true,
        lines = {
            "启动拍卖：使用·或者`+物品链接1+物品链接2+...`·的方式在团队频道发起拍卖。",
            "         当一次性发起多件物品的拍卖时，插件会自动将物品按顺序加入竞拍队列。",
            "         ·或者`为键盘tab键上方的的按键，中英文皆支持。",
            "一键拍卖：打开拾取窗口后，可将本次掉落的全部装备批量加入队列。",
            "公开拍卖：所有人的出分将公开显示在竞拍列表中。",
            "匿名拍卖：出分者M语出分，超分等提示只通过密语发给当事人，不在团队频道泄露出分人。",
            "模式切换：在「设置」页或竞拍窗口内的「公开拍卖 / 匿名拍卖」勾选框切换。",

        },
    },

    {
        title = "替补团数据同步",
        collapsed = true,
        lines = {
            "填写替补队长后，替补队长在线且安装了本插件的情况下，会自动在加分时获取最新的替补团数据。",
            "同工会：通过插件频道自动同步替补团队数据。",
            "跨工会：通过密语自动同步替补团队数据。",
            "替补半分：在「设置」页勾选「替补团半分」，替补团员获得主团一半的 DKP。",
            "替补队长加分：勾选后给主团加分时一并把替补队长计入奖励名单。",
        },
    },

    {
        title = "常见问题与数据安全",
        collapsed = true,
        lines = {
            "数据安全：开启自动备份后，即使游戏崩溃也不会丢失数据（需安装 SuperWOW）。",
            "查询 DKP：在「设置」页开启「允许团员查询 DKP」后，团员密语「dkp」查询自己，或「dkp 名字」查询他人。",
            "保存文件：遇到报错或数据异常时，可点击左下「保存文件」重载。",
            "静默模式：开启「全局静默模式」后，所有播报只在本地聊天框显示，不再发送到频道。",
            "挂机模式：「保持在线」可防止挂机被踢，需在非主城、非旅店才生效。",
        },
    },
}

-- ================================
-- 布局常量
-- ================================
ADKP_HELPDOC_PADDING_LEFT   = 18;   -- 正文左缩进
ADKP_HELPDOC_PADDING_RIGHT  = 18;   -- 正文右缩进
ADKP_HELPDOC_TITLE_HEIGHT   = 24;   -- 标题按钮高度
ADKP_HELPDOC_LINE_HEIGHT    = 16;   -- 单行正文基础高度（实际会按断行重算）
ADKP_HELPDOC_SECTION_GAP    = 8;    -- 段落间距
ADKP_HELPDOC_BODY_TOP_GAP   = 4;    -- 标题与正文之间的间距

-- ================================
-- 创建可折叠帮助面板（懒加载）
-- 容器复用 XML 全局 ADKP_Options_Frame
-- ================================
function ADKP_CreateHelpPanel()
    local parent = getglobal("ADKP_Options_Frame");
    if not parent then return end
    if ADKP_HelpPanel then return end

    local panel = CreateFrame("Frame", "ADKP_HelpPanel", parent);
    panel:SetAllPoints();                       -- 填满 ADKP_Options_Frame
    ADKP_HelpPanel = panel;

    -- 计算正文区可用宽度（用于断行 + 计算展开高度）
    -- parent 宽 405，减去左右内边距(Backdrop insets 5+5) 与 本面板左右 padding
    panel.bodyWidth = parent:GetWidth() - 10 - ADKP_HELPDOC_PADDING_LEFT - ADKP_HELPDOC_PADDING_RIGHT;

    -- 滚动容器（参照 ADKP.lua Boss 名单的 UIPanelScrollFrameTemplate 写法）
    panel.scroll = CreateFrame("ScrollFrame", "ADKP_HelpPanelScroll", panel, "UIPanelScrollFrameTemplate");
    panel.scroll:SetPoint("TOPLEFT",  panel, "TOPLEFT",  6, -30);   -- 留出顶部"帮助说明"标题
    panel.scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -28, 8);

    -- 变高 ScrollChild：折叠/展开后用 SetHeight 重算
    panel.child = CreateFrame("Frame", nil, panel.scroll);
    panel.child:SetWidth(panel.bodyWidth);
    panel.child:SetHeight(1);
    panel.scroll:SetScrollChild(panel.child);

    -- 为每段创建 标题按钮 + 正文 FontString 组
    panel.sections = {};
    local n = table.getn(ADKP_HelpDocSections);
    for i = 1, n do
        local data = ADKP_HelpDocSections[i];

        -- 标题按钮（可点击区域，叠一个独立左对齐文字层显示标题）
        local btn = CreateFrame("Button", nil, panel.child);
        btn:SetWidth(panel.bodyWidth);
        btn:SetHeight(ADKP_HELPDOC_TITLE_HEIGHT);
        btn.idx = i;
        btn:SetHighlightTexture("Interface\\FriendsFrame\\UI-FriendsFrame-HighlightBar", "ADD");
        -- 独立文字层：左对齐，金黄标题色（|cffffd200 = RGB(1,0.82,0)）
        btn.label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal");
        btn.label:SetAllPoints();
        btn.label:SetJustifyH("LEFT");
        btn.label:SetJustifyV("MIDDLE");
        btn:SetScript("OnClick", function()
            local d = ADKP_HelpDocSections[this.idx];
            d.collapsed = (not d.collapsed);
            ADKP_RefreshHelpPanel();
        end);

        -- 正文区：每行一个 FontString（自动断行）
        local bodyLines = {};
        local lineCount = table.getn(data.lines);
        for j = 1, lineCount do
            local fs = panel.child:CreateFontString(nil, "OVERLAY", "GameFontNormal");
            fs:SetWidth(panel.bodyWidth);          -- 定宽 → WoW 据此自动断行（中文友好）
            fs:SetJustifyH("LEFT");
            fs:SetJustifyV("TOP");
            fs:SetTextColor(0.85, 0.85, 0.85);     -- 正文浅灰
            fs:SetText(data.lines[j]);
            bodyLines[j] = fs;
        end

        panel.sections[i] = { button = btn, lines = bodyLines };
    end

    ADKP_RefreshHelpPanel();
end

-- ================================
-- 刷新帮助面板：重算显隐 + 布局 + ScrollChild 总高度
-- 折叠/展开切换、首次创建后都会调用
-- ================================
function ADKP_RefreshHelpPanel()
    local panel = ADKP_HelpPanel;
    if not panel then return end

    local child = panel.child;
    local xLeft = ADKP_HELPDOC_PADDING_LEFT;
    local yCursor = 0;                  -- 向下为负
    local totalHeight = 0;

    local n = table.getn(panel.sections);
    for i = 1, n do
        local sec = panel.sections[i];
        local data = ADKP_HelpDocSections[i];

        -- 标题按钮文字（金黄标题色 |cffffd200 = RGB(1,0.82,0)，与悬浮窗帮助窗一致）
        local prefix = data.collapsed and "[+] " or "[-] ";
        sec.button.label:SetText("|cffffd200" .. prefix .. data.title .. "|r");
        sec.button:ClearAllPoints();
        sec.button:SetPoint("TOPLEFT", child, "TOPLEFT", xLeft, yCursor);
        yCursor = yCursor - ADKP_HELPDOC_TITLE_HEIGHT;
        totalHeight = totalHeight + ADKP_HELPDOC_TITLE_HEIGHT;

        -- 正文行
        if data.collapsed then
            for j = 1, table.getn(sec.lines) do
                sec.lines[j]:Hide();
            end
        else
            yCursor = yCursor - ADKP_HELPDOC_BODY_TOP_GAP;
            totalHeight = totalHeight + ADKP_HELPDOC_BODY_TOP_GAP;
            for j = 1, table.getn(sec.lines) do
                local fs = sec.lines[j];
                fs:ClearAllPoints();
                fs:SetPoint("TOPLEFT", child, "TOPLEFT", xLeft, yCursor);
                fs:Show();
                local natW = fs:GetStringWidth() or panel.bodyWidth;
                local lines = 1;
                if natW > panel.bodyWidth then
                    lines = math.floor((natW + panel.bodyWidth - 1) / panel.bodyWidth);
                end
                -- 行间留 2px
                local lineH = lines * ADKP_HELPDOC_LINE_HEIGHT + 2;
                yCursor = yCursor - lineH;
                totalHeight = totalHeight + lineH;
            end
        end

        -- 段落间距
        yCursor = yCursor - ADKP_HELPDOC_SECTION_GAP;
        totalHeight = totalHeight + ADKP_HELPDOC_SECTION_GAP;
    end

    -- 重算 ScrollChild 高度，触发滚动条更新
    if totalHeight < 1 then totalHeight = 1; end
    child:SetHeight(totalHeight);
end
