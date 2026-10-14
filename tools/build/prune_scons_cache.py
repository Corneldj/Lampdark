#!/usr/bin/env python3
"""FND-04: drops SCons cache entries one build never used.

Usage: prune_scons_cache.py <cache dir> <--cache-debug log>

SCons names each cache entry by its content signature and, with --cache-debug, logs the signature of
every entry it retrieves or pushes. Everything else in the cache belongs to older builds and would only
grow the CI cache (GitHub evicts above 10 GB a repository). If the log names too few entries to be a
whole build (the format changed, or the build stopped early), nothing is pruned.
"""
import os
import re
import sys

MIN_USED = int(os.environ.get("LB_PRUNE_MIN_USED", "200"))
SIGNATURE = re.compile(r"^[0-9a-f]{32,}$")


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__, file=sys.stderr)
        return 2
    cache, log = sys.argv[1], sys.argv[2]
    used = set()
    pattern = re.compile(r"(?:retrieving from|pushing to)\s+(\S+)\s*$")
    try:
        with open(log, encoding="utf-8", errors="replace") as f:
            for line in f:
                m = pattern.search(line)
                if m:
                    used.add(os.path.basename(m.group(1)))
    except OSError as e:
        print(f"prune_scons_cache: no log ({e}); nothing pruned")
        return 0
    entries = []
    for root, _dirs, files in os.walk(cache):
        for name in files:
            if SIGNATURE.match(name):  # entries only: never CACHEDIR.TAG or config
                entries.append(os.path.join(root, name))
    if len(used) < MIN_USED:
        print(f"prune_scons_cache: the log names {len(used)} entries (under {MIN_USED}); nothing pruned")
        return 0
    removed = 0
    freed = 0
    for path in entries:
        if os.path.basename(path) not in used:
            freed += os.path.getsize(path)
            os.remove(path)
            removed += 1
    kept = len(entries) - removed
    print(f"prune_scons_cache: kept {kept} entries this build used, removed {removed} ({freed / 1048576:.0f} MiB)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
