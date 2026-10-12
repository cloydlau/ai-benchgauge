"""Subset the pinned Slide Xiaxing font for the Chinese brand; requires fontTools."""
from pathlib import Path
import hashlib
import sys
from fontTools import subset
from fontTools.ttLib import TTFont

source = Path(sys.argv[1])
assert hashlib.sha256(source.read_bytes()).hexdigest() == 'fac1f0ec044b63aa45c0775c17a2f03cbf6427b4bd7b93da87dde9e7e2020cfc', 'Unexpected Slide Xiaxing source version'
font = TTFont(source, recalcTimestamp=False)
assert all(ord(c) in font.getBestCmap() for c in '天梯')
options = subset.Options()
options.name_IDs = ['*']
options.name_languages = ['*']
options.name_legacy = True
options.notdef_outline = True
options.recommended_glyphs = True
subsetter = subset.Subsetter(options=options)
subsetter.populate(text=' 天梯')
subsetter.subset(font)
names = {1: 'BenchGauge Calligraphy', 3: 'BenchGaugeCalligraphy-Regular;SlideXiaxing1.000;subset', 4: 'BenchGauge Calligraphy Regular', 6: 'BenchGaugeCalligraphy-Regular', 16: 'BenchGauge Calligraphy'}
for record in font['name'].names:
    if record.nameID in names:
        record.string = names[record.nameID].encode(record.getEncoding())
target = Path(__file__).resolve().parent.parent / 'Sources/LeaderboardKit/Resources/Fonts/BenchGaugeCalligraphy.ttf'
font.save(target)
assert all(ord(c) in TTFont(target).getBestCmap() for c in '天梯')
print(f'Wrote Chinese brand font: {target.stat().st_size} bytes')
