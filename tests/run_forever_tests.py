"""Offline Forever regressions with Lua 5.1; no WoW/client-extension dependency.

Run: python tests/run_forever_tests.py --runtime-dir PATH_TO_LUPA
The optional path is for a temporary pip --target install, not an addon dependency.
"""
import argparse
from pathlib import Path
import re
import sys
import xml.etree.ElementTree as ET

parser = argparse.ArgumentParser()
parser.add_argument('--runtime-dir')
args = parser.parse_args()
if args.runtime_dir:
    sys.path.insert(0, args.runtime_dir)
from lupa.lua51 import LuaRuntime

root = Path(__file__).resolve().parents[1]
addon = root / 'ADKP_Forever'
toc = (addon / 'ADKP_Forever.toc').read_text(encoding='utf-8')
entries = [s.strip() for s in toc.splitlines() if s.strip() and not s.startswith('##')]
assert entries == ['Core.lua', 'Identity.lua', 'Data.lua', 'Roster.lua', 'Comm.lua', 'Chat.lua',
                   'Groups.lua', 'Awards.lua', 'Loot.lua', 'Bidding.lua', 'Encounters.lua', 'Classic.lua', 'UI.lua', 'Operations.lua', 'Main.lua']
assert '## Interface: 16001' in toc
assert len(entries) == len(set(entries))
assert not re.search(r'^## (?:Dependencies|OptionalDeps):', toc, re.M)
assert set(entries) == {p.name for p in addon.glob('*.lua')}
lua = LuaRuntime(unpack_returned_tuples=True)
lua.globals().ROOT = root.as_posix()
ns = {'ui': 'http://www.blizzard.com/wow/ui/'}
for filename, frame, prefix in [('ADKP_Frame.xml', 'ADKP_Frame', 'LEGACY_MAIN'),
                                 ('ADKP_Bid_Frame.xml', 'ADKP_BidFrame', 'LEGACY_BID')]:
    xml = ET.parse(root / 'ADKP' / filename)
    dim = xml.find('.//*[@name="' + frame + '"]/ui:Size/ui:AbsDimension', ns)
    assert dim is not None, frame
    lua.globals()[prefix + '_WIDTH'] = int(dim.attrib['x'])
    lua.globals()[prefix + '_HEIGHT'] = int(dim.attrib['y'])
assert (addon / 'Textures/MinimapButton.blp').read_bytes() == (root / 'ADKP/Textures/MinimapButton.blp').read_bytes()
for entry in entries:
    lua.execute('assert(loadstring(...))', (addon / entry).read_text(encoding='utf-8'))
    source = (addon / entry).read_text(encoding='utf-8')
    assert not re.search(r'\b(?:SUPERWOW_STRING|ImportFile|ExportFile|KeepOnline|PLAYER_CAMPING)\b', source), entry
lua.execute((root / 'tests/forever_spec.lua').read_text(encoding='utf-8'))
print('Forever manifest / Lua 5.1 syntax / dependency boundary PASS')
