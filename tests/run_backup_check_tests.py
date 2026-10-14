"""Verify current CSV backup/login recovery using the native Lua 5.0 runtime."""
import argparse
from pathlib import Path
import subprocess
import tempfile
import xml.etree.ElementTree as ET

parser = argparse.ArgumentParser()
parser.add_argument('--lua', required=True)
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
toc = (root / 'ADKP/ADKP.toc').read_text(encoding='utf-8')
entries = [line.strip() for line in toc.splitlines() if line.strip() and not line.startswith('##')]
assert len(entries) == len(set(entries))
assert entries.index('ADKP_BackupCheck.lua') < entries.index('ADKP.lua') < entries.index('ADKP_Frame.xml')
for entry in entries:
    path = root / 'ADKP' / entry
    assert path.is_file(), path
    if path.suffix == '.xml':
        ET.parse(path)
with tempfile.TemporaryDirectory(prefix='adkp-backup-check-') as folder:
    syntax = Path(folder) / 'syntax.lua'
    syntax.write_text('assert(string.find(_VERSION,"^Lua 5%.0")); for i=1,table.getn(arg) do assert(loadfile(arg[i])) end; print("Lua 5.0 syntax / TOC dependencies / XML PASS")', encoding='utf-8')
    subprocess.run([args.lua, str(syntax)] + [str(root / 'ADKP' / entry) for entry in entries if entry.endswith('.lua')], cwd=root, check=True)
    subprocess.run([args.lua, str(root / 'tests/backup_check_spec.lua')], cwd=root, check=True)
