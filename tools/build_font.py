"""Subset OFL Noto Sans SC to characters used by the game. Requires fonttools."""
from pathlib import Path
import sys
from fontTools import subset
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont

root = Path(__file__).resolve().parents[1]
text = ''.join(p.read_text() for p in (root / 'scripts').rglob('*.gd'))
text += ''.join(chr(i) for i in range(32, 127))
font = TTFont(sys.argv[1])
font = instantiateVariableFont(font, {'wght': 650}, inplace=True)
options = subset.Options()
options.name_IDs = ['*']
subsetter = subset.Subsetter(options=options)
subsetter.populate(text=text)
subsetter.subset(font)
font.save(root / 'assets/fonts/game.ttf')
print('Saved assets/fonts/game.ttf')
