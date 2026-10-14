"""QA-01: listener_ab_report pools testers and applies criterion 5's rule (facing-relative at 75% or
more and above screen-up, on headphones; speakers reported only)."""
import json
import os
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
import listener_ab_report as rep  # noqa: E402


def write(tester, facing_right, screen_right, a_is_facing=True, headphones=True, trials=20, screen_up_available=True):
    codes = {"A": "facing", "B": "screen_up"} if a_is_facing else {"A": "screen_up", "B": "facing"}
    code_of = {v: k for k, v in codes.items()}
    lines = [json.dumps({"tester": tester, "codes": codes, "headphones": headphones})]
    for cond, right in (("facing", facing_right), ("screen_up", screen_right)):
        for i in range(trials):
            lines.append(json.dumps({"code": code_of[cond], "correct": i < right, "screen_up_available": screen_up_available}))
    f = tempfile.NamedTemporaryFile("w", suffix=".jsonl", delete=False)
    f.write("\n".join(lines) + "\n")
    f.close()
    return f.name


class TestListenerAbReport(unittest.TestCase):
    def setUp(self):
        self.paths = []

    def tearDown(self):
        for p in self.paths:
            os.unlink(p)

    def files(self, *specs):
        self.paths += [write(*s[:3], **(s[3] if len(s) > 3 else {})) for s in specs]
        return self.paths[-len(specs):]

    def test_pass_and_blind_codes(self):
        paths = self.files(("T1", 17, 11), ("T2", 15, 10, {"a_is_facing": False}), ("T3", 16, 12))
        d = rep.decide([r for p in paths for r in rep.load(p)])
        self.assertEqual(d["headphones"]["facing"]["correct"], 48)
        self.assertTrue(d["pass"], "48/60 = 80% facing, above screen-up")
        self.assertEqual(rep.main(paths), 0)

    def test_below_threshold_or_not_better_fails(self):
        low = self.files(("T1", 14, 10), ("T2", 14, 10))
        self.assertEqual(rep.main(low), 1, "70%: below 75%")
        tie = self.files(("T3", 16, 16))
        self.assertEqual(rep.main(tie), 1, "80% but screen-up as good")

    def test_speakers_are_reported_not_decisive(self):
        paths = self.files(("T1", 16, 10), ("T2", 5, 15, {"headphones": False}))
        d = rep.decide([r for p in paths for r in rep.load(p)])
        self.assertTrue(d["pass"])
        self.assertEqual(d["speakers"]["facing"]["correct"], 5)
        self.assertEqual(d["testers"], 1)

    def test_no_screen_up_is_refused(self):
        paths = self.files(("T1", 16, 10, {"screen_up_available": False}))
        with self.assertRaises(ValueError):
            rep.load(paths[0])

    def test_no_data(self):
        f = tempfile.NamedTemporaryFile("w", suffix=".jsonl", delete=False)
        f.write(json.dumps({"tester": "T0", "codes": {"A": "facing", "B": "screen_up"}}) + "\n")
        f.close()
        self.paths.append(f.name)
        self.assertEqual(rep.main([f.name]), 2)


if __name__ == "__main__":
    unittest.main()
