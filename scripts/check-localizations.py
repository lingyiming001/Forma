#!/usr/bin/env python3
"""Check both resource catalogs and literal localization calls."""
import json
import re
from pathlib import Path
root=Path(__file__).resolve().parents[1]
base=root/'Packages/FormaKit/Sources/FormaLocalization/Resources'
pattern=re.compile(r'("(?:[^"\\]|\\.)*")\s*=\s*("(?:[^"\\]|\\.)*")\s*;')
def read(locale):
    text=(base/f'{locale}.lproj/Localizable.strings').read_text()
    entries=[(json.loads(k),json.loads(v)) for k,v in pattern.findall(text)]
    assert len(entries)==len(dict(entries)),f'Duplicate keys: {locale}'
    assert all(v.strip() for _,v in entries),f'Empty translations: {locale}'
    return dict(entries)
zh,en=read('zh-Hans'),read('en')
assert zh.keys()==en.keys(),f'Catalog mismatch: {zh.keys() ^ en.keys()}'
missing=[]
for folder in [root/'App',root/'Packages/FormaKit/Sources']:
    for file in folder.rglob('*.swift'):
        for match in re.finditer(r'\btr\(("(?:[^"\\]|\\.)*")\)',file.read_text()):
            key=json.loads(match.group(1))
            if key and key not in en:missing.append((str(file.relative_to(root)),key))
assert not missing,f'Missing localization keys: {missing}'
print(f'Localization checks passed: {len(en)} keys in Chinese and English.')
