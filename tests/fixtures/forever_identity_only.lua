-- Reproduce the reported saved state: full identities exist, DKP rows do not.
return {
    WebDKP_DkpTable = {},
    WebDKP_Log = {Version = 2},
    ADKP_ForeverDB = {
        schema = 1, revision = 2, sequence = 1, region = 5, tableID = 1,
        identity = {
            nextID = 2,
            guids = {["Player-6746-00387CF3"] = "p1", ["Player-6746-003C63AA"] = "p2"},
            names = {["加 百列"] = "p1", ["梦醒 融化如雪"] = "p2"},
            records = {
                p1 = {id = "p1", name = "加 百列", key = "加 百列", guid = "Player-6746-00387CF3"},
                p2 = {id = "p2", name = "梦醒 融化如雪", key = "梦醒 融化如雪", guid = "Player-6746-003C63AA"},
            },
        },
        awards = {
            ["award:1792924843:1"] = {
                id = "award:1792924843:1", reason = "击杀-巡山人巴恩", state = "ready",
                raidPoints = 1, subPoints = 1, main = {"加 百列", "梦醒 融化如雪"}, sub = {},
                tableID = 1, date = "2026-10-25 18:40:43", automatic = false,
            },
        },
    },
}
