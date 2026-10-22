"""Validate the addon manifest, Lua/XML scripts and actual encounter handlers."""
import argparse
from pathlib import Path
import subprocess
import tempfile
import xml.etree.ElementTree as ET

parser = argparse.ArgumentParser()
parser.add_argument('--lua', required=True)
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
entries = [s.strip() for s in (root / 'ADKP/ADKP.toc').read_text(encoding='utf-8').splitlines()
           if s.strip() and not s.startswith('##')]
assert len(entries) == len(set(entries))
assert entries.index('ADKP_RaidBossData.lua') < entries.index('ADKP_BossEncounters.lua') < entries.index('ADKP.lua') < entries.index('ADKP_Frame.xml')
for entry in entries:
    assert (root / 'ADKP' / entry).is_file(), entry
with tempfile.TemporaryDirectory(prefix='adkp-encounter-') as folder:
    folder = Path(folder)
    syntax = folder / 'syntax.lua'
    syntax.write_text('assert(string.find(_VERSION,"^Lua 5%.0")); for i=1,table.getn(arg) do assert(loadfile(arg[i])) end', encoding='utf-8')
    xml_scripts = []
    for entry in entries:
        if entry.endswith('.xml'):
            tree = ET.parse(root / 'ADKP' / entry)
            for scripts in tree.iter('{http://www.blizzard.com/wow/ui/}Scripts'):
                for script in scripts:
                    if script.text:
                        xml_scripts.append('function()\n' + script.text + '\nend')
    embedded = folder / 'xml_scripts.lua'
    embedded.write_text('local scripts = {\n' + ',\n'.join(xml_scripts) + '\n}', encoding='utf-8')
    subprocess.run([args.lua, str(syntax), str(embedded)] + [str(root / 'ADKP' / e) for e in entries if e.endswith('.lua')], cwd=root, check=True)
    print(f'Lua 5.0 / TOC / XML and {len(xml_scripts)} embedded handlers PASS', flush=True)
    subprocess.run([args.lua, str(root / 'tests/boss_encounter_spec.lua')], cwd=root, check=True)
