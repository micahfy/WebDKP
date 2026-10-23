-- ==========================================
-- ADKP 团队副本与BOSS内嵌名单 (含自定义副本)
-- 名称同时用于中英文识别；组合首领只占一个名单项。
-- ==========================================

ADKP_RaidBosses = {
    -- 熔火之心 (Molten Core)
    ["Molten Core"] = {
        name_zh = "熔火之心",
        bosses = {
            { en = "Lucifron", zh = "鲁西弗隆" },
            { en = "Magmadar", zh = "玛格曼达" },
            { en = "Incindis", zh = "因辛迪斯" },
            { en = "Gehennas", zh = "基赫纳斯" },
            { en = "Garr", zh = "加尔" },
            { en = "Baron Geddon", zh = "迦顿男爵" },
            { en = "Shazzrah", zh = "沙斯拉尔" },
            { en = "Sorcerer-Thane Thaurissan", zh = "法师领主索瑞森" },
            { en = "Sulfuron Harbinger", zh = "萨弗隆先驱者" },
            { en = "Golemagg the Incinerator", zh = "焚化者古雷曼格" },
            { en = "Twin Golems", zh = "双子傀儡", rule = "any", waitCombat = true,
                members = {
                    { en = "Smoldaris", zh = "斯摩达利斯", aliases = { "Smolderas" } },
                    { en = "Basalthar", zh = "巴萨尔萨" },
                } },
            { en = "Majordomo Executus", zh = "管理者埃克索图斯", rule = "count", waitCombat = true,
                members = {
                    { en = "Flamewaker Elite", zh = "烈焰行者精英", count = 4 },
                    { en = "Flamewaker Healer", zh = "烈焰行者医师", count = 4 },
                } },
            { en = "Ragnaros", zh = "拉格纳罗斯" },
        }
    },
    -- 奥妮克希亚的巢穴 (Onyxia's Lair)
    ["Onyxia's Lair"] = {
        name_zh = "奥妮克希亚的巢穴",
        bosses = {
            { en = "Broodcommander Axelus", zh = "巢穴指挥官阿克塞勒斯" },
            { en = "Onyxia", zh = "奥妮克希亚" },
        }
    },
    -- 黑翼之巢 (Blackwing Lair)
    ["Blackwing Lair"] = {
        name_zh = "黑翼之巢",
        bosses = {
            { en = "Razorgore the Untamed", zh = "狂野的拉佐格尔" },
            { en = "Vaelastrasz the Corrupt", zh = "堕落的瓦拉斯塔兹" },
            { en = "Broodlord Lashlayer", zh = "勒什雷尔" },
            { en = "Firemaw", zh = "费尔默" },
            { en = "Ebonroc", zh = "埃博诺克" },
            { en = "Flamegor", zh = "弗莱格尔" },
            { en = "Ezzel Darkbrewer", zh = "伊泽尔·黑酿" },
            { en = "Chromaggus", zh = "克洛玛古斯" },
            { en = "Nefarian", zh = "奈法利安" },
        }
    },
    -- 祖尔格拉布 (Zul'Gurub)
    ["Zul'Gurub"] = {
        name_zh = "祖尔格拉布",
        bosses = {
            { en = "High Priest Venoxis", zh = "高阶祭司温诺希斯" },
            { en = "High Priestess Jeklik", zh = "高阶祭司耶克里克" },
            { en = "High Priestess Mar'li", zh = "高阶祭司玛尔里" },
            { en = "High Priest Thekal", zh = "高阶祭司塞卡尔" },
            { en = "High Priestess Arlokk", zh = "高阶祭司阿罗克" },
            { en = "Bloodlord Mandokir", zh = "血领主曼多基尔" },
            { en = "Jin'do the Hexxer", zh = "妖术师金度" },
            { en = "Gahz'ranka", zh = "加兹兰卡" },
            { en = "Hakkar", zh = "哈卡" },
            { en = "Gri'lek", zh = "格里雷克" },
            { en = "Hazza'rah", zh = "哈扎拉尔" },
            { en = "Renataki", zh = "雷纳塔基" },
            { en = "Wushoolay", zh = "乌苏雷" },
        }
    },
    -- 安其拉废墟 (Ruins of Ahn'Qiraj)
    ["Ruins of Ahn'Qiraj"] = {
        name_zh = "安其拉废墟",
        bosses = {
            { en = "Kurinnaxx", zh = "库林纳克斯" },
            { en = "General Rajaxx", zh = "拉贾克斯将军" },
            { en = "Moam", zh = "莫阿姆" },
            { en = "Buru the Gorger", zh = "吞咽者布鲁" },
            { en = "Ayamiss the Hunter", zh = "狩猎者阿亚米斯" },
            { en = "Ossirian the Unscarred", zh = "无疤者奥斯里安", aliases = { "无伤者奥西里安" } },
        }
    },
    -- 安其拉神殿 (Temple of Ahn'Qiraj)
    ["Temple of Ahn'Qiraj"] = {
        name_zh = "安其拉神殿",
        bosses = {
            { en = "The Prophet Skeram", zh = "预言者斯克拉姆" },
            { en = "Battleguard Sartura", zh = "战争守卫沙尔图拉" },
            { en = "Fankriss the Unyielding", zh = "顽强的范克瑞斯" },
            { en = "Princess Huhuran", zh = "哈霍兰公主" },
            { en = "The Twin Emperors", zh = "双子皇帝", aliases = { "Twin Emperors" }, rule = "any", waitCombat = true,
                members = {
                    { en = "Emperor Vek'nilash", zh = "维克尼拉斯大帝", aliases = { "Vek'nilash" } },
                    { en = "Emperor Vek'lor", zh = "维克洛尔大帝", aliases = { "Vek'lor" } },
                } },
            { en = "Ouro", zh = "奥罗" },
            { en = "C'Thun", zh = "克苏恩" },
            { en = "Viscidus", zh = "维希度斯" },
            { en = "The Bug Trio", zh = "安其拉三宝", rule = "all", waitCombat = true,
                members = {
                    { en = "Vem", zh = "维姆", aliases = { "温姆" } },
                    { en = "Lord Kri", zh = "克里勋爵" },
                    { en = "Princess Yauj", zh = "亚尔基公主" },
                } },
        }
    },
    -- 纳克萨玛斯 (Naxxramas)
    ["Naxxramas"] = {
        name_zh = "纳克萨玛斯",
        bosses = {
            { en = "Anub'Rekhan", zh = "阿努布雷坎" },
            { en = "Grand Widow Faerlina", zh = "黑女巫法琳娜", aliases = { "大黑女巫法琳娜" } },
            { en = "Maexxna", zh = "迈克斯纳" },
            { en = "Noth the Plaguebringer", zh = "瘟疫使者诺斯" },
            { en = "Heigan the Unclean", zh = "肮脏的希尔盖" },
            { en = "Loatheb", zh = "洛欧塞布" },
            { en = "Instructor Razuvious", zh = "教官拉苏维奥斯", aliases = { "讲师拉苏维奥斯" } },
            { en = "Gothik the Harvester", zh = "收割者戈提克" },
            { en = "The Four Horsemen", zh = "天启四骑士", rule = "all", waitCombat = true,
                members = {
                    { en = "Highlord Mograine", zh = "大领主莫格莱尼", aliases = { "莫格莱尼大领主" } },
                    { en = "Thane Korth'azz", zh = "库尔塔兹领主" },
                    { en = "Lady Blaumeux", zh = "女公爵布劳缪克丝" },
                    { en = "Sir Zeliek", zh = "瑟里耶克爵士" },
                } },
            { en = "Patchwerk", zh = "帕奇维克" },
            { en = "Grobbulus", zh = "格罗布鲁斯" },
            { en = "Gluth", zh = "格拉斯" },
            { en = "Thaddius", zh = "塔迪乌斯" },
            { en = "Sapphiron", zh = "萨菲隆" },
            { en = "Kel'Thuzad", zh = "克尔苏加德" },
        }
    },
    -- 卡拉赞下层 (Lower Karazhan - 10人团队副本)
    ["Lower Karazhan"] = {
        name_zh = "卡拉赞下层",
        bosses = {
            { en = "Master Blacksmith Rolfen", zh = "锻造大师罗尔芬" },
            { en = "Brood Queen Araxxna", zh = "巢穴女王阿拉克萨娜" },
            { en = "Grizikil", zh = "格里齐基尔" },
            { en = "Clawlord Howlfang", zh = "爪王嚎牙" },
            { en = "Lord Blackwald II", zh = "布莱克沃尔德勋爵二世" },
            { en = "Moroes", zh = "莫罗斯" },
        }
    },
    -- 卡拉赞上层 (Upper Karazhan - 40人团队副本)
    ["Upper Karazhan"] = {
        name_zh = "卡拉赞上层",
        zoneAliases = { "Tower of Karazhan", "卡拉赞之塔", "卡拉赞", "The Rock of Desolation", "荒芜巨岩", "Outland", "外域" },
        bosses = {
            { en = "King", zh = "国王", aliases = { "King (Chess fight)", "国王议会" } },
            { en = "Sanv Tas'dal", zh = "桑夫·塔斯达尔" },
            { en = "Kruul", zh = "库鲁尔" },
            { en = "Ley-Watcher Incantagos", zh = "魔网观察者因塔苟斯" },
            { en = "Anomalus", zh = "阿诺玛鲁斯" },
            { en = "Echo of Medivh", zh = "麦迪文的回响" },
            { en = "Keeper Gnarlmoon", zh = "守护者纳尔穆恩" },
            { en = "Rupturan the Broken", zh = "破碎者鲁普图兰", rule = "yell", waitCombat = true,
                yells = { "化为尘土", "Perished... To dust" } },
            { en = "Mephistroth", zh = "孟菲斯托斯" },
        }
    },
    -- 翡翠圣殿 (Emerald Sanctum)
    ["Emerald Sanctum"] = {
        name_zh = "翡翠圣殿",
        bosses = {
            { en = "Erennius", zh = "埃伦纽斯" },
            { en = "Solnius", zh = "索尔纽斯", aliases = { "Solnius the Awakener" } },
        }
    },
    -- 木喉要塞 (Timbermaw Hold - 20人团队副本，乌龟服 1.18.1)
    ["Timbermaw Hold"] = {
        name_zh = "木喉要塞",
        bosses = {
            { en = "Karrsh the Sentinel", zh = "哨兵卡什" },
            { en = "Rotgrowl", zh = "腐嚎" },
            { en = "Ormanos the Cracked", zh = "裂地者欧曼诺斯" },
            { en = "Archdruid Kronn", zh = "大德鲁伊科罗恩" },
            { en = "Loktanag the Vile", zh = "落潭" },
            { en = "Trioch the Devourer", zh = "吞噬者提里奥克" },
            { en = "Selenaxx Foulheart", zh = "塞雷纳克斯·腐心" },
            { en = "Chieftain Partath", zh = "大酋长帕萨斯" },
            { en = "Ursol", zh = "乌索尔" },
            { en = "Peroth'arn", zh = "佩罗萨恩" },
        }
    },
    -- 世界首领 (World Bosses)
    ["World Bosses"] = {
        name_zh = "世界首领",
        bosses = {
            { en = "Azuregos", zh = "艾瑟雷戈斯" },
            { en = "Lord Kazzak", zh = "领主卡扎克" },
            { en = "Ysondre", zh = "伊森德雷" },
            { en = "Taerar", zh = "泰拉尔" },
            { en = "Emeriss", zh = "艾莫莉丝" },
            { en = "Lethon", zh = "雷索" },
            { en = "Ostorius", zh = "奥斯托留斯" },
        }
    }
}
