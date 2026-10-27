# ADKP 无限原版移植 · v1.0F

开发范围：仅面向当前无限客户端，不要求兼容 1.12、海龟服、旧客户端或旧插件版本。后续修改优先使用当前客户端的原生接口与其支持的 Lua 语法，不为旧版保留兼容分支。原版主体功能和整体界面继续保留，双名中的空格继续按完整身份处理；第三方客户端模组依赖及相应功能继续移除。当前复制代码仍依赖的适配层按调用关系逐步替换。

源码主目录统一为仓库中的 `ADKP_Forever_Classic/ADKP/`，安装包顶层为 `ADKP/`，对应清单 `ADKP.toc`。适配层从客户端取得实际插件目录名，冲突检测排除自身；原生 `ADDON_LOADED` 事件、贴图目录、测试入口及安装说明保持一致。后续修复以此目录为准。此调整将客户端保存文件名统一为 `ADKP.lua`；原来以 `ADKP_Forever_Classic` 目录安装的账本不会自动转移，沿用数据的方法见下方安装说明。

本轮修复“已扣分但装备没有分配”的两处缺陷：开拍时保存原始完整物品链接，授予和交付沿用同一链接，不再仅凭物品名重新查询，也不会使用查询结果替换原始物品变体；原生分配候选人按客户端的 `MAX_RAID_MEMBERS` 范围扫描，不再受当前团队人数截断。对于只有物品名的未分配条目，重试时可从当前掉落窗口恢复唯一匹配的完整链接；同名不同物品不猜测匹配。重试不重复记账或扣分。

拍卖品质筛选与队伍分配阈值分别处理：保留白色、绿色等已选品质的拍卖和记账；实际分配前读取 `GetLootThreshold()` 并与掉落槽第 5 个返回值的品质比较。低于实际阈值时提示“低于分配阈值”，需要拾取后交易，不擅自修改队伍拾取设置。绿色物品仍可能因链接、候选人或原生调用失败而无法分配，不能一概归因为白色物品限制。完整失败原因会写入聊天，并在未分配条目的悬停提示中显示；`/adkp diag` 增加分配权限、实际品质阈值和最近未交付原因。

27 项离线场景通过，包括绿色装备停拍后授予、缺失名称查询、原始链接变体保留、较后候选人索引、双名回执、旧条目重试不重复扣分、白色低于阈值和同名不同物品拒绝匹配；原界面尺寸和锚点检查通过。实际物品交付仍需客户端验证。当前未分配列表是会话数据，安装更新并重载前请先处理已扣分的旧条目；勿重新授予导致重复扣分。

接口依据：[原生分配候选人扫描与调用](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_UIPanels_Game/Mainline/GroupLootFrame.lua)、[原生拾取品质阈值菜单](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_UnitPopupShared/UnitPopupSharedButtonMixins.lua)。

本次修复悬浮窗“集／杀／散”右键分值设置中的输入框不可见：动态创建的旧输入框模板与现代 BackdropTemplate 组合时，后一个 OnLoad 可能覆盖输入框的样式初始化。私有创建适配器现于原生创建结束后补做输入框背景、边框和文字内边距初始化，沿用已有配色。主团分、替补分和击杀原因输入框的位置、尺寸、保存和回填规则保持不变；同类动态输入框也使用相同修复。通过真实右键入口核对样式描述和分值保存／回填，实际客户端贴图效果仍需实机确认。

本次修复悬浮窗“拍”的外观和一键品质筛选：现代 `UIPanelButtonTemplate` 使用 Left／Middle／Right 三片背景，原来只替换 NormalTexture 会留下红底。现直接更新三片背景，并在原生显示、松开鼠标和启用回调后恢复颜色。空闲时保持灰色白字，打开拾取列表后为红色黄字，竞拍中维持亮色返回状态；灰色时仍可左键设置品质、右键打开竞拍，窗口和按钮尺寸不变。

`GetLootSlotInfo` 的第 4 个返回值是货币 ID，第 5 个才是品质。批量竞拍现读取正确字段并沿用保存的品质复选框设置，不再将白色、绿色物品错误筛除。新增通过真实品质复选框和悬浮窗点击的回归，验证全选时白色、绿色均进入拍卖／队列，取消白色后只拍绿色；共 25 项离线场景通过，实际客户端贴图效果仍需实机确认。

接口依据：[无限客户端拾取窗口](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_UIPanels_Game/Mainline/LootFrame.lua)、[原生按钮背景及回调](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_SharedXML/SecureUIPanelTemplates.lua)。

本次修复名单悬浮报错：现代 `OnEnter` 的 `motion` 参数为布尔值，不能将旧上下文中的 `arg1` 当作框体。名单和竞拍行的 XML 回调显式传入 `self`；悬浮处理统一读取原始完整姓名，避免显示用的 `·` 影响账本查找。竞拍悬浮按数值比较出分，保留已选中行的背景色。新增真实 XML 移入／移出回调的 `true`、`false` 和省略参数检查，覆盖完整姓名提示及选中高亮，共 24 项离线场景通过。界面尺寸和布局保持不变。

本次修复登录时 Boss 加分弹窗的锚点错误：“替补”标签在图层创建阶段引用了稍后才创建的主团输入框。改为锚定前面已创建的“主团”标签，使用等效偏移 `8 + 60 + 20 = 88`，保留原控件位置和弹窗尺寸。XML 检查改为在每个控件创建时验证锚点目标，避免最终名称存在却在创建时不可用的漏检。

本次修复授予物品时 `GetLootMethod` 不存在的错误：私有适配器优先调用 `C_PartyInfo.GetLootMethod`，将 `Enum.LootMethod` 转为旧业务值，并完整处理队伍索引、团队索引及当前分配者身份。授予、流拍分配和团队查分中的旧调用均已替换；查询或分配接口不可用时保留装备记录，进入未交付流程。

同一件竞拍装备记账后不再允许重复记账，未交付重试只重试分配。分配接口明确返回失败时立即转未交付。拾取回执保留完整双名和内部空格，移除旧的姓名字节长度检查，并同时匹配玩家与完整物品标识，避免相同显示名的另一件物品被误认为交付成功。

新增回归覆盖：旧全局接口不存在、现代拾取枚举、只返回团队分配者索引、缺失／受限／报错的查询接口、实际授予按钮到分配调用、双名回执、重复点击、分配返回失败和未交付重试。共 23 项离线场景通过；真实服务器的受保护分配操作仍需实机验证。此前发生错误的授予可能已经扣分，应先核对装备记录再决定是否重新记账。

接口依据：[拾取方式及分配者索引](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/PartyInfoDocumentation.lua)、[拾取方式枚举](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/LootConstantsDocumentation.lua)。

本次依据客户端实际错误修复启动中断：移除顶层 `math.randomseed` 调用，使用游戏已有随机数生成器。该接口缺失会中断 `Bidding.lua` 的后半段，导致收价、停止、流拍、授予和匿名计时函数没有完成定义，也会使开拍在显示窗口前中断；此前 `.2` 和 `.3` 都存在这个根因。

旧 `ADKPEditBoxTemplate` 改为继承私有初始化 mixin，所有实例在自身 `OnLoad` 开始时初始化现代 Backdrop。这样即使实例覆盖模板的 `OnLoad`，竞拍物品、时间、授予价格等输入框也具有背景接口和原配色；共覆盖 19 个旧模板输入框。自用页快捷浮窗选项改为锚定实际存在的“替补队长加分”选项，修复对不存在的导入按钮的引用。

模拟环境已明确移除 `math.randomseed`，未初始化的控件不再自动获得假的 Backdrop 方法，并新增 XML 锚点名称检查。先复现上述加载错误，再通过 21 项场景、98 处锚点引用及完整竞拍入口回归。真实客户端聊天、点击和拾取仍需复测；本包包含 `.3` 的全部入口适配，可直接从 `.2` 升级。

此前补齐的竞拍入口适配继续保留：监听小队队长频道；正文和作者可读时，无关的受限聊天附加字段不再导致整条消息丢弃，这些字段会被移除，受限正文／作者仍不处理。通过消息 GUID 对照当前队伍完整姓名，无法匹配时保留原始姓名边界。开始／停止、流拍和授予按钮在 XML 加载后绑定原生点击回调，继续调用原业务函数；流拍保留左键执行和右键菜单。

物品查询异常回退到输入文字，开拍／停拍状态和窗口先于通知更新，避免查询或通知失败留下误导的按钮状态。`/adkp diag` 新增真实竞拍状态及最近回调／物品查询错误，便于定位仍只在客户端出现的问题。离线新增聊天开拍弹窗、出价入表、按钮停止、流拍左右键、选人授予扣分、受限附加字段、小队队长频道和物品查询失败的完整入口测试；真实客户端点击、聊天权限及拾取分配仍需实机复测。

上一版已修复竞拍列表的 `asdf` 调试占位文字：空行默认隐藏，窗口打开时刷新真实出价，下一件装备开拍时清除上一件的行文字与姓名缓存。同步修正列表缩短后的滚动偏移，保持原窗口尺寸、锚点和 13 行可见容量。

这一版直接复制仓库 `ADKP/` 的 1.98 源码，再做无限客户端适配。它是新的移植基线，与此前独立重写的 `ADKP_Forever/` 分开维护。原版源目录和先前测试包均保留。

## 保留的原版内容

- 原版 XML 主窗口、分页、职业筛选、名单、单点奖惩、独立竞拍窗口与原贴图。
- 原版六键悬浮窗及其设置、主团与替补奖惩、集合／解散／击杀快捷操作。
- 普通团员密语查分和出价、明拍／匿名拍、拍卖队列、流拍处理。
- 装备记录、未交付记录、原版活动编辑与导出、初始分导入、大小号共享分数管理。
- `WebDKP_*` 与共享分数 SavedVariables，沿用原数据布局和网站格式。

## 已移除

客户端扩展文件读写、自动／手动文件备份、本地备份恢复和指定文件名导入、登录备份检查、保持在线、防挂机；对应 Lua 文件、界面入口和说明均已清理。按此前确认继续移除幻化拍卖、HH／Roll 登记和幻化授予入口。普通装备拍卖与流拍保留。

保存由游戏的 SavedVariables 机制完成。导入初始分和导出活动记录继续通过原来的文本窗口复制粘贴。

## 适配范围

- 清单为 `Interface: 16001`，对应已反馈的无限 `1.60.1.70450` 客户端。
- 在原源码文件内部使用私有接口适配器，不覆盖系统的 `UnitName`、`SendAddonMessage`、`ChatFrame_OnEvent` 或 `SetItemRef`。
- 旧 `this/event/arg1...` 回调通过可嵌套并在异常后恢复的兼容上下文执行。原版初始化在 `PLAYER_LOGIN`、所有模块和 XML 完成加载后执行一次。
- 背景转到现代 Backdrop，修正下拉菜单和滚动参数，原小地图按钮直接依附当前 Minimap。缺失的旧标签、复选框、输入框和滚动模板由 `ADKP_ForeverTemplates.xml` 提供私有实现；不依赖客户端重新提供已移除的旧模板。
- 原生 `NameUtil.GetUnmodifiedUnitFullName`／`GetUnitName(unit, true)` 获取完整双名。保留内部空格，不依据字数、语言或英文大小写猜测姓名边界。
- 名单与竞拍行用 `·` 标出空格位置，选择动作仍读取原始名字。例如 `张三·四` 与 `张·三四` 分别对应两个完整姓名。姓名输入框放开旧长度限制；编辑时填写真实空格。
- 命令中的双名使用引号，例如 `/adkp tj "张三 四" 战士 60`、`/adkpshare "主号 全名" "小号 全名"`。界面姓名输入框无需引号。
- 主团／替补奖惩、首次为新成员建账等继续执行原版实现，没有另造一套账本。
- 替补同步保留原采集、职业分组、分包、人数核对、缓存和奖惩消费者，改用 `C_ChatInfo.SendAddonMessage(..., "WHISPER", 完整名)`。加入请求编号、对端和团队检查及限流。普通聊天密语不再接收内部替补数据，不回退到普通密语或公会广播。
- 首领确认接入官方 `ENCOUNTER_START`／`ENCOUNTER_END`／`BOSS_KILL`，重复信号去重，继续使用原 Boss 分设置、确认弹窗、自动记录与奖惩队列。内置名单沿用原版，不据此声称所有原版／自定义首领都存在于无限；未知官方首领用默认分值，可在原界面添加自定义设置。
- 拾取使用按物品槽位查询候选人的接口；重复装备需要原生窗口明确选择。没有接口、权限或交付回执时继续放入未交付流程，不因调用返回就当成交付完成。

## 安装与首轮排错

1. 将仓库 `ADKP_Forever_Classic/` 内的 `ADKP` 文件夹，或安装包中的顶层 `ADKP` 文件夹，放入客户端 `Interface/AddOns/`，最终应为 `Interface/AddOns/ADKP/ADKP.toc`。
2. 启用 **ADKP 无限原版移植**。同一客户端中原版与无限版均使用 `ADKP` 目录；该目录只保留适合当前客户端的一版。若还存在旧的 `ADKP_Forever_Classic` 或 `ADKP_Forever` 目录，须禁用这些重复版本。
3. 此目录对应账号 `SavedVariables/ADKP.lua`。如果此前使用 `ADKP_Forever_Classic` 目录安装并已有账本，应先退出游戏、保留原保存文件，再将该账号下的 `SavedVariables/ADKP_Forever_Classic.lua` 复制为 `SavedVariables/ADKP.lua`；如目标文件已有数据，先另行保存目标文件再替换。已使用 `ADKP` 目录的客户端无需改名。插件不自动读取其他插件文件，也不迁移重写版的 `ADKP_ForeverDB` 任务状态。
4. `/adkp` 打开原主窗口；`/dkp` 为同义入口；`/adkp diag` 输出版本、完整双名、GUID 和本次会话通信验证状态。
5. 先验证手动添加、目标 `c` 调分、主团奖惩，再验证网站导入／导出、竞拍与队列、大小号、双方 `/subteam`、真实首领和拾取事件。

这是一版可供逐项客户端排错的原版移植测试包。离线模拟不能证明真实服务器 WHISPER、受保护操作、字体贴图或 SavedVariables 落盘行为；`/adkp diag` 只有在本次会话收到匹配完整名单后才显示通信已验证。

## 开发验证

发布时可双击仓库 `tools/package_forever_classic.cmd`，或在终端执行 `python tools/package_forever_classic.py`（需要 Python 3.8 及以上，无额外依赖）。脚本读取当前 `ADKP.toc` 的版本，在临时副本中移除 Lua 注释、XML 注释及 XML 事件脚本里的 Lua 注释，再压缩为安装包，保留顶层 `ADKP/`。开发源码不变；临时副本打包完成后自动清理。字符串中的注释符号、中文、贴图及 TOC 的 `##` 插件元数据保持不变。注释位置的空白与 Lua 换行保留，避免相邻代码粘连。

默认输出到仓库根目录，文件名示例为 `ADKP_Forever_Classic-v1.0F-20261026-020304.zip`，时间使用北京时间（UTC+8）。同一秒重复运行会追加序号，已有包不会覆盖。可用 `--output-dir D:\发布目录` 指定输出位置。

```powershell
python tests/run_forever_classic_tests.py --runtime-dir "$env:TEMP/adkp-forever-lua-runtime"
python -m unittest discover -s tests -p test_package_forever_classic.py -v
python tools/package_forever_classic.py
```

测试实际加载本包全部 Lua 和 XML 内嵌脚本，并执行原版入口。当前覆盖：完整启动、305 处原 XML 尺寸／锚点、目标调分与首次建账、中文空格边界、嵌套回调恢复、原悬浮窗、出价和队列、原分页、导入导出窗口、首领信号去重、槽位候选与等待回执，以及独立 Lua 客户端间的替补通信与缓存。模拟只用于验证插件逻辑。

`tools/clone_forever_classic.py` 记录了初次复制和机械转换过程；它不是运行依赖。后续修复可直接修改本目录。不要未经比对执行生成器 `--refresh`，该选项会从 `ADKP/` 重新生成原文件，覆盖其后修改；四个 `ADKP_Forever*.lua` 手写适配文件不会被覆盖。

接口依据：暴雪客户端源码镜像的 [完整姓名工具](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_FrameXMLUtil/Camelot/NameUtil.lua)、[ChatInfo](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/ChatInfoDocumentation.lua)、[官方遭遇战事件](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/EncounterInfoDocumentation.lua)、[Backdrop](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_SharedXML/Backdrop.lua)。
