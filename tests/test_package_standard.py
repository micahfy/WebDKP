"""Standard releases use original sources, a separate ZIP name and shared stripping."""
from datetime import datetime, timezone
from pathlib import Path
import os
import subprocess
import sys
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from package_standard import DEFAULT_ADDON, package
from strip_addon_comments import strip_comments


class StandardPackageTests(unittest.TestCase):
    def test_default_sources_and_actual_cli_archive(self):
        self.assertEqual(DEFAULT_ADDON, ROOT / 'ADKP')
        before = {p.relative_to(DEFAULT_ADDON): p.read_bytes()
                  for p in DEFAULT_ADDON.rglob('*') if p.is_file()}
        with tempfile.TemporaryDirectory() as folder:
            # Run outside the repository to match double-clicking the CMD.
            result = subprocess.run(
                [sys.executable, '-B', str(ROOT / 'tools/package_standard.py'), '--output-dir', folder],
                cwd=folder, capture_output=True, text=True, check=True,
                env=dict(os.environ, PYTHONDONTWRITEBYTECODE='1'))
            archives = list(Path(folder).glob('ADKP-*.zip'))
            self.assertEqual(len(archives), 1, result.stdout)
            with zipfile.ZipFile(archives[0]) as archive:
                self.assertEqual(set(archive.namelist()), {'ADKP/' + p.as_posix() for p in before})
                toc = archive.read('ADKP/ADKP.toc')
                self.assertIn(b'## Interface: 11200', toc)
                self.assertNotIn('Forever', archives[0].name)
                for path, data in before.items():
                    self.assertEqual(archive.read('ADKP/' + path.as_posix()), strip_comments(path, data))
        self.assertEqual(before, {p: (DEFAULT_ADDON / p).read_bytes() for p in before})

    def test_version_time_duplicates_and_source_protection(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            addon = root / 'ADKP'
            addon.mkdir()
            (addon / 'ADKP.toc').write_bytes(b'## Interface: 11200\n## Version: 1.99\nA.lua\n')
            code = 'local text="装备 -- 字符串" -- 移除注释\nreturn text'.encode('utf-8')
            (addon / 'A.lua').write_bytes(code)
            now = datetime(2026, 10, 27, 18, 3, 4, tzinfo=timezone.utc)
            archive, count, changed = package(addon, root / 'out', now)
            self.assertEqual(archive.name, 'ADKP-1.99-20261028-020304.zip')
            self.assertEqual((count, changed), (2, 1))
            second, _, _ = package(addon, root / 'out', now)
            self.assertNotEqual(archive, second)
            self.assertEqual((addon / 'A.lua').read_bytes(), code)
            with self.assertRaises(ValueError):
                package(addon, addon / 'out', now)
            (addon / 'ADKP.toc').write_bytes(b'## Version: 1.99\nMissing.lua\n')
            with self.assertRaisesRegex(ValueError, 'Missing manifest entry'):
                package(addon, root / 'out', now)
            self.assertEqual(len(list((root / 'out').glob('*.zip'))), 2)


if __name__ == '__main__':
    unittest.main()
