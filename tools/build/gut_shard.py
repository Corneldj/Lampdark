#!/usr/bin/env python3
"""FND-04: splits the GUT suite (tests/unit and tests/scenario) into balanced shards, so CI runs it
in parallel jobs rather than one long process.

Usage:
  gut_shard.py <i> <n> <out.json>       GUT's config for shard i of n (0-based): .gutconfig.json's
                                        settings with "tests" in place of "dirs"
  gut_shard.py --record <junit.xml>...  rewrites gut_timings.json from merged JUnit reports

Each file goes to the shard with the least time so far, the longest first, by its seconds in
gut_timings.json (a file it does not know counts 2 s). Every file lands in exactly one shard, and
the split depends only on the file list and the timings, so every runner computes the same one.
"""
import glob
import json
import os
import sys
import xml.etree.ElementTree as ET

GAME = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
TIMINGS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "gut_timings.json")
DEFAULT_S = 2.0


def test_files() -> list:
    return sorted(
        os.path.relpath(p, GAME).replace(os.sep, "/")
        for d in ("tests/unit", "tests/scenario")
        for p in glob.glob(os.path.join(GAME, d, "**", "test_*.gd"), recursive=True)
    )


def timings() -> dict:
    if not os.path.exists(TIMINGS):
        return {}
    with open(TIMINGS) as fh:
        return json.load(fh)


def shard(i: int, n: int) -> list:
    times = timings()
    files = test_files()
    load = [0.0] * n
    shards = [[] for _ in range(n)]
    # The longest first; ties by name, so the split is the same everywhere.
    for f in sorted(files, key=lambda f: (-times.get(f, DEFAULT_S), f)):
        k = load.index(min(load))
        shards[k].append(f)
        load[k] += times.get(f, DEFAULT_S)
    return sorted(shards[i])


def record(reports: list) -> None:
    times = {}
    for path in reports:
        for s in ET.parse(path).getroot().iter("testsuite"):
            name = s.get("name", "")
            if name.startswith("res://"):
                name = name[len("res://"):]
            times[name] = round(float(s.get("time", DEFAULT_S)), 1)
    known = set(test_files())
    with open(TIMINGS, "w") as fh:
        json.dump({k: times[k] for k in sorted(times) if k in known}, fh, indent="\t", sort_keys=True)
        fh.write("\n")


def main() -> None:
    if len(sys.argv) >= 3 and sys.argv[1] == "--record":
        record(sys.argv[2:])
        return
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    i, n, out = int(sys.argv[1]), int(sys.argv[2]), sys.argv[3]
    if n < 1 or i < 0 or i >= n:
        sys.exit("gut_shard.py: shard %d of %d" % (i, n))
    with open(os.path.join(GAME, ".gutconfig.json")) as fh:
        cfg = json.load(fh)
    cfg.pop("dirs", None)
    cfg.pop("include_subdirs", None)
    cfg["tests"] = ["res://" + f for f in shard(i, n)]
    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    with open(out, "w") as fh:
        json.dump(cfg, fh, indent="\t")
        fh.write("\n")
    print("gut shard %d of %d: %d files" % (i, n, len(cfg["tests"])))


if __name__ == "__main__":
    main()
