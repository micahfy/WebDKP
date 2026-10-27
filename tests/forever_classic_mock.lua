NOW, MESSAGES, SENT, CHAT, FRAMES, FILTERS, HOOKS = 0, {}, {}, {}, {}, {}, {}
math.randomseed = nil -- Not exposed by the actual 1.60 client.
VALID_TEMPLATES={BackdropTemplate=true,UIPanelButtonTemplate=true,UIPanelCloseButton=true,UIDropDownMenuTemplate=true,GameTooltipTemplate=true}
SlashCmdList, UISpecialFrames, StaticPopupDialogs = {}, {}, {}
UNITS = {player = {name = "加 百列", class = "WARRIOR", guid = "Player-6746-00387CF3"},
    party1 = {name = "梦醒 融化如雪", class = "MAGE", guid = "Player-6746-003C63AA"}}
UNITS.target = UNITS.player
GROUP_SIZE = 2
local classes = {WARRIOR = "战士", MAGE = "法师", PRIEST = "牧师"}
function GetTime() return NOW end
function time(value) return value and os.time(value) or 1792924843 end
function date(format, value) return os.date(format, value or 1792924843) end
function GetBuildInfo() return "1.60.1", "70450", "", 16001 end
function RegionalUniqueNamesEnabled() return true end
function GetLocale() return "zhCN" end
function GetNumGroupMembers() return GROUP_SIZE end
function IsInRaid() return RAID or false end
function UnitIsGroupLeader() return LEADER ~= false end
function UnitIsGroupAssistant() return false end
function UnitIsPlayer(unit) return UNITS[unit] ~= nil end
function UnitIsFriend() return true end
function UnitExists(unit) return UNITS[unit] ~= nil end
function UnitGUID(unit) return UNITS[unit] and UNITS[unit].guid end
function UnitAffectingCombat() return false end
function UnitIsDeadOrGhost() return false end
function InCombatLockdown() return false end
function UnitClass(unit) local c=UNITS[unit] and UNITS[unit].class; return classes[c], c end
function UnitName(unit) return "Wrong first", "Wrong surname" end
function GetUnitName(unit) return UNITS[unit] and UNITS[unit].name end
NameUtil = {GetUnmodifiedUnitFullName = GetUnitName}
function issecretvalue(value) return type(value)=="table" and value.secret==true end
function GetRaidRosterInfo(i) local u=UNITS["raid"..i]; if u then return u.name, 2, 1, 60, classes[u.class], u.class, "Test", true end end
function GetGuildRosterInfo() return nil end
function GetNumGuildMembers() return 0 end
function GetGuildInfo() return nil end
function GetRealmName() return "Test" end
function GetZoneText() return "测试区域" end
GetRealZoneText, GetSubZoneText = GetZoneText, GetZoneText
function GetInstanceInfo() return "Test", "raid", 1, "Test", 40, false, false, 1 end
function GetNumLootItems() return 0 end
function GetLootSlotLink() return nil end
function GetLootSlotInfo() return nil end
function GetLootThreshold() return 2 end
function IsShiftKeyDown() return false end
function PlaySound() end
function ReloadUI() end
function GetCursorPosition() return 0,0 end
function GetCurrentRegion() return 5 end
C_AddOns = {IsAddOnLoaded=function(name) return name == "ADKP" end}
C_GuildInfo = {GuildRoster=function() end}
C_Item = {GetItemInfo=function(item) return item,item,4,60,60,"Armor","Plate",1,"",123 end}
C_PartyInfo = {InviteUnit=function() end, ConvertToRaid=function() end,
    GetLootMethod=function() return Enum.LootMethod.Freeforall,nil,nil end}
Enum = {SendAddonMessageResult={Success=0},LootMethod={Freeforall=0,Roundrobin=1,Masterlooter=2,Group=3,Needbeforegreed=4,Personal=5}}
C_ChatInfo = {
    RegisterAddonMessagePrefix=function() return true end,
    SendAddonMessage=function(prefix,message,channel,target) table.insert(SENT,{prefix,message,channel,target}); return 0 end,
    SendChatMessage=function(message,channel,language,target) table.insert(CHAT,{message,channel,target}) end,
    InChatMessagingLockdown=function() return false end,
    AreOutgoingAddonChatMessagesRestricted=function() return false end,
}
function ChatFrame_AddMessageEventFilter(event, fn) FILTERS[event]=fn end
function hooksecurefunc(name, fn) HOOKS[name]=fn end
function SetItemRef() end
function ChatFrame_OnEvent() end
function Mixin(object,mixin) for key,value in pairs(mixin) do object[key]=value end end
BackdropTemplateMixin = {
    SetBackdrop=function(self,b) self.backdrop=b end,
    SetBackdropColor=function(self,...) assert(self.backdrop,"backdrop descriptor required"); self.backdropColor={...} end,
    SetBackdropBorderColor=function(self,...) assert(self.backdrop,"backdrop descriptor required"); self.backdropBorderColor={...} end,
    OnBackdropSizeChanged=function() end,
}
SOUNDKIT = {}
local noOp=function() end
local methods={}
methods.LockHighlight, methods.UnlockHighlight = noOp, noOp
function methods:GetName() return self.name end
function methods:GetObjectType() return self.kind end
function methods:IsObjectType(kind) return self.kind==kind end
function methods:GetChildren() return unpack(self.children) end
function methods:GetRegions() return unpack(self.children) end
function methods:GetParent() return self.parent end
function methods:GetWidth() return self.width or 100 end
function methods:GetHeight() return self.height or 100 end
function methods:SetWidth(v) self.width=v end
function methods:SetHeight(v) self.height=v end
function methods:SetSize(w,h) self.width,self.height=w,h end
function methods:SetText(v) self.text=tostring(v or ""); if self.scripts.OnTextChanged then self.scripts.OnTextChanged(self,false) end end
function methods:GetText() return self.text or "" end
function methods:SetScript(event,fn) self.scripts[event]=fn end
function methods:GetScript(event) return self.scripts[event] end
function methods:HookScript(event,fn) local prior=self.scripts[event]; self.scripts[event]=function(...) if prior then prior(...) end; return fn(...) end end
function methods:RegisterEvent(event)
    assert(event~="RAID_ROSTER_UPDATE" and event~="PARTY_MEMBERS_CHANGED" and event~="CHAT_MSG_COMBAT_HOSTILE_DEATH" and event~="ITEM_TEXT_READY", "retired event "..event)
    self.events[event]=true
end
function methods:IsShown() return self.shown~=false end
function methods:IsVisible() return self:IsShown() end
function methods:Hide() local was=self:IsShown(); self.shown=false; if was and self.scripts.OnHide then self.scripts.OnHide(self) end end
function methods:Show() local was=self:IsShown(); self.shown=true; if not was and self.scripts.OnShow then self.scripts.OnShow(self) end end
function methods:SetChecked(v) self.checked=v end
function methods:GetChecked() return self.checked end
function methods:SetPoint(...) self.point={...} end
function methods:GetPoint() return unpack(self.point or {"CENTER",UIParent,"CENTER",0,0}) end
function methods:GetLeft() return 10 end
function methods:GetTop() return 10 end
function methods:GetCenter() return 0,0 end
function methods:GetEffectiveScale() return 1 end
function methods:GetScale() return 1 end
function methods:GetFrameLevel() return 1 end
function methods:GetID() return self.id or 1 end
function methods:SetID(v) self.id=v end
function methods:GetStringHeight() return 20 end
function methods:GetStringWidth() return string.len(self.text or "")*5 end
function methods:GetVerticalScroll() return self.vertical or 0 end
function methods:SetVerticalScroll(v) self.vertical=v end
function methods:SetMinMaxValues(low,high) self.minimum,self.maximum=low,high end
function methods:GetMinMaxValues() return self.minimum or 0,self.maximum or 0 end
function methods:GetValue() return self.value or 0 end
function methods:SetValue(value)
    local changed=self.value~=value; self.value=value
    if changed and self.scripts.OnValueChanged then self.scripts.OnValueChanged(self,value,false) end
end
function methods:SetShown(v) if v then self:Show() else self:Hide() end end
function methods:GetNumLines() return 1 end
function methods:GetFont() return "font",12,"" end
function methods:GetNumber() return tonumber(self.text) or 0 end
function methods:GetTextColor() return 1,1,1 end
function methods:SetVertexColor(...) self.vertexColor={...} end
function methods:SetTexture(value) self.texture=value end
function methods:IsEnabled() return true end
function methods:GetTextInsets() return 0,0,0,0 end
local serial=0
local function widget(kind,name,parent)
    serial=serial+1
    local w=setmetatable({kind=kind,name=name,parent=parent,scripts={},events={},shown=true,children={}}, {__index=function(_,key)
        if methods[key] then return methods[key] end
        if key=="SetBackdrop" or key=="SetBackdropColor" or key=="SetBackdropBorderColor" then return nil end
        if string.match(key,"^Set") or string.match(key,"^Enable") or string.match(key,"^Disable")
            or string.match(key,"^Register") or string.match(key,"^Start") or string.match(key,"^Stop")
            or string.match(key,"^Clear") or string.match(key,"^Add") or string.match(key,"^Highlight")
            or key=="UnregisterAllEvents" then return noOp end
    end})
    if name then _G[name]=w end
    if parent and parent.children then table.insert(parent.children,w) end
    return w
end
function methods:CreateTexture(name) return widget("Texture",name,self) end
function methods:CreateFontString(name) return widget("FontString",name,self) end
function methods:GetFontString() self.fontString=self.fontString or self:CreateFontString(); return self.fontString end
function methods:GetNormalTexture() self.normal=self.normal or self:CreateTexture(); return self.normal end
function methods:GetHighlightTexture() return self:GetNormalTexture() end
function methods:GetPushedTexture() return self:GetNormalTexture() end
function methods:RegisterForClicks(...)
    self.clicks={}
    for _,click in ipairs({...}) do self.clicks[click]=true end
end
function methods:Click(button)
    button=button or "LeftButton"
    if self.clicks and not self.clicks[button.."Up"] then return end
    if self.scripts.OnClick then self.scripts.OnClick(self,button,false) end
end
function CreateFrame(kind,name,parent,template)
    for part in string.gmatch(template or "","[^,]+") do assert(VALID_TEMPLATES[part],"unavailable modern template "..part) end
    local w=widget(kind,name,parent); w.template=template; table.insert(FRAMES,w)
    for part in string.gmatch(template or "","[^,]+") do
        if part=="BackdropTemplate" then Mixin(w,BackdropTemplateMixin) end
    end
    if name and template then
        for _,suffix in ipairs({"Left","Middle","Right","Text","DropDownButton","ScrollBar","ScrollBarScrollUpButton","ScrollBarScrollDownButton"}) do widget("Texture",name..suffix,w) end
    end
    for part in string.gmatch(template or "","[^,]+") do
        if part=="UIPanelButtonTemplate" then
            for _,key in ipairs({"Left","Middle","Right"}) do w[key]=(name and _G[name..key]) or widget("Texture",nil,w) end
        end
    end
    if BUILD_TEMPLATE and not LOADING_XML then
        for part in string.gmatch(template or "","[^,]+") do BUILD_TEMPLATE(w,part) end
        if w.scripts.OnLoad then w.scripts.OnLoad(w) end
    end
    return w
end
UIParent=CreateFrame("Frame","UIParent")
Minimap=CreateFrame("Frame","Minimap")
GameTooltip=CreateFrame("GameTooltip","GameTooltip")
DEFAULT_CHAT_FRAME={AddMessage=function(_,value) table.insert(MESSAGES,value) end}
function UIDropDownMenu_Initialize(frame,callback) frame.init=callback end
function UIDropDownMenu_AddButton(info) return info end
function UIDropDownMenu_SetWidth(frame,width) assert(type(frame)=="table"); frame.width=width end
function UIDropDownMenu_SetText(frame,text) assert(type(frame)=="table"); frame:SetText(text) end
function UIDropDownMenu_SetSelectedValue(frame,value) frame.selectedValue=value end
function UIDropDownMenu_GetSelectedValue(frame) return frame.selectedValue end
function UIDropDownMenu_SetSelectedName(frame,name) frame.selectedName=name end
function UIDropDownMenu_GetSelectedName(frame) return frame.selectedName end
function UIDropDownMenu_GetText(frame) return frame:GetText() end
function UIDropDownMenu_CreateInfo() return {} end
function ToggleDropDownMenu(_,_,frame) if frame.init then frame.init(frame,1) end end
function CloseDropDownMenus() end
function FauxScrollFrame_GetOffset(frame) return frame.offset or 0 end
function FauxScrollFrame_Update() end
function FauxScrollFrame_OnVerticalScroll(frame,offset,height,callback) frame.offset=math.floor(offset/height); callback() end
function StaticPopup_Show(which) LAST_POPUP=which; return CreateFrame("Frame","StaticPopup1") end
function StaticPopup_Hide() end
function PanelTemplates_SetTab(frame,id) frame.selectedTab=id end
function PanelTemplates_SetNumTabs(frame,n) frame.numTabs=n end
PanelTemplates_TabResize, PanelTemplates_SelectTab, PanelTemplates_DeselectTab = noOp,noOp,noOp
ChatFontNormal, GameFontNormal, GameFontNormalSmall, GameFontHighlightSmall = {},{},{},{}
strfind, strlen, strsub, strlower, strupper, format = string.find,string.len,string.sub,string.lower,string.upper,string.format
tinsert,tremove,sort,getn,floor,ceil,abs = table.insert,table.remove,table.sort,table.getn,math.floor,math.ceil,math.abs
