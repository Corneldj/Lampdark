"""QA-01 criterion 2: the kill test's voice-loss logs against Gameplay §6.2.

Usage: python3 tools/kill_test/voice_log_check.py [--json] [--min-utterances N] <server.log>...

Reads SND-08's dev and QA server log lines ("voice loss: utterance ... frames N sent M"), one per
utterance and listener, and compares the frames each listener was sent with §6.2's table:

- clean within half range;
- loss rising linearly from 0% to 40% between half range and the edge (binned by quarters);
- 25% while a Stythe's tell plays near the speaker or listener, 20% while the speaker runs or pants;
- losses stack (multiply);
- a cut route (a shut door or gate on the way) sends nothing: not one frame, whatever the count.

A bin passes when its frame-weighted delivered fraction is within +-5 percentage points of the
expected one. Frames drop in runs (SND-08's voice.loss_run_min/max_frames), so a bin is judged only
once it holds enough frames for that: 1.96^2 p(1-p) D / 0.05^2, with D the mean run length as the
design effect (about 2,200 frames at 33% loss); below that it reports "too few". The run passes when
every judged bin passes and there are at least --min-utterances utterances (SND-08 hands QA-01 a
50-utterance check). Utterance numbers restart with each server run; a drop in them starts a new run. A shut door's
listener is never routed and so never logged; GEN-03's test_m1_door covers that row.

The §6.2 numbers are the design's (the gate is the design's, not the current tuning's).
Exit codes: 0 pass, 1 a bin fails, 2 not enough data.
"""
import argparse
import json
import re
import sys

EDGE_LOSS = 0.40
STYTHE_LOSS = 0.25
RUNNING_LOSS = 0.20
TOLERANCE = 0.05
Z95 = 1.96

LINE = re.compile(
    r"voice loss: utterance (?P<utterance>\d+) speaker (?P<speaker>\d+) band (?P<band>\d+) route (?P<route>[A-Z_]+) "
    r"listener (?P<listener>\d+) via (?P<via>\S+) path (?P<distance>[\d.]+)/(?P<range>[\d.]+) "
    r"distance (?P<distance_loss>[\d.]+) stythe (?P<stythe_loss>[\d.]+) running (?P<running_loss>[\d.]+) "
    r"p (?P<p>[\d.]+) frames (?P<frames>\d+) sent (?P<sent>\d+)")

BINS = ["clean", "edge 0-25%", "edge 25-50%", "edge 50-75%", "edge 75-100%", "stythe", "running", "stacked", "cut"]


def parse(lines):
    out = []
    for line in lines:
        m = LINE.search(line)
        if not m:
            continue
        r = m.groupdict()
        rec = {k: r[k] for k in ("route", "via")}
        for k in ("utterance", "speaker", "band", "listener", "frames", "sent"):
            rec[k] = int(r[k])
        for k in ("distance", "range", "distance_loss", "stythe_loss", "running_loss", "p"):
            rec[k] = float(r[k])
        out.append(rec)
    return out


def expected_kept(rec):
    """§6.2's kept fraction for one line, from its distance, range and conditions."""
    if rec["route"] == "CUT":
        return 0.0
    half = rec["range"] / 2.0
    d = rec["distance"]
    distance_loss = 0.0 if d <= half or half <= 0 else min(1.0, (d - half) / half) * EDGE_LOSS
    kept = 1.0 - distance_loss
    if rec["stythe_loss"] > 0:
        kept *= 1.0 - STYTHE_LOSS
    if rec["running_loss"] > 0:
        kept *= 1.0 - RUNNING_LOSS
    return kept


def bin_of(rec):
    if rec["route"] == "CUT":
        return "cut"
    stythe = rec["stythe_loss"] > 0
    running = rec["running_loss"] > 0
    half = rec["range"] / 2.0
    edge = rec["distance"] > half and half > 0
    conditions = int(stythe) + int(running) + int(edge)
    if conditions > 1:
        return "stacked"
    if stythe:
        return "stythe"
    if running:
        return "running"
    if not edge:
        return "clean"
    quarter = min(3, int((rec["distance"] - half) / half * 4))
    return BINS[1 + quarter]


def mean_run_length(voice_json=None):
    """SND-08's mean loss run (frames), from the tuning when it can be read; 6.5 otherwise."""
    import os
    path = voice_json or os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))),
                                      "data", "tuning", "voice.json")
    try:
        with open(path, encoding="utf-8") as f:
            keys = json.load(f)["keys"]
        return (keys["voice.loss_run_min_frames"]["value"] + keys["voice.loss_run_max_frames"]["value"]) / 2.0
    except (OSError, KeyError, ValueError):
        return 6.5


def frames_needed(expected_kept, run_length):
    """Frames for a 95% interval of +-TOLERANCE when losses come in runs of `run_length`."""
    p = 1.0 - expected_kept
    return int(Z95 * Z95 * p * (1.0 - p) * max(1.0, run_length) / (TOLERANCE * TOLERANCE)) + 1


def check(records, min_utterances=50, min_bin=5, run_length=None):
    run_length = mean_run_length() if run_length is None else run_length
    bins = {name: {"lines": 0, "frames": 0, "sent": 0, "expected": 0.0} for name in BINS}
    utterances = set()
    run = 0
    last = 0
    for rec in records:
        if rec["utterance"] < last:
            run += 1  # numbering restarted: another server run
        last = rec["utterance"]
        if rec["frames"] <= 0:
            continue
        utterances.add((run, rec["utterance"]))
        b = bins[bin_of(rec)]
        b["lines"] += 1
        b["frames"] += rec["frames"]
        b["sent"] += rec["sent"]
        b["expected"] += rec["frames"] * expected_kept(rec)
    report = {"utterances": len(utterances), "bins": {}, "pass": True, "enough": len(utterances) >= min_utterances}
    for name in BINS:
        b = bins[name]
        entry = {"lines": b["lines"], "frames": b["frames"]}
        if b["frames"] > 0:
            entry["delivered"] = b["sent"] / b["frames"]
            entry["expected"] = b["expected"] / b["frames"]
            entry["difference"] = entry["delivered"] - entry["expected"]
            entry["frames_needed"] = frames_needed(entry["expected"], run_length)
        if name == "cut" and b["lines"] > 0:
            entry["pass"] = b["sent"] == 0  # nothing through a shut door or gate: no tolerance
            report["pass"] = report["pass"] and entry["pass"]
        elif b["lines"] >= min_bin and b["frames"] >= frames_needed(entry["expected"], run_length):
            entry["pass"] = abs(entry["difference"]) <= TOLERANCE + 1e-9
            report["pass"] = report["pass"] and entry["pass"]
        else:
            entry["pass"] = None  # too few lines to judge
        report["bins"][name] = entry
    return report


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("logs", nargs="+")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--min-utterances", type=int, default=50)
    ap.add_argument("--min-bin", type=int, default=5)
    ap.add_argument("--run-length", type=float, default=None,
                    help="mean loss run in frames (default: from data/tuning/voice.json, else 6.5)")
    a = ap.parse_args(argv)
    records = []
    for path in a.logs:
        with open(path, encoding="utf-8", errors="replace") as f:
            records.extend(parse(f))
        records.append({"utterance": -1, "frames": 0, "route": "", "sent": 0})  # a new file is a new run
    report = check(records, a.min_utterances, a.min_bin, a.run_length)
    if a.json:
        print(json.dumps(report, indent=2))
    else:
        print(f"{report['utterances']} utterances, {sum(1 for r in records if r['frames'] > 0)} listener lines")
        print(f"{'bin':<14}{'lines':>7}{'frames':>8}{'delivered':>11}{'expected':>10}{'diff':>8}  result")
        for name in BINS:
            e = report["bins"][name]
            if e["frames"] == 0:
                print(f"{name:<14}{0:>7}{0:>8}{'-':>11}{'-':>10}{'-':>8}  no data")
                continue
            verdict = (f"too few ({e['frames_needed']} frames needed)" if name != "cut" else "too few") if e["pass"] is None \
                else ("pass" if e["pass"] else "FAIL")
            print(f"{name:<14}{e['lines']:>7}{e['frames']:>8}{e['delivered']:>11.3f}{e['expected']:>10.3f}"
                  f"{e['difference'] * 100:>7.1f}pp  {verdict}")
        print("shut door or gate: never routed, never logged (GEN-03's test_m1_door)")
        if not report["enough"]:
            print(f"NOT ENOUGH DATA: {report['utterances']} utterances, {a.min_utterances} needed")
        print("PASS" if report["pass"] and report["enough"] else "FAIL" if not report["pass"] else "INCOMPLETE")
    if not report["pass"]:
        return 1
    return 0 if report["enough"] else 2


if __name__ == "__main__":
    sys.exit(main())
