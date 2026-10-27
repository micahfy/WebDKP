"""One-time, byte-preserving source port from ADKP/ to ADKP_Forever_Classic/ADKP/.

Requires the temporary tree-sitter Lua development runtime; never shipped with
the addon. --refresh regenerates only files copied from the original addon.
Handwritten Forever adapters are separate files and are not overwritten.
"""
from pathlib import Path
import argparse
import re
import shutil
import sys
import xml.etree.ElementTree as ET

args = argparse.ArgumentParser()
args.add_argument('--parser-dir', required=True)
args.add_argument('--refresh', action='store_true')
args = args.parse_args()
sys.path.insert(0, args.parser_dir)
from tree_sitter import Language, Parser
import tree_sitter_lua

ROOT = Path(__file__).resolve().parents[1]
SOURCE, DEST = ROOT / 'ADKP', ROOT / 'ADKP_Forever_Classic' / 'ADKP'
if DEST.exists() and not args.refresh:
    raise SystemExit('Destination exists; inspect changes before --refresh.')
parser = Parser(Language(tree_sitter_lua.language()))

def walk(node):
    yield node
    for child in node.named_children:
        yield from walk(child)

def text(source, node):
    return source[node.start_byte:node.end_byte].decode('utf-8') if node else ''

def edit(source, changes):
    kept, end = [], -1
    for a,b,value in sorted(changes, key=lambda c:(c[0],-c[1])):
        if a < end: continue
        kept.append((a,b,value)); end=b
    result = source
    for a, b, value in reversed(kept):
        result = result[:a] + value.encode('utf-8') + result[b:]
    return result

ALIASES = '''-- Forever adapters are private to this addon source file.
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
'''

def functions(source):
    return [(n, text(source, n.child_by_field_name('name'))) for n in walk(parser.parse(source).root_node)
            if n.type == 'function_declaration']

def remove_functions(source, predicate):
    return edit(source, [(n.start_byte, n.end_byte, '') for n, name in functions(source) if predicate(name, n)])

REMOVED = re.compile(r'AutoBackup|BackupRecovery|LatestBackup|KeepOnline|SettingsAutoBackup|SettingsRestore|SettingsBackup|SettingsImport(?:Button|EditBox)|ADKP_ResumeAutoBackup')

def cleanup(source):
    changes = []
    tree = parser.parse(source)
    for n in walk(tree.root_node):
        raw = text(source, n)
        if n.type == 'if_statement' and REMOVED.search(text(source, n.child_by_field_name('condition'))):
            changes.append((n.start_byte, n.end_byte, ''))
        elif n.type == 'field' and REMOVED.search(text(source, n.child_by_field_name('name'))):
            # Remove the adjacent comma too, since a missing field is not an expression.
            end = n.end_byte
            while end < len(source) and source[end:end+1] in (b' ', b'\r', b'\n', b'\t'): end += 1
            if source[end:end+1] in (b',', b';'): end += 1
            changes.append((n.start_byte, end, ''))
        elif n.type == 'assignment_statement' and REMOVED.search(text(source, n.named_children[0])):
            changes.append((n.start_byte, n.end_byte, ''))
    return edit(source, changes)

def adapt_lua(source):
    changes = []
    for n in walk(parser.parse(source).root_node):
        if n.type != 'function_call': continue
        name, arguments = n.child_by_field_name('name'), n.child_by_field_name('arguments')
        if not name or not arguments: continue
        method = name.child_by_field_name('method')
        argv = arguments.named_children
        if method and text(source, method) == 'SetTexture' and len(argv) >= 3:
            owner = text(source, name.child_by_field_name('table'))
            changes.append((n.start_byte, n.end_byte, 'ADKP_SetTexture(' + owner + ', ' + ', '.join(text(source, a) for a in argv) + ')'))
        if method and text(source, method) == 'SetMaxLetters' and argv:
            changes.append((argv[0].start_byte, argv[0].end_byte, '0'))
    return edit(source, changes)

def fold_retired(source):
    source = re.sub(rb'ADKP_Bid_IsTransmogMode\s*\(\s*\)', b'false', source)
    source = source.replace(b'ADKP_Bid_IsTransmogMode and false', b'false')
    source = source.replace(b'ADKP_TransmogMode', b'false')
    source = re.sub(rb'(?m)^local false\s*=.*?\r?\n', b'', source)
    source = re.sub(rb'(?m)^\s*false\s*=.*?\r?\n', b'\n', source)
    # Remove unreachable branches, preserving the selected original block bytes.
    for _ in range(8):
        changes = []
        for n in walk(parser.parse(source).root_node):
            if n.type != 'if_statement': continue
            condition = text(source, n.child_by_field_name('condition')).strip()
            if condition.startswith('false and '): condition='false'
            if condition not in ('false', 'not false'): continue
            chosen = n.child_by_field_name('consequence') if condition == 'not false' else None
            alternatives = [c for c in n.named_children if c.type in ('else_statement', 'elseif_statement')]
            if condition == 'false' and alternatives:
                first = alternatives[0]
                if first.type == 'else_statement': chosen = first.child_by_field_name('body')
                else:
                    replacement = 'if' + text(source, first)[6:] + ''.join('\n' + text(source, a) for a in alternatives[1:]) + '\nend'
                    changes.append((n.start_byte, n.end_byte, replacement)); continue
            changes.append((n.start_byte, n.end_byte, text(source, chosen)))
        if not changes: break
        source = edit(source, changes)
    return source

def xml_nodes(source):
    stack, nodes = [], []
    for m in re.finditer(r'<(/?)([A-Za-z][\w]*)(\b[^<>]*?)(/?)>', source):
        close, tag, attrs, short = m.groups()
        if close:
            if stack and stack[-1]['tag'] == tag:
                node = stack.pop(); node['end'] = m.end(); node['close'] = m.start(); nodes.append(node)
        elif short:
            nodes.append(dict(tag=tag, start=m.start(), open=m.end(), close=m.end(), end=m.end(), attrs=attrs, parent=stack[-1] if stack else None))
        else:
            stack.append(dict(tag=tag, start=m.start(), open=m.end(), attrs=attrs, parent=stack[-1] if stack else None))
    return nodes

def adapt_xml(source):
    nodes = xml_nodes(source)
    removed = []
    for n in nodes:
        if n['tag'] == 'Script' and 'file=' in n['attrs']:
            removed.append((n['start'], n['end'], ''))
        if re.search(r'name="(?:ADKP_AwardDKP_FrameToggleKeepOnline|ADKP_Settings(?:AutoBackupCheck|RestoreButton|BackupButton|ImportEditBox|ImportButton)|\$parent(?:Transmog|EndTransmog))"', n['attrs']):
            removed.append((n['start'], n['end'], ''))
        if n['tag'] == 'FontString' and 'text="备份文件:"' in n['attrs']:
            removed.append((n['start'], n['end'], ''))
    for a,b,v in sorted(removed, reverse=True): source = source[:a] + v + source[b:]
    source = source.replace('数据与备份', '数据管理').replace('$parentTransmog"', '$parentAward"')
    for old in ('CharacterFrameTabButtonTemplate','OptionsButtonTemplate','OptionsCheckButtonTemplate','UICheckButtonTemplate','FauxScrollFrameTemplate','GameMenuButtonTemplate','InputBoxTemplate','UIPanelScrollFrameTemplate'):
        source=source.replace('inherits="'+old+'"','inherits="ADKP_Forever'+old+'"')
    source = source.replace('ADKP_SettingsBackupGroup', 'ADKP_SettingsDataGroup')
    # Backdrop is no longer XML-supported; apply the original descriptor on load.
    nodes = xml_nodes(source); changes = []
    for n in nodes:
        if n['tag'] != 'Backdrop': continue
        e = ET.fromstring(source[n['start']:n['end']])
        fields = ['%s = "%s"' % (k, v.replace('\\', '\\\\')) for k,v in e.attrib.items() if k in ('bgFile','edgeFile')]
        if e.attrib.get('tile') == 'true': fields.append('tile = true')
        for tag,key in [('TileSize','tileSize'),('EdgeSize','edgeSize')]:
            d = e.find(tag + '/AbsValue')
            if d is not None: fields.append(key + ' = ' + d.attrib['val'])
        inset = e.find('BackgroundInsets/AbsInset')
        if inset is not None: fields.append('insets = {' + ', '.join(k+' = '+v for k,v in inset.attrib.items()) + '}')
        parent = n['parent']
        call = 'ADKP_ApplyBackdrop(self, {' + ', '.join(fields) + '});\n'
        onload = next((q for q in nodes if q['tag']=='OnLoad' and q.get('parent',{}).get('parent') is parent), None)
        if onload: changes.append((onload['open'],onload['open'],call))
        else:
            scripts = next((q for q in nodes if q['tag']=='Scripts' and q.get('parent') is parent), None)
            if scripts: changes.append((scripts['open'],scripts['open'],'<OnLoad>'+call+'</OnLoad>'))
            else: changes.append((parent['close'],parent['close'],'<Scripts><OnLoad>'+call+'</OnLoad></Scripts>'))
        changes.append((n['start'], n['end'], ''))
    for a,b,v in sorted(changes,reverse=True): source=source[:a]+v+source[b:]
    # Modern callback arguments are passed explicitly into the legacy scope.
    def callback(match):
        tag, attrs, body = match.groups()
        body = adapt_lua(body.encode('utf-8')).decode('utf-8')
        mapping={'getglobal':'ADKP_GetGlobal','setglobal':'ADKP_SetGlobal','UnitName':'ADKP_UnitName',
                 'CreateFrame':'ADKP_CreateFrame','PlaySound':'ADKP_PlaySound','GetNumRaidMembers':'ADKP_GetNumRaidMembers',
                 'GetNumPartyMembers':'ADKP_GetNumPartyMembers','FauxScrollFrame_OnVerticalScroll':'ADKP_FauxVerticalScroll',
                 'FauxScrollFrame_Update':'ADKP_FauxUpdate','FauxScrollFrame_GetOffset':'ADKP_FauxGetOffset','PanelTemplates_SetTab':'ADKP_PanelSetTab',
                 'UIDropDownMenu_SetWidth':'ADKP_DropdownSetWidth','UIDropDownMenu_SetText':'ADKP_DropdownSetText',
                 'UIDropDownMenu_Initialize':'ADKP_DropdownInitialize','UIDropDownMenu_AddButton':'ADKP_DropdownAddButton'}
        for old,new in mapping.items(): body=re.sub(r'\b'+old+r'(?=\s*\()',new,body)
        payload={'OnEvent':'event, ...','OnUpdate':'elapsed','OnClick':'button, down',
                 'OnMouseDown':'button','OnMouseUp':'button','OnMouseWheel':'delta','OnVerticalScroll':'offset',
                 'OnScrollRangeChanged':'xrange, yrange','OnTextChanged':'userInput','OnValueChanged':'value, userInput',
                 'OnSizeChanged':'width, height','OnDragStart':'button','OnKeyDown':'key','OnChar':'text',
                 'OnEnter':'motion','OnLeave':'motion','OnCursorChanged':'x, y, width, height',
                 'OnHyperlinkClick':'link, text, button'}.get(tag,'')
        return '<'+tag+attrs+'>ADKP_LegacyCall(self, "'+tag+'", function()\n'+body+'\nend'+(', '+payload if payload else '')+');</'+tag+'>'
    source = re.sub(r'<(On\w+)([^>]*)>(.*?)</\1>', callback, source, flags=re.S)
    source = re.sub(r'\bletters="\d+"', 'letters="0"', source)
    # XML-created controls also receive scripts later from Lua.
    nodes=xml_nodes(source); changes=[]
    kinds={'Frame','Button','CheckButton','EditBox','ScrollFrame','Slider','GameTooltip'}
    for n in nodes:
        if n['tag'] not in kinds or n['close']==n['open']: continue
        onload=next((q for q in nodes if q['tag']=='OnLoad' and q.get('parent',{}).get('parent') is n),None)
        if onload: changes.append((onload['open'],onload['open'],'ADKP_PrepareFrame(self);\n'))
        else:
            scripts=next((q for q in nodes if q['tag']=='Scripts' and q.get('parent') is n),None)
            body='<OnLoad>ADKP_PrepareFrame(self);</OnLoad>'
            at=scripts['open'] if scripts else n['close']
            changes.append((at,at,body if scripts else '<Scripts>'+body+'</Scripts>'))
    for a,b,v in sorted(changes,reverse=True): source=source[:a]+v+source[b:]
    return source

excluded = {'KeepOnline.lua','ADKP_BackupCheck.lua'}
DEST.mkdir(parents=True, exist_ok=True)
for path in SOURCE.rglob('*'):
    dest = DEST/path.relative_to(SOURCE)
    if path.is_dir(): dest.mkdir(exist_ok=True); continue
    if path.name in excluded:
        if dest.exists(): dest.unlink()
        continue
    if path.suffix not in ('.lua','.xml','.toc'):
        shutil.copy2(path,dest); continue
    if path.suffix == '.toc': continue
    source = path.read_bytes()
    if path.name == 'ADKP.lua':
        stop = source.index(b'function ADKP_CreatePlayerClassDropDown_Init')
        keep = {'ADKP_SaveToDisk','ADKP_GetTableNameById','ADKP_BuildBackupCSV'}
        source=remove_functions(source,lambda name,node:node.start_byte<stop and name not in keep)
        source=remove_functions(source,lambda name,node:name=='ADKP_ToggleKeepOnline')
        # Keep the original OnEnable work except global hooks into Blizzard UI.
        changes=[]
        for n in walk(parser.parse(source).root_node):
            raw=text(source,n)
            if n.type=='assignment_statement' and re.match(r'ADKP_(?:RegisterPopupMenu|UnitPopup_OnClick)\s*=',raw):
                changes.append((n.start_byte,n.end_byte,''))
            elif n.type=='function_call' and raw=='ADKP_RegisterPopupMenu()':
                changes.append((n.start_byte,n.end_byte,'ADKP_ForeverInstallUIHooks()'))
            elif n.type=='if_statement' and 'SetItemRef' in text(source,n.child_by_field_name('condition')):
                changes.append((n.start_byte,n.end_byte,'ADKP_ForeverInstallUIHooks()'))
        source=edit(source,changes)
        source=source.replace(b'ADKP_VERSION = "1.98"', b'ADKP_VERSION = "1.98-forever.1"')
        source=re.sub(rb'\s*frame:RegisterEvent\("(?:PARTY_MEMBERS_CHANGED|ITEM_TEXT_READY|CHAT_MSG_COMBAT_[A-Z_]+)"\);',b'',source)
        source=source.replace(b'frame:RegisterEvent("RAID_ROSTER_UPDATE")',b'frame:RegisterEvent("GROUP_ROSTER_UPDATE")')
        source=source.replace(b'ADKP_SaveToDisk',b'ADKP_RefreshSavedState')
        source=remove_functions(source,lambda name,node:name=='ADKP_RefreshSavedState')
    if path.name == 'Bidding.lua':
        source=remove_functions(source,lambda name,node:'Transmog' in name or name in ('ADKP_Bid_HandleRollMessage','ADKP_Bid_ParseRollMessage'))
        source=fold_retired(source)
        source=re.sub(rb'(?m)^local ADKP_Transmog\w*[^\r\n]*\r?\n', b'', source)
        source=re.sub(rb'(?m)^\s*ADKP_Transmog\w*\s*=.*?\r?\n', b'\n', source)
        source=source.replace(b'false and entry["Name"] or entry[1]',b'entry[1]')
        source=source.replace(b'false and (entry["Kind"] == "hh" and "HH" or "Roll") or entry[2]',b'entry[2]')
        source=source.replace(b'not false and (entry[6] or false)',b'(entry[6] or false)')
        source=source.replace(b'false and entry or nil',b'nil').replace(b'false and entry["Selected"] or ADKP_Bid_IsSelected',b'ADKP_Bid_IsSelected')
        source=re.sub(rb'(?m)^\s*ADKP_Bid_HideTransmogButtonTooltip\(\).*?\r?\n', b'\n', source)
        source=re.sub(rb'(?m)^\s*ADKP_Bid_SetTransmogUI\(.*?\r?\n', b'\n', source)
        source=re.sub(rb'(?m)^\s*local emptyText = ADKP_Bid_GetTransmogEmptyText\(\).*?\r?\n',b'\nlocal emptyText = nil\n',source)
    if path.name == 'ADKP_SubSync.lua':
        # Preserve original cache/label/replay helpers; native routing follows.
        end=source.index('ADKP_SubSync_OrigSendWhisper ='.encode())
        start=source.index(b'if not ADKP_SubSync_Installed then')
        source=b'-- Original cache helpers; native WHISPER routing is in ADKP_ForeverNetwork.lua.\n'+source[start:end]+b'\nend -- ADKP_SubSync_Installed\n'
    if path.name == 'WhisperDKP.lua':
        source=remove_functions(source,lambda name,node:name in ('ADKP_Register_WhisperHook','ADKP_ChatFrame_OnEvent_Hook'))
    if path.name=='ADKP.lua':
        source=fold_retired(source)
        source=source.replace('phase == "transmog" and "幻化中" or "竞拍中"'.encode(),'"竞拍中"'.encode())
        source=source.replace('phase == "transmog" and "当前幻化竞拍尚未结束" or "当前竞拍尚未结束"'.encode(),'"当前竞拍尚未结束"'.encode())
        source=re.sub(rb'if ADKP_Bid_HandleTransmogChat then.*?end',b'',source,flags=re.S)
        source=source.replace(b'GetMasterLootCandidate(j)',b'GetMasterLootCandidate(foundItemSlot, j)')
        source=re.sub(rb'local args = \{\}\s*for arg in string.gmatch\(cmd, "%S\+"\) do\s*table.insert\(args, arg\)\s*end',
                      b'local args, parseError = ADKP_ForeverArguments(cmd)\n    if not args then ADKP_Print(parseError); return end',source)
        source=source.replace('if reason == "" then reason = "分数调整" end'.encode(), 'if reason == "" then reason = "菜出天际-犯错" end'.encode())
        source=re.sub(rb'getglobal\(this:GetParent\(\):GetName\(\)\s*\.\.\s*"EditBox"\)', b'ADKP_PopupEditBox(this)', source)
        changes=[]
        for n in parser.parse(source).root_node.named_children:
            if n.type=='assignment_statement':
                raw=text(source,n)
                m=re.match(r'(WebDKP_\w+)\s*=\s*\{',raw)
                if m: changes.append((n.start_byte,n.end_byte,raw.replace('=', '= '+m[1]+' or',1)))
        source=edit(source,changes)
    if path.name=='ADKP_BossEncounters.lua':
        source=source.replace(b'frame:RegisterEvent("CHAT_MSG_MONSTER_YELL")',b'-- Native encounter events are handled by ADKP_ForeverFinalize.lua.')
    if path.name=='Bidding.lua': source=source.replace(b'GetMasterLootCandidate(i)',b'GetMasterLootCandidate(foundItemSlot, i)')
    if path.name in ('ADKP.lua','Bidding.lua'):
        source=re.sub(rb'getglobal\(this:GetName\(\)\s*\.\.\s*"Name"\):GetText\(\)',b'ADKP_RowName(this)',source)
    if path.name=='GroupFunctions.lua': source=source.replace(b'nameText:SetText(entries[index][1]);',b'ADKP_SetNameText(nameText, entries[index][1]);')
    if path.name=='Bidding.lua': source=source.replace(b'nameText:SetText(playerName);',b'ADKP_SetNameText(nameText, playerName);')
    if path.name=='ADKP_LootList.lua': source=source.replace(b'row.nameText:SetText(name)',b'ADKP_SetNameText(row.nameText, name)')
    if path.name=='ADKP_ShareGroups.lua':
        source=source.replace(b'line.mainText:SetText(relation.main)',b'ADKP_SetNameText(line.mainText, relation.main)')
        source=source.replace(b'line.altText:SetText(relation.alt)',b'ADKP_SetNameText(line.altText, relation.alt)')
        source=remove_functions(source,lambda name,node:name in ('restoreMetadata','ADKP_RestoreFromData'))
        source=re.sub(rb'(?m)^local OriginalRestoreFromData[^\r\n]*\r?\n',b'',source)
        changes=[]
        for n in walk(parser.parse(source).root_node):
            if n.type=='if_statement' and text(source,n.child_by_field_name('condition'))=='OriginalRestoreFromData':
                changes.append((n.start_byte,n.end_byte,''))
        source=edit(source,changes)
        source=source.replace(b'OriginalBuildBackupCSV',b'OriginalBuildActivityCSV')
    if path.name=='ADKP_HelpDoc.lua':
        source=re.sub('(?m)^.*".*(?:自动备份|防掉线|保持在线|数据安全：).*\r?\n'.encode(),b'',source)
        source=source.replace('同工会走插件频道同步，跨工会走密语同步。'.encode(),'通过原生插件 WHISPER 同步完整名单。'.encode())
    if path.name=='ADKP_Help.lua':
        # Documentation for removed controls must not promise removed features.
        source=cleanup(source)
    source=re.sub(rb'(?m)^.*--.*(?:SuperWoW|SuperWOW|superwow|SUPERWOW|ImportFile|ExportFile).*?\r?\n',b'\n',source)
    source=source.replace(b'ADKP_BuildBackupCSV',b'ADKP_BuildActivityCSV').replace(b'ADKP_SaveToDisk',b'ADKP_RefreshSavedState')
    if path.suffix=='.lua':
        source=cleanup(source); source=adapt_lua(source)
        source=ALIASES.encode()+source
    else: source=adapt_xml(source.decode('utf-8')).replace('-->image.png','-->').encode('utf-8')
    dest.write_bytes(source)

toc=(SOURCE/'ADKP.toc').read_text('utf-8')
toc=toc.replace('## Interface: 11200','## Interface: 16001').replace('## Title: ADKP','## Title: ADKP 无限原版移植',1)
toc=toc.replace('## Version: 1.98','## Version: 1.98-forever.1')
toc=toc.replace('ADKP_BackupCheck.lua\n','').replace('KeepOnline.lua\n','')
toc=toc.replace('ADKP_RaidBossData.lua','ADKP_ForeverCompat.lua\nADKP_RaidBossData.lua',1)
toc=toc.replace('ADKP_RaidBossData.lua','ADKP_ForeverTemplates.xml\nADKP_RaidBossData.lua',1)
toc=toc.replace('ADKP_Frame.xml','ADKP_ForeverRuntime.lua\nADKP_Frame.xml',1)
toc+='ADKP_ForeverNetwork.lua\nADKP_ForeverFinalize.lua\n'
(DEST/'ADKP.toc').write_text(toc,encoding='utf-8')
print('Cloned original addon into',DEST)
