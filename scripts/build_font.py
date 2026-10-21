#!/usr/bin/env python3
"""Rebuild the distributed OFL Japanese UI font from the game's current text."""
from pathlib import Path
from fontTools import subset
from fontTools.ttLib import TTFont

ROOT = Path(__file__).resolve().parents[1]
SOURCE = Path('/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc')
OUTPUT = ROOT / 'game/assets/NotoSansJP.ttf'


def main() -> None:
    if not SOURCE.is_file():
        raise SystemExit(f'Missing source font: {SOURCE}')
    characters = ''.join(path.read_text(encoding='utf-8') for path in (ROOT / 'game').rglob('*.gd'))
    # Keep Latin punctuation and digits for generated dynamic numbers and names.
    characters += ''.join(chr(code) for code in range(32, 127))
    font = TTFont(SOURCE, fontNumber=0)
    options = subset.Options()
    options.name_IDs = ['*']
    options.name_legacy = True
    options.name_languages = ['*']
    subsetter = subset.Subsetter(options=options)
    subsetter.populate(text=characters)
    subsetter.subset(font)
    font.flavor = None
    font.save(OUTPUT)
    print(f'{OUTPUT}: {OUTPUT.stat().st_size} bytes')


if __name__ == '__main__':
    main()
