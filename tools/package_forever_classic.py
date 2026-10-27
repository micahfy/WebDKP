"""Create a comment-free Forever release ZIP without modifying source files."""
import argparse
from datetime import datetime, timedelta, timezone
from pathlib import Path
import re
import tempfile
import zipfile

from strip_addon_comments import strip_comments

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_ADDON = ROOT / 'ADKP_Forever_Classic' / 'ADKP'
BEIJING = timezone(timedelta(hours=8), 'Asia/Shanghai')


def package(addon=DEFAULT_ADDON, output_dir=ROOT, now=None):
    addon, output_dir = Path(addon).resolve(), Path(output_dir).resolve()
    if output_dir == addon or addon in output_dir.parents:
        raise ValueError('Output directory must be outside the addon source')
    toc = (addon / 'ADKP.toc').read_text(encoding='utf-8-sig')
    version_match = re.search(r'^## Version:[ \t]*([^\r\n]+)', toc, re.MULTILINE)
    if not version_match:
        raise ValueError('ADKP.toc has no Version metadata')
    version = version_match[1].strip()
    if not re.fullmatch(r'[A-Za-z0-9._-]+', version):
        raise ValueError('Version contains characters unsuitable for a ZIP filename')
    for entry in toc.splitlines():
        entry = entry.strip()
        if entry and not entry.startswith('#') and not (addon / entry).is_file():
            raise ValueError(f'Missing manifest entry: {entry}')

    timestamp = (now or datetime.now(BEIJING)).astimezone(BEIJING).strftime('%Y%m%d-%H%M%S')
    output_dir.mkdir(parents=True, exist_ok=True)
    stem = f'ADKP_Forever_Classic-{version}-{timestamp}'
    archive, counter = output_dir / (stem + '.zip'), 2
    while archive.exists():
        archive = output_dir / f'{stem}-{counter}.zip'
        counter += 1
    files = sorted(path for path in addon.rglob('*') if path.is_file())
    changed = 0
    with tempfile.TemporaryDirectory(prefix='adkp-release-') as temporary:
        staged = Path(temporary) / 'ADKP'
        for path in files:
            original = path.read_bytes()
            try:
                cleaned = strip_comments(path, original)
            except Exception as error:
                raise ValueError(f'{path.relative_to(addon)}: {error}') from error
            target = staged / path.relative_to(addon)
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(cleaned)
            changed += cleaned != original
        created = False
        try:
            with zipfile.ZipFile(archive, 'x', compression=zipfile.ZIP_DEFLATED) as output:
                created = True
                for path in files:
                    target = staged / path.relative_to(addon)
                    output.write(target, 'ADKP/' + path.relative_to(addon).as_posix())
            with zipfile.ZipFile(archive) as output:
                if output.testzip() is not None or len(output.namelist()) != len(files):
                    raise ValueError('Archive integrity check failed')
                for path in files:
                    name = 'ADKP/' + path.relative_to(addon).as_posix()
                    if output.read(name) != (staged / path.relative_to(addon)).read_bytes():
                        raise ValueError(f'Archive content mismatch: {name}')
        except Exception:
            if created and archive.is_file():
                archive.unlink()  # Only the exact new archive from this run.
            raise
    return archive, len(files), changed


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output-dir', type=Path, default=ROOT, help='ZIP destination (default: repository root)')
    args = parser.parse_args()
    try:
        archive, count, changed = package(output_dir=args.output_dir)
    except Exception as error:
        parser.exit(1, f'Packaging failed: {error}\n')
    print(f'{archive}\n{count} files; comments removed from {changed} files. Source files unchanged.\nTimestamp timezone: Asia/Shanghai (UTC+8).')


if __name__ == '__main__':
    main()
