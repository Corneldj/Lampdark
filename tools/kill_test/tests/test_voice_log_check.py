"""QA-01: voice_log_check against synthetic logs that pass and fail each bin, and against the exact
line format SND-08's voice_system.gd writes."""
import os
import random
import re
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
import voice_log_check as vlc  # noqa: E402

GAME = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))


def line(utterance, distance, rng, frames, sent, stythe=0.0, running=0.0, route="NORMAL", via="road", band=2):
    return (f"12:00:00 [INFO] server: voice loss: utterance {utterance} speaker 1 band {band} route {route} listener 2 via {via} "
            f"path {distance:.1f}/{rng:.1f} distance 0.00 stythe {stythe:.2f} running {running:.2f} p 0.00 frames {frames} sent {sent}")


def synthetic(skew=None, seed=7):
    """About 200 utterances over every bin, frames kept at §6.2's rate (Bernoulli per frame); `skew`
    lowers one bin's kept rate by 10 points."""
    rnd = random.Random(seed)
    out = []
    u = 0
    cases = [("clean", 3.0, 0, 0), ("edge 0-25%", 6.7, 0, 0), ("edge 25-50%", 8.2, 0, 0), ("edge 50-75%", 9.7, 0, 0),
             ("edge 75-100%", 11.2, 0, 0), ("stythe", 3.0, 0.25, 0), ("running", 3.0, 0, 0.2), ("stacked", 11.9, 0.25, 0.2)]
    for name, d, st, rn in cases:
        for _ in range(25):
            u += 1
            rec = {"route": "NORMAL", "distance": d, "range": 12.0, "stythe_loss": st, "running_loss": rn}
            kept = vlc.expected_kept(rec) - (0.10 if name == skew else 0.0)
            frames = 50
            sent = sum(1 for _ in range(frames) if rnd.random() < kept)
            out.append(line(u, d, 12.0, frames, sent, st, rn))
    for _ in range(6):
        u += 1
        out.append(line(u, 4.0, 12.0, 40, 0, route="CUT", via="-"))
    return out


class TestVoiceLogCheck(unittest.TestCase):
    def test_the_line_format_is_voice_systems(self):
        src = open(os.path.join(GAME, "server/systems/sound/voice_system.gd"), encoding="utf-8").read()
        fmt = re.search(r'Log\.info\(\("(voice loss: [^"]+)"\s*\+\s*"([^"]+)"\)', src)
        self.assertIsNotNone(fmt, "voice_system.gd still logs the loss line")
        written = (fmt.group(1) + fmt.group(2)) % (4, 1, 2, "NORMAL", 3, "road", 7.5, 12.0, 0.1, 0.0, 0.2, 0.28, 50, 36)
        recs = vlc.parse([written])
        self.assertEqual(len(recs), 1, written)
        self.assertEqual(recs[0]["frames"], 50)
        self.assertEqual(recs[0]["sent"], 36)
        self.assertAlmostEqual(recs[0]["range"], 12.0)

    def test_the_design_table(self):
        e = vlc.expected_kept
        self.assertAlmostEqual(e({"route": "NORMAL", "distance": 6.0, "range": 12.0, "stythe_loss": 0, "running_loss": 0}), 1.0)
        self.assertAlmostEqual(e({"route": "NORMAL", "distance": 12.0, "range": 12.0, "stythe_loss": 0, "running_loss": 0}), 0.6)
        self.assertAlmostEqual(e({"route": "NORMAL", "distance": 9.0, "range": 12.0, "stythe_loss": 0, "running_loss": 0}), 0.8)
        stacked = e({"route": "NORMAL", "distance": 12.0, "range": 12.0, "stythe_loss": 0.25, "running_loss": 0.2})
        self.assertAlmostEqual(stacked, 0.36, msg="'keeps about a third' (§6.2)")
        self.assertEqual(e({"route": "CUT", "distance": 1.0, "range": 12.0, "stythe_loss": 0, "running_loss": 0}), 0.0)

    def test_honest_logs_pass_every_bin(self):
        report = vlc.check(vlc.parse(synthetic()), run_length=1)
        self.assertTrue(report["enough"])
        for name, entry in report["bins"].items():
            self.assertTrue(entry["pass"], f"{name}: {entry}")
        self.assertTrue(report["pass"])

    def test_each_bin_fails_when_skewed(self):
        for name in ["clean", "edge 0-25%", "edge 25-50%", "edge 50-75%", "edge 75-100%", "stythe", "running", "stacked"]:
            report = vlc.check(vlc.parse(synthetic(skew=name)), run_length=1)
            self.assertFalse(report["pass"], name)
            self.assertFalse(report["bins"][name]["pass"], f"{name} is the failing bin")
            others = [n for n, e in report["bins"].items() if n != name and e["pass"] is False]
            self.assertEqual(others, [], f"skewing {name} fails only {name}")

    def test_a_cut_route_that_sends_fails(self):
        logs = synthetic()
        logs.append(line(999, 2.0, 12.0, 40, 12, route="CUT", via="-"))
        report = vlc.check(vlc.parse(logs), run_length=1)
        self.assertFalse(report["bins"]["cut"]["pass"])

    def test_too_few_utterances_is_incomplete(self):
        recs = vlc.parse(synthetic()[:30])
        self.assertFalse(vlc.check(recs, run_length=1)["enough"])

    def test_runs_of_losses_need_more_frames(self):
        # Losses in runs of 6.5 frames carry less information per frame: the same 1,250 frames are
        # too few to judge a 15% bin within 5 points, and enough when frames drop one by one.
        self.assertGreater(vlc.frames_needed(0.85, 6.5), 1250)
        self.assertLess(vlc.frames_needed(0.85, 1.0), 1250)
        self.assertAlmostEqual(vlc.mean_run_length(), 6.5, msg="SND-08's voice.loss_run_min/max_frames, 3 and 10")
        report = vlc.check(vlc.parse(synthetic()), run_length=6.5)
        self.assertIsNone(report["bins"]["edge 25-50%"]["pass"], "too few frames: no verdict")
        self.assertEqual(report["bins"]["clean"]["frames_needed"], 1, "a clean bin needs no sample to speak of")

    def test_utterances_count_across_runs(self):
        logs = synthetic()[:10] + synthetic()[:10]  # the numbering restarts: a second server run
        self.assertEqual(vlc.check(vlc.parse(logs), run_length=1)["utterances"], 20)

    def test_the_command_line(self):
        import tempfile
        with tempfile.NamedTemporaryFile("w", suffix=".log", delete=False) as f:
            f.write("\n".join(synthetic()) + "\n")
            path = f.name
        try:
            self.assertEqual(vlc.main(["--run-length", "1", path]), 0)
            with open(path, "w") as f:
                f.write("\n".join(synthetic(skew="running")) + "\n")
            self.assertEqual(vlc.main(["--run-length", "1", path]), 1)
            with open(path, "w") as f:
                f.write("\n".join(synthetic()[:20]) + "\n")
            self.assertEqual(vlc.main(["--run-length", "1", path]), 2)
        finally:
            os.unlink(path)


if __name__ == "__main__":
    unittest.main()
