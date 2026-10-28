"""Create a comment-free WoW 1.12 / Turtle WoW ADKP ZIP, keeping sources intact."""
import argparse
from pathlib import Path

from package_forever_classic import package as package_addon

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_ADDON = ROOT / 'ADKP'


def package(addon=DEFAULT_ADDON, output_dir=ROOT, now=None):
    return package_addon(addon, output_dir, now, archive_prefix='ADKP')


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
