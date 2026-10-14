"""Standalone Lua 5.0 regression and addon manifest checks."""
import argparse
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET

parser = argparse.ArgumentParser()
parser.add_argument('--lua', help='Path to a Lua 5.0 interpreter')
args = parser.parse_args()
interpreter = args.lua or shutil.which('lua5.0') or shutil.which('lua50')
if not interpreter:
    parser.error('Lua 5.0 is required; specify --lua PATH')
root = Path(__file__).resolve().parents[1]
toc = (root / 'ADKP/ADKP.toc').read_text(encoding='utf-8-sig').splitlines()
entries = [line.strip() for line in toc if line.strip() and not line.startswith('##')]
assert len(entries) == len(set(entries)), 'Duplicate TOC entry'
assert 'ADKP_SyncStore' in next(line for line in toc if line.startswith('## SavedVariables:'))
assert 'ADKP_BackupStore' in next(line for line in toc if line.startswith('## SavedVariables:'))
for entry in entries:
    assert (root / 'ADKP' / entry).is_file(), entry
    if entry.endswith('.xml'):
        ET.parse(root / 'ADKP' / entry)
assert entries.index('ADKP_SyncCodec.lua') < entries.index('ADKP_SyncData.lua') < entries.index('ADKP.lua')
assert entries.index('ADKP_DataSync.lua') > entries.index('ADKP_ShareGroups.lua')
assert entries.index('ADKP_ShareGroups.lua') < entries.index('ADKP_Backup.lua') < entries.index('ADKP_DataSync.lua')
with tempfile.TemporaryDirectory(prefix='adkp-sync-') as directory:
    syntax = Path(directory) / 'syntax.lua'
    syntax.write_text('assert(string.find(_VERSION, "^Lua 5%.0"), "use Lua 5.0"); for i=1,table.getn(arg) do local f,e=loadfile(arg[i]); assert(f,e) end; print("All addon Lua syntax PASS")\n', encoding='utf-8')
    files = [str(root / 'ADKP' / entry) for entry in entries if entry.endswith('.lua')]
    subprocess.run([interpreter, str(syntax)] + files + [str(root / 'tests/sync_spec.lua')], cwd=root, check=True)
subprocess.run([interpreter, 'tests/sync_spec.lua'], cwd=root, check=True)
subprocess.run([sys.executable, 'tests/run_backup_tests.py', '--lua', interpreter], cwd=root, check=True)
print('TOC load order and XML parsing PASS')
