"""Source statistics by category: physical lines and effective lines (non-blank, not comment-only).

    python -B scripts/stats.py          # markdown table
    python -B scripts/stats.py --json   # machine-readable
"""
import json
import sys
from pathlib import Path

root = Path(__file__).resolve().parents[1]
CATEGORIES = [
    ('MoonBit production source', lambda p: p.suffix == '.mbt' and not p.name.endswith(('_test.mbt', '_wbtest.mbt')) and p.name != 'pkg.generated.mbti'),
    ('MoonBit tests (hand-written)', lambda p: p.name.endswith(('_test.mbt', '_wbtest.mbt')) and p.name != 'fixtures_wbtest.mbt'),
    ('MoonBit tests (generated from fixtures)', lambda p: p.name == 'fixtures_wbtest.mbt'),
    ('Host adapters, oracles and tooling', lambda p: p.parts[0] == 'scripts'),
    ('Fixtures and scenario inputs', lambda p: p.parts[0] in ('tests', 'examples')),
    ('Documentation', lambda p: p.suffix == '.md'),
    ('Build and CI configuration', lambda p: p.name in ('moon.mod', 'moon.pkg') or p.parts[0] == '.github'),
]
COMMENT = ('//', '#', '--')


def files():
    for path in sorted(root.rglob('*')):
        rel = path.relative_to(root)
        if path.is_file() and not any(part.startswith('.') and part != '.github' for part in rel.parts) \
                and rel.parts[0] not in ('_build', 'target', '.mooncakes') and rel.name != 'LICENSE':
            yield rel


def count(rel):
    lines = (root / rel).read_text(encoding='utf-8').splitlines()
    effective = sum(1 for line in lines if line.strip() and not line.strip().startswith(COMMENT))
    return len(lines), effective


def main():
    rows = []
    remaining = list(files())
    for title, match in CATEGORIES:
        matched = [rel for rel in remaining if match(rel)]
        remaining = [rel for rel in remaining if rel not in matched]
        physical = effective = 0
        for rel in matched:
            p, e = count(rel)
            physical += p
            effective += e
        rows.append({'category': title, 'files': len(matched), 'lines': physical, 'effective': effective})
    if '--json' in sys.argv:
        print(json.dumps(rows, indent=2))
        return
    print('| Category | Files | Lines | Effective lines |')
    print('| --- | ---: | ---: | ---: |')
    for row in rows:
        print('| %s | %d | %d | %d |' % (row['category'], row['files'], row['lines'], row['effective']))
    print()
    print('Effective lines exclude blank and comment-only lines. Counted from a clean checkout; generated files are listed separately.')


if __name__ == '__main__':
    main()
