"""Run the real addon backup paths against the shared Lua 5.0 game fixture."""
import argparse
from pathlib import Path
import subprocess
import tempfile
parser = argparse.ArgumentParser()
parser.add_argument('--lua', required=True)
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
fixture = (root / 'tests/sync_spec.lua').read_text(encoding='utf-8')
fixture = fixture[:fixture.index('local A, B = client(')]
with tempfile.TemporaryDirectory(prefix='adkp-backup-tests-') as folder:
    path = Path(folder) / 'backup.lua'
    path.write_text(fixture + (root / 'tests/backup_spec.lua').read_text(encoding='utf-8'), encoding='utf-8')
    subprocess.run([args.lua, str(path)], cwd=root, check=True)
