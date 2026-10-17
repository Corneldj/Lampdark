#!/usr/bin/env python3
"""GEN-16: the stub sets of the v1 biome cells (template_designs_v1.gd's WIDE_SETS and NARROW_SETS).

A cell's socket set has each edge shut (0.4) or open at offset 5, 10 or 15 (0.2 each): GEN-05's 0.6
edge-open rate, 256 sets. A template covers a set when it has a stub at every open position. GEN-05
chooses among the covering templates by weight, and the designs weigh a template 2^(4 - its stubs),
so the one with the fewest blind headings wins most often. The hub (all 12 stubs) weighs 0.01. A set
nothing covers counts its 12 - opened headings as blind (the fallback's).

Each step adds the design that most lowers a cell's expected blind headings, with the turns its biome
draws: a 3-wide biome's as authored and transposed (no other turn keeps a 3-wide stub on an offset),
the 2-wide Old Workings' in all eight orientations. Ties go to the design whose smallest mask is
smallest. The designs list each design by that mask.

Usage: python3 tools/templates/v1/stub_sets.py [--wide N] [--narrow N] [--check FILE]
Prints each biome kind's sets in the designs' notation ("N10 E5 ...") with the running expected blind
headings and the share of sets a non-hub template covers. With --check, fails unless FILE's
WIDE_SETS and NARROW_SETS are exactly these.
"""

import argparse
import itertools
import re
import sys

OFFSETS = (5, 10, 15)
EDGES = "NESW"
P_SHUT = 0.4
P_OPEN = 0.2
HUB = (1 << 12) - 1
HUB_WEIGHT = 0.01


def bit(edge: int, k: int) -> int:
    return 1 << (edge * 3 + k)


def stubs(mask: int) -> int:
    return bin(mask).count("1")


def weight(mask: int) -> float:
    return HUB_WEIGHT if mask == HUB else 2.0 ** (4 - stubs(mask))


def _map(mask: int, to) -> int:
    out = 0
    for e in range(4):
        for k in range(3):
            if mask & bit(e, k):
                ne, nk = to(e, k)
                out |= bit(ne, nk)
    return out


def rotate(mask: int) -> int:
    """A quarter turn clockwise: north to east (offset kept), east to south (reversed), and on."""
    return _map(mask, lambda e, k: ((e + 1) % 4, k if e in (0, 2) else 2 - k))


def mirror(mask: int) -> int:
    """East to west: north and south offsets reversed."""
    return _map(mask, lambda e, k: ({0: 0, 1: 3, 2: 2, 3: 1}[e], 2 - k if e in (0, 2) else k))


def transpose(mask: int) -> int:
    """(x, y) to (y, x): north and west swap, east and south, offsets kept."""
    return _map(mask, lambda e, k: ({0: 3, 3: 0, 1: 2, 2: 1}[e], k))


def orbit_wide(mask: int) -> list:
    return sorted({mask, transpose(mask)})


def orbit_narrow(mask: int) -> list:
    out = set()
    x = mask
    for _ in range(4):
        out.add(x)
        out.add(mirror(x))
        x = rotate(x)
    return sorted(out)


def socket_sets() -> list:
    """Every socket set: (open positions, probability, edges open)."""
    out = []
    for state in itertools.product((None, 0, 1, 2), repeat=4):
        mask, p, opened = 0, 1.0, 0
        for e, k in enumerate(state):
            if k is None:
                p *= P_SHUT
            else:
                mask |= bit(e, k)
                p *= P_OPEN
                opened += 1
        out.append((mask, p, opened))
    return out


def text(mask: int) -> str:
    return " ".join("%s%d" % (EDGES[e], OFFSETS[k]) for e in range(4) for k in range(3) if mask & bit(e, k))


def choose(n: int, orbit_of) -> list:
    """The first `n` designs, greedily: [(mask, expected blind headings, non-hub coverage)]."""
    sets = socket_sets()
    covering = {}
    for m in range(1, 1 << 12):
        covering[m] = [i for i, (s, _, _) in enumerate(sets) if s & ~m == 0]
    w = [0.0] * len(sets)
    b = [0.0] * len(sets)

    def add(m: int) -> None:
        for i in covering[m]:
            w[i] += weight(m)
            b[i] += weight(m) * (stubs(m) - sets[i][2])

    def f(wi: float, bi: float, i: int) -> float:
        return bi / wi if wi > 0 else 12 - sets[i][2]

    add(HUB)
    orbits = []
    seen = set()
    for m in range(1, 1 << 12):
        if m in seen or m == HUB:
            continue
        o = orbit_of(m)
        seen.update(o)
        if HUB not in o:
            orbits.append(o)
    covered = [False] * len(sets)
    chosen = []
    out = []
    for _ in range(n):
        best = None
        for o in orbits:
            if o[0] in chosen:
                continue
            delta = {}
            for m in o:
                for i in covering[m]:
                    dw, db = delta.get(i, (0.0, 0.0))
                    delta[i] = (dw + weight(m), db + weight(m) * (stubs(m) - sets[i][2]))
            gain = sum(sets[i][1] * (f(w[i] + dw, b[i] + db, i) - f(w[i], b[i], i)) for i, (dw, db) in delta.items())
            if best is None or gain < best[0]:
                best = (gain, o)
        chosen.append(best[1][0])
        for m in best[1]:
            add(m)
            for i in covering[m]:
                covered[i] = True
        expected = sum(p * f(w[i], b[i], i) for i, (_, p, _) in enumerate(sets))
        coverage = sum(p for i, (_, p, _) in enumerate(sets) if covered[i])
        out.append((best[1][0], expected, coverage))
    return out


def listed(source: str, name: str) -> list:
    """A const Array[String] of the designs script."""
    body = re.search(r"const %s: Array\[String\] = \[(.*?)\]" % name, source, re.S)
    return re.findall(r'"([^"]*)"', body.group(1)) if body else []


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--wide", type=int, default=26, help="3-wide biomes' designs (default 26)")
    ap.add_argument("--narrow", type=int, default=13, help="the Old Workings' designs (default 13)")
    ap.add_argument("--check", metavar="FILE", help="fail unless FILE's WIDE_SETS and NARROW_SETS match")
    args = ap.parse_args()
    results = {"WIDE_SETS": choose(args.wide, orbit_wide), "NARROW_SETS": choose(args.narrow, orbit_narrow)}
    for name, rows in results.items():
        print(name)
        for i, (m, e, c) in enumerate(rows):
            print("  %2d  %-28s blind %.3f  covered %.4f" % (i + 1, text(m), e, c))
    if args.check:
        source = open(args.check, encoding="utf-8").read()
        bad = [name for name, rows in results.items() if listed(source, name) != [text(m) for m, _, _ in rows]]
        for name in bad:
            print("stub_sets: %s's %s differs from the model's" % (args.check, name), file=sys.stderr)
        return 1 if bad else 0
    return 0


if __name__ == "__main__":
    sys.exit(main())
