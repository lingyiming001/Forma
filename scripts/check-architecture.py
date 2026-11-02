#!/usr/bin/env python3
"""Validate direct module imports and protect the UI-free inner layers."""
import json
import re
import subprocess
from pathlib import Path

root = Path(__file__).resolve().parents[1]
manifest = json.loads(subprocess.check_output([
    'swift', 'package', '--package-path', str(root / 'Packages/FormaKit'), 'dump-package'
]))
targets = {item['name']: item for item in manifest['targets'] if item['type'] != 'test'}
graph = {}
for name, target in targets.items():
    dependencies = {next(iter(item.values()))[0] for item in target['dependencies']}
    graph[name] = dependencies
    for file in (root / 'Packages/FormaKit/Sources' / name).rglob('*.swift'):
        imports = set(re.findall(r'^import (\w+)', file.read_text(), re.MULTILINE))
        undeclared = (imports & targets.keys()) - dependencies - {name}
        assert not undeclared, f'{file}: undeclared direct imports {undeclared}'
        if name in {'FormaDomain', 'FormaGeometry', 'FormaApplication'}:
            forbidden = imports & {'AppKit', 'SwiftUI', 'CoreGraphics', 'FormaDocumentIO', 'FormaCanvasEngine'}
            assert not forbidden, f'{file}: inner-layer dependency violation {forbidden}'

def visit(name, path):
    assert name not in path, f'Circular dependency: {path + [name]}'
    for dep in graph[name]:
        if dep in graph:
            visit(dep, path + [name])

for name in graph:
    visit(name, [])
print(f'Architecture checks passed: {len(targets)} library targets, acyclic direct dependencies.')
