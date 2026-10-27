"""Load the actual cloned Lua and XML in TOC order against a modern-only mock."""
import argparse
from pathlib import Path
import sys
import xml.etree.ElementTree as ET

p = argparse.ArgumentParser()
p.add_argument('--runtime-dir', required=True)
p.add_argument('--addon-dir', type=Path, help='Optional extracted release ADKP directory')
args = p.parse_args()
sys.path.insert(0, args.runtime_dir)
from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
ADDON = args.addon_dir or ROOT / 'ADKP_Forever_Classic' / 'ADKP'
entries = [line.strip() for line in (ADDON/'ADKP.toc').read_text('utf-8').splitlines()
           if line.strip() and not line.startswith('##')]
assert len(entries) == len(set(entries))
assert set(e for e in entries if e.endswith('.lua')) == {f.name for f in ADDON.glob('*.lua')}
assert not (ADDON/'KeepOnline.lua').exists()
assert not (ADDON/'ADKP_BackupCheck.lua').exists()
assert (ADDON/'Textures/MinimapButton.blp').read_bytes() == (ROOT/'ADKP/Textures/MinimapButton.blp').read_bytes()
# Every surviving named original control keeps its original size and anchors.
geometry_count=0
for filename in ('ADKP_Frame.xml','ADKP_Bid_Frame.xml','ADKP_Award_Frame.xml'):
    old=ET.parse(ROOT/'ADKP'/filename)
    new=ET.parse(ADDON/filename)
    def named_nodes(element, parents=()):
        name=element.attrib.get('name')
        path=parents+(name.replace('ADKP_SettingsBackupGroup','ADKP_SettingsDataGroup'),) if name else parents
        if name: yield path,element
        for child in element: yield from named_nodes(child,path)
    new_named=dict(named_nodes(new.getroot()))
    for name,element in named_nodes(old.getroot()):
        if name not in new_named: continue
        for tag in ('Size','Anchors'):
            a=element.find('{http://www.blizzard.com/wow/ui/}'+tag)
            b=new_named[name].find('{http://www.blizzard.com/wow/ui/}'+tag)
            if a is None or b is None: continue
            if filename=='ADKP_Frame.xml' and name[-2:]==('ADKP_BossKillAwardFrame','$parentSubLabel') and tag=='Anchors':
                # Equivalent placement through the preceding label avoids a forward reference:
                # raid-label edge + 8 px + 60 px input + 20 px = label edge + 88 px.
                a=ET.fromstring(ET.tostring(a))
                anchor=a.find('{http://www.blizzard.com/wow/ui/}Anchor')
                assert anchor.attrib['relativeTo']=='ADKP_BossKillRaidEdit'
                anchor.set('relativeTo','$parentRaidLabel')
                offset=anchor.find('{http://www.blizzard.com/wow/ui/}Offset/{http://www.blizzard.com/wow/ui/}AbsDimension')
                assert offset.attrib['x']=='20'
                offset.set('x','88')
            def geometry(node):
                attributes={k:v.replace('$parentTransmog','$parentAward') for k,v in node.attrib.items()}
                # This original anchor referenced a nonexistent import button.
                if filename=='ADKP_Frame.xml' and name[-2:]==('ADKP_Personal_Frame','$parentQuickFloatEnabled'):
                    if attributes.get('relativeTo')=='$parentImportTextButton':
                        attributes['relativeTo']='$parentIncludeSubCaptain'
                return (node.tag,sorted(attributes.items()),[geometry(c) for c in node])
            assert geometry(a)==geometry(b), (filename,name,tag)
            geometry_count+=1
print(f'PASS {geometry_count} original XML size/anchor contracts')
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute((ROOT/'tests/forever_classic_mock.lua').read_text('utf-8'))
g = lua.globals()
templates = {}
ui = '{http://www.blizzard.com/wow/ui/}'
frame_kinds = {'Frame','Button','CheckButton','EditBox','ScrollFrame','Slider','GameTooltip','StatusBar'}
parameters={'OnEvent':'self,event,...','OnUpdate':'self,elapsed','OnClick':'self,button,down',
    'OnMouseDown':'self,button','OnMouseUp':'self,button','OnMouseWheel':'self,delta',
    'OnVerticalScroll':'self,offset','OnScrollRangeChanged':'self,xrange,yrange',
    'OnTextChanged':'self,userInput','OnValueChanged':'self,value,userInput','OnSizeChanged':'self,width,height',
    'OnDragStart':'self,button','OnKeyDown':'self,key','OnChar':'self,text','OnEnter':'self,motion','OnLeave':'self,motion',
    'OnCursorChanged':'self,x,y,width,height','OnHyperlinkClick':'self,link,text,button'}
def xml_callback(tag,body):
    return lua.eval('function('+parameters.get(tag,'self')+')\n'+body+'\nend')

def build(node, parent=None, owner_name='', inherited=False):
    kind = node.tag.split('}')[-1]
    if kind not in frame_kinds and kind not in ('Texture','FontString'):
        return
    raw_name = node.attrib.get('name')
    name = raw_name.replace('$parent', owner_name) if raw_name else None
    if inherited:
        frame = parent
    elif kind in ('Texture','FontString'):
        frame = parent.CreateTexture(parent, name) if kind == 'Texture' else parent.CreateFontString(parent, name)
    else:
        frame = g.CreateFrame(kind, name, parent, node.attrib.get('inherits'))
    actual_name = frame.GetName(frame) or owner_name
    for anchor in node.findall(ui+'Anchors/'+ui+'Anchor'):
        relative = anchor.attrib.get('relativeTo')
        if relative:
            relative=relative.replace('$parent',owner_name)
            assert g[relative] is not None, f'{actual_name}: relative frame {relative} not yet constructed'
            anchor_refs.append((actual_name,relative))
    for base in node.attrib.get('inherits','').split(','):
        if base.strip() in templates:
            build(templates[base.strip()], frame, actual_name, True)
    for mixin in node.attrib.get('mixin','').split(','):
        if mixin.strip():
            assert g[mixin.strip()] is not None, f'Unknown mixin {mixin}'
            g.Mixin(frame,g[mixin.strip()])
    if 'text' in node.attrib:
        frame.SetText(frame, node.attrib['text'])
    if 'id' in node.attrib: frame.SetID(frame, int(node.attrib['id']))
    if 'checked' in node.attrib: frame.SetChecked(frame, node.attrib['checked']=='true')
    size = node.find(ui+'Size/'+ui+'AbsDimension')
    if size is not None:
        frame.SetWidth(frame, float(size.attrib.get('x',0)))
        frame.SetHeight(frame, float(size.attrib.get('y',0)))
    scripts = node.find(ui+'Scripts')
    if scripts is not None:
        for script in scripts:
            body = script.text or ''
            fn = xml_callback(script.tag.split('}')[-1],body)
            frame.SetScript(frame, script.tag.split('}')[-1], fn)
    for child in node:
        tag = child.tag.split('}')[-1]
        if tag in ('Frames','ScrollChild'):
            for element in child: build(element, frame, actual_name)
        elif tag == 'Layers':
            for layer in child:
                for element in layer: build(element, frame, actual_name)
    if not inherited:
        onload = frame.GetScript(frame, 'OnLoad')
        if onload:
            try: onload(frame)
            except Exception as e: raise RuntimeError(f'OnLoad {actual_name}: {e}') from e
        if node.attrib.get('hidden') == 'true': frame.Hide(frame)
    return frame

def load_addon(seed=None):
    global lua, g, templates, anchor_refs
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute((ROOT/'tests/forever_classic_mock.lua').read_text('utf-8'))
    if seed: lua.execute(seed)
    g, templates, anchor_refs = lua.globals(), {}, []
    def dynamic_template(frame,name):
        if name in templates: build(templates[name],frame,frame.GetName(frame) or '',True)
    g.BUILD_TEMPLATE=dynamic_template
    for entry in entries:
        path = ADDON/entry
        assert path.exists(), entry
        source = path.read_text('utf-8-sig')
        if entry.endswith('.lua'):
            try: lua.execute(source, ADDON.name, name=entry)
            except Exception as e: raise RuntimeError(f'{entry}: {e}') from e
        elif entry.endswith('.xml'):
            xml = ET.fromstring(source)
            assert not list(xml.iter(ui+'Script')), 'External Lua must load once via TOC'
            for script in xml.iter(ui+'Scripts'):
                for handler in script: xml_callback(handler.tag.split('}')[-1],handler.text or '')
            g.LOADING_XML=True
            for node in xml:
                if node.attrib.get('virtual') == 'true':
                    templates[node.attrib['name']] = node
                    g.VALID_TEMPLATES[node.attrib['name']]=True
                else:
                    try: build(node)
                    except Exception as e: raise RuntimeError(f'{entry} {node.attrib.get("name")}: {e}') from e
            g.LOADING_XML=False
    for owner,relative in anchor_refs:
        assert g[relative] is not None, f'{owner}: missing relative frame {relative}'
    print(f'PASS {len(anchor_refs)} XML anchor references resolve')
    return lua

lua=load_addon()

lua.execute((ROOT/'tests/forever_classic_spec.lua').read_text('utf-8'))
leader=lua
captain=load_addon('''
UNITS.player={name="替补 队长",class="WARRIOR",guid="Player-Sub"}
UNITS.party1={name="张三 四",class="WARRIOR",guid="Player-Space1"}
UNITS.party2={name="张 三四",class="MAGE",guid="Player-Space2"}
GROUP_SIZE=3
WebDKP_Options={SilentMode=true,SelectedTableId=1}
WebDKP_DkpTable={["原有 玩家"]={class="战士",dkp_1=88}}
''')
captain.execute('ADKP_ForeverNativeEvents:GetScript("OnEvent")(ADKP_ForeverNativeEvents,"PLAYER_LOGIN"); assert(WebDKP_DkpTable["原有 玩家"].dkp_1==88); assert(WebDKP_Options.SilentMode==true)')
print('PASS loaded SavedVariables keep existing scores and options')
leader.execute('ADKP_SetSubCaptain(1,"替补 队长"); ADKP_SubAwardData.captain="替补 队长"; ADKP_SubSync_RefreshRoster(); SENT={}')
captain.execute('SENT={}')

def pump(source, target, sender, expected):
    source.execute('NOW=NOW+0.2; ADKP_ForeverNativePump:GetScript("OnUpdate")(ADKP_ForeverNativePump)')
    packets=source.globals().SENT
    for i in range(1,len(packets)+1):
        packet=packets[i]
        assert packet[3]=='WHISPER' and packet[4]==expected
        target.globals().ADKP_ForeverHandleAddon(packet[1],packet[2],packet[3],sender)
    source.execute('SENT={}')

for _ in range(35):
    pump(leader,captain,'加 百列','替补 队长')
    pump(captain,leader,'替补 队长','加 百列')
leader.execute('''
assert(ADKP_ForeverCommsVerified)
local cache=ADKP_SubSync_Cache["替补 队长"]
assert(cache and cache.members["张三 四"] and cache.members["张 三四"])
assert(cache.members["张三 四"]=="战士" and cache.members["张 三四"]=="法师")
ADKP_ResetSubSyncState(); ADKP_SubSync_ReplayCache("替补 队长"); assert(ADKP_SubAwardData.subSyncComplete)
local before=cache.time
ADKP_ForeverHandleAddon("AMB_TBFS","wrong|SUB:恶意 玩家:战","WHISPER","替补 队长")
assert(not ADKP_SubSync_Cache["替补 队长"].members["恶意 玩家"])
''')
print('PASS independent clients sync distinct Chinese names through native addon WHISPER and replay complete cache')
print('Cloned manifest / all Lua / all embedded XML / modern callback startup PASS')
