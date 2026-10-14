"""QA-01 criterion 5: pools the A/B harness's result files (one per tester) and decides.

Usage: python3 tools/kill_test/listener_ab_report.py [--json] <results.jsonl>...

Each file's first line names what A and B meant for that tester; the rest are answers. Headphone
sessions decide (the Proposed rule); speaker sessions are reported for information. Passes when the
facing-relative listener is right 75% of the time or more and beats screen-up. A file whose
screen-up was unavailable (a release build) is refused. Exit codes: 0 pass, 1 fail, 2 no data.
"""
import argparse
import json
import sys

THRESHOLD = 0.75


def load(path):
    with open(path, encoding="utf-8") as f:
        lines = [json.loads(line) for line in f if line.strip()]
    head, answers = lines[0], lines[1:]
    codes = head["codes"]
    out = []
    for a in answers:
        if not a.get("screen_up_available", True):
            raise ValueError(f"{path}: screen-up was unavailable (a release build?)")
        out.append({"tester": head["tester"], "headphones": head.get("headphones", True),
                    "condition": codes[a["code"]], "correct": bool(a["correct"])})
    return out


def tally(rows):
    t = {}
    for r in rows:
        c = t.setdefault(r["condition"], [0, 0])
        c[0] += int(r["correct"])
        c[1] += 1
    return {k: {"correct": v[0], "trials": v[1], "rate": v[0] / v[1] if v[1] else 0.0} for k, v in t.items()}


def decide(rows):
    phones = tally([r for r in rows if r["headphones"]])
    speakers = tally([r for r in rows if not r["headphones"]])
    f = phones.get("facing", {"rate": 0.0, "trials": 0})
    s = phones.get("screen_up", {"rate": 0.0, "trials": 0})
    passed = f["trials"] > 0 and f["rate"] >= THRESHOLD and f["rate"] > s["rate"]
    return {"testers": len({r["tester"] for r in rows if r["headphones"]}), "headphones": phones, "speakers": speakers,
            "pass": passed, "data": f["trials"] > 0}


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("results", nargs="+")
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args(argv)
    rows = []
    for path in a.results:
        rows.extend(load(path))
    d = decide(rows)
    if a.json:
        print(json.dumps(d, indent=2))
    else:
        print(f"{d['testers']} testers on headphones")
        for kind in ("headphones", "speakers"):
            for cond, v in sorted(d[kind].items()):
                print(f"  {kind:<10} {cond:<9} {v['correct']}/{v['trials']} = {v['rate'] * 100:.1f}%")
        print("PASS" if d["pass"] else ("FAIL" if d["data"] else "NO DATA"),
              f"(facing-relative must reach {THRESHOLD * 100:.0f}% and beat screen-up, on headphones)")
    if not d["data"]:
        return 2
    return 0 if d["pass"] else 1


if __name__ == "__main__":
    sys.exit(main())
