#!/usr/bin/env python3
"""Check explicit opaque sRGB pairs; this is not a page accessibility audit."""
import argparse
import json
import math
import re
import sys
from pathlib import Path


def luminance(color):
    if not isinstance(color, str) or not re.fullmatch(r"#(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{6})", color):
        raise ValueError(f"Expected opaque #RGB or #RRGGBB: {color!r}")
    raw = color[1:]
    if len(raw) == 3:
        raw = ''.join(c * 2 for c in raw)
    channels = [int(raw[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    linear = [c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4 for c in channels]
    return sum(c * weight for c, weight in zip(linear, (0.2126, 0.7152, 0.0722)))


def contrast(foreground, background):
    a, b = sorted((luminance(foreground), luminance(background)))
    return (b + 0.05) / (a + 0.05)


def check(pairs):
    if not isinstance(pairs, list) or not pairs:
        raise ValueError('Provide a non-empty array of color pairs')
    results = []
    for i, pair in enumerate(pairs):
        if not isinstance(pair, dict):
            raise ValueError(f'Pair {i} must be an object')
        name = pair.get('name')
        minimum = pair.get('minimum')
        if not isinstance(name, str) or not name.strip():
            raise ValueError(f'Pair {i} needs a non-empty name')
        if isinstance(minimum, bool) or not isinstance(minimum, (int, float)) or not math.isfinite(minimum) or not 1 <= minimum <= 21:
            raise ValueError(f'{name}: minimum must be a finite number from 1 to 21')
        ratio = contrast(pair.get('foreground'), pair.get('background'))
        results.append((name, ratio, minimum, ratio >= minimum))
    return results


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('pairs', type=Path, help='JSON array of name, foreground, background, minimum')
    args = parser.parse_args()
    try:
        results = check(json.loads(args.pairs.read_text(encoding='utf-8')))
    except (OSError, ValueError) as error:
        print(f'ERROR: {error}', file=sys.stderr)
        return 2
    for name, ratio, minimum, passed in results:
        print(f'{"PASS" if passed else "FAIL"} {name}: {ratio:.4f}:1 (required {minimum}:1)')
    print(f'{sum(r[3] for r in results)}/{len(results)} pairs passed; explicit opaque colors only')
    return 0 if all(r[3] for r in results) else 1


if __name__ == '__main__':
    sys.exit(main())
