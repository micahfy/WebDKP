local login = ADKP_ForeverNativeEvents:GetScript("OnEvent")
login(ADKP_ForeverNativeEvents,"PLAYER_LOGIN")
assert(ADKP_Frame and ADKP_BidFrame)
print("PASS all cloned Lua modules and XML OnLoad handlers constructed")
local passed=1
local function test(name,fn) fn(); passed=passed+1; print("PASS "..name) end
local function eq(a,b) assert(a==b,"expected "..tostring(b)..", got "..tostring(a)) end
local function accept()
    local info=StaticPopupDialogs[LAST_POPUP]
    assert(info and info.OnAccept,"confirmation expected")
    info.OnAccept(StaticPopup1)
end
test("client API gaps do not abort bidding or inherited input initialization",function()
    eq(math.randomseed,nil)
    for _,name in ipairs({"ADKP_Bid_HandleBid","ADKP_Bid_StopBid","ADKP_Bid_PassButtonClick","ADKP_Bid_AwardSelected","ADKP_Bid_StartAnonTicker"}) do
        eq(type(_G[name]),"function")
    end
    local inputs=0
    for _,frame in ipairs(FRAMES) do
        if frame.ADKP_InitializeEditBox then
            inputs=inputs+1
            assert(frame.backdrop and frame.backdrop.bgFile)
            assert(frame.backdropColor and frame.backdropBorderColor)
        end
    end
    eq(inputs,19)
    for _,frame in ipairs({ADKP_BidFrameItem,ADKP_BidFrameTime,ADKP_AwardFrameCost}) do
        eq(frame.backdropColor[4],0.6); eq(frame.backdropBorderColor[1],0.5)
    end
end)
test("original dimensions and original tab controls are retained",function()
    eq(ADKP_Frame:GetWidth(),800); eq(ADKP_Frame:GetHeight(),500)
    eq(ADKP_BidFrame:GetWidth(),400); eq(ADKP_BidFrame:GetHeight(),500)
    assert(ADKP_FrameTab1 and ADKP_FrameTab2 and ADKP_FrameTab3 and ADKP_FrameTab4 and ADKP_FrameTab6)
    assert(not ADKP_BidFrameTransmog and not ADKP_SettingsBackupButton and not ADKP_AwardDKP_FrameToggleKeepOnline)
end)
test("native names auto-enroll through original roster and target award flow",function()
    assert(WebDKP_DkpTable["加 百列"]); assert(WebDKP_DkpTable["梦醒 融化如雪"])
    eq(WebDKP_DkpTable["加 百列"].dkp_1,0)
    ADKP_SlashCmdHandler("c-5"); accept()
    eq(ADKP_GetDKP("加 百列"),-5); eq(ADKP_GetDKP("梦醒 融化如雪"),0)
    assert(ADKP_BuildActivityCSV(false):find("加 百列",1,true))
end)
test("quoted manual additions keep Chinese surname boundaries distinct",function()
    ADKP_SlashCmdHandler('tj "张三 四" 战士 60')
    ADKP_SlashCmdHandler('tj "张 三四" 法师 20')
    eq(ADKP_GetDKP("张三 四"),60); eq(ADKP_GetDKP("张 三四"),20)
    ADKP_AddDKP(-5,"边界测试","false",{{name="张三 四",class="战士"}})
    eq(ADKP_GetDKP("张三 四"),55); eq(ADKP_GetDKP("张 三四"),20)
end)
test("native callback scopes are nested and restored after exceptions",function()
    local previousThis,previousArg,previousEvent=this,arg1,event
    local frame=ADKP_CreateFrame("Frame")
    frame:SetScript("OnClick",function()
        eq(this,frame); eq(arg1,"RightButton")
        local inner=ADKP_CreateFrame("Frame")
        inner:SetScript("OnUpdate",function() eq(this,inner); eq(arg1,0.2); error("expected test error") end)
        local ok=pcall(inner:GetScript("OnUpdate"),inner,0.2); eq(ok,false)
        eq(this,frame); eq(arg1,"RightButton")
    end)
    frame:GetScript("OnClick")(frame,"RightButton")
    eq(this,previousThis); eq(arg1,previousArg); eq(event,previousEvent)
end)
test("the original quick float and its settings still construct",function()
    RAID=true; UNITS.raid1=UNITS.player; UNITS.raid2=UNITS.party1
    WebDKP_Options.QuickFloatEnabled=true; ADKP_QuickFloat_UpdateVisibility()
    assert(ADKP_QuickFloatFrame); eq(ADKP_QuickFloatFrame:GetWidth(),136)
    RAID=false
end)

test("quick bid includes white and green items with modern loot slot fields",function()
    local numLoot,slotInfo,slotLink=GetNumLootItems,GetLootSlotInfo,GetLootSlotLink
    local oldFilter=WebDKP_Options.QuickBidQualityFilter
    local white="|cffffffff|Hitem:1001:0:0|h[白色物品]|h|r"
    local green="|cff1eff00|Hitem:1002:0:0|h[绿色物品]|h|r"
    WebDKP_Options.QuickBidQualityFilter={legendary=false,epic=false,rare=false,uncommon=false,common=false}
    ADKP_QuickBid_ShowQualitySettings()
    for _,check in ipairs(ADKP_QuickBidQualityFrame.checks) do check:SetChecked(true); check:Click() end
    GetNumLootItems=function() return 2 end
    GetLootSlotLink=function(slot) return slot==1 and white or green end
    GetLootSlotInfo=function(slot) return 123,"测试物品",1,nil,(slot==1 and 1 or 2),false end
    local events=ADKP_Frame:GetScript("OnEvent")
    events(ADKP_Frame,"LOOT_OPENED",false,false)
    local button=ADKP_QuickFloatFrame.bidBtn
    button:Click("LeftButton")
    assert(ADKP_Bid_IsInProgress(),"all checked qualities must start bidding for white and green loot")
    eq(ADKP_BidFrameItem:GetText(),white)
    eq(table.getn(ADKP_BidQueue),1); eq(ADKP_BidQueue[1].item,green)
    ADKP_Bid_StopBid(true); ADKP_BidQueue={}
    WebDKP_Options.QuickBidQualityFilter.common=false
    button:Click("LeftButton")
    assert(ADKP_Bid_IsInProgress()); eq(ADKP_BidFrameItem:GetText(),green)
    eq(table.getn(ADKP_BidQueue),0)
    ADKP_Bid_StopBid(true)
    GetNumLootItems,GetLootSlotInfo,GetLootSlotLink=numLoot,slotInfo,slotLink
    WebDKP_Options.QuickBidQualityFilter=oldFilter
    events(ADKP_Frame,"LOOT_CLOSED")
end)
test("original bidding accepts full-name bids and keeps queue UI",function()
    ADKP_Bid_ShowUI()
    for i=1,13 do
        local row=_G["ADKP_BidFrameLine"..i]
        assert(not row:IsShown(),"empty auction must not display template rows")
        for _,column in ipairs({"Name","Bid","DKP","Post"}) do
            eq(_G[row:GetName()..column]:GetText() or "","")
        end
    end
    ADKP_Bid_StartBid("Test Sword",30)
    assert(ADKP_Bid_IsInProgress())
    ADKP_Bid_HandleBid("张三 四",5)
    eq(ADKP_Bid_GetHighestBid(),"张三 四")
    assert(ADKP_BidFrameLine1:IsShown()); eq(ADKP_RowName(ADKP_BidFrameLine1),"张三 四")
    eq(ADKP_BidFrameLine1Name:GetText(),"张三·四"); eq(ADKP_BidFrameLine1Bid:GetText(),"5.00")
    for i=2,13 do assert(not _G["ADKP_BidFrameLine"..i]:IsShown()) end
    ADKP_BidFrameScrollFrame.offset=99
    ADKP_Bid_HideUI(); ADKP_Bid_ShowUI()
    eq(ADKP_FauxGetOffset(ADKP_BidFrameScrollFrame),0)
    assert(ADKP_BidFrameLine1:IsShown()); eq(ADKP_RowName(ADKP_BidFrameLine1),"张三 四")
    ADKP_Bid_StopBid()
    ADKP_Bid_StartBid("Next Sword",0)
    assert(not ADKP_BidFrameLine1:IsShown())
    eq(ADKP_BidFrameLine1Name:GetText(),""); eq(ADKP_BidFrameLine1Name.ADKP_RawName,nil)
    ADKP_Bid_StopBid()
    ADKP_Bid_ShowUI(); ADKP_CreateBidQueueWindow()
    assert(ADKP_BidQueueWindow)
end)

test("modern hover motion flags preserve full-name lookup and selected highlights",function()
    local row=ADKP_FrameLine1
    local player=WebDKP_DkpTable["张三 四"]
    local selected=player.Selected
    ADKP_SetNameText(ADKP_FrameLine1Name,"张三 四")
    local function hover(frame,background)
        for _,motion in ipairs({true,false}) do
            frame:GetScript("OnEnter")(frame,motion)
            eq(background.vertexColor[4],0.5)
            frame:GetScript("OnLeave")(frame,motion)
            eq(background.vertexColor[4],0)
        end
        frame:GetScript("OnEnter")(frame)
        eq(background.vertexColor[4],0.5)
        assert(GameTooltip:GetText():find("张三 四",1,true))
        frame:GetScript("OnLeave")(frame)
        eq(background.vertexColor[4],0)
    end
    local function selectedHover(frame,background)
        background:SetVertexColor(0.1,0.1,0.9,0.8)
        frame:GetScript("OnEnter")(frame,true)
        frame:GetScript("OnLeave")(frame,true)
        eq(background.vertexColor[4],0.8)
    end
    player.Selected=false; hover(row,ADKP_FrameLine1Background)
    player.Selected=true; selectedHover(row,ADKP_FrameLine1Background)
    player.Selected=selected; ADKP_UpdateTable()
    ADKP_Bid_StartBid("Hover Sword",0); ADKP_Bid_HandleBid("张三 四",5)
    hover(ADKP_BidFrameLine1,ADKP_BidFrameLine1Background)
    ADKP_BidFrameLine1:GetScript("OnMouseDown")(ADKP_BidFrameLine1,"LeftButton")
    selectedHover(ADKP_BidFrameLine1,ADKP_BidFrameLine1Background)
    eq(ADKP_Bid_GetSelected(),"张三 四")
    ADKP_Bid_StopBid()
end)
test("ordinary whispers cannot inject substitute data",function()
    ADKP_HandleSubWhisperData("加 百列","ADKP: SUB:伪造 玩家:战")
    local pending=ADKP_PendingSubMembers and ADKP_PendingSubMembers["加 百列"]
    assert(not pending or not pending["伪造 玩家"])
end)

test("native chat and auction buttons drive the whole auction",function()
    assert(ADKP_Frame.events.CHAT_MSG_RAID)
    ADKP_Bid_HideUI()
    local onEvent=ADKP_Frame:GetScript("OnEvent")
    onEvent(ADKP_Frame,"CHAT_MSG_RAID_LEADER","·[Test Sword]","加 百列","通用语")
    assert(ADKP_Bid_IsInProgress(),"chat start must open an auction")
    assert(ADKP_BidFrame:IsShown(),"chat start must show auction window")
    onEvent(ADKP_Frame,"CHAT_MSG_RAID","6","张三 四","通用语")
    eq(ADKP_Bid_GetHighestBid(),"张三 四")
    ADKP_BidFrameBidButton:Click("LeftButton")
    assert(not ADKP_Bid_IsInProgress(),"XML stop button must stop auction")
    ADKP_BidFrameBidButton:Click("LeftButton")
    assert(ADKP_Bid_IsInProgress(),"XML start button must start auction")
    ADKP_BidFramePass:Click("RightButton")
    assert(ADKP_BidPassMenu,"right click must open pass menu")
    ADKP_BidFramePass:Click("LeftButton")
    assert(not ADKP_Bid_IsInProgress(),"left click must record a passed item and stop auction")
    onEvent(ADKP_Frame,"CHAT_MSG_RAID_LEADER","·[Award Sword]","加 百列","通用语")
    onEvent(ADKP_Frame,"CHAT_MSG_RAID","10","张三 四","通用语")
    ADKP_BidFrameLine1:GetScript("OnMouseDown")(ADKP_BidFrameLine1,"LeftButton")
    eq(ADKP_Bid_GetSelected(),"张三 四")
    local before=ADKP_GetDKP("张三 四")
    ADKP_BidFrameAward:Click("LeftButton")
    eq(ADKP_GetDKP("张三 四"),before-10)
    assert(not ADKP_Bid_IsInProgress()); assert(not ADKP_BidFrame:IsShown())
end)
test("base client globals are not replaced by the cloned addon",function()
    eq(UnitName("player"),"Wrong first"); assert(not GetNumRaidMembers)
    assert(not SendAddonMessage); assert(HOOKS.SetItemRef)
    assert(FILTERS.CHAT_MSG_WHISPER)
end)

test("chat metadata does not discard readable auction commands",function()
    ADKP_Bid_HideUI()
    local onEvent=ADKP_Frame:GetScript("OnEvent")
    onEvent(ADKP_Frame,"CHAT_MSG_RAID_LEADER","·[Metadata Sword]","加 百列","通用语","","","",0,0,"",0,1,{secret=true})
    assert(ADKP_Bid_IsInProgress(),"unneeded restricted metadata must not discard readable chat")
    onEvent(ADKP_Frame,"CHAT_MSG_RAID","7","张 三四","通用语","","","",0,0,"",0,2,{secret=true})
    eq(ADKP_Bid_GetHighestBid(),"张 三四")
    onEvent(ADKP_Frame,"CHAT_MSG_RAID",{secret=true},"张 三四")
    eq(ADKP_Bid_GetHighestBid(),"张 三四")
    ADKP_BidFrameBidButton:Click("LeftButton")
    assert(not ADKP_Bid_IsInProgress())
    assert(ADKP_Frame.events.CHAT_MSG_PARTY_LEADER,"party leader messages must be registered")
    onEvent(ADKP_Frame,"CHAT_MSG_PARTY_LEADER","·[Party Sword]","加 百列","通用语")
    assert(ADKP_Bid_IsInProgress()); assert(ADKP_BidFrame:IsShown())
    ADKP_BidFrameBidButton:Click("LeftButton")
end)

test("auction entry tolerates item lookup failures and resolves full chat names by GUID",function()
    local query=C_Item.GetItemInfo
    C_Item.GetItemInfo=function() error("uncached item query failed") end
    ADKP_BidFrameItem:SetText("Uncached Sword"); ADKP_BidFrameTime:SetText("0")
    ADKP_BidFrameBidButton:Click("LeftButton")
    assert(ADKP_Bid_IsInProgress()); assert(ADKP_BidFrame:IsShown())
    ADKP_BidFrameBidButton:Click("LeftButton"); assert(not ADKP_Bid_IsInProgress())
    ADKP_BidFramePass:Click("LeftButton"); assert(not ADKP_BidFrame:IsShown())
    assert(ADKP_ForeverLastItemError)
    C_Item.GetItemInfo=query
    ADKP_ForeverLastItemError=nil
    ADKP_Frame:GetScript("OnEvent")(ADKP_Frame,"CHAT_MSG_RAID_LEADER","·[GUID Sword]","加 百列-Test","通用语","","","",0,0,"",0,10,UNITS.player.guid)
    assert(ADKP_Bid_IsInProgress()); assert(ADKP_BidFrame:IsShown())
    eq(ADKP_ForeverChatAuthor("加 百列-Test",UNITS.player.guid),"加 百列")
    eq(ADKP_ForeverChatAuthor("张 三四",nil),"张 三四")
    ADKP_BidFrameBidButton:Click("LeftButton")
end)
test("original data help and share tabs open through their XML callbacks",function()
    ADKP_FrameTab2:Click(); assert(ADKP_LootListFrame and ADKP_LootListFrame:IsShown())
    ADKP_FrameTab3:Click(); assert(ADKP_HelpPanel)
    ADKP_FrameTab4:Click(); assert(ADKP_ShareGroupsFrame)
    ADKP_FrameTab1:Click(); assert(ADKP_AwardDKP_Frame:IsShown())
end)
test("original import and export dialogs construct with modern callbacks",function()
    ADKP_ShowImportInitial(); assert(ADKP_ImportInitialEdit)
    ADKP_ShowExportRecords(); assert(ADKP_ExportRecordsFrame)
    assert(ADKP_BuildExportText():find("加 百列",1,true))
end)
test("native official boss signals deduplicate and keep the original award popup",function()
    WebDKP_Options.BossDeathPopup=true; WebDKP_Options.BossAutoAward=false
    local event=ADKP_ForeverNativeEvents:GetScript("OnEvent")
    event(ADKP_ForeverNativeEvents,"ENCOUNTER_START",90001,"测试首领")
    event(ADKP_ForeverNativeEvents,"ENCOUNTER_END",90001,"测试首领",1,2,1)
    local active=ADKP_BossEncounterState.active; assert(active and active.bossName=="测试首领")
    local queued=table.getn(ADKP_BossEncounterState.queue)
    event(ADKP_ForeverNativeEvents,"BOSS_KILL",90001,"测试首领")
    eq(table.getn(ADKP_BossEncounterState.queue),queued)
    event(ADKP_ForeverNativeEvents,"ENCOUNTER_END",90002,"失败首领",1,2,0)
    eq(table.getn(ADKP_BossEncounterState.queue),queued)
    assert(ADKP_BossKillAwardFrame:IsShown())
end)
test("slot specific native loot assignment waits for evidence and rejects duplicates",function()
    local link="|cffa335ee|Hitem:123:0:0|h[测试装备]|h|r"
    local assigned
    GetNumLootItems=function() return 1 end
    GetLootSlotLink=function(slot) if slot==1 then return link end end
    GetMasterLootCandidate=function(slot,i) eq(slot,1); if i==2 then return "梦醒 融化如雪" end end
    GiveMasterLoot=function(slot,i) assigned={slot,i} end
    local state=ADKP_AutoLootData
    state.isAssigning=true; state.awaitingResult=false; state.currentItemLink=link
    state.currentPlayer="梦醒 融化如雪"; state.currentItem="测试装备"
    ADKP_TryAssignLoot(); eq(assigned[1],1); eq(assigned[2],2); assert(state.awaitingResult)
    assigned=nil; ADKP_TryAssignLoot(); eq(assigned,nil)
    local pending=table.getn(ADKP_UnassignedLoot)
    state.awaitingResult=false
    GiveMasterLoot=function() return false end
    ADKP_TryAssignLoot()
    assert(not state.isAssigning); eq(table.getn(ADKP_UnassignedLoot),pending+1)
end)
test("name labels retain raw identities for old row selection handlers",function()
    local row=ADKP_CreateFrame("Button","NameBoundaryTest")
    local name=row:CreateFontString("NameBoundaryTestName")
    ADKP_SetNameText(name,"张三 四"); eq(name:GetText(),"张三·四"); eq(ADKP_RowName(row),"张三 四")
    ADKP_SetNameText(name,"张 三四"); eq(name:GetText(),"张·三四"); eq(ADKP_RowName(row),"张 三四")
end)
test("modern popup edit boxes retain original create-team confirmation behavior",function()
    local dialog=CreateFrame("Frame","ModernPopup")
    dialog.editBox=CreateFrame("EditBox",nil,dialog); dialog.editBox:SetText("测试二团")
    eq(ADKP_PopupEditBox(dialog),dialog.editBox)
    ADKP_ShowCreateTableDialog()
    StaticPopupDialogs.ADKP_CREATE_TABLE.OnAccept(dialog)
    local found=false
    for _,entry in pairs(WebDKP_Tables) do if type(entry)=="table" and entry.name=="测试二团" then found=true end end
    assert(found)
    ADKP_Frame.selectedTableid=1; WebDKP_Options.SelectedTableId=1
end)
test("private faux and text scrolling operate without deleted client templates",function()
    local faux=ADKP_CreateFrame("ScrollFrame","ADKP_PrivateFauxTest",UIParent,"FauxScrollFrameTemplate")
    local updates=0
    faux:SetScript("OnVerticalScroll",function() ADKP_FauxVerticalScroll(20,function() updates=updates+1 end) end)
    ADKP_FauxUpdate(faux,40,14,20); ADKP_ScrollWheel(faux,-3)
    eq(ADKP_FauxGetOffset(faux),3); eq(updates,1)
    ADKP_FauxUpdate(faux,1,14,20); eq(ADKP_FauxGetOffset(faux),0)
    local text=ADKP_CreateFrame("ScrollFrame","ADKP_PrivateTextTest",UIParent,"UIPanelScrollFrameTemplate")
    ADKP_ScrollRangeChanged(text,0,200); ADKP_ScrollWheel(text,-2); eq(text:GetVerticalScroll(),48)
end)
test("restricted roster abort reports failure to the original award queue",function()
    local previous=UNITS.party1
    UNITS.party1={name=nil,class="MAGE"}
    local called=false
    eq(ADKP_RunRaidAndSubAward(1,1,"测试",nil,function(success) called=true; eq(success,false) end),false)
    assert(called); UNITS.party1=previous
end)
test("modern loot enums and raid-only master looter indices preserve permissions",function()
    eq(GetLootMethod,nil)
    local query,raid,raid2=C_PartyInfo.GetLootMethod,RAID,UNITS.raid2
    C_PartyInfo.GetLootMethod=function() return Enum.LootMethod.Masterlooter,nil,2 end
    RAID=true; UNITS.raid2=UNITS.player
    eq(ADKP_GetLootMethod(),"master"); eq(ADKP_IsMasterLooter(),true)
    UNITS.raid2=UNITS.party1; eq(ADKP_IsMasterLooter(),false)
    C_PartyInfo.GetLootMethod=function() return Enum.LootMethod.Masterlooter,0,nil end
    eq(ADKP_IsMasterLooter(),true)
    C_PartyInfo.GetLootMethod=function() return Enum.LootMethod.Group,nil,nil end
    eq(ADKP_IsMasterLooter(),false)
    C_PartyInfo.GetLootMethod=function() return {secret=true},nil,nil end
    eq(ADKP_IsMasterLooter(),false)
    C_PartyInfo.GetLootMethod=nil; eq(ADKP_IsMasterLooter(),false)
    C_PartyInfo.GetLootMethod=function() error("query unavailable") end
    eq(ADKP_IsMasterLooter(),false)
    C_PartyInfo.GetLootMethod,RAID,UNITS.raid2=query,raid,raid2
end)

test("award records once and retries delivery using modern master loot permissions",function()
    local link="|cff1eff00|Hitem:123:0:0|h[测试装备]|h|r"
    local other="|cffa335ee|Hitem:456:0:0|h[测试装备]|h|r"
    local query,itemQuery=C_PartyInfo.GetLootMethod,C_Item.GetItemInfo
    local numLoot,slotLink,candidate,give=GetNumLootItems,GetLootSlotLink,GetMasterLootCandidate,GiveMasterLoot
    local slotInfo=GetLootSlotInfo
    local raid,raid2,autofill=RAID,UNITS.raid2,WebDKP_Options.AutofillEnabled
    RAID=true; UNITS.raid2=UNITS.player; WebDKP_Options.AutofillEnabled=0
    C_PartyInfo.GetLootMethod=function() return Enum.LootMethod.Masterlooter,nil,2 end
    C_Item.GetItemInfo=function(item)
        if item==link then return "测试装备",(link:gsub("item:123:0:0","item:123:9:0")),2,60,60,"Armor","Plate",1,"",123 end
        return nil -- A localized item name is not a reliable item-link lookup.
    end
    GetNumLootItems=function() return 1 end
    GetLootSlotLink=function(slot) if slot==1 then return link end end
    GetLootSlotInfo=function() return 123,"测试装备",1,0,2 end
    GetMasterLootCandidate=function(slot,i) eq(slot,1); if i==17 then return "张三 四" end end
    local calls=0
    GiveMasterLoot=function(slot,i) eq(slot,1); eq(i,17); calls=calls+1 end
    local function records()
        local count=0
        for _,entry in pairs(WebDKP_Log) do if type(entry)=="table" and entry.foritem=="true" then count=count+1 end end
        return count
    end
    local function auction(points)
        ADKP_Bid_StartBid(link,0); ADKP_Bid_HandleBid("张三 四",points)
        ADKP_Bid_StopBid(true)
        ADKP_BidFrameLine1:GetScript("OnMouseDown")(ADKP_BidFrameLine1,"LeftButton")
        eq(ADKP_Bid_GetSelected(),"张三 四")
        ADKP_BidFrameAward:Click("LeftButton")
    end
    local state=ADKP_AutoLootData
    local before,logs,pending=ADKP_GetDKP("张三 四"),records(),table.getn(ADKP_UnassignedLoot)
    auction(5)
    eq(ADKP_GetDKP("张三 四"),before-5); eq(records(),logs+1); eq(calls,1)
    assert(state.isAssigning and state.awaitingResult)
    ADKP_Bid_ShowUI(); ADKP_BidFrameAward:Click("LeftButton")
    eq(ADKP_GetDKP("张三 四"),before-5); eq(records(),logs+1); eq(calls,1)
    local onEvent=ADKP_Frame:GetScript("OnEvent")
    onEvent(ADKP_Frame,"CHAT_MSG_LOOT","张 三四获得了物品："..link.."。")
    assert(state.isAssigning)
    onEvent(ADKP_Frame,"CHAT_MSG_LOOT","张三 四获得了物品："..other.."。")
    assert(state.isAssigning)
    onEvent(ADKP_Frame,"CHAT_MSG_LOOT","张三 四获得了物品："..link.."。")
    assert(not state.isAssigning,"full-name loot receipt must complete delivery")
    eq(table.getn(ADKP_UnassignedLoot),pending)
    GiveMasterLoot=nil
    auction(6)
    eq(ADKP_GetDKP("张三 四"),before-11); eq(records(),logs+2)
    assert(not state.isAssigning); eq(table.getn(ADKP_UnassignedLoot),pending+1)
    local entry=ADKP_UnassignedLoot[table.getn(ADKP_UnassignedLoot)]
    assert(entry.recordRef); eq(entry.player,"张三 四")
    ADKP_RetryUnassignedLoot(entry.id)
    eq(ADKP_GetDKP("张三 四"),before-11); eq(records(),logs+2)
    assert(not entry.retrying)
    GiveMasterLoot=function(slot,i) eq(slot,1); eq(i,17); calls=calls+1 end
    ADKP_RetryUnassignedLoot(entry.id)
    assert(state.isAssigning and state.awaitingResult); eq(calls,2)
    onEvent(ADKP_Frame,"CHAT_MSG_LOOT","张三 四获得了物品："..link.."。")
    assert(not state.isAssigning)
    for _,pendingEntry in ipairs(ADKP_UnassignedLoot) do assert(pendingEntry.id~=entry.id) end
    eq(ADKP_GetDKP("张三 四"),before-11); eq(records(),logs+2)
    -- Repair an old name-only delivery entry without charging or logging again.
    local oldID=ADKP_AddUnassignedLoot("测试装备","张三 四","需要手动交付",nil,entry.recordRef)
    ADKP_RetryUnassignedLoot(oldID)
    assert(state.isAssigning and state.awaitingResult); eq(calls,3)
    eq(state.currentItemLink,link)
    onEvent(ADKP_Frame,"CHAT_MSG_LOOT","张三 四获得了物品："..link.."。")
    for _,pendingEntry in ipairs(ADKP_UnassignedLoot) do assert(pendingEntry.id~=oldID) end
    eq(ADKP_GetDKP("张三 四"),before-11); eq(records(),logs+2)
    C_PartyInfo.GetLootMethod,C_Item.GetItemInfo=query,itemQuery
    GetNumLootItems,GetLootSlotLink,GetMasterLootCandidate,GiveMasterLoot=numLoot,slotLink,candidate,give
    GetLootSlotInfo=slotInfo
    RAID,UNITS.raid2,WebDKP_Options.AutofillEnabled=raid,raid2,autofill
end)

test("white loot below the actual threshold records once and explains manual delivery",function()
    local link="|cffffffff|Hitem:789:0:0|h[测试白色装备]|h|r"
    local query,itemQuery=C_PartyInfo.GetLootMethod,C_Item.GetItemInfo
    local numLoot,slotLink,slotInfo,threshold=GetNumLootItems,GetLootSlotLink,GetLootSlotInfo,GetLootThreshold
    local candidate,give=GetMasterLootCandidate,GiveMasterLoot
    local raid,raid2,autofill=RAID,UNITS.raid2,WebDKP_Options.AutofillEnabled
    RAID=true; UNITS.raid2=UNITS.player; WebDKP_Options.AutofillEnabled=0
    C_PartyInfo.GetLootMethod=function() return Enum.LootMethod.Masterlooter,nil,2 end
    C_Item.GetItemInfo=function(item) if item==link then return "测试白色装备",link,1,60,60,"Armor","Plate",1,"",123 end end
    GetNumLootItems=function() return 1 end
    GetLootSlotLink=function() return link end
    GetLootSlotInfo=function() return 123,"测试白色装备",1,999,1 end
    GetLootThreshold=function() return 2 end
    GetMasterLootCandidate=function() error("below-threshold items must not query candidates") end
    GiveMasterLoot=function() error("below-threshold items must not call native assignment") end
    local before,pending=ADKP_GetDKP("张三 四"),table.getn(ADKP_UnassignedLoot)
    ADKP_Bid_StartBid(link,0); ADKP_Bid_HandleBid("张三 四",4); ADKP_Bid_StopBid(true)
    ADKP_BidFrameLine1:GetScript("OnMouseDown")(ADKP_BidFrameLine1,"LeftButton")
    ADKP_BidFrameAward:Click("LeftButton")
    eq(ADKP_GetDKP("张三 四"),before-4)
    eq(table.getn(ADKP_UnassignedLoot),pending+1)
    local entry=ADKP_UnassignedLoot[pending+1]
    eq(entry.reason,"低于分配阈值")
    assert(entry.rawError:find("白色",1,true) and entry.rawError:find("绿色",1,true))
    local row=ADKP_UnassignedLootFrame.rows[1]
    ADKP_UnassignedLootPage=math.ceil((pending+1)/ADKP_UNASSIGNED_PAGE_SIZE)
    ADKP_UpdateUnassignedLootWindow()
    for _,current in ipairs(ADKP_UnassignedLootFrame.rows) do if current.pendingId==entry.id then row=current end end
    row:GetScript("OnEnter")(row,true)
    assert(GameTooltip:GetText():find(entry.rawError,1,true))
    row:GetScript("OnLeave")(row,true)
    ADKP_RetryUnassignedLoot(entry.id)
    eq(ADKP_GetDKP("张三 四"),before-4); eq(table.getn(ADKP_UnassignedLoot),pending+1)
    eq(entry.reason,"低于分配阈值"); assert(not entry.retrying)
    -- Never invent a threshold when the client does not expose a readable value.
    GetLootThreshold=nil; eq(ADKP_ForeverLootThreshold(),nil)
    GetLootThreshold=function() return {secret=true} end; eq(ADKP_ForeverLootThreshold(),nil)
    GetLootThreshold=function() error("unavailable") end; eq(ADKP_ForeverLootThreshold(),nil)
    ADKP_RemoveUnassignedLoot(entry.id)
    C_PartyInfo.GetLootMethod,C_Item.GetItemInfo=query,itemQuery
    GetNumLootItems,GetLootSlotLink,GetLootSlotInfo,GetLootThreshold=numLoot,slotLink,slotInfo,threshold
    GetMasterLootCandidate,GiveMasterLoot=candidate,give
    RAID,UNITS.raid2,WebDKP_Options.AutofillEnabled=raid,raid2,autofill
end)

test("name-only delivery resolution refuses different loot variants sharing a name",function()
    local numLoot,slotLink=GetNumLootItems,GetLootSlotLink
    local first="|cff1eff00|Hitem:321:0:0|h[同名装备]|h|r"
    local second="|cff1eff00|Hitem:321:9:0|h[同名装备]|h|r"
    GetNumLootItems=function() return 2 end
    GetLootSlotLink=function(slot) return slot==1 and first or second end
    eq(ADKP_ForeverResolveLootLink(first),first)
    local resolved,reason=ADKP_ForeverResolveLootLink("同名装备")
    eq(resolved,nil); assert(reason:find("同名但不同",1,true))
    GetLootSlotLink=function() return first end
    eq(ADKP_ForeverResolveLootLink("[同名装备]"),first)
    GetNumLootItems,GetLootSlotLink=numLoot,slotLink
end)
print("Cloned Forever scenarios passed: "..passed)
