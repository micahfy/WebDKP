local passed = 0
local function eq(actual, expected, why)
    assert(actual == expected, (why or "value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function count(list) local n = 0; for _ in ipairs(list) do n = n + 1 end; return n end
local function test(name, fn)
    fn(); passed = passed + 1; print("PASS " .. name)
end
local files = {"Core.lua", "Identity.lua", "Data.lua", "Roster.lua", "Comm.lua", "Chat.lua", "Groups.lua", "Awards.lua",
    "Loot.lua", "Bidding.lua", "Encounters.lua", "Classic.lua", "UI.lua", "Operations.lua", "Main.lua"}

local function widget()
    local w = { scripts = {}, shown = true, text = "", children = {}, points = {} }
    function w:SetScript(name, fn) self.scripts[name] = fn end
    function w:RegisterEvent(name) self.events = self.events or {}; self.events[name] = true end
    function w:UnregisterAllEvents() self.events = {} end
    function w:SetText(text)
        self.text = text
        if self.scripts.OnTextChanged then self.scripts.OnTextChanged(self) end
    end
    function w:GetText() return self.text end
    function w:Show() self.shown = true end
    function w:Hide() self.shown = false end
    function w:SetShown(state) self.shown = state end
    function w:IsShown() return self.shown end
    function w:CreateFontString() local child = widget(); table.insert(self.children, child); return child end
    function w:CreateTexture() local child = widget(); table.insert(self.children, child); return child end
    function w:SetSize(width, height) self.width, self.height = width, height end
    function w:SetPoint(...) table.insert(self.points, {...}) end
    function w:ClearAllPoints() self.points = {} end
    function w:GetPoint() return unpack(self.points[1] or {"CENTER", {}, "CENTER", 0, 0}) end
    function w:SetBackdrop(value) self.backdrop = value end
    function w:SetChecked(value) self.checked = value end
    function w:GetChecked() return self.checked end
    function w:SetEnabled(value) self.enabled = value end
    function w:GetStringHeight() return 340 end
    local noop = function() end
    for _, method in ipairs({"SetWidth", "SetHeight", "SetFontObject", "SetAutoFocus",
        "SetMaxLetters", "SetMultiLine", "SetFocus", "ClearFocus", "HighlightText", "SetFrameStrata",
        "SetMovable", "EnableMouse", "RegisterForDrag", "StartMoving", "StopMovingOrSizing", "SetJustifyH",
        "SetJustifyV", "SetSpacing", "SetScrollChild", "RegisterForClicks", "SetNormalTexture", "SetTexture",
        "SetAllPoints", "SetColorTexture", "EnableMouseWheel", "SetHighlightTexture", "SetWordWrap", "SetClampedToScreen"}) do w[method] = noop end
    return w
end

local function client(myName)
    local e = setmetatable({}, {__index = _G})
    e._G = e
    e.now, e.messages, e.sent, e.chat, e.frames = 0, {}, {}, {}, {}
    e.units = {player = {name = myName or "Leader One", guid = "Player-" .. (myName or "Leader One"), class = "WARRIOR"}}
    e.groupSize, e.raid, e.sendResult = 0, false, 0
    e.GetTime = function() return e.now end
    e.time = function() return 1800000000 end
    e.date = function(fmt, stamp) return os.date(fmt, stamp or 1800000000) end
    e.GetBuildInfo = function() return "1.60.1", "70450", "", 16001 end
    e.RegionalUniqueNamesEnabled = function() return true end
    e.GetCurrentRegion = function() return 5 end
    e.C_AddOns = {IsAddOnLoaded = function() return false end}
    e.GetUnitName = function(unit) return e.units[unit] and e.units[unit].name end
    -- Deliberately incompatible with traditional name/realm concatenation.
    e.UnitName = function() return "WrongFirst", "WrongSurname" end
    e.UnitFullName = function() return "WrongFirst", "WrongSurname" end
    e.UnitGUID = function(unit) return e.units[unit] and e.units[unit].guid end
    e.UnitExists = function(unit) return e.units[unit] ~= nil end
    e.UnitClass = function(unit) return "Warrior", e.units[unit] and e.units[unit].class end
    e.UnitIsPlayer = function() return true end
    e.GetNumGroupMembers = function() return e.groupSize end
    e.IsInRaid = function() return e.raid end
    e.UnitIsGroupLeader = function() return e.leader ~= false end
    e.UnitIsGroupAssistant = function() return e.assistant end
    e.issecretvalue = function(value) return type(value) == "table" and value.secret == true end
    e.Enum = {SendAddonMessageResult = {Success = 0}, RegisterAddonMessagePrefixResult = {Success = 0}}
    e.C_ChatInfo = {
        RegisterAddonMessagePrefix = function(prefix) e.registered = prefix; return 0 end,
        AreOutgoingAddonChatMessagesRestricted = function() return e.restricted end,
        InChatMessagingLockdown = function() return e.chatRestricted end,
        SendAddonMessage = function(prefix, text, channel, target)
            table.insert(e.sent, {prefix, text, channel, target})
            return e.sendResult
        end,
        SendChatMessage = function(text, channel, _, target) table.insert(e.chat, {text, channel, target}) end,
    }
    e.DEFAULT_CHAT_FRAME = {AddMessage = function(_, message) table.insert(e.messages, message) end}
    e.CreateFrame = function(kind, name, parent, template)
        local w = widget(); w.TitleText = widget()
        w.kind, w.parent, w.template = kind, parent, template
        if parent and parent.children then table.insert(parent.children, w) end
        if name then e.frames[name] = w end
        return w
    end
    e.UIParent, e.ChatFontNormal = {}, {}
    e.UISpecialFrames, e.SlashCmdList = {}, {}
    for _, file in ipairs(files) do
        local fn = assert(loadfile(ROOT .. "/ADKP_Forever/" .. file)); setfenv(fn, e); fn()
    end
    e.F = e.ADKP_Forever
    assert(e.F.Initialize()); assert(e.F.Comm.Initialize())
    return e
end

local function initial(e, text)
    local plan, err = e.F.Data.PrepareInitial(text)
    assert(plan, err); assert(e.F.Data.ApplyInitial(plan))
end

local function deliver(from, to)
    local packets = from.sent; from.sent = {}
    for _, packet in ipairs(packets) do
        eq(packet[3], "WHISPER"); eq(packet[4], to.units.player.name)
        assert(string.len(packet[2]) <= 240)
        to.F.Comm.Receive(packet[1], packet[2], packet[3], from.units.player.name)
    end
end

local function exchange(a, b, ticks)
    for _ = 1, ticks or 100 do
        a.now, b.now = a.now + 0.2, b.now + 0.2
        a.F.Comm.Pump(); b.F.Comm.Pump()
        deliver(a, b); deliver(b, a)
    end
end

test("full names, same first name, UTF-8 and GUID conflicts", function()
    local e = client("星河 晨风")
    local I = e.F.Identity
    local a = assert(I.Register("星河 晨风", "g1"))
    local b = assert(I.Register("星河 暮雨", "g2"))
    assert(a.id ~= b.id); eq(I.Resolve("星河"), nil)
    eq(I.Target("星河 晨风"), "星河 晨风")
    eq(I.Register("星河 晨风", "g3"), nil)
    eq(I.Register("改名 新姓", "g1"), nil)
    eq(I.Name("名字\t姓氏"), nil)
    eq(I.Name("bad\239"), nil)
    eq(I.Name("bad\237\160\128"), nil)
    assert(I.Name(string.rep("星", 40) .. " " .. string.rep("雨", 40)))
    eq(I.Name({secret = true}), nil)
end)

test("native composed name, never tuple realm suffix", function()
    local e = client("First Last")
    local p = assert(e.F.Identity.FromUnit("player"))
    eq(p.name, "First Last"); eq(e.F.Identity.Target(p.name), "First Last")
end)

test("Chinese full names tolerate six characters without imposing server rules", function()
    local I = client().F.Identity
    eq(I.LiveName("加 百列"), "加 百列")
    eq(I.LiveName("天地玄黄 宇宙"), "天地玄黄 宇宙")
    eq(I.LiveName("甲 乙丙丁戊己"), "甲 乙丙丁戊己")
    eq(I.LiveName("天地玄黄 宇宙洪"), "天地玄黄 宇宙洪")
    -- U+20000 is a four-byte Han character, still one character, not four.
    local supplementary = "\240\160\128\128"
    eq(I.LiveName(supplementary .. " 名"), supplementary .. " 名")
end)

test("English full names tolerate twelve-letter components without truncation", function()
    local I = client().F.Identity
    local maximum = "Abcdefghijkl Mnopqrstuvwx"
    eq(I.LiveName(maximum), maximum)
    eq(I.LiveName("Abcdefghijklm Last"), "Abcdefghijklm Last")
    eq(I.LiveName("First Abcdefghijklm"), "First Abcdefghijklm")
    eq(I.LiveName("First Last7"), "First Last7")
    eq(I.LiveName("First Last-name"), "First Last-name")
end)

test("native names are opaque and have no character-creation policy checks", function()
    local I = client().F.Identity
    for _, name in ipairs({"加 Gabriel", "Gabriel 百列", "Ga加 briel", "加百 列A", "加  百列",
        "加\194\160百列", "单名", "First", "First Middle Last"}) do
        eq(I.LiveName(name), name, name)
    end
    eq(I.LiveName("  加 百列  "), "加 百列")
end)

test("legacy names and unusual full names remain intact across data and addressing", function()
    local e = client()
    local oldName = string.rep("星", 12)
    initial(e, oldName .. ",MAGE,55\n加 百列,PRIEST,80")
    eq(e.F.Data.Balance(oldName), 55)
    assert(string.find(e.F.Data.ExportInitial(), oldName, 1, true))
    eq(e.F.Identity.Target(oldName), oldName)
    assert(e.F.Comm.SetCaptain(oldName))
    assert(e.F.Comm.Allow("加 Gabriel", true))
    assert(e.F.Comm.Request("First Abcdefghijklm"))
    eq(count(e.F.Comm.queue), 1)
    local copy = client(); initial(copy, e.F.Data.ExportInitial())
    eq(copy.F.Data.Balance(oldName), 55)
end)

test("native and WHISPER paths tolerate the reported full-name boundaries", function()
    local a = client("加 百列")
    eq(assert(a.F.Identity.FromUnit("player")).name, "加 百列")
    a.units.target = {name = "天地玄黄 宇宙洪", guid = "Player-invalid", class = "MAGE"}
    eq(assert(a.F.Identity.FromUnit("target")).name, a.units.target.name)
    assert(a.F.Identity.Resolve(a.units.target.name))
    local b = client("Abcdefghijkl Mnopqrstuvwx")
    assert(b.F.Comm.Allow("加 百列", true))
    assert(a.F.Comm.SetCaptain(b.units.player.name)); assert(a.F.Comm.Request())
    exchange(a, b, 30)
    assert(a.F.Comm.verified)
    eq(a.F.Comm.verified.target, b.units.player.name)
end)

test("initial import stages all rows and preserves other teams", function()
    local e = client()
    initial(e, "星河 晨风,WARRIOR,100\n星河 暮雨,MAGE,20")
    e.WebDKP_DkpTable["星河 晨风"].dkp_2 = 999
    e.WebDKP_Log.other = {tableid = 2, awarded = {}}
    local before = e.F.Data.ExportInitial()
    eq(e.F.Data.PrepareInitial("新人 姓氏,MAGE,20\n坏行,MAGE,NaN"), nil)
    eq(e.F.Data.ExportInitial(), before)
    local plan = assert(e.F.Data.PrepareInitial("新名 新姓,ROGUE,30"))
    eq(e.WebDKP_DkpTable["星河 晨风"].dkp_1, 100)
    assert(e.F.Data.ApplyInitial(plan))
    eq(e.WebDKP_DkpTable["星河 晨风"].dkp_2, 999)
    eq(e.WebDKP_DkpTable["星河 晨风"].dkp_1, nil)
    assert(e.WebDKP_Log.other)
    eq(e.WebDKP_DkpTable["新名 新姓"].dkp_1, 30)
end)

test("initial round trip keeps full names and website-bound shared balance", function()
    local a, b = client(), client()
    initial(a, "\239\187\191First LongSurname,WARRIOR,123.45,\r\nFirst OtherSurname,MAGE,123.45,First LongSurname\r\n")
    local text = a.F.Data.ExportInitial()
    initial(b, text)
    eq(b.F.Data.ExportInitial(), text)
    eq(b.F.Data.Balance("First LongSurname"), 123.45)
    eq(b.F.Data.Balance("First OtherSurname"), 123.45)
    eq(b.ADKP_ShareGroups[1]["First OtherSurname"], "First LongSurname")
    eq(a.F.Data.PrepareInitial("First Last,MAGE,0\nfirst last,MAGE,1"), nil)
    eq(a.F.Data.PrepareInitial("A B,MAGE,0,C D\nC D,MAGE,0,A B"), nil)
end)

test("stale import confirmations cannot replace changed ledger", function()
    local e = client(); initial(e, "A B,MAGE,50")
    local plan = assert(e.F.Data.PrepareInitial("A B,MAGE,100"))
    assert(e.F.Data.Award({"A B"}, 5, "集合分", false, "event1"))
    eq(e.F.Data.ApplyInitial(plan), nil)
    eq(e.F.Data.Balance("A B"), 55)
    local again = assert(e.F.Data.PrepareInitial("A B,MAGE,1"))
    e.F.db.tableID = 2
    eq(e.F.Data.ApplyInitial(again), nil)
end)

test("awards deduplicate receipts, not independent equal-time events", function()
    local e = client(); initial(e, "A B,MAGE,50")
    local key = assert(e.F.Data.Award({"A B"}, 5, "集合分", false, "event1"))
    eq(e.F.Data.Award({"A B"}, 5, "集合分", false, "event1"), key)
    eq(e.F.Data.Balance("A B"), 55)
    assert(e.F.Data.Award({"A B"}, 5, "集合分", false, "event2"))
    eq(e.F.Data.Balance("A B"), 60)
    eq(e.F.Data.Award({"A B", "A B"}, 5, "重复名单"), nil)
end)

test("quoted binding and legacy shared award semantics", function()
    local e = client(); initial(e, "主号 全名,WARRIOR,100\n小号 全名,MAGE,20")
    e.F.Command('share "主号 全名" "小号 全名"')
    eq(e.F.Data.Balance("主号 全名"), 120)
    assert(e.F.Data.Award({"主号 全名"}, 10, "击杀-首领"))
    assert(e.F.Data.Award({"小号 全名"}, 5, "击杀-首领-替补"))
    eq(e.F.Data.Balance("主号 全名"), 130)
    eq(e.F.Data.Balance("小号 全名"), 130)
    assert(e.F.Data.Award({"小号 全名"}, -30, "装备", true))
    eq(e.F.Data.Balance("主号 全名"), 100)
    assert(string.find(assert(e.F.Data.ExportActivity("compact")), "#ADKP_SHARE_PROPOSAL,主号 全名,小号 全名,MAGE", 1, true))
    eq(e.F.Arguments('"unclosed'), nil)
end)

test("new activity export is read by actual legacy export conventions", function()
    local e = client(); initial(e, "星河 晨风,WARRIOR,100\n星河 暮雨,MAGE,20")
    assert(e.F.Data.Award({"星河 晨风", "星河 暮雨"}, 5, "集合分"))
    assert(e.F.Data.Award({"星河 暮雨"}, -10, "装备", true))
    local file = assert(io.open(ROOT .. "/ADKP/ADKP.lua", "rb")); local src = file:read("*a"); file:close()
    local function extract(first, last)
        local start = assert(string.find(src, first, 1, true))
        return string.sub(src, start, assert(string.find(src, last, start + string.len(first), true)) - 1)
    end
    e.ADKP_GetTableid = function() return 1 end; e.ADKP_ROUND = e.F.Round
    local compact = assert(loadstring(extract("function ADKP_BuildBackupCSV(", "-- 备份文件名构造 helper")))
    setfenv(compact, e); compact()
    local full = assert(loadstring(extract("function ADKP_BuildExportText()", "function ADKP_ExportRecords_SwitchMode(")))
    setfenv(full, e); full()
    local function sorted(text)
        local lines = {}; for line in string.gmatch(text, "[^\n]+") do table.insert(lines, line) end
        table.sort(lines); return table.concat(lines, "\n")
    end
    -- The legacy compact serializer iterates the awarded map without a stable
    -- player order; compare each semicolon player list independently.
    local function normalize(text)
        local lines = {}
        for line in string.gmatch(text, "[^\n]+") do
            local fields = e.F.Data.Split(line, ",")
            local players = e.F.Data.Split(fields[6], ";"); table.sort(players)
            fields[6] = table.concat(players, ";"); table.insert(lines, table.concat(fields, ","))
        end
        table.sort(lines); return table.concat(lines, "\n")
    end
    eq(normalize(e.F.Data.ExportActivity("compact")), normalize(e.ADKP_BuildBackupCSV(false)))
    eq(sorted(e.F.Data.ExportActivity("full")), sorted(e.ADKP_BuildExportText()))
end)

test("WHISPER complete round trip, six-character Chinese name and reverse packet order", function()
    local a, b = client("主团 团长"), client("替补 队长")
    b.groupSize, b.units.party1 = 2, {name = "星河落 晨风起", guid = "Player-long", class = "MAGE"}
    assert(b.F.Comm.Allow(a.units.player.name, true))
    assert(a.F.Comm.SetCaptain(b.units.player.name)); assert(a.F.Comm.Request())
    a.F.Comm.Pump(); deliver(a, b)
    local packets = b.F.Comm.queue; b.F.Comm.queue = {}
    for i = count(packets), 1, -1 do
        assert(string.len(packets[i].text) <= 240)
        a.F.Comm.Receive(a.F.prefix, packets[i].text, "WHISPER", b.units.player.name)
        a.F.Comm.Receive(a.F.prefix, packets[i].text, "WHISPER", b.units.player.name)
    end
    local cache = a.F.db.sync.caches[1][a.F.Identity.Key(b.units.player.name)]
    eq(count(cache.members), 2); assert(a.F.Comm.verified)
    eq(count(a.chat), 0); eq(count(b.chat), 0)
end)

test("unauthorized requester gets no roster, fake sender cannot satisfy request", function()
    local a, b = client(), client("Sub Captain")
    assert(a.F.Comm.SetCaptain("Sub Captain")); assert(a.F.Comm.Request())
    exchange(a, b, 4)
    eq(count(b.sent), 0); eq(a.F.Comm.verified, nil)
    eq(a.F.db.sync.caches[1], nil)
    b.F.Comm.Allow("Leader One", true)
    local request = a.F.Comm.pending[a.F.Identity.Key("Sub Captain")]
    b.F.Comm.Receive(b.F.prefix, b.F.Comm.Encode({"1", "REQ", request.id}), "WHISPER", "Leader One")
    for _, packet in ipairs(b.F.Comm.queue) do a.F.Comm.Receive(a.F.prefix, packet.text, "WHISPER", "Fake Sender") end
    eq(a.F.Comm.verified, nil)
end)

test("partial, corrupt and timed-out transfers preserve complete cache", function()
    local a, b = client(), client("Sub Captain")
    b.F.Comm.Allow("Leader One", true); a.F.Comm.SetCaptain("Sub Captain")
    a.F.Comm.Request(); exchange(a, b, 20)
    local key = a.F.Identity.Key("Sub Captain")
    local old = a.F.db.sync.caches[1][key]
    assert(old)
    a.F.Comm.Request(); a.F.Comm.Pump(); deliver(a, b)
    for i, packet in ipairs(b.F.Comm.queue) do
        if i == 1 then a.F.Comm.Receive(a.F.prefix, packet.text, "WHISPER", "Sub Captain") end
    end
    a.F.Comm.Receive(a.F.prefix, "1:14:DATA", "WHISPER", "Sub Captain")
    a.now = a.now + 121; a.F.Comm.Pump()
    eq(a.F.db.sync.caches[1][key], old)
    eq(a.F.Comm.status[key].state, "timeout")
    for _, packet in ipairs(b.F.Comm.queue) do a.F.Comm.Receive(a.F.prefix, packet.text, "WHISPER", "Sub Captain") end
    eq(a.F.db.sync.caches[1][key], old)
end)

test("send failure and chat restriction never claim successful synchronization", function()
    local e = client(); e.sendResult = 8
    e.F.Comm.SetCaptain("Other Person"); e.F.Comm.Request()
    for _ = 1, 6 do e.now = e.now + 4; e.F.Comm.Pump() end
    eq(e.F.Comm.verified, nil)
    eq(e.F.Comm.status[e.F.Identity.Key("Other Person")].state, "failed")
    e.restricted = true; e.F.Comm.Request()
    local sends = count(e.sent); e.now = e.now + 4; e.F.Comm.Pump(); eq(count(e.sent), sends)
end)

test("team switch does not redirect an in-flight response", function()
    local a, b = client(), client("Sub Captain")
    b.F.Comm.Allow("Leader One", true); a.F.Comm.SetCaptain("Sub Captain"); a.F.Comm.Request()
    a.F.db.tableID = 2
    exchange(a, b, 20)
    assert(a.F.db.sync.caches[1]); eq(a.F.db.sync.caches[2], nil)
end)

test("codec rejects malformed lengths and never splits names on spaces", function()
    local C = client().F.Comm
    local fields = {"姓 名", "", "First Last"}
    local decoded = assert(C.Decode(C.Encode(fields)))
    eq(decoded[1], fields[1]); eq(decoded[2], ""); eq(decoded[3], fields[3])
    eq(C.Decode("9999999:x"), nil); eq(C.Decode("-1:x"), nil); eq(C.Decode("3:ab"), nil)
end)

test("native raid roster changes and restricted names fail closed", function()
    local e = client()
    e.raid, e.groupSize = true, 2
    e.units.raid1 = e.units.player
    e.units.raid2 = {name = "Other Surname", guid = "Player-other", class = "MAGE"}
    eq(count(assert(e.F.Roster.Snapshot())), 2)
    e.units.raid2.name = {secret = true}
    eq(e.F.Roster.Snapshot(), nil)
    e.units.raid2.name = "Other Surname"
    local original = e.GetUnitName
    e.GetUnitName = function(unit)
        if unit == "raid2" then e.F.Roster.Invalidate() end
        return original(unit)
    end
    eq(e.F.Roster.Snapshot(), nil)
end)

test("identity failure rolls back import and the entire received roster", function()
    local a, b = client(), client("Sub Captain")
    initial(a, "Original Person,MAGE,88")
    local plan = assert(a.F.Data.PrepareInitial("New Person,MAGE,99"))
    -- A pre-existing damaged record in another team must not cause a partial
    -- commit after the import has removed the current team's points/logs.
    a.WebDKP_DkpTable["Invalid,Name"] = {dkp_2 = 10}
    eq(a.F.Data.ApplyInitial(plan), nil)
    eq(a.F.Data.Balance("Original Person"), 88)
    eq(a.F.Identity.Resolve("New Person"), nil)
    a.WebDKP_DkpTable["Invalid,Name"] = nil
    b.F.Comm.Allow("Leader One", true)
    a.F.Comm.SetCaptain("Sub Captain")
    a.F.Comm.Request(); exchange(a, b, 20)
    local key = a.F.Identity.Key("Sub Captain")
    local old = a.F.db.sync.caches[1][key]
    assert(a.F.Identity.Register("Existing Person", "wrong-guid"))
    b.groupSize = 3
    b.units.party1 = {name = "Brandnew Person", guid = "new-guid", class = "MAGE"}
    b.units.party2 = {name = "Existing Person", guid = "conflicting-guid", class = "MAGE"}
    a.F.Comm.Request(); exchange(a, b, 40)
    eq(a.F.db.sync.caches[1][key], old)
    eq(a.F.Identity.Resolve("Brandnew Person"), nil)
    eq(a.F.Comm.status[key].state, "conflict")
end)

test("revoking requester access stops queued roster transmission", function()
    local a, b = client(), client("Sub Captain")
    b.F.Comm.Allow("Leader One", true)
    a.F.Comm.SetCaptain("Sub Captain"); a.F.Comm.Request()
    a.F.Comm.Pump(); deliver(a, b)
    assert(count(b.F.Comm.queue) > 0)
    b.F.Comm.Allow("Leader One", false)
    for _ = 1, 20 do b.now = b.now + 0.2; b.F.Comm.Pump() end
    eq(count(b.sent), 0)
end)

test("corrupted checksum and wrong channels never verify WHISPER", function()
    local a, b = client(), client("Sub Captain")
    b.F.Comm.Allow("Leader One", true)
    a.F.Comm.SetCaptain("Sub Captain"); a.F.Comm.Request()
    a.F.Comm.Pump(); deliver(a, b)
    for _, packet in ipairs(b.F.Comm.queue) do
        local fields = assert(a.F.Comm.Decode(packet.text))
        fields[6] = "0"
        a.F.Comm.Receive(a.F.prefix, a.F.Comm.Encode(fields), "WHISPER", "Sub Captain")
        a.F.Comm.Receive(a.F.prefix, packet.text, "GUILD", "Sub Captain")
    end
    eq(a.F.Comm.verified, nil); eq(a.F.db.sync.caches[1], nil)
end)

test("c remains one-target adjustment with its original default reason", function()
    local e = client()
    initial(e, "Target Fullname,MAGE,50\nOther Person,MAGE,70")
    e.units.target = {name = "Target Fullname", guid = "Player-target", class = "MAGE"}
    e.F.Command("c-5")
    eq(e.F.Data.Balance("Target Fullname"), 45)
    eq(e.F.Data.Balance("Other Person"), 70)
    local found = false
    for _, log in pairs(e.WebDKP_Log) do
        if type(log) == "table" and log.reason == "菜出天际-犯错" then found = true end
    end
    assert(found)
end)

test("relogin derives missing bases without resetting saved balances", function()
    local e = client()
    initial(e, "A B,MAGE,100")
    assert(e.F.Data.Award({"A B"}, 5, "First Award"))
    e.ADKP_ShareSessionBase = {}
    e.F.Data.InitializeBases()
    assert(e.F.Data.Award({"A B"}, 10, "Next Award"))
    eq(e.F.Data.Balance("A B"), 115)
end)

test("duplicate prefix registration is usable but invalid prefix is not", function()
    local e = client()
    e.Enum.RegisterAddonMessagePrefixResult.DuplicatePrefix = 1
    e.C_ChatInfo.RegisterAddonMessagePrefix = function() return 1 end
    assert(e.F.Comm.Initialize())
    e.C_ChatInfo.RegisterAddonMessagePrefix = function() return 2 end
    eq(e.F.Comm.Initialize(), nil)
    eq(e.F.Comm.ready, false)
end)

test("native event boot and non-addon whisper query preserve sender full name", function()
    local e = client("星河 晨风")
    initial(e, "星河 晨风,WARRIOR,80\n星河 暮雨,MAGE,20")
    e.frames.ADKP_ForeverEvents.scripts.OnEvent(e.frames.ADKP_ForeverEvents, "PLAYER_LOGIN")
    assert(e.F.active); assert(e.SlashCmdList.ADKPFOREVER)
    local onEvent = e.frames.ADKP_ForeverEvents.scripts.OnEvent
    onEvent(e.frames.ADKP_ForeverEvents, "CHAT_MSG_WHISPER", "dkp", "星河 暮雨", nil, nil, nil, nil, nil, nil, nil, nil, nil, "Player-other")
    eq(e.chat[1][3], "星河 暮雨"); assert(string.find(e.chat[1][1], "20", 1, true))
    e.F.UI.Toggle(); assert(e.F.UI.frame:IsShown())
    e.F.UI.TextDialog("import"); e.F.UI.dialog.edit:SetText("星河 晨风,WARRIOR,90")
    e.F.UI.dialog.action.scripts.OnClick(); eq(e.F.Data.Balance("星河 晨风"), 80)
    e.F.UI.dialog.action.scripts.OnClick(); eq(e.F.Data.Balance("星河 晨风"), 90)
end)

test("wrong client and legacy addon collision refuse startup", function()
    local e = client()
    e.GetBuildInfo = function() return "1.12.1", "5875", "", 11200 end
    e.frames.ADKP_ForeverEvents.scripts.OnEvent(e.frames.ADKP_ForeverEvents, "PLAYER_LOGIN")
    eq(e.F.active, nil); eq(e.SlashCmdList.ADKPFOREVER, nil)
    local other = client(); other.C_AddOns.IsAddOnLoaded = function() return true end
    other.frames.ADKP_ForeverEvents.scripts.OnEvent(other.frames.ADKP_ForeverEvents, "PLAYER_LOGIN")
    eq(other.F.active, nil)
end)

local function raiders()
    local e = client("Leader One")
    e.groupSize = 3
    e.units.party1 = {name = "Alpha Beta", guid = "Player-beta", class = "MAGE"}
    e.units.party2 = {name = "Alpha Gamma", guid = "Player-gamma", class = "PRIEST"}
    initial(e, "Leader One,WARRIOR,100\nAlpha Beta,MAGE,60\nAlpha Gamma,PRIEST,20")
    return e
end

test("public bids accept full names, P, all-in and deterministic ties", function()
    local e = raiders(); local B = e.F.Bidding
    assert(B.Enqueue("Sword of Testing", 30, "public"))
    B.Chat("CHAT_MSG_PARTY", "30P", "Alpha Beta")
    B.Chat("CHAT_MSG_WHISPER", "30", "Leader One")
    eq(B.Ranking()[1].name, "Alpha Beta")
    B.Chat("CHAT_MSG_PARTY", "sh", "Alpha Gamma")
    eq(B.Current().entries[3].amount, 20)
    eq(B.Submit("Alpha Beta", 30, "CHAT_MSG_PARTY"), nil)
    eq(count(B.Current().entries), 3)
    eq(B.Submit("Not InGroup", 1, "CHAT_MSG_PARTY"), nil)
end)

test("anonymous bids and overbid warnings never disclose details to the group", function()
    local e = raiders(); local B = e.F.Bidding
    assert(B.Enqueue("Secret Sword", 30, "anonymous"))
    eq(B.Submit("Alpha Beta", 40, "CHAT_MSG_PARTY"), nil)
    assert(B.Submit("Alpha Beta", 40, "CHAT_MSG_WHISPER"))
    e.now = 25
    assert(B.Submit("Alpha Gamma", 99, "CHAT_MSG_WHISPER"))
    eq(B.Ranking()[1].name, "Alpha Beta")
    eq(B.Current().deadline, 35)
    for _, job in ipairs(e.F.Chat.queue) do
        if job.channel ~= "WHISPER" then
            assert(not string.find(job.message, "Alpha", 1, true))
            assert(not string.find(job.message, "99", 1, true))
            assert(not string.find(job.message, "40", 1, true))
        end
    end
end)

test("settlement is explicit and idempotent, delivery never deducts again", function()
    local e = raiders(); local B = e.F.Bidding
    assert(B.Enqueue("Sword", 0, "public")); assert(B.Submit("Alpha Beta", 30, "CHAT_MSG_PARTY"))
    eq(B.Settle(), nil)
    assert(B.Stop()); local key = assert(B.Settle())
    eq(e.F.Data.Balance("Alpha Beta"), 30)
    eq(B.Settle(), nil); eq(e.F.Data.Balance("Alpha Beta"), 30)
    local id = B.Current().id
    eq(e.F.db.deliveries[id].record, key)
    assert(e.F.Loot.Confirm(id)); assert(e.F.Loot.Confirm(id))
    eq(e.F.Data.Balance("Alpha Beta"), 30)
end)

test("balance changes invalidate a formerly affordable bid before settlement", function()
    local e = raiders(); local B = e.F.Bidding
    B.Enqueue("Sword", 0, "public"); B.Submit("Alpha Beta", 50, "CHAT_MSG_PARTY"); B.Stop()
    e.F.Data.Award({"Alpha Beta"}, -30, "罚分")
    eq(B.Settle("Alpha Beta", 50), nil)
    eq(e.F.Data.Balance("Alpha Beta"), 30)
end)

test("multi-link queue waits for settlement and survives reload paused", function()
    local e = raiders(); local B = e.F.Bidding
    local first = "|cffffffff|Hitem:1:0|h[First Sword]|h|r"
    local second = "|cffffffff|Hitem:2:0|h[Second Sword]|h|r"
    assert(B.Enqueue(first .. " " .. second, 30, "public"))
    eq(B.Current().item, first); eq(count(e.F.db.auctions.queue), 1)
    eq(B.Next(), nil)
    e.now = 10; B.Tick(); eq(B.Current().remaining, 20)
    B.Initialize(); eq(B.Current().phase, "paused")
    e.now = 0; assert(B.Resume()); eq(B.Current().deadline, 20)
    B.Pass(); assert(B.Next()); eq(B.Current().item, second)
    eq(B.Items("prefix " .. first), nil)
end)

test("auction freezes its team and blocks destructive initial replacement", function()
    local e = raiders(); local B = e.F.Bidding
    B.Enqueue("Sword", 30, "public")
    eq(e.F.Data.PrepareInitial("Leader One,WARRIOR,0"), nil)
    e.F.db.tableID = 2
    eq(B.Submit("Alpha Beta", 10, "CHAT_MSG_WHISPER"), nil)
    eq(B.Settle("Alpha Beta", 0), nil)
    e.F.db.tableID = 1; B.Pass()
    assert(e.F.Data.PrepareInitial("Leader One,WARRIOR,0"))
end)

test("all bid callbacks ignore secret values and retired appearance commands", function()
    local e = raiders(); local B = e.F.Bidding
    B.Enqueue("Sword", 0, "public")
    B.Chat("CHAT_MSG_PARTY", {secret = true}, "Alpha Beta")
    B.Chat("CHAT_MSG_PARTY", "10", {secret = true})
    B.Chat("CHAT_MSG_PARTY", "hh", "Alpha Beta")
    eq(count(B.Current().entries), 0)
    eq(B.Transmog, nil); eq(B.Roll, nil)
end)

test("raid and substitute awards use fresh response and remove duplicate members", function()
    local a, b = raiders(), client("Sub Captain")
    initial(a, "Leader One,WARRIOR,100\nAlpha Beta,MAGE,60\nAlpha Gamma,PRIEST,20\nSub Captain,MAGE,10\nReserve Person,MAGE,5")
    b.groupSize = 3
    b.units.party1 = {name = "Alpha Beta", guid = "Player-beta", class = "MAGE"}
    b.units.party2 = {name = "Reserve Person", guid = "Player-reserve", class = "MAGE"}
    b.F.Comm.Allow("Leader One", true); a.F.Comm.SetCaptain("Sub Captain")
    local job = assert(a.F.Awards.New(10, 5, "集合分"))
    eq(job.state, "waiting"); eq(a.F.Awards.Apply(job.id), nil)
    exchange(a, b, 50)
    assert(a.F.Awards.Apply(job.id)); assert(a.F.Awards.Apply(job.id))
    eq(a.F.Data.Balance("Leader One"), 110)
    eq(a.F.Data.Balance("Alpha Beta"), 70)
    eq(a.F.Data.Balance("Reserve Person"), 10)
    eq(count(job.sub), 2)
    assert(a.F.Data.Void(job.result.main))
    eq(a.F.Data.Balance("Leader One"), 100)
    eq(a.F.Data.Balance("Reserve Person"), 5)
end)

test("failed substitute sync changes no scores until explicit main-only choice", function()
    local e = raiders(); e.F.Comm.SetCaptain("Missing Captain")
    local job = assert(e.F.Awards.New(10, 5, "集合分"))
    e.now = 121; e.F.Comm.Pump()
    eq(e.F.Awards.Apply(job.id), nil)
    eq(e.F.Data.Balance("Alpha Beta"), 60)
    assert(e.F.Awards.MainOnly(job.id)); assert(e.F.Awards.Apply(job.id))
    eq(e.F.Data.Balance("Alpha Beta"), 70)
end)

test("both award groups are validated before the first group is changed", function()
    local a, b = raiders(), client("Sub Captain")
    b.F.Comm.Allow("Leader One", true); a.F.Comm.SetCaptain("Sub Captain")
    local job = assert(a.F.Awards.New(10, 5, "集合分"))
    exchange(a, b, 30)
    eq(a.F.Awards.Apply(job.id), nil)
    eq(a.F.Data.Balance("Leader One"), 100)
    eq(job.result, nil)
end)

test("shared raid/sub award takes the higher positive value once per event", function()
    local a, b = client("Main Person"), client("Alt Person")
    a.groupSize = 1
    initial(a, "Main Person,WARRIOR,100\nAlt Person,MAGE,100,Main Person")
    b.F.Comm.Allow("Main Person", true); a.F.Comm.SetCaptain("Alt Person")
    local first = assert(a.F.Awards.New(10, 5, "同一次击杀")); exchange(a, b, 30); assert(a.F.Awards.Apply(first.id))
    eq(a.F.Data.Balance("Main Person"), 110)
    local second = assert(a.F.Awards.New(10, 5, "同一次击杀")); exchange(a, b, 30); assert(a.F.Awards.Apply(second.id))
    eq(a.F.Data.Balance("Main Person"), 120)
end)

test("official encounter events deduplicate kill signals and ignore wipes", function()
    local e = raiders(); local E = e.F.Encounters
    E.Event("ENCOUNTER_START", 101, "Test Boss")
    E.Event("ENCOUNTER_END", 101, "Test Boss", 1, 3, 0)
    eq(next(e.F.db.encounters.pending), nil)
    E.Event("ENCOUNTER_END", 101, "Test Boss", 1, 3, 1)
    E.Event("BOSS_KILL", 101, "Test Boss")
    local n, id = 0, nil; for key in pairs(e.F.db.encounters.pending) do n = n + 1; id = key end
    eq(n, 1)
    assert(E.Submit(id)); eq(e.F.Data.Balance("Leader One"), 101)
    eq(E.Submit(id), nil)
    E.Event("BOSS_KILL", 101, "Test Boss")
    eq(e.F.Data.Balance("Leader One"), 101)
end)

test("boss automation is recorder-only, optional and respects disabled encounters", function()
    local e = raiders(); local E = e.F.Encounters
    e.leader, e.assistant = false, true
    e.F.db.settings.bossAuto = true
    E.Event("BOSS_KILL", 102, "Ignored Boss"); eq(next(e.F.db.encounters.pending), nil)
    e.F.db.settings.recorder = "Leader One"
    E.Configure(102, 10, 0, false)
    E.Event("BOSS_KILL", 102, "Ignored Boss"); eq(next(e.F.db.encounters.pending), nil)
    E.Configure(103, 10, 0, true)
    E.Event("BOSS_KILL", 103, "Award Boss"); E.Pump()
    eq(e.F.Data.Balance("Leader One"), 110)
    e.F.Awards.Pump(); eq(e.F.Data.Balance("Leader One"), 110)
end)

test("loot record, refund and reauction do not confuse accounting and delivery", function()
    local e = raiders()
    local link = "|cffffffff|Hitem:123:0|h[Sword]|h|r"
    local record = assert(e.F.Loot.Record(link, "Alpha Beta", 25))
    eq(e.F.Data.Balance("Alpha Beta"), 35)
    local id; for key, job in pairs(e.F.db.deliveries) do id = key; eq(job.state, "pending") end
    eq(e.F.Loot.Assign(id), nil)
    eq(e.F.Data.Balance("Alpha Beta"), 35)
    assert(e.F.Data.Void(record)); eq(e.F.Data.Balance("Alpha Beta"), 60)
    eq(e.F.db.deliveries[id].state, "cancelled")
    eq(e.F.Loot.Confirm(id), nil)
    assert(e.F.Bidding.Enqueue(link, 30, "public"))
end)

test("master loot uses slot-specific candidates and waits for actual evidence", function()
    local e = raiders(); local link = "|cffffffff|Hitem:123:0|h[Sword]|h|r"
    e.F.Loot.Record(link, "Alpha Beta", 25)
    local id; for key in pairs(e.F.db.deliveries) do id = key end
    e.GetLootMethod = function() return "master", 0, nil end
    e.GetNumLootItems = function() return 1 end
    e.GetLootSlotLink = function() return link end
    e.GetMasterLootCandidate = function(slot, index) eq(slot, 1); if index == 2 then return "Alpha Beta" end end
    local assigned = 0
    e.GiveMasterLoot = function(slot, index) eq(slot, 1); eq(index, 2); assigned = assigned + 1 end
    assert(e.F.Loot.Assign(id)); eq(assigned, 1)
    eq(e.F.db.deliveries[id].state, "awaiting")
    eq(e.F.Loot.Assign(id), nil); eq(assigned, 1)
    e.F.Loot.Observe("Alpha Beta获得了物品：" .. link .. "。", "")
    eq(e.F.db.deliveries[id].state, "delivered")
    eq(e.F.Data.Balance("Alpha Beta"), 35)
end)

test("duplicate physical loot slots require native disambiguation", function()
    local e = raiders(); local link = "|cffffffff|Hitem:123:0|h[Sword]|h|r"
    e.F.Loot.Record(link, "Alpha Beta", 25)
    local id; for key in pairs(e.F.db.deliveries) do id = key end
    e.GetLootMethod = function() return "master", 0, nil end
    e.GetNumLootItems = function() return 2 end
    e.GetLootSlotLink = function() return link end
    e.GetMasterLootCandidate = function() error("must not choose a duplicate slot") end
    e.GiveMasterLoot = function() error("must not assign an ambiguous item") end
    eq(e.F.Loot.Assign(id), nil)
end)

test("quick adjust remains single-target with optional configured player and reason", function()
    local e = raiders()
    e.units.target = e.units.party1
    e.F.db.settings.quickPoints = -5
    assert(e.F.Operations.Adjust()); eq(e.F.Data.Balance("Alpha Beta"), 55); eq(e.F.Data.Balance("Alpha Gamma"), 20)
    e.F.db.settings.quickPlayer, e.F.db.settings.quickReason = "Alpha Gamma", "迟到"
    assert(e.F.Operations.Adjust()); eq(e.F.Data.Balance("Alpha Gamma"), 15); eq(e.F.Data.Balance("Alpha Beta"), 55)
end)

test("all business panels and native event callbacks construct successfully", function()
    local e = raiders()
    for _, tab in ipairs({"auction", "awards", "boss", "loot", "logs", "share", "settings", "queue"}) do
        e.F.Operations.Show(tab); eq(e.F.Operations.tab, tab)
    end
    local event = e.frames.ADKP_ForeverEvents
    event.scripts.OnEvent(event, "PLAYER_LOGIN")
    assert(event.events.ENCOUNTER_END); assert(event.events.CHAT_MSG_RAID)
    e.F.Command("bid public 30 Sword")
    event.scripts.OnEvent(event, "CHAT_MSG_WHISPER", "10p", "Alpha Beta")
    eq(e.F.Bidding.Ranking()[1].name, "Alpha Beta")
    event.scripts.OnUpdate(event)
    eq(e.F.Operations.panels.auction == nil, false)
end)

test("next queued item starts after settlement and manual countdown only announces", function()
    local e = raiders(); local B = e.F.Bidding
    B.Enqueue("First Sword", 0, "public"); B.Enqueue("Second Sword", 0, "public")
    B.Countdown()
    for _ = 1, 8 do B.Tick(); e.now = e.now + 1 end
    eq(B.Current().phase, "bidding")
    B.Submit("Alpha Beta", 10, "CHAT_MSG_PARTY"); B.Stop()
    e.now = e.now + 10; B.Tick(); eq(B.Current().item, "First Sword")
    assert(B.Settle()); e.now = e.now + 2; B.Tick(); eq(B.Current().item, "Second Sword")
end)

test("party invitation keeps full names, is opt-in and does not spam", function()
    local e = raiders(); local invites, conversions = {}, 0
    e.C_PartyInfo = {
        CanInvite = function() return true end,
        InviteUnit = function(name) table.insert(invites, name) end,
        ConvertToRaid = function() conversions = conversions + 1 end,
    }
    e.F.Groups.Whisper("9527", "加 百列"); eq(count(invites), 0)
    e.F.db.settings.autoInvite = true
    e.F.Groups.Whisper("9527", "加 百列"); e.F.Groups.Whisper("9527", "加 百列")
    eq(count(invites), 1); eq(invites[1], "加 百列")
    e.F.db.settings.autoConvert = true; e.groupSize = 5
    e.F.Groups.Roster(); e.F.Groups.Roster(); eq(conversions, 1)
end)

test("secret encounter parameters and changed restricted rosters cannot silently award", function()
    local e = raiders(); local E = e.F.Encounters
    E.Event("BOSS_KILL", {secret = true}, "Boss"); eq(next(e.F.db.encounters.pending), nil)
    e.units.party1.name = {secret = true}
    E.Event("BOSS_KILL", 405, "Restricted Boss")
    local id, job = next(e.F.db.encounters.pending)
    assert(job); eq(job.rows, nil)
    e.units.party1.name = "Alpha Beta"; e.F.Roster.Invalidate(); E.Pump()
    eq(job.rows, nil); eq(E.Submit(id), nil)
    assert(E.RefreshRoster(id)); assert(E.Submit(id))
    eq(e.F.Data.Balance("Alpha Beta"), 61)
end)

test("commanded raid award finishes after fresh substitute response", function()
    local a, b = raiders(), client("Sub Captain")
    initial(a, "Leader One,WARRIOR,100\nAlpha Beta,MAGE,60\nAlpha Gamma,PRIEST,20\nSub Captain,MAGE,5")
    b.F.Comm.Allow("Leader One", true); a.F.Comm.SetCaptain("Sub Captain")
    a.F.Command("award 10 5 集合分")
    exchange(a, b, 30); a.F.Awards.Pump()
    eq(a.F.Data.Balance("Leader One"), 110); eq(a.F.Data.Balance("Sub Captain"), 10)
    a.F.Awards.Pump(); eq(a.F.Data.Balance("Leader One"), 110)
end)

test("loss of host authority prevents committing the auction", function()
    local e = raiders(); local B = e.F.Bidding
    B.Enqueue("Sword", 0, "public"); B.Submit("Alpha Beta", 10, "CHAT_MSG_PARTY"); B.Stop()
    e.leader, e.assistant = false, false
    eq(B.Settle(), nil); eq(e.F.Data.Balance("Alpha Beta"), 60)
end)

test("voiding an item excludes it from both website activity formats", function()
    local e = raiders()
    local key = assert(e.F.Loot.Record("Sword", "Alpha Beta", 10))
    assert(string.find(e.F.Data.ExportActivity("compact"), "Sword", 1, true))
    assert(e.F.Data.Void(key))
    eq(e.F.Data.ExportActivity("compact"), "")
    eq(e.F.Data.ExportActivity("full"), "")
    eq(e.F.Data.Balance("Alpha Beta"), 60)
end)

test("fractional legacy bid syntax remains supported without rounding to free bids", function()
    local e = raiders(); local B = e.F.Bidding
    B.Enqueue("Sword", 0, "public")
    assert(B.Chat("CHAT_MSG_WHISPER", ".5", "Alpha Beta"))
    eq(B.Current().entries[1].amount, 0.5)
    eq(B.Submit("Alpha Beta", 0.001, "CHAT_MSG_WHISPER"), nil)
    eq(count(B.Current().entries), 1)
end)

test("native own-chat start and stop commands preserve item names with spaces", function()
    local e = raiders(); local B = e.F.Bidding
    B.Chat("CHAT_MSG_PARTY", "·Sword of Testing 30", "Alpha Beta")
    eq(B.Current(), nil)
    assert(B.Chat("CHAT_MSG_PARTY", "·Sword of Testing 30", "Leader One"))
    eq(B.Current().item, "Sword of Testing"); eq(B.Current().duration, 30)
    assert(B.Chat("CHAT_MSG_PARTY", "?stopbid", "Leader One")); eq(B.Current().phase, "closed")
end)

test("classic layout matches actual legacy XML sizes and list anchors", function()
    local e = raiders(); local U, O = e.F.UI, e.F.Operations
    U.Toggle(); O.Show("auction"); O.Initialize()
    eq(U.frame.width, LEGACY_MAIN_WIDTH); eq(U.frame.height, LEGACY_MAIN_HEIGHT)
    eq(O.bid.width, LEGACY_BID_WIDTH); eq(O.bid.height, LEGACY_BID_HEIGHT)
    eq(U.frame.backdrop.bgFile, "Interface\\TutorialFrame\\TutorialFrameBackground")
    eq(U.frame.backdrop.edgeFile, "Interface\\Tooltips\\UI-Tooltip-Border")
    eq(U.list.frame.points[1][2], 97); eq(U.list.frame.points[1][3], -70)
    eq(count(U.list.rows), 14); eq(U.list.rows[1].width, 245); eq(U.list.rows[1].height, 20)
    eq(O.bid.list.frame.points[1][2], 16); eq(O.bid.list.frame.points[1][3], -184)
    eq(count(O.bid.list.rows), 13); eq(O.bid.list.rows[1].width, 350)
    eq(O.quick.width, 136); eq(O.quick.height, 70); eq(count(O.quickButtons), 6)
    for i, text in ipairs({"集", "散", "杀", "奖惩", "拍", "?"}) do eq(O.quickButtons[i]:GetText(), text) end
end)

test("classic tabs route commands and full width lists hide the left controls", function()
    local e = raiders(); local U, O = e.F.UI, e.F.Operations
    O.Show("settings"); eq(U.tab, "settings"); assert(U.left:IsShown())
    eq(U.tabs.settings:GetText(), "设置"); eq(U.tabs.logs:GetText(), "数据列表")
    eq(U.tabs.awards:GetText(), "奖惩"); eq(U.tabs.share:GetText(), "大小号"); eq(U.tabs.help:GetText(), "帮助")
    O.Show("logs"); eq(U.tab, "logs"); eq(U.left:IsShown(), false)
    O.Show("loot"); eq(U.tab, "logs"); eq(O.panels.logs.mode, "delivery")
    O.Show("share"); eq(U.left:IsShown(), false)
    O.Show("awards"); assert(U.left:IsShown()); assert(U.panels.awards:IsShown())
    eq(U.panels.logs:IsShown(), false)
    O.Show("queue"); eq(O.queue.points[1][2], O.bid); eq(O.queue.points[1][3], "TOPRIGHT")
end)

test("display separators never become ledger keys, whisper targets or export names", function()
    local e = client("张 三四")
    initial(e, "张三 四,WARRIOR,60\n张 三四,MAGE,20\nAbcdefghijkl Mnopqrstuvwx,PRIEST,40")
    local I, D, U = e.F.Identity, e.F.Data, e.F.UI
    eq(I.Display("张三 四"), "张三·四"); eq(I.Display("张 三四"), "张·三四")
    assert(I.Display("张三·四") ~= I.Display("张三 四"))
    assert(I.Key("张三 四") ~= I.Key("张 三四"))
    assert(I.Resolve("张三 四").id ~= I.Resolve("张 三四").id)
    eq(I.Target("张 三四"), "张 三四")
    assert(D.Award({"张三 四"}, -5, "检查空格", false))
    eq(D.Balance("张三 四"), 55); eq(D.Balance("张 三四"), 20)
    assert(string.find(D.ExportInitial(), "张三 四,WARRIOR,55", 1, true))
    assert(string.find(D.ExportActivity("compact"), "张三 四", 1, true))
    eq(string.find(D.ExportActivity("compact"), "张三·四", 1, true), nil)
    U.Toggle(); U.mode = "all"; U.Refresh()
    local names = {}; for _, row in ipairs(U.list.rows) do if row.value then names[row.value.name] = row.cells[1]:GetText() end end
    eq(names["张三 四"], "张三·四"); eq(names["张 三四"], "张·三四")
    U.search:SetText("张三·四"); eq(count(U.Rows()), 1); eq(U.Rows()[1].name, "张三 四")
end)

test("native unmodified name helper supplies exact target and never guesses a Chinese split", function()
    local e = client(); initial(e, "张三 四,WARRIOR,60\n张 三四,WARRIOR,20")
    e.units.target = {name = "张三 四", guid = "Player-Chinese-One", class = "WARRIOR"}
    e.NameUtil = {GetUnmodifiedUnitFullName = function(unit) return e.units[unit].name end}
    e.GetUnitName = function() return "张三四" end
    e.F.Command("c-5")
    eq(e.F.Data.Balance("张三 四"), 55); eq(e.F.Data.Balance("张 三四"), 20)
    e.F.Command("name"); assert(string.find(e.messages[count(e.messages)], "已精确匹配账本", 1, true))
    e.NameUtil.GetUnmodifiedUnitFullName = function() return {secret = true} end
    eq(e.F.Identity.FromUnit("target"), nil)
    e.NameUtil.GetUnmodifiedUnitFullName = function() error("restricted") end
    eq(e.F.Identity.FromUnit("target"), nil)
end)

test("missing separators are diagnosed but never auto-merged or assigned a balance", function()
    local e = client(); initial(e, "张三 四,WARRIOR,60\n张 三四,WARRIOR,20")
    local I = e.F.Identity
    assert(I.Register("张三四", "Player-Wrong"))
    local points = e.F.Data.Balance("张三四"); eq(points, nil)
    local before = count(e.F.Data.TeamRows())
    local message = I.Diagnose("张三四")
    assert(string.find(message, "张三·四", 1, true)); assert(string.find(message, "张·三四", 1, true))
    eq(e.F.Data.Award({"张三四"}, -10, "检查", false), nil)
    eq(count(e.F.Data.TeamRows()), before); eq(e.F.Data.Balance("张三 四"), 60); eq(e.F.Data.Balance("张 三四"), 20)
end)

test("selection toggles, filters and point changes use the same exact-name rows", function()
    local e = raiders(); local U = e.F.UI
    U.Toggle(); U.mode = "all"; U.search:SetText("Alpha Beta"); U.Refresh()
    local row = U.list.rows[1]; eq(row.value.name, "Alpha Beta")
    row.scripts.OnClick(row); assert(U.selected["Alpha Beta"]); assert(row.selection:IsShown())
    row.scripts.OnClick(row); eq(U.selected["Alpha Beta"], nil); eq(row.selection:IsShown(), false)
    U.SelectAll(true); U.points:SetText("5"); U.reason:SetText("选中调整"); U.AdjustSelected(-1)
    eq(e.F.Data.Balance("Alpha Beta"), 55); eq(e.F.Data.Balance("Alpha Gamma"), 20)
    U.classes.MAGE = false; U.Refresh(); eq(count(U.Rows()), 0)
    U.AdjustSelected(-1); eq(e.F.Data.Balance("Alpha Beta"), 55)
end)

test("classic quick presets keep raid/sub values and adjustment stays single target", function()
    local e = raiders(); local O = e.F.Operations
    O.Initialize(); O.Preset("rally", true)
    O.preset.raid:SetText("3"); O.preset.sub:SetText("1"); O.preset.reason:SetText("集合分")
    -- Find the save button by text, independent of its creation order.
    for _, child in ipairs(O.preset.children) do if child.text == "保存" then child.scripts.OnClick(child) end end
    eq(e.F.db.settings.presets.rally.raid, 3); eq(e.F.db.settings.presets.rally.sub, 1)
    O.Preset("rally"); eq(e.F.Data.Balance("Alpha Beta"), 63); eq(e.F.Data.Balance("Alpha Gamma"), 23)
    O.QuickAdjust(); O.adjust.player:SetText("Alpha Gamma"); O.adjust.points:SetText("2")
    for _, child in ipairs(O.adjust.children) do if child.text == "扣分" then child.scripts.OnClick(child) end end
    eq(e.F.Data.Balance("Alpha Gamma"), 21); eq(e.F.Data.Balance("Alpha Beta"), 63)
end)

test("manual add preserves full names and existing balances without silent duplicates", function()
    local e = client(); initial(e, "张三 四,WARRIOR,60")
    assert(e.F.Data.AddPlayer("张 三四", "MAGE")); eq(e.F.Data.Balance("张 三四"), 0)
    eq(e.F.Data.AddPlayer("张三 四", "MAGE"), nil); eq(e.F.Data.Balance("张三 四"), 60)
    e.F.Data.Recalculate(1); eq(e.F.Data.Balance("张三 四"), 60)
end)

test("data tabs keep raid/sub awards separate and recipient cells use visible boundaries", function()
    local e = client("张三 四"); initial(e, "张三 四,WARRIOR,60\n张 三四,MAGE,20")
    assert(e.F.Data.Award({"张三 四"}, 2, "集合分", false))
    assert(e.F.Data.Award({"张 三四"}, 1, "集合分-替补", false))
    local O = e.F.Operations; O.Show("logs"); local p = O.panels.logs
    p.mode = "raid"; O.Refresh(); eq(count(p.list.items), 1); eq(p.list.items[1].cells[2], "张三·四")
    p.mode = "sub"; O.Refresh(); eq(count(p.list.items), 1); eq(p.list.items[1].cells[2], "张·三四")
    assert(e.F.Loot.Record("Test Sword", "张三 四", 5))
    O.Show("loot"); eq(p.list.items[1].cells[2], "张三·四"); eq(p.list.items[1].cells[3], "5")
end)

test("WHISPER roster retains both Chinese names with different boundary positions", function()
    local leader, sub = client("主团 团长"), client("替补 队长")
    sub.groupSize = 3
    sub.units.party1 = {name = "张三 四", class = "WARRIOR", guid = "Player-Space-One"}
    sub.units.party2 = {name = "张 三四", class = "MAGE", guid = "Player-Space-Two"}
    assert(sub.F.Comm.Allow("主团 团长", true))
    assert(leader.F.Comm.SetCaptain("替补 队长")); assert(leader.F.Comm.Request())
    exchange(leader, sub)
    local cache = leader.F.db.sync.caches[1][leader.F.Identity.Key("替补 队长")]
    assert(cache and cache.verified); eq(count(cache.members), 3)
    local names = {}; for _, row in ipairs(cache.members) do names[row.name] = row.guid end
    eq(names["张三 四"], "Player-Space-One"); eq(names["张 三四"], "Player-Space-Two")
    assert(leader.F.Identity.Resolve("张三 四").id ~= leader.F.Identity.Resolve("张 三四").id)
end)

test("displayed share and auction rows operate on raw names rather than placeholder labels", function()
    local e = client("张三 四"); initial(e, "张三 四,WARRIOR,60\n张 三四,MAGE,20")
    local O, D, B = e.F.Operations, e.F.Data, e.F.Bidding
    assert(D.Bind("张三 四", "张 三四")); O.Show("share")
    local p = O.panels.share; local row = p.list.rows[1]
    eq(row.cells[1]:GetText(), "张·三四"); row.scripts.OnClick(row)
    eq(p.alt:GetText(), "张 三四"); eq(p.main:GetText(), "张三 四")
    assert(D.Unbind("张 三四"))
    B.Enqueue("Sword", 0, "public"); B.Submit("张三 四", 5, "CHAT_MSG_WHISPER"); B.Stop(); O.Show("auction")
    local bid = O.bid.list.rows[1]; eq(bid.cells[1]:GetText(), "张三·四"); bid.scripts.OnClick(bid)
    for _, child in ipairs(O.bid.children) do if child.text == "奖惩物品给玩家" then child.scripts.OnClick(child) end end
    assert(string.find(O.confirm.message:GetText(), "张三·四", 1, true)); assert(O.confirm.action())
    eq(D.Balance("张三 四"), 55); eq(D.Balance("张 三四"), 20)
end)

local function identityOnly()
    local e = client("加 百列")
    local saved = assert(loadfile(ROOT .. "/tests/fixtures/forever_identity_only.lua"))()
    for key, value in pairs(saved) do e[key] = value end
    assert(e.F.Initialize()); assert(e.F.Identity.IndexLedger()); e.F.Data.InitializeBases()
    e.units.player = {name = "加 百列", class = "WARRIOR", guid = "Player-6746-00387CF3"}
    e.units.party1 = {name = "梦醒 融化如雪", class = "MAGE", guid = "Player-6746-003C63AA"}
    e.units.target = e.units.player; e.groupSize = 2
    return e
end

test("reported identity-only save supports first target adjustment and preserves GUIDs", function()
    local e = identityOnly(); local D = e.F.Data
    eq(count(D.TeamRows()), 0); eq(D.Balance("加 百列"), nil)
    e.F.Command("c-5")
    eq(D.Balance("加 百列"), -5); eq(e.WebDKP_DkpTable["加 百列"].class, "WARRIOR")
    eq(e.F.Identity.Resolve("加 百列").id, "p1"); eq(e.F.Identity.Resolve("加 百列").guid, "Player-6746-00387CF3")
    eq(e.F.Identity.Resolve("梦醒 融化如雪").id, "p2"); eq(D.Balance("梦醒 融化如雪"), nil)
    e.F.Command("c2"); eq(D.Balance("加 百列"), -3)
    local reloaded = client()
    for _, key in ipairs({"ADKP_ForeverDB", "WebDKP_DkpTable", "WebDKP_Log", "ADKP_ShareSessionBase"}) do
        reloaded[key] = e.F.Copy(e[key])
    end
    assert(reloaded.F.Initialize()); assert(reloaded.F.Identity.IndexLedger()); reloaded.F.Data.InitializeBases()
    eq(reloaded.F.Data.Balance("加 百列"), -3)
    assert(reloaded.F.Data.Award({"加 百列"}, 1, "重载后", false)); eq(reloaded.F.Data.Balance("加 百列"), -2)
end)

test("reported pending award can finish after explicit roster enrollment without losing scores", function()
    local e = identityOnly(); local D = e.F.Data
    local id = "award:1792924843:1"
    eq(e.F.Awards.Apply(id), nil); eq(e.F.db.awards[id].state, "ready")
    e.F.Command("addgroup"); eq(count(D.TeamRows()), 2)
    eq(D.Balance("加 百列"), 0); eq(D.Balance("梦醒 融化如雪"), 0)
    assert(e.F.Awards.Apply(id)); eq(e.F.db.awards[id].state, "done")
    eq(D.Balance("加 百列"), 1); eq(D.Balance("梦醒 融化如雪"), 1)
    eq(D.AddGroup(), 0); eq(D.Balance("加 百列"), 1); eq(D.Balance("梦醒 融化如雪"), 1)
    assert(e.F.Awards.Apply(id)); eq(D.Balance("加 百列"), 1)
end)

test("first target award validates permissions values and native identity before creating a balance", function()
    local e = identityOnly(); local D = e.F.Data
    e.leader = false; eq(D.AdjustUnit("target", 5, "测试"), nil); eq(count(D.TeamRows()), 0)
    e.leader = true
    eq(D.AdjustUnit("target", "bad", "测试"), nil); eq(count(D.TeamRows()), 0)
    eq(D.AdjustUnit("target", 5, "bad\nreason"), nil); eq(count(D.TeamRows()), 0)
    e.UnitIsPlayer = function() return false end
    eq(D.AdjustUnit("target", 5, "测试"), nil); eq(count(D.TeamRows()), 0)
    e.UnitIsPlayer = function() return true end
    e.units.target = {name = "加 百列", class = "WARRIOR", guid = "Player-Conflicting"}
    eq(D.AdjustUnit("target", 5, "测试"), nil); eq(count(D.TeamRows()), 0)
    e.units.target = {name = "加 百列", class = {secret = true}, guid = "Player-6746-00387CF3"}
    eq(D.AdjustUnit("target", 5, "测试"), nil); eq(count(D.TeamRows()), 0)
    e.units.target = {name = "张三 四", class = "MAGE", guid = "Player-New"}
    assert(D.AddPlayer("张 三四", "WARRIOR"))
    assert(D.AdjustUnit("target", 3, "测试")); eq(D.Balance("张三 四"), 3); eq(D.Balance("张 三四"), 0)
end)

test("quick adjustment creates only an exact live target and manual addition gives visible feedback", function()
    local e = identityOnly(); local O, D, U = e.F.Operations, e.F.Data, e.F.UI
    e.F.db.settings.quickPoints = -2
    e.F.db.settings.quickPlayer = "加 百列"
    assert(O.Adjust()); eq(D.Balance("加 百列"), -2)
    e.F.db.settings.quickPlayer = "未知 玩家"
    eq(O.Adjust(), nil); eq(D.Balance("未知 玩家"), nil)
    e.units.target = e.units.party1
    U.Toggle(); U.newName:SetText("")
    local filters = U.newName.parent
    for _, child in ipairs(filters.children) do if child.text == "添加玩家" then child.scripts.OnClick(child) end end
    eq(D.Balance("梦醒 融化如雪"), 0); eq(U.mode, "all")
    assert(string.find(e.messages[count(e.messages)], "零分记录", 1, true))
    e.F.Command("add"); eq(D.Balance("梦醒 融化如雪"), 0)
end)

test("bulk enrollment is atomic and preserves existing points in every team", function()
    local e = identityOnly(); local D = e.F.Data
    assert(D.AddPlayer("加 百列", "WARRIOR")); assert(D.Award({"加 百列"}, 60, "已有分数", false))
    e.WebDKP_DkpTable["加 百列"].dkp_2 = 90
    local identityCount = e.F.db.identity.nextID
    eq(D.AddPlayers({{name = "新 玩家", class = "MAGE"}, {name = "坏 玩家", class = ""}}), nil)
    eq(e.F.Identity.Resolve("新 玩家"), nil); eq(e.F.db.identity.nextID, identityCount)
    eq(count(D.TeamRows()), 1); eq(D.Balance("加 百列"), 60)
    eq(D.AddGroup(), 1); eq(D.Balance("加 百列"), 60); eq(D.Balance("加 百列", 2), 90)
    eq(D.AddGroup(), 0); D.Recalculate(1); eq(D.Balance("加 百列"), 60)
end)

print("Forever scenarios passed: " .. passed)
